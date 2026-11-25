--[[
    AUTO AIM v1 — Asistencia de tiro para Blue Lock: Rivals
    Cuando estás cerca de la portería y tienes el balón, el tiro se redirige a un punto
    aleatorio del marco: escuadras, esquinas bajas o centro.

    Cómo funciona: intercepta el RemoteEvent de disparo (Shoot / shoot_event) y reescribe
    el vector/posición/CFrame objetivo antes de enviarlo al servidor.

    Importante: no conozco los argumentos exactos de esos remotos. El modo "auto" usa una
    heurística. Si el tiro no se desvía, pon Debug = true, dispara una vez, mira en la
    consola qué argumentos manda el juego y ajusta ArgMode / ArgIndex.

    API: getgenv().AutoAim.Enabled = true/false | .preview() | .setRange(n) | .stop()
]]

--==========================================================================
-- 1. SERVICIOS
--==========================================================================
local function getService(name)
    local ok, svc = pcall(function() return game:GetService(name) end)
    return ok and svc or nil
end

local Players = getService("Players")
local RunService = getService("RunService")
local UIS = getService("UserInputService")
local Workspace = getService("Workspace")
local LP = Players and Players.LocalPlayer
if not (Players and RunService and UIS and Workspace and LP) then
    warn("[AutoAim] no pude acceder a los servicios de Roblox")
    return
end

-- Si ya había una copia corriendo, se apaga antes de empezar
if getgenv().AutoAim and getgenv().AutoAim.stop then
    pcall(getgenv().AutoAim.stop)
end

--==========================================================================
-- 2. CONFIGURACIÓN
--==========================================================================
local Cfg = {
    Enabled = true,

    -- Distancia (studs, en horizontal) a la portería para que la ayuda se active
    MinDistance = 15,
    MaxDistance = 60,
    SliderMin = 30,            -- límites del deslizador de la GUI para MaxDistance
    SliderMax = 120,

    -- Búsqueda de la portería (nombres en minúsculas)
    GoalNames = { "goal", "goals", "rim", "arco", "porteria" },
    PartialMatch = false,      -- true = basta con que el nombre contenga alguno
    RequireFacing = true,      -- solo la portería que tienes delante (cámara)
    FacingDot = 0.2,           -- 1 = justo de frente, 0 = de lado

    -- Balón y posesión
    BallName = "Football",
    PossessionDistance = 9,    -- si el juego no marca dueño, "tienes el balón" = estar a esta distancia
    OwnerKeys = { "Owner", "Possessor", "Holder", "BallOwner" },   -- atributos/valores que se revisan
    HasBallCheck = nil,        -- opcional: function(ball, root) return true/false end

    -- Remotos de disparo (por nombre; sirve para el sistema Legacy y el nuevo)
    RemoteNames = { Shoot = true, shoot_event = true },
    ArgMode = "auto",          -- "auto" | "direction" | "position"
    ArgIndex = nil,            -- número de argumento a reescribir (nil = automático)
    AimStrength = 1,           -- 1 = va exacto al punto; 0.7 = mezcla con tu tiro original
    ShotWindow = 0.35,         -- si el juego manda 2 remotos por tiro, ambos usan el mismo punto

    -- Puntos de destino. u: -0.5 (izquierda) a 0.5 (derecha) | v: 0 (césped) a 1 (travesaño)
    Targets = {
        { name = "Escuadra izquierda", u = -0.40, v = 0.86, weight = 1.0 },
        { name = "Escuadra derecha",   u =  0.40, v = 0.86, weight = 1.0 },
        { name = "Inferior izquierda", u = -0.36, v = 0.14, weight = 1.0 },
        { name = "Inferior derecha",   u =  0.36, v = 0.14, weight = 1.0 },
        { name = "Centro",             u =  0.00, v = 0.50, weight = 0.6 },
    },
    Jitter = 0.05,             -- variación aleatoria alrededor de cada punto
    Margin = 0.06,             -- nunca más cerca que esto del borde del marco
    DepthFactor = 0,           -- 0 = centro del marco; >0 = más adentro de la red

    -- Alternativa sin hook: apunta la cámara al pulsar disparo (experimental)
    InputFallback = true,
    ShootInputs = { Enum.UserInputType.MouseButton1 },

    ShowGui = true,
    Debug = false,
}
getgenv().AutoAim = Cfg

--==========================================================================
-- 3. ESTADO
--==========================================================================
local running = true
local conns = {}
local rng = Random.new(os.time())
local hooked = false

