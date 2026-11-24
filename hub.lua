-- Blue Hub (loader): menú con botones. Descarga cada módulo de tu GitHub al activarlo.
-- Ejecutar: loadstring(game:HttpGet("URL_RAW_DE_ESTE_ARCHIVO"))()

-- Tu URL raw SIN el nombre del archivo (debe terminar en "/")
local BASE =  "https://raw.githubusercontent.com/krz861521-del/Kino/refs/heads/main/"
-- Nombres de tus archivos en GitHub
local FILES = { dive = "autodive.lua", dribble = "autodribble.lua" }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

if getgenv and getgenv().BlueHub then
    pcall(function() getgenv().BlueHub.stop() end)
end

local Hub = { conns = {}, alive = true }
local notify = function() end -- se reasigna al crear la interfaz

-- Descarga y ejecuta un archivo de tu GitHub
local function runFile(file)
    if string.find(BASE, "USUARIO", 1, true) then
        return false, "edita BASE en el hub (tu URL raw)"
    end
    local okGet, src = pcall(function()
        return game:HttpGet(BASE .. file .. "?t=" .. os.time())
    end)
    if not okGet or type(src) ~= "string" or #src < 20 or string.find(src, "^404") then
        return false, "no pude descargar " .. file
    end
    local fn, err = loadstring(src)
    if not fn then
        warn("[BlueHub] sintaxis en " .. file .. ":", err)
        return false, "error de sintaxis en " .. file
    end
    local okRun, runErr = pcall(fn)
    if not okRun then
        warn("[BlueHub] error al ejecutar " .. file .. ":", runErr)
        return false, "error al ejecutar " .. file
    end
    return true
end

--==========================================================================
-- MÓDULOS (cada uno: enable() -> true | false, mensaje ; disable() ; stop())
--==========================================================================
local Modules = {}

Modules.dribble = {
    enable = function()
        local ok, err = runFile(FILES.dribble)
        if not ok then return false, "Auto Dribleo: " .. err end
        return true
    end,
    disable = function()
        pcall(function() getgenv().AutoDribble.stop() end)
    end,
}
Modules.dribble.stop = Modules.dribble.disable

local diveLoaded = false
Modules.dive = {
    enable = function()
        if not diveLoaded then
            local okRemotes = pcall(function()
                local s = ReplicatedStorage:WaitForChild("Packages", 5):WaitForChild("Knit", 5):WaitForChild("Services", 5)
                s:WaitForChild("BallService", 5):WaitForChild("RE", 5):WaitForChild("Dive", 5)
            end)
            if not okRemotes then return false, "Auto Save: no encontré los remotes del juego" end

            local ok, err = runFile(FILES.dive)
            if not ok then return false, "Auto Save: " .. err end
            diveLoaded = true

            -- el hub ya tiene su botón: se quitan los extras del script
            local C = getgenv().AutoDive
            if C then C.InfiniteStamina = false end
            local pg = LP:FindFirstChild("PlayerGui")
            local extra = pg and pg:FindFirstChild("ADToggle")
            if extra then pcall(function() extra:Destroy() end) end
        end
        local C = getgenv().AutoDive
        if not C then return false, "Auto Save: no se cargó" end
        C.Enabled = true
        return true
    end,
    disable = function()
        local C = getgenv().AutoDive
        if C then C.Enabled = false end
    end,
    stop = function()
        pcall(function() getgenv().AutoDive.stop() end)
    end,
}

local stam = { conn = nil, on = false }
Modules.stamina = {
    enable = function()
        stam.on = true
        local stats = LP:FindFirstChild("PlayerStats") or LP:WaitForChild("PlayerStats", 10)
        local s = stats and (stats:FindFirstChild("Stamina") or stats:WaitForChild("Stamina", 5))
        if not s then
            stam.on = false
            return false, "Stamina: no encontré PlayerStats"
        end
        if stam.conn then stam.conn:Disconnect() end
        s.Value = 100
        stam.conn = s:GetPropertyChangedSignal("Value"):Connect(function()
            if stam.on and s.Value < 95 then s.Value = 100 end
        end)
        return true
    end,
    disable = function()
        stam.on = false
        if stam.conn then stam.conn:Disconnect() stam.conn = nil end
    end,
}
Modules.stamina.stop = Modules.stamina.disable

