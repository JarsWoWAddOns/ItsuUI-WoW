-- Itsu:UI: class resource by spec (combo points, holy power, chi, runes, essence...).
-- retail version, from JarsResourceCounter. brewmaster gets a stagger bar

local _, ns = ...

ns.RegisterModule("rc", "Class Resource", function()

local DB = ns.db.rc
local DEFAULTS = {
    displayMode   = "SEGMENTS",
    segmentSize   = 22,
    segmentGap    = 3,
    numericSize   = 64,
    position      = { point = "CENTER", x = 0, y = -175 },
    staggerWidth  = 200,
    staggerHeight = 18,
}
for k, v in pairs(DEFAULTS) do
    if DB[k] == nil then
        DB[k] = type(v) == "table" and CopyTable(v) or v
    end
end

local PANEL = "Class Resource"
-- anything bigger than this (maelstrom, fury, insanity, astral) is a number, not boxes
local DISCRETE_MAX = 12

local COL_LOW   = { 0.20, 0.85, 0.20 }
local COL_MID   = { 1.00, 0.78, 0.10 }
local COL_HIGH  = { 1.00, 0.22, 0.22 }
local COL_EMPTY = { 0.15, 0.15, 0.18 }

local function SegmentColor(i, max)
    local frac = i / max
    if frac <= 0.40 then return COL_LOW end
    if frac <= 0.70 then return COL_MID end
    return COL_HIGH
end

local function StaggerColor(pct)
    if pct < 0.30 then return COL_LOW end
    if pct < 0.60 then return COL_MID end
    return COL_HIGH
end

local function AbbrevNum(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n))
end

-- same thresholds as SegmentColor as a step curve, for power that goes secret in combat
local secretCurve = C_CurveUtil.CreateColorCurve()
secretCurve:SetType(Enum.LuaCurveType.Step)
secretCurve:AddPoint(0, CreateColor(0.4, 0.4, 0.4, 1))
secretCurve:AddPoint(0.0001, CreateColor(0.20, 0.85, 0.20, 1))
secretCurve:AddPoint(0.4001, CreateColor(1.00, 0.78, 0.10, 1))
secretCurve:AddPoint(0.7001, CreateColor(1.00, 0.22, 0.22, 1))

-- powerType nil = nothing to show for that spec. warriors and hunters have nothing
local SPEC_RESOURCE = {
    [268] = { name = "Brewmaster", powerType = "STAGGER" },
    [269] = { name = "Windwalker", powerType = Enum.PowerType.Chi },
    [259] = { name = "Assassination", powerType = Enum.PowerType.ComboPoints },
    [260] = { name = "Outlaw", powerType = Enum.PowerType.ComboPoints },
    [261] = { name = "Subtlety", powerType = Enum.PowerType.ComboPoints },
    [102] = { name = "Balance", powerType = Enum.PowerType.LunarPower },
    [103] = { name = "Feral", powerType = Enum.PowerType.ComboPoints },
    [65] = { name = "Holy", powerType = Enum.PowerType.HolyPower },
    [66] = { name = "Protection", powerType = Enum.PowerType.HolyPower },
    [70] = { name = "Retribution", powerType = Enum.PowerType.HolyPower },
    [265] = { name = "Affliction", powerType = Enum.PowerType.SoulShards },
    [266] = { name = "Demonology", powerType = Enum.PowerType.SoulShards },
    [267] = { name = "Destruction", powerType = Enum.PowerType.SoulShards },
    [62] = { name = "Arcane", powerType = Enum.PowerType.ArcaneCharges },
    [250] = { name = "Blood", powerType = Enum.PowerType.Runes },
    [251] = { name = "Frost DK", powerType = Enum.PowerType.Runes },
    [252] = { name = "Unholy", powerType = Enum.PowerType.Runes },
    [1467] = { name = "Devastation", powerType = Enum.PowerType.Essence },
    [1473] = { name = "Augmentation", powerType = Enum.PowerType.Essence },
    [262] = { name = "Elemental", powerType = Enum.PowerType.Maelstrom },
    [263] = { name = "Enhancement", powerType = Enum.PowerType.Maelstrom },
    [577] = { name = "Havoc", powerType = Enum.PowerType.Fury },
    [258] = { name = "Shadow", powerType = Enum.PowerType.Insanity },
}

