-- Itsu:UI: immersion style quest + gossip text bubble

local _, ns = ...

ns.RegisterModule("npc", "NPC Chat", function()

-- JarsNPCChat: Immersion-style quest/gossip text bubble UI
-- Replaces default QuestFrame and GossipFrame with a centered, auto-sized text bubble
-- Action buttons are positioned to the right of the bubble

---------------------------------------------------------------------------
-- Constants & Style
---------------------------------------------------------------------------
local BUBBLE_PADDING = 20
local BUBBLE_MIN_WIDTH = 350
local BUBBLE_MAX_WIDTH = 550
local BUTTON_WIDTH = 100
local BUTTON_HEIGHT = 28
local BUTTON_GAP = 6
local FONT = ns.GetFont()
local JarsNPCChatDB = ns.db.npc

local STYLE = {
    bg        = { 0.10, 0.10, 0.12, 0.92 },
    border    = { 0.25, 0.25, 0.28, 1 },
    title     = { 1.0, 0.82, 0.0 },
    body      = { 0.95, 0.95, 0.95 },
    option    = { 0.6, 0.85, 1.0 },
    optHover  = { 1.0, 0.82, 0.0 },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local currentState = nil
local selectedReward = nil
local blizzGossip = false

local TITLE_MIN, TITLE_MAX = 10, 33

---------------------------------------------------------------------------
-- Saved Variables defaults
---------------------------------------------------------------------------
local DEFAULTS = {
    fontSize = 15,
    titleFontSize = 18,
}

---------------------------------------------------------------------------
-- Option button pool
---------------------------------------------------------------------------
local optionButtonPool = {}
local activeOptionButtons = {}

---------------------------------------------------------------------------
-- Reward button pool
---------------------------------------------------------------------------
local rewardButtonPool = {}
local activeRewardButtons = {}

---------------------------------------------------------------------------
-- Main Frame (invisible anchor)
---------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame", "JarsNPCChatFrame", UIParent)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame:SetSize(1, 1)
mainFrame:SetFrameStrata("DIALOG")
mainFrame:Hide()

tinsert(UISpecialFrames, "JarsNPCChatFrame")

---------------------------------------------------------------------------
-- Text Bubble
---------------------------------------------------------------------------
local bubble = CreateFrame("Frame", "JarsNPCChatBubble", mainFrame, "BackdropTemplate")
bubble:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
bubble:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
})
bubble:SetBackdropColor(unpack(STYLE.bg))
bubble:SetBackdropBorderColor(unpack(STYLE.border))
bubble:EnableMouse(true)
bubble:SetHyperlinksEnabled(true)

-- Tooltip for inline hyperlinks (item/spell links) in quest/gossip text
bubble:SetScript("OnHyperlinkEnter", function(self, link)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end)
bubble:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
end)
bubble:SetScript("OnHyperlinkClick", function(self, link, _, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then
            -- ChatEdit_InsertLink(link)
            ChatFrameUtil.InsertLink(link)
        end
    end
end)

-- Title
local titleText = bubble:CreateFontString(nil, "OVERLAY")
titleText:SetFont(FONT, DEFAULTS.titleFontSize, "")
titleText:SetTextColor(unpack(STYLE.title))
titleText:SetJustifyH("LEFT")
titleText:SetPoint("TOPLEFT", bubble, "TOPLEFT", BUBBLE_PADDING, -BUBBLE_PADDING)
titleText:SetPoint("TOPRIGHT", bubble, "TOPRIGHT", -BUBBLE_PADDING, -BUBBLE_PADDING)

-- Body
local bodyText = bubble:CreateFontString(nil, "OVERLAY")
bodyText:SetFont(FONT, DEFAULTS.fontSize, "")
bodyText:SetTextColor(unpack(STYLE.body))
bodyText:SetJustifyH("LEFT")
bodyText:SetWordWrap(true)
bodyText:SetSpacing(3)
bodyText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -10)

