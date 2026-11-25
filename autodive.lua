--[[ BLR HUB v1.1 · Blue Lock: Rivals
     Auto Steal (remote) + Grab Ball + Cámara al balón + Anti-Ragdoll
     Todo en un solo menú con toggles que se guardan ]]
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService  = game:GetService("HttpService")

local me  = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
if ENV.HUB and ENV.HUB.unload then pcall(ENV.HUB.unload) end

--== CONFIG ==----------------------------------------------------------
local C = {
    bg=Color3.fromRGB(14,16,26),   card=Color3.fromRGB(30,33,48),
    txt=Color3.fromRGB(235,238,248), mut=Color3.fromRGB(140,146,170),
    acc=Color3.fromRGB(60,120,255), off=Color3.fromRGB(58,62,84),
    ok =Color3.fromRGB(80,220,140), warn=Color3.fromRGB(255,180,60),
}
local K = {
    range = 12, carrier = 8, facing = 0.5, cooldown = 1.2,
    grabKey = Enum.KeyCode.G, grabTime = 6,
    pulls = { 0.25, 0.5, 1 },
    file = "BLR_Hub.json",
}

--== ESTADO PERSISTENTE ==---------------------------------------------
local cfg = { features = {}, pull = 2 }
pcall(function()
    if isfile and readfile and isfile(K.file) then
        local d = HttpService:JSONDecode(readfile(K.file))
        cfg.features = d.features or {}
        cfg.pull = math.clamp(tonumber(d.pull) or 2, 1, #K.pulls)
    end
end)
local function save()
    if writefile then pcall(function() writefile(K.file, HttpService:JSONEncode(cfg)) end) end
end

--== UTIL ==------------------------------------------------------------
local FLAT = Vector3.new(1,0,1)
local cons, statusLbl = {}, nil
local function link(c) cons[#cons+1] = c; return c end
local function mk(cls, p, parent)
    local o = Instance.new(cls)
    for k,v in pairs(p) do pcall(function() o[k] = v end) end
    o.Parent = parent; return o
end
local function corner(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r) }, o); return o end
local function say(t, col)
    print("[Hub] "..t)
    if statusLbl then statusLbl.Text = t; statusLbl.TextColor3 = col or C.mut end
end
local function rootOf(p) local c=p.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function humOf(p)  local c=p.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function isFoe(p)
    if p == me then return false end
    if p.Team and me.Team and p.Team == me.Team then return false end
    return true
end

--== BALÓN + REMOTE ==--------------------------------------------------
local BallService
pcall(function()
    BallService = game:GetService("ReplicatedStorage"):WaitForChild("Packages", 5)
        :WaitForChild("Knit", 5):WaitForChild("Services", 5)
        :WaitForChild("BallService", 5):WaitForChild("RE", 5)
end)
local function getBallOwner()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local f = p.Character:FindFirstChild("Football")
            if f and f:IsA("BasePart") then return p, f end
        end
    end
    return nil, nil
end

--== FEATURE 1: AUTO STEAL ==-------------------------------------------
local lastSteal = -1e9
local function stealStep()
    if not BallService then return end
    local r0 = rootOf(me); if not r0 then return end
    if os.clock() - lastSteal < K.cooldown then return end
    local owner = getBallOwner()
    if not owner or not isFoe(owner) then return end
    local rt = rootOf(owner); if not rt then return end
    local to = (rt.Position - r0.Position) * FLAT
    local d = to.Magnitude
    if d < 2 or d > K.range then return end
    local look = r0.CFrame.LookVector * FLAT
    if look.Magnitude < 0.05 then return end
    if look.Unit:Dot(to.Unit) < K.facing then return end
    lastSteal = os.clock()
    say("Steal → "..owner.DisplayName, C.warn)
    pcall(function() BallService.Slide:FireServer() end)
end

