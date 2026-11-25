--[[
    BLR Custom Hub v1.0
    Funciones: Anti Ragdoll, CFrame Speed (Toggle + Slider), Auto Dribble (Rango).
    Basado en la estética de Exuso Hub.
]]

--==========================================================================
-- 1. SERVICIOS Y VARIABLES
--==========================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Configuración inicial
local Config = {
    AntiRagdoll = false,
    CFrameSpeed = false,
    CFramesSpeedValue = 0.15,
    AutoDribble = false,
    DribbleRange = 23,
}

-- Estado
local Connections = {}
local CurrentBall = nil
local IsDribbling = false

--==========================================================================
-- 2. LÓGICA: ANTI RAGDOLL
--==========================================================================
-- El ragdoll en Roblox se controla cambiando el estado del Humanoid o aplicando fuerzas.
-- Este bucle fuerza al personaje a estar de pie y elimina cualquier fuerza externa.
local function AntiRagdollLoop()
    if not Config.AntiRagdoll then return end
    local char = LP.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    
    if hum and root then
        -- Forzar estado de estar de pie
        if hum:GetState() == Enum.HumanoidStateType.Physics or hum:GetState() == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        
        -- Eliminar fuerzas que puedan estar causando el ragdoll
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyAngularVelocity") or v:IsA("BodyForce") then
                v:Destroy()
            end
        end
        -- Restablecer la posición si se está cayendo
        if root.Velocity.Y < -50 then
            root.Velocity = Vector3.new(0, 0, 0)
        end
    end
end

--==========================================================================
-- 3. LÓGICA: CFrame SPEED (Y TOGGLE)
--==========================================================================
-- El CFrame Speed mueve el personaje directamente, ignorando la física.
-- Esto permite atravesar paredes y moverse más rápido de lo normal.
local function CFrameSpeedLoop()
    if not Config.CFrameSpeed then return end
    local char = LP.Character
    if not char then return end
    
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    -- Obtener la dirección del movimiento
    local moveDir = Vector3.new()
    if UIS:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
    
    if moveDir.Magnitude > 0 then
        moveDir = moveDir.Unit
        -- Aplicar el movimiento basado en el valor del slider
        local speed = Config.CFramesSpeedValue
        root.CFrame = root.CFrame + (moveDir * speed)
    end
end

--==========================================================================
-- 4. LÓGICA: AUTO DRIBBLE (RANGO)
--==========================================================================
-- Busca el balón y, si está dentro del rango, lo teletransporta al jugador
-- o empuja al oponente. En este caso, hacemos un "magnetismo" del balón.
local function GetBall()
    if CurrentBall and CurrentBall.Parent then return CurrentBall end
    -- Buscar el balón en el workspace
    local ball = Workspace:FindFirstChild("Football") or Workspace:FindFirstChild("SoccerBall")
    if ball then
        -- Si es un modelo, buscar la parte principal
        CurrentBall = ball:IsA("BasePart") and ball or ball:FindFirstChildWhichIsA("BasePart")
    end
    return CurrentBall
end

local function AutoDribbleLoop()
    if not Config.AutoDribble then return end
    local char = LP.Character
    if not char then return end
    
    local root = char:FindFirstChild("HumanoidRootPart")
    local ball = GetBall()
    
    if root and ball then
        local dist = (ball.Position - root.Position).Magnitude
        if dist <= Config.DribbleRange then
            -- Teletransportar el balón a una posición delante del jugador
            -- Esto simula un "dribble" perfecto
            local targetPos = root.Position + (root.CFrame.LookVector * 3) + Vector3.new(0, 1, 0)
            ball.CFrame = CFrame.new(targetPos)
            ball.Velocity = Vector3.new(0, 0, 0) -- Detener el balón
        end
    end
end

