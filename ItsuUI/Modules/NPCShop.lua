-- Itsu:UI: merchant, trainer + mailbox list, part of NPC chat

local _, ns = ...

-- blizzards merchant, trainer and mail windows stay open but invisible, so bag selling, junk
-- icons, COD and buy confirmations keep working. this draws a list on top of them
function ns.InitNPCShop()

local ROWS, ROW_H, LIST_W, MENU_W, PAD, HEAD = 8, 40, 400, 160, 12, 44
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STYLE = {
    bg = { 0.10, 0.10, 0.12, 0.92 },
    border = { 0.25, 0.25, 0.28, 1 },
    title = { 1.0, 0.82, 0.0 },
    dim = { 0.6, 0.6, 0.6 },
}

-- mode: buy, buyback, train, mail (inbox) or letter (one open mail). focus: list, menu or bags (pad only)
-- mail = the open mail's inbox index, letter = its header bits, sending = blizzards send tab is up
local S = { mode = nil, blizz = nil, entries = {}, menu = {}, offset = 0, cur = 1, mcur = 1, focus = "list",
    mail = nil, letter = {}, sending = false }
local BODY_MAX = 200

local function Backdrop(f)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    f:SetBackdropColor(unpack(STYLE.bg))
    f:SetBackdropBorderColor(unpack(STYLE.border))
end

local function Text(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(ns.GetFont(), size, "")
    fs.size = size
    return fs
end

-- frames ----------------------------------------------------------------------

local shop = CreateFrame("Frame", "JarsNPCShopFrame", UIParent)
shop:SetSize(LIST_W + 8 + MENU_W, PAD * 2 + HEAD + ROWS * ROW_H)
shop:SetPoint("CENTER", 0, 40)
shop:SetFrameStrata("HIGH")
shop:Hide()

local panel = CreateFrame("Frame", nil, shop, "BackdropTemplate")
panel:SetPoint("TOPLEFT")
panel:SetSize(LIST_W, shop:GetHeight())
panel:EnableMouse(true)
panel:EnableMouseWheel(true)
Backdrop(panel)

local title = Text(panel, 16)
title:SetPoint("TOPLEFT", PAD, -PAD)
title:SetTextColor(unpack(STYLE.title))
local sub = Text(panel, 12)
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
sub:SetTextColor(unpack(STYLE.dim))
local money = Text(panel, 13)
money:SetPoint("TOPRIGHT", -PAD, -PAD)
local empty = Text(panel, 13)
empty:SetPoint("CENTER", 0, -HEAD / 2)
empty:SetTextColor(unpack(STYLE.dim))

-- thin scroll bar, only there when the list is longer than ROWS
local track = panel:CreateTexture(nil, "ARTWORK")
track:SetColorTexture(1, 1, 1, 0.06)
track:SetWidth(4)
track:SetPoint("TOPRIGHT", -6, -(PAD + HEAD))
track:SetHeight(ROWS * ROW_H)
local thumb = panel:CreateTexture(nil, "OVERLAY")
thumb:SetColorTexture(unpack(STYLE.title))
thumb:SetWidth(4)

-- letter text sits between the header and the rows, wheel scrolls it when its long
local bodyScroll = CreateFrame("ScrollFrame", nil, panel)
bodyScroll:SetPoint("TOPLEFT", PAD, -(PAD + HEAD))
bodyScroll:SetSize(LIST_W - PAD * 2, 1)
bodyScroll:EnableMouseWheel(true)
bodyScroll:Hide()
local bodyChild = CreateFrame("Frame", nil, bodyScroll)
bodyChild:SetSize(LIST_W - PAD * 2, 1)
bodyScroll:SetScrollChild(bodyChild)
local body = Text(bodyChild, 13)
body:SetPoint("TOPLEFT")
body:SetWidth(LIST_W - PAD * 2 - 8)
body:SetJustifyH("LEFT")
body:SetSpacing(2)
bodyScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, bodyChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 20)))
end)

local menu = CreateFrame("Frame", nil, shop, "BackdropTemplate")
menu:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
menu:SetWidth(MENU_W)
Backdrop(menu)

-- tooltips --------------------------------------------------------------------

