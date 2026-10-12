local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace = game:GetService("Workspace")

local UserInputService = game:GetService("UserInputService")

local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

--==================================================

-- REMOTES

--==================================================

local ChallengeBoss = ReplicatedStorage:WaitForChild("challengeBoss")

local RequestBossPrompt = ReplicatedStorage:WaitForChild("requestBossPrompt")

local RunInfTower = ReplicatedStorage:WaitForChild("runInfTower")

local InfinityTowerAction =

    ReplicatedStorage:WaitForChild("infinityTowerAction")

local BattleEvent =

    ReplicatedStorage:WaitForChild("battleEvent")

local TeleportToArea = ReplicatedStorage:WaitForChild("teleportToArea")

local SwapParty = ReplicatedStorage:WaitForChild("swapParty")

--==================================================

-- TELEPORT ROUTES

--==================================================

local SetStatus, SetCurrent, SetTimer, AutoEnabled
local ActiveWorldKey = nil
local ActiveNpcBoss = nil

local BOSS_TELEPORT = {
    colossal_titan = {1, nil},
    thriller_king = {3, nil},
    red_dog = {4, nil},
    dragon_emperor = {4, nil},
    curse_tyrant = {5, nil},
    kikoru_shinomiya = {"raid", "kaiju"},
    soshiro_hoshina = {"raid", "kaiju"},
    mina_ashiro = {"raid", "kaiju"},
    gen_narumi = {"raid", "kaiju"},
    crimson_phantom = {"lobby", nil},
}

local function NormalizeNpcName(name)
    return string.lower((name:gsub("[%s_%-]", "")))
end

local function FindBossNpc(boss)
    local wanted = NormalizeNpcName(boss)
    local modelMatch = nil
    local partMatch = nil

    for _, instance in ipairs(Workspace:GetDescendants()) do
        if NormalizeNpcName(instance.Name) == wanted then
            if instance:IsA("Model") then
                modelMatch = instance
                break
            elseif instance:IsA("BasePart") and not partMatch then
                partMatch = instance
            end
        end
    end

    return modelMatch or partMatch
end

local function GetNpcCFrame(npc)
    if npc:IsA("Model") then
        if npc.PrimaryPart then
            return npc.PrimaryPart.CFrame
        end
        local root = npc:FindFirstChild("HumanoidRootPart", true)
        if root and root:IsA("BasePart") then
            return root.CFrame
        end
        local part = npc:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.CFrame
        end
    elseif npc:IsA("BasePart") then
        return npc.CFrame
    end
    return nil
end

local function TeleportCharacterNearNpc(boss)
    SetStatus("FINDING NPC")
    SetCurrent("Searching for " .. boss)
    SetTimer("Waiting for NPC to load...")

    local deadline = os.clock() + 30
    local npc = nil
    local npcCFrame = nil

    while AutoEnabled and os.clock() < deadline do
        npc = FindBossNpc(boss)
        if npc then
            npcCFrame = GetNpcCFrame(npc)
            if npcCFrame then
                break
            end
        end
        task.wait(0.5)
    end

    if not AutoEnabled then
        return false
    end
    if not npc or not npcCFrame then
        warn("NPC not found in Workspace:", boss)
        SetStatus("NPC NOT FOUND")
        SetCurrent("Could not find " .. boss)
        SetTimer("Check NPC model name in Workspace")
        return false
    end

    local character = Player.Character or Player.CharacterAdded:Wait()
    if not character then
        SetStatus("CHARACTER NOT FOUND")
        return false
    end

    -- Place the character a few studs in front of the NPC instead of inside it.
    local targetCFrame = npcCFrame * CFrame.new(0, 0, -6)
    local ok, err = pcall(function()
        character:PivotTo(targetCFrame)
    end)
    if not ok then
        warn("Could not move character near NPC:", err)
        SetStatus("NPC TELEPORT FAILED")
        return false
    end

    task.wait(0.75)
    return AutoEnabled
end

local function TeleportToBoss(boss)
    local destination = BOSS_TELEPORT[boss]
    if not destination then
        warn("No teleport route for boss:", boss)
        SetStatus("NO TELEPORT ROUTE")
        return false
    end

    -- Same boss/world: keep running the next difficulty without teleporting again.
    if ActiveNpcBoss == boss and ActiveWorldKey ~= nil and boss ~= "crimson_phantom" then
        SetCurrent(boss .. " • staying in current world")
        return AutoEnabled
    end

    local worldKey = tostring(destination[1]) .. "|" .. tostring(destination[2])
    local alreadyInWorld = ActiveWorldKey == worldKey
    local isRaidWorld = destination[1] == "raid" and destination[2] == "kaiju"
    local isCrimsonPhantom = boss == "crimson_phantom"

    if not alreadyInWorld then
        SetStatus("TELEPORTING TO WORLD")
        SetCurrent("Going to " .. boss)
        SetTimer("Loading boss world...")

        local ok, err = pcall(function()
            TeleportToArea:FireServer(destination[1], destination[2])
        end)
        if not ok then
            warn("World teleport failed:", err)
            SetStatus("WORLD TELEPORT FAILED")
            return false
        end

        if isRaidWorld then
            -- Raid/Kaiju requires standing at this fixed battle-start position.
            -- Do not search for an NPC in this world.
            task.wait(3)
            if not AutoEnabled then
                return false
            end

            local character = Player.Character or Player.CharacterAdded:Wait()
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not character or not root then
                SetStatus("CHARACTER NOT FOUND")
                SetTimer("Cannot move to Kaiju battle point")
                return false
            end

            local kaijuPosition = Vector3.new(
                1498.989990234375,
                1503.4979248046875,
                3547.98828125
            )
            local moved, moveErr = pcall(function()
                character:PivotTo(CFrame.new(kaijuPosition))
            end)
            if not moved then
                warn("Could not move to Kaiju battle point:", moveErr)
                SetStatus("POSITION TELEPORT FAILED")
                return false
            end

            SetCurrent("Kaiju battle point reached")
            SetTimer("Ready to challenge boss")
            task.wait(0.5)
            ActiveWorldKey = worldKey
        else
            if isCrimsonPhantom then
                -- The secret encounter only triggers reliably after returning to Lobby,
                -- then moving to the user's specified exact battle-start transform.
                task.wait(3)
                if not AutoEnabled then return false end
                local character = Player.Character or Player.CharacterAdded:Wait()
                if not character then
                    SetStatus("CHARACTER NOT FOUND")
                    return false
                end
                local secretStart = CFrame.new(
                    -1143.69226, 18.5480232, -730.611572,
                    0.429486394, -7.90959263e-08, 0.903073311,
                    6.21687457e-09, 1, 8.46286312e-08,
                    -0.903073311, -3.07325543e-08, 0.429486394
                )
                local moved, moveErr = pcall(function() character:PivotTo(secretStart) end)
                if not moved then
                    warn("Could not move to Crimson Phantom start:", moveErr)
                    SetStatus("SECRET BOSS TELEPORT FAILED")
                    return false
                end
                SetCurrent("Crimson Phantom start point reached")
                SetTimer("Ready to challenge secret boss")
                task.wait(1)
            else
                local worldDeadline = os.clock() + 30
                local foundNpc = false
                while AutoEnabled and os.clock() < worldDeadline do
                    if FindBossNpc(boss) then
                        foundNpc = true
                        break
                    end
                    task.wait(0.5)
                end
                if not AutoEnabled then return false end
                if not foundNpc then
                    warn("World loaded, but NPC was not found:", boss)
                    SetStatus("NPC NOT FOUND")
                    SetCurrent("Could not find " .. boss)
                    SetTimer("Check NPC name in Workspace")
                    return false
                end
            end
            ActiveWorldKey = worldKey
        end
    else
        SetStatus("SAME WORLD")
        SetCurrent("Staying in current world: " .. boss)
    end

    -- In Raid/Kaiju, move to the shared battle point when switching to another boss.
    -- Other boss worlds still move near the matching NPC.
    if isRaidWorld then
        local character = Player.Character or Player.CharacterAdded:Wait()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not character or not root then
            SetStatus("CHARACTER NOT FOUND")
            return false
        end
        local kaijuPosition = Vector3.new(
            1498.989990234375,
            1503.4979248046875,
            3547.98828125
        )
        local moved, moveErr = pcall(function()
            character:PivotTo(CFrame.new(kaijuPosition))
        end)
        if not moved then
            warn("Could not move to Kaiju battle point:", moveErr)
            SetStatus("POSITION TELEPORT FAILED")
            return false
        end
        task.wait(0.5)
    else
        if isCrimsonPhantom then
            SetStatus("CRIMSON PHANTOM POSITION")
            SetCurrent("Moving to secret boss start point")
            local character = Player.Character or Player.CharacterAdded:Wait()
            if not character then
                SetStatus("CHARACTER NOT FOUND")
                return false
            end
            local secretStart = CFrame.new(
                -1143.69226, 18.5480232, -730.611572,
                0.429486394, -7.90959263e-08, 0.903073311,
                6.21687457e-09, 1, 8.46286312e-08,
                -0.903073311, -3.07325543e-08, 0.429486394
            )
            local moved, moveErr = pcall(function() character:PivotTo(secretStart) end)
            if not moved then
                warn("Could not move to Crimson Phantom start:", moveErr)
                SetStatus("SECRET BOSS TELEPORT FAILED")
                return false
            end
            task.wait(0.75)
        elseif not TeleportCharacterNearNpc(boss) then
            return false
        end
    end

    ActiveNpcBoss = boss
    return AutoEnabled
