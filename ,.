-- Blue Lock: Rivals — Auto Dive v4 (Remote + BodyVelocity)
-- F6 o botón en pantalla = ON/OFF | getgenv().AutoDive.stop() = apagar todo
-- getgenv().AutoDive.listButtons() = lista los botones de la pantalla (para ajustar DiveButtonName)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

if getgenv().AutoDive and getgenv().AutoDive.stop then
    pcall(getgenv().AutoDive.stop)
end

local Cfg = {
    Enabled = true,
    Cooldown = 2.4,
    MinSpeed = 18,
    Range = 75,
    MaxTime = 3.5,            -- solo se lanza si el balón llega en menos de X segundos
    MaxDiveSpeed = 65.2,      -- velocidad lateral máxima (la del juego original)
    PingComp = 1,             -- compensación de ping al calcular el tiempo útil (0 = apagada)
    ExtraReach = 2,           -- studs extra hacia el lado del balón
    RequireButton = true,     -- solo se lanza si el botón de Dive del juego está visible
    DiveButtonName = "dive",  -- texto que se busca en el nombre/texto del botón
    InfiniteStamina = true,
    ShowButton = true,        -- botón ON/OFF en pantalla (para celular)
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
local diveConn, diveBV, staminaConn, gui, btn
local btnList, lastScan, lastCheck, btnOk, everFound = {}, 0, 0, false, false

local function track(c) conns[#conns + 1] = c return c end

-- Stamina infinita
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

-- Botón de Dive del juego: solo se lanza mientras esté visible (en el área)
local function isShown(obj)
    local cur = obj
    while cur do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function isOurs(d) return gui ~= nil and d:IsDescendantOf(gui) end

local function findDiveButtons()
    local list = {}
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return list end
    local key = string.lower(Cfg.DiveButtonName)
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("GuiButton") and not isOurs(d) then
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
        if d:IsA("GuiButton") and not isOurs(d) then
            print("[AutoDive] botón:", d:GetFullName(), "| visible:", isShown(d),
                "| texto:", d:IsA("TextButton") and d.Text or "-")
        end
    end
end

-- Balón y preparación
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
            warn("[AutoDive] no encontré los remotes del juego:", err)
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

-- Detección: devuelve una tabla si el balón va hacia el arco
local function incoming(b)
    local vel = b.AssemblyLinearVelocity
    if vel.Magnitude < Cfg.MinSpeed then return end

    local cf = rootPart.CFrame
    local relVel = cf:VectorToObjectSpace(vel)
    local relPos = cf:PointToObjectSpace(b.Position)

    -- debe acercarse de frente (se tolera un balón apenas a la altura del portero)
    local ahead = -relPos.Z
    if relVel.Z <= REL_VEL_Z_MIN or ahead < -BEHIND_TOL then return end

    local t = math.max(math.max(ahead, 0) / relVel.Z, 0.03)
    if t > Cfg.MaxTime then return end

    -- altura al llegar. Si el balón rueda, o caería al suelo antes de llegar
    -- (rebota y sigue), se trata como tiro raso en vez de descartarlo
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

-- Lanzamiento
-- Distancia lateral que recorre el lanzamiento en T segundos con velocidad inicial v0
local function disp(v0, T)
    if T <= 0.08 then return v0 * T end
    local t2 = T - 0.08
    if v0 / DECEL_VAL >= t2 then
        return v0 * T - 0.5 * DECEL_VAL * t2 * t2
    end
    return v0 * 0.08 + v0 * v0 / (2 * DECEL_VAL)
end

-- Velocidad justa para recorrer d studs en T segundos (sin pasarse del balón)
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

-- El servidor ve tu movimiento con retraso: se descuenta del tiempo útil
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

    -- datos para el servidor
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

    -- lateral: solo lo necesario para quedar en la trayectoria del balón a tiempo
    local T = math.clamp(info.t - latency(), 0.08, NUDGE_DURATION)
    local dir = info.px >= 0 and 1 or -1
    local velX = dir * speedFor(math.abs(info.px) + Cfg.ExtraReach, T)
    local animName, dirKey = "DiveL", "l"
    if dir > 0 then animName, dirKey = "DiveR", "r" end

    -- vertical: tiros altos como antes; a ras de suelo, a la altura del balón
    local diveV, grav
    if isAirShot then
        diveV = math.clamp(AIR_DIVE_MIN + math.max(currentRelY, predictedRelY) * 2.5, AIR_DIVE_MIN, AIR_DIVE_MAX)
        grav = AIR_GRAVITY
    else
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
            endDive(false)
            return
        end
        local elapsed = tick() - startTime
        if elapsed > NUDGE_DURATION then
            endDive(true)
            return
        end
        bv.Velocity = root.CFrame:VectorToWorldSpace(Vector3.new(vx, 0, 0)) + Vector3.new(0, vv, 0)
        if elapsed > 0.08 then
            local step = dt * DECEL_VAL
            if vx > step then vx = vx - step elseif vx < -step then vx = vx + step else vx = 0 end
        end
        vv = vv - dt * grav
    end)
end

-- Control: botón ON/OFF, bucle principal y apagado
local function refreshButton()
    if not btn then return end
    if not Cfg.Enabled then
        btn.Text, btn.BackgroundColor3 = "Dive: OFF", Color3.fromRGB(75, 78, 95)
    elseif areaOk then
        btn.Text, btn.BackgroundColor3 = "Dive: ON", Color3.fromRGB(60, 190, 110)
    else
        btn.Text, btn.BackgroundColor3 = "Dive: fuera", Color3.fromRGB(200, 140, 40)
    end
end

local function toggle()
    Cfg.Enabled = not Cfg.Enabled
    print("[AutoDive]", Cfg.Enabled and "ON" or "OFF")
    refreshButton()
end

track(RunService.Heartbeat:Connect(function()
    if not Cfg.Enabled or diving or not ready then return end
    if not rootPart or not rootPart.Parent or humanoid.Health <= 0 then return end

    local ok = diveButtonAvailable()
    if ok ~= areaOk then areaOk = ok refreshButton() end
    if not ok then return end

    local b = getBall()
    if not b or (b.Position - rootPart.Position).Magnitude > Cfg.Range then return end

    local info = incoming(b)
    if info then performDive(b, info) end
end))

track(UIS.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.F6 then toggle() end
end))

if Cfg.ShowButton then
    pcall(function()
        gui = Instance.new("ScreenGui")
        gui.Name = "ADToggle"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 999
        btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(92, 34)
        btn.Position = UDim2.new(1, -102, 0, 70)
        btn.AutoButtonColor = false
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Parent = gui
        Instance.new("UICorner", btn)
        refreshButton()
        btn.Activated:Connect(toggle)
        gui.Parent = LP:WaitForChild("PlayerGui", 5)
    end)
end

function Cfg.stop()
    running = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if staminaConn then staminaConn:Disconnect() staminaConn = nil end
    if diving then endDive(true) end
    if gui then pcall(function() gui:Destroy() end) end
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
        warn("[AutoDive] No he visto ningún botón con '" .. Cfg.DiveButtonName ..
            "'. Si estás en el área, usa getgenv().AutoDive.listButtons() y cambia DiveButtonName.")
    end
end)

print("[AutoDive] v4 cargado | F6 o botón = ON/OFF")