--==========================================================================
-- 5. INTERFAZ GRÁFICA (ESTILO EXUSO HUB)
--==========================================================================
local function CreateUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "BLR_CustomHub"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = game:GetService("CoreGui")

    -- Panel Principal
    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 300, 0, 380)
    MainFrame.Position = UDim2.new(0.5, -150, 0.5, -190)
    MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui
    MainFrame.Active = true
    MainFrame.Draggable = true
    
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 8)
    UICorner.Parent = MainFrame

    -- Título
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 40)
    Title.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 16
    Title.Text = "BLR Custom Hub"
    Title.Parent = MainFrame
    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 8)
    TitleCorner.Parent = Title

    -- Contenedor de Scroll
    local ScrollFrame = Instance.new("ScrollingFrame")
    ScrollFrame.Size = UDim2.new(1, 0, 1, -40)
    ScrollFrame.Position = UDim2.new(0, 0, 0, 40)
    ScrollFrame.BackgroundTransparency = 1
    ScrollFrame.ScrollBarThickness = 2
    ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 120, 255)
    ScrollFrame.Parent = MainFrame
    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 400)

    local Layout = Instance.new("UIListLayout")
    Layout.Padding = UDim.new(0, 10)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Parent = ScrollFrame
    
    local Padding = Instance.new("UIPadding")
    Padding.PaddingTop = UDim.new(0, 10)
    Padding.PaddingLeft = UDim.new(0, 10)
    Padding.PaddingRight = UDim.new(0, 10)
    Padding.Parent = ScrollFrame

    -- Función auxiliar para crear Toggles
    local function CreateToggle(name, desc, configKey, callback)
        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, 0, 0, 50)
        Frame.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
        Frame.BorderSizePixel = 0
        Frame.Parent = ScrollFrame
        local FrameCorner = Instance.new("UICorner")
        FrameCorner.CornerRadius = UDim.new(0, 6)
        FrameCorner.Parent = Frame

        local TextLabel = Instance.new("TextLabel")
        TextLabel.Size = UDim2.new(1, -60, 0, 20)
        TextLabel.Position = UDim2.new(0, 10, 0, 5)
        TextLabel.BackgroundTransparency = 1
        TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        TextLabel.Font = Enum.Font.GothamMedium
        TextLabel.TextSize = 13
        TextLabel.TextXAlignment = Enum.TextXAlignment.Left
        TextLabel.Text = name
        TextLabel.Parent = Frame

        local DescLabel = Instance.new("TextLabel")
        DescLabel.Size = UDim2.new(1, -60, 0, 15)
        DescLabel.Position = UDim2.new(0, 10, 0, 25)
        DescLabel.BackgroundTransparency = 1
        DescLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        DescLabel.Font = Enum.Font.Gotham
        DescLabel.TextSize = 10
        DescLabel.TextXAlignment = Enum.TextXAlignment.Left
        DescLabel.Text = desc
        DescLabel.Parent = Frame

        local ToggleBtn = Instance.new("TextButton")
        ToggleBtn.Size = UDim2.new(0, 40, 0, 20)
        ToggleBtn.Position = UDim2.new(1, -50, 0.5, -10)
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        ToggleBtn.Text = ""
        ToggleBtn.Parent = Frame
        local ToggleCorner = Instance.new("UICorner")
        ToggleCorner.CornerRadius = UDim.new(1, 0)
        ToggleCorner.Parent = ToggleBtn

        local Indicator = Instance.new("Frame")
        Indicator.Size = UDim2.new(0, 16, 0, 16)
        Indicator.Position = UDim2.new(0, 2, 0, 2)
        Indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Indicator.Parent = ToggleBtn
        local IndCorner = Instance.new("UICorner")
        IndCorner.CornerRadius = UDim.new(1, 0)
        IndCorner.Parent = Indicator

        ToggleBtn.MouseButton1Click:Connect(function()
            Config[configKey] = not Config[configKey]
            if Config[configKey] then
                ToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
                Indicator.Position = UDim2.new(1, -18, 0, 2)
            else
                ToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
                Indicator.Position = UDim2.new(0, 2, 0, 2)
            end
            if callback then callback(Config[configKey]) end
        end)
    end

    -- Función auxiliar para crear Sliders
    local function CreateSlider(name, min, max, default, configKey)
        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, 0, 0, 60)
        Frame.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
        Frame.BorderSizePixel = 0
        Frame.Parent = ScrollFrame
        local FrameCorner = Instance.new("UICorner")
        FrameCorner.CornerRadius = UDim.new(0, 6)
        FrameCorner.Parent = Frame

        local TextLabel = Instance.new("TextLabel")
        TextLabel.Size = UDim2.new(1, -60, 0, 20)
        TextLabel.Position = UDim2.new(0, 10, 0, 5)
        TextLabel.BackgroundTransparency = 1
        TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        TextLabel.Font = Enum.Font.GothamMedium
        TextLabel.TextSize = 13
        TextLabel.TextXAlignment = Enum.TextXAlignment.Left
        TextLabel.Text = name
        TextLabel.Parent = Frame

        local ValueLabel = Instance.new("TextLabel")
        ValueLabel.Size = UDim2.new(0, 50, 0, 20)
        ValueLabel.Position = UDim2.new(1, -60, 0, 5)
        ValueLabel.BackgroundTransparency = 1
        ValueLabel.TextColor3 = Color3.fromRGB(0, 120, 255)
        ValueLabel.Font = Enum.Font.GothamBold
        ValueLabel.TextSize = 13
        ValueLabel.Text = tostring(default)
        ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
        ValueLabel.Parent = Frame

        local Bar = Instance.new("Frame")
        Bar.Size = UDim2.new(1, -20, 0, 6)
        Bar.Position = UDim2.new(0, 10, 0, 35)
        Bar.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        Bar.Parent = Frame
        local BarCorner = Instance.new("UICorner")
        BarCorner.CornerRadius = UDim.new(1, 0)
        BarCorner.Parent = Bar

        local Fill = Instance.new("Frame")
        Fill.Size = UDim2.new((default - min)/(max - min), 0, 1, 0)
        Fill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
        Fill.Parent = Bar
        local FillCorner = Instance.new("UICorner")
        FillCorner.CornerRadius = UDim.new(1, 0)
        FillCorner.Parent = Fill

        local SliderBtn = Instance.new("TextButton")
        SliderBtn.Size = UDim2.new(1, 0, 1, 0)
        SliderBtn.BackgroundTransparency = 1
        SliderBtn.Text = ""
        SliderBtn.Parent = Bar

        local dragging = false
        SliderBtn.MouseButton1Down:Connect(function() dragging = true end)
        UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)

        UIS.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local mouseX = UIS:GetMouseLocation().X
                local barAbsX = Bar.AbsolutePosition.X
                local barAbsWidth = Bar.AbsoluteSize.X
                local percent = math.clamp((mouseX - barAbsX) / barAbsWidth, 0, 1)
                local val = min + (max - min) * percent
                
                Config[configKey] = val
                ValueLabel.Text = string.format("%.2f", val)
                Fill.Size = UDim2.new(percent, 0, 1, 0)
            end
        end)
    end

    -- Crear los elementos del menú
    CreateToggle("anti ragdoll", "Mantiene al personaje de pie.", "AntiRagdoll")
    CreateSlider("CFrame Speed", 0.1, 1.0, 0.15, "CFramesSpeedValue")
    CreateToggle("Toggle CFrame Speed", "Activa el movimiento por CFrame.", "CFrameSpeed")
    CreateSlider("Auto Dribble Range", 10, 50, 23, "DribbleRange")
    CreateToggle("Auto Dribble", "Atrae el balón si está en rango.", "AutoDribble")
end

--==========================================================================
-- 6. INICIALIZACIÓN Y BUCLE PRINCIPAL
--==========================================================================
CreateUI()

-- Conectar los bucles a RunService
table.insert(Connections, RunService.Heartbeat:Connect(AntiRagdollLoop))
table.insert(Connections, RunService.Heartbeat:Connect(CFrameSpeedLoop))
table.insert(Connections, RunService.Heartbeat:Connect(AutoDribbleLoop))

-- Limpieza al recargar
LP.CharacterAdded:Connect(function()
    wait(1)
    -- Reiniciar referencias si es necesario
end)

print("[BLR Custom Hub] Cargado correctamente.")
