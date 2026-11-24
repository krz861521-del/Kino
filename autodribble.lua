local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

if getgenv and getgenv().AutoDribble then
    pcall(function() getgenv().AutoDribble.stop() end)
end

local Config = {
    TriggerName = "Sliding",     -- animación del rival que activa el regate
    DribbleName = "Dribbling",   -- nombre del remote o botón del regate
    Range = 15,                  -- distancia máxima del rival (studs)
    FacingDot = 0.5,             -- 0.5 = apunta hacia ti (~60°). 0.8 = más estricto
    Cooldown = 0.8,              -- segundos entre regates
    ReactionDelay = 0.05,        -- espera antes de regatear
    DribbleKey = Enum.KeyCode.Q, -- tecla si no hay remote ni botón
    RemoteArgs = {},             -- argumentos si el remote los pide
    IgnoreTeammates = true,
    Debug = true,
}

local running = true
local active = {}
local lastDribble = 0
local seenNames = {}
local remoteCache, buttonCache

local function log(...)
    if Config.Debug then print("[AutoDribble]", ...) end
end

local function findRemote()
    if remoteCache and remoteCache.Parent then return remoteCache end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and d.Name == Config.DribbleName then
            remoteCache = d
            return d
        end
    end
end

local function findButton()
    if buttonCache and buttonCache.Parent then return buttonCache end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("GuiButton") and d.Name == Config.DribbleName then
            buttonCache = d
            return d
        end
    end
end

local function pressButton(btn)
    if not getconnections then return false end
    local fired = false
    for _, sig in ipairs({ btn.MouseButton1Down, btn.MouseButton1Click, btn.MouseButton1Up, btn.Activated, btn.TouchTap }) do
        pcall(function()
            for _, c in ipairs(getconnections(sig)) do
                c:Fire()
                fired = true
            end
        end)
    end
    return fired
end

local function dribble()
    -- 1) Remote
    local remote = findRemote()
    if remote then
        local ok = pcall(function()
            if remote:IsA("RemoteEvent") then
                remote:FireServer(table.unpack(Config.RemoteArgs))
            else
                remote:InvokeServer(table.unpack(Config.RemoteArgs))
            end
        end)
        if ok then
            log("Dribbling vía remote:", remote:GetFullName())
            return
        end
    end

    -- 2) Botón en pantalla
    local btn = findButton()
    if btn and pressButton(btn) then
        log("Dribbling vía botón:", btn:GetFullName())
        return
    end

    -- 3) Tecla
    local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    if ok and vim then
        vim:SendKeyEvent(true, Config.DribbleKey, false, game)
        task.delay(0.05, function()
            vim:SendKeyEvent(false, Config.DribbleKey, false, game)
        end)
        log("Dribbling vía tecla:", Config.DribbleKey.Name)
    else
        warn("[AutoDribble] No encontré remote, botón ni pude simular la tecla.")
    end
end

local function trigger()
    if os.clock() - lastDribble < Config.Cooldown then return end
    lastDribble = os.clock()
    task.delay(Config.ReactionDelay, dribble)
end

local function isTriggerTrack(track)
    local a = track.Animation
    local wanted = string.lower(Config.TriggerName)
    for _, n in ipairs({ track.Name, a and a.Name or "" }) do
        if n ~= "" and string.find(string.lower(n), wanted, 1, true) then
            return true
        end
    end
    return false
end

local function isFacingMe(root, toMe)
    local flat = Vector3.new(toMe.X, 0, toMe.Z)
    if flat.Magnitude < 0.05 then return true end
    local look = root.CFrame.LookVector
    look = Vector3.new(look.X, 0, look.Z)
    if look.Magnitude < 0.05 then return false end
    return look.Unit:Dot(flat.Unit) >= Config.FacingDot
end

local conn = RunService.Heartbeat:Connect(function()
    if not running then return end

    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local nowActive = {}

    for _, player in ipairs(Players:GetPlayers()) do
        local sameTeam = Config.IgnoreTeammates and player.Team and player.Team == LocalPlayer.Team
        if player ~= LocalPlayer and not sameTeam then
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")

            if root and animator then
                local toMe = myRoot.Position - root.Position
                if toMe.Magnitude <= Config.Range then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        if Config.Debug and not seenNames[track.Name] then
                            seenNames[track.Name] = true
                            log("Animación vista en rival cercano:", track.Name)
                        end

                        if isTriggerTrack(track) then
                            nowActive[track] = true
                            if not active[track] and isFacingMe(root, toMe) then
                                log(Config.TriggerName .. " de", player.Name, "→ regateando")
                                trigger()
                            end
                        end
                    end
                end
            end
        end
    end

    active = nowActive
end)

local api = {}
function api.stop()
    running = false
    pcall(function() conn:Disconnect() end)
    if getgenv then getgenv().AutoDribble = nil end
    print("[AutoDribble] detenido")
end
function api.config() return Config end
if getgenv then getgenv().AutoDribble = api end

print("[AutoDribble] activo con '" .. Config.TriggerName .. "'")
