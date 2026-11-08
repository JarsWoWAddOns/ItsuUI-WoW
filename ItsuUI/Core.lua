-- Itsu:UI for retail WoW 12.1
-- all of Jar's addons in one, this file is the shared stuff

local addonName, ns = ...

ns.UI = {
    bg        = { 0.10, 0.10, 0.12, 0.95 },
    header    = { 0.13, 0.13, 0.16, 1 },
    accent    = { 1.0,  0.55, 0.0,  1 },
    accentDim = { 0.70, 0.35, 0.0,  1 },
    text      = { 0.90, 0.90, 0.90, 1 },
    textDim   = { 0.55, 0.55, 0.58, 1 },
    section   = { 0.16, 0.16, 0.19, 1 },
    border    = { 0.22, 0.22, 0.26, 1 },
    sliderBg  = { 0.18, 0.18, 0.22, 1 },
    sliderFill= { 1.0,  0.55, 0.0,  0.6 },
    btnNormal = { 0.18, 0.18, 0.22, 1 },
    btnHover  = { 0.24, 0.24, 0.28, 1 },
    btnPress  = { 0.14, 0.14, 0.17, 1 },
    checkOff  = { 0.22, 0.22, 0.26, 1 },
}

ns.BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

ns.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
-- font setting that means leave the game's fonts alone
ns.FONT_DEFAULT = "Blizzard Default"

-------------------------------------------------------------------------------
-- Media
-------------------------------------------------------------------------------
local LSM = LibStub("LibSharedMedia-3.0")
ns.LSM = LSM

local TEXTURE_PATH = "Interface\\AddOns\\ItsuUI\\textures\\"
local TEXTURES = {
    ["Smooth"]  = "smooth",
    ["Soft"]    = "soft",
    ["Gloss"]   = "gloss",
    ["Tube"]    = "tube",
    ["Bevel"]   = "bevel",
    ["Inset"]   = "inset",
    ["Chrome"]  = "chrome",
    ["Edge"]    = "edge",
    ["Fade"]    = "fade",
    ["Stripes"] = "stripes",
    ["Hatch"]   = "hatch",
    ["Lines"]   = "lines",
    ["Brushed"] = "brushed",
    -- from bar-textures
    ["Bevel 2"]   = "bevel2",
    ["Brushed 2"] = "brushed2",
    ["Chevron"]   = "chevron",
    ["Cloud"]     = "cloud",
    ["Dualtone"]  = "dualtone",
    ["Frosted"]   = "frosted",
    ["Glossy"]    = "glossy",
    ["Hammered"]  = "hammered",
    ["Scanline"]  = "scanline",
    ["Segmented"] = "segmented",
    ["Smooth 2"]  = "smooth2",
    ["Stone"]     = "stone",
    ["Striped"]   = "striped",
    ["Tube 2"]    = "tube2",
    ["Wave"]      = "wave",
    ["Woodgrain"] = "woodgrain",
}
for name, file in pairs(TEXTURES) do
    LSM:Register(LSM.MediaType.STATUSBAR, name, TEXTURE_PATH .. file .. ".tga")
end

function ns.GetTexture()
    return LSM:Fetch("statusbar", ns.db.general.texture)
end

-- font packs go missing and SetFont errors on a bad path
local fontProbe, checkedFont
function ns.GetFont()
    if ns.db.general.globalFont == ns.FONT_DEFAULT then return ns.DEFAULT_FONT end
    local font = LSM:Fetch("font", ns.db.general.globalFont) or ns.DEFAULT_FONT
    if font == ns.DEFAULT_FONT or font == checkedFont then return font end
    fontProbe = fontProbe or UIParent:CreateFontString(nil, "OVERLAY")
    if pcall(fontProbe.SetFont, fontProbe, font, 12, "") then
        checkedFont = font
        return font
    end
    return ns.DEFAULT_FONT
end

