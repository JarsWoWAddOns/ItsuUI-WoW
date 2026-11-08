-- Itsu:UI: player + target cast bars

local _, ns = ...

ns.RegisterModule("cast", "Cast Bars", function()

local playerCastbar, targetCastbar
local JarsCastbarDB = ns.db.cast

local function InitDB()
    JarsCastbarDB.playerY = JarsCastbarDB.playerY or -200
    JarsCastbarDB.width = JarsCastbarDB.width or 200
    JarsCastbarDB.targetY = JarsCastbarDB.targetY or -135
    if JarsCastbarDB.showTarget == nil then JarsCastbarDB.showTarget = true end
end

-- Update player castbar position
local function UpdatePlayerPosition(yPos)
    JarsCastbarDB.playerY = yPos
    if playerCastbar then
        playerCastbar:ClearAllPoints()
        playerCastbar:SetPoint("TOP", UIParent, "CENTER", 0, yPos)
    end
end

-- Update target castbar position
local function UpdateTargetPosition(yPos)
    JarsCastbarDB.targetY = yPos
    if targetCastbar then
        targetCastbar:ClearAllPoints()
        targetCastbar:SetPoint("TOP", UIParent, "CENTER", 0, yPos)
    end
end

-- Update castbar width
local function UpdateWidth(width)
    JarsCastbarDB.width = width
    if playerCastbar then
        playerCastbar:SetWidth(width)
        playerCastbar.Bar:SetWidth(width - 4)
    end
    if targetCastbar then
        targetCastbar:SetWidth(width)
        targetCastbar.Bar:SetWidth(width - 4)
    end
end

-- texture + font come from the shared settings
local function ApplyMedia()
    local texture, font = ns.GetTexture(), ns.GetFont()
    for _, bar in ipairs({ playerCastbar, targetCastbar }) do
        bar.Bar:SetStatusBarTexture(texture)
        bar.Text:SetFont(font, 12, "OUTLINE")
        bar.Time:SetFont(font, 12, "OUTLINE")
    end
end

-- remaining time as "2.3", same as the old string.format
local timeFormatter = C_StringUtil.CreateNumericRuleFormatter()
timeFormatter:AddBreakpoint({ threshold = 0, format = "%.1f" })

-- 1px black edge on all four sides, no size math
local function AddEdges(f)
    local function edge(p1, p2, w, h)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

-- Create a castbar frame
local function CreateCastbar(unit)
    local frame = CreateFrame("Frame", "JarsCastbar_" .. unit, UIParent)
    frame:SetSize(JarsCastbarDB.width, 24)
    frame:SetFrameStrata("MEDIUM")
    
    -- Background
    frame.Bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.Bg:SetAllPoints()
    frame.Bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Border
    -- frame.Border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- frame.Border:SetAllPoints()
    -- frame.Border:SetBackdrop({
    --     edgeFile = "Interface\\Buttons\\WHITE8X8",
    --     edgeSize = 1,
    -- })
    -- frame.Border:SetBackdropBorderColor(0, 0, 0, 1)
    -- plain 1px edges, the backdrop template's OnSizeChanged did math on a secret width
    frame.Border = CreateFrame("Frame", nil, frame)
    frame.Border:SetAllPoints()
    AddEdges(frame.Border)

    -- Status bar
    local texturePath = ns.GetTexture()
    frame.Bar = CreateFrame("StatusBar", nil, frame)
    frame.Bar:SetPoint("TOPLEFT", 2, -2)
    frame.Bar:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.Bar:SetStatusBarTexture(texturePath)
    frame.Bar:SetMinMaxValues(0, 1)
    frame.Bar:SetValue(0)
    
    -- Spell name text
    local fontPath = ns.GetFont()
    frame.Text = frame.Bar:CreateFontString(nil, "OVERLAY")
    frame.Text:SetFont(fontPath, 12, "OUTLINE")
    frame.Text:SetPoint("LEFT", frame.Bar, "LEFT", 4, 0)
    frame.Text:SetTextColor(1, 1, 1)
    
    -- Time text
    frame.Time = frame.Bar:CreateFontString(nil, "OVERLAY")
    frame.Time:SetFont(fontPath, 12, "OUTLINE")
    frame.Time:SetPoint("RIGHT", frame.Bar, "RIGHT", -4, 0)
    frame.Time:SetTextColor(1, 1, 1)
    
    -- Spell icon
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetSize(20, 20)
    frame.Icon:SetPoint("RIGHT", frame, "LEFT", -4, 0)
    frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Icon border
    frame.IconBorder = CreateFrame("Frame", nil, frame)
    frame.IconBorder:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
    frame.IconBorder:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)
    AddEdges(frame.IconBorder)
    
    -- Empower stage pips (markers)
    frame.stagePips = {}
    for i = 1, 4 do
        local pip = frame.Bar:CreateTexture(nil, "OVERLAY")
        pip:SetSize(2, 24)
        pip:SetColorTexture(0, 0, 0, 0.8)
        pip:Hide()
        frame.stagePips[i] = pip
    end

    -- time text drives itself off the duration obj
    frame.timeBinding = C_DurationUtil.CreateDurationTextBinding()
    frame.timeBinding:SetFormatter(timeFormatter)
    frame.timeBinding:SetFontString(frame.Time)
    frame.timeBinding:SetEnabled(true)

    frame.unit = unit
    frame.casting = false
    frame.channeling = false
    frame.empowering = false
    frame.castBarID = nil
    frame.duration = nil
    frame.stagePcts = nil

    return frame
