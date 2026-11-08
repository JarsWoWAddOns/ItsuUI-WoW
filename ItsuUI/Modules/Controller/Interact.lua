-- Itsu:UI controller mode, started from JarStick. edit it here
-- JarStick interact + window navigation
-- Blizzard soft interact picks the NPC/object in front of you. X becomes "interact" while one exists.
-- With a gossip/quest/loot window open the pad goes into menu mode: a legend shows what
-- X/A/B/Y do, and the dpad moves a cursor over the rows, rewards or loot.

local _, jf = ...
jf.jsParts = jf.jsParts or {}
jf.jsParts[#jf.jsParts + 1] = function(ns, ADDON)

local NAV_KEYS = { "PAD1", "PAD2", "PAD3", "PAD4", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }
-- the book also wants the bumpers and start, and L2/R2 held while placing
local BOOK_KEYS = { "PAD1", "PAD2", "PAD3", "PAD4", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT",
    "PADLSHOULDER", "PADRSHOULDER", "PADFORWARD" }
local BOOK_MODS = { "", "SHIFT-", "CTRL-" }

-- windows that turn the pad into a menu controller. popups and the book only out of combat
local WATCH = {
    { name = "JarStickBook", nocombat = true, book = true },
    { name = "JarsNPCChatFrame" }, -- Jars NPC Chat replaces the two below when its loaded
    { name = "GossipFrame" },
    { name = "QuestFrame" },
    { name = "LootFrame" },
    { name = "MerchantFrame" },
    { name = "JarsBagsFrame", nocombat = true, bags = true }, -- made at login, attached late
    { name = "StaticPopup1", nocombat = true, popup = true },
    { name = "StaticPopup2", nocombat = true, popup = true },
    { name = "StaticPopup3", nocombat = true, popup = true },
    { name = "StaticPopup4", nocombat = true, popup = true },
}

local function BookShown()
    return ns.BookShown and ns.BookShown()
end

-- which pick resets when a window (re)opens
local RESET = { GOSSIP_SHOW = "gossip", LOOT_OPENED = "loot", QUEST_GREETING = "greet", QUEST_COMPLETE = "reward" }

local ui, reticle, legend, hl
local probes = {}
local sel = { gossip = 1, loot = 1, reward = 1, greet = 1, npc = 1 }
local PanelCursor -- defined with the grid code below, used by RefreshUI above it

-- chests, seats, quest objects: a soft interact with no unit token. only the event guid tells us
local softObject = false

-- nil = nothing in front. a secret guid (instances restrict unit identity) still means
-- something is there, we just cant read which. seen in Jar's dungeon log 2026-10-02
local function GuidPresent(guid)
    if guid == nil then return false end
    if issecretvalue and issecretvalue(guid) then return true end
    return guid ~= ""
end

local function HasSoft()
    return UnitExists("softinteract") or softObject
end
ns.HasSoftInteract = HasSoft

local function Glyph(key)
    return GetBindingText(key, 1)
end

local function Wrap(i, n)
    if n < 1 then return 1 end
    return ((i - 1) % n) + 1
end

local function IsUp(key)
    return key == "PADDUP" or key == "PADDLEFT"
end

local function IsDown(key)
    return key == "PADDDOWN" or key == "PADDRIGHT"
end

-- click blizzards own button so popups/sounds behave, api call if its gone
local function Click(name, fallback)
    local b = _G[name]
    if b and b:IsVisible() then
        b:Click()
    elseif fallback then
        fallback()
    end
end

-- cursor ----------------------------------------------------------------------

local function Highlight(frame)
    if not frame then
        hl:Hide()
        return
    end
    hl:SetParent(frame)
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", -4, 4)
    hl:SetPoint("BOTTOMRIGHT", 4, -4)
    hl:SetFrameLevel(frame:GetFrameLevel() + 5)
    hl.tag:SetText(Glyph("PAD3"))
    hl:Show()
end

local function ScrollFrameFor(sb, match)
    if not (sb and sb.FindElementDataByPredicate) then return end
    local data = sb:FindElementDataByPredicate(match)
    if not data then return end
    if sb.ScrollToElementData then
        sb:ScrollToElementData(data)
    end
    return sb:FindFrame(data)
end

-- gossip --------------------------------------------------------------------

-- same order blizz draws them: available quests, active quests, options
local function GossipList()
    local list = {}
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests()) do
        list[#list + 1] = { kind = "avail", id = q.questID }
    end
    for _, q in ipairs(C_GossipInfo.GetActiveQuests()) do
        list[#list + 1] = { kind = "active", id = q.questID }
    end
    local options = C_GossipInfo.GetOptions()
    table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
    for _, o in ipairs(options) do
        list[#list + 1] = { kind = "option", id = o.gossipOptionID }
    end
    return list
end

local function GossipHighlight()
    local list = GossipList()
    sel.gossip = Wrap(sel.gossip, #list)
    local e = list[sel.gossip]
    if not e then
        Highlight(nil)
        return
    end
    local panel = GossipFrame.GreetingPanel
    Highlight(ScrollFrameFor(panel and panel.ScrollBox, function(d)
        local info = d and d.info
        if not info then return false end
        if e.kind == "option" then return info.gossipOptionID == e.id end
        return info.questID == e.id
    end))
end

local function GossipKey(key)
    local list = GossipList()
    if IsUp(key) then
        sel.gossip = Wrap(sel.gossip - 1, #list)
        GossipHighlight()
    elseif IsDown(key) then
        sel.gossip = Wrap(sel.gossip + 1, #list)
        GossipHighlight()
    elseif key == "PAD3" then
        local e = list[Wrap(sel.gossip, #list)]
        if not e then return end
        if e.kind == "avail" then
            C_GossipInfo.SelectAvailableQuest(e.id)
        elseif e.kind == "active" then
            C_GossipInfo.SelectActiveQuest(e.id)
        else
            C_GossipInfo.SelectOption(e.id)
        end
    elseif key == "PAD2" then
        C_GossipInfo.CloseGossip()
    end
end

-- loot ----------------------------------------------------------------------

local function LootList()
    local list = {}
    for i = 1, GetNumLootItems() do
        if LootSlotHasItem(i) then list[#list + 1] = i end
    end
    return list
end

local function LootHighlight()
    local list = LootList()
    sel.loot = Wrap(sel.loot, #list)
    local slot = list[sel.loot]
    if not slot then
        Highlight(nil)
        return
    end
    Highlight(ScrollFrameFor(LootFrame.ScrollBox, function(d) return d and d.slotIndex == slot end))
end

local function LootKey(key)
    local list = LootList()
    if IsUp(key) then
        sel.loot = Wrap(sel.loot - 1, #list)
        LootHighlight()
    elseif IsDown(key) then
        sel.loot = Wrap(sel.loot + 1, #list)
        LootHighlight()
    elseif key == "PAD3" then
        local slot = list[Wrap(sel.loot, #list)]
        if slot then LootSlot(slot) end
    elseif key == "PAD4" then
        for i = #list, 1, -1 do
            LootSlot(list[i])
        end
    elseif key == "PAD2" then
        CloseLoot()
    end
end

-- quest ---------------------------------------------------------------------

local function RewardChoices()
    local list = {}
    local frame = QuestInfoRewardsFrame
    for _, b in ipairs(frame and frame.RewardButtons or {}) do
        if b.type == "choice" and b:IsShown() then list[#list + 1] = b end
    end
    table.sort(list, function(a, b) return a:GetID() < b:GetID() end)
    return list
end

local function GreetList()
    local list = {}
    local pool = QuestFrameGreetingPanel.titleButtonPool
    if pool then
        for b in pool:EnumerateActive() do
            list[#list + 1] = b
        end
        table.sort(list, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    end
    return list
end

local function QuestHighlight()
    if QuestFrameRewardPanel:IsVisible() then
        local list = RewardChoices()
        sel.reward = Wrap(sel.reward, #list)
        local b = list[sel.reward]
        -- clicking it is how blizz picks the reward
        if b and QuestInfoFrame.itemChoice ~= b:GetID() then b:Click() end
        Highlight(b)
    elseif QuestFrameGreetingPanel:IsVisible() then
        local list = GreetList()
        sel.greet = Wrap(sel.greet, #list)
        Highlight(list[sel.greet])
    else
        Highlight(nil)
    end
end

local function QuestKey(key)
    if QuestFrameRewardPanel:IsVisible() then
        local n = #RewardChoices()
        if IsUp(key) then
            sel.reward = Wrap(sel.reward - 1, n)
            QuestHighlight()
        elseif IsDown(key) then
            sel.reward = Wrap(sel.reward + 1, n)
            QuestHighlight()
        elseif key == "PAD3" then
            Click("QuestFrameCompleteQuestButton", function() GetQuestReward(QuestInfoFrame.itemChoice) end)
        elseif key == "PAD2" then
            Click("QuestFrameCancelButton", CloseQuest)
        end
    elseif QuestFrameProgressPanel:IsVisible() then
        if key == "PAD3" then
            Click("QuestFrameCompleteButton", CompleteQuest)
        elseif key == "PAD2" then
            Click("QuestFrameGoodbyeButton", CloseQuest)
        end
    elseif QuestFrameDetailPanel:IsVisible() then
        if key == "PAD3" then
            Click("QuestFrameAcceptButton", AcceptQuest)
        elseif key == "PAD1" or key == "PAD2" then
            Click("QuestFrameDeclineButton", DeclineQuest)
        end
    elseif QuestFrameGreetingPanel:IsVisible() then
        local list = GreetList()
        if IsUp(key) then
            sel.greet = Wrap(sel.greet - 1, #list)
            QuestHighlight()
        elseif IsDown(key) then
            sel.greet = Wrap(sel.greet + 1, #list)
            QuestHighlight()
        elseif key == "PAD3" then
            local b = list[Wrap(sel.greet, #list)]
            if b then b:Click() end
        elseif key == "PAD2" then
            Click("QuestFrameGreetingGoodbyeButton", CloseQuest)
        end
    end
end

-- Jars NPC Chat ---------------------------------------------------------------
-- it swallows the blizzard gossip/quest windows, so drive its own buttons via JarsNPCChatAPI

local PRIMARY = { Accept = true, Continue = true, Complete = true, OK = true }

local function NPC()
    local api = JarsNPCChatAPI
    if api and api.frame and api.frame:IsShown() then return api end
end

local function NPCAction(api, want)
    for _, b in ipairs(api.GetActions()) do
        local text = b:GetText()
        if (want == "primary" and PRIMARY[text]) or text == want then return b end
    end
end

local function NPCHighlight()
    local api = NPC()
    if not api then
        Highlight(nil)
        return
    end
    local rewards = api.GetRewardChoices()
    local options = api.GetOptions()
    if #rewards > 1 then
        sel.npc = Wrap(sel.npc, #rewards)
        local b = rewards[sel.npc]
        if b and b.index ~= api.GetSelectedReward() then b:Click() end
        Highlight(b)
    elseif #options > 0 then
        sel.npc = Wrap(sel.npc, #options)
        Highlight(options[sel.npc])
    else
        Highlight(NPCAction(api, "primary"))
    end
end

local function NPCKey(api, key)
    local rewards = api.GetRewardChoices()
    local options = api.GetOptions()
    local n = (#rewards > 1) and #rewards or #options
    if IsUp(key) and n > 0 then
        sel.npc = Wrap(sel.npc - 1, n)
        NPCHighlight()
    elseif IsDown(key) and n > 0 then
        sel.npc = Wrap(sel.npc + 1, n)
        NPCHighlight()
    elseif key == "PAD3" then
        local b = (#options > 0) and options[Wrap(sel.npc, #options)] or NPCAction(api, "primary")
        if b then b:Click() end
    elseif key == "PAD1" then
        local b = NPCAction(api, "Decline")
        if b then b:Click() end
    elseif key == "PAD2" then
        local b = NPCAction(api, "Close")
        if b then
            b:Click()
        elseif api.GetState() == "GOSSIP" then
            C_GossipInfo.CloseGossip()
        else
            CloseQuest()
        end
    end
end

-- Jars Bags -----------------------------------------------------------------
-- dpad walks the items by where they sit on screen. X is bound straight to the picked
-- item button as a right click (use, equip, sell at a vendor) so it stays a real key
-- press. Y asks before deleting, the popup's own X does the delete

local BAG_LIST = { 0, 1, 2, 3, 4, 5 }
if Enum.BagIndex and Enum.BagIndex.Keyring then BAG_LIST[#BAG_LIST + 1] = Enum.BagIndex.Keyring end
local bagPick -- picked button name

local function Bags()
    local f = _G.JarsBagsFrame
    if f and f:IsShown() then return f end
end

local function BagButtons()
    local list = {}
    for _, bag in ipairs(BAG_LIST) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local b = _G["JarsBagsItemBtn" .. bag .. "_" .. slot]
            if b and b:IsVisible() then list[#list + 1] = b end
        end
    end
    return list
end

local function BagTopLeft(list)
    table.sort(list, function(a, b)
        local at, bt = a:GetTop() or 0, b:GetTop() or 0
        if math.abs(at - bt) > 2 then return at > bt end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    return list[1]
end

-- nearest button that way, sideways drift costs double. same rule as the talent trees
local function BagMove(key)
    local list = BagButtons()
    local cur = bagPick and _G[bagPick]
    if not (cur and cur:IsVisible()) then
        cur = BagTopLeft(list)
        bagPick = cur and cur:GetName()
        return
    end
    local cx, cy = cur:GetCenter()
    local vx, vy = 0, 0
    if key == "PADDUP" then vy = 1 elseif key == "PADDDOWN" then vy = -1 elseif key == "PADDLEFT" then vx = -1 else vx = 1 end
    local best, score
    for _, b in ipairs(list) do
        local x, y = b:GetCenter()
        local dx, dy = x - cx, y - cy
        local fwd, side = dx * vx + dy * vy, math.abs(dx * vy - dy * vx)
        if fwd > 1 and (not score or fwd + side * 2 < score) then best, score = b, fwd + side * 2 end
    end
    if best then bagPick = best:GetName() end
end

-- the item list scrolls, keep the pick on screen
local function BagScrollTo(b)
    local f = Bags()
    local scroll = f and f.content and f.content:GetParent()
    if not (scroll and scroll.GetVerticalScroll) then return end
    local top, bottom, bt, bb = scroll:GetTop(), scroll:GetBottom(), b:GetTop(), b:GetBottom()
    if not (top and bt) then return end
    local cur = scroll:GetVerticalScroll()
    if bt > top then
        scroll:SetVerticalScroll(math.max(0, cur - (bt - top) - 4))
    elseif bb < bottom then
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScrollRange(), cur + (bottom - bb) + 4))
    end
end

-- the secure side binds X to whatever this names, out of combat only (bags are nocombat)
local function SetBagButton(name)
    name = name or ""
    if not ui or InCombatLockdown() or ui:GetAttribute("bagbtn") == name then return end
    ui:SetAttribute("bagbtn", name)
    ui:SetAttribute("state-poke", (tonumber(ui:GetAttribute("state-poke")) or 0) + 1)
end

local function BagHighlight()
    local b = bagPick and _G[bagPick]
    if not (b and b:IsVisible()) then
        b = BagTopLeft(BagButtons())
        bagPick = b and b:GetName()
    end
    if b then BagScrollTo(b) end
    Highlight(b)
    SetBagButton(bagPick)
end

StaticPopupDialogs.JARSTICK_DELETE_ITEM = {
    text = "Delete %s?",
    button1 = DELETE,
    button2 = CANCEL,
    -- the item could have moved since Y, only delete if its still the same one
    OnAccept = function(_, data)
        if C_Container.GetContainerItemLink(data.bag, data.slot) ~= data.link then return end
        ClearCursor()
        C_Container.PickupContainerItem(data.bag, data.slot)
        if CursorHasItem() then DeleteCursorItem() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

local function BagKey(key)
    if key:find("^PADD") then
        BagMove(key)
        BagHighlight()
    elseif key == "PAD4" then
        local b = bagPick and _G[bagPick]
        local bag, slot = b and b:GetParent():GetID(), b and b:GetID()
        local link = bag and C_Container.GetContainerItemLink(bag, slot)
        if link then StaticPopup_Show("JARSTICK_DELETE_ITEM", link, nil, { bag = bag, slot = slot, link = link }) end
    elseif key == "PAD2" then
        Bags():Hide()
    end
end

-- popups --------------------------------------------------------------------

local function VisiblePopup()
    for i = 1, 4 do
        local p = _G["StaticPopup" .. i]
        if p and p:IsShown() then return p end
    end
end

local function PopupButton(p, n)
    local b = p.GetButton and p:GetButton(n)
    b = b or p["Button" .. n] or p["button" .. n]
    if b and b:IsShown() and b:IsEnabled() then return b end
end

-- dispatch ------------------------------------------------------------------

-- popups are not handled here: their buttons can call protected stuff (summon, res,
-- bonus roll), so the handler binds X/A/B straight to them and the press is a real key event
local function UIKey(key)
    if VisiblePopup() then
        return
    elseif BookShown() then
        ns.BookKey(key)
    elseif LootFrame:IsShown() then
        LootKey(key)
    elseif NPC() then
        NPCKey(NPC(), key)
    elseif QuestFrame:IsShown() then
        QuestKey(key)
    elseif GossipFrame:IsShown() then
        GossipKey(key)
    elseif Bags() then
        BagKey(key)
    elseif MerchantFrame:IsShown() and key == "PAD2" then
        CloseMerchant()
    end
end

-- legend --------------------------------------------------------------------

local function Entry(key, text)
    return Glyph(key) .. " " .. text
end

local function NavEntry(text)
    return Glyph("PADDUP") .. Glyph("PADDDOWN") .. " " .. text
end

local function LegendEntries()
    local p = VisiblePopup()
    if p then
        local list = {}
        local b1, b2 = PopupButton(p, 1), PopupButton(p, 2)
        if b1 then list[#list + 1] = Entry("PAD3", b1:GetText() or "Accept") end
        if b2 then list[#list + 1] = Entry("PAD1", b2:GetText() or "Decline") end
        list[#list + 1] = Entry("PAD2", "Close")
        return list
    elseif BookShown() then
        return ns.BookLegend()
    elseif LootFrame:IsShown() then
        return { Entry("PAD3", "Loot"), Entry("PAD4", "Loot all"), Entry("PAD2", "Close"), NavEntry("Item") }
    elseif NPC() then
        local api = NPC()
        local options, rewards = api.GetOptions(), api.GetRewardChoices()
        local primary = NPCAction(api, "primary")
        local list = {}
        if #options > 0 then
            list[#list + 1] = Entry("PAD3", "Select")
        elseif primary then
            list[#list + 1] = Entry("PAD3", primary:GetText())
        end
        if NPCAction(api, "Decline") then list[#list + 1] = Entry("PAD1", "Decline") end
        list[#list + 1] = Entry("PAD2", "Close")
        if #rewards > 1 then
            list[#list + 1] = NavEntry("Reward")
        elseif #options > 1 then
            list[#list + 1] = NavEntry("Option")
        end
        return list
    elseif QuestFrame:IsShown() then
        if QuestFrameRewardPanel:IsVisible() then
            local list = { Entry("PAD3", "Complete"), Entry("PAD2", "Cancel") }
            if #RewardChoices() > 1 then list[#list + 1] = NavEntry("Reward") end
            return list
        elseif QuestFrameProgressPanel:IsVisible() then
            return { Entry("PAD3", "Continue"), Entry("PAD2", "Close") }
        elseif QuestFrameDetailPanel:IsVisible() then
            return { Entry("PAD3", "Accept"), Entry("PAD1", "Decline"), Entry("PAD2", "Close") }
        end
        return { Entry("PAD3", "Select"), Entry("PAD2", "Close"), NavEntry("Quest") }
    elseif GossipFrame:IsShown() then
        return { Entry("PAD3", "Select"), Entry("PAD2", "Close"), NavEntry("Option") }
    elseif Bags() then
        local use = MerchantFrame:IsShown() and "Sell" or "Use / equip"
        return { Entry("PAD3", use), Entry("PAD4", "Delete"), Entry("PAD2", "Close"), NavEntry("Item") }
    elseif MerchantFrame:IsShown() then
        return { Entry("PAD2", "Close"), Glyph("PADRSTICK") .. "+" .. Glyph("PADLSTICK") .. " Mouse to buy" }
    end
end

local function UpdateLegend()
    local entries = LegendEntries()
    if not entries or ui:GetAttribute("uiopen") ~= 1 then
        legend:Hide()
        return
    end
    legend.text:SetText(table.concat(entries, "      "))
    legend:SetWidth(legend.text:GetStringWidth() + 36)
    -- npc chat: sit right under its text bubble, otherwise bottom center
    legend:ClearAllPoints()
    local bubble = _G.JarsNPCChatBubble
    if NPC() and bubble and bubble:IsVisible() and not VisiblePopup() and not BookShown() and not LootFrame:IsShown() then
        legend:SetPoint("TOP", bubble, "BOTTOM", 0, -10)
    else
        legend:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    end
    legend:Show()
end

local function RefreshUI()
    local bagActive = false
    if BookShown() then
        ns.BookRefresh()
    elseif LootFrame:IsShown() then
        LootHighlight()
    elseif NPC() then
        NPCHighlight()
    elseif QuestFrame:IsShown() then
        QuestHighlight()
    elseif GossipFrame:IsShown() then
        GossipHighlight()
    elseif Bags() and ui:GetAttribute("uiopen") == 1 then
        bagActive = true
        BagHighlight()
    elseif ui:GetAttribute("uiopen") ~= 1 and PanelCursor() then
        -- grid cursor placed
    else
        Highlight(nil)
    end
    -- X only goes to a bag item while the bags are what the pad drives
    if not bagActive then SetBagButton(nil) end
    UpdateLegend()
end

-- scroll boxes fill a frame or two after the event
local function RefreshSoon()
    C_Timer.After(0, RefreshUI)
    C_Timer.After(0.25, RefreshUI)
end

local function OnUIMode(open)
    if open then
        for k in pairs(sel) do sel[k] = 1 end
        RefreshSoon()
    else
        legend:Hide()
        Highlight(nil)
    end
end

-- reticle -------------------------------------------------------------------

-- crosshair lines are optional, the "X Name" prompt under them always shows
local function UpdateReticle()
    reticle:SetScale(ns.db.reticleScale or 1)
    reticle:Show()
    local has = HasSoft()
    if ns.debug then
        ns.Log("softinteract " .. (UnitExists("softinteract") and "unit" or (softObject and "object" or "none")))
    end
    for _, t in ipairs(reticle.parts) do
        t:SetShown(ns.db.reticle)
        if has then
            t:SetColorTexture(0.3, 1, 0.3, 0.9)
        else
            t:SetColorTexture(1, 1, 1, 0.5)
        end
    end
    if has then
        reticle.label:SetFormattedText("%s %s", Glyph("PAD3"), UnitName("softinteract") or "Interact")
    else
        reticle.label:SetText("")
    end
end

local function CreateReticle()
    local f = CreateFrame("Frame", "JarStickReticle", UIParent)
    f:SetSize(32, 32)
    f:SetPoint("CENTER")
    f:SetFrameStrata("LOW")
    f.parts = {}
    local function bar(w, h, x, y)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetSize(w, h)
        t:SetPoint("CENTER", x, y)
        f.parts[#f.parts + 1] = t
    end
    bar(3, 10, 0, 11)
    bar(3, 10, 0, -11)
    bar(10, 3, 11, 0)
    bar(10, 3, -11, 0)
    bar(3, 3, 0, 0)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -8)
    return f
end

-- secure side ---------------------------------------------------------------

local function InteractDriver()
    if ns.db.interactInCombat then
        return "[@softinteract,exists] 1; 0"
    end
    return "[nocombat,@softinteract,exists] 1; 0"
end

-- insecure side poke: fine out of combat, the secure probe covers combat
local pokes = 0
local function PokeHandler()
    if ui and not InCombatLockdown() then
        pokes = pokes + 1
        ui:SetAttribute("state-poke", pokes)
    end
end

local function Poke(name, what)
    if ns.debug then
        ns.Print(name .. " " .. what .. (InCombatLockdown() and " (in combat, secure probe only)" or ""))
    end
    PokeHandler()
    RefreshSoon()
end

-- old select menu: panel commands per pad key on the handler. the wheel replaced it
-- local function ApplySelectMenu()
--     ns.RunWhenSafe("selectmenu", function()
--         if not ui then return end
--         for i, key in ipairs(NAV_KEYS) do
--             ui:SetAttribute("selcmd" .. i, ns.db.selectMenu[key] or "")
--         end
--         PokeHandler()
--     end)
-- end

-- spare bar grids: the toggle and the dpad walk run in the restricted env so they work in combat
local function CreatePanelHandlers()
    for _, side in ipairs({ "L", "R" }) do
        local t = CreateFrame("Button", "JarStickPanelToggle" .. side, UIParent, "SecureHandlerClickTemplate")
        t:RegisterForClicks("AnyDown")
        t:SetFrameRef("panel", ns.panels[side])
        t:SetFrameRef("ui", ui)
        t:SetAttribute("_onclick", [[
            local p = self:GetFrameRef("panel")
            if p:IsShown() then p:Hide() else p:Show() end
            local ui = self:GetFrameRef("ui")
            ui:SetAttribute("state-probe", (tonumber(ui:GetAttribute("state-probe")) or 0) + 1)
        ]])
    end

    local nav = CreateFrame("Button", "JarStickPanelNav", UIParent, "SecureHandlerClickTemplate")
    nav:RegisterForClicks("AnyDown")
    nav:SetFrameRef("ui", ui)
    nav:SetFrameRef("pL", ns.panels.L)
    nav:SetFrameRef("pR", ns.panels.R)
    nav:SetAttribute("_onclick", [[
        local ui = self:GetFrameRef("ui")
        local lOpen = self:GetFrameRef("pL"):IsShown()
        local rOpen = self:GetFrameRef("pR"):IsShown()
        local side = ui:GetAttribute("panelside") or "L"
        local idx = tonumber(ui:GetAttribute("panelidx")) or 1
        if side == "L" and not lOpen then side = "R" end
        if side == "R" and not rOpen then side = "L" end
        -- no floor in the restricted env, integer math instead
        local col = (idx - 1) % 4
        local row = (idx - 1 - col) / 4
        if button == "PADDUP" then
            row = (row - 1) % 3
        elseif button == "PADDDOWN" then
            row = (row + 1) % 3
        elseif button == "PADDLEFT" then
            col = col - 1
            if col < 0 then
                col = 3
                if side == "R" and lOpen then side = "L" end
            end
        elseif button == "PADDRIGHT" then
            col = col + 1
            if col > 3 then
                col = 0
                if side == "L" and rOpen then side = "R" end
            end
        end
        ui:SetAttribute("panelside", side)
        ui:SetAttribute("panelidx", row * 4 + col + 1)
        ui:SetAttribute("state-probe", (tonumber(ui:GetAttribute("state-probe")) or 0) + 1)
    ]])
end

-- cursor on the picked grid slot, false when no grid is open
PanelCursor = function()
    local pL, pR = ns.panels and ns.panels.L, ns.panels and ns.panels.R
    if not (pL and (pL:IsShown() or pR:IsShown())) then return false end
    local side = ui:GetAttribute("panelside") or "L"
    local idx = ui:GetAttribute("panelidx") or 1
    if side == "L" and not pL:IsShown() then side = "R" end
    if side == "R" and not pR:IsShown() then side = "L" end
    local p = side == "L" and pL or pR
    Highlight(p.buttons[idx])
    return true
end

-- tell the handler whether an object is in front. in combat the [combat] driver drops it securely
local function UpdateSoftObject()
    ns.RunWhenSafe("softobject", function()
        if not ui then return end
        ui:SetAttribute("softobject", HasSoft() and 1 or 0)
        PokeHandler()
    end)
end

-- /js ui: who is open, what the probes see, what the pad keys are bound to
local function UIReport()
    ns.Print("uiopen=" .. tostring(ui and ui:GetAttribute("uiopen")) .. "  combat=" .. tostring(InCombatLockdown())
        .. "  PAD3 -> " .. tostring(GetBindingAction("PAD3", true)) .. "  PAD4 -> " .. tostring(GetBindingAction("PAD4", true)))
    ns.Print("  PADDUP -> " .. tostring(GetBindingAction("PADDUP", true)) .. "  grid L=" .. tostring(ns.panels and ns.panels.L:IsShown())
        .. " R=" .. tostring(ns.panels and ns.panels.R:IsShown()) .. "  cursor=" .. tostring(ui and ui:GetAttribute("panelside"))
        .. tostring(ui and ui:GetAttribute("panelidx")))
    for _, w in ipairs(WATCH) do
        local f, p = _G[w.name], probes[w.name]
        if f then
            ns.Print(string.format("  %s shown=%s visible=%s  probe visible=%s", w.name, tostring(f:IsShown()),
                tostring(f:IsVisible()), tostring(p and p:IsVisible())))
        end
    end
end
ns.UIReport = UIReport

-- probes sit under the blizzard windows so their show/hide reaches the restricted env
local nprobes = 0
local function AttachProbe(w)
    local target = _G[w.name]
    if target and not probes[w.name] then
        nprobes = nprobes + 1
        local n = nprobes
        local probe = CreateFrame("Frame", nil, target, "SecureHandlerShowHideTemplate")
        probe.ignoreInLayout = true -- popups are layout frames, stay out of their math
        probe:SetSize(1, 1)
        probe:SetPoint("TOPLEFT")
        probe:SetFrameRef("ui", ui)
        if w.nocombat then probe:SetAttribute("nocombat", true) end
        if w.book then probe:SetAttribute("book", true) end
        if w.popup then
            -- real button names, so the snippet can bind the pad straight to them
            local b1 = target.GetButton and target:GetButton(1) or target.Button1
            local b2 = target.GetButton and target:GetButton(2) or target.Button2
            probe:SetAttribute("b1", b1 and b1:GetName() or "")
            probe:SetAttribute("b2", b2 and b2:GetName() or "")
            probe:SetAttribute("close", target.CloseButton and target.CloseButton:GetName() or "")
        end
        -- bump a state attr on the handler, same trigger path the drivers use
        probe:SetAttribute("_onshow", [[
            local ui = self:GetFrameRef("ui")
            ui:SetAttribute("state-probe", (tonumber(ui:GetAttribute("state-probe")) or 0) + 1)
        ]])
        probe:SetAttribute("_onhide", [[
            local ui = self:GetFrameRef("ui")
            ui:SetAttribute("state-probe", (tonumber(ui:GetAttribute("state-probe")) or 0) + 1)
        ]])
        ui:SetFrameRef("w" .. n, probe)
        probes[w.name] = probe
        local name = w.name
        target:HookScript("OnShow", function() Poke(name, "shown") end)
        target:HookScript("OnHide", function() Poke(name, "hidden") end)
        ui:SetAttribute("nwatch", n)
    end
end

-- windows that only exist after login (Jars Bags builds its frame then)
local function AttachLateProbes()
    ns.RunWhenSafe("lateprobes", function()
        for _, w in ipairs(WATCH) do AttachProbe(w) end
    end)
end

local function CreateHandler()
    ui = CreateFrame("Frame", "JarStickUI", UIParent, "SecureHandlerStateTemplate")
    ui:SetAttribute("nwatch", 0)
    for _, w in ipairs(WATCH) do AttachProbe(w) end
    for i, key in ipairs(NAV_KEYS) do
        ui:SetAttribute("navkey" .. i, key)
    end
    ui:SetAttribute("nnav", #NAV_KEYS)
    for i, key in ipairs(BOOK_KEYS) do
        ui:SetAttribute("bookkey" .. i, key)
    end
    ui:SetAttribute("nbook", #BOOK_KEYS)
    for i, mod in ipairs(BOOK_MODS) do
        ui:SetAttribute("bookmod" .. i, mod)
    end
    ui:SetAttribute("nbookmod", #BOOK_MODS)

    -- window open: pad keys go to the menu. else X interacts when something is in front
    ui:SetAttribute("refresh", [[
        local incombat = tostring(self:GetAttribute("state-combat")) == "1"
        local open, book = false, false
        local b1, b2, close
        for i = 1, self:GetAttribute("nwatch") do
            local w = self:GetFrameRef("w" .. i)
            if w and w:IsVisible() and not (incombat and w:GetAttribute("nocombat")) then
                open = true
                if w:GetAttribute("book") then book = true end
                -- first visible popup owns X/A/B
                if not b1 and w:GetAttribute("b1") then
                    b1, b2, close = w:GetAttribute("b1"), w:GetAttribute("b2"), w:GetAttribute("close")
                end
            end
        end
        self:ClearBindings()
        if open and book and not b1 then
            -- modded keys pass the bare name, the book reads shift/ctrl itself
            for i = 1, self:GetAttribute("nbook") do
                local key = self:GetAttribute("bookkey" .. i)
                for j = 1, self:GetAttribute("nbookmod") do
                    self:SetBindingClick(true, self:GetAttribute("bookmod" .. j) .. key, "JarStickUIKey", key)
                end
            end
        elseif open then
            local bagbtn = self:GetAttribute("bagbtn") or ""
            for i = 1, self:GetAttribute("nnav") do
                local key = self:GetAttribute("navkey" .. i)
                if b1 and key == "PAD3" and b1 ~= "" then
                    self:SetBindingClick(true, key, b1, "LeftButton")
                elseif not b1 and key == "PAD3" and bagbtn ~= "" then
                    -- right click on the bag item: use, equip, or sell at a vendor
                    self:SetBindingClick(true, key, bagbtn, "RightButton")
                elseif b1 and key == "PAD1" and b2 ~= "" then
                    self:SetBindingClick(true, key, b2, "LeftButton")
                elseif b1 and key == "PAD2" and close ~= "" then
                    self:SetBindingClick(true, key, close, "LeftButton")
                else
                    self:SetBindingClick(true, key, "JarStickUIKey", key)
                end
            end
        elseif self:GetFrameRef("pL"):IsShown() or self:GetFrameRef("pR"):IsShown() then
            -- a spare bar grid is open: dpad walks it, X uses the picked slot
            self:SetBindingClick(true, "PADDUP", "JarStickPanelNav", "PADDUP")
            self:SetBindingClick(true, "PADDDOWN", "JarStickPanelNav", "PADDDOWN")
            self:SetBindingClick(true, "PADDLEFT", "JarStickPanelNav", "PADDLEFT")
            self:SetBindingClick(true, "PADDRIGHT", "JarStickPanelNav", "PADDRIGHT")
            local side = self:GetAttribute("panelside") or "L"
            local idx = tonumber(self:GetAttribute("panelidx")) or 1
            if side == "L" and not self:GetFrameRef("pL"):IsShown() then side = "R" end
            if side == "R" and not self:GetFrameRef("pR"):IsShown() then side = "L" end
            self:SetBindingClick(true, "PAD3", "JarStickPanel" .. side .. idx, "LeftButton")
        elseif tostring(self:GetAttribute("state-interact")) == "1"
            or (not incombat and self:GetAttribute("softobject") == 1) then
            self:SetBinding(true, "PAD3", "INTERACTTARGET")
        end
        self:SetAttribute("uiopen", open and 1 or 0)
    ]])
    ui:SetAttribute("_onstate-interact", [[ self:RunAttribute("refresh") ]])
    ui:SetAttribute("_onstate-combat", [[ self:RunAttribute("refresh") ]])
    ui:SetAttribute("_onstate-probe", [[ self:RunAttribute("refresh") ]])
    ui:SetAttribute("_onstate-poke", [[ self:RunAttribute("refresh") ]])
    ui:SetFrameRef("pL", ns.panels.L)
    ui:SetFrameRef("pR", ns.panels.R)
    ui:SetAttribute("panelside", ns.db.panelSide or "L")
    ui:SetAttribute("panelidx", ns.db.panelIdx or 1)
    CreatePanelHandlers()
    ui:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "uiopen" then OnUIMode(value == 1) end
        if name == "panelside" then
            ns.db.panelSide = value
            RefreshSoon()
        elseif name == "panelidx" then
            ns.db.panelIdx = value
            if ns.debug then ns.Log("grid cursor " .. tostring(ui:GetAttribute("panelside")) .. tostring(value)) end
            RefreshSoon()
        end
        if ns.debug and (name == "uiopen" or name == "state-interact" or name == "state-combat") then
            ns.Log(name .. " = " .. tostring(value) .. "  PAD3 -> " .. tostring(GetBindingAction("PAD3", true)))
        end
    end)
    RegisterStateDriver(ui, "combat", "[combat] 1; 0")
    RegisterStateDriver(ui, "interact", InteractDriver())
end

local function Init()
    local keyBtn = CreateFrame("Button", "JarStickUIKey", UIParent)
    keyBtn:SetSize(1, 1)
    keyBtn:SetPoint("TOPLEFT")
    keyBtn:SetAlpha(0)
    keyBtn:EnableMouse(false)
    keyBtn:RegisterForClicks("AnyDown", "AnyUp")
    keyBtn:SetScript("OnClick", function(_, key, down)
        if down then
            UIKey(key)
            RefreshSoon()
        end
    end)

    -- the pad cursor: pulsing gold frame with the X glyph on its corner
    hl = CreateFrame("Frame", "JarStickCursor", UIParent, "BackdropTemplate")
    hl:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    hl:SetBackdropColor(1, 0.85, 0.2, 0.18)
    hl:SetBackdropBorderColor(1, 0.85, 0.2)
    hl:EnableMouse(false)
    hl.tag = hl:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hl.tag:SetPoint("RIGHT", hl, "LEFT", -4, 0)
    local pulse = hl:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.55)
    a:SetDuration(0.6)
    hl:SetScript("OnShow", function() pulse:Play() end)
    hl:SetScript("OnHide", function() pulse:Stop() end)
    hl:Hide()

    legend = CreateFrame("Frame", "JarStickLegend", UIParent, "BackdropTemplate")
    legend:SetSize(200, 34)
    legend:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    legend:SetFrameStrata("HIGH")
    legend:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    legend:SetBackdropColor(0.08, 0.08, 0.1, 0.85)
    legend:SetBackdropBorderColor(1, 0.55, 0, 1)
    legend.text = legend:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    legend.text:SetPoint("CENTER")
    legend:Hide()

    reticle = CreateReticle()
    CreateHandler()
    UpdateReticle()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        -- needs the clusters and grids from JarStick.lua. after a /reload in combat
        -- the safe queue runs in no particular order, so let that side call us
        if ns.panels then
            ns.RunWhenSafe("interact-init", Init)
        else
            ns.InitInteract = Init
        end
        self:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
        for e in pairs(RESET) do self:RegisterEvent(e) end
        self:RegisterEvent("LOOT_SLOT_CLEARED")
        self:RegisterEvent("QUEST_DETAIL")
        self:RegisterEvent("QUEST_PROGRESS")
        self:RegisterEvent("GOSSIP_CLOSED")
        self:RegisterEvent("LOOT_CLOSED")
        self:RegisterEvent("QUEST_FINISHED")
        return
    end
    if not ui then return end
    if event == "PLAYER_LOGIN" then
        -- give other addons their own login handlers first
        C_Timer.After(1, AttachLateProbes)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        UpdateSoftObject()
        return
    end
    if event == "PLAYER_SOFT_INTERACT_CHANGED" or event == "GAME_PAD_ACTIVE_CHANGED" then
        if event == "PLAYER_SOFT_INTERACT_CHANGED" then
            softObject = GuidPresent(arg2)
            if ns.debug then
                local function Show(v)
                    if issecretvalue and issecretvalue(v) then return "SECRET" end
                    return tostring(v)
                end
                ns.Log(string.format("soft change: unit=%s old=%s new=%s combat=%s",
                    tostring(UnitExists("softinteract")), Show(arg1), Show(arg2), tostring(InCombatLockdown())))
            end
            UpdateSoftObject()
        end
        UpdateReticle()
        if legend:IsShown() then UpdateLegend() end
        if ns.debug then
            -- state driver polls every 0.2s, look after it had a chance
            C_Timer.After(0.4, function() ns.Log("after soft target change, PAD3 -> " .. tostring(GetBindingAction("PAD3", true))) end)
        end
        return
    end
    local k = RESET[event]
    if k then sel[k] = 1 end
    if event:find("GOSSIP") or event:find("QUEST") then sel.npc = 1 end
    RefreshSoon()
end)

ns.UpdateReticle = function()
    if reticle then UpdateReticle() end
end

-- for Book.lua: the same pad cursor, legend and handler poke
ns.Highlight = function(frame)
    if hl then Highlight(frame) end
end
ns.Glyph = Glyph
ns.RefreshLegend = function()
    if ui then UpdateLegend() end
end
ns.PokeUI = function()
    PokeHandler()
    if ui then RefreshSoon() end
end

ns.PanelChanged = function()
    if ui then RefreshSoon() end
end

ns.ApplyInteract = function()
    ns.RunWhenSafe("interact", function()
        if not ui then return end
        UnregisterStateDriver(ui, "interact")
        RegisterStateDriver(ui, "interact", InteractDriver())
    end)
end

ns.loadHooks[#ns.loadHooks + 1] = function() ev:GetScript("OnEvent")(ev, "ADDON_LOADED", ADDON) end
end