end

local function TeleportToTower()
    SetStatus("TELEPORTING")
    SetCurrent("Going to Lobby")
    SetTimer("Preparing Infinity Tower...")

    local ok, err = pcall(function()
        TeleportToArea:FireServer("lobby", nil)
    end)
    if not ok then
        warn("Tower teleport failed:", err)
        SetStatus("TELEPORT FAILED")
        return false
    end

    ActiveWorldKey = "lobby|nil"
    ActiveNpcBoss = nil
    task.wait(3)
    return AutoEnabled
end

--==================================================

-- SETTINGS

--==================================================


local DIFFICULTIES = {

    "Normal",

    "Hard",

    "Extreme",

    "Nightmare"

}

-- deadbeat_dad and curse_tyrant stop at Hard.

-- Every other boss uses all 4 difficulties above.

local BOSS_DIFFICULTIES = {

    thriller_king = {"Hard", "Extreme", "Nightmare"},

    red_dog = {"Nightmare"},

    dragon_emperor = {"Hard", "Extreme", "Nightmare"},

    curse_tyrant = {"Hard", "Extreme", "Nightmare"},

    kikoru_shinomiya = {"Normal", "Hard", "Extreme", "Nightmare" },

    soshiro_hoshina = {"Normal", "Hard", "Extreme", "Nightmare" },

    mina_ashiro = {"Normal", "Hard", "Extreme", "Nightmare" },

    gen_narumi = {"Normal", "Hard", "Extreme", "Nightmare" },

    crimson_phantom = {"Normal", "Hard", "Extreme", "Nightmare"}

}

local TOTAL_BOSS_RUNS = 26 -- includes Crimson Phantom Normal/Hard/Extreme

local INFINITY_DURATION = 10 * 60

--==================================================

-- STATE

--==================================================

AutoEnabled = false

local Busy = false

local BattleStarted = false

local BattleEnded = false

local CurrentBoss = ""

local CurrentDifficulty = ""

local BossInfoCache = {}

--==================================================

-- BATTLE EVENT TRACKER

--==================================================

BattleEvent.OnClientEvent:Connect(function(eventName, ...)

    if eventName == "battle_start" then

        BattleStarted = true

        BattleEnded = false

    elseif eventName == "battle_ended" then

        BattleEnded = true

    end

end)

--==================================================

-- GUI

--==================================================

local ScreenGui = Instance.new("ScreenGui")

ScreenGui.Name = "MIRACLE_AUTO"

ScreenGui.ResetOnSpawn = false

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

ScreenGui.Parent = Player:WaitForChild("PlayerGui")

--==================================================

-- MAIN

--==================================================

local Main = Instance.new("Frame")

Main.Name = "Main"

Main.Size = UDim2.fromOffset(360, 480)

Main.Position = UDim2.new(0.5, -180, 0.5, -240)

Main.BackgroundColor3 = Color3.fromRGB(226, 241, 255)

Main.BorderSizePixel = 0

Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")

MainCorner.CornerRadius = UDim.new(0, 16)

MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")

MainStroke.Color = Color3.fromRGB(93, 173, 235)

MainStroke.Thickness = 1.5

MainStroke.Transparency = 0.25

MainStroke.Parent = Main

--==================================================

-- TOP BAR

--==================================================

local TopBar = Instance.new("Frame")

TopBar.Size = UDim2.new(1, 0, 0, 62)

TopBar.BackgroundColor3 = Color3.fromRGB(190, 224, 252)

TopBar.BorderSizePixel = 0

TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")

TopCorner.CornerRadius = UDim.new(0, 16)

TopCorner.Parent = TopBar

local Title = Instance.new("TextLabel")

Title.Size = UDim2.new(1, -120, 0, 30)

Title.Position = UDim2.fromOffset(18, 8)

Title.BackgroundTransparency = 1

Title.Text = "MIRACLE"

Title.TextColor3 = Color3.fromRGB(25, 75, 120)

Title.TextSize = 19

Title.Font = Enum.Font.GothamBold

Title.TextXAlignment = Enum.TextXAlignment.Left

Title.Parent = TopBar

local Subtitle = Instance.new("TextLabel")

Subtitle.Size = UDim2.new(1, -120, 0, 20)

Subtitle.Position = UDim2.fromOffset(19, 34)

Subtitle.BackgroundTransparency = 1

Subtitle.Text = "AUTO BOSS  •  INFINITY TOWER"

Subtitle.TextColor3 = Color3.fromRGB(57, 119, 166)

Subtitle.TextSize = 10

Subtitle.Font = Enum.Font.GothamMedium

Subtitle.TextXAlignment = Enum.TextXAlignment.Left

Subtitle.Parent = TopBar

--==================================================

-- MINIMIZE

--==================================================

local Minimize = Instance.new("TextButton")

Minimize.Size = UDim2.fromOffset(34, 34)