end

local GREY = CreateColor(0.7, 0.7, 0.7)
local CAST_COLOR = CreateColor(1.0, 0.7, 0.0)
local CHANNEL_COLOR = CreateColor(0.0, 1.0, 0.0)
local ELAPSED = Enum.StatusBarTimerDirection.ElapsedTime
local REMAINING = Enum.StatusBarTimerDirection.RemainingTime
local SMOOTHING = Enum.StatusBarInterpolation.Immediate

local STAGE_COLORS = {
    { 0.2, 0.5, 0.8 },  -- Dark blue
    { 0.3, 0.7, 1.0 },  -- Medium blue
    { 0.5, 0.8, 1.0 },  -- Bright blue
    { 0.7, 0.6, 1.0 },  -- Purple
}

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
}

-- where castBarID sits in the payload after unit, its always the last arg
local CASTBAR_ID_ARG = {
    UNIT_SPELLCAST_STOP = 3,
    UNIT_SPELLCAST_FAILED = 3,
    UNIT_SPELLCAST_DELAYED = 3,
    UNIT_SPELLCAST_CHANNEL_UPDATE = 3,
    UNIT_SPELLCAST_EMPOWER_UPDATE = 3,
    UNIT_SPELLCAST_INTERRUPTED = 4,
    UNIT_SPELLCAST_CHANNEL_STOP = 4,
    UNIT_SPELLCAST_EMPOWER_STOP = 5,
}

local function RegisterCastEvents(frame, unit)
    for _, event in ipairs(CAST_EVENTS) do
        frame:RegisterUnitEvent(event, unit)
    end
end

-- secret means its there, we just cant look at it
local function HasValue(v)
    return issecretvalue(v) or v ~= nil
end

local function IsOurCast(self, castBarID)
    return castBarID == nil or self.castBarID == nil or castBarID == self.castBarID
end

local function ClearCast(self)
    self.casting = false
    self.channeling = false
    self.empowering = false
    self.castBarID = nil
    self.duration = nil
    self.stagePcts = nil
    for i = 1, 4 do
        self.stagePips[i]:Hide()
    end
end

local function SetTimer(self, duration, direction)
    if not HasValue(duration) then return end
    self.duration = duration
    self.Bar:SetTimerDuration(duration, SMOOTHING, direction)
    self.timeBinding:SetDuration(duration)
end

local function SetInterruptColor(self, notInterruptible, color)
    -- self.Bar:SetStatusBarColor(1.0, 0.7, 0.0)
    -- pcall(function()
    --     if notInterruptible then
    --         self.Bar:SetStatusBarColor(0.7, 0.7, 0.7)
    --     end
    -- end)
    -- can be nil sometimes, api wants a real bool
    if not issecretvalue(notInterruptible) then
        notInterruptible = notInterruptible and true or false
    end
    self.Bar:GetStatusBarTexture():SetVertexColorFromBoolean(notInterruptible, GREY, color)
end

