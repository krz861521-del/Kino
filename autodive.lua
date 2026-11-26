-- =====================================================
-- NOVA HUB — v1.0
-- =====================================================

local Players = game:GetService("Players")
-- =====================================================
-- AUTO DRIBBLE v2 — regatea solo cuando un rival se lanza
-- =====================================================
local function startAutoDribble()
    -- ⬇️ PEGA AQUÍ TODO EL SCRIPT DE AUTO DRIBBLE v2 (el que me pasaste) ⬇️
    -- Nada más. Empieza desde "local Players = game:GetService("Players")"
    -- hasta "print("[AutoDribble] v2 cargado · modo " .. Cfg.Mode)"
    -- ⬆️ FIN DEL PEGADO ⬆️
end

local function stopAutoDribble()
    if getgenv().AutoDribble and getgenv().AutoDribble.stop then
        pcall(getgenv().AutoDribble.stop)
    end
end

makeCard("Auto Dribble", "Regatea solo vs rivales que se lanzan", "⚽", function(on)
    if on then
        startAutoDribble()
        notify("Auto Dribble activado", C.Green)
    else
        stopAutoDribble()
        notify("Auto Dribble desactivado", C.Red)
    end
end)
print("[AutoDribble] v2 cargado · modo " .. Cfg.Mode .. " (Nova Hub)")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local C = {
    Bg      = Color3.fromRGB(20, 22, 32),
    Bg2     = Color3.fromRGB(14, 16, 24),
    Card    = Color3.fromRGB(32, 35, 48),
    Hover   = Color3.fromRGB(42, 46, 62),
    Accent  = Color3.fromRGB(130, 105, 255),
    Accent2 = Color3.fromRGB(90, 180, 255),
    Text    = Color3.fromRGB(240, 242, 250),
    Dim     = Color3.fromRGB(150, 155, 175),
    Green   = Color3.fromRGB(60, 210, 130),
    Off     = Color3.fromRGB(50, 55, 70),
    Red     = Color3.fromRGB(235, 85, 105),
}

local function mk(c, p, parent)
    local i = Instance.new(c)
    for k, v in pairs(p or {}) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local function corner(p, r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p) end
local function stroke(p, col, t) return mk("UIStroke", { Color = col, Thickness = t or 1 }, p) end

-- ===== ScreenGuis =====
local gui = mk("ScreenGui", { Name = "NovaHub", ResetOnSpawn = false, DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, PG)
local notifGui = mk("ScreenGui", { Name = "NovaNotif", ResetOnSpawn = false, DisplayOrder = 101 }, PG)

-- ===== Notificaciones =====
local notifBox = mk("Frame", {
    Size = UDim2.fromOffset(280, 320),
    Position = UDim2.new(1, -300, 1, -340),
    BackgroundTransparency = 1,
}, notifGui)
mk("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
}, notifBox)

local nOrder = 0
local function notify(text, color)
    nOrder = nOrder + 1
    local f = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = C.Card,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = nOrder,
    }, notifBox)
    corner(f, 10)
    stroke(f, color, 1)
    local bar = mk("Frame", {
        Size = UDim2.fromOffset(3, 24),
        Position = UDim2.new(0, 10, 0.5, -12),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, f)
    corner(bar, 2)
    local lbl = mk("TextLabel", {
        Size = UDim2.new(1, -32, 1, 0),
        Position = UDim2.fromOffset(22, 0),
        BackgroundTransparency = 1,
        Text = text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = C.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTransparency = 1,
    }, f)

    TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 0.05 }):Play()
    TweenService:Create(lbl, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()

    task.delay(2.5, function()
        TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
        task.wait(0.35)
        f:Destroy()
    end)
end

-- ===== Ventana principal =====
local win = mk("Frame", {
    Size = UDim2.fromOffset(360, 460),
    Position = UDim2.new(0.5, -180, 0.5, -230),
    BackgroundColor3 = C.Bg,
    BorderSizePixel = 0,
}, gui)
corner(win, 14)
stroke(win, C.Accent, 1.5)
mk("UIGradient", {
    Color = ColorSequence.new(C.Bg, C.Bg2),
    Rotation = 90,
}, win)

-- Header
local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1 }, win)