-- Options panel (RIGHT of bubble, above action buttons, for gossip/quest options)
local optionsPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
optionsPanel:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
})
optionsPanel:SetBackdropColor(unpack(STYLE.bg))
optionsPanel:SetBackdropBorderColor(unpack(STYLE.border))
optionsPanel:Hide()

local optionsList = CreateFrame("Frame", nil, optionsPanel)
optionsList:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 10, -10)
optionsList:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -10, -10)

-- Reward frame container
local rewardFrame = CreateFrame("Frame", nil, bubble)
rewardFrame:SetPoint("RIGHT", bubble, "RIGHT", -BUBBLE_PADDING, 0)
rewardFrame:EnableMouse(true)
rewardFrame:Hide()

local rewardLabel = rewardFrame:CreateFontString(nil, "OVERLAY")
rewardLabel:SetFont(FONT, 12, "")
rewardLabel:SetTextColor(unpack(STYLE.title))
rewardLabel:SetJustifyH("LEFT")
rewardLabel:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", 0, 0)

-- second row label for fixed rewards when theres choices too
local rewardLabel2 = rewardFrame:CreateFontString(nil, "OVERLAY")
rewardLabel2:SetFont(FONT, 12, "")
rewardLabel2:SetTextColor(unpack(STYLE.title))
rewardLabel2:SetJustifyH("LEFT")

local moneyText = rewardFrame:CreateFontString(nil, "OVERLAY")
moneyText:SetFont(FONT, 12, "")
moneyText:SetTextColor(unpack(STYLE.body))
moneyText:SetJustifyH("LEFT")

---------------------------------------------------------------------------
-- Button Panel (right of bubble, below options panel)
---------------------------------------------------------------------------
local buttonPanel = CreateFrame("Frame", nil, mainFrame)
buttonPanel:SetWidth(BUTTON_WIDTH)
buttonPanel:SetHeight(1)

-- buttonPanel position is set dynamically in PositionRightPanels

local MAX_ACTION_BUTTONS = 3
local actionButtons = {}
for i = 1, MAX_ACTION_BUTTONS do
    local btn = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate")
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetPoint("TOP", buttonPanel, "TOP", 0, -((i - 1) * (BUTTON_HEIGHT + BUTTON_GAP)))
    btn:Hide()
    actionButtons[i] = btn
end

---------------------------------------------------------------------------
-- Button configurations per state
---------------------------------------------------------------------------
local STATE_BUTTONS = {
    GOSSIP = {
        { text = "Close", action = function() C_GossipInfo.CloseGossip() end },
    },
    QUEST_OFFER = {
        { text = "Accept", action = function() AcceptQuest() end },
        { text = "Decline", action = function() DeclineQuest() end },
    },
    QUEST_AUTO = {
        { text = "OK", action = function() AcknowledgeAutoAcceptQuest() end },
    },
    QUEST_GREETING = {
        { text = "Close", action = function() CloseQuest() end },
    },
    QUEST_PROGRESS = {
        { text = "Continue", action = function() CompleteQuest() end, condition = IsQuestCompletable },
        { text = "Close", action = function() CloseQuest() end },
    },
    QUEST_COMPLETE = {
        -- { text = "Complete", action = function() GetQuestReward(selectedReward) end },
        { text = "Complete", action = function()
            if (GetNumQuestChoices() or 0) > 1 and not selectedReward then
                UIErrorsFrame:AddMessage("Pick a reward first.", 1, 0.1, 0.1)
                return
            end
            GetQuestReward(selectedReward)
        end },
    },
}