local State = {
    ready = false,             -- ¿se cumplen todas las condiciones ahora mismo?
    status = "Iniciando",
    root = nil, ball = nil, ballRoot = nil,
    goal = nil, frame = nil,
    preset = nil,              -- próximo destino ya elegido (aleatorio)
    shotPoint = nil, shotAt = 0,
}
local goals = {}               -- [Instance] = true
local boundsCache = {}
local lastPreset
local debugShots = 0

local function track(c) conns[#conns + 1] = c return c end

--==========================================================================
-- 4. FUNCIONES AUXILIARES: PORTERÍA
--==========================================================================
local function nameMatches(n)
    n = string.lower(n)
    for _, key in ipairs(Cfg.GoalNames) do
        if n == key or (Cfg.PartialMatch and string.find(n, key, 1, true)) then return true end
    end
    return false
end

-- Registra una portería. Si hay un modelo "Goal" con piezas "Goal" dentro, se queda el modelo.
local function considerGoal(inst)
    if goals[inst] then return end
    local okType = inst:IsA("BasePart") or inst:IsA("Model")
    if not (okType and nameMatches(inst.Name)) then return end
    local p = inst.Parent
    while p and p ~= Workspace do
        if goals[p] then return end
        p = p.Parent
    end
    for g in pairs(goals) do
        if g:IsDescendantOf(inst) then goals[g] = nil boundsCache[g] = nil end
    end
    goals[inst] = true
end

local function scanGoals()
    local ok, list = pcall(function() return Workspace:GetDescendants() end)
    if ok then
        for _, d in ipairs(list) do pcall(considerGoal, d) end
    end
end

-- CFrame y tamaño de una portería (con caché de 1 s)
local function boundsOf(inst)
    local c = boundsCache[inst]
    local now = tick()
    if c and now - c.t < 1 then return c.cf, c.size end
    local ok, cf, size = pcall(function()
        if inst:IsA("Model") then return inst:GetBoundingBox() end
        return inst.CFrame, inst.Size
    end)
    if ok and cf and size then
        boundsCache[inst] = { t = now, cf = cf, size = size }
        return cf, size
    end
end

local function flatUnit(v, fallback)
    local f = Vector3.new(v.X, 0, v.Z)
    if f.Magnitude < 0.01 then return fallback end
    return f.Unit
end

-- Ejes del marco: el lado horizontal más largo es el ancho; el otro, la profundidad
local function frameOf(cf, size)
    local right = flatUnit(cf.RightVector, Vector3.new(1, 0, 0))
    local look = flatUnit(cf.LookVector, Vector3.new(0, 0, -1))
    if size.X >= size.Z then
        return { center = cf.Position, w = right, d = look, width = size.X, depth = size.Z, height = size.Y }
    end
    return { center = cf.Position, w = look, d = right, width = size.Z, depth = size.X, height = size.Y }
end

-- Elige la portería válida (distancia + de frente) más alineada con tu vista
local function pickGoal(pos, lookVec)
    local best, bestScore
    for inst in pairs(goals) do
        if inst.Parent then
            local cf, size = boundsOf(inst)
            if cf then
                local flat = Vector3.new(cf.Position.X - pos.X, 0, cf.Position.Z - pos.Z)
                local dist = flat.Magnitude
                if dist >= Cfg.MinDistance and dist <= Cfg.MaxDistance then
                    local facing = dist > 0.01 and lookVec:Dot(flat.Unit) or 1
                    if (not Cfg.RequireFacing or facing >= Cfg.FacingDot) and (not bestScore or facing > bestScore) then
                        best, bestScore = { inst = inst, cf = cf, size = size, dist = dist }, facing
                    end
                end
            end
        end
    end
    return best
end

--==========================================================================
-- 5. FUNCIONES AUXILIARES: OBJETIVO ALEATORIO
--==========================================================================
-- Elige un destino por peso, sin repetir el anterior (para que sea impredecible)
local function rollPreset()
    local total = 0
    for _, t in ipairs(Cfg.Targets) do
        if t ~= lastPreset then total = total + t.weight end
    end
    local r = rng:NextNumber() * total
    for _, t in ipairs(Cfg.Targets) do
        if t ~= lastPreset then
            r = r - t.weight
            if r <= 0 then lastPreset = t return t end
        end
    end
    lastPreset = Cfg.Targets[1]
    return lastPreset
end

-- Convierte un destino (u, v) en un punto 3D dentro del marco, visto desde el tirador
local function targetPoint(frame, preset, shooterPos)
    local toGoal = Vector3.new(frame.center.X - shooterPos.X, 0, frame.center.Z - shooterPos.Z)
    local fwd = toGoal.Magnitude > 0.01 and toGoal.Unit or frame.d
    local right = fwd:Cross(Vector3.new(0, 1, 0))      -- tu derecha
    local w, d = frame.w, frame.d
    if w:Dot(right) < 0 then w = -w end                -- +u siempre = tu derecha
    if d:Dot(fwd) < 0 then d = -d end                  -- +profundidad = hacia la red

    local m = Cfg.Margin
    local u = math.clamp(preset.u + (rng:NextNumber() - 0.5) * 2 * Cfg.Jitter, -0.5 + m, 0.5 - m)
    local v = math.clamp(preset.v + (rng:NextNumber() - 0.5) * 2 * Cfg.Jitter, m, 1 - m)
    return frame.center
        + w * (u * frame.width)
        + Vector3.new(0, (v - 0.5) * frame.height, 0)
        + d * (frame.depth * Cfg.DepthFactor)
end

-- Punto de este tiro. Si ya se pidió hace un instante (2 remotos por tiro), se reutiliza
local function takeShotPoint()
    local now = tick()
    if State.shotPoint and now - State.shotAt < Cfg.ShotWindow then return State.shotPoint end
    local preset = State.preset or rollPreset()
    State.shotPoint = targetPoint(State.frame, preset, State.root.Position)
    State.shotName, State.shotAt = preset.name, now
    State.preset = nil              -- el siguiente tiro tendrá otro destino
    return State.shotPoint
end

--==========================================================================
-- 6. FUNCIONES AUXILIARES: BALÓN, POSESIÓN, DISTANCIA
--==========================================================================
local function getBall()
    if State.ball and State.ball.Parent then return State.ball end
    local f = Workspace:FindFirstChild(Cfg.BallName) or Workspace:FindFirstChild(Cfg.BallName, true)
    if not f then return nil end
    State.ball = f:IsA("BasePart") and f
        or f:FindFirstChild("Hitbox") or f:FindFirstChild("BALL") or f:FindFirstChildWhichIsA("BasePart")
    State.ballRoot = f
    return State.ball
end

local function ownerMatches(v)
    return v == LP or v == LP.Name or v == LP.UserId or (LP.Character ~= nil and v == LP.Character)
end

-- ¿Tienes el balón? Usa el dueño que marque el juego; si no hay, la distancia
local function hasBall(root, ball)
    if Cfg.HasBallCheck then
        local ok, res = pcall(Cfg.HasBallCheck, ball, root)
        if ok then return res and true or false end
    end
    for _, key in ipairs(Cfg.OwnerKeys) do
        local attr = ball:GetAttribute(key)
        if attr ~= nil then return ownerMatches(attr) end
        local holder = ball:FindFirstChild(key) or (State.ballRoot and State.ballRoot:FindFirstChild(key))
        if holder and holder:IsA("ValueBase") then return ownerMatches(holder.Value) end
    end
    return (ball.Position - root.Position).Magnitude <= Cfg.PossessionDistance
end

--==========================================================================
-- 7. DETECCIÓN Y REDIRECCIÓN DEL DISPARO
--==========================================================================
local function describe(args)
    local out = {}
    for i = 1, args.n do out[i] = i .. "=" .. typeof(args[i]) .. ":" .. tostring(args[i]) end
    return table.concat(out, " | ")
end

local function blend(original, desired) return original:Lerp(desired, Cfg.AimStrength) end

-- Devuelve una copia de los argumentos con el destino sustituido (o nil si no hay qué cambiar)
local function rewriteArgs(remote, args)
    local point = takeShotPoint()
    local origin = State.ball and State.ball.Position or State.root.Position
    local desired = point - origin
    if desired.Magnitude < 0.5 then return nil end

    if Cfg.Debug and debugShots < 10 then
        debugShots = debugShots + 1
        print("[AutoAim] " .. remote.Name .. " -> " .. describe(args) .. " | destino: " .. (State.shotName or "?"))
    end

    local out = { n = args.n }
    local changed = false
    local positions = {}
    for i = 1, args.n do
        local a = args[i]
        out[i] = a
        if Cfg.ArgIndex == nil or Cfg.ArgIndex == i then
            local t = typeof(a)
            if t == "Vector3" then
                local mag = a.Magnitude
                local asDir = Cfg.ArgMode == "direction" or (Cfg.ArgMode == "auto" and mag > 0.5 and mag <= 1.5)
                local asPos = Cfg.ArgMode == "position" or (Cfg.ArgMode == "auto" and mag > 1.5)
                if asDir then
                    out[i] = blend(a, desired.Unit).Unit
                    changed = true
                elseif asPos then
                    positions[#positions + 1] = i
                end
            elseif t == "CFrame" then
                out[i] = a:Lerp(CFrame.lookAt(a.Position, a.Position + desired), Cfg.AimStrength)
                changed = true
            end
        end
    end

    -- Posiciones: en modo auto solo si hay una única y está lejos de ti (es un destino, no un origen)
    if #positions > 0 then
        local explicit = Cfg.ArgMode == "position" or Cfg.ArgIndex ~= nil
        if explicit or (#positions == 1 and (args[positions[1]] - State.root.Position).Magnitude > 8) then
            for _, i in ipairs(positions) do
                out[i] = blend(args[i], point)
                changed = true
            end
        end
    end
    return changed and out or nil
end

-- Hook al RemoteEvent: se ejecuta cada vez que el juego llama FireServer/InvokeServer
local function installHook()
    if not (hookmetamethod and getnamecallmethod) then return false end
    local ok, err = pcall(function()
        local old
        local function handler(self, ...)
            local method = getnamecallmethod()
            if running and Cfg.Enabled and State.ready and typeof(self) == "Instance"
                and (method == "FireServer" or method == "InvokeServer")
                and Cfg.RemoteNames[self.Name] then
                local cls = self.ClassName
                if cls == "RemoteEvent" or cls == "RemoteFunction" then
                    local okR, newArgs = pcall(rewriteArgs, self, table.pack(...))
                    if okR and newArgs then
                        return old(self, table.unpack(newArgs, 1, newArgs.n))
                    end
                end
            end
            return old(self, ...)
        end
        old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(handler) or handler)
    end)
    if not ok then warn("[AutoAim] no pude instalar el hook:", err) end
    return ok
end

-- Alternativa sin hook: al pulsar disparo, gira la cámara hacia el punto (experimental)
local function onInput(input)
    if hooked or not Cfg.InputFallback or not Cfg.Enabled or not State.ready then return end
    for _, s in ipairs(Cfg.ShootInputs) do
        if input.UserInputType == s or input.KeyCode == s then
            local cam = Workspace.CurrentCamera
            if cam then
                local cur = cam.CFrame
                cam.CFrame = cur:Lerp(CFrame.lookAt(cur.Position, takeShotPoint()), Cfg.AimStrength)
            end
            return
        end
    end
end

--==========================================================================
-- 8. BUCLE PRINCIPAL: evalúa las condiciones en cada frame
--==========================================================================
local function step()
    State.ready = false
    if not Cfg.Enabled then State.status = "Apagado" return end

    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then State.status = "Sin personaje" return end
    State.root = root

    local ball = getBall()
    if not ball then State.status = "Sin balón en el mapa" return end

    local cam = Workspace.CurrentCamera
    local lookVec = flatUnit(cam and cam.CFrame.LookVector or root.CFrame.LookVector, Vector3.new(0, 0, -1))
    local goal = pickGoal(root.Position, lookVec)
    if not goal then State.status = "Fuera de rango" State.preset = nil return end
    if not hasBall(root, ball) then State.status = "Sin balón" return end

    if State.goal ~= goal.inst then State.goal = goal.inst State.preset = nil end
    State.frame = frameOf(goal.cf, goal.size)
    State.ready = true
    State.status = string.format("Listo · %d st", math.floor(goal.dist + 0.5))
    if not State.preset then State.preset = rollPreset() end
end

-- Muestra un destino de prueba (sin disparar) para comprobar que cae dentro del marco
function Cfg.preview()
    if not State.frame or not State.root then return nil end
    local preset = rollPreset()
    return preset.name, targetPoint(State.frame, preset, State.root.Position)
end

--==========================================================================
-- 9. GUI DE CONTROL: botón ON/OFF + deslizador del rango
--==========================================================================
local gui, toggleBtn, rangeLabel, statusLabel, fill, knob

local function setMaxDistance(v)
    Cfg.MaxDistance = math.clamp(math.floor(v + 0.5), Cfg.SliderMin, Cfg.SliderMax)
    if rangeLabel then rangeLabel.Text = "Rango máx: " .. Cfg.MaxDistance .. " st" end
    if fill and knob then
        local a = (Cfg.MaxDistance - Cfg.SliderMin) / (Cfg.SliderMax - Cfg.SliderMin)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
    end
end
Cfg.setRange = setMaxDistance

local function refreshGui()
    if not toggleBtn then return end
    toggleBtn.Text = Cfg.Enabled and "Auto Aim: ON" or "Auto Aim: OFF"
    toggleBtn.BackgroundColor3 = Cfg.Enabled and Color3.fromRGB(60, 190, 110) or Color3.fromRGB(75, 78, 95)
    statusLabel.Text = State.status
end

local function buildGui()
    gui = Instance.new("ScreenGui")
    gui.Name = "AutoAimPanel"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 997

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(190, 126)
    panel.Position = UDim2.new(0, 10, 0.5, -63)
    panel.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel)

    local function label(text, y, size, bold)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Position = UDim2.fromOffset(10, y)
        l.Size = UDim2.fromOffset(170, 16)
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        l.TextSize = size
        l.TextColor3 = Color3.fromRGB(235, 235, 240)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = text
        l.Parent = panel
        return l
    end

    label("Auto Aim", 6, 13, true)

    toggleBtn = Instance.new("TextButton")
    toggleBtn.Position = UDim2.fromOffset(10, 28)
    toggleBtn.Size = UDim2.fromOffset(170, 28)
    toggleBtn.AutoButtonColor = false
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 12
    toggleBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleBtn.Parent = panel
    Instance.new("UICorner", toggleBtn)
    toggleBtn.Activated:Connect(function()
        Cfg.Enabled = not Cfg.Enabled
        refreshGui()
    end)

        rangeLabel = label("", 62, 11, false)
     -- Deslizador (ratón y táctil)
    local trackBar = Instance.new("Frame")
    trackBar.Position = UDim2.fromOffset(10, 90)
    trackBar.Size = UDim2.fromOffset(170, 8)
    trackBar.BackgroundColor3 = Color3.fromRGB(75, 78, 95)
    trackBar.BorderSizePixel = 0
    trackBar.Parent = panel
    Instance.new("UICorner", trackBar)

    fill = Instance.new("Frame")
    fill.BackgroundColor3 = Color3.fromRGB(70, 130, 255)
    fill.BorderSizePixel = 0
    fill.Parent = trackBar
    Instance.new("UICorner", fill)

    knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(16, 16)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = trackBar
    Instance.new("UICorner", knob)

    statusLabel = label("", 104, 10, false)
    statusLabel.TextColor3 = Color3.fromRGB(150, 155, 175)

    local dragging = false
    local function fromX(x)
        local a = math.clamp((x - trackBar.AbsolutePosition.X) / trackBar.AbsoluteSize.X, 0, 1)
        setMaxDistance(Cfg.SliderMin + a * (Cfg.SliderMax - Cfg.SliderMin))
    end
    trackBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(input.Position.X)
        end
    end)
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromX(input.Position.X)
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    setMaxDistance(Cfg.MaxDistance)
    refreshGui()

    -- Montaje: PlayerGui primero; si falla, gethui/CoreGui
    local parent = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
    if not (parent and pcall(function() gui.Parent = parent end)) then
        pcall(function() gui.Parent = gethui and gethui() or getService("CoreGui") end)
    end