Minimize.Position = UDim2.new(1, -82, 0, 14)

Minimize.BackgroundColor3 = Color3.fromRGB(103, 183, 240)

Minimize.BorderSizePixel = 0

Minimize.Text = "−"

Minimize.TextColor3 = Color3.fromRGB(255, 255, 255)

Minimize.TextSize = 22

Minimize.Font = Enum.Font.GothamBold

Minimize.Parent = TopBar

local MinCorner = Instance.new("UICorner")

MinCorner.CornerRadius = UDim.new(0, 9)

MinCorner.Parent = Minimize

--==================================================

-- CLOSE

--==================================================

local Close = Instance.new("TextButton")

Close.Size = UDim2.fromOffset(34, 34)

Close.Position = UDim2.new(1, -42, 0, 14)

Close.BackgroundColor3 = Color3.fromRGB(80, 145, 210)

Close.BorderSizePixel = 0

Close.Text = "×"

Close.TextColor3 = Color3.fromRGB(255, 255, 255)

Close.TextSize = 21

Close.Font = Enum.Font.GothamBold

Close.Parent = TopBar

local CloseCorner = Instance.new("UICorner")

CloseCorner.CornerRadius = UDim.new(0, 9)

CloseCorner.Parent = Close

--==================================================

-- CONTENT

--==================================================

local Content = Instance.new("Frame")

Content.Size = UDim2.new(1, 0, 1, -62)

Content.Position = UDim2.fromOffset(0, 62)

Content.BackgroundTransparency = 1

Content.Parent = Main

--==================================================

-- STATUS BOX

--==================================================

local StatusBox = Instance.new("Frame")

StatusBox.Size = UDim2.new(1, -32, 0, 118)

StatusBox.Position = UDim2.fromOffset(16, 15)

StatusBox.BackgroundColor3 = Color3.fromRGB(244, 250, 255)

StatusBox.BorderSizePixel = 0

StatusBox.Parent = Content

local StatusCorner = Instance.new("UICorner")

StatusCorner.CornerRadius = UDim.new(0, 12)

StatusCorner.Parent = StatusBox

local StatusTitle = Instance.new("TextLabel")

StatusTitle.Size = UDim2.new(1, -24, 0, 20)

StatusTitle.Position = UDim2.fromOffset(12, 10)

StatusTitle.BackgroundTransparency = 1

StatusTitle.Text = "STATUS"

StatusTitle.TextColor3 = Color3.fromRGB(70, 120, 160)

StatusTitle.TextSize = 11

StatusTitle.Font = Enum.Font.GothamBold

StatusTitle.TextXAlignment = Enum.TextXAlignment.Left

StatusTitle.Parent = StatusBox

local StatusLabel = Instance.new("TextLabel")

StatusLabel.Size = UDim2.new(1, -24, 0, 28)

StatusLabel.Position = UDim2.fromOffset(12, 31)

StatusLabel.BackgroundTransparency = 1

StatusLabel.Text = "IDLE"

StatusLabel.TextColor3 = Color3.fromRGB(25, 75, 120)

StatusLabel.TextSize = 19

StatusLabel.Font = Enum.Font.GothamBold

StatusLabel.TextXAlignment = Enum.TextXAlignment.Left

StatusLabel.Parent = StatusBox

local CurrentLabel = Instance.new("TextLabel")

CurrentLabel.Size = UDim2.new(1, -24, 0, 24)

CurrentLabel.Position = UDim2.fromOffset(12, 62)

CurrentLabel.BackgroundTransparency = 1

CurrentLabel.Text = "Waiting..."

CurrentLabel.TextColor3 = Color3.fromRGB(55, 105, 145)

CurrentLabel.TextSize = 13

CurrentLabel.Font = Enum.Font.GothamMedium

CurrentLabel.TextXAlignment = Enum.TextXAlignment.Left

CurrentLabel.Parent = StatusBox

local TimerLabel = Instance.new("TextLabel")

TimerLabel.Size = UDim2.new(1, -24, 0, 20)

TimerLabel.Position = UDim2.fromOffset(12, 87)

TimerLabel.BackgroundTransparency = 1

TimerLabel.Text = ""

TimerLabel.TextColor3 = Color3.fromRGB(35, 135, 220)

TimerLabel.TextSize = 12

TimerLabel.Font = Enum.Font.GothamBold

TimerLabel.TextXAlignment = Enum.TextXAlignment.Left

TimerLabel.Parent = StatusBox

--==================================================

-- PROGRESS

--==================================================

local ProgressLabel = Instance.new("TextLabel")

ProgressLabel.Size = UDim2.new(1, -32, 0, 24)

ProgressLabel.Position = UDim2.fromOffset(16, 143)

ProgressLabel.BackgroundTransparency = 1

ProgressLabel.Text = "BOSS PROGRESS     0 / 23 "

ProgressLabel.TextColor3 = Color3.fromRGB(70, 120, 160)

ProgressLabel.TextSize = 12

ProgressLabel.Font = Enum.Font.GothamBold

ProgressLabel.TextXAlignment = Enum.TextXAlignment.Left

ProgressLabel.Parent = Content

local ProgressBackground = Instance.new("Frame")

ProgressBackground.Size = UDim2.new(1, -32, 0, 7)

ProgressBackground.Position = UDim2.fromOffset(16, 169)

ProgressBackground.BackgroundColor3 = Color3.fromRGB(35, 39, 52)

ProgressBackground.BorderSizePixel = 0

ProgressBackground.Parent = Content

local ProgressCorner = Instance.new("UICorner")

ProgressCorner.CornerRadius = UDim.new(1, 0)

ProgressCorner.Parent = ProgressBackground

local ProgressFill = Instance.new("Frame")

ProgressFill.Size = UDim2.new(0, 0, 1, 0)

ProgressFill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)

ProgressFill.BorderSizePixel = 0

ProgressFill.Parent = ProgressBackground

local FillCorner = Instance.new("UICorner")

FillCorner.CornerRadius = UDim.new(1, 0)

FillCorner.Parent = ProgressFill

--==================================================

-- CURRENT BOSS

--==================================================

local BossBox = Instance.new("Frame")

BossBox.Size = UDim2.new(1, -32, 0, 70)

BossBox.Position = UDim2.fromOffset(16, 190)

BossBox.BackgroundColor3 = Color3.fromRGB(22, 25, 36)

BossBox.BorderSizePixel = 0

BossBox.Parent = Content

local BossCorner = Instance.new("UICorner")

BossCorner.CornerRadius = UDim.new(0, 11)

BossCorner.Parent = BossBox

local BossLabel = Instance.new("TextLabel")

BossLabel.Size = UDim2.new(1, -20, 0, 25)

BossLabel.Position = UDim2.fromOffset(10, 8)

BossLabel.BackgroundTransparency = 1

BossLabel.Text = "BOSS"

BossLabel.TextColor3 = Color3.fromRGB(70, 120, 160)

BossLabel.TextSize = 10

BossLabel.Font = Enum.Font.GothamBold

BossLabel.TextXAlignment = Enum.TextXAlignment.Left

BossLabel.Parent = BossBox

local BossName = Instance.new("TextLabel")

BossName.Size = UDim2.new(1, -20, 0, 30)