local options = {
    { key = "dribble", name = "Auto Dribleo",     desc = "Regatea cuando te hacen Sliding", mod = Modules.dribble },
    { key = "dive",    name = "Auto Save",        desc = "Portero: se lanza a los tiros",   mod = Modules.dive },
    { key = "stamina", name = "Stamina infinita", desc = "Mantiene la stamina en 100",      mod = Modules.stamina },
}

--==========================================================================
-- INTERFAZ
--==========================================================================
local gui = nil

-- Prueba varios lugares hasta que la interfaz quede realmente dentro del juego
local function mountGui(g)
    local candidates = {
        function() return LP:WaitForChild("PlayerGui", 5) end,
        function() return gethui and gethui() end,
        function() return game:GetService("CoreGui") end,
    }
    for _, getParent in ipairs(candidates) do
        local ok, parent = pcall(getParent)
        if ok and parent then
            local ok2 = pcall(function() g.Parent = parent end)
            if ok2 and g.Parent == parent then return parent end
        end
    end
    return nil
end

function Hub.stop()
    Hub.alive = false
    for _, opt in ipairs(options) do
        pcall(opt.mod.stop or opt.mod.disable)
    end
    for _, c in ipairs(Hub.conns) do pcall(function() c:Disconnect() end) end
    if gui then pcall(function() gui:Destroy() end) end
    if getgenv then getgenv().BlueHub = nil end
    print("[BlueHub] cerrado")
end

