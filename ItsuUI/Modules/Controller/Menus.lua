-- Itsu:UI controller mode: list menus the pad drives
-- Select tap: a menu like the shop window (Character, Map ...). X opens, B closes.
-- Game menu (Start): d-pad walks Blizzard's buttons, X is a real key press on the picked one
--   through a secure click proxy, so Log Out / Exit / Edit Mode stay untainted.
-- Flight map: d-pad hops between flight points, Y flips to an A-Z list, X flies, B closes.
-- Interact.lua binds the keys and asks MenuNav() what is up.

local _, jf = ...
jf.jsParts = jf.jsParts or {}
jf.jsParts[#jf.jsParts + 1] = function(ns, ADDON)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local STYLE = {
    bg = { 0.10, 0.10, 0.12, 0.92 },
    border = { 0.25, 0.25, 0.28, 1 },
    title = { 1.0, 0.82, 0.0 },
    dim = { 0.6, 0.6, 0.6 },
}

local function Backdrop(f)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    f:SetBackdropColor(unpack(STYLE.bg))
    f:SetBackdropBorderColor(unpack(STYLE.border))
end

local function Text(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(jf.GetFont(), size, "")
    return fs
end

local function Wrap(i, n)
    if n < 1 then return 1 end
    return ((i - 1) % n) + 1
end

-- a list panel: title + rows with an icon on the left
local function ListFrame(name, width, rowH, maxRows)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetWidth(width)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    Backdrop(f)
    f.title = Text(f, 16)
    f.title:SetPoint("TOPLEFT", 12, -12)
    f.title:SetTextColor(unpack(STYLE.title))
    f.rows = {}
    for i = 1, maxRows do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(width - 24, rowH - 2)
        r:SetPoint("TOPLEFT", 12, -(40 + (i - 1) * rowH))
        r.hover = r:CreateTexture(nil, "BACKGROUND")
        r.hover:SetAllPoints()
        r.hover:SetColorTexture(1, 1, 1, 0.07)
        r.hover:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(rowH - 8, rowH - 8)
        r.icon:SetPoint("LEFT", 2, 0)
        r.label = Text(r, 14)
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.value = Text(r, 12)
        r.value:SetPoint("RIGHT", -6, 0)
        r:SetScript("OnEnter", function(self) self.hover:Show() end)
        r:SetScript("OnLeave", function(self) self.hover:Hide() end)
        f.rows[i] = r
    end
    function f:Fit(n)
        for i, r in ipairs(self.rows) do r:SetShown(i <= n) end
        self:SetHeight(52 + n * rowH)
    end
    return f
end

-- select menu ---------------------------------------------------------------------

local sel = ListFrame("JarStickSelMenu", 300, 36, #ns.MenuItems)
sel:SetPoint("CENTER", 0, 30)
sel.title:SetText("Menu")
sel.pick = 1

local function OpenPick(i)
    local it = ns.MenuItems[i]
    sel:Hide()
    if it then ns.OpenMenuItem(it) end
end

for i, it in ipairs(ns.MenuItems) do
    local r = sel.rows[i]
    r.icon:SetTexture(it.icon)
    r.label:SetText(it.name)
    r:SetScript("OnClick", function() OpenPick(i) end)
end
sel:Fit(#ns.MenuItems)
sel:SetScript("OnShow", function(self) self.pick = 1 end)

-- tap Select: Wheel.lua calls this. out of combat only, the pad cant be handed over in combat
ns.ToggleSelMenu = function()
    if InCombatLockdown() then return end
    sel:SetShown(not sel:IsShown())
end

local selNav = {
    Key = function(key)
        local n = #ns.MenuItems
        if key == "PADDUP" then
            sel.pick = Wrap(sel.pick - 1, n)
        elseif key == "PADDDOWN" then
            sel.pick = Wrap(sel.pick + 1, n)
        elseif key == "PAD3" then
            OpenPick(sel.pick)
        elseif key == "PAD2" then
            sel:Hide()
        end
    end,
    Current = function() return sel.rows[sel.pick] end,
    Legend = function() return { { "PAD3", "Open" }, { "PAD2", "Close" }, { "NAV", "Pick" } } end,
    Anchor = function() return sel end,
}

-- game menu -----------------------------------------------------------------------
-- the picked button rides on two secure click proxies. Interact.lua binds X and B to
-- them like it does for popups, so the press is a real key event on Blizzard's button

local function Proxy(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "click")
    return b
end
local gmClick = Proxy("JarStickMenuClick")
local gmBack = Proxy("JarStickMenuBack")
local gm = { pick = 1 }

local function GMButtons()
    local list = {}
    if GameMenuFrame and GameMenuFrame.buttonPool then
        for b in GameMenuFrame.buttonPool:EnumerateActive() do
            if b:IsShown() then list[#list + 1] = b end
        end
    end
    table.sort(list, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    return list
end

-- the bottom one is Return to Game
local function GMCurrent()
    local list = GMButtons()
    gm.pick = math.max(1, math.min(gm.pick, #list))
    local b = list[gm.pick]
    if not InCombatLockdown() then
        gmClick:SetAttribute("clickbutton", b)
        gmBack:SetAttribute("clickbutton", list[#list])
    end
    return b
end

local function GMMove(d)
    local list = GMButtons()
    for _ = 1, #list do
        gm.pick = Wrap(gm.pick + d, #list)
        if list[gm.pick]:IsEnabled() then return end
    end
end

local gmNav = {
    Key = function(key)
        if key == "PADDUP" then GMMove(-1) elseif key == "PADDDOWN" then GMMove(1) end
    end,
    Current = GMCurrent,
    Legend = function() return { { "PAD3", "Select" }, { "PAD2", "Close" }, { "NAV", "Option" } } end,
    Anchor = function() return GameMenuFrame end,
}

if GameMenuFrame then
    GameMenuFrame:HookScript("OnShow", function() gm.pick = 1 end)
end

-- flight map ------------------------------------------------------------------------

local taxi = { list = false, slot = nil, pick = 1, hovered = nil }
local LIST_ROWS = 14
local tl = ListFrame("JarStickTaxiList", 280, 30, LIST_ROWS)
tl.title:SetText("Fly to")
tl.offset = 0

local function TaxiMap()
    if FlightMapFrame and FlightMapFrame:IsShown() then return FlightMapFrame end
    if TaxiFrame and TaxiFrame:IsShown() then return TaxiFrame end
end

local REACH = { CURRENT = true, REACHABLE = true }

-- current + reachable points only, the gray nubs and unreachable ones are skipped
local function Nodes(map)
    local list = {}
    if map == FlightMapFrame then
        local state = Enum.FlightPathState
        for pin in map:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
            local d = pin.taxiNodeData
            if d and pin:IsShown() and not pin.isMapLayerTransition
                and (d.state == state.Current or d.state == state.Reachable) then
                list[#list + 1] = { frame = pin, slot = d.slotIndex, name = d.name, current = d.state == state.Current }
            end
        end
    else
        for i = 1, NumTaxiNodes() do
            local b, t = _G["TaxiButton" .. i], TaxiNodeGetType(i)
            if b and b:IsShown() and REACH[t] then
                list[#list + 1] = { frame = b, slot = i, name = TaxiNodeName(i), current = t == "CURRENT" }
            end
        end
    end
    return list
end

-- the route line + cost tooltip, same as mousing over the point
local function Unhover()
    local f = taxi.hovered
    taxi.hovered = nil
    if not f then return end
    if f.OnMouseLeave then
        f:OnMouseLeave()
    elseif f:GetScript("OnLeave") then
        f:GetScript("OnLeave")(f)
    end
end

local function Hover(f)
    if taxi.hovered == f then return end
    Unhover()
    taxi.hovered = f
    if f.OnMouseEnter then
        f:OnMouseEnter()
    elseif f:GetScript("OnEnter") then
        f:GetScript("OnEnter")(f)
    end
end

local function Find(nodes, slot)
    for _, n in ipairs(nodes) do
        if n.slot == slot then return n end
    end
    for _, n in ipairs(nodes) do
        if n.current then return n end
    end
    return nodes[1]
end

-- nearest point that way, sideways drift costs double. same rule as the bag cursor
local function Hop(key, nodes)
    local cur = Find(nodes, taxi.slot)
    if not cur then return end
    local cx, cy = cur.frame:GetCenter()
    local vx, vy = 0, 0
    if key == "PADDUP" then vy = 1 elseif key == "PADDDOWN" then vy = -1 elseif key == "PADDLEFT" then vx = -1 else vx = 1 end
    local best, score
    for _, n in ipairs(nodes) do
        local x, y = n.frame:GetCenter()
        if x and cx then
            local dx, dy = x - cx, y - cy
            local fwd, side = dx * vx + dy * vy, math.abs(dx * vy - dy * vx)
            if fwd > 1 and (not score or fwd + side * 2 < score) then best, score = n, fwd + side * 2 end
        end
    end
    if best then taxi.slot = best.slot end
end

-- A-Z, without the one you are standing at
local function Destinations(nodes)
    local list = {}
    for _, n in ipairs(nodes) do
        if not n.current then list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function DrawList(map, dest)
    taxi.pick = math.max(1, math.min(taxi.pick, #dest))
    if taxi.pick <= tl.offset then
        tl.offset = taxi.pick - 1
    elseif taxi.pick > tl.offset + LIST_ROWS then
        tl.offset = taxi.pick - LIST_ROWS
    end
    local shown = math.min(LIST_ROWS, #dest)
    for i = 1, shown do
        local n, r = dest[tl.offset + i], tl.rows[i]
        r.icon:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-White")
        r.label:SetText(n.name)
        local cost = TaxiNodeCost(n.slot)
        r.value:SetText(cost and cost > 0 and GetMoneyString(cost, true) or "")
    end
    tl:Fit(math.max(shown, 1))
    tl:ClearAllPoints()
    tl:SetPoint("TOPLEFT", map, "TOPRIGHT", 8, 0)
    tl:Show()
end

local function TaxiCurrent()
    local map = TaxiMap()
    if not map then return end
    local nodes = Nodes(map)
    if taxi.list then
        local dest = Destinations(nodes)
        if #dest == 0 then return end
        DrawList(map, dest)
        local n = dest[taxi.pick]
        taxi.slot = n.slot
        Hover(n.frame)
        return tl.rows[taxi.pick - tl.offset]
    end
    tl:Hide()
    local n = Find(nodes, taxi.slot)
    if not n then return end
    taxi.slot = n.slot
    Hover(n.frame)
    return n.frame
end

local function Fly()
    local n = Find(Nodes(TaxiMap()), taxi.slot)
    if n and not n.current then TakeTaxiNode(n.slot) end
end

local taxiNav = {
    Key = function(key)
        local map = TaxiMap()
        if key == "PAD3" then
            Fly()
        elseif key == "PAD4" then
            taxi.list = not taxi.list
            -- the list starts on whatever the map cursor was on
            if taxi.list then
                for i, n in ipairs(Destinations(Nodes(map))) do
                    if n.slot == taxi.slot then taxi.pick = i end
                end
            end
        elseif key == "PAD2" then
            CloseTaxiMap()
        elseif taxi.list then
            local n = #Destinations(Nodes(map))
            if key == "PADDUP" then taxi.pick = Wrap(taxi.pick - 1, n) end
            if key == "PADDDOWN" then taxi.pick = Wrap(taxi.pick + 1, n) end
        elseif key:find("^PADD") then
            Hop(key, Nodes(map))
        end
    end,
    Current = TaxiCurrent,
    Legend = function()
        return { { "PAD3", "Fly" }, { "PAD4", taxi.list and "Map" or "List" }, { "PAD2", "Close" },
            { "NAV", "Flight point" } }
    end,
}

local function TaxiClosed()
    Unhover()
    tl:Hide()
    taxi.list, taxi.slot, taxi.pick, tl.offset = false, nil, 1, 0
end

local hooked = {}
local function HookTaxi(f)
    if f and not hooked[f] then
        hooked[f] = true
        f:HookScript("OnHide", TaxiClosed)
    end
end
HookTaxi(TaxiFrame)
HookTaxi(FlightMapFrame)

-- for Interact.lua: whichever of these is up drives the pad. game menu sits on top
ns.MenuNav = function()
    if GameMenuFrame and GameMenuFrame:IsShown() then return gmNav end
    if sel:IsShown() then return selNav end
    if TaxiMap() then return taxiNav end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_DISABLED" then
        sel:Hide()
    elseif name == "Blizzard_FlightMap" then
        HookTaxi(FlightMapFrame)
        if ns.AttachLateProbes then ns.AttachLateProbes() end
    end
end)

end