BossName.Position = UDim2.fromOffset(10, 31)

BossName.BackgroundTransparency = 1

BossName.Text = "None"

BossName.TextColor3 = Color3.fromRGB(25, 75, 120)

BossName.TextSize = 17

BossName.Font = Enum.Font.GothamBold

BossName.TextXAlignment = Enum.TextXAlignment.Left

BossName.Parent = BossBox

--==================================================
-- STAGE CONFIGURATION UI (PC + MOBILE)
--==================================================

local BossNames = {
    {id = "colossal_titan", label = "Colossal Titan"},
    {id = "thriller_king", label = "Thriller King"},
    {id = "red_dog", label = "Red Dog"},
    {id = "dragon_emperor", label = "Dragon Emperor"},
    {id = "curse_tyrant", label = "Curse Tyrant"},
    {id = "kikoru_shinomiya", label = "Kikoru Shinomiya"},
    {id = "soshiro_hoshina", label = "Soshiro Hoshina"},
    {id = "mina_ashiro", label = "Mina Ashiro"},
    {id = "gen_narumi", label = "Gen Narumi"},
    {id = "crimson_phantom", label = "Crimson Phantom (Secret)"},
}

local SelectedStages = {}
local SelectedParty = {} -- party/deck slot per boss (1-4)
local SelectedTowerParty = 1 -- party/deck slot used for Infinity Tower (1-4)
local SelectedTower = true

for _, bossInfo in ipairs(BossNames) do
    SelectedStages[bossInfo.id] = {}
    SelectedParty[bossInfo.id] = 1
    local available = BOSS_DIFFICULTIES[bossInfo.id] or DIFFICULTIES
    for _, difficulty in ipairs(available) do
        SelectedStages[bossInfo.id][difficulty] = true
    end
end

-- Default selection mirrors the supported difficulty list for each boss.
local ConfigButton = Instance.new("TextButton")
ConfigButton.Name = "ConfigButton"
ConfigButton.Size = UDim2.new(1, -32, 0, 34)
ConfigButton.Position = UDim2.fromOffset(16, 270)
ConfigButton.BackgroundColor3 = Color3.fromRGB(94, 174, 235)
ConfigButton.BorderSizePixel = 0
ConfigButton.Text = "STAGE SETTINGS  •  OPEN ▼"
ConfigButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ConfigButton.TextSize = 12
ConfigButton.Font = Enum.Font.GothamBold
ConfigButton.Parent = Content
local ConfigButtonCorner = Instance.new("UICorner")
ConfigButtonCorner.CornerRadius = UDim.new(0, 9)
ConfigButtonCorner.Parent = ConfigButton

local ConfigPanel = Instance.new("Frame")
ConfigPanel.Name = "ConfigPanel"
ConfigPanel.Size = UDim2.new(1, -24, 1, -78)
ConfigPanel.Position = UDim2.fromOffset(12, 5)
ConfigPanel.BackgroundColor3 = Color3.fromRGB(220, 239, 255)
ConfigPanel.BorderSizePixel = 0
ConfigPanel.Visible = false
ConfigPanel.ZIndex = 20
ConfigPanel.Parent = Content
local ConfigPanelCorner = Instance.new("UICorner")
ConfigPanelCorner.CornerRadius = UDim.new(0, 12)
ConfigPanelCorner.Parent = ConfigPanel

local ConfigTitle = Instance.new("TextLabel")
ConfigTitle.Size = UDim2.new(1, -100, 0, 30)
ConfigTitle.Position = UDim2.fromOffset(12, 8)
ConfigTitle.BackgroundTransparency = 1
ConfigTitle.Text = "CHOOSE STAGES / DIFFICULTY"
ConfigTitle.TextColor3 = Color3.fromRGB(25, 75, 120)
ConfigTitle.TextSize = 12
ConfigTitle.Font = Enum.Font.GothamBold
ConfigTitle.TextXAlignment = Enum.TextXAlignment.Left
ConfigTitle.ZIndex = 21
ConfigTitle.Parent = ConfigPanel

local ConfigClose = Instance.new("TextButton")
ConfigClose.Size = UDim2.fromOffset(30, 28)
ConfigClose.Position = UDim2.new(1, -40, 0, 8)
ConfigClose.BackgroundColor3 = Color3.fromRGB(90, 155, 220)
ConfigClose.BorderSizePixel = 0
ConfigClose.Text = "X"
ConfigClose.TextColor3 = Color3.new(1, 1, 1)
ConfigClose.TextSize = 13
ConfigClose.Font = Enum.Font.GothamBold
ConfigClose.ZIndex = 22
ConfigClose.Parent = ConfigPanel
local ConfigCloseCorner = Instance.new("UICorner")
ConfigCloseCorner.CornerRadius = UDim.new(0, 7)
ConfigCloseCorner.Parent = ConfigClose

local SelectAllButton = Instance.new("TextButton")
SelectAllButton.Size = UDim2.new(0.5, -18, 0, 28)
SelectAllButton.Position = UDim2.fromOffset(12, 42)
SelectAllButton.BackgroundColor3 = Color3.fromRGB(45, 135, 90)
SelectAllButton.BorderSizePixel = 0
SelectAllButton.Text = "SELECT ALL"
SelectAllButton.TextColor3 = Color3.new(1, 1, 1)
SelectAllButton.TextSize = 11
SelectAllButton.Font = Enum.Font.GothamBold
SelectAllButton.ZIndex = 21
SelectAllButton.Parent = ConfigPanel
local SelectAllCorner = Instance.new("UICorner")
SelectAllCorner.CornerRadius = UDim.new(0, 7)
SelectAllCorner.Parent = SelectAllButton

local ClearAllButton = Instance.new("TextButton")
ClearAllButton.Size = UDim2.new(0.5, -18, 0, 28)
ClearAllButton.Position = UDim2.new(0.5, 6, 0, 42)
ClearAllButton.BackgroundColor3 = Color3.fromRGB(145, 195, 235)
ClearAllButton.BorderSizePixel = 0
ClearAllButton.Text = "CLEAR ALL"
ClearAllButton.TextColor3 = Color3.new(1, 1, 1)
ClearAllButton.TextSize = 11
ClearAllButton.Font = Enum.Font.GothamBold
ClearAllButton.ZIndex = 21
ClearAllButton.Parent = ConfigPanel
local ClearAllCorner = Instance.new("UICorner")
ClearAllCorner.CornerRadius = UDim.new(0, 7)
ClearAllCorner.Parent = ClearAllButton

