-- Itsu:UI: simple XP bar with rested overlay, replaces blizz's status bars

local _, ns = ...

ns.RegisterModule("xp", "XP Bar", function()

local DB = ns.db.xp
local DEFAULTS = {
    width = 600,
    height = 12,
    x = 0,
    y = 24,
    color = "purple",
    bgAlpha = 0.5,
    showRested = true,
    showText = true,
    textOnHover = false,
    textMode = "both",
    fontSize = 10,
    hideAtMax = true,
    hideBlizzard = true,
}
for k, v in pairs(DEFAULTS) do
    if DB[k] == nil then DB[k] = v end
end

local COLORS = {
    purple = { 0.58, 0.0, 0.55 },
    blue   = { 0.0, 0.39, 0.88 },
    green  = { 0.2, 0.8, 0.2 },
    gold   = { 1.0, 0.75, 0.1 },
    orange = { 1.0, 0.55, 0.0 },
}

local bar, restBar, bg, text
local hovering = false

local function GetColor()
    if DB.color == "class" then
        local _, class = UnitClass("player")
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return unpack(COLORS[DB.color] or COLORS.purple)
end

local function BuildText(cur, max, rested)
    local pct = math.floor(cur / max * 100)
    local s
    if DB.textMode == "percent" then
        s = pct .. "%"
    elseif DB.textMode == "numbers" then
        s = BreakUpLargeNumbers(cur) .. " / " .. BreakUpLargeNumbers(max)
    else
        s = BreakUpLargeNumbers(cur) .. " / " .. BreakUpLargeNumbers(max) .. "  (" .. pct .. "%)"
    end
    if rested > 0 then
        s = s .. "  +" .. math.floor(rested / max * 100) .. "% rested"
    end
    return s
end

local function Update()
    if not bar then return end
    if DB.hideAtMax and not GameRulesUtil.CanShowExperienceBar() then
        bar:Hide()
        return
    end
    bar:Show()

    local cur, max = UnitXP("player"), math.max(UnitXPMax("player"), 1)
    local rested = GetXPExhaustion() or 0

    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    restBar:SetMinMaxValues(0, max)
    restBar:SetValue(math.min(cur + rested, max))
    restBar:SetShown(DB.showRested and rested > 0)

    text:SetText(BuildText(cur, max, rested))
    text:SetShown(DB.showText and (not DB.textOnHover or hovering))
end

local function ApplyLook()
    if not bar then return end
    local texture = ns.GetTexture()
    local r, g, b = GetColor()
    local unlocked = ns.db.general.unlocked

    bar:SetSize(DB.width, DB.height)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", DB.x, DB.y)
    bar:SetStatusBarTexture(texture)
    bar:SetStatusBarColor(r, g, b)
    restBar:SetStatusBarTexture(texture)
    restBar:SetStatusBarColor(r, g, b, 0.35)
    bg:SetColorTexture(0, 0, 0, DB.bgAlpha)
    text:SetFont(ns.GetFont(), DB.fontSize, "OUTLINE")

    -- clicks go thru to the world unless the bar needs the mouse
    bar:EnableMouse(unlocked or DB.textOnHover)
    Update()
end
ns.OnShared(ApplyLook)

local function CreateBar()
    bar = CreateFrame("StatusBar", "JarForeverXPBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- measure back from bottom center so it stays put at other resolutions
        local cx = self:GetCenter()
        DB.x = math.floor(cx - UIParent:GetWidth() / 2 + 0.5)
        DB.y = math.floor(self:GetBottom() + 0.5)
        ApplyLook()
        ns.RefreshPanel("XP Bar")
    end)
    bar:SetScript("OnEnter", function()
        hovering = true
        Update()
    end)
    bar:SetScript("OnLeave", function()
        hovering = false
        Update()
    end)

    bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)

    restBar = CreateFrame("StatusBar", nil, bar)
    restBar:SetAllPoints()
    restBar:SetFrameLevel(bar:GetFrameLevel())
    restBar:EnableMouse(false)

    -- on its own frame so the text sits over both bars
    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    text = textFrame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")

    ApplyLook()
end

-- also takes rep + honor bars with it, it all lives in this one frame
local function HideBlizzardBars()
    if not DB.hideBlizzard then return end
    ns.RunWhenSafe("xpBlizzard", function()
        local hider = CreateFrame("Frame")
        hider:Hide()
        StatusTrackingBarManager:UnregisterAllEvents()
        StatusTrackingBarManager:SetParent(hider)
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEVEL_CHANGED")
eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
eventFrame:RegisterEvent("ENABLE_XP_GAIN")
eventFrame:RegisterEvent("DISABLE_XP_GAIN")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        CreateBar()
        HideBlizzardBars()
    else
        Update()
    end
end)

ns.RegisterPanel(62, "XP Bar", function(b)
    local function Look(key)
        return function() return DB[key] end,
            function(v) DB[key] = v; ApplyLook() end
    end

    b:Header("Size + Position")
    b:Slider("Width", 100, 1600, 10, Look("width"))
    b:Slider("Height", 4, 40, 1, Look("height"))
    b:Slider("Left / Right", -1000, 1000, 1, Look("x"))
    b:Slider("Up From Bottom", 0, 1200, 1, Look("y"))
    b:Text("Or turn on Unlock Frames in General and drag it.")

    b:Header("Look")
    b:Cycle("Color", {
        { "Purple", "purple" }, { "Blue", "blue" }, { "Green", "green" },
        { "Gold", "gold" }, { "Orange", "orange" }, { "Class Color", "class" },
    }, Look("color"))
    local getBg, setBg = Look("bgAlpha")
    b:Slider("Background Opacity", 0, 1, 0.05, getBg, setBg,
        function(v) return string.format("%.0f%%", v * 100) end)
    b:Check("Show rested XP", Look("showRested"))

    b:Header("Text")
    b:Check("Show text", Look("showText"))
    b:Check("Only show text when moused over", Look("textOnHover"))
    b:Toggle("Text Shows", { { "Both", "both" }, { "Numbers", "numbers" }, { "Percent", "percent" } }, Look("textMode"))
    b:Slider("Font Size", 8, 24, 1, Look("fontSize"))

    b:Header("Behavior")
    b:Check("Hide at max level", Look("hideAtMax"))
    b:Check("Hide Blizzard's XP + reputation bars  (needs a /reload)",
        function() return DB.hideBlizzard end,
        function(v) DB.hideBlizzard = v end)

    b:Spacer(8)
    b:Buttons({ { "Reset to Defaults", function()
        for k, v in pairs(DEFAULTS) do DB[k] = v end
        ApplyLook()
        b:Refresh()
    end, 160 } })
end)

end)