local function SetActionButtons(state)
    local config = STATE_BUTTONS[state]
    for i = 1, MAX_ACTION_BUTTONS do
        local btn = actionButtons[i]
        local cfg = config and config[i]
        if cfg then
            -- Check condition (e.g. IsQuestCompletable)
            if cfg.condition and not cfg.condition() then
                btn:Hide()
            else
                btn:SetText(cfg.text)
                btn:SetScript("OnClick", function() cfg.action() end)
                btn:Show()
            end
        else
            btn:Hide()
        end
    end
    -- Adjust panel height
    local visibleCount = 0
    for i = 1, MAX_ACTION_BUTTONS do
        if actionButtons[i]:IsShown() then visibleCount = visibleCount + 1 end
    end
    buttonPanel:SetHeight(math.max(visibleCount * (BUTTON_HEIGHT + BUTTON_GAP) - BUTTON_GAP, 1))
end

---------------------------------------------------------------------------
-- Bubble auto-sizing
---------------------------------------------------------------------------
local function ResizeBubble()
    -- Measure body text at max width
    bodyText:SetWidth(BUBBLE_MAX_WIDTH - (BUBBLE_PADDING * 2))
    bodyText:SetText(bodyText:GetText() or "")

    local rawWidth = bodyText:GetStringWidth()
    if rawWidth then rawWidth = tonumber(rawWidth) else rawWidth = 0 end
    local contentWidth = math.min(rawWidth + (BUBBLE_PADDING * 2) + 4, BUBBLE_MAX_WIDTH)
    contentWidth = math.max(contentWidth, BUBBLE_MIN_WIDTH)

    -- Re-wrap at chosen width
    bodyText:SetWidth(contentWidth - (BUBBLE_PADDING * 2))

    local titleHeight = titleText:GetStringHeight() or 0
    if titleHeight then titleHeight = tonumber(titleHeight) else titleHeight = 0 end
    titleHeight = titleHeight + 10

    local bodyHeight = bodyText:GetStringHeight() or 0
    if bodyHeight then bodyHeight = tonumber(bodyHeight) else bodyHeight = 0 end

    local rewardsHeight = rewardFrame:IsShown() and (rewardFrame:GetHeight() + 12) or 0

    local totalHeight = BUBBLE_PADDING + titleHeight + bodyHeight + rewardsHeight + BUBBLE_PADDING
    totalHeight = math.max(totalHeight, 80)

    bubble:SetSize(contentWidth, totalHeight)

    -- Position the reward frame below body
    rewardFrame:SetPoint("TOPLEFT", bodyText, "BOTTOMLEFT", 0, -12)
end

---------------------------------------------------------------------------
-- Option button helpers
---------------------------------------------------------------------------
local function GetOptionButton()
    local btn
    if #optionButtonPool > 0 then
        btn = table.remove(optionButtonPool)
    else
        btn = CreateFrame("Button", nil, optionsList)
        btn:SetHeight(26)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(20, 20)
        btn.icon:SetPoint("LEFT", 4, 0)

        btn.label = btn:CreateFontString(nil, "OVERLAY")
        btn.label:SetFont(FONT, 14, "")
        btn.label:SetJustifyH("LEFT")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)

        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)

        btn:SetScript("OnEnter", function(self)
            self.label:SetTextColor(unpack(STYLE.optHover))
        end)
        btn:SetScript("OnLeave", function(self)
            self.label:SetTextColor(unpack(STYLE.option))
        end)
    end
    btn:Show()
    table.insert(activeOptionButtons, btn)
    return btn
end

local function ReleaseAllOptionButtons()
    for _, btn in ipairs(activeOptionButtons) do
        btn:Hide()
        btn:SetScript("OnClick", nil)
        table.insert(optionButtonPool, btn)
    end
    wipe(activeOptionButtons)
end

---------------------------------------------------------------------------
-- Reward button helpers
---------------------------------------------------------------------------
local function GetRewardButton()
    local btn
    if #rewardButtonPool > 0 then
        btn = table.remove(rewardButtonPool)
    else
        btn = CreateFrame("Button", nil, rewardFrame)
        btn:SetSize(36, 36)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(32, 32)
        btn.icon:SetPoint("CENTER")
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn.border = btn:CreateTexture(nil, "OVERLAY")
        btn.border:SetSize(36, 36)
        btn.border:SetPoint("CENTER")
        btn.border:SetColorTexture(0.5, 0.5, 0.5, 0.6)
        btn.border:Hide()

        btn.selected = btn:CreateTexture(nil, "OVERLAY")
        btn.selected:SetSize(38, 38)
        btn.selected:SetPoint("CENTER")
        btn.selected:SetColorTexture(1, 0.82, 0, 0.4)
        btn.selected:Hide()

        btn:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    btn:Show()
    table.insert(activeRewardButtons, btn)
    return btn