local current -- SPEC_RESOURCE entry for the active spec, or nil

local function RefreshSpec()
    local idx = C_SpecializationInfo.GetSpecialization()
    local specID = idx and C_SpecializationInfo.GetSpecializationInfo(idx)
    current = specID and SPEC_RESOURCE[specID]
end

local mainFrame, numericText, dragBorder
local staggerTrack, staggerFill, staggerText
local segments = {}
local numSegs, shownMode = 0, nil

local function ClearWidgets()
    for _, s in ipairs(segments) do s:Hide() end
    numSegs = 0
    if numericText then numericText:Hide() end
    if staggerTrack then
        staggerTrack:Hide()
        staggerFill:Hide()
        staggerText:Hide()
    end
    shownMode = nil
end

local function BuildSegments(n)
    ClearWidgets()
    local sz, gap = DB.segmentSize, DB.segmentGap
    mainFrame:SetSize(n * sz + (n - 1) * gap, sz)
    for i = 1, n do
        local seg = segments[i]
        if not seg then
            seg = mainFrame:CreateTexture(nil, "ARTWORK")
            segments[i] = seg
        end
        seg:ClearAllPoints()
        seg:SetSize(sz, sz)
        seg:SetPoint("LEFT", mainFrame, "LEFT", (i - 1) * (sz + gap), 0)
        seg:SetTexture(ns.GetTexture())
        seg:SetVertexColor(unpack(COL_EMPTY))
        seg:Show()
    end
    numSegs = n
    shownMode = "SEG"
end

local function NumericText(sz)
    if not numericText then
        numericText = mainFrame:CreateFontString(nil, "OVERLAY")
        numericText:SetPoint("CENTER")
    end
    numericText:SetFont(ns.GetFont(), sz, "OUTLINE")
    numericText:Show()
    return numericText
end

local function BuildNumeric()
    ClearWidgets()
    local sz = DB.numericSize
    mainFrame:SetSize(sz * 1.4, sz * 1.4)
    NumericText(sz):SetText("0")
    shownMode = "NUM"
end

local function BuildStagger()
    ClearWidgets()
    local w, h = DB.staggerWidth, DB.staggerHeight
    mainFrame:SetSize(w, h + 14)
    if not staggerTrack then
        staggerTrack = mainFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        staggerTrack:SetPoint("TOPLEFT", 0, -14)
        staggerFill = mainFrame:CreateTexture(nil, "ARTWORK")
        staggerFill:SetPoint("TOPLEFT", staggerTrack, "TOPLEFT")
        staggerText = mainFrame:CreateFontString(nil, "OVERLAY")
        staggerText:SetPoint("BOTTOM", staggerTrack, "TOP", 0, 2)
        staggerText:SetTextColor(0.9, 0.9, 0.9, 1)
    end
    staggerTrack:SetSize(w, h)
    staggerTrack:SetTexture(ns.GetTexture())
    staggerTrack:SetVertexColor(unpack(COL_EMPTY))
    staggerFill:SetSize(1, h)
    staggerFill:SetTexture(ns.GetTexture())
    staggerFill:SetVertexColor(unpack(COL_LOW))
    staggerText:SetFont(ns.GetFont(), 11, "OUTLINE")
    staggerText:SetText("Stagger 0%")
    staggerTrack:Show()
    staggerFill:Show()
    staggerText:Show()
    shownMode = "STAG"
end