-- pip at the end of each stage, last entry is the hold so no pip there
local function PlaceStagePips(self)
    local pcts = UnitEmpoweredStagePercentages(self.unit)
    if not pcts or issecretvalue(pcts[1]) then return end
    self.stagePcts = pcts

    local width = self.Bar:GetWidth()
    local cumulative = 0
    for i = 1, #pcts - 1 do
        cumulative = cumulative + pcts[i]
        local pip = self.stagePips[i]
        if pip and cumulative > 0 and cumulative < 1 then
            pip:ClearAllPoints()
            pip:SetPoint("BOTTOM", self.Bar, "BOTTOMLEFT", width * cumulative, 0)
            pip:SetPoint("TOP", self.Bar, "TOPLEFT", width * cumulative, 0)
            pip:Show()
        end
    end
end

-- picks up whatever the unit is doing right now, cast/channel/empower
local function StartCast(self)
    local unit = self.unit
    ClearCast(self)

    local name, text, texture, _, _, _, _, notInterruptible, _, castBarID = UnitCastingInfo(unit)
    local isEmpowered, numStages, duration, direction, color
    if HasValue(name) then
        self.casting = true
        duration, direction, color = UnitCastingDuration(unit), ELAPSED, CAST_COLOR
    else
        name, text, texture, _, _, _, notInterruptible, _, isEmpowered, numStages, castBarID = UnitChannelInfo(unit)
        if not HasValue(name) then
            self:Hide()
            return
        end
        if isEmpowered then
            -- includes hold at max by default
            self.empowering = true
            duration, direction = UnitEmpoweredChannelDuration(unit), ELAPSED
        else
            self.channeling = true
            duration, direction, color = UnitChannelDuration(unit), REMAINING, CHANNEL_COLOR
        end
    end

    if not HasValue(duration) then
        ClearCast(self)
        self:Hide()
        return
    end

    self.castBarID = castBarID
    SetTimer(self, duration, direction)
    self.Text:SetText(text)
    self.Icon:SetTexture(texture)

    if self.empowering then
        -- Blue color for empower
        self.Bar:SetStatusBarColor(0.3, 0.7, 1.0)
        self:Show()
        -- pips after show so width is good
        if numStages and numStages > 0 then
            PlaceStagePips(self)
        end
    else
        SetInterruptColor(self, notInterruptible, color)
        self:Show()
    end
end

-- Update castbar
local function OnUpdate(self)
    if not self.casting and not self.channeling and not self.empowering then
        self:Hide()
        return
    end

    -- stage colors, only when progress is readable (the player basically)
    if self.empowering and self.stagePcts and not issecretvalue(self.duration) then
        local elapsed = self.duration:GetElapsedPercent()
        if issecretvalue(elapsed) then return end

        local cumulative, stage = 0, #self.stagePcts
        for i, pct in ipairs(self.stagePcts) do
            cumulative = cumulative + pct
            if elapsed < cumulative then
                stage = i - 1
                break
            end
        end
        self.Bar:SetStatusBarColor(unpack(STAGE_COLORS[math.min(stage, 3) + 1]))
    end
end

-- Castbar event handlers
local function OnEvent(self, event, unit, ...)
    if unit ~= self.unit then return end

    local idx = CASTBAR_ID_ARG[event]
    local castBarID = idx and (select(idx, ...))

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        StartCast(self)

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- failed spam press has a diff id, ignore it
        if not IsOurCast(self, castBarID) then return end

        -- Don't hide if we're channeling and the channel is still active
        if (self.channeling or self.empowering) and event ~= "UNIT_SPELLCAST_CHANNEL_STOP" and event ~= "UNIT_SPELLCAST_EMPOWER_STOP" then
            if HasValue(UnitChannelInfo(unit)) then return end
        end
        ClearCast(self)
        self:Hide()

    elseif event == "UNIT_SPELLCAST_DELAYED" then
        if self.casting and IsOurCast(self, castBarID) then
            SetTimer(self, UnitCastingDuration(unit), ELAPSED)
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if self.channeling and IsOurCast(self, castBarID) then
            SetTimer(self, UnitChannelDuration(unit), REMAINING)
        end

    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        if self.empowering and IsOurCast(self, castBarID) then
            SetTimer(self, UnitEmpoweredChannelDuration(unit), ELAPSED)
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self.Bar:SetStatusBarColor(self.channeling and 0.0 or 1.0, self.channeling and 1.0 or 0.7, 0.0)

    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self.Bar:SetStatusBarColor(0.7, 0.7, 0.7)
    end