end

local function ReleaseAllRewardButtons()
    for _, btn in ipairs(activeRewardButtons) do
        btn:Hide()
        btn:SetScript("OnClick", nil)
        btn.selected:Hide()
        btn.link = nil
        table.insert(rewardButtonPool, btn)
    end
    wipe(activeRewardButtons)
end

local function UpdateRewardSelection()
    for _, btn in ipairs(activeRewardButtons) do
        if btn.isChoice then
            btn.selected:SetShown(btn.index == selectedReward)
        end
    end
end

---------------------------------------------------------------------------
-- UI State Handlers
---------------------------------------------------------------------------
local function PositionRightPanels()
    -- Position options panel and button panel on the right side of the bubble
    buttonPanel:ClearAllPoints()
    optionsPanel:ClearAllPoints()

    if #activeOptionButtons > 0 then
        -- Measure the widest option label
        local maxWidth = 0
        for _, btn in ipairs(activeOptionButtons) do
            local labelWidth = tonumber(btn.label:GetStringWidth()) or 0
            local iconWidth = btn.icon:IsShown() and 26 or 0
            local totalW = iconWidth + labelWidth
            if totalW > maxWidth then maxWidth = totalW end
        end
        local panelWidth = maxWidth + 20 + 8  -- 10 padding each side + buffer
        panelWidth = math.max(panelWidth, 180)
        panelWidth = math.min(panelWidth, 350)

        local panelHeight = (#activeOptionButtons * 28) + 20  -- 10 padding top/bottom
        optionsPanel:SetSize(panelWidth, panelHeight)
        optionsList:SetSize(panelWidth - 20, #activeOptionButtons * 28)

        -- Set explicit width on each option button so it's clickable
        for _, btn in ipairs(activeOptionButtons) do
            btn:SetWidth(panelWidth - 20)
        end

        optionsPanel:SetPoint("TOPLEFT", bubble, "TOPRIGHT", 10, 0)
        optionsPanel:Show()

        -- Button panel goes below the options panel
        buttonPanel:SetPoint("TOPLEFT", optionsPanel, "BOTTOMLEFT", 0, -6)
    else
        optionsPanel:Hide()
        -- Button panel anchors directly to bubble right
        buttonPanel:SetPoint("TOPLEFT", bubble, "TOPRIGHT", 10, 0)
    end
end

local function HideUI()
    currentState = nil  -- clear BEFORE hiding so OnHide doesn't re-close gossip (would cancel bank open)
    mainFrame:Hide()
    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardFrame:Hide()
    selectedReward = nil
end

local function ShowGossip()
    currentState = "GOSSIP"

    titleText:SetText(UnitName("npc") or "NPC")

    local gossipText = C_GossipInfo.GetText and C_GossipInfo.GetText() or ""
    bodyText:SetText(gossipText)

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    rewardFrame:Hide()

    local options = C_GossipInfo.GetOptions() or {}
    -- same order blizz uses
    table.sort(options, function(a, b) return a.orderIndex < b.orderIndex end)
    local availableQuests = C_GossipInfo.GetAvailableQuests() or {}
    local activeQuests = C_GossipInfo.GetActiveQuests() or {}

    local yOffset = 0

    -- Available quests
    for _, quest in ipairs(availableQuests) do
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(quest.title)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            C_GossipInfo.SelectAvailableQuest(quest.questID)
        end)
        yOffset = yOffset + 26
    end

    -- Active quests
    for _, quest in ipairs(activeQuests) do
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(quest.title)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            C_GossipInfo.SelectActiveQuest(quest.questID)
        end)
        yOffset = yOffset + 26
    end

    -- Gossip options
    for _, option in ipairs(options) do
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(option.name)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture(option.icon or "Interface\\GossipFrame\\GossipGossipIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            C_GossipInfo.SelectOption(option.gossipOptionID)
        end)
        yOffset = yOffset + 26
    end

    PositionRightPanels()

    SetActionButtons("GOSSIP")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestOffer()
    currentState = "QUEST_OFFER"

    titleText:SetText(GetTitleText())
    bodyText:SetText(GetQuestText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardFrame:Hide()

    PositionRightPanels()
    -- auto accept quests only get an OK
    SetActionButtons(QuestGetAutoAccept() and "QUEST_AUTO" or "QUEST_OFFER")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestGreeting()
    currentState = "QUEST_GREETING"

    titleText:SetText(UnitName("npc") or "NPC")
    bodyText:SetText(GetGreetingText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    rewardFrame:Hide()

    local yOffset = 0

    -- Active quests
    local numActive = GetNumActiveQuests() or 0
    for i = 1, numActive do
        local title, isComplete = GetActiveTitle(i)
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        if isComplete then
            btn.label:SetText(title)
            btn.label:SetTextColor(unpack(STYLE.option))
        else
            btn.label:SetText(title)
            btn.label:SetTextColor(0.6, 0.6, 0.6)
        end
        btn.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            SelectActiveQuest(i)
        end)
        yOffset = yOffset + 26
    end

    -- Available quests
    local numAvailable = GetNumAvailableQuests() or 0
    for i = 1, numAvailable do
        local title = GetAvailableTitle(i)
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(title)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            SelectAvailableQuest(i)
        end)
        yOffset = yOffset + 26
    end

    PositionRightPanels()

    SetActionButtons("QUEST_GREETING")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestProgress()
    currentState = "QUEST_PROGRESS"

    titleText:SetText(GetTitleText())
    bodyText:SetText(GetProgressText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardFrame:Hide()

    PositionRightPanels()
    SetActionButtons("QUEST_PROGRESS")
    ResizeBubble()
    mainFrame:Show()
end

-- one row of reward icons, returns the new y
local function AddRewardRow(label, kind, count, y, isChoice)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", 0, y)
    label:Show()
    for i = 1, count do
        local _, texture = GetQuestItemInfo(kind, i)
        local btn = GetRewardButton()
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", (i - 1) * 40, y - 18)
        btn.icon:SetTexture(texture)
        btn.link = GetQuestItemLink(kind, i)
        btn.index = isChoice and i or nil
        btn.isChoice = isChoice
        btn.selected:SetShown(isChoice and i == selectedReward)
        if isChoice then
            btn:SetScript("OnClick", function(self)
                selectedReward = self.index
                UpdateRewardSelection()
            end)
        end
    end
    return y - 58
end

local function ShowQuestComplete()
    currentState = "QUEST_COMPLETE"
    selectedReward = nil

    titleText:SetText(GetTitleText())
    bodyText:SetText(GetRewardText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardLabel:Hide()
    rewardLabel2:Hide()
    moneyText:Hide()

    local numChoices = GetNumQuestChoices() or 0
    local numRewards = GetNumQuestRewards() or 0
    local money = GetRewardMoney() or 0

    if numChoices > 0 or numRewards > 0 or money > 0 then
        rewardFrame:Show()
        local y = 0

        if numChoices > 0 then
            rewardLabel:SetText("Choose a reward:")
            -- selectedReward = 1
            if numChoices == 1 then selectedReward = 1 end
            y = AddRewardRow(rewardLabel, "choice", numChoices, y, true)
        end

        if numRewards > 0 then
            local label = numChoices > 0 and rewardLabel2 or rewardLabel
            label:SetText(numChoices > 0 and "You will also receive:" or "You will receive:")
            y = AddRewardRow(label, "reward", numRewards, y, false)
        end

        if money > 0 then
            moneyText:ClearAllPoints()
            moneyText:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", 0, y)
            moneyText:SetText(C_CurrencyInfo.GetCoinTextureString(money, 12))
            moneyText:Show()
            y = y - 18
        end

        rewardFrame:SetSize(math.max(math.max(numChoices, numRewards) * 40, 100), -y)
    else
        rewardFrame:Hide()
    end

    PositionRightPanels()
    SetActionButtons("QUEST_COMPLETE")
    ResizeBubble()
    mainFrame:Show()
end

---------------------------------------------------------------------------
-- Default frame suppression
---------------------------------------------------------------------------
local function SuppressDefaultFrames()
    -- Retail uses CustomGossipFrameManager for gossip (not GossipFrame)
    if CustomGossipFrameManager then
        CustomGossipFrameManager:UnregisterEvent("GOSSIP_SHOW")
        CustomGossipFrameManager:UnregisterEvent("GOSSIP_CLOSED")
    end

    -- Classic uses GossipFrame
    if GossipFrame then
        GossipFrame:UnregisterEvent("GOSSIP_SHOW")
        GossipFrame:UnregisterEvent("GOSSIP_CLOSED")
        GossipFrame:UnregisterEvent("QUEST_LOG_UPDATE")
    end

    -- Suppress the quest frame
    if QuestFrame then
        QuestFrame:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------
-- OnHide: close server-side interaction
---------------------------------------------------------------------------
mainFrame:SetScript("OnHide", function()
    if currentState == "GOSSIP" then
        C_GossipInfo.CloseGossip()
    elseif currentState then
        CloseQuest()
    end
    currentState = nil
end)

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("QUEST_ITEM_UPDATE")

-- only close if the close event matches what we're showing, and the npc is really gone
local GOSSIP_STATES = { GOSSIP = true }
local QUEST_STATES = { QUEST_OFFER = true, QUEST_GREETING = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true }

local function IsStillTalking()
    local pim = C_PlayerInteractionManager
    return pim.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.Gossip)
        or pim.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.QuestGiver)
