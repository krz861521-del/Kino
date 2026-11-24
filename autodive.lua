-- Config.lua
local Config = {}

-- Valores por defecto
Config.Defaults = {
    WalkSpeed = 16,
    JumpPower = 50,
    FlySpeed = 50,
    BallESP = true,
    PlayerESP = false,
    FullBright = false,
    AntiAFK = true,
}

-- Ruta del archivo de guardado (usando la API de Rayfield)
Config.SaveFile = "BlueLockRivals_Config.json"

-- Función para cargar configuración guardada (si existe)
function Config.load()
    local success, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(
            readfile(Config.SaveFile)
        )
    end)
    if success and type(data) == "table" then
        for k, v in pairs(data) do
            if Config.Defaults[k] ~= nil then
                Config.Defaults[k] = v
            end
        end
    end
    return Config.Defaults
end

-- Función para guardar la configuración actual
function Config.save(current)
    local success, err = pcall(function()
        writefile(Config.SaveFile, game:GetService("HttpService"):JSONEncode(current))
    end)
    if not success then
        warn("[BlueLockRivals] No se pudo guardar la configuración: " .. tostring(err))
    end
end

return Config
-- Modules/Utilities.lua
local Utilities = {}

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- FullBright
function Utilities.setFullBright(enabled)
    if enabled then
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    else
        Lighting.Ambient = Color3.fromRGB(0, 0, 0)
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    end
end

-- Anti‑AFK (evita el kick por inactividad)
local antiAFKConnection
function Utilities.setAntiAFK(enabled)
    if enabled and not antiAFKConnection then
        antiAFKConnection = game:GetService("RunService").Heartbeat:Connect(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    elseif not enabled and antiAFKConnection then
        antiAFKConnection:Disconnect()
        antiAFKConnection = nil
    end
end

-- Teleport a una posición fija (spawn)
function Utilities.teleportToSpawn()
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(0, 5, 0) -- Ajusta según el mapa
    end
end

return Utilities

-- Modules/PlayerEnhancer.lua
local PlayerEnhancer = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- Infinite Stamina (modifica el valor local, puede no replicarse)
function PlayerEnhancer.setInfiniteStamina(enabled)
    local char = player.Character
    if not char then return end
    local stamina = char:FindFirstChild("Stamina") -- nombre típico en el juego
    if stamina and stamina:IsA("NumberValue") then
        if enabled then
            stamina.Value = math.huge
        else
            stamina.Value = 100 -- valor por defecto aproximado
        end
    end
end

-- WalkSpeed
function PlayerEnhancer.setWalkSpeed(speed)
    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.WalkSpeed = speed
    end
end

-- JumpPower
function PlayerEnhancer.setJumpPower(power)
    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.JumpPower = power
        char.Humanoid.UseJumpPower = true
    end
end

-- Fly (modo vuelo básico usando BodyVelocity)
local flyConnection
function PlayerEnhancer.setFly(enabled, speed)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if enabled then
        if flyConnection then return end
        local bv = Instance.new("BodyVelocity")
        bv.Name = "FlyBV"
        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bv.Velocity = Vector3.zero
        bv.Parent = hrp

        flyConnection = RunService.RenderStepped:Connect(function()
            local cam = workspace.CurrentCamera
            local move = Vector3.zero
            if game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.W) then
                move += cam.CFrame.LookVector
            end
            if game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.S) then
                move -= cam.CFrame.LookVector
            end
            if game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.A) then
                move -= cam.CFrame.RightVector
            end
            if game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.D) then
                move += cam.CFrame.RightVector
            end
            if game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.Space) then
                move += Vector3.new(0, 1, 0)
            end
            bv.Velocity = move * (speed or 50)
        end)
    else
        if flyConnection then
            flyConnection:Disconnect()
            flyConnection = nil
        end
        local bv = hrp:FindFirstChild("FlyBV")
        if bv then bv:Destroy() end
    end
end

return PlayerEnhancer

-- Modules/BallController.lua
local BallController = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

-- Referencia al servicio del balón (según scripts públicos)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BallService = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("BallService")
local BallRE = BallService:WaitForChild("RE")