local ConfigScroll = Instance.new("ScrollingFrame")
ConfigScroll.Name = "ConfigScroll"
ConfigScroll.Size = UDim2.new(1, -16, 1, -112)
ConfigScroll.Position = UDim2.fromOffset(8, 78)
ConfigScroll.BackgroundColor3 = Color3.fromRGB(239, 248, 255)
ConfigScroll.BorderSizePixel = 0
ConfigScroll.ScrollBarThickness = 5
ConfigScroll.CanvasSize = UDim2.fromOffset(0, 0)
ConfigScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
ConfigScroll.ScrollingDirection = Enum.ScrollingDirection.Y
ConfigScroll.ZIndex = 21
ConfigScroll.Parent = ConfigPanel
local ConfigScrollCorner = Instance.new("UICorner")
ConfigScrollCorner.CornerRadius = UDim.new(0, 8)
ConfigScrollCorner.Parent = ConfigScroll
local ConfigListLayout = Instance.new("UIListLayout")
ConfigListLayout.Padding = UDim.new(0, 5)
ConfigListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ConfigListLayout.Parent = ConfigScroll
local ConfigPadding = Instance.new("UIPadding")
ConfigPadding.PaddingTop = UDim.new(0, 7)
ConfigPadding.PaddingLeft = UDim.new(0, 7)
ConfigPadding.PaddingRight = UDim.new(0, 7)
ConfigPadding.PaddingBottom = UDim.new(0, 7)
ConfigPadding.Parent = ConfigScroll

local NextLayoutOrder = 0
local CheckButtons = {}
local PartyButtons = {}
local TowerCheckButton
local function MakeCheckButton(parent, text, width, callback, height)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(width or 1, width and -4 or 0, 0, height or 28)
    button.BackgroundColor3 = Color3.fromRGB(185, 220, 249)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.fromRGB(28, 74, 112)
    button.TextSize = 10
    button.Font = Enum.Font.GothamMedium
    button.TextWrapped = true
    button.ZIndex = 22
    button.Parent = parent
    NextLayoutOrder += 1
    button.LayoutOrder = NextLayoutOrder
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button
    button.MouseButton1Click:Connect(callback)
    return button
end

local function RefreshStageButton(bossId, difficulty)
    local button = CheckButtons[bossId] and CheckButtons[bossId][difficulty]
    if not button then return end
    local enabled = SelectedStages[bossId][difficulty] == true
    button.Text = (enabled and "☑ " or "☐ ") .. difficulty
    button.BackgroundColor3 = enabled and Color3.fromRGB(72, 158, 225) or Color3.fromRGB(185, 220, 249)
end

local function RefreshBossHeader(bossInfo, header)
    local enabledCount = 0
    local available = BOSS_DIFFICULTIES[bossInfo.id] or DIFFICULTIES
    for _, difficulty in ipairs(available) do
        if SelectedStages[bossInfo.id][difficulty] then enabledCount += 1 end
    end
    header.Text = (enabledCount > 0 and "●  " or "○  ") .. bossInfo.label .. "  (tap to toggle all)"
    header.BackgroundColor3 = enabledCount > 0 and Color3.fromRGB(131, 196, 243) or Color3.fromRGB(185, 220, 249)
end

local BossHeaderButtons = {}
local function ToggleBoss(bossInfo)
    local available = BOSS_DIFFICULTIES[bossInfo.id] or DIFFICULTIES
    local allEnabled = true
    for _, difficulty in ipairs(available) do
        if not SelectedStages[bossInfo.id][difficulty] then
            allEnabled = false
            break
        end
    end
    for _, difficulty in ipairs(available) do
        SelectedStages[bossInfo.id][difficulty] = not allEnabled
        RefreshStageButton(bossInfo.id, difficulty)
    end
    RefreshBossHeader(bossInfo, BossHeaderButtons[bossInfo.id])
end

TowerCheckButton = MakeCheckButton(ConfigScroll, "", 1, function()
    SelectedTower = not SelectedTower
    TowerCheckButton.Text = (SelectedTower and "☑ " or "☐ ") .. "INFINITY TOWER"
    TowerCheckButton.BackgroundColor3 = SelectedTower and Color3.fromRGB(72, 158, 225) or Color3.fromRGB(185, 220, 249)
end, 32)
TowerCheckButton.Text = "☑ INFINITY TOWER"
TowerCheckButton.BackgroundColor3 = Color3.fromRGB(72, 158, 225)

-- Infinity Tower uses its own party/card-set selection, independent of each boss.
-- Forward-declare the button so the click callback updates this local button,
-- rather than accidentally resolving a global TowerPartyButton.
local TowerPartyButton
TowerPartyButton = MakeCheckButton(ConfigScroll, "", 1, function()
    SelectedTowerParty = (SelectedTowerParty % 4) + 1
    if TowerPartyButton then
        TowerPartyButton.Text = "   ◈ TOWER PARTY / CARD SET: " .. tostring(SelectedTowerParty) .. "   •   TAP TO CHANGE"
    end
end, 27)
TowerPartyButton.Text = "   ◈ TOWER PARTY / CARD SET: 1   •   TAP TO CHANGE"
TowerPartyButton.BackgroundColor3 = Color3.fromRGB(190, 225, 255)

for _, bossInfo in ipairs(BossNames) do
    local header = MakeCheckButton(ConfigScroll, "", 1, function()
        ToggleBoss(bossInfo)
    end, 30)
    BossHeaderButtons[bossInfo.id] = header
    RefreshBossHeader(bossInfo, header)

    local difficultyRow = Instance.new("Frame")
    difficultyRow.Size = UDim2.new(1, -2, 0, 29)
    difficultyRow.BackgroundTransparency = 1
    difficultyRow.BorderSizePixel = 0
    difficultyRow.ZIndex = 22
    difficultyRow.Parent = ConfigScroll
    NextLayoutOrder += 1
    difficultyRow.LayoutOrder = NextLayoutOrder
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    rowLayout.Padding = UDim.new(0, 4)
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Parent = difficultyRow
    CheckButtons[bossInfo.id] = {}

    local available = BOSS_DIFFICULTIES[bossInfo.id] or DIFFICULTIES
    for _, difficulty in ipairs(available) do
        local button = MakeCheckButton(difficultyRow, "", 1 / #available, function()
            SelectedStages[bossInfo.id][difficulty] = not SelectedStages[bossInfo.id][difficulty]
            RefreshStageButton(bossInfo.id, difficulty)
            RefreshBossHeader(bossInfo, header)
        end, 27)
        CheckButtons[bossInfo.id][difficulty] = button
        RefreshStageButton(bossInfo.id, difficulty)
    end

    -- Each boss gets its own party/deck slot selector.
    local partyButton = MakeCheckButton(ConfigScroll, "", 1, function()
        SelectedParty[bossInfo.id] = (SelectedParty[bossInfo.id] % 4) + 1
        PartyButtons[bossInfo.id].Text = "   ◈ PARTY / CARD SET: " .. tostring(SelectedParty[bossInfo.id]) .. "   •   TAP TO CHANGE"
    end, 25)
    PartyButtons[bossInfo.id] = partyButton
    partyButton.Text = "   ◈ PARTY / CARD SET: 1   •   TAP TO CHANGE"
    partyButton.BackgroundColor3 = Color3.fromRGB(211, 235, 255)
end

ConfigButton.MouseButton1Click:Connect(function()
    ConfigPanel.Visible = not ConfigPanel.Visible
    ConfigButton.Text = ConfigPanel.Visible and "STAGE SETTINGS  •  CLOSE ▲" or "STAGE SETTINGS  •  OPEN ▼"
end)
ConfigClose.MouseButton1Click:Connect(function()
    ConfigPanel.Visible = false
    ConfigButton.Text = "STAGE SETTINGS  •  OPEN ▼"
end)

