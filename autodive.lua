--[[
    AUTO AIM v2 — Blue Lock: Rivals
    Mejoras: completo, tabla-scan en args, modo APRENDER (detecta el remote real
    que usa el juego), frame sólo con postes (ignora la red), y stop() real.
]]

--==========================================================================
-- 1. SERVICIOS
--==========================================================================
local Players   = game:GetService("Players")
local RunService= game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LP        = Players.LocalPlayer

if getgenv().AutoAim and getgenv().AutoAim.stop then
    pcall(getgenv().AutoAim.stop)
end

--==========================================================================
-- 2. CONFIGURACIÓN
--==========================================================================
local Cfg = {
    Enabled         = true,
    MinDistance     = 12,
    MaxDistance     = 120,
    SliderMin       = 30,
    SliderMax       = 200,
    RequireFacing   = true,
    FacingDot       = 0.15,

    -- Portería: ahora incluye nombres más comunes
    GoalNames       = { "goal", "goals", "goalpost", "goalposts", "goalnet",
                        "net", "rim", "arco", "porteria", "portería", "target" },
    PartialMatch    = true,       -- true ayuda muchísimo, "Goal" vs "GoalLeft"
    -- Sub-piezas dentro del modelo de portería cuyo tamaño representa el marco real
    FramePartNames  = { "post", "posts", "crossbar", "bar", "frame", "goalpost", "goalposts" },

    -- Balón
    BallNames       = { "Football", "Ball", "SoccerBall", "Soccer Ball", "Soccerball", "football" },
    PossessionDistance = 14,
    OwnerKeys       = { "Owner", "Possessor", "Holder", "BallOwner", "PlayerOwner" },

    -- Remotos de disparo
    RemoteNames     = { Shoot=true, shoot_event=true, Shot=true, Kick=true,
                        KickEvent=true, ShootEvent=true, BallKick=true },
    ArgMode         = "auto",
    ArgIndex        = nil,
    AimStrength     = 1,
    ShotWindow      = 0.40,

    -- Puntos dentro del marco (u: -0.5 izq / +0.5 der | v: 0 césped / 1 travesaño)
    Targets = {
        { name = "Escuadra izq", u = -0.40, v = 0.88, weight = 1.2 },
        { name = "Escuadra der", u =  0.40, v = 0.88, weight = 1.2 },
        { name = "Abajo izq",    u = -0.38, v = 0.12, weight = 1.0 },
        { name = "Abajo der",    u =  0.38, v = 0.12, weight = 1.0 },
        { name = "Centro",       u =  0.00, v = 0.50, weight = 0.7 },
    },
    Jitter      = 0.05,
    Margin      = 0.06,
    DepthFactor = 0,            -- 0 = plano del arco; subir para meterla dentro

    -- Fallback: rotar cámara al pulsar disparo
    InputFallback = true,
    ShootInputs   = { Enum.UserInputType.MouseButton1 },

    -- Modo APRENDER: loggea TODOS los remotos que se disparan para identificar el de tiro
    Learn   = false,

    ShowGui = true,
    Debug   = false,
}
getgenv().AutoAim = Cfg

--==========================================================================
-- 3. ESTADO
--==========================================================================
local State = {
    ready=false, status="Iniciando", root=nil, ball=nil,
    goal=nil, frame=nil, preset=nil, shotPoint=nil, shotAt=0, shotName=nil,
}
local goals, boundsCache = {}, {}
local lastPreset
local conns = {}
local rng = Random.new(tick() * 1000)
local running = true
local hooked = false
local oldNamecall