-- Encuentra el balón en el workspace
local function getFootball()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name == "Football" then
            return obj
        end
    end
    return nil
end

-- Teleport al balón
function BallController.teleportToBall()
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local ball = getFootball()
    if ball and ball:FindFirstChild("Handle") then
        hrp.CFrame = ball.Handle.CFrame + Vector3.new(0, 5, 0)
    end
end

-- Auto‑Goal: cuando el jugador tiene el balón, lo envía a la portería
function BallController.setAutoGoal(enabled)
    if enabled then
        -- Lógica basada en el script público: tween hacia la portería
        -- (Se simplifica para evitar errores si la portería no existe)
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        -- Buscar portería (nombre típico "HomeGK" o "AwayGK")
        local goals = workspace:FindFirstChild("Goals")
        if goals then
            local target = goals:FindFirstChild("HomeGK") or goals:FindFirstChild("AwayGK")
            if target then
                local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
                local tween = TweenService:Create(hrp, tweenInfo, {CFrame = target.CFrame})
                tween:Play()
            end
        end
    end
end

-- Auto‑Steal: posicionamiento predictivo (simplificado)
function BallController.setAutoSteal(enabled)
    if enabled then
        local ball = getFootball()
        if ball and ball:FindFirstChild("Handle") then
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                char.HumanoidRootPart.CFrame = ball.Handle.CFrame + Vector3.new(0, 0, 3)
            end
        end
    end
end

return BallController

-- Modules/ESP.lua
local ESP = {}

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Resaltado del balón
function ESP.setBallESP(enabled)
    local ball = workspace:FindFirstChild("Football")
    if not ball then return end
    if enabled then
        local highlight = ball:FindFirstChild("BallHighlight") or Instance.new("Highlight")
        highlight.Name = "BallHighlight"
        highlight.FillColor = Color3.fromRGB(255, 215, 0)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.Parent = ball
    else
        local highlight = ball:FindFirstChild("BallHighlight")
        if highlight then highlight:Destroy() end
    end
end

-- ESP de jugadores (cajas simples usando Highlight)
function ESP.setPlayerESP(enabled)
    for _, other in pairs(Players:GetPlayers()) do
        if other ~= player and other.Character then
            local char = other.Character
            if enabled then
                if not char:FindFirstChild("PlayerHighlight") then
                    local hl = Instance.new("Highlight")
                    hl.Name = "PlayerHighlight"
                    hl.FillColor = Color3.fromRGB(255, 0, 0)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.Parent = char
                end
            else
                local hl = char:FindFirstChild("PlayerHighlight")
                if hl then hl:Destroy() end
            end
        end
    end
end

return ESP
-- UI/RayfieldLoader.lua
local RayfieldLoader = {}

function RayfieldLoader.load()
    local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Rayfield/main/source'))()
    return Rayfield
end

return RayfieldLoader

-- Main.lua
-- Punto de entrada: carga la configuración, la UI y conecta los módulos.

local Config = require(script.Parent.Config)
local Utilities = require(script.Parent.Modules.Utilities)
local PlayerEnhancer = require(script.Parent.Modules.PlayerEnhancer)
local BallController = require(script.Parent.Modules.BallController)
local ESP = require(script.Parent.Modules.ESP)
local RayfieldLoader = require(script.Parent.UI.RayfieldLoader)

-- Cargar valores guardados
local currentConfig = Config.load()

-- Cargar Rayfield
local Rayfield = RayfieldLoader.load()

-- Crear ventana principal
local Window = Rayfield:CreateWindow({
    Name = "Blue Lock: Rivals — Hub Profesional",
    LoadingTitle = "Cargando módulos...",
    LoadingSubtitle = "por tu nombre",
    Theme = "Default",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "BlueLockRivals",
        FileName = "Config"
    },
    KeySystem = false
})

-- Pestaña "Jugador"
local PlayerTab = Window:CreateTab("Jugador", 0)
local PlayerSection = PlayerTab:CreateSection("Movimiento")

PlayerTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 100},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = currentConfig.WalkSpeed,
    Flag = "WalkSpeed",
    Callback = function(value)
        currentConfig.WalkSpeed = value
        PlayerEnhancer.setWalkSpeed(value)
    end,
})

PlayerTab:CreateSlider({
    Name = "JumpPower",
    Range = {50, 200},
    Increment = 5,
    Suffix = "power",
    CurrentValue = currentConfig.JumpPower,
    Flag = "JumpPower",
    Callback = function(value)
        currentConfig.JumpPower = value
        PlayerEnhancer.setJumpPower(value)
    end,
})

PlayerTab:CreateToggle({
    Name = "Stamina Infinita",
    CurrentValue = false,
    Flag = "InfStamina",
    Callback = function(state)
        PlayerEnhancer.setInfiniteStamina(state)
    end,
})

PlayerTab:CreateToggle({
    Name = "Vuelo (Fly)",
    CurrentValue = false,
    Flag = "Fly",
    Callback = function(state)
        PlayerEnhancer.setFly(state, currentConfig.FlySpeed)
    end,
})

PlayerTab:CreateSlider({
    Name = "Velocidad de vuelo",
    Range = {10, 200},
    Increment = 5,
    Suffix = "speed",
    CurrentValue = currentConfig.FlySpeed,
    Flag = "FlySpeed",
    Callback = function(value)
        currentConfig.FlySpeed = value
    end,
})

-- Pestaña "Balón"
local BallTab = Window:CreateTab("Balón", 0)
local BallSection = BallTab:CreateSection("Control del balón")

BallTab:CreateButton({
    Name = "Teleport al balón",
    Callback = function()
        BallController.teleportToBall()
    end,
})

BallTab:CreateToggle({
    Name = "Auto‑Goal (con posesión)",
    CurrentValue = false,
    Flag = "AutoGoal",
    Callback = function(state)
        BallController.setAutoGoal(state)
    end,
})

BallTab:CreateToggle({
    Name = "Auto‑Steal",
    CurrentValue = false,
    Flag = "AutoSteal",
    Callback = function(state)
        BallController.setAutoSteal(state)
    end,
})

-- Pestaña "Visuales"
local VisualTab = Window:CreateTab("Visuales", 0)
local VisualSection = VisualTab:CreateSection("ESP y entorno")

VisualTab:CreateToggle({
    Name = "Ball ESP",
    CurrentValue = currentConfig.BallESP,
    Flag = "BallESP",
    Callback = function(state)
        currentConfig.BallESP = state
        ESP.setBallESP(state)
    end,
})

VisualTab:CreateToggle({
    Name = "Player ESP",
    CurrentValue = currentConfig.PlayerESP,
    Flag = "PlayerESP",
    Callback = function(state)
        currentConfig.PlayerESP = state
        ESP.setPlayerESP(state)
    end,
})

VisualTab:CreateToggle({
    Name = "FullBright",
    CurrentValue = currentConfig.FullBright,
    Flag = "FullBright",
    Callback = function(state)
        currentConfig.FullBright = state
        Utilities.setFullBright(state)
    end,
})

-- Pestaña "Utilidades"
local UtilTab = Window:CreateTab("Utilidades", 0)
local UtilSection = UtilTab:CreateSection("Varios")

UtilTab:CreateToggle({
    Name = "Anti‑AFK",
    CurrentValue = currentConfig.AntiAFK,
    Flag = "AntiAFK",
    Callback = function(state)
        currentConfig.AntiAFK = state
        Utilities.setAntiAFK(state)
    end,
})

UtilTab:CreateButton({
    Name = "Teleport a Spawn",
    Callback = function()
        Utilities.teleportToSpawn()
    end,
})

-- Guardar configuración al cerrar (Rayfield ya lo hace automáticamente,
-- pero forzamos un guardado manual por si acaso)
game:GetService("Players").LocalPlayer.OnTeleport:Connect(function()
    Config.save(currentConfig)
end)

Rayfield:Notify({
    Title = "Blue Lock: Rivals Hub",
    Content = "Script cargado correctamente. Usa las pestañas para configurar.",
    Duration = 5,
    Image = nil,
})