-- sticky = pad cursor, sits in the default bottom right spot like the enemy tooltip
local function ShowTip(r, sticky)
    local e = r.entry
    if not e then return end
    if sticky then
        GameTooltip_SetDefaultAnchor(GameTooltip, r)
    else
        GameTooltip:SetOwner(r, "ANCHOR_LEFT")
    end
    if e.kind == "buy" then
        GameTooltip:SetMerchantItem(e.index)
        if GameTooltip_ShowCompareItem and (IsModifiedClick("COMPAREITEMS") or GetCVarBool("alwaysCompareItems")) then
            GameTooltip_ShowCompareItem(GameTooltip)
        end
    elseif e.kind == "buyback" then
        GameTooltip:SetBuybackItem(e.index)
    elseif e.kind == "train" then
        GameTooltip:SetTrainerService(e.index)
    elseif e.kind == "attach" then
        GameTooltip:SetInboxItem(e.index, e.slot)
    elseif e.kind == "mail" then
        if e.items == 1 then
            GameTooltip:SetInboxItem(e.index)
        else
            GameTooltip:SetText(e.info ~= "" and e.info or e.name)
            if e.items > 1 then GameTooltip:AddLine(e.items .. " items", 1, 1, 1) end
        end
        if e.money > 0 then GameTooltip:AddLine("Money: " .. GetMoneyString(e.money, true), 1, 1, 1) end
        if e.cod > 0 then GameTooltip:AddLine("COD: " .. GetMoneyString(e.cod, true), 1, 0.4, 0.4) end
    else
        GameTooltip:SetText(e.name)
    end
    GameTooltip:Show()
end

local rows = {}

local function HideRowTip()
    local owner = GameTooltip:GetOwner()
    for _, r in ipairs(rows) do
        if owner == r then GameTooltip:Hide() end
    end
end

-- buying ----------------------------------------------------------------------

-- blizzards own item button for that index, flipped to the right page. its click
-- handlers do the extended cost + high price confirmations for us
local function BlizzButton(index)
    local per = MERCHANT_ITEMS_PER_PAGE or 10
    MerchantFrame.page = math.floor((index - 1) / per) + 1
    MerchantFrame_Update()
    return _G["MerchantItem" .. ((index - 1) % per + 1) .. "ItemButton"]
end

-- same math blizzard uses for a shift click split
local function MaxBuy(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    local n = GetMerchantItemMaxStack(index)
    if info.price and info.price > 0 then
        n = math.min(n, math.floor(GetMoney() / (info.price / info.stackCount)))
    end
    if info.hasExtendedCost then
        for i = 1, MAX_ITEM_COST or 3 do
            local _, value, link, currencyName = GetMerchantItemCostItem(index, i)
            if link and not currencyName and value and value > 0 then
                local have = C_Item.GetItemCount(link, false, false, true)
                n = math.min(n, math.floor(have / (value / info.stackCount)))
            end
        end
    end
    return n
end

local function BuyStack(e)
    local btn = BlizzButton(e.index)
    local n = MaxBuy(e.index)
    if btn and n > 0 then btn.SplitStack(btn, n) end
end

StaticPopupDialogs.ITSUUI_CONFIRM_PROFESSION = {
    text = "Learn %s?",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, index) BuyTrainerService(index) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Train(e)
    if e.status ~= "available" then return end
    if e.isProf and IsTradeskillTrainer() then
        if select(2, GetProfessions()) then
            UIErrorsFrame:AddMessage("You already have two professions", 1, 0.1, 0.1)
            return
        end
        StaticPopup_Show("ITSUUI_CONFIRM_PROFESSION", e.name, nil, e.index)
    else
        BuyTrainerService(e.index)
    end
end

-- mail: open it through blizzards inbox click, so OpenMailFrame (invisible) has it too
local function OpenLetter(index)
    InboxFrame_OnClick({ GetChecked = function() return true end }, index)
end

-- money + items in one go. COD mail has to go item by item through the confirm popup
local function TakeAll(index)
    if not index then return end
    local cod = select(6, GetInboxHeaderInfo(index))
    if cod and cod == 0 then AutoLootMailItem(index) end
end

local function ClickIf(btn)
    if btn and btn:IsEnabled() then btn:Click() end
end

-- button: mouse button, or "pad"
local function Activate(e, button)
    if not e then return end
    if e.kind == "mail" then
        -- shift click takes everything, same as blizzards inbox
        if button ~= "pad" and IsModifiedClick() then TakeAll(e.index) else OpenLetter(e.index) end
    elseif e.kind == "attach" then
        ClickIf(_G["OpenMailAttachmentButton" .. e.slot])
    elseif e.kind == "money" then
        ClickIf(OpenMailMoneyButton)
    elseif e.kind == "copy" then
        ClickIf(OpenMailLetterButton)
    elseif e.kind == "buyback" then
        BuybackItem(e.index)
    elseif e.kind == "train" then
        Train(e)
    elseif button ~= "pad" and IsModifiedClick() then
        -- shift split, ctrl dressup, chat links. blizzard does it, we move the split box over
        local btn = BlizzButton(e.index)
        MerchantItemButton_OnModifiedClick(btn, button)
        if StackSplitFrame and StackSplitFrame:IsShown() then
            StackSplitFrame:ClearAllPoints()
            StackSplitFrame:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 4)
        end
    else
        -- blizzard rules: right click buys, left click picks it up to drag into a bag
        MerchantItemButton_OnClick(BlizzButton(e.index), button == "pad" and "RightButton" or button)
    end