local function buildUi()
    local BG        = Color3.fromRGB(22, 24, 32)
    local ROW       = Color3.fromRGB(34, 37, 50)
    local ACCENT    = Color3.fromRGB(70, 130, 255)
    local ON_COLOR  = Color3.fromRGB(60, 190, 110)
    local OFF_COLOR = Color3.fromRGB(75, 78, 95)
    local TEXT      = Color3.fromRGB(240, 240, 245)
    local SUBTEXT   = Color3.fromRGB(150, 155, 175)

    local function corner(inst, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r)
        c.Parent = inst
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "BlueHub"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local WIDTH, TITLE_H, ROW_H, GAP, STATUS_H = 250, 38, 42, 4, 20
    local expandedH = TITLE_H + 8 + #options * (ROW_H + GAP) + STATUS_H + 8

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.fromOffset(WIDTH, expandedH)
    main.Position = UDim2.new(0.5, -WIDTH / 2, 0, 70)
    main.BackgroundColor3 = BG
    main.BorderSizePixel = 0
    main.Active = true
    main.ClipsDescendants = true
    main.Parent = gui
    corner(main, 10)
    local stroke = Instance.new("UIStroke")
    stroke.Color = ACCENT
    stroke.Thickness = 1
    stroke.Parent = main

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, TITLE_H)
    title.BackgroundColor3 = ROW
    title.BorderSizePixel = 0
    title.Active = true
    title.Parent = main
    corner(title, 10)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.fromOffset(12, 0)
    titleLabel.Size = UDim2.new(1, -80, 1, 0)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 15
    titleLabel.TextColor3 = TEXT
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = "Blue Hub"
    titleLabel.Parent = title

    local function titleButton(text, offsetX)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, offsetX, 0.5, 0)
        b.Size = UDim2.fromOffset(28, 26)
        b.BackgroundColor3 = OFF_COLOR
        b.AutoButtonColor = false
        b.Font = Enum.Font.GothamBold
        b.TextSize = 16
        b.TextColor3 = TEXT
        b.Text = text
        b.Parent = title
        corner(b, 6)
        return b
    end

    local closeBtn = titleButton("X", -6)
    local minBtn = titleButton("-", -40)

    local body = Instance.new("Frame")
    body.Position = UDim2.fromOffset(0, TITLE_H)
    body.Size = UDim2.new(1, 0, 1, -TITLE_H)
    body.BackgroundTransparency = 1
    body.Parent = main

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = body

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, GAP)
    list.Parent = body

    local status = Instance.new("TextLabel")
    status.LayoutOrder = 100
    status.BackgroundTransparency = 1
    status.Size = UDim2.new(1, 0, 0, STATUS_H)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextColor3 = SUBTEXT
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Text = "Listo"
    status.Parent = body

    notify = function(text) status.Text = text end

    for i, opt in ipairs(options) do
        local row = Instance.new("Frame")
        row.LayoutOrder = i
        row.Size = UDim2.new(1, 0, 0, ROW_H)
        row.BackgroundColor3 = ROW
        row.BorderSizePixel = 0
        row.Parent = body
        corner(row, 8)

        local name = Instance.new("TextLabel")
        name.BackgroundTransparency = 1
        name.Position = UDim2.fromOffset(10, 5)
        name.Size = UDim2.new(1, -80, 0, 18)
        name.Font = Enum.Font.GothamBold
        name.TextSize = 13
        name.TextColor3 = TEXT
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.Text = opt.name
        name.Parent = row

        local desc = Instance.new("TextLabel")
        desc.BackgroundTransparency = 1
        desc.Position = UDim2.fromOffset(10, 23)
        desc.Size = UDim2.new(1, -80, 0, 14)
        desc.Font = Enum.Font.Gotham
        desc.TextSize = 10
        desc.TextColor3 = SUBTEXT
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.TextTruncate = Enum.TextTruncate.AtEnd
        desc.Text = opt.desc
        desc.Parent = row

        local switch = Instance.new("TextButton")
        switch.AnchorPoint = Vector2.new(1, 0.5)
        switch.Position = UDim2.new(1, -10, 0.5, 0)
        switch.Size = UDim2.fromOffset(52, 26)
        switch.BackgroundColor3 = OFF_COLOR
        switch.AutoButtonColor = false
        switch.Font = Enum.Font.GothamBold
        switch.TextSize = 12
        switch.TextColor3 = TEXT
        switch.Text = "OFF"
        switch.Parent = row
        corner(switch, 13)

        local state = false
        local function set(v, silent)
            state = v
            switch.Text = v and "ON" or "OFF"
            switch.BackgroundColor3 = v and ON_COLOR or OFF_COLOR
            if silent then return end

            if v then
                notify("Cargando " .. opt.name .. "...")
                task.spawn(function()
                    local called, ok, msg = pcall(opt.mod.enable)
                    if not called then
                        warn("[BlueHub]", opt.name, ok)
                        ok, msg = false, opt.name .. ": error inesperado"
                    end
                    if not state then          -- lo apagaron mientras cargaba
                        pcall(opt.mod.disable)
                        return
                    end
                    if ok then
                        notify(opt.name .. " activado")
                    else
                        pcall(opt.mod.disable)
                        set(false, true)
                        notify(msg or (opt.name .. ": error"))
                        warn("[BlueHub]", msg)
                    end
                end)
            else
                pcall(opt.mod.disable)
                notify(opt.name .. " desactivado")
            end
        end

        switch.Activated:Connect(function() set(not state) end)
    end

    -- Arrastrar (mouse y táctil)
    local dragging, dragStart, startPos = false, nil, nil
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    table.insert(Hub.conns, UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))

    -- Minimizar / cerrar / ocultar con RightShift
    local minimized = false
    minBtn.Activated:Connect(function()
        minimized = not minimized
        main.Size = UDim2.fromOffset(WIDTH, minimized and TITLE_H or expandedH)
        minBtn.Text = minimized and "+" or "-"
    end)

    table.insert(Hub.conns, UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightShift then gui.Enabled = not gui.Enabled end
    end))

    closeBtn.Activated:Connect(Hub.stop)
end

local okUi, errUi = pcall(buildUi)
if not okUi then warn("[BlueHub] ERROR al crear la interfaz:", errUi) end

if gui then
    local parent = mountGui(gui)
    if parent then
        local okName, full = pcall(function() return parent:GetFullName() end)
        print("[BlueHub] interfaz visible en:", okName and full or tostring(parent))
    else
        warn("[BlueHub] No pude poner la interfaz en ningún lugar (PlayerGui, gethui, CoreGui).")
    end
    -- Si el juego la elimina, la vuelve a poner
    task.spawn(function()
        while Hub.alive do
            task.wait(2)
            if gui and gui.Parent == nil then mountGui(gui) end
        end
    end)
end

if getgenv then getgenv().BlueHub = Hub end
print("[BlueHub] cargado")
