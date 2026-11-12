-- Itsu:UI controller mode, started from JarStick. edit it here
-- JarStick wheels
-- Select wheel: hold Select, push the right stick, let go of Select to open the pick.
-- Party ring: R1 + L1 in either order, point the right stick to target. Let go of either to close.
-- The ring targets through a secure button. The stick directions are bound as keys while it is
-- open (GamePadStickAxisButtons), so the pick works in combat. The drawing is all insecure.

local _, jf = ...
jf.jsParts = jf.jsParts or {}
jf.jsParts[#jf.jsParts + 1] = function(ns, ADDON)

local PALETTE = {
    bg = { 0.10, 0.10, 0.12, 0.92 },
    accent = { 1.0, 0.55, 0.0, 1 },
    text = { 0.95, 0.95, 0.95, 1 },
    textDim = { 0.70, 0.70, 0.70, 1 },
    border = { 0.25, 0.25, 0.28, 1 },
}
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- clockwise from the top. no game menu, Start already does it and calling it from addon code taints.
-- RunBinding is blizzard only now (ADDON_ACTION_FORBIDDEN), so each item calls what its binding runs.
-- spellbook and talents are blizzards own here, L2 + R2 + A / Y open the jarstick book
local ITEMS = {
    { name = "Character", fn = function() ToggleCharacter("PaperDollFrame") end, icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
    { name = "Spellbook", fn = function() PlayerSpellsUtil.ToggleSpellBookFrame() end, icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { name = "Talents", fn = function() PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() end, icon = "Interface\\Icons\\Ability_Marksmanship" },
    { name = "Professions", fn = function() ToggleProfessionsBook() end, icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { name = "Bags", fn = function() ToggleAllBags() end, icon = "Interface\\Icons\\INV_Misc_Bag_08" },
    { name = "Collections", fn = function() ToggleCollectionsJournal() end, icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { name = "Housing", fn = function() HousingFramesUtil.ToggleHousingDashboard() end, icon = "Interface\\Icons\\INV_Misc_Rune_01" },
    { name = "Shop", fn = function() ToggleStoreUI() end, icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { name = "Calendar", fn = function() ToggleCalendar() end, icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { name = "Achievements", icon = "Interface\\Icons\\Achievement_General", fn = function()
        if (HasCompletedAnyAchievement() or IsInGuild()) and CanShowAchievementUI() then ToggleAchievementFrame() end
    end },
    { name = "Adventure guide", icon = "Interface\\Icons\\INV_Bone_Skull_04", fn = function()
        if CanShowEncounterJournal() then ToggleEncounterJournal() end
    end },
    { name = "Map & quests", fn = function() ToggleWorldMap() end, icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { name = "Group finder", fn = function() PVEFrame_ToggleFrame() end, icon = "Interface\\Icons\\INV_Sword_04" },
    { name = "Guild", fn = function() ToggleGuildFrame() end, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    { name = "Friends", fn = function() ToggleFriendsFrame() end, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
}

local R_ITEM, R_LABEL = 150, 222

local function Stick()
    local st = C_GamePad.GetDeviceMappedState()
    local s = st and st.sticks and st.sticks[ns.db.rightStick]
    if not s then return 0, 0 end
    -- retail invert flips the axes in the pad config, undo it so up is still up here
    local f = ns.stickFlip or { x = 1, y = 1 }
    return (s.x or 0) * f.x, (s.y or 0) * f.y
end

-- degrees clockwise from straight up, y up is positive on the pad
local function Angle(x, y)
    return (math.deg(math.atan2(x, y)) + 360) % 360
end

local function Circle(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(CIRCLE)
    t:SetSize(size, size)
    return t
end

-- shared hub dot that rides the edge toward the stick
local function PointDot(dot, hub, x, y, r)
    local len = math.sqrt(x * x + y * y)
    dot:SetShown(len > 0.2)
    if len > 0.2 then
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", hub, "CENTER", x / len * r, y / len * r)
    end
end

-- select wheel ------------------------------------------------------------------

local wheel
local ws = { pick = nil, active = false, used = false, held = false, t = 0 }

local function BuildWheel()
    wheel = CreateFrame("Frame", "JarStickWheel", UIParent)
    wheel:SetSize(560, 560)
    wheel:SetPoint("CENTER", 0, 30)
    wheel:SetFrameStrata("FULLSCREEN_DIALOG")
    wheel:Hide()
    local bg = Circle(wheel, 2 * R_LABEL + 40)
    bg:SetPoint("CENTER")
    bg:SetVertexColor(0, 0, 0, 0.5)

    wheel.items = {}
    local n = #ITEMS
    for i, it in ipairs(ITEMS) do
        local a = math.rad((i - 1) * 360 / n)
        local f = CreateFrame("Frame", nil, wheel)
        f:SetSize(54, 54)
        f:SetPoint("CENTER", wheel, "CENTER", math.sin(a) * R_ITEM, math.cos(a) * R_ITEM)
        f.disc = Circle(f, 54)
        f.disc:SetPoint("CENTER")
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(34, 34)
        f.icon:SetPoint("CENTER")
        f.icon:SetTexture(it.icon)
        local mask = f:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(f.icon)
        f.icon:AddMaskTexture(mask)
        f.label = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        local lx, ly = math.sin(a) * R_LABEL, math.cos(a) * R_LABEL
        f.label:SetPoint(math.abs(lx) < 30 and "CENTER" or lx > 0 and "LEFT" or "RIGHT", wheel, "CENTER", lx, ly)
        f.label:SetText(it.name)
        f.label:SetShadowOffset(1, -1)
        wheel.items[i] = f
    end

    wheel.hub = CreateFrame("Frame", nil, wheel)
    wheel.hub:SetSize(132, 132)
    wheel.hub:SetPoint("CENTER")
    local ring = Circle(wheel.hub, 132, "BORDER")
    ring:SetPoint("CENTER")
    ring:SetVertexColor(unpack(PALETTE.accent))
    local hub = Circle(wheel.hub, 126, "ARTWORK")
    hub:SetPoint("CENTER")
    hub:SetVertexColor(0.1, 0.1, 0.12, 0.97)
    wheel.name = wheel.hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    wheel.name:SetPoint("CENTER", 0, 8)
    wheel.name:SetWidth(120)
    wheel.hint = wheel.hub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wheel.hint:SetPoint("TOP", wheel.name, "BOTTOM", 0, -4)
    wheel.dot = Circle(wheel.hub, 12, "OVERLAY")
    wheel.dot:SetVertexColor(unpack(PALETTE.accent))
end

local function PaintWheel()
    for i, f in ipairs(wheel.items) do
        local on = i == ws.pick
        f.disc:SetVertexColor(on and 1 or 0.08, on and 0.55 or 0.08, on and 0 or 0.1, on and 0.9 or 0.92)
        f:SetScale(on and 1.2 or 1)
        f.label:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
    end
    local it = ws.pick and ITEMS[ws.pick]
    wheel.name:SetText(it and it.name or "")
    wheel.hint:SetText(it and ("release " .. ns.Glyph("PADBACK")) or (ns.Glyph("PADRSTICK") .. " to pick"))
    wheel:SetAlpha(ws.active and 1 or 0.45)
end

local function WheelUpdate(_, elapsed)
    if not ws.held then return end
    ws.t = ws.t + elapsed
    local x, y = Stick()
    if x * x + y * y > 0.25 then
        -- springing back to center keeps the last pick
        ws.pick = math.floor(Angle(x, y) / (360 / #ITEMS) + 0.5) % #ITEMS + 1
        ws.active = true
    end
    local show = ws.active or (ws.t > 0.3 and not ws.used)
    if show ~= wheel:IsShown() then wheel:SetShown(show) end
    if show then
        PaintWheel()
        PointDot(wheel.dot, wheel.hub, x, y, 60)
    end
end

local function OpenItem(it)
    -- PanelShown in JarStick.lua turns the cursor on for whatever opens now
    ns.wheelOpening = true
    -- if it.fn then it.fn() else RunBinding(it.cmd) end
    it.fn()
    ns.wheelOpening = nil
end

local driverFrame = CreateFrame("Frame")

-- while select is held this eats the right stick so the camera doesnt turn.
-- enabled once out of combat, after that show/hide is fine in combat too.
-- returning true passes a stick on, so the left one still walks
local capture
local function BuildCapture()
    capture = CreateFrame("Frame", "JarStickWheelCapture", UIParent)
    capture:Hide()
    capture:EnableGamePadStick(true)
    capture:SetScript("OnGamePadStick", function(_, stick)
        return stick ~= "Camera"
    end)
end

-- the wheel and the party ring both want it, up while either does
local captureWant = {}
local function SetCapture(who, on)
    captureWant[who] = on or nil
    if capture then capture:SetShown(next(captureWant) ~= nil) end
end

-- party ring: right stick picks the member, not the camera
local function RingCamera(on)
    ns.FreezeCamera(on)
    SetCapture("ring", on)
end

-- the list menu in Menus.lua uses the same items
ns.MenuItems = ITEMS
ns.OpenMenuItem = OpenItem

-- tap Select = the menu (Menus.lua). holding it still pages the face buttons and zooms,
-- so a hold that pressed a slot or a trigger doesnt count as a tap. the wheel is retired
local TAP = 0.35

-- ns.WheelSelect = function(down)
--     if not wheel then BuildWheel() end
--     if down and ns.BookShown and ns.BookShown() then return end
--     if down then
--         ws.pick, ws.active, ws.used, ws.held, ws.t = nil, false, false, true, 0
--         driverFrame:SetScript("OnUpdate", WheelUpdate)
--         SetCapture("wheel", true)
--         return
--     end
--     ws.held = false
--     driverFrame:SetScript("OnUpdate", nil)
--     SetCapture("wheel", false)
--     wheel:Hide()
--     local it = ws.active and ws.pick and ITEMS[ws.pick]
--     if it then OpenItem(it) end
-- end
ns.WheelSelect = function(down)
    -- with the book up, select is just the page you are placing on
    if down and ns.BookShown and ns.BookShown() then return end
    if down then
        ws.used, ws.held, ws.t = false, true, GetTime()
        driverFrame:SetScript("OnUpdate", function()
            if IsShiftKeyDown() or IsControlKeyDown() then ws.used = true end
        end)
        return
    end
    if not ws.held then return end
    ws.held = false
    driverFrame:SetScript("OnUpdate", nil)
    if not ws.used and GetTime() - ws.t < TAP and ns.ToggleSelMenu then ns.ToggleSelMenu() end
end

-- start or a slot press while select is down: not a tap
local function WheelCancel()
    if ws.held then
        ws.active, ws.pick, ws.used = false, nil, true
        if wheel then wheel:Hide() end
    end
end

-- JarStickSelect binds start to this while select is down
local cancelBtn = CreateFrame("Button", "JarStickWheelCancel", UIParent)
cancelBtn:RegisterForClicks("AnyDown")
cancelBtn:SetScript("OnClick", WheelCancel)

-- party ring ----------------------------------------------------------------------
-- R1 + L1, either order. JarStickL1 is the L1 binding: a tap is /targetenemy, but with R1
-- (alt) down it opens the ring instead and letting go of either closes it. The ctl state
-- driver catches R1 coming down second.

local ctl, ringFrame
local members = {}

-- party, or your own group in a raid. 4 = lined up with the R1 d-pad layer
local function Members()
    wipe(members)
    if IsInRaid() then
        local mine
        for i = 1, GetNumGroupMembers() do
            local name, _, sub = GetRaidRosterInfo(i)
            if name and UnitIsUnit("raid" .. i, "player") then mine = sub end
        end
        for i = 1, GetNumGroupMembers() do
            local _, _, sub = GetRaidRosterInfo(i)
            if sub == mine and not UnitIsUnit("raid" .. i, "player") then members[#members + 1] = "raid" .. i end
        end
    else
        for i = 1, 4 do
            if UnitExists("party" .. i) then members[#members + 1] = "party" .. i end
        end
    end
    if #members == 4 and not IsInRaid() then
        members[3], members[4] = members[4], members[3]
    end
    return members
end

local function SliceAngle(i, n)
    return (i - 1) * 360 / n
end

local function NearestSlice(dx, dy)
    local n = #members
    if n == 0 or (dx == 0 and dy == 0) then return nil end
    local a, best, bestD = Angle(dx, dy), nil, 999
    for i = 1, n do
        local d = math.abs((SliceAngle(i, n) - a + 540) % 360 - 180)
        if d < bestD then best, bestD = i, d end
    end
    return best
end

-- the restricted side only knows 8 directions, hand it a lookup
local function ApplyRingMap()
    ns.RunWhenSafe("ringmap", function()
        if not ctl then return end
        Members()
        for dx = -1, 1 do
            for dy = -1, 1 do
                -- the keys come off the flipped axes too
                local f = ns.stickFlip or { x = 1, y = 1 }
                local i = NearestSlice(dx * f.x, dy * f.y)
                -- ctl:SetAttribute("map" .. dx .. "_" .. dy, i and members[i] or "player")
                ctl:SetAttribute("map" .. dx .. "_" .. dy, i and members[i] or nil)
            end
        end
    end)
end

-- geometry --------------------------------------------------------------------------
-- slices are solid quads bent into shape with SetVertexOffset, ~5 degrees each

local R_OUT, R_IN, BAR = 200, 82, 18
local HUB = R_IN - 8
local STEP = 5

local function XY(r, deg)
    local a = math.rad(deg)
    return r * math.sin(a), r * math.cos(a)
end

local function Take(f, layer, sub)
    f.qi = f.qi + 1
    local t = f.quads[f.qi]
    if not t then
        t = f:CreateTexture(nil, layer, nil, sub)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(2, 2)
        t:SetPoint("CENTER")
        f.quads[f.qi] = t
    end
    t:SetDrawLayer(layer, sub)
    t:Show()
    return t
end

local function Reset(f)
    f.qi = 0
    for _, t in ipairs(f.quads) do t:Hide() end
end

-- corners go round: UL, UR, LR, LL. y is up
local function Bend(t, x1, y1, x2, y2, x3, y3, x4, y4)
    t:SetVertexOffset(UPPER_LEFT_VERTEX, x1 + 1, y1 - 1)
    t:SetVertexOffset(UPPER_RIGHT_VERTEX, x2 - 1, y2 - 1)
    t:SetVertexOffset(LOWER_RIGHT_VERTEX, x3 - 1, y3 + 1)
    t:SetVertexOffset(LOWER_LEFT_VERTEX, x4 + 1, y4 + 1)
end

-- ring band r0..r1 between two angles (clockwise from straight up)
local function Band(f, layer, sub, r0, r1, a0, a1, count)
    count = count or math.max(1, math.ceil((a1 - a0) / STEP))
    local list = {}
    for k = 1, count do
        local b0, b1 = a0 + (a1 - a0) * (k - 1) / count, a0 + (a1 - a0) * k / count
        local x1, y1 = XY(r1, b0)
        local x2, y2 = XY(r1, b1)
        local x3, y3 = XY(r0, b1)
        local x4, y4 = XY(r0, b0)
        local t = Take(f, layer, sub)
        Bend(t, x1, y1, x2, y2, x3, y3, x4, y4)
        list[k] = t
    end
    return list
end

-- straight edge from r0 to r1 along one angle
local function Spoke(f, layer, sub, r0, r1, a, w)
    local dx, dy = math.sin(math.rad(a)), math.cos(math.rad(a))
    local px, py = dy * w / 2, -dx * w / 2
    local t = Take(f, layer, sub)
    Bend(t, r1 * dx - px, r1 * dy - py, r1 * dx + px, r1 * dy + py, r0 * dx + px, r0 * dy + py, r0 * dx - px, r0 * dy - py)
    return t
end

local function Paint(list, r, g, b, a)
    for _, t in ipairs(list) do t:SetVertexColor(r, g, b, a) end
end

-- hp arc: health is secret in combat, so every quad gets its own step curve. below its
-- threshold it's clear, above it takes the red/yellow/green of the current health.
-- the curve does the compare engine side and SetVertexColor takes the secret color
local RED, YEL, GRN, CLEAR
local segCurves = {}
local function SegCurve(t)
    local key = math.floor(t * 1000 + 0.5)
    if segCurves[key] then return segCurves[key] end
    if not RED then
        RED, YEL, GRN = CreateColor(1, 0.1, 0.1, 1), CreateColor(1, 0.85, 0.1, 1), CreateColor(0.1, 1, 0.1, 1)
        CLEAR = CreateColor(0, 0, 0, 0)
    end
    local function Col(p) return p < 0.25 and RED or p < 0.6 and YEL or GRN end
    local c = C_CurveUtil.CreateColorCurve()
    c:AddPoint(0, CLEAR)
    if t > 0.002 then c:AddPoint(t - 0.001, CLEAR) end
    c:AddPoint(t, Col(t))
    for _, b in ipairs({ 0.25, 0.6 }) do
        if b > t + 0.002 then
            c:AddPoint(b - 0.001, Col(b - 0.002))
            c:AddPoint(b, Col(b))
        end
    end
    c:AddPoint(1, GRN)
    segCurves[key] = c
    return c
end

local function HPBand(f, r0, r1, a0, a1, count)
    local list = Band(f, "ARTWORK", 1, r0, r1, a0, a1, count)
    for k, t in ipairs(list) do t.curve = SegCurve((k - 0.5) / #list) end
    return list
end

local function PaintHP(list, unit)
    for _, t in ipairs(list) do
        t:SetVertexColor(UnitHealthPercent(unit, true, t.curve):GetRGBA())
    end
end

-- slices ------------------------------------------------------------------------------

local slices, layoutN = {}, nil
local ringPick

local function Slice(i)
    if slices[i] then return slices[i] end
    local s = CreateFrame("Frame", nil, ringFrame)
    s:SetSize(2, 2)
    s:SetPoint("CENTER")
    s.quads, s.qi = {}, 0
    s.role = s:CreateTexture(nil, "OVERLAY", nil, 2)
    s.role:SetSize(20, 20)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.name:SetShadowOffset(1, -1)
    s.name:SetWidth(130)
    s.pct = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.pct:SetShadowOffset(1, -1)
    s.tag = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.tag:SetShadowOffset(1, -1)
    slices[i] = s
    return s
end

local function LayoutSlice(s, i, n)
    Reset(s)
    local step = 360 / n
    local c = SliceAngle(i, n)
    local gap = n > 1 and 1.2 or 0
    local a0, a1 = c - step / 2 + gap, c + step / 2 - gap
    if n == 1 then a0, a1 = 0, 360 end
    s.c = c
    s.base = Band(s, "BACKGROUND", 0, R_IN, R_OUT, a0, a1)
    s.tint = Band(s, "BORDER", 0, R_IN, R_OUT - BAR - 2, a0, a1)
    s.hpbg = Band(s, "ARTWORK", 0, R_OUT - BAR, R_OUT, a0, a1)
    s.hp = HPBand(s, R_OUT - BAR, R_OUT, a0, a1)
    s.edge = Band(s, "OVERLAY", 0, R_OUT, R_OUT + 2, a0, a1)
    for _, t in ipairs(Band(s, "OVERLAY", 0, R_IN - 2, R_IN, a0, a1)) do s.edge[#s.edge + 1] = t end
    if n > 1 then
        s.edge[#s.edge + 1] = Spoke(s, "OVERLAY", 0, R_IN - 2, R_OUT + 2, a0, 2)
        s.edge[#s.edge + 1] = Spoke(s, "OVERLAY", 0, R_IN - 2, R_OUT + 2, a1, 2)
    end
    Paint(s.base, 0.055, 0.055, 0.07, 0.92)
    Paint(s.hpbg, 0, 0, 0, 0.7)
    local tx, ty = XY((R_IN + R_OUT - BAR) / 2, c)
    s.role:ClearAllPoints()
    s.role:SetPoint("CENTER", s, "CENTER", tx, ty + 26)
    s.name:ClearAllPoints()
    s.name:SetPoint("CENTER", s, "CENTER", tx, ty + 4)
    s.pct:ClearAllPoints()
    s.pct:SetPoint("CENTER", s, "CENTER", tx, ty - 15)
    s.tag:ClearAllPoints()
    s.tag:SetPoint("CENTER", s, "CENTER", tx, ty - 31)
end

local function ClassRGB(unit)
    local _, cls = UnitClass(unit)
    local col = cls and not issecretvalue(cls) and C_ClassColor.GetClassColor(cls)
    if col then return col:GetRGB() end
    return 0.6, 0.6, 0.6
end

local function PaintSlice(s, unit, picked)
    local r, g, b = ClassRGB(unit)
    local dead = UnitIsDeadOrGhost(unit)
    dead = not issecretvalue(dead) and dead
    if dead then r, g, b = 0.4, 0.4, 0.4 end
    Paint(s.tint, r, g, b, picked and 0.5 or 0.28)
    PaintHP(s.hp, unit)
    local dispel = ns.DispelColor(unit)
    if picked then
        Paint(s.edge, 1, 0.82, 0, 1)
    elseif dispel then
        Paint(s.edge, dispel[1], dispel[2], dispel[3], 1)
    else
        Paint(s.edge, 0.23, 0.23, 0.26, 1)
    end
    s.name:SetText((UnitName(unit)))
    s.name:SetTextColor(r, g, b)
    s.pct:SetFormattedText("%.0f%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))
    local role = UnitGroupRolesAssigned(unit)
    local roleOK = not issecretvalue(role) and (role == "TANK" or role == "HEALER" or role == "DAMAGER")
    s.role:SetShown(roleOK)
    if roleOK then s.role:SetAtlas(GetIconForRole(role)) end
    -- out of range fades. a secret answer leaves it lit
    local inRange, checked = UnitInRange(unit)
    local far = not issecretvalue(checked) and not issecretvalue(inRange) and checked and not inRange
    s:SetAlpha(far and 0.45 or 1)
    if dead then
        s.tag:SetText("|cffaaaaaaDEAD|r")
    elseif dispel then
        s.tag:SetText("DISPEL")
        s.tag:SetTextColor(dispel[1], dispel[2], dispel[3])
    elseif far then
        s.tag:SetText("|cffaaaaaaOUT OF RANGE|r")
    else
        s.tag:SetText("")
    end
    -- picked slice pops out a bit
    local px, py = XY(picked and #members > 1 and 12 or 0, s.c)
    s:ClearAllPoints()
    s:SetPoint("CENTER", ringFrame, "CENTER", px, py)
end

local function PaintHub()
    local hub = ringFrame.hub
    PaintHP(hub.hp, "player")
    local on = ringPick == nil
    -- Paint(hub.edge, on and 1 or 0.23, on and 0.82 or 0.23, on and 0 or 0.26, 1)
    Paint(hub.edge, 0.23, 0.23, 0.26, 1)
    local r, g, b = ClassRGB("player")
    hub.name:SetText((UnitName("player")))
    hub.name:SetTextColor(r, g, b)
    hub.pct:SetFormattedText("%.0f%%", UnitHealthPercent("player", false, CurveConstants.ScaleTo100))
    hub.hint:SetText(on and "point at someone" or "targeted")
end

local function PaintRing()
    local n = #members
    if n ~= layoutN then
        layoutN = n
        for i = 1, math.max(n, #slices) do
            local s = Slice(i)
            if i <= n then LayoutSlice(s, i, n) end
        end
    end
    for i, s in ipairs(slices) do
        s:SetShown(i <= n)
        if i <= n then PaintSlice(s, members[i], ringPick == i) end
    end
    PaintHub()
end

local lastPick, tick = false, 0
local function RingUpdate(_, elapsed)
    local x, y = Stick()
    if ctl and ctl:GetAttribute("open") == 1 then
        -- show whoever the secure side actually targeted
        local pick = ctl:GetAttribute("pick")
        ringPick = nil
        for i, u in ipairs(members) do
            if u == pick then ringPick = i end
        end
    else
        -- /js ring preview, same 8-way rule as the secure side
        local dx = x > 0.5 and 1 or x < -0.5 and -1 or 0
        local dy = y > 0.5 and 1 or y < -0.5 and -1 or 0
        ringPick = NearestSlice(dx, dy)
    end
    PointDot(ringFrame.dot, ringFrame.hub, x, y, HUB - 4)
    tick = tick + elapsed
    if tick > 0.1 or ringPick ~= lastPick then
        tick, lastPick = 0, ringPick
        PaintRing()
    end
end

local function ShowRing()
    Members()
    ringPick, lastPick = nil, false
    ringFrame:Show()
    PaintRing()
end

local function BuildRingFrame()
    ringFrame = CreateFrame("Frame", "JarStickRingFrame", UIParent)
    ringFrame:SetSize(560, 560)
    ringFrame:SetPoint("CENTER", 0, 30)
    ringFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ringFrame:Hide()
    local bg = Circle(ringFrame, 2 * (R_OUT + 34))
    bg:SetPoint("CENTER")
    bg:SetVertexColor(0, 0, 0, 0.45)

    local hub = CreateFrame("Frame", nil, ringFrame)
    hub:SetSize(2, 2)
    hub:SetPoint("CENTER")
    hub:SetFrameLevel(ringFrame:GetFrameLevel() + 5)
    hub.quads, hub.qi = {}, 0
    local disc = Circle(hub, 2 * HUB)
    disc:SetPoint("CENTER")
    disc:SetVertexColor(0.08, 0.08, 0.1, 0.97)
    hub.hp = HPBand(hub, HUB, HUB + 6, 0, 360, 60)
    hub.edge = Band(hub, "OVERLAY", 0, HUB + 6, HUB + 9, 0, 360, 60)
    hub.name = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hub.name:SetPoint("CENTER", 0, 14)
    hub.pct = hub:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hub.pct:SetPoint("CENTER", 0, -4)
    hub.hint = hub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hub.hint:SetPoint("CENTER", 0, -22)
    ringFrame.hub = hub
    ringFrame.dot = Circle(hub, 12, "OVERLAY")
    ringFrame.dot:SetVertexColor(unpack(PALETTE.accent))
    ringFrame:SetScript("OnUpdate", RingUpdate)
end

-- R1 held: party labels on the dpad only show after a short hold so taps dont flash them.
-- the bindings swap right away though, secure code has no clock to wait with
local R1_HOLD = 0.4
local holdTimer

local function R1Held(on)
    if holdTimer then holdTimer:Cancel() end
    holdTimer = nil
    if on then
        holdTimer = C_Timer.NewTimer(R1_HOLD, function()
            holdTimer = nil
            ns.r1Layer = true
            if ns.UpdateOverlay then ns.UpdateOverlay() end
        end)
    else
        ns.r1Layer = false
        if ns.UpdateOverlay then ns.UpdateOverlay() end
    end
end

-- secure side ---------------------------------------------------------------------------

local function BuildRing()
    if ctl then return end
    BuildRingFrame()

    ctl = CreateFrame("Frame", "JarStickRingCtl", UIParent, "SecureHandlerStateTemplate")
    ctl:SetAttribute("open", 0)
    ctl:SetAttribute("openring", [[
        if self:GetAttribute("open") == 1 then return end
        for _, d in ipairs(newtable("UP", "DOWN", "LEFT", "RIGHT")) do
            self:SetAttribute("d" .. d, 0)
            self:SetBindingClick(true, "ALT-PADRSTICK" .. d, "JarStickRingDir", d)
            self:SetBindingClick(true, "PADRSTICK" .. d, "JarStickRingDir", d)
        end
        self:SetAttribute("open", 1)
        self:SetAttribute("r1used", 1)
    ]])
    ctl:SetAttribute("closering", [[
        self:ClearBindings()
        for _, d in ipairs(newtable("UP", "DOWN", "LEFT", "RIGHT")) do self:SetAttribute("d" .. d, 0) end
        self:SetAttribute("pick", nil)
        self:SetAttribute("open", 0)
    ]])
    -- R1 coming down while L1 is held opens it, R1 going up closes it.
    -- state drivers hand over numbers not strings
    ctl:SetAttribute("_onstate-alt", [[
        if newstate == 1 then
            if self:GetAttribute("l1") == 1 then self:RunAttribute("openring") end
        elseif self:GetAttribute("open") == 1 then
            self:RunAttribute("closering")
        end
    ]])
    -- RegisterStateDriver(ctl, "alt", "[mod:alt] 1; 0")
    -- JarStickR1 sets state-alt itself now, see below

    -- stick directions target right away, so whoever is lit up is your target.
    -- stick back to center keeps the last pick
    local dir = CreateFrame("Button", "JarStickRingDir", UIParent, "SecureActionButtonTemplate")
    dir:RegisterForClicks("AnyDown", "AnyUp")
    dir:SetAttribute("type", "target")
    SecureHandlerWrapScript(dir, "OnClick", ctl, [[
        owner:SetAttribute("d" .. button, down and 1 or 0)
        if owner:GetAttribute("open") ~= 1 then return false end
        local x = (owner:GetAttribute("dRIGHT") or 0) - (owner:GetAttribute("dLEFT") or 0)
        local y = (owner:GetAttribute("dUP") or 0) - (owner:GetAttribute("dDOWN") or 0)
        local unit = owner:GetAttribute("map" .. x .. "_" .. y)
        if not unit or unit == owner:GetAttribute("pick") then return false end
        owner:SetAttribute("pick", unit)
        self:SetAttribute("unit", unit)
        -- fire on whichever half of the press this is
        self:SetAttribute("useOnKeyDown", down)
        return "LeftButton"
    ]])

    -- L1 itself: tab target on a plain press, ring with R1
    local l1 = CreateFrame("Button", "JarStickL1", UIParent, "SecureActionButtonTemplate")
    l1:RegisterForClicks("AnyDown", "AnyUp")
    l1:SetAttribute("type", "macro")
    l1:SetAttribute("macrotext", "/targetenemy")
    l1:SetAttribute("useOnKeyDown", true)
    SecureHandlerWrapScript(l1, "OnClick", ctl, [[
        if down then
            owner:SetAttribute("l1", 1)
            -- IsAltKeyDown is false during a pad click even with R1 held, the driver knows better
            if IsAltKeyDown() or owner:GetAttribute("state-alt") == 1 then
                owner:RunAttribute("openring")
                return false
            end
            return
        end
        owner:SetAttribute("l1", 0)
        if owner:GetAttribute("open") == 1 then owner:RunAttribute("closering") end
        return false
    ]])

    -- R1 is a plain binding, blizzards alt emulation kept dropping out on it.
    -- down: dpad targets party 2-5 and L1 opens the ring. up: back to normal,
    -- and /targetfriend if nothing got used while it was held
    local party = CreateFrame("Button", "JarStickR1Party", UIParent, "SecureActionButtonTemplate")
    party:RegisterForClicks("AnyDown")
    party:SetAttribute("type", "target")
    party:SetAttribute("useOnKeyDown", true)
    SecureHandlerWrapScript(party, "OnClick", ctl, [[
        owner:SetAttribute("r1used", 1)
        self:SetAttribute("unit", button)
        return "LeftButton"
    ]])

    local r1 = CreateFrame("Button", "JarStickR1", UIParent, "SecureActionButtonTemplate")
    r1:RegisterForClicks("AnyDown", "AnyUp")
    r1:SetAttribute("type", "macro")
    r1:SetAttribute("macrotext", "/targetfriend")
    r1:SetAttribute("useOnKeyDown", false)
    SecureHandlerWrapScript(r1, "OnClick", ctl, [[
        if down then
            owner:SetAttribute("r1used", 0)
            -- plain keys only, L2/R2 + dpad keep switching bars
            self:SetBindingClick(true, "PADDUP", "JarStickR1Party", "party1")
            self:SetBindingClick(true, "PADDRIGHT", "JarStickR1Party", "party2")
            self:SetBindingClick(true, "PADDLEFT", "JarStickR1Party", "party3")
            self:SetBindingClick(true, "PADDDOWN", "JarStickR1Party", "party4")
            owner:SetAttribute("state-alt", 1)
            return false
        end
        self:ClearBindings()
        owner:SetAttribute("state-alt", 0)
        if owner:GetAttribute("r1used") == 1 then return false end
    ]])

    -- debug: did the L1 click land, and does the game see R1 as alt
    l1:HookScript("OnClick", function(_, button, down)
        if ns.debug or ns.padWatch then
            ns.Log(("L1 click %s %s  alt=%s  open=%s"):format(tostring(button), down and "down" or "up",
                tostring(IsAltKeyDown()), tostring(ctl:GetAttribute("open"))))
        end
    end)

    ctl:HookScript("OnAttributeChanged", function(_, name, value)
        if (ns.debug or ns.padWatch) and (name == "state-alt" or name == "l1" or name == "pick") then
            ns.Log(("ring ctl %s=%s"):format(name, tostring(value)))
        end
        if name == "state-alt" then R1Held(value == 1) end
        if name ~= "open" then return end
        if ns.debug or ns.padWatch then
            ns.Log(("ring %s  alt=%s  members=%d"):format(value == 1 and "open" or "closed", tostring(IsAltKeyDown()), #Members()))
        end
        if value == 1 then
            ShowRing()
            RingCamera(true)
        else
            ringFrame:Hide()
            RingCamera(false)
        end
    end)
    ApplyRingMap()
    if ns.debug then ns.Log("party ring built") end
end
ns.InitRing = BuildRing
ns.ApplyRingMap = ApplyRingMap

-- run the open/close snippets straight, out of combat. proves they work without the pad
ns.RingSelfTest = function()
    if not ctl then return "not built" end
    if InCombatLockdown() then return "skipped in combat" end
    local ok, err = pcall(SecureHandlerExecute, ctl, [[self:RunAttribute("openring")]])
    local opened = ctl:GetAttribute("open") == 1
    local ok2, err2 = pcall(SecureHandlerExecute, ctl, [[self:RunAttribute("closering")]])
    if not ok then return "openring error: " .. tostring(err) end
    if not ok2 then return "closering error: " .. tostring(err2) end
    return ("open=%s closed=%s"):format(tostring(opened), tostring(ctl:GetAttribute("open") == 0))
end

-- /js ring: just the drawing for 4 seconds, no binding or targeting involved
ns.TestRing = function()
    if not ringFrame then
        ns.Print("party ring not built yet (it builds with the clusters, out of combat)")
        return
    end
    ShowRing()
    RingCamera(true)
    C_Timer.After(4, function()
        if not ctl or ctl:GetAttribute("open") ~= 1 then
            ringFrame:Hide()
            RingCamera(false)
        end
    end)
    ns.Print(("ring test: %d member(s), PADLSHOULDER -> %s, ALT-PADLSHOULDER -> %s"):format(#members,
        tostring(GetBindingAction("PADLSHOULDER", true)), tostring(GetBindingAction("ALT-PADLSHOULDER", true))))
end

-- init ----------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.RunWhenSafe("wheelcapture", BuildCapture)
        -- a slot pressed while select is held means you are using the page, no wheel
        for _, b in ipairs(ns.buttons or {}) do
            b:HookScript("OnClick", function()
                if ws.held then WheelCancel() end
            end)
        end
    end
    ApplyRingMap()
end)

end