--== FEATURE 2: GRAB BALL ==--------------------------------------------
local chaseUntil, chasing = 0, false
local rparams = RaycastParams.new(); rparams.FilterType = Enum.RaycastFilterType.Exclude
local function grab()
    if chaseUntil > os.clock() then chaseUntil = 0; say("Grab Ball cancelado"); return end
    local _, b = getBallOwner()
    if not b then say("No hay pelota", C.warn); return end
    chaseUntil = os.clock() + K.grabTime
    say("Corriendo...", C.acc)
end
local function grabStep()
    local active = chaseUntil > os.clock()
    local r0, h = rootOf(me), humOf(me)
    if not (r0 and h) then return end
    if active then
        local _, b = getBallOwner()
        if not b then chaseUntil = 0; return end
        chasing = true
        if (b.Position - r0.Position).Magnitude < 3.5 then
            chaseUntil = 0
            pcall(function() h:MoveTo(r0.Position) end)
            chasing = false; say("Alcanzada", C.ok); return
        end
        local pred = b.Position + b.AssemblyLinearVelocity * 0.25
        pcall(function() h:MoveTo(pred) end)
    elseif chasing then
        chasing = false
        if r0 and h then pcall(function() h:MoveTo(r0.Position) end) end
    end
end

--== FEATURE 3: CÁMARA ==-----------------------------------------------
local CAM = "BLRHubCam"
local function camStep(dt)
    local cam = workspace.CurrentCamera
    local _, b = getBallOwner()
    if not (cam and b) then return end
    local cf = cam.CFrame
    local flat = (b.Position - cf.Position) * FLAT
    if flat.Magnitude < 3 then return end
    local y = cf.LookVector.Y
    local goal = flat.Unit * math.sqrt(math.max(0, 1-y*y)) + Vector3.new(0, y, 0)
    local a = 1 - (1 - K.pulls[cfg.pull]) ^ (math.max(dt, 0.001) * 60)
    cam.CFrame = cf:Lerp(CFrame.lookAt(cf.Position, cf.Position + goal), math.clamp(a, 0, 1))
end
local function setCam(on)
    pcall(function() RunService:UnbindFromRenderStep(CAM) end)
    if on then
        RunService:BindToRenderStep(CAM, Enum.RenderPriority.Camera.Value + 1,
            function(dt) pcall(camStep, dt) end)
    end
end

--== FEATURE 4: ANTI-RAGDOLL ==-----------------------------------------
local antiRagConn = nil
local antiRagCached = {}
local antiRagReconnect = nil

local function cacheChar()
    local char = me.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then return false end
    antiRagCached = { character = char, humanoid = hum, root = root }
    return true
end

local function isRagdolled()
    local hum = antiRagCached.humanoid
    if not hum then return false end
    local ok, state = pcall(function() return hum:GetState() end)
    if not ok then return false end
    return state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.GettingUp
end

local function cleanRagdoll()
    local char = antiRagCached.character
    if not char then return end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BallSocketConstraint")
        or (v:IsA("Attachment") and v.Name:find("RagdollAttachment")) then
            pcall(function() v:Destroy() end)
        end
    end
end

local function forceExit()
    local hum  = antiRagCached.humanoid
    local root = antiRagCached.root
    if not (hum and root) then return end
    pcall(function()
        me:SetAttribute("RagdollEndTime", workspace:GetServerTimeNow())
    end)
    if hum.Health > 0 then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
    pcall(function()
        root.Anchored = false
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = CFrame.new(root.Position)
            * CFrame.Angles(0, math.rad(root.Orientation.Y), 0)
    end)
    local cam = workspace.CurrentCamera
    if cam and cam.CameraSubject ~= hum then
        pcall(function() cam.CameraSubject = hum end)
    end
end

local function antiRagLoop()
    if not antiRagCached.humanoid or not antiRagCached.humanoid.Parent then
        if not cacheChar() then return end
    end
    if isRagdolled() then
        cleanRagdoll()
        forceExit()
    end
end

