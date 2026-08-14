--[[
    RSS Style Celebration GUI -- R15 ONLY

    Same GUI
    Same emotes
    Emote plays while moving
    WASD does not replace the emote
    Jumping/falling does not replace the emote
    Emote repeats
    Selected emote returns after death
]]

local Players = game:GetService("Players")
local CAS = game:GetService("ContextActionService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

---------------------------------------------------
-- PREVENT DUPLICATES
---------------------------------------------------

if PlayerGui:FindFirstChild("RSSCelebrations") then
    return
end

---------------------------------------------------
-- EMOTES
---------------------------------------------------

local Emotes = {
    { name = "Failed Backflip", id = 82250437555780 },
    { name = "Mbappe Celebration", id = 101032415365235 },
    { name = "FF LOL Laugh", id = 129709531895539 },
    { name = "Take The L", id = 133005847117851 },

    { name = "Hide", id = 84868707350198 },
    { name = "Orbital Body", id = 73124249069461 },
    { name = "Druski Shuffle Dance", id = 108939580037531 },
    { name = "Pasito cumbia", id = 139816236849217 },
    { name = "Hakari Dance", id = 122147154162464 },
    { name = "Ronaldo Siuuu Celebration", id = 107447321843426 },

    { name = "Chinese Dance", id = 87149979837754 },
    { name = "Cholo Cumbia", id = 131035546452795 },
    { name = "Crazy", id = 120819498172771 },
    { name = "Default Dance OG", id = 80877772569772 },

    { name = "Tall Scary Creature", id = 79216795769647 },
    { name = "Zero Two Dance V2", id = 95385842020103 },
    { name = "Cute Sit", id = 87715072383313 },
    { name = "Gangnam Style", id = 80923445784018 },
}

---------------------------------------------------
-- STATE
---------------------------------------------------

local SelectedEmote = nil
local CurrentTrack = nil
local Character = nil
local Humanoid = nil
local AnimateScript = nil

local Generation = 0

---------------------------------------------------
-- CHARACTER SETUP
---------------------------------------------------

local function SetupCharacter(NewCharacter)

    Character = NewCharacter
    Humanoid = nil
    AnimateScript = nil
    CurrentTrack = nil

    Humanoid = NewCharacter:WaitForChild(
        "Humanoid",
        10
    )

    if not Humanoid then
        return false
    end

    -- Wait for R15 Animate to appear
    task.wait(0.3)

    AnimateScript =
        NewCharacter:FindFirstChild("Animate")

    return true
end

---------------------------------------------------
-- ENABLE DEFAULT ANIMATIONS
---------------------------------------------------

local function EnableAnimate()

    if AnimateScript then

        pcall(function()
            AnimateScript.Disabled = false
        end)

    elseif Character then

        local Animate =
            Character:FindFirstChild("Animate")

        if Animate then

            pcall(function()
                Animate.Disabled = false
            end)

        end
    end
end

---------------------------------------------------
-- DISABLE DEFAULT ANIMATIONS
---------------------------------------------------

local function DisableAnimate()

    if AnimateScript then

        pcall(function()
            AnimateScript.Disabled = true
        end)

    elseif Character then

        local Animate =
            Character:FindFirstChild("Animate")

        if Animate then

            AnimateScript = Animate

            pcall(function()
                Animate.Disabled = true
            end)

        end
    end
end

---------------------------------------------------
-- STOP CURRENT EMOTE
---------------------------------------------------

local function StopCurrentEmote()

    Generation += 1

    if CurrentTrack then

        pcall(function()
            CurrentTrack:Stop(0)
        end)

        pcall(function()
            CurrentTrack:Destroy()
        end)

        CurrentTrack = nil
    end

    -- Restore normal Roblox animations
    EnableAnimate()
end

---------------------------------------------------
-- PLAY EMOTE
---------------------------------------------------

local function PlaySelectedEmote()

    if not SelectedEmote then
        return
    end

    if not Character or not Humanoid then
        return
    end

    if Humanoid.Health <= 0 then
        return
    end

    local MyGeneration = Generation

    ------------------------------------------------
    -- IMPORTANT:
    -- PLAY EMOTE FIRST
    -- DO NOT DISABLE ANIMATE YET
    ------------------------------------------------

    local Success, Track = pcall(function()

        return Humanoid:PlayEmoteAndGetAnimTrackById(
            tostring(SelectedEmote.id)
        )

    end)

    ------------------------------------------------
    -- FALLBACK
    ------------------------------------------------

    if not Success or not Track then

        local Description =
            Humanoid:FindFirstChildOfClass(
                "HumanoidDescription"
            )

        if not Description then

            Description =
                Instance.new("HumanoidDescription")

            Description.Parent = Humanoid
        end

        pcall(function()

            Description:AddEmote(
                SelectedEmote.name,
                SelectedEmote.id
            )

        end)

        Success, Track = pcall(function()

            return Humanoid:PlayEmoteAndGetAnimTrackById(
                tostring(SelectedEmote.id)
            )

        end)
    end

    ------------------------------------------------
    -- FAILED
    ------------------------------------------------

    if not Success or not Track then

        warn(
            "[RSS Celebrations] Failed to play:",
            SelectedEmote.name,
            SelectedEmote.id
        )

        return
    end

    ------------------------------------------------
    -- REQUEST WAS CANCELLED
    ------------------------------------------------

    if MyGeneration ~= Generation then

        pcall(function()
            Track:Stop(0)
        end)

        return
    end

    ------------------------------------------------
    -- SAVE TRACK
    ------------------------------------------------

    CurrentTrack = Track

    ------------------------------------------------
    -- HIGH PRIORITY
    ------------------------------------------------

    pcall(function()

        Track.Priority =
            Enum.AnimationPriority.Action4

    end)

    ------------------------------------------------
    -- NOW DISABLE DEFAULT ANIMATE
    --
    -- The emote has already been created.
    ------------------------------------------------

    DisableAnimate()

    ------------------------------------------------
    -- REPLAY WHEN FINISHED
    ------------------------------------------------

    Track.Stopped:Connect(function()

        if MyGeneration ~= Generation then
            return
        end

        if CurrentTrack ~= Track then
            return
        end

        if not SelectedEmote then
            return
        end

        CurrentTrack = nil

        task.wait(0.05)

        if MyGeneration ~= Generation then
            return
        end

        if SelectedEmote
            and Humanoid
            and Humanoid.Health > 0 then

            PlaySelectedEmote()

        end
    end)
end

---------------------------------------------------
-- SELECT EMOTE
---------------------------------------------------

local function PlayEmote(Name, Id)

    ------------------------------------------------
    -- STOP PREVIOUS
    ------------------------------------------------

    StopCurrentEmote()

    ------------------------------------------------
    -- SAVE NEW EMOTE
    ------------------------------------------------

    SelectedEmote = {
        name = Name,
        id = Id
    }

    ------------------------------------------------
    -- PLAY
    ------------------------------------------------

    task.spawn(function()

        task.wait(0.1)

        if SelectedEmote then
            PlaySelectedEmote()
        end

    end)
end

---------------------------------------------------
-- CHARACTER SPAWN
---------------------------------------------------

Player.CharacterAdded:Connect(function(NewCharacter)

    -- New character means old track is gone
    CurrentTrack = nil

    local Ready =
        SetupCharacter(NewCharacter)

    if not Ready then
        return
    end

    ------------------------------------------------
    -- RESTART SELECTED EMOTE
    ------------------------------------------------

    if SelectedEmote then

        task.spawn(function()

            task.wait(0.5)

            if Character == NewCharacter
                and SelectedEmote
                and Humanoid
                and Humanoid.Health > 0 then

                PlaySelectedEmote()

            end

        end)
    end
end)

---------------------------------------------------
-- INITIAL CHARACTER
---------------------------------------------------

if Player.Character then

    SetupCharacter(Player.Character)

end

---------------------------------------------------
-- GUI
---------------------------------------------------

local ScreenGui =
    Instance.new("ScreenGui")

ScreenGui.Name =
    "RSSCelebrations"

ScreenGui.ResetOnSpawn = false

ScreenGui.Parent =
    PlayerGui

---------------------------------------------------
-- MAIN
---------------------------------------------------

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.new(0,260,0,300)

Main.Position =
    UDim2.new(1,-280,0.5,-150)

Main.BackgroundColor3 =
    Color3.fromRGB(15,15,15)

Main.BorderSizePixel = 0

Main.Active = true
Main.Draggable = true

Main.Parent = ScreenGui

Instance.new("UICorner", Main).CornerRadius =
    UDim.new(0,12)

---------------------------------------------------
-- TOP BAR
---------------------------------------------------

local TopBar =
    Instance.new("Frame")

TopBar.Size =
    UDim2.new(1,0,0,35)

TopBar.BackgroundColor3 =
    Color3.fromRGB(25,25,25)

TopBar.BorderSizePixel = 0

TopBar.Parent = Main

Instance.new("UICorner", TopBar).CornerRadius =
    UDim.new(0,12)

---------------------------------------------------
-- TITLE
---------------------------------------------------

local Title =
    Instance.new("TextLabel")

Title.Size =
    UDim2.new(1,-35,1,0)

Title.Position =
    UDim2.new(0,8,0,0)

Title.BackgroundTransparency = 1

Title.Text =
    "Celebrations"

Title.TextColor3 =
    Color3.new(1,1,1)

Title.TextScaled = true

Title.Font =
    Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent = TopBar

---------------------------------------------------
-- CLOSE
---------------------------------------------------

local Close =
    Instance.new("TextButton")

Close.Size =
    UDim2.new(0,25,0,25)

Close.Position =
    UDim2.new(1,-30,0.5,-12)

Close.Text = "X"

Close.TextColor3 =
    Color3.new(1,1,1)

Close.BackgroundColor3 =
    Color3.fromRGB(170,0,0)

Close.TextScaled = true

Close.Parent = TopBar

Instance.new("UICorner", Close).CornerRadius =
    UDim.new(1,0)

Close.MouseButton1Click:Connect(function()

    Main.Visible = false

end)

---------------------------------------------------
-- SCROLL
---------------------------------------------------

local Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.new(0,8,0,40)

Scroll.Size =
    UDim2.new(1,-16,1,-48)

Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Scroll.ScrollBarThickness = 4

Scroll.BackgroundTransparency = 1

Scroll.BorderSizePixel = 0

Scroll.Parent = Main

---------------------------------------------------
-- GRID
---------------------------------------------------

local Grid =
    Instance.new("UIGridLayout")

Grid.CellSize =
    UDim2.new(0,75,0,75)

Grid.CellPadding =
    UDim2.new(0,6,0,6)

Grid.Parent = Scroll

---------------------------------------------------
-- BUTTONS
---------------------------------------------------

for _, emote in pairs(Emotes) do

    local Button =
        Instance.new("ImageButton")

    Button.Size =
        UDim2.new(0,75,0,75)

    Button.BackgroundColor3 =
        Color3.fromRGB(35,35,35)

    Button.BorderSizePixel = 0

    Button.Image =
        "rbxthumb://type=Asset&id="
        .. tostring(emote.id)
        .. "&w=150&h=150"

    Button.Parent = Scroll

    Instance.new("UICorner", Button).CornerRadius =
        UDim.new(0,10)

    ------------------------------------------------
    -- LABEL
    ------------------------------------------------

    local Label =
        Instance.new("TextLabel")

    Label.Size =
        UDim2.new(1,0,1,0)

    Label.BackgroundTransparency = 0.4

    Label.BackgroundColor3 =
        Color3.fromRGB(0,0,0)

    Label.Text =
        "<b>" .. emote.name .. "</b>"

    Label.RichText = true

    Label.TextScaled = true

    Label.TextColor3 =
        Color3.new(1,1,1)

    Label.Font =
        Enum.Font.GothamBold

    Label.Parent = Button

    Instance.new("UICorner", Label).CornerRadius =
        UDim.new(0,10)

    ------------------------------------------------
    -- CLICK
    ------------------------------------------------

    Button.MouseButton1Click:Connect(function()

        PlayEmote(
            emote.name,
            emote.id
        )

    end)
end

---------------------------------------------------
-- PC TOGGLE
---------------------------------------------------

local function Toggle(_, State)

    if State == Enum.UserInputState.Begin then

        Main.Visible =
            not Main.Visible

    end

    return Enum.ContextActionResult.Sink
end

CAS:BindAction(
    "OpenRSSCelebrations",
    Toggle,
    false,
    Enum.KeyCode.Comma
)

---------------------------------------------------
-- MOBILE TOGGLE
---------------------------------------------------

local ToggleButton =
    Instance.new("TextButton")

ToggleButton.Size =
    UDim2.new(0,45,0,45)

ToggleButton.Position =
    UDim2.new(1,-85,1,-150)

ToggleButton.BackgroundColor3 =
    Color3.fromRGB(20,20,20)

ToggleButton.Text = "🎉"

ToggleButton.TextScaled = true

ToggleButton.TextColor3 =
    Color3.new(1,1,1)

ToggleButton.Parent =
    ScreenGui

ToggleButton.Active = true
ToggleButton.Draggable = true

Instance.new("UICorner", ToggleButton).CornerRadius =
    UDim.new(1,0)

local IsOpen = true

ToggleButton.MouseButton1Click:Connect(function()

    IsOpen = not IsOpen

    Main.Visible = IsOpen

end)