local function BuildStaggerNumeric()
    ClearWidgets()
    local sz = math.max(math.floor(DB.numericSize * 0.55), 16)
    mainFrame:SetSize(math.max(sz * 7, 160), sz * 2)
    NumericText(sz):SetText("0 / 0")
    shownMode = "NUM"
end

local function RebuildDisplay()
    if not mainFrame then return end
    if not (current and current.powerType) then
        ClearWidgets()
        mainFrame:Hide()
        return
    end
    if current.powerType == "STAGGER" then
        if DB.displayMode == "NUMERIC" then BuildStaggerNumeric() else BuildStagger() end
        mainFrame:Show()
        return
    end
    -- the player's own max is never secret
    local max = UnitPowerMax("player", current.powerType)
    if max <= 0 then
        ClearWidgets()
        mainFrame:Hide()
        return
    end
    if DB.displayMode == "SEGMENTS" and max <= DISCRETE_MAX then
        BuildSegments(max)
    else
        BuildNumeric()
    end
    mainFrame:Show()
end

local function UpdateStagger()
    local amount, maxHP = UnitStagger("player") or 0, UnitHealthMax("player")
    if issecretvalue(amount) then
        if DB.displayMode == "NUMERIC" then
            numericText:SetFormattedText("%s / %s", AbbreviateNumbers(amount), AbbreviateNumbers(maxHP))
        elseif staggerText then
            staggerText:SetFormattedText("Stagger  %s", AbbreviateNumbers(amount))
        end
        return
    end
    if maxHP == 0 then maxHP = 1 end
    local pct = math.min(amount / maxHP, 1)
    local c = StaggerColor(pct)
    if DB.displayMode == "NUMERIC" then
        numericText:SetTextColor(c[1], c[2], c[3], 1)
        numericText:SetText(AbbrevNum(amount) .. " / " .. AbbrevNum(maxHP))
    elseif staggerFill then
        staggerFill:SetWidth(math.max(DB.staggerWidth * pct, 1))
        staggerFill:SetVertexColor(c[1], c[2], c[3])
        staggerText:SetText(string.format("Stagger  %.1f%%", pct * 100))
    end
end

local function UpdateDisplay()
    if not (mainFrame and current and current.powerType) then return end
    if current.powerType == "STAGGER" then
        if mainFrame:IsShown() then UpdateStagger() end
        return
    end

    local pt = current.powerType
    local cur, max = UnitPower("player", pt), UnitPowerMax("player", pt)
    if max <= 0 then
        mainFrame:Hide()
        return
    end
    local useSegments = DB.displayMode == "SEGMENTS" and max <= DISCRETE_MAX
    if (useSegments and (shownMode ~= "SEG" or max ~= numSegs)) or (not useSegments and shownMode ~= "NUM") then
        RebuildDisplay()
    end
    mainFrame:Show()

    -- segments are only for the never-secret ones (combo, holy power, chi...)
    if useSegments then
        if issecretvalue(cur) then return end
        for i = 1, numSegs do
            segments[i]:SetVertexColor(unpack(i <= cur and SegmentColor(i, max) or COL_EMPTY))
        end
    elseif issecretvalue(cur) then
        -- astral, maelstrom, fury, insanity go secret in combat, color comes off the curve
        numericText:SetTextColor(UnitPowerPercent("player", pt, false, secretCurve):GetRGBA())
        numericText:SetFormattedText("%d", cur)
    else
        local c = cur > 0 and SegmentColor(cur, max) or { 0.4, 0.4, 0.4 }
        numericText:SetTextColor(c[1], c[2], c[3], 1)
        numericText:SetText(tostring(cur))
    end
end

local function ApplyPosition()
    local pos = DB.position
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

local function ApplyShared()
    if not mainFrame then return end
    local unlocked = ns.db.general.unlocked
    mainFrame.bg:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    mainFrame:EnableMouse(unlocked)
    dragBorder:SetShown(unlocked)
    RebuildDisplay()
    UpdateDisplay()
end
ns.OnShared(ApplyShared)