local function SetAllSelections(enabled)
    for _, bossInfo in ipairs(BossNames) do
        local available = BOSS_DIFFICULTIES[bossInfo.id] or DIFFICULTIES
        for _, difficulty in ipairs(available) do
            SelectedStages[bossInfo.id][difficulty] = enabled
            RefreshStageButton(bossInfo.id, difficulty)
        end
        RefreshBossHeader(bossInfo, BossHeaderButtons[bossInfo.id])
    end
    SelectedTower = enabled
    TowerCheckButton.Text = (enabled and "☑ " or "☐ ") .. "INFINITY TOWER"
    TowerCheckButton.BackgroundColor3 = enabled and Color3.fromRGB(72, 158, 225) or Color3.fromRGB(185, 220, 249)
end
SelectAllButton.MouseButton1Click:Connect(function() SetAllSelections(true) end)
ClearAllButton.MouseButton1Click:Connect(function() SetAllSelections(false) end)

-- Scale the entire interface down on smaller screens, including phones.
local Camera = Workspace.CurrentCamera
local MobileScale = Instance.new("UIScale")
MobileScale.Name = "MobileScale"
MobileScale.Parent = Main
local function UpdateMobileScale()
    Camera = Workspace.CurrentCamera
    if not Camera then return end
    local viewport = Camera.ViewportSize
    MobileScale.Scale = math.clamp(math.min(viewport.X / 390, viewport.Y / 540, 1), 0.62, 1)
end
local ViewportConnection
local function BindCameraViewport()
    Camera = Workspace.CurrentCamera
    if ViewportConnection then ViewportConnection:Disconnect() end
    if Camera then
        ViewportConnection = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateMobileScale)
    end
    UpdateMobileScale()
end
BindCameraViewport()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(BindCameraViewport)

--==================================================

-- BUTTONS

--==================================================

local Start = Instance.new("TextButton")

Start.Size = UDim2.new(0.5, -22, 0, 50)

Start.Position = UDim2.fromOffset(16, 315)

Start.BackgroundColor3 = Color3.fromRGB(45, 155, 90)

Start.BorderSizePixel = 0

Start.Text = "START AUTO"

Start.TextColor3 = Color3.fromRGB(255, 255, 255)

Start.TextSize = 14

Start.Font = Enum.Font.GothamBold

Start.Parent = Content

local StartCorner = Instance.new("UICorner")

StartCorner.CornerRadius = UDim.new(0, 10)

StartCorner.Parent = Start

local Stop = Instance.new("TextButton")

Stop.Size = UDim2.new(0.5, -22, 0, 50)

Stop.Position = UDim2.new(0.5, 6, 0, 315)

Stop.BackgroundColor3 = Color3.fromRGB(90, 155, 220)

Stop.BorderSizePixel = 0

Stop.Text = "STOP"

Stop.TextColor3 = Color3.fromRGB(255, 255, 255)

Stop.TextSize = 14

Stop.Font = Enum.Font.GothamBold

Stop.Parent = Content

local StopCorner = Instance.new("UICorner")

StopCorner.CornerRadius = UDim.new(0, 10)

StopCorner.Parent = Stop

--==================================================

-- FOOTER

--==================================================

local Footer = Instance.new("TextLabel")

Footer.Size = UDim2.new(1, -32, 0, 50)

Footer.Position = UDim2.fromOffset(16, 455)

Footer.BackgroundTransparency = 1

Footer.Text =

    "AUTO ORDER\n" ..

    "Cart → Colossal → Sand → Crow → Worthy → Thriller → Dragon → Dad → Curse"

Footer.TextColor3 = Color3.fromRGB(105, 110, 130)

Footer.TextSize = 10

Footer.Font = Enum.Font.GothamMedium

Footer.TextXAlignment = Enum.TextXAlignment.Left

Footer.TextYAlignment = Enum.TextYAlignment.Top

Footer.Visible = false
Footer.Parent = Content

--==================================================

-- DRAG SYSTEM

--==================================================

local Dragging = false

local DragStart

local StartPosition

TopBar.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1

        or input.UserInputType == Enum.UserInputType.Touch then

        Dragging = true

        DragStart = input.Position

        StartPosition = UDim2.fromOffset(Main.AbsolutePosition.X, Main.AbsolutePosition.Y)

        input.Changed:Connect(function()

            if input.UserInputState == Enum.UserInputState.End then

                Dragging = false

            end

        end)

    end

end)

UserInputService.InputChanged:Connect(function(input)

    if not Dragging then

        return

    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement

        and input.UserInputType ~= Enum.UserInputType.Touch then

        return

    end

    local Delta = input.Position - DragStart

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local mainSize = Main.AbsoluteSize
    local x = math.clamp(StartPosition.X.Offset + Delta.X, 0, math.max(0, viewport.X - mainSize.X))
    local y = math.clamp(StartPosition.Y.Offset + Delta.Y, 0, math.max(0, viewport.Y - mainSize.Y))
    Main.Position = UDim2.fromOffset(x, y)

end)

--==================================================

-- MINIMIZE

--==================================================

local Minimized = false

local function SetMinimized(state)

    Minimized = state

    Content.Visible = not state
    ConfigPanel.Visible = false

    if state then

        -- Compact floating UI

        Main.Size = UDim2.fromOffset(180, 48)

        TopBar.Size = UDim2.new(1, 0, 1, 0)

        Title.Size = UDim2.new(0, 62, 1, 0)

        Title.Position = UDim2.fromOffset(10, 0)

        Title.TextSize = 15

        Title.Text = "MIRACLE"

        Subtitle.Visible = false

        Minimize.Size = UDim2.fromOffset(32, 32)

        Minimize.Position = UDim2.new(1, -70, 0, 8)

        Minimize.Text = "+"

        Close.Size = UDim2.fromOffset(32, 32)

        Close.Position = UDim2.new(1, -34, 0, 8)

    else

        -- Restore full UI

        Main.Size = UDim2.fromOffset(360, 480)

        TopBar.Size = UDim2.new(1, 0, 0, 62)

        Title.Size = UDim2.new(1, -120, 0, 30)

        Title.Position = UDim2.fromOffset(18, 8)

        Title.TextSize = 19

        Title.Text = "MIRACLE"

        Subtitle.Visible = true

        Minimize.Size = UDim2.fromOffset(34, 34)

        Minimize.Position = UDim2.new(1, -82, 0, 14)

        Minimize.Text = "−"

        Close.Size = UDim2.fromOffset(34, 34)

        Close.Position = UDim2.new(1, -42, 0, 14)

    end

end

Minimize.MouseButton1Click:Connect(function()

    SetMinimized(not Minimized)

end)

--==================================================

-- CLOSE

--==================================================

local ReopenButton = Instance.new("TextButton")
ReopenButton.Name = "MIRACLE_Reopen"
ReopenButton.Size = UDim2.fromOffset(54, 54)
ReopenButton.Position = UDim2.new(0, 16, 0.5, -27)
ReopenButton.BackgroundColor3 = Color3.fromRGB(80, 166, 235)
ReopenButton.BorderSizePixel = 0
ReopenButton.Text = "M"
ReopenButton.TextColor3 = Color3.new(1, 1, 1)
ReopenButton.TextSize = 22
ReopenButton.Font = Enum.Font.GothamBold
ReopenButton.Visible = false
ReopenButton.Parent = ScreenGui
local ReopenCorner = Instance.new("UICorner")
ReopenCorner.CornerRadius = UDim.new(1, 0)
ReopenCorner.Parent = ReopenButton

