-- Itsu:UI: global font. every font object the game has, chat + world text

local _, ns = ...

ns.RegisterModule("fonts", "Global Font", function()

local LSM = ns.LSM

-- what things had before we touched them, so Blizzard Default can put it back
local originals = {}
local originalWorld = {}

-- the client reads these when the world loads, so they need a relog to show
local WORLD_FONTS = { "DAMAGE_TEXT_FONT", "UNIT_NAME_FONT", "STANDARD_TEXT_FONT", "NAMEPLATE_FONT" }

-- nil means leave the game alone. font packs can register after us, wait for those
local function WantedPath()
    local key = ns.db.general.globalFont
    if key == ns.FONT_DEFAULT or not LSM:IsValid("font", key) then return nil end
    return ns.GetFont()
end

local function SetObjectFont(obj, path)
    local cur, size, flags = obj:GetFont()
    if not cur then return end
    originals[obj] = originals[obj] or cur
    local want = path or originals[obj]
    if cur ~= want then
        -- one odd font shouldnt stop the rest
        pcall(obj.SetFont, obj, want, size, flags)
    end
end

local function Apply()
    local path = WantedPath()

    for _, name in ipairs(GetFonts()) do
        local obj = _G[name]
        if type(obj) == "table" and obj.GetFont then
            SetObjectFont(obj, path)
        end
    end

    -- chat windows keep their own font instead of using a font object
    for _, name in ipairs(CHAT_FRAMES) do
        local frame = _G[name]
        if frame then
            SetObjectFont(frame, path)
            local box = _G[name .. "EditBox"]
            if box then SetObjectFont(box, path) end
        end
    end

    for _, name in ipairs(WORLD_FONTS) do
        if _G[name] then
            originalWorld[name] = originalWorld[name] or _G[name]
            _G[name] = path or originalWorld[name]
        end
    end
end

-- load on demand addons bring new font objects, catch those too
local queued = false
local function QueueApply()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Apply()
    end)
end

-- right away so stuff built after this reads the new font
Apply()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
eventFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
eventFrame:SetScript("OnEvent", QueueApply)
hooksecurefunc("FCF_OpenTemporaryWindow", QueueApply)

-- a font pack just showed up with the one we saved
LSM.RegisterCallback(ns, "LibSharedMedia_Registered", function(_, mediaType, key)
    if mediaType == "font" and key == ns.db.general.globalFont then
        QueueApply()
    end
end)

-- this fires for every shared setting, only scan when the font really changed
local lastFont = ns.db.general.globalFont
ns.OnShared(function()
    if ns.db.general.globalFont ~= lastFont then
        lastFont = ns.db.general.globalFont
        Apply()
    end
end)

end)
