--[[ AUTO AIM v3 · Blue Lock: Rivals
     · Detección de portería con exclusión de red y desambiguación por boca del arco
     · Modo APRENDER + scorer de remotos (click-to-shot + args vectoriales)
     · Hook __namecall con reescritura recursiva de args y stop() que restaura todo
     · GUI colapsable con sliders, dump de remotos y hotkey ]]

--==========================================================================
-- 1. SERVICIOS / GUARD
--==========================================================================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Workspace  = game:GetService("Workspace")
local Tween      = game:GetService("TweenService")
local LP         = Players.LocalPlayer

if getgenv().AutoAim and getgenv().AutoAim.stop then
    pcall(getgenv().AutoAim.stop)
end

--==========================================================================
-- 2. CONFIG
--==========================================================================
local Cfg = {
    Enabled = true, Hotkey = Enum.KeyCode.RightShift,

    MinDistance = 12, MaxDistance = 120,
    SliderMin = 20, SliderMax = 220,
    RequireFacing = true, FacingDot = 0.15,

    GoalNames = { "goal", "goals", "goalpost", "goalposts", "goalnet", "net",
                  "rim", "arco", "porteria", "portería", "target", "gate" },
    PartialMatch = true,
    FramePartNames = { "post", "posts", "crossbar", "bar", "frame", "goalpost",
                       "goalposts", "travesa" },
    NetNames = { "net", "red", "malla", "mesh", "fabric" },

    BallNames = { "Football", "Ball", "SoccerBall", "Soccer Ball", "Soccerball", "football" },
    PossessionDistance = 14,
    OwnerKeys = { "Owner", "Possessor", "Holder", "BallOwner", "PlayerOwner" },

    -- remote de tiro
    RemoteNames = { Shoot=true, shoot_event=true, Shot=true, Kick=true,
                    KickEvent=true, ShootEvent=true, BallKick=true, ShootBall=true },
    RemotePatterns = { "shoot", "shot", "kick", "strike", "remate", "chute", "tirar" },
    ConfirmedRemote = nil,
    ArgMode = "auto",       -- auto | direction | position
    ArgIndex = nil,         -- nil = todos los args
    AimStrength = 1,
    ShotWindow = 0.40,

    Targets = {
        { name = "Escuadra izq", u = -0.40, v = 0.88, weight = 1.2 },
        { name = "Escuadra der", u =  0.40, v = 0.88, weight = 1.2 },
        { name = "Abajo izq",    u = -0.38, v = 0.12, weight = 1.0 },
        { name = "Abajo der",    u =  0.38, v = 0.12, weight = 1.0 },
        { name = "Centro",       u =  0.00, v = 0.50, weight = 0.7 },
    },
    Jitter = 0.05, Margin = 0.06, DepthFactor = 0,

    InputFallback = true,
    ShootInputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
    Learn = false, Debug = false, ShowGui = true,
}

--==========================================================================
-- 3. ESTADO
--==========================================================================
local State = {
    ready=false, status="Iniciando", root=nil, ball=nil,
    goal=nil, frame=nil, preset=nil, shotPoint=nil, shotAt=0, shotName=nil,
}
local goals, boundsCache = {}, {}
local learnStats, learnLog = {}, {}
local lastPreset, lastShootInput = nil, -1e9
local conns, rng = {}, Random.new(tick()*1000)
local running, hooked, oldNamecall = true, false, nil
local gui, statusLabel, toggleBtn, learnBtn, remoteLabel
local lastScan = 0