local function track(c) conns[#conns+1] = c; return c end

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
    -- Descartar si un ancestro ya es portería (evita anidamientos)
    local p = inst.Parent
    while p and p ~= Workspace do
        if goals[p] then return end
        p = p.Parent
    end
    -- Sacar hijos registrados
    for g in pairs(goals) do
        if g:IsDescendantOf(inst) then goals[g]=nil; boundsCache[g]=nil end
    end
    goals[inst] = true
end

local function scanGoals()
    goals = {}
    boundsCache = {}
    local ok, list = pcall(Workspace.GetDescendants, Workspace)
    if not ok then return end
    for _, d in ipairs(list) do
        local ok2 = pcall(considerGoal, d)
        if not ok2 then end
    end
end

-- Boundingbox EXCLUYENDO la red: si encuentro postes/travesaños, los uso
local function boundsOf(inst)
    local c = boundsCache[inst]
    if c and tick() - c.t < 1 then return c.cf, c.size end

    local cf, size
    if inst:IsA("BasePart") then
        cf, size = inst.CFrame, inst.Size
    else
        -- Intentar con sub-piezas del marco
        local fparts = {}
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                local n = string.lower(d.Name)
                for _, k in ipairs(Cfg.FramePartNames) do
                    if string.find(n, k, 1, true) then fparts[#fparts+1] = d; break end
                end
            end
        end
        if #fparts >= 2 then
            -- bounding box manual sobre los postes
            local min = Vector3.new(math.huge, math.huge, math.huge)
            local max = -min
            for _, d in ipairs(fparts) do
                local dcf, dsz = d.CFrame, d.Size
                for _, sx in ipairs({-0.5, 0.5}) do
                    for _, sy in ipairs({-0.5, 0.5}) do
                        for _, sz in ipairs({-0.5, 0.5}) do
                            local world = (dcf * CFrame.new(sx*dsz.X, sy*dsz.Y, sz*dsz.Z)).Position
                            min = Vector3.new(math.min(min.X,world.X), math.min(min.Y,world.Y), math.min(min.Z,world.Z))
                            max = Vector3.new(math.max(max.X,world.X), math.max(max.Y,world.Y), math.max(max.Z,world.Z))
                        end
                    end
                end
            end
            local center = (min + max) * 0.5
            size = max - min
            cf = CFrame.new(center) * (inst:GetPivot() - inst:GetPivot().Position)
        else
            local ok, rcf, rsz = pcall(function() return inst:GetBoundingBox() end)
            if not ok then return end
            cf, size = rcf, rsz
        end
    end

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
    -- En portería: profundidad suele ser el menor de X/Z
    if size.X >= size.Z then
        return { center=cf.Position, w=right, d=look, width=size.X, depth=size.Z, height=size.Y }
    else
        return { center=cf.Position, w=look,  d=right, width=size.Z, depth=size.X, height=size.Y }
    end
end

local function pickGoal(pos, lookVec)
    local best, bestScore
    for inst in pairs(goals) do
        if inst.Parent then
            local cf, size = boundsOf(inst)
            if cf and size then
                local flat = Vector3.new(cf.Position.X-pos.X, 0, cf.Position.Z-pos.Z)
                local dist = flat.Magnitude
                if dist >= Cfg.MinDistance and dist <= Cfg.MaxDistance then
                    local facing = dist > 0.01 and lookVec:Dot(flat.Unit) or 1
                    if (not Cfg.RequireFacing or facing >= Cfg.FacingDot)
                        and (not bestScore or facing > bestScore) then
                        best = { inst=inst, cf=cf, size=size, dist=dist }
                        bestScore = facing
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
    local v = math.clamp(preset.v + (rng:NextNumber()-0.5)*2*Cfg.Jitter,  m,     1-m)
    return frame.center
        + w * (u * frame.width)
        + Vector3.yAxis * ((v-0.5)*frame.height)
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
-- 7. LEARN MODE (identificar el remote de tiro)
--==========================================================================
local learnLog = {}
local function logRemote(inst, args)
    if #learnLog > 200 then return end
    local parts = {}
    for i = 1, args.n do
        local v = args[i]
        local t = typeof(v)
        if t == "Instance" then parts[i] = i..":Inst("..v:GetFullName()..")"
        elseif t == "table" then
            local ks = {}
            for k, val in pairs(v) do ks[#ks+1] = tostring(k).."="..typeof(val) end
            parts[i] = i..":{"..table.concat(ks, ",").."}"
        else parts[i] = i..":"..t.."="..tostring(v):sub(1, 50) end
    end
    learnLog[#learnLog+1] = inst:GetFullName().."  |  "..table.concat(parts, " | ")
end

--==========================================================================
-- 8. REESCRITURA DE ARGUMENTOS (con recursión a tablas)
--==========================================================================
local function blend(a, b) return a:Lerp(b, Cfg.AimStrength) end

-- Devuelve (vecCambiado, indiceCambiado) para vector único
local function rewriteValue(v, origin, point)
    local t = typeof(v)
    if t == "Vector3" then
        local mag = v.Magnitude
        local asDir = Cfg.ArgMode=="direction" or (Cfg.ArgMode=="auto" and mag > 0.5 and mag <= 1.5)
        local asPos = Cfg.ArgMode=="position"  or (Cfg.ArgMode=="auto" and mag > 1.5)
        if asDir then
            local d = point - origin
            if d.Magnitude < 0.5 then return nil end
            return blend(v, d.Unit).Unit
        elseif asPos then
            -- Sólo si está lejos del jugador (probablemente es un target, no un origen)
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

-- Recorre args; busca dentro de tablas también
local function rewriteArgs(remote, args)
    local point = takeShotPoint()
    if not point then return nil end
    local origin = (State.ball and State.ball.Position) or State.root.Position

    local changed = false
    local out = { n = args.n }

    local function visit(node, depth)
        local t = typeof(node)
        if t == "table" then
            if depth > 3 then return end
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
            local before = changed
            out[i] = visit(args[i], 0)
            if Cfg.Debug and not before and changed then
                print("[AutoAim] arg "..i.." reescrito -> destino "..(State.shotName or "?"))
            end
        else
            out[i] = args[i]
        end
    end

    return changed and out or nil
end

--==========================================================================
-- 9. HOOK
--==========================================================================
local function installHook()
    if hooked then return true end
    if not (hookmetamethod and getnamecallmethod and newcclosure) then
        warn("[AutoAim] Tu executor no soporta hookmetamethod/newcclosure. Usa InputFallback o cambia de executor.")
        return false
    end

    local function handler(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local ok, res = pcall(function() return typeof(self) == "Instance" end)
            if not ok or not res then
                return oldNamecall(self, ...)
            end

            local args = table.pack(...)

            -- Modo aprender: loggea TODO lo que se dispara
            if Cfg.Learn then
                local okL = pcall(logRemote, self, args)
                if not okL then end
            end

            -- Interceptar si es el remote de disparo
            if running and Cfg.Enabled and State.ready and Cfg.RemoteNames[self.Name] then
                local okR, newArgs = pcall(rewriteArgs, self, args)
                if okR and newArgs then
                    return oldNamecall(self, table.unpack(newArgs, 1, newArgs.n))
                end
            end
        end
        return oldNamecall(self, ...)
    end

    local ok = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(handler))
    end)
    if not ok then
        warn("[AutoAim] Falló la instalación del hook. Muchos juegos con anti-cheat lo bloquean.")
        return false
    end
    hooked = true
    return true
end

-- Fallback: rotar cámara al pulsar disparo
local function onInput(input)
    if hooked or not Cfg.InputFallback or not Cfg.Enabled or not State.ready then return end
    for _, s in ipairs(Cfg.ShootInputs) do
        if input.UserInputType == s or input.KeyCode == s then
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
-- 10. LOOP
--==========================================================================
local function step()
    State.ready = false
    if not Cfg.Enabled then State.status="Apagado" return end

    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then State.status="Sin personaje"; return end
    State.root = root

    local ball = getBall()
    if not ball then State.status="Sin balón en el mapa"; return end

    local cam = Workspace.CurrentCamera
    local lookVec = flatUnit(cam and cam.CFrame.LookVector or root.CFrame.LookVector, Vector3.new(0,0,-1))
    local g = pickGoal(root.Position, lookVec)
    if not g then State.status="Fuera de rango"; State.preset=nil; return end
    if not hasBall(root, ball) then State.status="Sin balón"; return end

    if State.goal ~= g.inst then State.goal = g.inst; State.preset = nil end
    State.frame = frameOf(g.cf, g.size)
    State.ready = true
    State.status = string.format("Listo · %d st", math.floor(g.dist + 0.5))
    if not State.preset then State.preset = rollPreset() end
end

--==========================================================================
-- 11. GUI
--==========================================================================
local gui, toggleBtn, rangeLabel, statusLabel, fill, knob, learnBtn, printBtn

local function applyRange(v)
    Cfg.MaxDistance = math.clamp(math.floor(v + 0.5), Cfg.SliderMin, Cfg.SliderMax)
    if rangeLabel then rangeLabel.Text = "Rango: "..Cfg.MaxDistance.." st" end
    if fill and knob then
        local a = (Cfg.MaxDistance - Cfg.SliderMin) / (Cfg.SliderMax - Cfg.SliderMin)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
    end
end
Cfg.setRange = applyRange

local function refreshGui()
    if not toggleBtn then return end
    toggleBtn.Text = Cfg.Enabled and "Auto Aim: ON" or "Auto Aim: OFF"
    toggleBtn.BackgroundColor3 = Cfg.Enabled
        and Color3.fromRGB(60,190,110) or Color3.fromRGB(75,78,95)
    learnBtn.Text = Cfg.Learn and "Aprender: ON" or "Aprender: OFF"
    learnBtn.BackgroundColor3 = Cfg.Learn
        and Color3.fromRGB(200,160,50) or Color3.fromRGB(75,78,95)
    if statusLabel then statusLabel.Text = State.status end
end

local function buildGui()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    gui = Instance.new("ScreenGui")
    gui.Name = "AutoAimV2"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 998
    gui.Parent = parent

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(200, 190)
    panel.Position = UDim2.new(0, 10, 0.5, -95)
    panel.BackgroundColor3 = Color3.fromRGB(22,24,32)
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
    Instance.new("UIPadding", panel).PaddingTop = UDim.new(0, 6)

    local function label(text, y, size, bold)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
            l.Position = UDim2.fromOffset(10, y)
        l.Size = UDim2.fromOffset(180, 16)
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        l.TextSize = size
        l.TextColor3 = Color3.fromRGB(235,235,240)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = text
        l.Parent = panel
        return l
    end

    label("Auto Aim v2", 2, 13, true)

    toggleBtn = Instance.new("TextButton")
    toggleBtn.Position = UDim2.fromOffset(10, 24)
    toggleBtn.Size = UDim2.fromOffset(180, 26)
    toggleBtn.AutoButtonColor = false
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 12
    toggleBtn.TextColor3 = Color3.new(1,1,1)
    toggleBtn.Parent = panel
    Instance.new("UICorner", toggleBtn)
    toggleBtn.Activated:Connect(function()
        Cfg.Enabled = not Cfg.Enabled; refreshGui()
    end)

    rangeLabel = label("Rango: "..Cfg.MaxDistance.." st", 56, 11, false)

    local track = Instance.new("Frame")
    track.Position = UDim2.fromOffset(10, 74)
    track.Size = UDim2.fromOffset(180, 8)
    track.BackgroundColor3 = Color3.fromRGB(45,48,62)
    track.BorderSizePixel = 0
    track.Parent = panel
    Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)

    fill = Instance.new("Frame")
    fill.Size = UDim2.new((Cfg.MaxDistance - Cfg.SliderMin)/(Cfg.SliderMax - Cfg.SliderMin), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(80,150,255)
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)

    knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.Position = UDim2.new((Cfg.MaxDistance - Cfg.SliderMin)/(Cfg.SliderMax - Cfg.SliderMin), 0, 0.5, 0)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)

    local sliderBtn = Instance.new("TextButton")
    sliderBtn.BackgroundTransparency = 1
    sliderBtn.Size = UDim2.new(1, 0, 3, 0)
    sliderBtn.Position = UDim2.new(0, 0, -1, 0)
    sliderBtn.Text = ""
    sliderBtn.Parent = track
    sliderBtn.MouseButton1Down:Connect(function()
        local function update(x)
            local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            applyRange(Cfg.SliderMin + rel * (Cfg.SliderMax - Cfg.SliderMin))
        end
        update(UIS:GetMouseLocation().X)
        local moveConn
        moveConn = UIS.InputChanged:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseMovement then
                update(inp.Position.X)
            end
        end)
        local upConn
        upConn = UIS.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                if moveConn then moveConn:Disconnect() end
                if upConn then upConn:Disconnect() end
            end
        end)
    end)

    learnBtn = Instance.new("TextButton")
    learnBtn.Position = UDim2.fromOffset(10, 90)
    learnBtn.Size = UDim2.fromOffset(180, 24)
    learnBtn.AutoButtonColor = false
    learnBtn.Font = Enum.Font.GothamBold
    learnBtn.TextSize = 11
    learnBtn.TextColor3 = Color3.new(1,1,1)
    learnBtn.BackgroundColor3 = Color3.fromRGB(75,78,95)
    learnBtn.Text = "Aprender: OFF"
    learnBtn.Parent = panel
    Instance.new("UICorner", learnBtn)
    learnBtn.Activated:Connect(function()
        Cfg.Learn = not Cfg.Learn
        if Cfg.Learn then learnLog = {} end
        refreshGui()
    end)

    printBtn = Instance.new("TextButton")
    printBtn.Position = UDim2.fromOffset(10, 118)
    printBtn.Size = UDim2.fromOffset(180, 22)
    printBtn.AutoButtonColor = false
    printBtn.Font = Enum.Font.Gotham
    printBtn.TextSize = 11
    printBtn.TextColor3 = Color3.new(1,1,1)
    printBtn.BackgroundColor3 = Color3.fromRGB(45,48,62)
    printBtn.Text = "Volcar remotos al Output"
    printBtn.Parent = panel
    Instance.new("UICorner", printBtn)
    printBtn.Activated:Connect(function()
        if #learnLog == 0 then
            print("[AutoAim] Sin remotos. Activa Aprender, dispara, luego pulsa de nuevo.")
        else
            print("[AutoAim] === Remotos capturados ("..#learnLog..") ===")
            for _, l in ipairs(learnLog) do print("  "..l) end
            print("[AutoAim] Busca uno con Vector3/CFrame y añádelo a Cfg.RemoteNames.")
        end
    end)

    statusLabel = label("Iniciando", 148, 11, false)
    statusLabel.TextColor3 = Color3.fromRGB(150,200,255)

    if not Cfg.ShowGui then gui.Enabled = false end
    refreshGui()
end

--==========================================================================
-- 12. ARRANQUE
--==========================================================================
scanGoals()
installHook()
if Cfg.ShowGui then buildGui() end

-- Re-escanear porterías cada 30 s y en respawn
local lastScan = tick()
local function tickLoop()
    if not running then return end
    local now = tick()
    if now - lastScan > 30 then
        lastScan = now
        pcall(scanGoals)
    end
    local ok = pcall(step)
    if not ok then State.status = "Error en loop" end
    if gui and statusLabel then
        pcall(function() statusLabel.Text = State.status end)
    end
end

track(RunService.Heartbeat:Connect(tickLoop))
track(UIS.InputBegan:Connect(onInput))

-- Limpieza
function Cfg.stop()
    running = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    if gui then pcall(function() gui:Destroy() end) gui = nil end
    if getgenv().AutoAim == Cfg then getgenv().AutoAim = nil end
    print("[AutoAim] Detenido.")
end

print("[AutoAim] Listo. Enabled="..tostring(Cfg.Enabled)..". Hook="..tostring(hooked))
if not hooked then
    print("[AutoAim] Sin hook. Usa el botón 'Aprender', dispara y revisa qué remoto sale con Vector3.")
end