local titleLbl = mk("TextLabel", {
    Size = UDim2.new(1, -100, 1, 0),
    Position = UDim2.fromOffset(18, 0),
    BackgroundTransparency = 1,
    Text = "✦  NOVA HUB",
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = C.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
mk("UIGradient", { Color = ColorSequence.new(C.Accent, C.Accent2) }, titleLbl)

mk("Frame", {
    Size = UDim2.new(1, -24, 0, 1),
    Position = UDim2.new(0, 12, 0, 48),
    BackgroundColor3 = C.Hover,
    BorderSizePixel = 0,
}, win)

local closeBtn = mk("TextButton", {
    Size = UDim2.fromOffset(26, 26),
    Position = UDim2.new(1, -38, 0, 11),
    BackgroundColor3 = C.Red,
    BackgroundTransparency = 0.55,
    Text = "✕",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = C.Text,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, header)
corner(closeBtn, 7)

local minBtn = mk("TextButton", {
    Size = UDim2.fromOffset(26, 26),
    Position = UDim2.new(1, -70, 0, 11),
    BackgroundColor3 = C.Accent2,
    BackgroundTransparency = 0.55,
    Text = "—",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = C.Text,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, header)
corner(minBtn, 7)

-- Drag
do
    local dragging, dragStart, startPos
    local function inBtn(b, pos)
        local a, s = b.AbsolutePosition, b.AbsoluteSize
        return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
    end
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if inBtn(closeBtn, i.Position) or inBtn(minBtn, i.Position) then return end
            dragging, dragStart, startPos = true, i.Position, win.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- Contenido
local content = mk("ScrollingFrame", {
    Size = UDim2.new(1, -24, 1, -84),
    Position = UDim2.fromOffset(12, 62),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.Accent,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, win)
mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, content)

-- Card factory
local function makeCard(title, desc, icon, onToggle)
    local isOn = false
    local card = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 76),
        BackgroundColor3 = C.Card,
        BorderSizePixel = 0,
    }, content)
    corner(card, 10)
    stroke(card, C.Hover, 1)

    local iconBg = mk("Frame", {
        Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(0, 14, 0.5, -22),
        BackgroundColor3 = C.Bg,
        BorderSizePixel = 0,
    }, card)
    corner(iconBg, 10)
    mk("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = icon,
        Font = Enum.Font.GothamBold,
        TextSize = 22,
        TextColor3 = C.Text,
    }, iconBg)

    mk("TextLabel", {
        Size = UDim2.new(1, -170, 0, 20),
        Position = UDim2.fromOffset(70, 16),
        BackgroundTransparency = 1,
        Text = title,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = C.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    mk("TextLabel", {
        Size = UDim2.new(1, -170, 0, 18),
        Position = UDim2.fromOffset(70, 38),
        BackgroundTransparency = 1,
        Text = desc,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.Dim,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)

    local sw = mk("Frame", {
        Size = UDim2.fromOffset(44, 24),
        Position = UDim2.new(1, -60, 0.5, -12),
        BackgroundColor3 = C.Off,
        BorderSizePixel = 0,
    }, card)
    corner(sw, 12)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = C.Text,
        BorderSizePixel = 0,
    }, sw)
    corner(knob, 9)

    local click = mk("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 5,
    }, card)

    local function setState(on)
        isOn = on
        TweenService:Create(sw, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundColor3 = on and C.Green or C.Off }):Play()
        TweenService:Create(knob, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
            Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
        }):Play()
        if onToggle then
            local ok, err = pcall(onToggle, on)
            if not ok then warn("[Hub] error:", err) end
        end
    end

    click.Activated:Connect(function() setState(not isOn) end)
    click.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = C.Hover }):Play()
    end)
    click.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = C.Card }):Play()
    end)

    return { setState = setState, isOn = function() return isOn end, frame = card }
end

-- Minimizar
minBtn.Activated:Connect(function()
    local isMin = win.Size.Y.Offset == 48   -- ¿está minimizada ANTES del click?
    local targetSize = isMin and UDim2.fromOffset(360, 460) or UDim2.fromOffset(360, 48)

    -- si estaba minimizada → restauramos (visible = true)
    -- si estaba abierta    → minimizamos (visible = false)
    content.Visible = isMin

    -- separador y footer se ocultan junto al contenido
    for _, c in ipairs(win:GetChildren()) do
        if c ~= header and c ~= content and (c.Size.Y.Offset == 1 or c:IsA("TextLabel")) then
            c.Visible = isMin
        end
    end

    TweenService:Create(win, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = targetSize }):Play()
end)

-- Cerrar
closeBtn.Activated:Connect(function()
    if getgenv().AutoDive and getgenv().AutoDive.stop then pcall(getgenv().AutoDive.stop) end
    TweenService:Create(win, TweenInfo.new(0.2), { Size = UDim2.fromOffset(0, 0) }):Play()
    task.wait(0.25)
    gui:Destroy()
    notifGui:Destroy()
end)