Close.MouseButton1Click:Connect(function()
    ConfigPanel.Visible = false
    Main.Visible = false
    ReopenButton.Visible = true
end)
-- Allow the floating M icon to be dragged while the main UI is hidden.
-- A short tap reopens the UI; moving the pointer/finger only drags the icon.
local ReopenDragging = false
local ReopenMoved = false
local ReopenStartInput = nil
local ReopenStartPosition = nil
local ReopenActiveInput = nil

ReopenButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        ReopenDragging = true
        ReopenMoved = false
        ReopenStartInput = input.Position
        ReopenStartPosition = UDim2.fromOffset(
            ReopenButton.AbsolutePosition.X,
            ReopenButton.AbsolutePosition.Y
        )
        ReopenActiveInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not ReopenDragging then
        return
    end

    local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
    local isTouchMove = input == ReopenActiveInput
    if not isMouseMove and not isTouchMove then
        return
    end

    local delta = input.Position - ReopenStartInput
    if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
        ReopenMoved = true
    end

    if ReopenMoved then
        local camera = Workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
        local buttonSize = ReopenButton.AbsoluteSize
        local x = math.clamp(ReopenStartPosition.X.Offset + delta.X, 0, math.max(0, viewport.X - buttonSize.X))
        local y = math.clamp(ReopenStartPosition.Y.Offset + delta.Y, 0, math.max(0, viewport.Y - buttonSize.Y))
        ReopenButton.Position = UDim2.fromOffset(x, y)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not ReopenDragging then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        local shouldReopen = not ReopenMoved
        ReopenDragging = false
        ReopenActiveInput = nil
        if shouldReopen then
            Main.Visible = true
            ReopenButton.Visible = false
        end
    end
end)

--==================================================

-- GUI FUNCTIONS

--==================================================

SetStatus = function(text)

    StatusLabel.Text = text

end

SetCurrent = function(text)

    CurrentLabel.Text = text

end

SetTimer = function(text)

    TimerLabel.Text = text

end

local function SetBoss(text)

    BossName.Text = text

end

local function SetProgress(number)

    number = tonumber(number) or 0

    ProgressLabel.Text =

        "BOSS PROGRESS     " ..

        tostring(number) ..

        " / " .. TOTAL_BOSS_RUNS

    local percent = math.clamp(number / TOTAL_BOSS_RUNS, 0, 1)

    TweenService:Create(

        ProgressFill,

        TweenInfo.new(0.25),

        {

            Size = UDim2.new(percent, 0, 1, 0)

        }

    ):Play()

end

--==================================================

-- GET REAL BOSS DATA

--==================================================

local function GetBossInfo(boss)

    local success, result = pcall(function()

        return RequestBossPrompt:InvokeServer(boss)

    end)

    if not success or type(result) ~= "table" then

        return nil

    end

    BossInfoCache[boss] = result

    return result

end

--==================================================

-- FIND DIFFICULTY

--==================================================

local function GetDifficultyInfo(boss, difficulty)

    local info = GetBossInfo(boss)

    if not info then

        return nil

    end

    if type(info.difficulties) ~= "table" then

        return nil

    end

    for _, data in ipairs(info.difficulties) do

        if data.name == difficulty then

            return data

        end

    end

    return nil

end

--==================================================

-- WAIT COOLDOWN

--==================================================

local function WaitForReady(boss, difficulty)

    while AutoEnabled do

        local data = GetDifficultyInfo(

            boss,

            difficulty

        )

        if not data then

            SetStatus("READING BOSS")

            SetCurrent(

                boss .. "  •  " .. difficulty

            )

            task.wait(1)

        else

            if data.unlocked == false then

                SetStatus("LOCKED")

                SetCurrent(

                    boss .. "  •  " .. difficulty

                )

                return false

            end

            local cooldown = tonumber(data.cooldown) or 0

            if cooldown <= 0 then

                SetTimer("READY")

                return true

            end

            SetStatus("COOLDOWN")

            SetCurrent(

                boss .. "  •  " .. difficulty

            )

            SetTimer(

                "Ready in  " ..

                string.format(

                    "%02d:%02d",

                    math.floor(cooldown / 60),

                    math.floor(cooldown % 60)

                )

            )

            task.wait(1)

        end

    end

    return false

end

--==================================================

-- WAIT BATTLE

--==================================================

local function WaitForBattleToFinish()

    BattleStarted = false

    BattleEnded = false

    local startTimeout = os.clock() + 15

    -- Wait for actual battle_start

    while AutoEnabled

        and not BattleStarted

        and os.clock() < startTimeout do

        task.wait(0.1)

    end

    if not BattleStarted then

        return false

    end

    SetStatus("BATTLE")

    SetTimer("Fighting...")

    -- IMPORTANT:

    -- Do NOT start next boss until battle_ended

    while AutoEnabled and not BattleEnded do

        SetCurrent(

            CurrentBoss ..

            "  •  " ..

            CurrentDifficulty

        )

        SetTimer("Waiting for battle to finish...")

        task.wait(0.2)

    end

    return BattleEnded

end

--==================================================

-- CHECK IF A DIFFICULTY IS ALREADY COMPLETED

--==================================================

local function IsDifficultyCompleted(boss, difficulty)

    local info = GetDifficultyInfo(boss, difficulty)

    if not info then

        return false

    end

    local completedFields = {

        "completed",

        "complete",

        "cleared",

        "clear",

        "finished",

        "isCompleted",

        "isCleared",

        "passed",

        "won",

        "victory"

    }

    for _, field in ipairs(completedFields) do

        if info[field] == true then

            return true

        end

    end

    local statusFields = {

        "status",

        "state",

        "result"

    }

    for _, field in ipairs(statusFields) do

        if type(info[field]) == "string" then

            local status = string.lower(info[field])

            if status == "completed"

                or status == "complete"

                or status == "cleared"

                or status == "clear"

                or status == "finished"

                or status == "passed"

                or status == "won"

                or status == "victory" then

                return true

            end

        end

    end

    return false

end

--==================================================

-- RUN ONE BOSS

--==================================================