local function CreateMainFrame()
    mainFrame = CreateFrame("Frame", "JarsResourceCounterFrame", UIParent)
    mainFrame:SetSize(100, 30)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:Hide()

    mainFrame.bg = mainFrame:CreateTexture(nil, "BACKGROUND")
    mainFrame.bg:SetAllPoints()

    dragBorder = mainFrame:CreateTexture(nil, "OVERLAY")
    dragBorder:SetAllPoints()
    dragBorder:SetColorTexture(1, 0.85, 0, 0.5)

    ApplyPosition()

    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then self:StartMoving() end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        DB.position.point, DB.position.x, DB.position.y = point, x, y
        ns.RefreshPanel(PANEL)
    end)
end

local function FullRefresh()
    RefreshSpec()
    RebuildDisplay()
    UpdateDisplay()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
-- stagger's aura ticks with it, the payload is secret in combat, it's only a ping
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CreateMainFrame()
        ApplyShared()
    elseif event == "PLAYER_ENTERING_WORLD" then
        FullRefresh()
        -- power isnt always ready at zone in
        C_Timer.After(1.5, FullRefresh)
    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        -- the spec / form api catches up a moment later
        C_Timer.After(0.1, FullRefresh)
    elseif event == "UNIT_HEALTH" or event == "UNIT_AURA" then
        if current and current.powerType == "STAGGER" then UpdateDisplay() end
    else
        UpdateDisplay()
    end
end)

ns.RegisterPanel(60, PANEL, function(b)
    b:Text(function()
        if not current then return "This spec has no class resource to show." end
        return "Showing: " .. current.name
    end)
    b:Header("Display")
    b:Toggle("Mode", { { "Segments", "SEGMENTS" }, { "Number", "NUMERIC" } },
        function() return DB.displayMode end,
        function(v) DB.displayMode = v; RebuildDisplay(); UpdateDisplay() end)
    b:Note("Big pools (maelstrom, fury, insanity, astral power) always show as a number. Brewmaster gets a stagger bar.")
    b:Slider("Segment Size", 10, 40, 1,
        function() return DB.segmentSize end,
        function(v) DB.segmentSize = v; RebuildDisplay(); UpdateDisplay() end)
    b:Slider("Segment Gap", 0, 12, 1,
        function() return DB.segmentGap end,
        function(v) DB.segmentGap = v; RebuildDisplay(); UpdateDisplay() end)
    b:Slider("Number Font Size", 20, 120, 2,
        function() return DB.numericSize end,
        function(v) DB.numericSize = v; RebuildDisplay(); UpdateDisplay() end)
    b:Slider("Stagger Bar Width", 80, 400, 2,
        function() return DB.staggerWidth end,
        function(v) DB.staggerWidth = v; RebuildDisplay(); UpdateDisplay() end)
    b:Slider("Stagger Bar Height", 8, 40, 1,
        function() return DB.staggerHeight end,
        function(v) DB.staggerHeight = v; RebuildDisplay(); UpdateDisplay() end)

    b:Header("Position")
    b:Text("Turn on Unlock Frames in General to drag it.")
    b:Slider("Left / Right", -1000, 1000, 1,
        function() return DB.position.x end,
        function(v) DB.position.x = v; if mainFrame then ApplyPosition() end end)
    b:Slider("Up / Down", -600, 600, 1,
        function() return DB.position.y end,
        function(v) DB.position.y = v; if mainFrame then ApplyPosition() end end)
    b:Buttons({ { "Reset Position", function()
        DB.position.point, DB.position.x, DB.position.y = "CENTER", 0, -175
        if mainFrame then ApplyPosition() end
        ns.RefreshPanel(PANEL)
    end } })
end)

SLASH_JARSRESOURCECOUNTER1 = "/jrc"
SlashCmdList["JARSRESOURCECOUNTER"] = function() ns.OpenConfig(PANEL) end

end)