local function startAntiRag()
    if antiRagConn then antiRagConn:Disconnect(); antiRagConn = nil end
    if antiRagReconnect then antiRagReconnect:Disconnect(); antiRagReconnect = nil end
    if not cacheChar() then
        -- Aún sin personaje: esperamos a que reaparezca
        antiRagReconnect = me.CharacterAdded:Connect(function()
            task.wait(0.5)
            if Features["antiragg"] and Features["antiragg"].enabled then
                startAntiRag()
            end
        end)
        return
    end
    antiRagConn = RunService.RenderStepped:Connect(antiRagLoop)
    -- También re-cachea si mueres y reapareces
    antiRagReconnect = me.CharacterAdded:Connect(function()
        task.wait(0.5)
        cacheChar()
    end)
end

local function stopAntiRag()
    if antiRagConn then antiRagConn:Disconnect(); antiRagConn = nil end
    if antiRagReconnect then antiRagReconnect:Disconnect(); antiRagReconnect = nil end
    antiRagCached = {}
end

--== GESTOR DE FEATURES ==----------------------------------------------
local Features = {}
local function toggleFeature(name, state)
    local f = Features[name]; if not f then return end
    state = (state ~= nil) and state or not f.enabled
    f.enabled = state; cfg.features[name] = state; save()
    if state then
        pcall(function() if f.onEnable then f.onEnable() end end)
        if f.loop then
            table.insert(f.connections, RunService.Heartbeat:Connect(function(dt)
                pcall(f.loop, dt)
            end))
        end
    else
        for _, c in ipairs(f.connections) do pcall(function() c:Disconnect() end) end
        f.connections = {}
        pcall(function() if f.onDisable then f.onDisable() end end)
    end
end
local function register(name, opts)
    Features[name] = {
        enabled = cfg.features[name] == true,
        connections = {}, loop = opts.loop,
        onEnable = opts.onEnable, onDisable = opts.onDisable,
    }
    if Features[name].enabled then
        pcall(function() if opts.onEnable then opts.onEnable() end end)
        if opts.loop then
            table.insert(Features[name].connections, RunService.Heartbeat:Connect(function(dt)
                pcall(opts.loop, dt)
            end))
        end
    end
end

register("autosteal", { loop = stealStep })
register("cam", { loop = camStep, onEnable = function() setCam(true) end,
                                    onDisable = function() setCam(false) end })
register("antiragg", { onEnable = startAntiRag, onDisable = stopAntiRag })

--== UI ==--------------------------------------------------------------
local gui = mk("ScreenGui", { Name="BLRHub", ResetOnSpawn=false, DisplayOrder=35 })
local panel = corner(mk("Frame", {
    Size = UDim2.fromOffset(260, 300), Position = UDim2.new(0, 12, 0.4, 0),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true,
}, gui), 12)
mk("UIStroke", { Color = C.acc, Thickness = 1.5, Transparency = 0.4 }, panel)

local head = mk("Frame", { Size = UDim2.new(1,0,0,30), BackgroundTransparency = 1, Active = true }, panel)
mk("TextLabel", { Text = "⚽  BLR Hub", Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12,0), Size = UDim2.new(1,-50,1,0) }, head)
statusLbl = mk("TextLabel", { Text = "Listo", Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = C.mut, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    BackgroundTransparency = 1, Position = UDim2.new(0,12,1,-18), Size = UDim2.new(1,-24,0,16) }, panel)

-- drag
local dragging, dS, dO = false, nil, nil
link(head.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dS, dO = true, i.Position, panel.Position
    end
end))
link(UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dS
        panel.Position = UDim2.new(dO.X.Scale, dO.X.Offset + d.X, dO.Y.Scale, dO.Y.Offset + d.Y)
    end
end))
link(UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end))

local scroll = mk("ScrollingFrame", {
    Size = UDim2.new(1,-16,1,-50), Position = UDim2.fromOffset(8,34),
    BackgroundTransparency = 1, ScrollBarThickness = 3, ScrollBarImageColor3 = C.acc,
    CanvasSize = UDim2.new(0,0,0,0),
}, panel)
local layout = mk("UIListLayout", { Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scroll.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 8)
end)