end

--==========================================================================
-- 10. CONEXIONES, ARRANQUE Y LIMPIEZA
--==========================================================================
scanGoals()
track(Workspace.DescendantAdded:Connect(function(d) pcall(considerGoal, d) end))
track(Workspace.DescendantRemoving:Connect(function(d)
    if goals[d] then goals[d] = nil boundsCache[d] = nil end
end))

local guiTimer = 0
track(RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    step()
    guiTimer = guiTimer + dt
    if guiTimer > 0.2 then guiTimer = 0 refreshGui() end
end))

track(UIS.InputBegan:Connect(function(input) pcall(onInput, input) end))

-- Si el personaje muere o se reinicia, se limpia el estado del tiro
track(LP.CharacterRemoving:Connect(function()
    State.ready, State.preset, State.shotPoint, State.root = false, nil, nil, nil
end))

hooked = installHook()
if not hooked then
    warn("[AutoAim] tu ejecutor no soporta hookmetamethod: solo funciona la alternativa por cámara.")
end

if Cfg.ShowGui then
    local ok, err = pcall(buildGui)
    if not ok then warn("[AutoAim] error al crear la GUI:", err) end
end

-- Apagado: desconecta todo. El hook queda como paso directo (running = false)
function Cfg.stop()
    running = false
    Cfg.Enabled = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if gui then pcall(function() gui:Destroy() end) end
    print("[AutoAim] detenido")
end

print("[AutoAim] v1 cargado · hook: " .. (hooked and "sí" or "no"))