-- Footer
mk("TextLabel", {
    Size = UDim2.new(1, -24, 0, 16),
    Position = UDim2.new(0, 12, 1, -22),
    BackgroundTransparency = 1,
    Text = "v1.0  ·  Nova Hub",
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = C.Dim,
    TextXAlignment = Enum.TextXAlignment.Center,
}, win)

-- =====================================================
-- AUTO DIVE — Blue Lock: Rivals (v4)
-- =====================================================
local function startAutoDive()
    if getgenv().AutoDive and getgenv().AutoDive.stop then
        pcall(getgenv().AutoDive.stop)
    end

    local Cfg = {
        Enabled = true,
        Cooldown = 2.4,
        MinSpeed = 18,
        Range = 75,
        MaxTime = 3.5,
        MaxDiveSpeed = 65.2,
        PingComp = 1,
        ExtraReach = 2,
        RequireButton = true,
        DiveButtonName = "dive",
        InfiniteStamina = true,
        ShowButton = false, -- el hub controla el ON/OFF
    }
    getgenv().AutoDive = Cfg

    local GOAL_WIDTH = 48
    local DECEL_VAL = 37
    local GROUND_VERTICAL, GROUND_GRAVITY = 35, 130
    local AIR_DIVE_MIN, AIR_DIVE_MAX, AIR_GRAVITY = 75, 85, 300
    local NUDGE_DURATION, REL_VEL_Z_MIN, BEHIND_TOL = 0.55, 1.5, 2

    local running, ready, areaOk = true, false, true
    local conns = {}
    local humanoid, rootPart, ball
    local DiveRemote, StaminaRemote, MovementAnims
    local animTracks = {}
    local diving, lastDive = false, 0
    local diveConn, diveBV, staminaConn
    local btnList, lastScan, lastCheck, btnOk, everFound = {}, 0, 0, false, false

    local function track(c) conns[#conns + 1] = c return c end

    local function hookStamina()
        if not Cfg.InfiniteStamina then return end
        local stats = LP:FindFirstChild("PlayerStats") or LP:WaitForChild("PlayerStats", 10)
        local stam = stats and (stats:FindFirstChild("Stamina") or stats:WaitForChild("Stamina", 5))
        if not stam or not running then return end
        stam.Value = 100
        if staminaConn then staminaConn:Disconnect() end
        staminaConn = stam:GetPropertyChangedSignal("Value"):Connect(function()
            if running and Cfg.InfiniteStamina and stam.Value < 95 then stam.Value = 100 end
        end)
    end

    local function isShown(obj)
        local cur = obj
        while cur do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return true
    end

    local function findDiveButtons()
        local list = {}
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return list end
        local key = string.lower(Cfg.DiveButtonName)
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiButton") then
                local hit = string.find(string.lower(d.Name), key, 1, true)
                if not hit and d:IsA("TextButton") then
                    hit = string.find(string.lower(d.Text), key, 1, true)
                end
                if hit then list[#list + 1] = d end
            end
        end
        return list
    end

    local function diveButtonAvailable()
        if not Cfg.RequireButton then return true end
        local now = tick()
        if now - lastCheck < 0.15 then return btnOk end
        lastCheck = now
        if now - lastScan > (btnOk and 3 or 0.5) then
            lastScan = now
            btnList = findDiveButtons()
            if #btnList > 0 then everFound = true end
        end
        btnOk = false
        for _, b in ipairs(btnList) do
            if b.Parent and isShown(b) then btnOk = true break end
        end
        return btnOk
    end

    function Cfg.listButtons()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return end
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiButton") then
                print("[AutoDive] botón:", d:GetFullName(), "| visible:", isShown(d),
                    "| texto:", d:IsA("TextButton") and d.Text or "-")
            end
        end
    end

    local function getBall()
        if ball and ball.Parent then return ball end
        local f = workspace:FindFirstChild("Football")
        if not f then return nil end
        ball = f:IsA("BasePart") and f
            or f:FindFirstChild("Hitbox") or f:FindFirstChild("BALL") or f:FindFirstChildWhichIsA("BasePart")
        return ball
    end

    local function setup()
        ready = false
        local char = LP.Character or LP.CharacterAdded:Wait()
        humanoid = char:WaitForChild("Humanoid")
        rootPart = char:WaitForChild("HumanoidRootPart")

        if not DiveRemote then
            local ok, err = pcall(function()
                local services = ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("Knit", 10):WaitForChild("Services", 10)
                DiveRemote = services:WaitForChild("BallService", 10):WaitForChild("RE", 10):WaitForChild("Dive", 10)
                StaminaRemote = services:WaitForChild("StaminaService", 10):WaitForChild("RE", 10):WaitForChild("DecreaseStamina", 10)
                MovementAnims = ReplicatedStorage:WaitForChild("Assets", 10):WaitForChild("ReplicatedAnims", 10):WaitForChild("Movement", 10)
            end)
            if not ok then
                DiveRemote = nil
                warn("[AutoDive] no encontré los remotes:", err)
                return
            end
        end
        if not running then return end

        local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
        animTracks = {}
        for _, name in ipairs({ "DiveL", "DiveR" }) do
            local anim = MovementAnims:FindFirstChild(name)
            if anim then animTracks[name] = animator:LoadAnimation(anim) end
        end
        ready = true
    end

    local function incoming(b)
        local vel = b.AssemblyLinearVelocity
        if vel.Magnitude < Cfg.MinSpeed then return end

        local cf = rootPart.CFrame
        local relVel = cf:VectorToObjectSpace(vel)
        local relPos = cf:PointToObjectSpace(b.Position)

        local ahead = -relPos.Z
        if relVel.Z <= REL_VEL_Z_MIN or ahead < -BEHIND_TOL then return end

        local t = math.max(math.max(ahead, 0) / relVel.Z, 0.03)
        if t > Cfg.MaxTime then return end

        local y0 = b.Position.Y
        local restY = math.max(b.Size.Y * 0.5, 1)
        local px = relPos.X + relVel.X * t
        local py = y0 + vel.Y * t - 0.5 * workspace.Gravity * t * t
        local grounded = false
        if y0 < 4 and math.abs(vel.Y) < 10 then
            grounded, py = true, y0
        elseif py <= restY + 0.5 then
            grounded, py = true, restY
        end

        if math.abs(px) < GOAL_WIDTH / 2 and py < 29 then
            return { vel = vel, relVel = relVel, relPos = relPos, grounded = grounded, t = t, px = px, py = py }
        end
    end

    local function disp(v0, T)
        if T <= 0.08 then return v0 * T end
        local t2 = T - 0.08
        if v0 / DECEL_VAL >= t2 then
            return v0 * T - 0.5 * DECEL_VAL * t2 * t2
        end
        return v0 * 0.08 + v0 * v0 / (2 * DECEL_VAL)
    end

    local function speedFor(d, T)
        local lo, hi = 0, Cfg.MaxDiveSpeed
        if disp(hi, T) <= d then return hi end
        for _ = 1, 14 do
            local mid = (lo + hi) / 2
            if disp(mid, T) < d then lo = mid else hi = mid end
        end
        return hi
    end

    local function endDive(restore)
        if diveConn then diveConn:Disconnect() diveConn = nil end
        if diveBV then pcall(function() diveBV:Destroy() end) diveBV = nil end
        if restore and rootPart and rootPart.Parent then
            local v = rootPart.AssemblyLinearVelocity
            rootPart.AssemblyLinearVelocity = Vector3.new(v.X * 0.25, math.min(v.Y, -14), v.Z * 0.25)
            if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
        end
        diving = false
    end

    local function latency()
        local ok, p = pcall(function() return LP:GetNetworkPing() end)
        if ok and type(p) == "number" then return math.clamp(p * Cfg.PingComp, 0, 0.3) end
        return 0
    end

    local function performDive(b, info)
        local now = tick()
        if diving or not ready or now - lastDive < Cfg.Cooldown then return end
        diving, lastDive = true, now

        local root, vel, relVel, relPos = rootPart, info.vel, info.relVel, info.relPos
        local g = workspace.Gravity

        local pTime = math.clamp(math.abs(relPos.Z / math.max(math.abs(relVel.Z), 0.5)), 0.01, 1.5)
        local targetPos = b.Position + vel * pTime
        if info.grounded then
            targetPos = Vector3.new(targetPos.X, info.py, targetPos.Z)
        else
            targetPos = targetPos + Vector3.new(0, -0.5 * g * pTime * pTime, 0)
        end

        local currentRelY = b.Position.Y - root.Position.Y
        local predictedRelY = targetPos.Y - root.Position.Y
        local isAirShot = not info.grounded and ((predictedRelY > 4) or (currentRelY > 4))

        local T = math.clamp(info.t - latency(), 0.08, NUDGE_DURATION)
        local dir = info.px >= 0 and 1 or -1
        local velX = dir * speedFor(math.abs(info.px) + Cfg.ExtraReach, T)
        local animName, dirKey = "DiveL", "l"
        if dir > 0 then animName, dirKey = "DiveR", "r" end

        local diveV, grav
        if isAirShot then
            diveV = math.clamp(AIR_DIVE_MIN + math.max(currentRelY, predictedRelY) * 2.5, AIR_DIVE_MIN, AIR_DIVE_MAX)
            grav = GROUND_GRAVITY
            local h = math.clamp(info.py - root.Position.Y, -3, 4)
            diveV = math.clamp((h + 0.5 * grav * T * T) / T, 0, GROUND_VERTICAL)
        end

        pcall(function() StaminaRemote:FireServer(10) end)
        pcall(function() DiveRemote:FireServer(targetPos, pTime, dirKey) end)

        local anim = animTracks[animName]
        if anim then
            anim.Priority = Enum.AnimationPriority.Action4
            anim:Play(0, 1, math.clamp(1.4 * NUDGE_DURATION / math.max(T, 0.25), 1.4, 2.2))
        end

        humanoid:ChangeState(Enum.HumanoidStateType.Physics)

        endDive(false)
        diving = true
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1, 1, 1) * 2500000
        bv.Parent = root
        diveBV = bv

        root.AssemblyLinearVelocity = root.CFrame:VectorToWorldSpace(Vector3.new(velX, 0, 0)) + Vector3.new(0, diveV, 0)

        local startTime = tick()
        local vx, vv = velX, diveV
        diveConn = RunService.Heartbeat:Connect(function(dt)
            if not running or not root.Parent or not bv.Parent or humanoid.Health <= 0 then
                endDive(false) return
            end
            local elapsed = tick() - startTime
            if elapsed > NUDGE_DURATION then endDive(true) return end
            bv.Velocity = root.CFrame:VectorToWorldSpace(Vector3.new(vx, 0, 0)) + Vector3.new(0, vv, 0)
            if elapsed > 0.08 then
                local step = dt * DECEL_VAL
                if vx > step then vx = vx - step elseif vx < -step then vx = vx + step else vx = 0 end
            end
            vv = vv - dt * grav
        end)
    end

    track(RunService.Heartbeat:Connect(function()
        if not Cfg.Enabled or diving or not ready then return end
        if not rootPart or not rootPart.Parent or humanoid.Health <= 0 then return end
        local ok = diveButtonAvailable()
        if ok ~= areaOk then areaOk = ok end
        if not ok then return end
        local b = getBall()
        if not b or (b.Position - rootPart.Position).Magnitude > Cfg.Range then return end
        local info = incoming(b)
        if info then performDive(b, info) end
    end))

    function Cfg.stop()
        running = false
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        if staminaConn then staminaConn:Disconnect() staminaConn = nil end
        if diving then endDive(true) end
        print("[AutoDive] detenido")
    end

    task.spawn(setup)
    task.spawn(hookStamina)
    track(LP.CharacterAdded:Connect(function()
        ready = false
        task.wait(0.5)
        if not running then return end
        setup()
        task.wait(1)
        hookStamina()
    end))

    task.delay(15, function()
        if running and Cfg.RequireButton and not everFound then
            warn("[AutoDive] No he visto botón '" .. Cfg.DiveButtonName ..
                "'. Usa getgenv().AutoDive.listButtons() y ajusta DiveButtonName.")
        end
    end)

    print("[AutoDive] v4 cargado (controlado por Nova Hub)")
end

local function stopAutoDive()
    if getgenv().AutoDive and getgenv().AutoDive.stop then
        pcall(getgenv().AutoDive.stop)
    end
end

-- ===== Botón Auto Dive en el hub =====
makeCard("Auto Dive", "Blue Lock: Rivals · atajadas automáticas", "🎯", function(on)
    if on then
        startAutoDive()
        notify("Auto Dive activado", C.Green)
    else
        stopAutoDive()
        notify("Auto Dive desactivado", C.Red)
    end
end)

-- ===== Ejemplo: agrega más scripts así =====
-- makeCard("Speed Hack", "Aumenta tu velocidad", "⚡", function(on)
--     if on then
--         -- cargar script
--         notify("Speed activado", C.Green)
--     else
--         -- descargar script
--         notify("Speed desactivado", C.Red)
--     end
-- end)

print("[Nova Hub] Cargado ✦")
notify("Nova Hub v1.0 listo", C.Accent)