end

-- Create player castbar
local function CreatePlayerCastbar()
    playerCastbar = CreateCastbar("player")
    playerCastbar:SetPoint("TOP", UIParent, "CENTER", 0, JarsCastbarDB.playerY)

    playerCastbar:SetScript("OnUpdate", OnUpdate)
    playerCastbar:SetScript("OnEvent", OnEvent)
    RegisterCastEvents(playerCastbar, "player")

    playerCastbar:Hide()
end

local function RegisterTargetEvents()
    targetCastbar:RegisterEvent("PLAYER_TARGET_CHANGED")
    RegisterCastEvents(targetCastbar, "target")
end

-- Create target castbar
local function CreateTargetCastbar()
    targetCastbar = CreateCastbar("target")
    targetCastbar:SetPoint("TOP", UIParent, "CENTER", 0, JarsCastbarDB.targetY)

    targetCastbar:SetScript("OnUpdate", OnUpdate)
    targetCastbar:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_TARGET_CHANGED" then
            -- clears old state + checks new target for cast/channel/empower
            StartCast(self)
        else
            OnEvent(self, event, ...)
        end
    end)

    if JarsCastbarDB.showTarget then
        RegisterTargetEvents()
    end
    targetCastbar:Hide()
end

-- blizz target bar, only hidden while ours is on
local function SetBlizzardTargetBarHidden(hide)
    local bar = TargetFrameSpellBar
    if not bar then return end

    if hide then
        bar:UnregisterAllEvents()
        bar:Hide()
    else
        -- same stuff TargetFrame + CastingBarMixin:SetUnit register
        RegisterCastEvents(bar, "target")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar:RegisterEvent("PLAYER_TARGET_CHANGED")
        bar:RegisterEvent("CVAR_UPDATE")
        bar:RegisterEvent("VARIABLES_LOADED")
        bar:SetAlpha(1)
    end
end

-- Toggle target castbar
local function ToggleTargetCastbar(show)
    JarsCastbarDB.showTarget = show
    if not targetCastbar then return end

    if show then
        RegisterTargetEvents()
        SetBlizzardTargetBarHidden(true)
        StartCast(targetCastbar)
    else
        targetCastbar:UnregisterAllEvents()
        ClearCast(targetCastbar)
        targetCastbar:Hide()
        SetBlizzardTargetBarHidden(false)
    end
end

-- Hide Blizzard cast bars
local function HideBlizzardCastbars()
    -- oUF way, edit mode still shows it but it hides again on exit
    if PlayerCastingBarFrame then
        PlayerCastingBarFrame:UnregisterAllEvents()
        PlayerCastingBarFrame:Hide()
        -- PlayerCastingBarFrame:SetAlpha(0)
    end

    if JarsCastbarDB.showTarget then
        SetBlizzardTargetBarHidden(true)
    end
end

ns.RegisterPanel(40, "Cast Bars", function(b)
    b:Header("Player")
    b:Slider("Vertical Position", -500, 500, 5,
        function() return JarsCastbarDB.playerY end,
        UpdatePlayerPosition)

    b:Header("Target")
    b:Check("Show Target Cast Bar  (replaces Blizzard's)",
        function() return JarsCastbarDB.showTarget end,
        ToggleTargetCastbar)
    b:Slider("Vertical Position", -500, 500, 5,
        function() return JarsCastbarDB.targetY end,
        UpdateTargetPosition)

    b:Header("Both")
    b:Slider("Width", 150, 600, 10,
        function() return JarsCastbarDB.width end,
        UpdateWidth)
    b:Buttons({ { "Reset to Defaults", function()
        UpdatePlayerPosition(-200)
        UpdateTargetPosition(-135)
        UpdateWidth(200)
        ToggleTargetCastbar(true)
        b:Refresh()
    end, 160 } })
end)

SLASH_JARSCASTBAR1 = "/jarscastbar"
SLASH_JARSCASTBAR2 = "/jcb"
SlashCmdList["JARSCASTBAR"] = function() ns.OpenConfig("Cast Bars") end

InitDB()
CreatePlayerCastbar()
CreateTargetCastbar()
ApplyMedia()
ns.OnShared(ApplyMedia)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", HideBlizzardCastbars)

end)