-- modules hook this for the settings they share (texture, font, opacity, unlock)
local sharedCallbacks = {}
function ns.OnShared(fn)
    sharedCallbacks[#sharedCallbacks + 1] = fn
end

function ns.ApplyShared()
    for _, fn in ipairs(sharedCallbacks) do fn() end
end

-------------------------------------------------------------------------------
-- Combat queue, anything touching secure frames goes thru here
-------------------------------------------------------------------------------
local pendingSafe = {}
function ns.RunWhenSafe(key, fn)
    if InCombatLockdown() then
        pendingSafe[key] = fn
    else
        pendingSafe[key] = nil
        fn()
    end
end

-------------------------------------------------------------------------------
-- Hiding blizz bars
-------------------------------------------------------------------------------
local barHider

-- clear a key w/o leaving taint on it
local function PurgeKey(t, k)
    t[k] = nil
    local c = 42
    repeat
        if t[c] == nil then
            t[c] = nil
        end
        c = c + 1
    until issecurevariable(t, k)
end

function ns.HideBlizzardBar(frame, clearEvents)
    if not frame then return end
    if not barHider then
        barHider = CreateFrame("Frame")
        barHider:Hide()
    end
    if clearEvents then
        frame:UnregisterAllEvents()
    end
    -- EditMode bits
    if frame.system then
        PurgeKey(frame, "isShownExternal")
    end
    if frame.HideBase then
        frame:HideBase()
    else
        frame:Hide()
    end
    frame:SetParent(barHider)
end

-------------------------------------------------------------------------------
-- Modules + panels
-------------------------------------------------------------------------------
ns.moduleList = {}
ns.panelList = {}

-- the old standalone addon for each module, both running at once would fight
ns.OLD_ADDONS = {
    bars       = "JarsG13Bars",
    unitFrames = "juf",
    cast       = "JarsCastbar",
    bags       = "JarsBags",
    npc        = "JarsNPCChat",
    rc         = "JarsResourceCounter",
    grid       = "JarGrid",
    fonts      = "JarsFontChanger",
    controller = "JarStick",
}
local OLD_NO_MODULE = { "JarsAddonConfig", "JarsTextures" }

function ns.RegisterModule(key, label, fn)
    ns.moduleList[#ns.moduleList + 1] = { key = key, label = label, fn = fn }
end

-- group: panels with the same group sit indented under one sidebar heading
function ns.RegisterPanel(order, name, build, group)
    ns.panelList[#ns.panelList + 1] = { order = order, name = name, build = build, group = group }
end

-- toc has these as OptionalDeps so they load first, if on theyre already loaded by now
local function IsOldAddonOn(name)
    -- return C_AddOns.GetAddOnEnableState(name, UnitName("player")) > 0
    local loaded = C_AddOns.IsAddOnLoaded(name)
    return loaded
end

-- newer modules never had an old addon
function ns.IsModuleBlocked(key)
    local old = ns.OLD_ADDONS[key]
    return old and IsOldAddonOn(old)
end

function ns.IsModuleOn(key)
    return ns.db.modules[key] ~= false and not ns.IsModuleBlocked(key)
end

function ns.GetOldAddonsOn()
    local on = {}
    for _, name in pairs(ns.OLD_ADDONS) do
        if IsOldAddonOn(name) then on[#on + 1] = name end
    end
    for _, name in ipairs(OLD_NO_MODULE) do
        if IsOldAddonOn(name) then on[#on + 1] = name end
    end
    table.sort(on)
    return on
end

function ns.DisableOldAddons()
    -- blizz's addon list passes the guid here, not the name
    local me = UnitGUID("player")
    for _, name in ipairs(ns.GetOldAddonsOn()) do
        C_AddOns.DisableAddOn(name, me)
    end
    C_AddOns.SaveAddOns()
    ReloadUI()
end

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------
local GENERAL_DEFAULTS = {
    texture      = "Solid",
    globalFont   = ns.FONT_DEFAULT,
    bgAlpha      = 0,
    unlocked     = false,
    configScale  = 0.85, -- bumped x1.15 once below, so 0.98 on screen
    minimapAngle = -1.93,
}

local function InitDB()
    JarForeverDB = JarForeverDB or {}
    JarForeverCharDB = JarForeverCharDB or {}
    local db = JarForeverDB

    db.general = db.general or {}
    -- old font setting only ever covered this addon, friz was just its default
    if db.general.font then
        if db.general.font ~= "Friz Quadrata TT" then db.general.globalFont = db.general.font end
        db.general.font = nil
    end
    -- textures lost the Jar prefix
    if db.general.texture then db.general.texture = db.general.texture:gsub("^Jar ", "") end
    for k, v in pairs(GENERAL_DEFAULTS) do
        if db.general[k] == nil then db.general[k] = v end
    end
    -- the window read a bit small, everyone gets 15% more once
    if not db.general.scaleBumped then
        db.general.configScale = math.min(1.5, db.general.configScale * 1.15)
        db.general.scaleBumped = true
    end
    db.modules = db.modules or {}
    -- keyboard bars by default, the controller is the other half of that switch
    if db.modules.controller == nil then db.modules.controller = false end
    for _, key in ipairs({ "unitFrames", "bars", "cast", "bags", "npc", "rc", "grid", "xp", "gameMenu", "stance", "controller" }) do
        db[key] = db[key] or {}
    end
    JarForeverCharDB.bars = JarForeverCharDB.bars or {}
    JarForeverCharDB.controller = JarForeverCharDB.controller or {}

    -- coming from the standalone JarStick: take its settings over once. it's an OptionalDep
    -- so it has loaded by now if its still on
    if C_AddOns.IsAddOnLoaded("JarStick") then
        if not db.controller.imported and JarStickDB then
            db.controller = CopyTable(JarStickDB)
            db.controller.imported = true
        end
        if not JarForeverCharDB.controller.imported and JarStickCharDB then
            JarForeverCharDB.controller = CopyTable(JarStickCharDB)
            JarForeverCharDB.controller.imported = true
        end
    end

    ns.db = db
    ns.char = JarForeverCharDB
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        -- one broken module shouldnt take the rest down with it
        for _, m in ipairs(ns.moduleList) do
            if ns.IsModuleOn(m.key) then
                xpcall(m.fn, geterrorhandler())
            end
        end

    elseif event == "PLAYER_LOGIN" then
        ns.CreateMinimapButton()
        print("|cffff8c00Itsu:UI|r loaded. Type |cff00ffff/jf|r for options.")
        local old = ns.GetOldAddonsOn()
        if #old > 0 then
            print("|cffff8c00Itsu:UI|r old addons still on: " .. table.concat(old, ", ") .. ". Type |cff00ffff/jf cleanup|r to turn them off.")
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        for key, fn in pairs(pendingSafe) do
            pendingSafe[key] = nil
            fn()
        end
    end
end)

-- what /js used to take, passed on to JarStick when controller mode is on
ns.JS_COMMANDS = {
    lock = true, unlock = true, mouse = true, reset = true, resetall = true, pad = true,
    debug = true, ring = true, book = true, spells = true, talents = true, ui = true,
    save = true, load = true, delete = true, list = true,
}

SLASH_JARFOREVER1 = "/jf"
SLASH_JARFOREVER2 = "/jarforever"
SLASH_JARFOREVER3 = "/jac"
SlashCmdList["JARFOREVER"] = function(msg)
    local raw = (msg or ""):trim() -- profile names keep their case
    msg = raw:lower()
    local cmd = msg:match("^(%S+)")
    if msg == "cleanup" then
        ns.DisableOldAddons()
    elseif cmd and ns.js and ns.js.SlashCommand and ns.JS_COMMANDS[cmd] then
        -- controller mode: JarStick's old /js commands live here now
        ns.js.SlashCommand(raw)
    else
        ns.ToggleConfig()
    end
end