end

-- list ------------------------------------------------------------------------

local function Money(v, red)
    local s = GetMoneyString(v, true)
    return red and ("|cffff5050" .. s .. "|r") or s
end

local function Quality(link)
    local q = link and select(3, C_Item.GetItemInfo(link))
    local c = q and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function CostText(index, info)
    local parts = {}
    if info.price and info.price > 0 then parts[#parts + 1] = Money(info.price, GetMoney() < info.price) end
    if info.hasExtendedCost then
        for i = 1, MAX_ITEM_COST or 3 do
            local tex, value = GetMerchantItemCostItem(index, i)
            if tex and value and value > 0 then parts[#parts + 1] = value .. " |T" .. tex .. ":14:14|t" end
        end
    end
    return table.concat(parts, "  ")
end

local function BuildBuy(list)
    for i = 1, GetMerchantNumItems() do
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then
            if info.currencyID and CurrencyContainerUtil then
                info.name, info.texture, info.numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(
                    info.currencyID, info.numAvailable, info.name, info.texture, nil)
            end
            local bits = {}
            if info.stackCount and info.stackCount > 1 then bits[#bits + 1] = "x" .. info.stackCount end
            if info.numAvailable and info.numAvailable >= 0 then bits[#bits + 1] = info.numAvailable .. " left" end
            local r, g, b = Quality(GetMerchantItemLink(i))
            list[#list + 1] = {
                kind = "buy", index = i, name = info.name or "...", texture = info.texture,
                info = table.concat(bits, "   "), price = CostText(i, info),
                usable = info.isUsable and info.isPurchasable ~= false, r = r, g = g, b = b,
            }
        end
    end
end

local function BuildBuyback(list)
    for i = 1, GetNumBuybackItems() do
        local name, tex, price, qty, _, usable = GetBuybackItemInfo(i)
        if name then
            local r, g, b = Quality(GetBuybackItemLink(i))
            list[#list + 1] = {
                kind = "buyback", index = i, name = name, texture = tex,
                info = (qty or 1) > 1 and ("x" .. qty) or "", price = Money(price or 0, GetMoney() < (price or 0)),
                usable = usable, r = r, g = g, b = b,
            }
        end
    end
end

local TRAIN_COLOR = { available = { 1, 1, 1 }, unavailable = { 1, 0.35, 0.35 }, used = { 0.5, 0.5, 0.5 } }

local function BuildTrain(list)
    -- forever pet trainers charge training points, not gold
    local pet = C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType
        and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
    for i = 1, GetNumTrainerServices() do
        local name, status, tex, reqLevel, subText = GetTrainerServiceInfo(i)
        if name and status ~= "header" then
            local cost, isProf = GetTrainerServiceCost(i)
            local bits = {}
            if subText and subText ~= "" then bits[#bits + 1] = subText end
            if reqLevel and reqLevel > 1 and status ~= "used" then
                local lvl = "Level " .. reqLevel
                bits[#bits + 1] = UnitLevel("player") < reqLevel and ("|cffff5050" .. lvl .. "|r") or lvl
            end
            local price = ""
            if cost and cost > 0 then
                price = pet and (cost .. " TP") or Money(cost, GetMoney() < cost)
            end
            local c = TRAIN_COLOR[status] or TRAIN_COLOR.unavailable
            list[#list + 1] = {
                kind = "train", index = i, name = name, texture = tex, info = table.concat(bits, "   "),
                price = price, status = status, isProf = isProf, usable = status ~= "unavailable",
                r = c[1], g = c[2], b = c[3],
            }
        end
    end
end

local function BuildMail(list)
    for i = 1, GetInboxNumItems() do
        local pkg, stationery, sender, subject, cash, cod, days, items, wasRead = GetInboxHeaderInfo(i)
        local bits = { subject or "" }
        if days then
            local d = days >= 1 and (math.floor(days) .. " days") or "< 1 day"
            bits[#bits + 1] = days < 3 and ("|cffff5050" .. d .. "|r") or d
        end
        local price = ""
        if cod and cod > 0 then
            price = "COD " .. Money(cod, cod > GetMoney())
        elseif cash and cash > 0 then
            price = Money(cash)
        elseif items and items > 0 then
            price = items .. (items == 1 and " item" or " items")
        end
        -- read mail goes dim, like blizzards inbox
        local c = wasRead and 0.6 or 1
        list[#list + 1] = {
            kind = "mail", index = i, name = sender or "", texture = pkg or stationery,
            info = table.concat(bits, "   "), price = price, items = items or 0, money = cash or 0, cod = cod or 0,
            r = c, g = c * (wasRead and 1 or 0.82), b = wasRead and c or 0,
        }
    end
end

local function InvoiceText(index)
    local kind, item, who, bid, _, deposit, cut = GetInboxInvoiceInfo(index)
    if kind == "seller" then
        return ("Sold %s to %s\nSale price: %s\nDeposit: %s\nAuction house cut: %s"):format(item or "?", who or "?",
            Money(bid or 0), Money(deposit or 0), Money(cut or 0))
    elseif kind == "buyer" then
        return ("Bought %s from %s for %s"):format(item or "?", who or "?", Money(bid or 0))
    end
    return ""
end

local function BuildLetter(list)
    local i = S.mail
    wipe(S.letter)
    local _, _, sender, subject, cash, cod, _, _, _, _, textCreated, canReply = GetInboxHeaderInfo(i or 0)
    if not sender then return end
    local text, _, _, takeable, invoice = GetInboxText(i)
    S.letter.sender, S.letter.subject, S.letter.cod, S.letter.canReply = sender, subject, cod or 0, canReply
    S.letter.body = invoice and InvoiceText(i) or text or ""
    if cash and cash > 0 then
        list[#list + 1] = { kind = "money", name = "Money", texture = "Interface\\Icons\\INV_Misc_Coin_01", price = Money(cash) }
    end
    for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, _, tex, count, quality, canUse = GetInboxItem(i, a)
        if name then
            local c = quality and ITEM_QUALITY_COLORS[quality]
            list[#list + 1] = {
                kind = "attach", index = i, slot = a, name = name, texture = tex,
                info = (count or 1) > 1 and ("x" .. count) or "", usable = canUse,
                price = (cod and cod > 0) and ("COD " .. Money(cod, cod > GetMoney())) or "",
                r = c and c.r or 1, g = c and c.g or 1, b = c and c.b or 1,
            }
        end
    end
    if takeable and not textCreated then
        list[#list + 1] = { kind = "copy", name = "Copy of the letter", texture = "Interface\\Icons\\INV_Misc_Note_01" }
    end
end

local function Build()
    wipe(S.entries)
    if S.mode == "buy" then
        BuildBuy(S.entries)
    elseif S.mode == "buyback" then
        BuildBuyback(S.entries)
    elseif S.mode == "train" then
        BuildTrain(S.entries)
    elseif S.mode == "mail" then
        BuildMail(S.entries)
    elseif S.mode == "letter" then
        BuildLetter(S.entries)
    end
end

for i = 1, ROWS do
    local r = CreateFrame("Button", nil, panel)
    r:SetSize(LIST_W - PAD * 2 - 6, ROW_H - 2)
    r:SetPoint("TOPLEFT", PAD, -(PAD + HEAD + (i - 1) * ROW_H))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(1, 1, 1, 0.07)
    r.hover:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 8, ROW_H - 8)
    r.icon:SetPoint("LEFT", 2, 0)
    r.price = Text(r, 12)
    r.price:SetPoint("RIGHT", -4, 0)
    r.price:SetJustifyH("RIGHT")
    r.name = Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
    r.name:SetWidth(LIST_W - PAD * 2 - ROW_H - 140)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.info = Text(r, 11)
    r.info:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 2)
    r.info:SetTextColor(unpack(STYLE.dim))
    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        ShowTip(self, false)
    end)
    r:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button) Activate(self.entry, button) end)
    rows[i] = r
end

-- menu ------------------------------------------------------------------------

local menuButtons = {}
local function MenuButton(i)
    local b = menuButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, menu)
    b:SetSize(MENU_W - 16, 28)
    b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 30)
    b.hover = b:CreateTexture(nil, "BACKGROUND")
    b.hover:SetAllPoints()
    b.hover:SetColorTexture(1, 1, 1, 0.07)
    b.hover:Hide()
    b.label = Text(b, 13)
    b.label:SetPoint("LEFT", 6, 0)
    b.value = Text(b, 11)
    b.value:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.item and not self.item.disabled then self.item.fn(false) end
    end)
    menuButtons[i] = b
    return b
end

local Render, Close

local function SetMode(mode)
    S.mode, S.offset, S.cur = mode, 0, 1
    Build()
    Render()
end

local function JunkCount()
    if C_MerchantFrame.GetNumJunkItems then return C_MerchantFrame.GetNumJunkItems() end
    return 1
end

local function SellJunk()
    if C_MerchantFrame.IsSellAllJunkEnabled and C_MerchantFrame.IsSellAllJunkEnabled()
        and MerchantFrame_OnSellAllJunkButtonClicked then
        MerchantFrame_OnSellAllJunkButtonClicked()
        return
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.quality == 0 and not item.hasNoValue then C_Container.UseContainerItem(bag, slot) end
        end
    end
end

-- blizzard hides OpenMailFrame after a delete or return, its OnHide brings us back to the inbox
local function Back()
    HideUIPanel(OpenMailFrame)
end

local function MenuItems()
    local list = {}
    if S.mode == "mail" then
        list[#list + 1] = { text = "Open all", fn = function() ClickIf(OpenAllMail) end,
            disabled = #S.entries == 0 or not (OpenAllMail and OpenAllMail:IsEnabled()) }
        -- writing needs text boxes, so blizzards send tab comes back for that. its Inbox tab returns here
        list[#list + 1] = { text = "Send mail", fn = function() MailFrameTab_OnClick(nil, 2) end }
    elseif S.mode == "letter" then
        list[#list + 1] = { text = "Take all", fn = function() TakeAll(S.mail) end,
            disabled = #S.entries == 0 or (S.letter.cod or 0) > 0 }
        list[#list + 1] = { text = "Reply", fn = function() ClickIf(OpenMailReplyButton) end,
            disabled = not OpenMailReplyButton:IsEnabled() }
        list[#list + 1] = { text = InboxItemCanDelete(S.mail) and "Delete" or "Return",
            fn = function() ClickIf(OpenMailDeleteButton) end, disabled = not OpenMailDeleteButton:IsEnabled() }
        list[#list + 1] = { text = "Back", fn = Back }
    elseif S.mode ~= "train" then
        list[#list + 1] = { text = "Buy", on = S.mode == "buy", fn = function() SetMode("buy") end }
        list[#list + 1] = { text = "Buyback", on = S.mode == "buyback", fn = function() SetMode("buyback") end }
        if CanMerchantRepair() then
            local cost, can = GetRepairAllCost()
            list[#list + 1] = { text = "Repair", value = can and Money(cost) or "", disabled = not can,
                fn = function() RepairAllItems() end }
            if CanGuildBankRepair and CanGuildBankRepair() then
                list[#list + 1] = { text = "Guild repair", disabled = not can, fn = function() RepairAllItems(true) end }
            end
        end
        list[#list + 1] = { text = "Sell junk", disabled = JunkCount() == 0, fn = SellJunk }
        -- pad: hands the cursor to the bags, X sells whatever its on. B comes back here
        list[#list + 1] = { text = "Sell items", fn = function(pad)
            OpenAllBags()
            if pad then
                S.focus = "bags"
                HideRowTip()
            end
        end }
    end
    list[#list + 1] = { text = "Close", fn = function() Close() end }
    return list
end

local function RenderMenu()
    S.menu = MenuItems()
    for i, item in ipairs(S.menu) do
        local b = MenuButton(i)
        b.item = item
        b.label:SetText(item.text)
        b.value:SetText(item.value or "")
        if item.disabled then
            b.label:SetTextColor(0.45, 0.45, 0.45)
        elseif item.on then
            b.label:SetTextColor(unpack(STYLE.title))
        else
            b.label:SetTextColor(1, 1, 1)
        end
        b:Show()
    end
    for i = #S.menu + 1, #menuButtons do menuButtons[i]:Hide() end
    menu:SetHeight(16 + #S.menu * 30)
    S.mcur = math.max(1, math.min(S.mcur, #S.menu))
end

local SUB = { buy = "Buy", buyback = "Buyback", train = "Trainer", mail = "Inbox" }
local EMPTY = { buy = "Nothing for sale", buyback = "Nothing to buy back", train = "Nothing to learn",
    mail = "No mail", letter = "Nothing attached" }

-- the letter text pushes the rows down, everything below it follows
local function Layout(bodyH)
    for i, r in ipairs(rows) do r:SetPoint("TOPLEFT", PAD, -(PAD + HEAD + bodyH + (i - 1) * ROW_H)) end
    track:SetPoint("TOPRIGHT", -6, -(PAD + HEAD + bodyH))
    empty:SetPoint("CENTER", 0, -(HEAD + bodyH) / 2)
    local h = PAD * 2 + HEAD + bodyH + ROWS * ROW_H
    panel:SetHeight(h)
    shop:SetHeight(h)
end

local function Header()
    if S.mode == "mail" then
        local shown, total = GetInboxNumItems()
        title:SetText("Mailbox")
        sub:SetText((total and total > shown) and ("Inbox  (%d of %d)"):format(shown, total) or ("Inbox  (%d)"):format(shown))
    elseif S.mode == "letter" then
        title:SetText(S.letter.sender or "")
        sub:SetText(S.letter.subject or "")
    else
        title:SetText(UnitName("npc") or "")
        sub:SetText(SUB[S.mode] or "")
    end
    local text = S.mode == "letter" and S.letter.body or ""
    if text == "" then
        bodyScroll:Hide()
        Layout(0)
        return
    end
    body:SetText(text)
    local th = body:GetStringHeight()
    bodyChild:SetHeight(th)
    bodyScroll:SetHeight(math.min(th, BODY_MAX))
    bodyScroll:Show()
    Layout(math.min(th, BODY_MAX) + 10)
end

Render = function()
    local n = #S.entries
    S.offset = math.max(0, math.min(S.offset, n - ROWS))
    -- buying back the last item etc shrinks the list under the pad cursor
    S.cur = math.max(1, math.min(S.cur, n))
    for i, r in ipairs(rows) do
        local e = S.entries[S.offset + i]
        r.entry = e
        if e then
            r.icon:SetTexture(e.texture)
            if e.usable == false then r.icon:SetVertexColor(1, 0.3, 0.3) else r.icon:SetVertexColor(1, 1, 1) end
            r.name:SetText(e.name)
            r.name:SetTextColor(e.r or 1, e.g or 1, e.b or 1)
            r.info:SetText(e.info or "")
            r.price:SetText(e.price or "")
            r:Show()
        else
            r:Hide()
        end
    end
    empty:SetText(EMPTY[S.mode] or "")
    empty:SetShown(n == 0)
    if n > ROWS then
        local h = ROWS * ROW_H
        local th = math.max(16, h * ROWS / n)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(h - th) * S.offset / (n - ROWS))
        track:Show()
        thumb:Show()
    else
        track:Hide()
        thumb:Hide()
    end
    Header()
    money:SetText(GetMoneyString(GetMoney(), true))
    RenderMenu()
end

panel:SetScript("OnMouseWheel", function(_, delta)
    S.offset = S.offset - delta * 2
    Render()
    -- whatever row is under the mouse now has a different item
    for _, r in ipairs(rows) do
        if r:IsShown() and r:IsMouseOver() then ShowTip(r, false) end
    end
end)

-- open / close ----------------------------------------------------------------

Close = function()
    if S.mode == "train" then
        CloseTrainer()
    elseif S.mode == "mail" or S.mode == "letter" then
        CloseMail()
    else
        CloseMerchant()
    end
end

local function Open(frame, mode)
    S.blizz, S.focus, S.mcur = frame, "list", 1
    -- back from the send tab with a mail still open
    if mode == "mail" and OpenMailFrame and OpenMailFrame:IsShown() then
        S.mail = InboxFrame.openMailID
        mode = "letter"
    end
    SetMode(mode)
    shop:Show()
end

shop:SetScript("OnHide", function()
    HideRowTip()
    S.focus = "list"
    -- the send tab hides us without closing the mailbox
    if S.blizz and S.blizz:IsShown() and not S.sending then Close() end
    if not S.sending then S.blizz = nil end
end)

-- shrunk to nothing and see through, still "shown" as far as blizzard knows
local scales = {}
local function Conceal(f)
    if f:GetScale() > 0.05 then scales[f] = f:GetScale() end
    f:SetAlpha(0)
    f:SetScale(0.01)
end

local function Reveal(f)
    f:SetAlpha(1)
    f:SetScale(scales[f] or 1)
end

local taken = {}
local function Take(frame, mode)
    if taken[frame] then return end
    taken[frame] = true
    frame:HookScript("OnShow", function()
        Conceal(frame)
        Open(frame, mode)
    end)
    frame:HookScript("OnHide", function()
        if S.blizz == frame then
            S.sending = false
            shop:Hide()
        end
    end)
    if frame:IsShown() then
        Conceal(frame)
        Open(frame, mode)
    end
end

Take(MerchantFrame, "buy")
if ClassTrainerFrame then Take(ClassTrainerFrame, "train") end

local function TakeMail()
    if taken[OpenMailFrame] then return end
    taken[OpenMailFrame] = true
    Take(MailFrame, "mail")
    OpenMailFrame:HookScript("OnShow", function(self)
        Conceal(self)
        if shop:IsShown() then
            S.mail = InboxFrame.openMailID
            S.focus = "list"
            SetMode("letter")
        end
    end)
    OpenMailFrame:HookScript("OnHide", function()
        if S.mode == "letter" and shop:IsShown() then SetMode("mail") end
    end)
    -- send tab: blizzards window comes back and we step aside. inbox tab: the other way round
    hooksecurefunc("MailFrameTab_OnClick", function(tab, id)
        if not MailFrame:IsShown() then return end
        id = id or (tab and tab:GetID())
        if id == 2 then
            S.sending = true
            Reveal(MailFrame)
            shop:Hide()
        elseif S.sending then
            S.sending = false
            Conceal(MailFrame)
            Open(MailFrame, "mail")
        end
    end)
end
if MailFrame and OpenMailFrame then TakeMail() end

local pending = false
local function RenderSoon()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if not shop:IsShown() then return end
        Build()
        Render()
    end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "MERCHANT_UPDATE", "PLAYER_MONEY", "BAG_UPDATE_DELAYED",
    "UPDATE_INVENTORY_DURABILITY", "GET_ITEM_INFO_RECEIVED", "TRAINER_UPDATE", "MAIL_INBOX_UPDATE" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TrainerUI" and ClassTrainerFrame then Take(ClassTrainerFrame, "train") end
        if arg1 == "Blizzard_MailFrame" and MailFrame and OpenMailFrame then TakeMail() end
        return
    end
    if shop:IsShown() then RenderSoon() end
end)

ns.OnShared(function()
    for _, fs in ipairs({ title, sub, money, empty, body }) do fs:SetFont(ns.GetFont(), fs.size, "") end
    for _, r in ipairs(rows) do
        for _, fs in ipairs({ r.name, r.info, r.price }) do fs:SetFont(ns.GetFont(), fs.size, "") end
    end
    for _, b in ipairs(menuButtons) do
        b.label:SetFont(ns.GetFont(), b.label.size, "")
        b.value:SetFont(ns.GetFont(), b.value.size, "")
    end
end)

-- escape menu -----------------------------------------------------------------
-- same flat look as the rest. only the art changes, the buttons stay blizzards own so
-- Log Out, Exit and Edit Mode never run from our code

local gmSkin, gmTitle
local gmHover = {}

local function SkinGameMenu()
    local f = GameMenuFrame
    if not gmSkin then
        if f.Border then f.Border:SetAlpha(0) end
        if f.Header then f.Header:SetAlpha(0) end
        gmSkin = CreateFrame("Frame", nil, f, "BackdropTemplate")
        gmSkin.ignoreInLayout = true
        gmSkin:SetAllPoints()
        gmSkin:SetFrameLevel(f:GetFrameLevel())
        Backdrop(gmSkin)
        gmTitle = Text(gmSkin, 16)
        gmTitle:SetPoint("TOP", 0, -16)
        gmTitle:SetTextColor(unpack(STYLE.title))
        gmTitle:SetText(MAINMENU_BUTTON or "Game Menu")
    end
    for b in f.buttonPool:EnumerateActive() do
        for _, part in ipairs({ "Left", "Center", "Right" }) do
            if b[part] then b[part]:SetAlpha(0) end
        end
        local hl = b:GetHighlightTexture()
        if hl then hl:SetAlpha(0) end
        local fs = b:GetFontString()
        if fs then fs:SetFont(ns.GetFont(), 15, "") end
        local hover = gmHover[b]
        if not hover then
            hover = b:CreateTexture(nil, "BACKGROUND")
            hover:SetPoint("TOPLEFT", 0, -3)
            hover:SetPoint("BOTTOMRIGHT", 0, 3)
            hover:SetColorTexture(1, 1, 1, 0.07)
            gmHover[b] = hover
        end
        hover:Hide()
        -- AddButton resets OnEnter/OnLeave every time the menu opens, so these go back on each time
        b:HookScript("OnEnter", function() hover:Show() end)
        b:HookScript("OnLeave", function() hover:Hide() end)
    end
end

if GameMenuFrame and GameMenuFrame.InitButtons and GameMenuFrame.buttonPool then
    hooksecurefunc(GameMenuFrame, "InitButtons", SkinGameMenu)
end

-- pad -------------------------------------------------------------------------
-- Interact.lua (controller mode) drives this through JarsNPCShopAPI

local function ClampCur()
    local n = #S.entries
    if n == 0 then
        S.cur = 1
        return
    end
    if S.cur < 1 then S.cur = n elseif S.cur > n then S.cur = 1 end
    if S.cur <= S.offset then
        S.offset = S.cur - 1
    elseif S.cur > S.offset + ROWS then
        S.offset = S.cur - ROWS
    end
end

local function CurrentRow()
    local r = rows[S.cur - S.offset]
    if r and r:IsShown() then return r end
end

local VERB = { buy = "Buy", buyback = "Buy back", train = "Train", mail = "Open", letter = "Take" }
local NAV = { train = "Skill", mail = "Mail" }

JarsNPCShopAPI = {
    frame = shop,
    BagFocus = function() return S.focus == "bags" end,
    LeaveBags = function() S.focus = "list" end,
    Current = function()
        if S.focus == "menu" then return menuButtons[S.mcur] end
        return CurrentRow()
    end,
    -- the item under the pad cursor keeps its tooltip up
    PadTip = function()
        if S.focus ~= "list" then
            HideRowTip()
            return
        end
        local r = CurrentRow()
        if r and r.entry then ShowTip(r, true) end
    end,
    Key = function(key)
        if key == "PADDUP" or key == "PADDDOWN" then
            local d = key == "PADDUP" and -1 or 1
            if S.focus == "menu" then
                S.mcur = (S.mcur - 1 + d) % #S.menu + 1
            else
                S.cur = S.cur + d
                ClampCur()
                Render()
            end
        elseif key == "PADDRIGHT" then
            S.focus = "menu"
        elseif key == "PADDLEFT" then
            S.focus = "list"
        elseif key == "PAD3" then
            if S.focus == "menu" then
                local item = S.menu[S.mcur]
                if item and not item.disabled then item.fn(true) end
            else
                Activate(S.entries[S.cur], "pad")
            end
        elseif key == "PAD4" and S.focus == "list" and S.entries[S.cur] then
            if S.mode == "buy" then
                BuyStack(S.entries[S.cur])
            elseif S.mode == "mail" then
                TakeAll(S.entries[S.cur].index)
            elseif S.mode == "letter" then
                TakeAll(S.mail)
            end
        elseif key == "PAD2" then
            if S.mode == "letter" then Back() else Close() end
        end
    end,
    Legend = function()
        local close = S.mode == "letter" and "Back" or "Close"
        if S.focus == "menu" then
            return { { "PAD3", "Select" }, { "PADDLEFT", "List" }, { "PAD2", close }, { "NAV", "Menu" } }
        end
        local list = {}
        local any = #S.entries > 0
        if any then list[#list + 1] = { "PAD3", VERB[S.mode] } end
        if any and S.mode == "buy" then list[#list + 1] = { "PAD4", "Buy stack" } end
        if any and (S.mode == "mail" or S.mode == "letter") then list[#list + 1] = { "PAD4", "Take all" } end
        list[#list + 1] = { "PADDRIGHT", "Menu" }
        list[#list + 1] = { "PAD2", close }
        if #S.entries > 1 then list[#list + 1] = { "NAV", NAV[S.mode] or "Item" } end
        return list
    end,
}

end