end

local function HideWhenDone(states)
    C_Timer.After(0, function()
        if not states[currentState] then return end
        if IsStillTalking() then return end
        HideUI()
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        for k, v in pairs(DEFAULTS) do
            if JarsNPCChatDB[k] == nil then
                JarsNPCChatDB[k] = v
            end
        end

        -- Apply saved font sizes
        JarsNPCChatDB.titleFontSize = math.min(math.max(JarsNPCChatDB.titleFontSize, TITLE_MIN), TITLE_MAX)
        titleText:SetFont(ns.GetFont(), JarsNPCChatDB.titleFontSize, "")
        bodyText:SetFont(ns.GetFont(), JarsNPCChatDB.fontSize, "")

        SuppressDefaultFrames()

    elseif event == "GOSSIP_SHOW" then
        local textureKit = ...
        if textureKit and CustomGossipFrameManager then
            -- delve pickers etc, let blizz do it
            HideUI()
            blizzGossip = true
            CustomGossipFrameManager:HandleOpenEvent(textureKit)
        else
            ShowGossip()
        end

    elseif event == "GOSSIP_CLOSED" then
        if blizzGossip then
            blizzGossip = false
            CustomGossipFrameManager:HideOpenedUIPanel(...)
        end
        HideWhenDone(GOSSIP_STATES)

    elseif event == "QUEST_FINISHED" then
        HideWhenDone(QUEST_STATES)

    elseif event == "QUEST_ITEM_UPDATE" then
        -- redraw rewards, keep whatever they picked
        if currentState == "QUEST_COMPLETE" then
            local keep = selectedReward
            ShowQuestComplete()
            selectedReward = keep or selectedReward
            UpdateRewardSelection()
        end

    elseif event == "QUEST_DETAIL" then
        ShowQuestOffer()

    elseif event == "QUEST_GREETING" then
        ShowQuestGreeting()

    elseif event == "QUEST_PROGRESS" then
        ShowQuestProgress()

    elseif event == "QUEST_COMPLETE" then
        ShowQuestComplete()
    end
end)