local function track(c) conns[#conns+1] = c; return c end
local function say(t, col) State.status = t; if Cfg.Debug then print("[AutoAim] "..t) end end

--==========================================================================
-- 4. PORTERÍA
--==========================================================================
local function nameMatches(n)
    n = string.lower(n)
    for _, k in ipairs(Cfg.GoalNames) do
        if n == k or (Cfg.PartialMatch and string.find(n, k, 1, true)) then return true end
    end
    return false
end

local function considerGoal(inst)
    if goals[inst] then return end
    if not (inst:IsA("BasePart") or inst:IsA("Model")) then return end
    if not nameMatches(inst.Name) then return end
    local p = inst.Parent
    while p and p ~= Workspace do
        if goals[p] then return end
        p = p.Parent
    end
    for g in pairs(goals) do
        if g:IsDescendantOf(inst) then goals[g] = nil; boundsCache[g] = nil end
    end
    goals[inst] = true
end

local function scanGoals()
    local ok, list = pcall(Workspace.GetDescendants, Workspace)
    if not ok then return end
    for g in pairs(goals) do
        if not g.Parent then goals[g] = nil; boundsCache[g] = nil end
    end
    for _, d in ipairs(list) do pcall(considerGoal, d) end
end

local function isNet(part)
    local n = string.lower(part.Name)
    for _, k in ipairs(Cfg.NetNames) do
        if string.find(n, k, 1, true) then return true end
    end
    return false
end

local function boundsOf(inst)
    local c = boundsCache[inst]
    if c and tick() - c.t < 1 then return c.cf, c.size end

    local cf, size
    if inst:IsA("BasePart") then
        cf, size = inst.CFrame, inst.Size
    else
        local fparts = {}
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") and not isNet(d) then
                local n = string.lower(d.Name)
                for _, k in ipairs(Cfg.FramePartNames) do
                    if string.find(n, k, 1, true) then fparts[#fparts+1] = d; break end
                end
            end
        end
        if #fparts >= 2 then
            local min = Vector3.new(math.huge, math.huge, math.huge)
            local max = -min
            for _, d in ipairs(fparts) do
                local dcf, dsz = d.CFrame, d.Size
                for _, sx in ipairs({-0.5, 0.5}) do
                    for _, sy in ipairs({-0.5, 0.5}) do
                        for _, sz in ipairs({-0.5, 0.5}) do
                            local w = (dcf * CFrame.new(sx*dsz.X, sy*dsz.Y, sz*dsz.Z)).Position
                            min = Vector3.new(math.min(min.X,w.X), math.min(min.Y,w.Y), math.min(min.Z,w.Z))
                            max = Vector3.new(math.max(max.X,w.X), math.max(max.Y,w.Y), math.max(max.Z,w.Z))
                        end
                    end
                end
            end
            local pivot = inst:GetPivot()
            size = max - min
            cf = CFrame.new((min + max) * 0.5) * (pivot - pivot.Position)
        else
            local ok, rcf, rsz = pcall(function() return inst:GetBoundingBox() end)
            if not ok then return end
            cf, size = rcf, rsz
        end
    end
    if size.X < 1 or size.Y < 1 then return end
    boundsCache[inst] = { t=tick(), cf=cf, size=size }
    return cf, size
end

local function flatUnit(v, fb)
    local f = Vector3.new(v.X, 0, v.Z)
    if f.Magnitude < 0.01 then return fb end
    return f.Unit
end

local function frameOf(cf, size)
    local right = flatUnit(cf.RightVector, Vector3.new(1,0,0))
    local look  = flatUnit(cf.LookVector,  Vector3.new(0,0,-1))
    if size.X >= size.Z then
        return { center=cf.Position, w=right, d=look, width=size.X, depth=size.Z, height=size.Y }
    end
    return { center=cf.Position, w=look, d=right, width=size.Z, depth=size.X, height=size.Y }
end

-- Elige el arco cuya BOCA encaras (no sólo "el que miras")
local function pickGoal(pos, lookVec)
    local best, bestScore
    for inst in pairs(goals) do
        if inst.Parent then
            local cf, size = boundsOf(inst)
            if cf and size then
                local flat = Vector3.new(cf.Position.X-pos.X, 0, cf.Position.Z-pos.Z)
                local dist = flat.Magnitude
                if dist >= Cfg.MinDistance and dist <= Cfg.MaxDistance and dist > 0.01 then
                    local dir = flat.Unit
                    local facing = lookVec:Dot(dir)
                    if not Cfg.RequireFacing or facing >= Cfg.FacingDot then
                        local frame = frameOf(cf, size)
                        -- penaliza si lo abordas de lado
                        local side = math.abs(dir:Dot(frame.w))
                        local score = facing - side*0.55 - dist/2000
                        if frame.width >= 3 and (not bestScore or score > bestScore) then
                            best  = { inst=inst, cf=cf, size=size, dist=dist }
                            bestScore = score
                        end
                    end
                end
            end
        end
    end
    return best
end

--==========================================================================
-- 5. PUNTO OBJETIVO
--==========================================================================
local function rollPreset()
    local total = 0
    for _, t in ipairs(Cfg.Targets) do
        if t ~= lastPreset then total = total + t.weight end
    end
    if total <= 0 then lastPreset = Cfg.Targets[1]; return lastPreset end
    local r = rng:NextNumber() * total
    for _, t in ipairs(Cfg.Targets) do
        if t ~= lastPreset then
            r = r - t.weight
            if r <= 0 then lastPreset = t; return t end
        end
    end
    lastPreset = Cfg.Targets[1]
    return lastPreset
end

local function targetPoint(frame, preset, shooterPos)
    local toGoal = Vector3.new(frame.center.X - shooterPos.X, 0, frame.center.Z - shooterPos.Z)
    local fwd = toGoal.Magnitude > 0.01 and toGoal.Unit or frame.d
    local right = fwd:Cross(Vector3.yAxis)
    local w, d = frame.w, frame.d
    if w:Dot(right) < 0 then w = -w end
    if d:Dot(fwd)   < 0 then d = -d  end
    local m = Cfg.Margin
    local u = math.clamp(preset.u + (rng:NextNumber()-0.5)*2*Cfg.Jitter, -0.5+m, 0.5-m)
    local v = math.clamp(preset.v + (rng:NextNumber()-0.5)*2*Cfg.Jitter, m, 1-m)
    return frame.center
        + w * (u * frame.width)
        + Vector3.yAxis * ((v-0.5) * frame.height)
        + d * (frame.depth * Cfg.DepthFactor)
end

local function takeShotPoint()
    local now = tick()
    if State.shotPoint and now - State.shotAt < Cfg.ShotWindow then return State.shotPoint end
    if not (State.frame and State.root) then return nil end
    local preset = State.preset or rollPreset()
    State.shotPoint = targetPoint(State.frame, preset, State.root.Position)
    State.shotName  = preset.name
    State.shotAt    = now
    State.preset    = nil
    return State.shotPoint
end

--==========================================================================
-- 6. BALÓN / POSESIÓN
--==========================================================================
local function getBall()
    if State.ball and State.ball.Parent then return State.ball end
    State.ball = nil
    for _, n in ipairs(Cfg.BallNames) do
        local f = Workspace:FindFirstChild(n, true)
        if f then
            local part = f:IsA("BasePart") and f
                or f:FindFirstChild("Hitbox")
                or f:FindFirstChild("BALL")
                or f:FindFirstChildWhichIsA("BasePart", true)
            if part then State.ball = part; return part end
        end
    end
end

local function ownerMatches(v)
    return v == LP or v == LP.Name or v == LP.UserId or v == LP.Character
end

local function hasBall(root, ball)
    for _, key in ipairs(Cfg.OwnerKeys) do
        local a = ball:GetAttribute(key)
        if a ~= nil then return ownerMatches(a) end
        local h = ball:FindFirstChild(key)
        if h and h:IsA("ValueBase") then return ownerMatches(h.Value) end
    end
    return (ball.Position - root.Position).Magnitude <= Cfg.PossessionDistance
end

--==========================================================================
-- 7. APRENDER / DETECCIÓN DE REMOTE
--==========================================================================
local function isShootRemote(name)
    if Cfg.ConfirmedRemote and name == Cfg.ConfirmedRemote then return true end
    if Cfg.RemoteNames[name] then return true end
    local lower = string.lower(name)
    for _, p in ipairs(Cfg.RemotePatterns) do
        if string.find(lower, p, 1, true) then return true end
    end
    return false
end

local function logRemote(inst, args)
    local stat = learnStats[inst.Name]
    if not stat then stat = { count=0, afterClick=0, vec=false }; learnStats[inst.Name] = stat end
    stat.count = stat.count + 1
    if tick() - lastShootInput < 0.25 then stat.afterClick = stat.afterClick + 1 end

    local parts = {}
    for i = 1, args.n do
        local v, t = args[i], typeof(args[i])
        if t == "Vector3" or t == "CFrame" then stat.vec = true end
        if t == "Instance" then parts[i] = i..":Inst("..v:GetFullName()..")"
        elseif t == "table" then
            local ks = {}
            for k, val in pairs(v) do ks[#ks+1] = tostring(k).."="..typeof(val) end
            parts[i] = i..":{"..table.concat(ks, ",").."}"
        else parts[i] = i..":"..t.."="..tostring(v):sub(1, 50) end
    end
    if #learnLog < 300 then
        learnLog[#learnLog+1] = inst:GetFullName().."  |  "..table.concat(parts, " | ")
    end
end

local function scoreOf(s)
    return s.afterClick * 3 + (s.vec and 2 or 0) + math.min(s.count, 10) * 0.1
end

local function bestCandidate()
    local best, bestScore = nil, 0
    for name, s in pairs(learnStats) do
        local sc = scoreOf(s)
        if sc > bestScore then best, bestScore = name, sc end
    end
    return best, bestScore
end

--==========================================================================
-- 8. REESCRITURA DE ARGS
--==========================================================================
local function blend(a, b) return a:Lerp(b, Cfg.AimStrength) end

local function rewriteValue(v, origin, point)
    local t = typeof(v)
    if t == "Vector3" then
        local mag = v.Magnitude
        local asDir = Cfg.ArgMode == "direction" or (Cfg.ArgMode == "auto" and mag > 0.5 and mag <= 1.5)
        local asPos = Cfg.ArgMode == "position"  or (Cfg.ArgMode == "auto" and mag > 1.5)
        if asDir then
            local d = point - origin
            if d.Magnitude < 0.5 then return nil end
            return blend(v, d.Unit).Unit
        elseif asPos then
            if (v - origin).Magnitude < 8 then return nil end
            return blend(v, point)
        end
    elseif t == "CFrame" then
        local d = point - origin
        if d.Magnitude < 0.5 then return nil end
        return v:Lerp(CFrame.lookAt(v.Position, v.Position + d), Cfg.AimStrength)
    end
    return nil
end

local function rewriteArgs(remote, args)
    local point = takeShotPoint()
    if not point then return nil end
    local origin = (State.ball and State.ball.Position) or State.root.Position
    local out, changed = { n = args.n }, false

    local function visit(node, depth)
        if typeof(node) == "table" then
            if depth > 3 then return node end
            local copy = {}
            for k, v in pairs(node) do copy[k] = visit(v, depth+1) end
            return copy
        end
        local r = rewriteValue(node, origin, point)
        if r ~= nil then changed = true; return r end
        return node
    end

    for i = 1, args.n do
        if Cfg.ArgIndex == nil or Cfg.ArgIndex == i then
            out[i] = visit(args[i], 0)
        else
            out[i] = args[i]
        end
    end

    if changed and Cfg.Debug then
        print(("[AutoAim] %s -> %s"):format(remote.Name, State.shotName or "?"))
    end
    return changed and out or nil
end

--==========================================================================
-- 9. HOOK
--==========================================================================
local function handler(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        if typeof(self) ~= "Instance" then return oldNamecall(self, ...) end
        local args = table.pack(...)

        if Cfg.Learn then pcall(logRemote, self, args) end

        if running and Cfg.Enabled and State.ready and isShootRemote(self.Name) then
            local ok, newArgs = pcall(rewriteArgs, self, args)
            if ok and newArgs then
                return oldNamecall(self, table.unpack(newArgs, 1, newArgs.n))
            end
        end
    end
    return oldNamecall(self, ...)
end

local function installHook()
    if hooked then return true end
    if not (hookmetamethod and getnamecallmethod and newcclosure) then return false end
    local ok = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(handler))
    end)
    if not ok then return false end
    hooked = true
    return true
end

local function removeHook()
    if hooked and oldNamecall then
        pcall(function() hookmetamethod(game, "__namecall", oldNamecall) end)
    end
    hooked, oldNamecall = false, nil
end

--==========================================================================
-- 10. INPUT
--==========================================================================
local function onInput(input, gp)
    if gp then return end

    if input.KeyCode == Cfg.Hotkey then
        Cfg.Enabled = not Cfg.Enabled
        if Cfg.Enabled then installHook() end
        if gui then gui.Enabled = true end
        return
    end

    for _, s in ipairs(Cfg.ShootInputs) do
        if input.UserInputType == s or input.KeyCode == s then
            lastShootInput = tick()
            if hooked or not Cfg.InputFallback or not Cfg.Enabled or not State.ready then return end
            local cam = Workspace.CurrentCamera
            local point = takeShotPoint()
            if cam and point then
                local cur = cam.CFrame
                cam.CFrame = cur:Lerp(CFrame.lookAt(cur.Position, point), Cfg.AimStrength)
            end
            return
        end
    end
end

--==========================================================================
-- 11. LOOP
--==========================================================================
local function step()
    State.ready = false
    if not Cfg.Enabled then say("Apagado") return end

    if tick() - lastScan > 2 then
        lastScan = tick()
        task.spawn(function() pcall(scanGoals) end)
    end

    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then say("Sin personaje") return end
    State.root = root

    local ball = getBall()
    if not ball then say("Sin balón en el mapa") return end

    local cam = Workspace.CurrentCamera
    local lookVec = flatUnit(cam and cam.CFrame.LookVector or root.CFrame.LookVector, Vector3.new(0,0,-1))
    local g = pickGoal(root.Position, lookVec)
    if not g then State.preset = nil; say("Fuera de rango") return end
    if not hasBall(root, ball) then say("Sin balón") return end

    if State.goal ~= g.inst then
        State.goal, State.preset, State.shotPoint = g.inst, nil, nil
    end
    State.frame = frameOf(g.cf, g.size)
    State.ready = true
    say(("Listo · %d st"):format(math.floor(g.dist + 0.5)))
end

--==========================================================================
-- 12. GUI
--==========================================================================
local C = {
    bg=Color3.fromRGB(18,20,28), card=Color3.fromRGB(30,33,45),
    txt=Color3.fromRGB(232,236,246), mut=Color3.fromRGB(138,144,166),
    acc=Color3.fromRGB(60,120,255), off=Color3.fromRGB(58,62,84),
    ok=Color3.fromRGB(60,190,110), warn=Color3.fromRGB(200,160,50),
}

local function mk(cls, p, parent)
    local o = Instance.new(cls)
    for k, v in pairs(p) do pcall(function() o[k] = v end) end
    o.Parent = parent; return o
end
local function corner(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r) }, o); return o end

local function refreshGui()
    if not gui then return end
    if toggleBtn then
        toggleBtn.Text = Cfg.Enabled and "Aim: ON" or "Aim: OFF"
      toggleBtn.BackgroundColor3 = Cfg.Enabled and C.ok or C.off
    end
    if learnBtn then
        learnBtn.Text = Cfg.Learn and "Aprender: ON" or "Aprender: OFF"
        learnBtn.BackgroundColor3 = Cfg.Learn and C.warn or C.off
    end
    if remoteLabel then
        remoteLabel.Text = "Remote: "..(Cfg.ConfirmedRemote or "auto")
        remoteLabel.TextColor3 = Cfg.ConfirmedRemote and C.ok or C.mut
    end
    if statusLabel then statusLabel.Text = State.status end
end

local function buildGui()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    gui = mk("ScreenGui", { Name="AutoAimV3", ResetOnSpawn=false, DisplayOrder=998 }, parent)

    local panel = corner(mk("Frame", {
        Size = UDim2.fromOffset(230, 372), Position = UDim2.new(0, 12, 0.35, 0),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true,
    }, gui), 10)
    mk("UIStroke", { Color = C.acc, Thickness = 1.5, Transparency = 0.45 }, panel)

    local head = mk("Frame", { Size = UDim2.new(1,0,0,28), BackgroundTransparency = 1, Active = true }, panel)
    mk("TextLabel", { Text = "⚽ Auto Aim v3", Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10,0), Size = UDim2.new(1,-80,1,0) }, head)

    local minBtn = corner(mk("TextButton", { Text="–", Font=Enum.Font.GothamBold, TextSize=13,
        TextColor3=C.mut, BackgroundColor3=C.card, Size=UDim2.fromOffset(24,20),
        Position=UDim2.new(1,-56,0,4), AutoButtonColor=false }, head), 5)
    local closeBtn = corner(mk("TextButton", { Text="✕", Font=Enum.Font.GothamBold, TextSize=12,
        TextColor3=C.mut, BackgroundColor3=C.card, Size=UDim2.fromOffset(24,20),
        Position=UDim2.new(1,-30,0,4), AutoButtonColor=false }, head), 5)

    statusLabel = mk("TextLabel", { Text="Iniciando", Font=Enum.Font.Gotham, TextSize=11,
        TextColor3=C.mut, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
        BackgroundTransparency=1, Position=UDim2.new(0,10,0,26), Size=UDim2.new(1,-20,0,14) }, panel)

    remoteLabel = mk("TextLabel", { Text="Remote: auto", Font=Enum.Font.Gotham, TextSize=11,
        TextColor3=C.mut, TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1,
        Position=UDim2.new(0,10,0,40), Size=UDim2.new(1,-20,0,14) }, panel)

    local body = mk("ScrollingFrame", {
        Size = UDim2.new(1,-14,1,-92), Position = UDim2.fromOffset(7,58),
        BackgroundTransparency=1, ScrollBarThickness=3, ScrollBarImageColor3=C.acc,
        CanvasSize=UDim2.new(0,0,0,0),
    }, panel)
    local layout = mk("UIListLayout", { Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder }, body)
    track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        body.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 6)
    end))

    local expanded = panel.Size
    local collapsed = false
    minBtn.Activated:Connect(function()
        collapsed = not collapsed
        panel.Size = collapsed and UDim2.fromOffset(230, 30) or expanded
        body.Visible = not collapsed
        statusLabel.Visible = not collapsed
        remoteLabel.Visible = not collapsed
        minBtn.Text = collapsed and "+" or "–"
    end)

    local dragging, dS, dO = false, nil, nil
    track(head.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dS, dO = true, i.Position, panel.Position
        end
    end))
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dS
            panel.Position = UDim2.new(dO.X.Scale, dO.X.Offset+d.X, dO.Y.Scale, dO.Y.Offset+d.Y)
        end
    end))
    track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    local function addToggle(text, get, set)
        local r = corner(mk("Frame", { Size=UDim2.new(1,-4,0,32), BackgroundColor3=C.card, BorderSizePixel=0 }, body), 7)
        mk("TextLabel", { Text=text, Font=Enum.Font.GothamMedium, TextSize=12, TextColor3=C.txt,
            TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1,
            Position=UDim2.fromOffset(9,0), Size=UDim2.new(1,-60,1,0) }, r)
        local t = corner(mk("TextButton", { Text="", AutoButtonColor=false,
            Size=UDim2.fromOffset(34,18), Position=UDim2.new(1,-42,0.5,-9),
            BackgroundColor3=get() and C.acc or C.off }, r), 9)
        local k = corner(mk("Frame", { Size=UDim2.fromOffset(12,12), Position=UDim2.fromOffset(3,3),
            BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0 }, t), 6)
        local function render()
            local on = get()
            Tween:Create(t, TweenInfo.new(0.14), { BackgroundColor3 = on and C.acc or C.off }):Play()
            Tween:Create(k, TweenInfo.new(0.14), { Position = UDim2.fromOffset(on and 19 or 3, 3) }):Play()
        end
        track(t.Activated:Connect(function() set(not get()); render(); refreshGui() end))
        render()
    end

    local function addSlider(text, get, set, min, max, step, fmt)
        local r = corner(mk("Frame", { Size=UDim2.new(1,-4,0,42), BackgroundColor3=C.card, BorderSizePixel=0 }, body), 7)
        mk("TextLabel", { Text=text, Font=Enum.Font.GothamMedium, TextSize=11, TextColor3=C.txt,
            TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1,
            Position=UDim2.fromOffset(9,3), Size=UDim2.new(1,-80,0,14) }, r)
        local val = mk("TextLabel", { Text="", Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.acc,
            TextXAlignment=Enum.TextXAlignment.Right, BackgroundTransparency=1,
            Position=UDim2.new(1,-64,0,3), Size=UDim2.fromOffset(56,14) }, r)
        local t = corner(mk("Frame", { Size=UDim2.new(1,-18,0,5), Position=UDim2.fromOffset(9,25),
            BackgroundColor3=C.off, BorderSizePixel=0 }, r), 3)
        local fill = corner(mk("Frame", { Size=UDim2.new(0,0,1,0), BackgroundColor3=C.acc, BorderSizePixel=0 }, t), 3)
        local knob = corner(mk("Frame", { Size=UDim2.fromOffset(11,11), AnchorPoint=Vector2.new(0.5,0.5),
            Position=UDim2.new(0,0,0.5,0), BackgroundColor3=C.txt, BorderSizePixel=0, ZIndex=2 }, t), 6)
        local function render()
            local v = get()
            local a = math.clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, 0, 0.5, 0)
            val.Text = fmt(v)
        end
        local held = false
        local function fromX(x)
            local rel = math.clamp((x - t.AbsolutePosition.X) / math.max(t.AbsoluteSize.X, 1), 0, 1)
            set(math.clamp(math.floor((min + rel*(max-min))/step + 0.5)*step, min, max)); render()
        end
        track(t.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                held = true; fromX(i.Position.X)
            end
        end))
        track(UIS.InputChanged:Connect(function(i)
            if held and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                fromX(i.Position.X)
            end
        end))
        track(UIS.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then held = false end
        end))
        render()
    end

    local function addButton(text, cb, accent)
        local b = corner(mk("TextButton", { Text=text, Font=Enum.Font.GothamBold, TextSize=11,
            TextColor3=C.txt, BackgroundColor3=accent and C.acc or C.card, AutoButtonColor=false,
            Size=UDim2.new(1,-4,0,28) }, body), 7)
        track(b.Activated:Connect(function() pcall(cb) end))
    end

    toggleBtn = corner(mk("TextButton", { Text="Aim: ON", Font=Enum.Font.GothamBold, TextSize=12,
        TextColor3=C.txt, BackgroundColor3=C.ok, AutoButtonColor=false,
        Size=UDim2.new(1,-4,0,30) }, body), 7)
    track(toggleBtn.Activated:Connect(function()
        Cfg.Enabled = not Cfg.Enabled
        if Cfg.Enabled then installHook() end
        refreshGui()
    end))

    learnBtn = corner(mk("TextButton", { Text="Aprender: OFF", Font=Enum.Font.GothamBold, TextSize=12,
        TextColor3=C.txt, BackgroundColor3=C.off, AutoButtonColor=false,
        Size=UDim2.new(1,-4,0,30) }, body), 7)
    track(learnBtn.Activated:Connect(function()
        Cfg.Learn = not Cfg.Learn
        if Cfg.Learn then learnStats = {}; learnLog = {}; print("[AutoAim] aprendizaje ON") end
        refreshGui()
    end))

    addSlider("Alcance", function() return Cfg.MaxDistance end,
        function(v) Cfg.MaxDistance = v end, Cfg.SliderMin, Cfg.SliderMax, 5,
        function(v) return ("%d st"):format(v) end)
    addSlider("Fuerza", function() return Cfg.AimStrength end,
        function(v) Cfg.AimStrength = v end, 0.2, 1, 0.05,
        function(v) return ("%d%%"):format(math.floor(v*100+0.5)) end)
    addSlider("Cono", function() return Cfg.FacingDot end,
        function(v) Cfg.FacingDot = v; Cfg.RequireFacing = v > -0.99 end, -1, 0.8, 0.05,
        function(v) return ("%d°"):format(math.deg(math.acos(math.clamp(v,-1,1)))) end)

    addButton("Usar mejor candidato", function()
        local name, sc = bestCandidate()
        if not name then say("Nada aprendido aún"); refreshGui(); return end
        Cfg.ConfirmedRemote = name
        say(("Remote fijado: %s (%.1f)"):format(name, sc), C.ok)
        print("[AutoAim] candidatos:")
        for n, s in pairs(learnStats) do print(("  %-28s count=%d click=%d vec=%s score=%.1f")
            :format(n, s.count, s.afterClick, tostring(s.vec), scoreOf(s))) end
        refreshGui()
    end, true)

    addButton("Volcar remotes al log", function()
        if #learnLog == 0 then say("Log vacío · activa Aprender") return end
        print("=== REMOTES ("..#learnLog..") ===")
        for _, l in ipairs(learnLog) do print(l) end
    end)
    addButton("Reset stats", function()
        learnStats, learnLog = {}, {}
        say("Stats borradas")
    end)
    addButton("Quitar remote fijado", function()
        Cfg.ConfirmedRemote = nil; say("Remote en auto"); refreshGui()
    end)

    refreshGui()
end

--==========================================================================
-- 13. CICLO DE VIDA
--==========================================================================
local function start()
    running = true
    if Cfg.ShowGui then pcall(buildGui) end
    if Cfg.Enabled then installHook() end
    track(RunService.Heartbeat:Connect(function() pcall(step) end))
    track(UIS.InputBegan:Connect(onInput))
    track(Workspace.DescendantAdded:Connect(function(d)
        if nameMatches(d.Name) then pcall(considerGoal, d) end
    end))
    task.spawn(function() pcall(scanGoals) end)
    say("Listo")
    if not hooked and Cfg.InputFallback then
        say("Hook no disponible · usando fallback de cámara", C.warn)
    end
end

local function stop()
    running = false
    State.ready = false
    removeHook()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    if gui then pcall(function() gui:Destroy() end); gui = nil end
    getgenv().AutoAim = nil
    print("[AutoAim] detenido, hook restaurado")
end

Cfg.stop  = stop
Cfg.start = start
Cfg.state = State
Cfg.learn = learnStats
getgenv().AutoAim = Cfg

start()