local function RunBoss(

    boss,

    difficulty,

    progress

)

    if not AutoEnabled then

        return false

    end

    CurrentBoss = boss

    CurrentDifficulty = difficulty

    SetBoss(

        boss ..

        "  /  " ..

        difficulty

    )

    SetCurrent(

        boss ..

        "  •  " ..

        difficulty

    )

    -- Ensure the correct world is loaded before reading boss data.
    if not TeleportToBoss(boss) then
        return false
    end

    if not AutoEnabled then
        return false
    end

    --==========================================

    -- CHECK IF ALREADY COMPLETED

    --==========================================

    if IsDifficultyCompleted(boss, difficulty) then

        SetStatus("ALREADY COMPLETED")

        SetCurrent(

            boss ..

            "  •  " ..

            difficulty ..

            "  → SKIP"

        )

        SetTimer("Already cleared")

        task.wait(0.7)

        return "SKIPPED"

    end

    --==========================================

    -- WAIT COOLDOWN / UNLOCK

    --==========================================

    if not WaitForReady(

        boss,

        difficulty

    ) then

        return false

    end

    if not AutoEnabled then

        return false

    end

    -- Check again after waiting.

    if IsDifficultyCompleted(boss, difficulty) then

        SetStatus("ALREADY COMPLETED")

        SetCurrent(

            boss ..

            "  •  " ..

            difficulty ..

            "  → SKIP"

        )

        SetTimer("Already cleared")

        task.wait(0.7)

        return "SKIPPED"

    end

    --==========================================

    -- START BATTLE

    --==========================================

    BattleStarted = false

    BattleEnded = false

    SetStatus("STARTING")

    SetTimer("Entering battle...")
    ChallengeBoss:FireServer(
        boss,
        difficulty
    )

    --==========================================

    -- WAIT FOR REAL BATTLE

    --==========================================

    local completed =

        WaitForBattleToFinish()

    if not completed then

        return false

    end

    task.wait(0.5)

    --==========================================

    -- VERIFY RESULT

    --==========================================

    local info = GetDifficultyInfo(

        boss,

        difficulty

    )

    if info then

        SetStatus("COMPLETED")

        SetTimer("Battle finished")

    end

    SetProgress(progress)

    task.wait(1)

    return true

end

--==================================================

-- INFINITY TOWER

--==================================================

local function RunInfinityTower()

    if not AutoEnabled then

        return false

    end

    SetBoss("INFINITY TOWER")

    SetStatus("INFINITY TOWER")

    SetCurrent(

        "Running Infinity Tower"

    )

    SetTimer(

        "Starting..."

    )

    if not TeleportToTower() then
        return false
    end

    if not AutoEnabled then
        return false
    end

    -- Switch to the card set chosen specifically for Infinity Tower.
    SetStatus("SWITCHING TOWER CARD SET")
    SetCurrent("Infinity Tower • Party / Card Set " .. tostring(SelectedTowerParty))
    local swapOk, swapErr = pcall(function()
        SwapParty:FireServer(SelectedTowerParty)
    end)
    if not swapOk then
        warn("Could not switch party for Infinity Tower:", swapErr)
        SetStatus("TOWER PARTY SWITCH FAILED")
        return false
    end
    task.wait(0.8)

    if not AutoEnabled then
        return false
    end

    RunInfTower:FireServer()

    local StartTime = os.clock()

    while AutoEnabled do

        local elapsed =

            os.clock() - StartTime

        local remaining =

            INFINITY_DURATION - elapsed

        if remaining <= 0 then

            break

        end

        SetStatus("INFINITY TOWER")

        SetCurrent(

            "Tower is running..."

        )

        SetTimer(

            string.format(

                "Remaining  %02d:%02d",

                math.floor(remaining / 60),

                math.floor(remaining % 60)

            )

        )

        task.wait(1)

    end

    if not AutoEnabled then

        return false

    end

    -- Pause

    SetStatus("PAUSING TOWER")

    SetCurrent(

        "Sending PAUSE..."

    )

    SetTimer("")

    InfinityTowerAction:FireServer(

        "pause"

    )

    task.wait(2)

    return true

end

--==================================================

-- MAIN AUTO

--==================================================

local function StartAuto()

    if Busy then

        return

    end

    Busy = true

    AutoEnabled = true

    Start.Text = "AUTO RUNNING"

    local selectedBossCount = 0
    for _, bossInfo in ipairs(BossNames) do
        for _, difficulty in ipairs(BOSS_DIFFICULTIES[bossInfo.id] or DIFFICULTIES) do
            if SelectedStages[bossInfo.id][difficulty] then selectedBossCount += 1 end
        end
    end
    if selectedBossCount == 0 and not SelectedTower then
        SetStatus("NOTHING SELECTED")
        SetCurrent("Open STAGE SETTINGS and select a stage")
        Busy = false
        AutoEnabled = false
        Start.Text = "START AUTO"
        return
    end

    TOTAL_BOSS_RUNS = math.max(selectedBossCount, 1)
    SetProgress(0)
    local progress = 0

    while AutoEnabled do
        local didAnyBoss = false
        for _, bossInfo in ipairs(BossNames) do
            local boss = bossInfo.id
            local selectedDifficulties = {}
            for _, difficulty in ipairs(BOSS_DIFFICULTIES[boss] or DIFFICULTIES) do
                if SelectedStages[boss][difficulty] then
                    table.insert(selectedDifficulties, difficulty)
                end
            end

            if #selectedDifficulties > 0 and AutoEnabled then
                didAnyBoss = true
                local partyReady = true
                local partyNumber = SelectedParty[boss] or 1
                SetStatus("SWITCHING CARD SET")
                SetCurrent(bossInfo.label .. " • Party / Card Set " .. tostring(partyNumber))
                local swapOk, swapErr = pcall(function()
                    SwapParty:FireServer(partyNumber)
                end)
                if not swapOk then
                    warn("Could not switch party for " .. boss .. ":", swapErr)
                    partyReady = false
                else
                    task.wait(0.8)
                end
                if partyReady and boss == "crimson_phantom" then
                    -- Always return to Lobby first, then move to the exact secret encounter point.
                    SetStatus("RETURNING TO LOBBY")
                    SetCurrent("Crimson Phantom requires Lobby reset")
                    local lobbyOk, lobbyErr = pcall(function()
                        TeleportToArea:FireServer("lobby", nil)
                    end)
                    if not lobbyOk then
                        warn("Could not return to Lobby before Crimson Phantom:", lobbyErr)
                        partyReady = false
                    else
                        ActiveWorldKey = "lobby|nil"
                        ActiveNpcBoss = nil
                        task.wait(3)
                    end
                end

                if partyReady then
                    for _, difficulty in ipairs(selectedDifficulties) do
                        if not AutoEnabled then break end
                        local result = RunBoss(boss, difficulty, progress + 1)
                        if result == true then
                            progress += 1
                            SetProgress(progress)
                        elseif result == false then
                            -- Stop this boss's remaining difficulties on failure.
                            break
                        end
                    end
                end

            end
            if not AutoEnabled then break end
        end

        if not AutoEnabled then break end
        if SelectedTower then
            RunInfinityTower()
        end
        if not AutoEnabled then break end

        -- Match the previous behavior: boss selections repeat until STOP;
        -- Tower-only selection runs once.
        if not didAnyBoss then break end
        progress = 0
        SetProgress(0)
        SetStatus("NEXT ROUND")
        SetCurrent("Starting selected stages again")
        task.wait(2)
    end

    Busy = false

    Start.Text = "START AUTO"

    SetStatus("IDLE")

    SetCurrent("Stopped")

    SetTimer("")

    SetBoss("None")

end

--==================================================

-- START

--==================================================

Start.MouseButton1Click:Connect(function()

    if AutoEnabled then

        return

    end

    task.spawn(StartAuto)

end)

--==================================================

-- STOP

--==================================================

Stop.MouseButton1Click:Connect(function()

    AutoEnabled = false

    SetStatus("STOPPING")

    SetCurrent(

        "Waiting for current action..."

    )

    SetTimer("")

end)