---------------------------------------------------------------------------
-- Small API so JarStick (gamepad) can drive the buttons
---------------------------------------------------------------------------
JarsNPCChatAPI = {
    frame = mainFrame,
    GetState = function() return currentState end,
    GetSelectedReward = function() return selectedReward end,
    GetOptions = function() return activeOptionButtons end, -- top to bottom
    GetActions = function()
        local shown = {}
        for i = 1, MAX_ACTION_BUTTONS do
            if actionButtons[i]:IsShown() then shown[#shown + 1] = actionButtons[i] end
        end
        return shown
    end,
    GetRewardChoices = function()
        local choices = {}
        for _, btn in ipairs(activeRewardButtons) do
            if btn.isChoice then choices[#choices + 1] = btn end
        end
        table.sort(choices, function(a, b) return a.index < b.index end)
        return choices
    end,
}

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_JARSNPCCHAT1 = "/jnc"
SLASH_JARSNPCCHAT2 = "/jarsnpcchat"
SlashCmdList["JARSNPCCHAT"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "fontsize" or msg == "font" then
        print("|cffff8c00Itsu:UI|r Current font sizes:")
        print("  Body: " .. JarsNPCChatDB.fontSize .. "  Title: " .. JarsNPCChatDB.titleFontSize)
        print("  Usage: /jnc fontsize <body> <title>")
    elseif msg:match("^fontsize%s+%d") then
        local bodySize, titleSize = msg:match("^fontsize%s+(%d+)%s*(%d*)")
        bodySize = tonumber(bodySize)
        titleSize = tonumber(titleSize) or bodySize + 3
        titleSize = math.min(math.max(titleSize, TITLE_MIN), TITLE_MAX)
        if bodySize >= 10 and bodySize <= 30 then
            JarsNPCChatDB.fontSize = bodySize
            JarsNPCChatDB.titleFontSize = titleSize
            bodyText:SetFont(ns.GetFont(), bodySize, "")
            titleText:SetFont(ns.GetFont(), titleSize, "")
            print("|cffff8c00Itsu:UI|r Font sizes set to body=" .. bodySize .. ", title=" .. titleSize)
        else
            print("|cffff8c00Itsu:UI|r Font size must be between 10 and 30.")
        end
    else
        print("|cffff8c00Itsu:UI|r Commands:")
        print("  |cff00ff00/jnc fontsize|r - Show current font sizes")
        print("  |cff00ff00/jnc fontsize <body> [title]|r - Set font sizes (10-30)")
    end
end

---------------------------------------------------------------------------
-- Shared font + config panel
---------------------------------------------------------------------------
local function ApplyFonts()
    titleText:SetFont(ns.GetFont(), JarsNPCChatDB.titleFontSize or DEFAULTS.titleFontSize, "")
    bodyText:SetFont(ns.GetFont(), JarsNPCChatDB.fontSize or DEFAULTS.fontSize, "")
end
ns.OnShared(ApplyFonts)

ns.RegisterPanel(70, "NPC Chat", function(b)
    b:Text("Replaces the quest and gossip windows with a text bubble.")
    b:Header("Text")
    b:Slider("Body Font Size", 10, 30, 1,
        function() return JarsNPCChatDB.fontSize or DEFAULTS.fontSize end,
        function(v) JarsNPCChatDB.fontSize = v; ApplyFonts() end)
    b:Slider("Title Font Size", TITLE_MIN, TITLE_MAX, 1,
        function() return JarsNPCChatDB.titleFontSize or DEFAULTS.titleFontSize end,
        function(v) JarsNPCChatDB.titleFontSize = v; ApplyFonts() end)
end)

end)