local togglesUI = {}
local function addToggle(text, name)
    local r = corner(mk("Frame", { Size = UDim2.new(1,-4,0,34), BackgroundColor3 = C.card, BorderSizePixel = 0 }, scroll), 8)
    mk("TextLabel", { Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.txt,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10,0), Size = UDim2.new(1,-70,1,0) }, r)
    local track = corner(mk("TextButton", { Text = "", AutoButtonColor = false,
        Size = UDim2.fromOffset(38,20), Position = UDim2.new(1,-46,0.5,-10),
        BackgroundColor3 = C.off }, r), 10)
    local knob = corner(mk("Frame", { Size = UDim2.fromOffset(14,14), Position = UDim2.fromOffset(3,3),
        BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0 }, track), 7)
    local function render()
        local on = Features[name] and Features[name].enabled
        TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = on and C.acc or C.off }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), { Position = UDim2.fromOffset(on and 21 or 3, 3) }):Play()
    end
    render(); togglesUI[name] = render
    link(track.Activated:Connect(function()
        toggleFeature(name)
        for _, f in pairs(togglesUI) do pcall(f) end
        say(text..(Features[name].enabled and " ON" or " OFF"),
            Features[name].enabled and C.ok or C.mut)
    end))
end
local function addButton(text, cb, accent)
    local r = corner(mk("TextButton", { Text = text, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = C.txt, BackgroundColor3 = accent and C.acc or C.card, AutoButtonColor = false,
        Size = UDim2.new(1,-4,0,34) }, scroll), 8)
    link(r.Activated:Connect(function() pcall(cb) end))
end

addToggle("Auto Steal", "autosteal")
addToggle("Cámara al balón", "cam")
addToggle("Anti-Ragdoll", "antiragg")

-- botón ciclar cámara
local camBtn = corner(mk("TextButton", { Text = "", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.txt, BackgroundColor3 = C.card, AutoButtonColor = false,
    Size = UDim2.new(1,-4,0,30) }, scroll), 8)
local function camTxt() camBtn.Text = "📷  Fuerza cámara: "..math.floor(K.pulls[cfg.pull]*100).."%" end
camTxt()
link(camBtn.Activated:Connect(function()
    cfg.pull = cfg.pull % #K.pulls + 1; camTxt(); save(); say("Cámara "..math.floor(K.pulls[cfg.pull]*100).."%", C.acc)
end))

addButton("🏃  Grab Ball  (G)", grab, true)

-- hotkey G
link(UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == K.grabKey then pcall(grab) end
end))

--== UNLOAD ==----------------------------------------------------------
local function unload()
    for _, c in ipairs(cons) do pcall(function() c:Disconnect() end) end
    for _, f in pairs(Features) do
        for _, c in ipairs(f.connections or {}) do pcall(function() c:Disconnect() end) end
    end
    setCam(false)
    stopAntiRag()
    pcall(function() gui:Destroy() end)
    ENV.HUB = nil
    print("[Hub] descargado")
end
local xb = corner(mk("TextButton", { Text = "✕", Font = Enum.Font.GothamBold, TextSize = 13,
    TextColor3 = C.mut, BackgroundColor3 = C.card, Size = UDim2.fromOffset(26,22),
    Position = UDim2.new(1,-34,0,4) }, head), 6)
link(xb.Activated:Connect(unload))

local parent
if gethui then local ok, h = pcall(gethui); if ok and h then parent = h end end
if not parent then local ok, cg = pcall(function() return game:GetService("CoreGui") end); if ok and cg then parent = cg end end
if not parent then parent = me:WaitForChild("PlayerGui") end
gui.Parent = parent

ENV.HUB = { unload = unload, toggle = toggleFeature, features = Features, grab = grab }
print("[Hub] listo · Anti-Ragdoll incluido")
