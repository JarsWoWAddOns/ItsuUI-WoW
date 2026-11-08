-- Itsu:UI controller mode, started from JarStick. edit it here
-- JarStick: gamepad action bars, camera and cursor glue for WoW 12.1
-- Left stick moves, right stick looks. A/B/X/Y are slots 1-4 of a bar, L2 + face 5-8, R2 + face 9-12.
-- Dpad picks the bar (up 1, right 2, down 3, left 4) and it sticks. Select holds bar 6. L1/R1 tab enemy/friend. L3 jumps.
-- R3 toggles mouse mode (R1 left click, L1 right click). Select + right stick = menu wheel, Select + L2/R2 zooms.
-- R1 held + L1 held = party ring. Start = Esc.

local _, jf = ...
jf.jsParts = jf.jsParts or {}
jf.jsParts[#jf.jsParts + 1] = function(ns, ADDON)

ns.acct = ns.acct or {}         -- account: named profiles
ns.charDB = ns.charDB or {} -- this character: live settings + last profile name

local defaults = {
    invertX = false,
    invertY = false,
    cameraSpeed = 1.0,
    turnAlways = true,      -- so the reticle aims where the character faces
    interactInCombat = false,
    reticle = false,       -- center crosshair, the X prompt shows either way
    reticleScale = 1.5,
    objectIcon = true,      -- blizzards marker on the soft interact object
    partyHealth = "both",   -- special layer party colors: border, fill, both, off
    zoomSpeed = 1.0,
    zoomFlip = false,
    rightStick = 2,         -- index into GamePadMappedState.sticks
    device = "",            -- "" auto, "combined", or a device name for GamePadSingleActiveID
    mouseStick = "R3",      -- which stick click toggles mouse mode, the other one jumps
    panels = { L = false, R = false }, -- spare bar grids open?
    panelSide = "L",        -- grid cursor
    panelIdx = 1,
    actionCam = false,
    actionCamMode = "basic",
    configScale = 1.25,     -- couch sized options window
    scale = 1.0,
    locked = true,
    mirror = true,          -- right cluster follows the left one
    hideBlizzard = true,
    showGlyphs = true,
    left = {},              -- x/y from screen center, filled on first run
    right = {},
    -- sel: page shown while select is held. b1-b5: page per bonusbar state (bar 1 only)
    pages = { sel = 13, b1 = 7, b2 = 8, b3 = 9, b4 = 10, b5 = 11 },
    -- dpad right/down/left -> page. up is always Action Bar 1 and follows forms
    bars = { PADDRIGHT = 6, PADDDOWN = 5, PADDLEFT = 3 }, -- Action Bar 2, 3, 4
    bar = 1,                -- which dpad bar is picked, 1-4
    -- L2+R2 + dpad: raid target icon index (1 star .. 8 skull)
    marks = { PADDUP = 7, PADDRIGHT = 8, PADDLEFT = 2, PADDDOWN = 3 }, -- cross, skull, circle, diamond
}

-- old select menu, the 8 buttons opened panels. replaced by the wheel in Wheel.lua
-- ns.PANELS = {
--     { cmd = "TOGGLECHARACTER0", name = "Character" },
--     ...
-- }

-- L2 + R2 together is a fixed layer nothing else can page over
local SPECIAL = {
    -- dpad: raid markers here, the party targets live on the R1 hold layer
    PADDUP = { cmd = "TARGETPARTYMEMBER1", label = "Party 2", unit = "party1", mark = 1 },
    PADDRIGHT = { cmd = "TARGETPARTYMEMBER2", label = "Party 3", unit = "party2", mark = 2 },
    PADDLEFT = { cmd = "TARGETPARTYMEMBER3", label = "Party 4", unit = "party3", mark = 3 },
    PADDDOWN = { cmd = "TARGETPARTYMEMBER4", label = "Party 5", unit = "party4", mark = 4 },
    -- PAD3 = { cmd = "TARGETSELF", label = "Self" },
    -- PAD4 = { cmd = "VEHICLEEXIT", label = "Leave" },
    -- PAD1 = { cmd = "EXTRAACTIONBUTTON1", label = "Extra" },
    -- face: the jarstick book, cluster lock, mount
    PAD1 = { click = "JarStickBookSpells", label = "Spells" },
    PAD4 = { click = "JarStickBookTalents", label = "Talents" },
    PAD3 = { click = "JarStickPadMove", label = "Unlock" },
    PAD2 = { click = "JarStickMount", label = "Mount" },
}
local SPECIAL_MODS = { ["CTRL-SHIFT-"] = true, ["ALT-CTRL-SHIFT-"] = true }
-- the random favorite spell cant be /cast by name, SummonByID(0) is blizzards own route
local MOUNT_MACRO = "/dismount [mounted]\n/stopmacro [mounted]\n/run C_MountJournal.SummonByID(0)"

-- action pages and which blizzard bar they are
ns.PAGES = {
    { page = 1,  name = "Action Bar 1",      slots = "1-12" },
    { page = 2,  name = "Page 2",            slots = "13-24" },
    { page = 3,  name = "Action Bar 4",      slots = "25-36" },
    { page = 4,  name = "Action Bar 5",      slots = "37-48" },
    { page = 5,  name = "Action Bar 3",      slots = "49-60" },
    { page = 6,  name = "Action Bar 2",      slots = "61-72" },
    { page = 7,  name = "Bonus page 7",      slots = "73-84" },
    { page = 8,  name = "Bonus page 8",      slots = "85-96" },
    { page = 9,  name = "Bonus page 9",      slots = "97-108" },
    { page = 10, name = "Bonus page 10",     slots = "109-120" },
    { page = 11, name = "Skyriding page 11", slots = "121-132" },
    { page = 12, name = "Possess page 12",   slots = "133-144" },
    { page = 13, name = "Action Bar 6",      slots = "145-156" },
    { page = 14, name = "Action Bar 7",      slots = "157-168" },
    { page = 15, name = "Action Bar 8",      slots = "169-180" },
}

local SIZE, GAP = 45, 4

-- dx/dy place the diamond (x in half steps)
-- 1-4: face buttons = slots 1-4 of the picked bar, L2 adds 4, R2 adds 8
-- 5-8: dpad, picks the bar. 9-10: bumper boxes, always tab targeting
-- local BUTTONS = {
--     { key = "PADDUP",    cluster = "left",  dx = 0,  dy = 1 },
--     { key = "PADDLEFT",  cluster = "left",  dx = -1, dy = 0 },
--     { key = "PADDRIGHT", cluster = "left",  dx = 1,  dy = 0 },
--     { key = "PADDDOWN",  cluster = "left",  dx = 0,  dy = -1 },
--     { key = "PAD4",      cluster = "right", dx = 0,  dy = 1 },
--     { key = "PAD3",      cluster = "right", dx = -1, dy = 0 },
--     { key = "PAD2",      cluster = "right", dx = 1,  dy = 0 },
--     { key = "PAD1",      cluster = "right", dx = 0,  dy = -1 },
--     ...bumpers
-- }
local BUTTONS = {
    { key = "PAD1",      cluster = "right", dx = 0,  dy = -1 }, -- A / cross
    { key = "PAD2",      cluster = "right", dx = 1,  dy = 0 },  -- B / circle
    { key = "PAD3",      cluster = "right", dx = -1, dy = 0 },  -- X / square
    { key = "PAD4",      cluster = "right", dx = 0,  dy = 1 },  -- Y / triangle
    { key = "PADDUP",    cluster = "left",  dx = 0,  dy = 1,  bar = 1 },
    { key = "PADDRIGHT", cluster = "left",  dx = 1,  dy = 0,  bar = 2 },
    { key = "PADDDOWN",  cluster = "left",  dx = 0,  dy = -1, bar = 3 },
    { key = "PADDLEFT",  cluster = "left",  dx = -1, dy = 0,  bar = 4 },
    { key = "PADLSHOULDER", cluster = "left",  dx = -2, dy = 1, target = "TARGETNEARESTENEMY", color = { 1, 0.2, 0.2 }, panel = "L" },
    { key = "PADRSHOULDER", cluster = "right", dx = 2,  dy = 1, target = "TARGETNEARESTFRIEND", color = { 0.2, 1, 0.2 }, panel = "R" },
}
local NUM_SLOTS = 4
local BAR_KEYS = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT" }

-- spare bars as 3x4 grids above the bumper boxes, toggled with L2+R2+L1 / R1
local PANELS = { L = { page = 3, anchor = 9 }, R = { page = 4, anchor = 10 } }
local PCOLS, PROWS = 4, 3

-- every modifier combo gets bound so a held L2/R2/R3 never swallows a press
local MODS = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }

-- cvars we own while loaded
local PAD_CVARS = {
    GamePadEmulateShift = "PADLTRIGGER",      -- L2
    GamePadEmulateCtrl = "PADRTRIGGER",       -- R2
    -- R1 doubles as alt: tap = target friend, hold = party layer on the dpad
    GamePadEmulateAlt = "PADRSHOULDER",
    GamePadEmulateEsc = "NONE",               -- start is bound to TOGGLEGAMEMENU instead, emulation never fired
    GamePadCursorLeftClick = "PADRSHOULDER",  -- R1 left clicks in mouse mode
    GamePadCursorRightClick = "PADLSHOULDER", -- L1 right clicks
    GamePadCursorAutoDisableSticks = 0,       -- keep moving while in mouse mode
    GamePadCursorAutoDisableJump = 0,
    GamePadCursorAutoEnable = 0,              -- only R3+L3 brings the cursor up, not every window
    GamePadCursorCentering = 0,
    SoftTargetInteract = 3,                   -- always pick the npc/object in front
    SoftTargetInteractArc = 1,                -- front arc, not dead center only
    SoftTargetIconInteract = 1,
    GamePadStickAxisButtons = 1,              -- stick directions as keys, the party ring binds them
}

local db
local clusters = {}
local buttons = {}
local driver, bindOwner, zoomer, UIHider
local hiddenBars = false

local HideBlizzardBars, ApplyBindings, ApplyLayout, ApplyAll
local ApplyStickInvert

-- queue secure stuff til combat ends
local pendingSafe = {}
local function RunWhenSafe(key, fn)
    if InCombatLockdown() then
        pendingSafe[key] = fn
    else
        pendingSafe[key] = nil
        fn()
    end
end

local function FlushSafeQueue()
    for key, fn in pairs(pendingSafe) do
        pendingSafe[key] = nil
        fn()
    end
end

local function Print(msg)
    print("|cffff8c00Itsu:UI|r " .. msg)
end

-- debug lines also go to the saved vars so they can be read after a /reload
local function Log(msg)
    Print(msg)
    local log = ns.acct.debugLog
    if not log then
        log = {}
        ns.acct.debugLog = log
    end
    log[#log + 1] = date("%H:%M:%S ") .. msg
    while #log > 80 do
        table.remove(log, 1)
    end
end
ns.Log = Log

local function PageName(page)
    for _, p in ipairs(ns.PAGES) do
        if p.page == page then return p.name end
    end
    return "Page " .. tostring(page)
end

-- cvars ---------------------------------------------------------------------

-- blizzards hand icon over the object it thinks you are facing, handy for aiming
local function ApplyObjectIcon()
    C_CVar.SetCVar("SoftTargetIconGameObject", db.objectIcon and "1" or "0")
end

-- frozen = party ring is up, stick is the selector only
-- invert: negative speeds do nothing and the mouse invert cvars dont touch the pad.
-- forever has gamepadInvertYaw/Pitch, retail has no pad invert cvar at all
local cameraFrozen = false
local function ApplyCamera()
    local s = db.cameraSpeed
    -- local yaw, pitch = db.invertX and -s or s, db.invertY and -s or s
    local yaw, pitch = s, s
    if cameraFrozen then yaw, pitch = 0, 0 end
    -- C_CVar.SetCVar("mouseInvertYaw", db.invertX and "1" or "0")
    -- C_CVar.SetCVar("mouseInvertPitch", db.invertY and "1" or "0")
    if C_CVar.GetCVar("gamepadInvertPitch") ~= nil then
        C_CVar.SetCVar("gamepadInvertYaw", db.invertX and "1" or "0")
        C_CVar.SetCVar("gamepadInvertPitch", db.invertY and "1" or "0")
    end
    C_CVar.SetCVar("GamePadCameraYawSpeed", tostring(yaw))
    C_CVar.SetCVar("GamePadCameraPitchSpeed", tostring(pitch))
    if ApplyStickInvert then ApplyStickInvert() end
    if db.turnAlways then
        -- camera locked: char faces the camera, stick back = backpedal.
        -- face-movement has to be off or the two fight and you flip forward again
        C_CVar.SetCVar("GamePadTurnWithCamera", "2")
        C_CVar.SetCVar("GamePadFaceMovementMaxAngle", "180")
    else
        C_CVar.SetCVar("GamePadTurnWithCamera", C_CVar.GetCVarDefault("GamePadTurnWithCamera"))
        C_CVar.SetCVar("GamePadFaceMovementMaxAngle", C_CVar.GetCVarDefault("GamePadFaceMovementMaxAngle"))
    end
end

-- blizzards action cam presets, same as /console actioncam basic|full|off
-- the motion sickness cvars (keep character centered etc) quietly override it, so those
-- go to 0 while its on and back to whatever the player had when its off
local CALM_CVARS = { "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }

local function ApplyActionCam(fromLogin)
    if not ConsoleExec then
        Print("ConsoleExec is gone, set action cam with /console actioncam basic")
        return
    end
    if db.actionCam then
        -- no "experimental camera features" popup every login, action cam is on by choice here
        if GameEvent and GameEvent.UnregisterInternalEvent then
            GameEvent.UnregisterInternalEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
        end
        db.calmCVars = db.calmCVars or {}
        for _, cv in ipairs(CALM_CVARS) do
            local cur = C_CVar.GetCVar(cv)
            if cur and db.calmCVars[cv] == nil then db.calmCVars[cv] = cur end
            if cur then C_CVar.SetCVar(cv, "0") end
        end
        ConsoleExec("actioncam " .. (db.actionCamMode or "basic"))
    elseif not fromLogin then
        ConsoleExec("actioncam off")
        for cv, v in pairs(db.calmCVars or {}) do C_CVar.SetCVar(cv, v) end
        db.calmCVars = nil
    end
end

local function ApplyPadCVars()
    if not C_GamePad.IsEnabled() then
        C_CVar.SetCVar("GamePadEnable", "1")
        Print("gamepad input enabled, /jf for options")
    end
    for cvar, value in pairs(PAD_CVARS) do
        C_CVar.SetCVar(cvar, tostring(value))
    end
    ApplyCamera()
    ApplyObjectIcon()
end

local function ResetPadCVars()
    local list = { "GamePadCameraYawSpeed", "GamePadCameraPitchSpeed", "GamePadTurnWithCamera",
        "GamePadFaceMovementMaxAngle", "GamePadSingleActiveID", "SoftTargetIconGameObject",
        "gamepadInvertYaw", "gamepadInvertPitch" }
    for cvar in pairs(PAD_CVARS) do
        table.insert(list, cvar)
    end
    for _, cvar in ipairs(list) do
        -- some only exist on one client
        if C_CVar.GetCVar(cvar) ~= nil then
            C_CVar.SetCVar(cvar, C_CVar.GetCVarDefault(cvar))
        end
    end
    Print("gamepad cvars back to Blizzard defaults, disable the addon to keep them")
end

-- blizzards own "Lock Action Bars", it keeps LOCK_ACTIONBAR in sync off the cvar
local function GetLockActionBars()
    return C_CVar.GetCVarBool("lockActionBars")
end

local function SetLockActionBars(on)
    C_CVar.SetCVar("lockActionBars", on and "1" or "0")
end

-- xbox pads seen through directinput put the triggers on a stick axis
local function GetForceXInput()
    return C_CVar.GetCVarBool("GamePadForceXInput")
end

local function SetForceXInput(on)
    C_CVar.SetCVar("GamePadForceXInput", on and "1" or "0")
    Print("XInput " .. (on and "forced" or "not forced") .. ", /reload or replug the pad")
end

-- real devices, the combined one left out. generic = blizzard has no map for it
local function DeviceList()
    local list = {}
    local combined = C_GamePad.GetCombinedDeviceID()
    for _, id in ipairs(C_GamePad.GetAllDeviceIDs()) do
        if id ~= combined then
            local st = C_GamePad.GetDeviceMappedState(id)
            if st then
                list[#list + 1] = { id = id, name = st.name or ("Device " .. id), generic = (st.labelStyle == "Generic") }
            end
        end
    end
    return list
end

-- a pad on a dongle can show up twice (xinput + directinput). combined input then
-- doubles every press and puts the triggers on a stick axis, so pick one device
local lastPick
local function ApplyDevice()
    local list = DeviceList()
    local id, why = 0, nil
    if db.device == "combined" then
        why = "all controllers combined"
    elseif db.device ~= "" then
        for _, e in ipairs(list) do
            if e.name == db.device then id = e.id end
        end
        why = id > 0 and ("using " .. db.device) or ("'" .. db.device .. "' not connected, using combined input")
    elseif #list >= 2 then
        local pick, n = nil, 0
        for _, e in ipairs(list) do
            if not e.generic then
                n = n + 1
                pick = e
            end
        end
        if n == 1 then
            id = pick.id
            local others = {}
            for _, e in ipairs(list) do
                if e.id ~= id then others[#others + 1] = e.name end
            end
            why = "using " .. pick.name .. " only, ignoring " .. table.concat(others, ", ") .. " (same pad seen twice)"
        end
    end
    C_CVar.SetCVar("GamePadSingleActiveID", tostring(id))
    if why and why ~= lastPick then
        lastPick = why
        Print(why)
    end
end

-- /js pad: what the pad is and what each control sends, for sorting out bad axis maps
local function PadReport()
    -- also kept in the saved vars so it can be read after a /reload
    local report = {}
    ns.acct.padReport = report
    local function Say(s)
        Print(s)
        report[#report + 1] = s
    end
    local ids = C_GamePad.GetAllDeviceIDs()
    Say(#ids .. " device(s), active id " .. tostring(C_GamePad.GetActiveDeviceID()))
    for _, id in ipairs(ids) do
        local st = C_GamePad.GetDeviceMappedState(id)
        local raw = C_GamePad.GetDeviceRawState(id)
        Say(string.format("  #%d %s  labels=%s  buttons=%d axes=%d sticks=%d  raw=%s (%d axes, %d buttons)",
            id, st and st.name or "?", st and tostring(st.labelStyle) or "?",
            st and st.buttonCount or 0, st and st.axisCount or 0, st and st.stickCount or 0,
            raw and raw.name or "?", raw and raw.rawAxisCount or 0, raw and raw.rawButtonCount or 0))
    end
    local cv = {}
    for _, name in ipairs({ "GamePadSingleActiveID", "GamePadTurnWithCamera", "GamePadFaceMovementMaxAngle",
        "GamePadFaceMovementMaxAngleCombat", "GamePadAnalogMovement", "GamePadForceXInput", "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt", "GamePadEmulateTapWindowMs" }) do
        cv[#cv + 1] = name:gsub("^GamePad", "") .. "=" .. tostring(C_CVar.GetCVar(name))
    end
    Say("cvars: " .. table.concat(cv, " "))
    Say(string.format("softinteract: %s  PAD3 -> %s  PADFORWARD -> %s  SoftTargetInteract=%s arc=%s",
        (ns.HasSoftInteract and ns.HasSoftInteract()) and "yes" or "none", tostring(GetBindingAction("PAD3", true)),
        tostring(GetBindingAction("PADFORWARD", true)), tostring(C_CVar.GetCVar("SoftTargetInteract")),
        tostring(C_CVar.GetCVar("SoftTargetInteractArc"))))
    Say("group=" .. tostring(IsInGroup()) .. "  ALT-PADDUP -> " .. tostring(GetBindingAction("ALT-PADDUP", true))
        .. "  PADLSHOULDER -> " .. tostring(GetBindingAction("PADLSHOULDER", true))
        .. "  ALT-PADLSHOULDER -> " .. tostring(GetBindingAction("ALT-PADLSHOULDER", true))
        .. "  ring=" .. tostring(_G.JarStickL1 ~= nil and _G.JarStickRingCtl ~= nil) .. "  StickAxisButtons=" .. tostring(C_CVar.GetCVar("GamePadStickAxisButtons")))
    Say("ring self test: " .. (ns.RingSelfTest and ns.RingSelfTest() or "no Wheel.lua"))
    -- Say("now hold R1, then press L2, then R2, then move the right stick. watching for 5 seconds")
    Say("now hold R1 and press L1, let go of both, then L1 first and R1. watching for 8 seconds")
    ns.padWatch = true
    local seen, t = {}, 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local st = C_GamePad.GetDeviceMappedState()
        for i, v in ipairs(st and st.axes or {}) do
            if math.abs(v) > 0.5 and not seen["a" .. i] then
                seen["a" .. i] = true
                Say(string.format("  axis %d (%s) = %.2f", i, tostring(C_GamePad.AxisIndexToConfigName(i - 1)), v))
            end
        end
        for i, s in ipairs(st and st.sticks or {}) do
            if (s.len or 0) > 0.5 and not seen["s" .. i] then
                seen["s" .. i] = true
                Say(string.format("  stick %d (%s) x=%.2f y=%.2f", i, tostring(C_GamePad.StickIndexToConfigName(i - 1)), s.x, s.y))
            end
        end
        for i, down in ipairs(st and st.buttons or {}) do
            if down and not seen["b" .. i] then
                seen["b" .. i] = true
                Say(string.format("  button %d (%s)", i, tostring(C_GamePad.ButtonIndexToBinding(i - 1))))
            end
        end
        -- which modifiers the game thinks are held
        for _, m in ipairs({ { "alt", IsAltKeyDown }, { "shift", IsShiftKeyDown }, { "ctrl", IsControlKeyDown } }) do
            if m[2]() and not seen[m[1]] then
                seen[m[1]] = true
                Say("  modifier held: " .. m[1])
            end
        end
        if t > 8 then
            ns.padWatch = nil
            self:SetScript("OnUpdate", nil)
            Say("pad report done")
        end
    end)
end

-- R1 as alt sometimes stops working while the cvar still reads PADRSHOULDER (Jar, 2026-11-07).
-- setting it to NONE and back brings it back, so do that when a held button isnt giving its
-- modifier. the triggers get the same check
local EMULATE = {
    GamePadEmulateShift = IsShiftKeyDown,
    GamePadEmulateCtrl = IsControlKeyDown,
    GamePadEmulateAlt = IsAltKeyDown,
}
local rearming = false
local heldFor = {}

local function Rearm(cvar)
    rearming = true
    C_CVar.SetCVar(cvar, "NONE")
    C_CVar.SetCVar(cvar, PAD_CVARS[cvar])
    rearming = false
    Log(cvar .. " stopped working, re-armed it")
end

local function CheckEmulation(elapsed)
    -- in mouse mode R1 is a click, not alt
    if IsGamePadCursorControlEnabled() then return end
    local st = C_GamePad.GetDeviceMappedState()
    if not st then return end
    local wait = (tonumber(C_CVar.GetCVar("GamePadEmulateTapWindowMs")) or 350) / 1000 + 0.25
    for cvar, isDown in pairs(EMULATE) do
        local idx = C_GamePad.ButtonBindingToIndex(PAD_CVARS[cvar])
        if idx and st.buttons[idx + 1] and not isDown() then
            heldFor[cvar] = (heldFor[cvar] or 0) + elapsed
            if heldFor[cvar] > wait then
                heldFor[cvar] = -3 -- give it a few seconds before trying again
                Rearm(cvar)
            end
        elseif (heldFor[cvar] or 0) > 0 then
            heldFor[cvar] = 0
        end
    end
end

-- mouse mode ----------------------------------------------------------------

-- only R3+L3, /js mouse, or a panel opened from the select menu may turn the cursor on.
-- blizzard's game menu and loot window call SetGamePadCursorControl(true) themselves,
-- so veto anything we didnt ask for
local wantCursor = false

local function SetMouseMode(on)
    if on and CanGamePadControlCursor and not CanGamePadControlCursor() then return end
    wantCursor = on
    SetGamePadCursorControl(on)
    -- the cursor rides the same stick axes, it gets them back unflipped
    ApplyStickInvert()
end

-- retail has no pad invert cvar (forever has gamepadInvertYaw/Pitch), so flip the right stick
-- axes in the pad config. C_GamePad.GetConfig only hands back addon made configs, never
-- blizzard's built-in ones, so this carries a copy of blizzard's default for the pads it
-- knows (WTF\GamePadConfig_Default.json, configVersion 4) and sends that with the stick
-- flipped. nothing is touched until invert is ticked, unticking deletes ours again
local stickFlip = { x = 1, y = 1 } -- the wheel and ring read the flipped axes, they undo it with this
ns.stickFlip = stickFlip

local function RawMap(list, field)
    local t = {}
    for i, v in ipairs(list) do t[i] = { rawIndex = i - 1, [field] = v } end
    return t
end

local PAD_DEFAULTS = {
    -- Xbox 360 Controller, XInput. blizzard's raw Y axes point down, hence the -1s
    ["1118:654"] = {
        labelStyle = "Letters",
        rawButtonMappings = RawMap({ "PAD1", "PAD2", "PAD3", "PAD4", "PADBACK", "PADSYSTEM", "PADFORWARD",
            "PADLSTICK", "PADRSTICK", "PADLSHOULDER", "PADRSHOULDER", "PADDUP", "PADDDOWN", "PADDLEFT",
            "PADDRIGHT", "PAD5", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4", "None" }, "button"),
        rawAxisMappings = RawMap({ "LStickX", "LStickY", "RStickX", "RStickY", "LTrigger", "RTrigger" }, "axis"),
        axisConfigs = {
            { axis = "LStickX", shift = 0, scale = 1 },
            { axis = "LStickY", shift = 0, scale = -1 },
            { axis = "RStickX", shift = 0, scale = 1 },
            { axis = "RStickY", shift = 0, scale = -1 },
            { axis = "GStickX", shift = 0, scale = 1 },
            { axis = "GStickY", shift = 0, scale = 1 },
            { axis = "PStickX", shift = -0.5, scale = 2 },
            { axis = "PStickY", shift = -0.5, scale = -2 },
            { axis = "LTrigger", shift = 0, scale = 1 },
            { axis = "RTrigger", shift = 0, scale = 1 },
        },
        stickConfigs = {}, -- sticks come from blizzard's All Devices config
    },
}

local function PadConfigID()
    local id = tonumber(C_CVar.GetCVar("GamePadSingleActiveID")) or 0
    if id == 0 then id = C_GamePad.GetActiveDeviceID() end
    local raw = id and C_GamePad.GetDeviceRawState(id)
    if raw and raw.vendorID and raw.vendorID ~= 0 then
        return { vendorID = raw.vendorID, productID = raw.productID }, raw.vendorID .. ":" .. raw.productID
    end
end

-- this runs on every camera change, so only touch the config when the wanted flip changes
local lastInvert, warnedPad
ApplyStickInvert = function()
    if C_CVar.GetCVar("gamepadInvertPitch") ~= nil then return end
    RunWhenSafe("stickinvert", function()
        local cfgID, key = PadConfigID()
        if not cfgID then return end
        local sx = (db.invertX and not wantCursor) and -1 or 1
        local sy = (db.invertY and not wantCursor) and -1 or 1
        local want = key .. ":" .. sx .. ":" .. sy
        if want == lastInvert then return end
        lastInvert = want

        if sx == 1 and sy == 1 then
            -- back to blizzard's own default
            if C_GamePad.GetConfig(cfgID) then
                C_GamePad.DeleteConfig(cfgID)
                C_GamePad.ApplyConfigs()
            end
        elseif PAD_DEFAULTS[key] then
            local cfg = CopyTable(PAD_DEFAULTS[key])
            cfg.configID = cfgID
            cfg.comment = "JarStick invert, right stick flipped"
            for _, a in ipairs(cfg.axisConfigs) do
                if a.axis == "RStickX" then a.scale = a.scale * sx end
                if a.axis == "RStickY" then a.scale = a.scale * sy end
            end
            C_GamePad.SetConfig(cfg)
            C_GamePad.ApplyConfigs()
        else
            if warnedPad ~= key then
                warnedPad = key
                Print("invert doesn't know this controller (" .. key .. "), only the Xbox 360 pad so far")
            end
            sx, sy = 1, 1
        end
        if ns.debug then Log("stick invert " .. want) end
        if stickFlip.x ~= sx or stickFlip.y ~= sy then
            stickFlip.x, stickFlip.y = sx, sy
            if ns.ApplyRingMap then ns.ApplyRingMap() end
        end
    end)
end

local function ToggleMouseMode()
    SetMouseMode(not IsGamePadCursorControlEnabled())
end

hooksecurefunc("SetGamePadCursorControl", function(enable)
    if enable and not wantCursor then
        if ns.debug then Print("blizzard turned the cursor on, turning it back off") end
        SetGamePadCursorControl(false)
    elseif not enable and wantCursor then
        SetGamePadCursorControl(true)
    end
end)

local function UpdateModeLabel()
    local text = IsGamePadCursorControlEnabled() and "MOUSE" or ""
    for _, c in pairs(clusters) do
        c.mode:SetText(text)
    end
end

-- select + L2/R2 zoom ---------------------------------------------------------
-- the right stick belongs to the wheel now. triggers are shift/ctrl so just read those

-- local function ZoomOnUpdate(self, elapsed)
--     local state = C_GamePad.GetDeviceMappedState()
--     local stick = state and state.sticks and state.sticks[db.rightStick]
--     if not stick then return end
--     local y = stick.y or 0
--     if db.zoomFlip then y = -y end
--     local step = math.abs(y) * db.zoomSpeed * elapsed * 15
--     if y > 0.15 then
--         CameraZoomIn(step)
--     elseif y < -0.15 then
--         CameraZoomOut(step)
--     end
-- end

local function ZoomOnUpdate(_, elapsed)
    local out, inn = IsShiftKeyDown(), IsControlKeyDown()
    if out == inn then return end
    if db.zoomFlip then out = not out end
    local step = db.zoomSpeed * elapsed * 15
    if out then
        CameraZoomOut(step)
    else
        CameraZoomIn(step)
    end
end

-- freeze the camera while select is held, the right stick drives the wheel
local function StartZoom()
    if zoomer:IsShown() then return end
    C_CVar.SetCVar("GamePadCameraYawSpeed", "0")
    C_CVar.SetCVar("GamePadCameraPitchSpeed", "0")
    zoomer:Show()
end

local function StopZoom()
    if not zoomer:IsShown() then return end
    zoomer:Hide()
    ApplyCamera()
end

-- buttons -------------------------------------------------------------------

-- blizz UpdateHotkeys looks for ACTIONBUTTON0, put the pad glyph there instead
local function UpdateGlyph(button)
    local hk = button.HotKey
    if not hk then return end
    local text = db.showGlyphs and GetBindingText(button.padKey, 1) or ""
    if button.side then
        -- the marker overlay carries the glyph while its up, dont show it twice
        button.side.glyph:SetText(text)
        if button.side:IsShown() then text = "" end
    end
    if text == "" then
        hk:SetText("")
        hk:Hide()
        return
    end
    hk:ClearAllPoints()
    hk:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    hk:SetSize(button:GetWidth(), 16)
    hk:SetText(text)
    hk:Show()
end

local function RefreshGlyphs()
    for _, b in ipairs(buttons) do
        UpdateGlyph(b)
    end
end

local overlay, selectHeld = nil, false

-- place mode from Book.lua: slots you can drop on pulse, bumpers point up at the grids
local placeGlows = {}
local function Glow(frame)
    local g = placeGlows[frame]
    if g then return g end
    g = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    g:SetPoint("TOPLEFT", -3, 3)
    g:SetPoint("BOTTOMRIGHT", 3, -3)
    g:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    g:SetBackdropBorderColor(1, 0.55, 0, 1)
    g:SetFrameLevel(frame:GetFrameLevel() + 8)
    local pulse = g:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.5)
    g:SetScript("OnShow", function() pulse:Play() end)
    g:SetScript("OnHide", function() pulse:Stop() end)
    g:Hide()
    placeGlows[frame] = g
    return g
end

local function PaintPlace()
    local mode = ns.placeMode
    for i, b in ipairs(buttons) do
        Glow(b):SetShown(mode == "slots" and i <= NUM_SLOTS)
        local alpha = mode == "grid" and 0.35 or 1
        if b.placeAlpha ~= alpha then
            b.placeAlpha = alpha
            b:SetAlpha(alpha)
        end
        if b.side and overlay == nil then
            if mode then
                -- Misc_ArrowLup, same arrow the special layer uses for the grids
                b.side.icon:SetTexture(450907)
                b.side.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.side.icon:SetVertexColor(1, 1, 1)
            else
                b.side.icon:SetTexture("Interface\\Cursor\\Crosshairs")
                b.side.icon:SetTexCoord(0, 1, 0, 1)
                b.side.icon:SetVertexColor(unpack(b.sideColor))
            end
        end
    end
    for _, p in pairs(ns.panels or {}) do
        Glow(p):SetShown(mode == "slots")
    end
    -- the grids sit where the page label goes, drop it under the cluster
    for _, c in pairs(clusters) do
        c.page:ClearAllPoints()
        if mode then
            c.page:SetPoint("TOP", c, "BOTTOM", 0, -18)
        else
            c.page:SetPoint("BOTTOM", c, "TOP", 0, 2)
        end
    end
end

-- dpad diamonds: the picked bar gets the gold edge
local function PaintBars()
    local bar = driver and driver:GetAttribute("bar") or db.bar
    for _, b in ipairs(buttons) do
        if b.bar then
            local on = b.bar == bar
            b:SetBackdropBorderColor(on and 1 or 0.25, on and 0.82 or 0.25, on and 0 or 0.28, 1)
            b.num:SetTextColor(on and 1 or 0.55, on and 0.82 or 0.55, on and 0 or 0.55)
        end
    end
end

-- bar name above the clusters, plus which third of it the triggers are showing
local ROW_TEXT = { [1] = "  5-8", [2] = "  9-12" }
local function SetPageLabel()
    local text = ""
    if overlay then
        text = overlay
    elseif driver then
        local row = tonumber(driver:GetAttribute("state-row")) or 0
        local name
        if selectHeld then
            name = PageName(db.pages.sel)
        elseif driver:GetAttribute("takeover") ~= 1 then
            local bar = driver:GetAttribute("bar") or 1
            name = bar == 1 and "Action Bar 1" or PageName(db.bars[BAR_KEYS[bar]])
        end
        if name then text = name:upper() .. (ROW_TEXT[row] or "") end
    end
    for _, c in pairs(clusters) do
        c.page:SetText(text)
    end
    PaintPlace()
end

local function OverlayLabel(key)
    if overlay == "SPECIAL" then
        local sp = SPECIAL[key]
        if sp and sp.mark then return "" end -- drawn as a texture instead
        if key == "PAD3" then return db.locked and "Unlock" or "Lock" end
        return sp and sp.label or ""
    end
    if overlay == "PARTY" then
        local sp = SPECIAL[key]
        if sp and sp.unit then return sp.label end
        return ""
    end
    return ""
end

-- party health borders on the special layer. health is secret in combat, so the
-- curve does the thresholds engine side and we just pipe the color into a statusbar
local hpCurve
local function HealthCurve()
    if hpCurve then return hpCurve end
    local black, red = CreateColor(0, 0, 0, 1), CreateColor(1, 0.1, 0.1, 1)
    local yellow, green = CreateColor(1, 0.85, 0.1, 1), CreateColor(0.1, 1, 0.1, 1)
    hpCurve = C_CurveUtil.CreateColorCurve()
    -- tight point pairs = hard steps
    hpCurve:AddPoint(0, black)
    hpCurve:AddPoint(0.005, red)
    hpCurve:AddPoint(0.245, red)
    hpCurve:AddPoint(0.25, yellow)
    hpCurve:AddPoint(0.595, yellow)
    hpCurve:AddPoint(0.6, green)
    hpCurve:AddPoint(1, green)
    return hpCurve
end

-- dispellable debuff -> border color. aura data is secret while restricted
-- (combat, encounters, M+, pvp), only readable outside that
local DISPEL = {
    Magic = { 0.2, 0.6, 1 },
    Curse = { 0.6, 0.2, 1 },
    Poison = { 0.55, 0.35, 0.15 },
    Disease = { 0.55, 0.35, 0.15 },
}

local function DispelColor(unit)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    if not aura or issecretvalue(aura.dispelName) then return end
    return DISPEL[aura.dispelName]
end

local function UpdatePartyHealth()
    local on = overlay == "PARTY"
    for _, b in ipairs(buttons) do
        local sp = b.hp and SPECIAL[b.padKey]
        if sp then
            local style = db.partyHealth or "both"
            if on and UnitExists(sp.unit) and style ~= "off" then
                local color = UnitHealthPercent(sp.unit, true, HealthCurve())
                if ns.debug and not b.hp:IsShown() then
                    ns.Log(string.format("party %s %s: color=%s", b.padKey, sp.unit, type(color)))
                end
                local dispel = DispelColor(sp.unit)
                if dispel then
                    b.hp:SetStatusBarColor(unpack(dispel))
                else
                    b.hp:SetStatusBarColor(color:GetRGB())
                end
                b.hpFill:SetStatusBarColor(color:GetRGB())
                b.hp:SetShown(dispel ~= nil or style == "border" or style == "both")
                b.hpFill:SetShown(style == "fill" or style == "both")
            else
                b.hp:Hide()
                b.hpFill:Hide()
            end
        end
    end
end

-- both triggers, or R1, held: dim the icons and show what each button does instead.
-- select is a plain page now, zoom uses the triggers there so skip the layers
local function UpdateOverlay()
    local shift, ctrl, alt = IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()
    local want = not selectHeld and ((shift and ctrl) and "SPECIAL"
        or (alt and not shift and not ctrl) and "PARTY") or nil
    if want == overlay then return end
    if ns.debug then
        ns.Log(string.format("overlay %s -> %s  shift=%s ctrl=%s alt=%s  group=%s  ALT-PADDUP -> %s",
            tostring(overlay), tostring(want), tostring(shift), tostring(ctrl), tostring(alt),
            tostring(IsInGroup()), tostring(GetBindingAction("ALT-PADDUP", true))))
    end
    overlay = want
    for _, b in ipairs(buttons) do
        local text = overlay and OverlayLabel(b.padKey) or ""
        b.special:SetText(text)
        b.special:SetShown(overlay ~= nil)
        -- party layer only dims the dpad it uses
        local dim = overlay and (overlay ~= "PARTY" or text ~= "")
        if b.icon then b.icon:SetAlpha(dim and 0.3 or 1) end
        if b.mark then
            local n = overlay == "SPECIAL" and db.marks[b.padKey]
            if n then b.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n) end
            b.mark:SetShown(n and true or false)
            -- hide the ability under the marker so it reads clean
            if n and b.icon then b.icon:SetAlpha(0) end
        end
        -- bumper boxes: up arrow while the special layer is held, they open the grids
        if b.side then
            if overlay == "SPECIAL" then
                -- Misc_ArrowLup, the red up arrow spell icon
                b.side.icon:SetTexture(450907)
                b.side.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.side.icon:SetVertexColor(1, 1, 1)
            elseif overlay == "PARTY" and b.padKey == "PADLSHOULDER" then
                -- Misc_ArrowDown: L1 targets yourself while R1 is held
                b.side.icon:SetTexture(450905)
                b.side.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.side.icon:SetVertexColor(1, 1, 1)
            else
                b.side.icon:SetTexture("Interface\\Cursor\\Crosshairs")
                b.side.icon:SetTexCoord(0, 1, 0, 1)
                b.side.icon:SetVertexColor(unpack(b.sideColor))
            end
        end
    end
    UpdatePartyHealth()
    SetPageLabel()
end

-- offsets from screen center in the clusters own scale, same trick as JarsUnitFrames
local function SavePos(c, key)
    local s = c:GetScale()
    local cx, cy = c:GetCenter()
    local ux, uy = UIParent:GetCenter()
    db[key] = { x = cx - ux / s, y = cy - uy / s }
end

local function MirrorFrom(key)
    local other = key == "left" and "right" or "left"
    db[other] = { x = -db[key].x, y = db[key].y }
end

local function DefaultPositions()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    db.left = { x = -(w / 2 - 190), y = -(h / 2 - 230) }
    db.right = { x = w / 2 - 190, y = -(h / 2 - 230) }
end

local function CreateCluster(key, name)
    local f = CreateFrame("Frame", "JarStick" .. name, UIParent)
    f:SetSize(SIZE * 3 + GAP * 2, SIZE * 3 + GAP * 2)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos(self, key)
        if db.mirror then MirrorFrom(key) end
        ApplyLayout()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0.6, 1, 0.25)
    f.bg:Hide()

    f.page = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.page:SetPoint("BOTTOM", f, "TOP", 0, 2)

    f.mode = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.mode:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.mode:SetTextColor(0.2, 1, 0.2)
    return f
end

-- dpad diamond: no action, just the bar number. the picked one is lit by PaintBars
local function CreateBarButton(parent, def)
    local b = CreateFrame("Button", "JarStickBar" .. def.bar, parent, "BackdropTemplate")
    b:EnableMouse(false)
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    b.bar = def.bar
    -- b.icon is what the layers dim, same as the action buttons icon
    b.icon = CreateFrame("Frame", nil, b)
    b.icon:SetAllPoints()
    local bg = b.icon:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    b.num = b.icon:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    b.num:SetPoint("CENTER", 0, -2)
    b.num:SetText(def.bar)
    b.HotKey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    return b
end

local function CreateButton(i, def)
    local parent = clusters[def.cluster]
    local b
    if def.bar then
        b = CreateBarButton(parent, def)
    elseif def.target then
        -- bumper box, the side overlay below is all of it
        b = CreateFrame("Button", "JarStickBumper" .. def.panel, parent)
        b:EnableMouse(false)
        b.HotKey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    else
        b = CreateFrame("CheckButton", "JarStickButton" .. i, parent, "ActionBarButtonTemplate")
        b:SetAttribute("action", i)
        if b.UpdateHotkeys then
            hooksecurefunc(b, "UpdateHotkeys", UpdateGlyph)
        end
    end
    b:SetSize(SIZE, SIZE)
    b:SetPoint("CENTER", parent, "CENTER", def.dx * (SIZE + GAP) / 2, def.dy * (SIZE + GAP))
    b.padKey = def.key
    UpdateGlyph(b)
    b.special = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.special:SetPoint("CENTER")
    b.special:SetWidth(SIZE - 2)
    b.special:SetWordWrap(true)
    b.special:Hide()

    -- dpad buttons: health colored border behind them for the special layer
    if SPECIAL[def.key] and SPECIAL[def.key].unit then
        local hp = CreateFrame("StatusBar", nil, parent)
        hp:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
        hp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
        hp:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))
        hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        hp:SetMinMaxValues(0, 1)
        hp:SetValue(1)
        hp:Hide()
        b.hp = hp

        -- fill: tinted wash over the dimmed icon, under the label
        local fill = CreateFrame("StatusBar", nil, b)
        fill:SetAllPoints()
        fill:SetFrameLevel(b:GetFrameLevel() + 2)
        fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        fill:SetAlpha(0.55)
        fill:Hide()
        b.hpFill = fill
        -- label lives on a frame above the wash so it stays readable
        local top = CreateFrame("Frame", nil, b)
        top:SetAllPoints()
        top:SetFrameLevel(b:GetFrameLevel() + 3)
        b.special:SetParent(top)
        -- raid marker shown big on the slot while L2+R2 are held
        b.mark = top:CreateTexture(nil, "OVERLAY")
        b.mark:SetPoint("CENTER")
        b.mark:SetSize(SIZE - 8, SIZE - 8)
        b.mark:Hide()
    end

    -- bumpers: a colored target marker, always up now that slots live on the triggers
    if def.target then
        local s = CreateFrame("Frame", nil, b)
        s:SetAllPoints()
        s:SetFrameLevel(b:GetFrameLevel() + 5)
        s.bg = s:CreateTexture(nil, "BACKGROUND")
        s.bg:SetAllPoints()
        s.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetPoint("CENTER")
        s.icon:SetSize(SIZE - 10, SIZE - 10)
        s.icon:SetTexture("Interface\\Cursor\\Crosshairs")
        s.icon:SetVertexColor(unpack(def.color))
        s.glyph = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        s.glyph:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
        s.glyph:SetSize(SIZE, 16)
        b.side = s
        b.sideColor = def.color
        UpdateGlyph(b)
    end
    return b
end

-- a 3x4 grid of one spare bar, parented to the cluster so it follows scale and position
local function CreatePanel(side, def)
    local anchorBtn = buttons[def.anchor]
    local f = CreateFrame("Frame", "JarStickPanel" .. side, anchorBtn:GetParent())
    f:SetSize(PCOLS * SIZE + (PCOLS - 1) * GAP, PROWS * SIZE + (PROWS - 1) * GAP)
    if side == "L" then
        f:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 0, GAP * 2)
    else
        f:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, GAP * 2)
    end
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("TOPLEFT", -4, 4)
    f.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    f.bg:SetColorTexture(0, 0, 0, 0.5)
    f.buttons = {}
    for i = 1, PCOLS * PROWS do
        local b = CreateFrame("CheckButton", "JarStickPanel" .. side .. i, f, "ActionBarButtonTemplate")
        b:SetSize(SIZE, SIZE)
        local row, col = math.floor((i - 1) / PCOLS), (i - 1) % PCOLS
        b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (SIZE + GAP), -row * (SIZE + GAP))
        b:SetAttribute("action", (def.page - 1) * 12 + i)
        f.buttons[i] = b
    end
    -- open state is remembered, the secure toggle in Interact.lua does the show/hide
    -- place mode shows both for a bit, that isnt the player opening them
    f:HookScript("OnShow", function()
        if ns.placeMode then return end
        db.panels[side] = true
        if ns.PanelChanged then ns.PanelChanged() end
    end)
    f:HookScript("OnHide", function()
        if ns.placeMode then return end
        db.panels[side] = false
        if ns.PanelChanged then ns.PanelChanged() end
    end)
    f:SetShown(db.panels[side] and true or false)
    return f
end

-- paging --------------------------------------------------------------------

-- bar 1 only: forms, stealth etc. vehicles/possess/skyriding take over every bar
local function PageDriver()
    local p = db.pages
    return "[overridebar][vehicleui][possessbar][shapeshift] possess; " ..
        "[bonusbar:5] " .. (p.b5 == 11 and "dragon" or p.b5) .. "; " ..
        "[bonusbar:4] " .. p.b4 .. "; [bonusbar:3] " .. p.b3 .. "; " ..
        "[bonusbar:2] " .. p.b2 .. "; [bonusbar:1] " .. p.b1 .. "; 1"
end

-- which third of the bar the face buttons show. both triggers = special layer, row 0
local ROW_DRIVER = "[mod:shift,mod:ctrl] 0; [mod:shift] 1; [mod:ctrl] 2; 0"

local function SetBarPages()
    driver:SetAttribute("bar", db.bar or 1) -- profile loads bring their own pick
    for i = 2, 4 do
        driver:SetAttribute("barpage" .. i, db.bars[BAR_KEYS[i]])
    end
    driver:SetAttribute("selpage", db.pages.sel)
end

-- re-run the secure apply from out here, out of combat only
local function ApplyDriver(pre)
    SecureHandlerExecute(driver, (pre or "") .. [[ self:RunAttribute("apply") ]])
end

-- page swaps run in the restricted env so the dpad and L2/R2 work in combat
local function CreateDriver()
    driver = CreateFrame("Frame", "JarStickDriver", UIParent, "SecureHandlerStateTemplate")
    for i = 1, NUM_SLOTS do
        driver:SetFrameRef("button" .. i, buttons[i])
    end
    driver:SetAttribute("nslots", NUM_SLOTS)
    SetBarPages()
    -- select held > vehicle etc > picked bar. L2/R2 shift it by 4 or 8 slots
    driver:SetAttribute("apply", [[
        local bar = self:GetAttribute("bar") or 1
        local page
        if self:GetAttribute("selheld") == 1 then
            page = self:GetAttribute("selpage")
        elseif bar == 1 or self:GetAttribute("takeover") == 1 then
            page = self:GetAttribute("basepage")
        else
            page = self:GetAttribute("barpage" .. bar)
        end
        page = page or 1
        local row = tonumber(self:GetAttribute("state-row")) or 0
        for i = 1, self:GetAttribute("nslots") do
            local button = self:GetFrameRef("button" .. i)
            if button then
                button:SetAttribute("action", (page - 1) * 12 + row * 4 + i)
            end
        end
        self:SetAttribute("curpage", page)
    ]])
    driver:SetAttribute("_onstate-row", [[ self:RunAttribute("apply") ]])
    driver:SetAttribute("_onstate-page", [[
        local page = newstate
        self:SetAttribute("takeover", (page == "possess" or page == "dragon") and 1 or 0)
        if page == "possess" or page == "dragon" then
            if HasVehicleActionBar() then
                page = GetVehicleBarIndex()
            elseif HasOverrideActionBar() then
                page = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar() then
                page = GetTempShapeshiftBarIndex()
            elseif HasBonusActionBar() then
                page = GetBonusBarIndex()
            else
                page = 12
            end
        end
        self:SetAttribute("basepage", tonumber(page) or 1)
        self:RunAttribute("apply")
    ]])
    driver:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "bar" then
            db.bar = value
            PaintBars()
        end
        if name == "curpage" or name == "bar" then SetPageLabel() end
    end)
    RegisterStateDriver(driver, "page", PageDriver())
    RegisterStateDriver(driver, "row", ROW_DRIVER)

    -- the dpad lands here, the binding passes the key as the button
    local pick = CreateFrame("Button", "JarStickBarPick", UIParent, "SecureHandlerClickTemplate")
    pick:RegisterForClicks("AnyDown")
    pick:SetFrameRef("driver", driver)
    pick:SetAttribute("_onclick", [[
        local bar = (button == "PADDUP" and 1) or (button == "PADDRIGHT" and 2)
            or (button == "PADDDOWN" and 3) or (button == "PADDLEFT" and 4)
        if not bar then return end
        local d = self:GetFrameRef("driver")
        d:SetAttribute("bar", bar)
        d:RunAttribute("apply")
    ]])
    PaintBars()
end

local function RefreshPageDriver()
    RunWhenSafe("pagedriver", function()
        if not driver then return end
        SetBarPages()
        UnregisterStateDriver(driver, "page")
        RegisterStateDriver(driver, "page", PageDriver())
        ApplyDriver()
        SetPageLabel()
    end)
end

-- for the book: pick a bar from insecure code, it's out of combat only
local function SetBar(bar)
    if not driver or InCombatLockdown() then return end
    ApplyDriver(("self:SetAttribute('bar', %d)"):format(bar))
end

-- invisible buttons the pad bindings click into
local function CreateHelperButton(name, down, up)
    local b = CreateFrame("Button", name, UIParent)
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT")
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, isDown)
        if isDown then
            down()
        elseif up then
            up()
        end
    end)
    return b
end

-- all non-priority, the interact/menu handler in Interact.lua sits on top with priority ones
ApplyBindings = function()
    RunWhenSafe("bindings", function()
        ClearOverrideBindings(bindOwner)
        local mouseKey = db.mouseStick == "L3" and "PADLSTICK" or "PADRSTICK"
        local jumpKey = db.mouseStick == "L3" and "PADRSTICK" or "PADLSTICK"
        for _, mod in ipairs(MODS) do
            for i, def in ipairs(BUTTONS) do
                local key = mod .. def.key
                local sp = SPECIAL_MODS[mod] and SPECIAL[def.key]
                local party = mod == "ALT-"
                if def.key == "PADLSHOULDER" and (mod == "" or party) then
                    -- L1 goes through JarStickL1 (Wheel.lua): tap = target enemy, with R1 = party ring
                    SetOverrideBindingClick(bindOwner, false, key, "JarStickL1", "LeftButton")
                elseif def.panel and SPECIAL_MODS[mod] then
                    -- L2+R2+bumper toggles that sides spare bar grid
                    SetOverrideBindingClick(bindOwner, false, key, "JarStickPanelToggle" .. def.panel, "LeftButton")
                elseif def.target then
                    SetOverrideBinding(bindOwner, false, key, def.target)
                elseif sp and sp.mark then
                    -- L2+R2 + dpad: toggle a raid marker on the target
                    SetOverrideBindingClick(bindOwner, false, key, "JarStickMark" .. sp.mark, "LeftButton")
                elseif sp and sp.click then
                    SetOverrideBindingClick(bindOwner, false, key, sp.click, "LeftButton")
                elseif sp then
                    SetOverrideBinding(bindOwner, false, key, sp.cmd)
                elseif party and SPECIAL[def.key] and SPECIAL[def.key].unit then
                    -- R1 held: dpad picks party members
                    SetOverrideBinding(bindOwner, false, key, SPECIAL[def.key].cmd)
                elseif def.bar then
                    -- dpad picks the bar, with or without a trigger held
                    SetOverrideBindingClick(bindOwner, false, key, "JarStickBarPick", def.key)
                else
                    SetOverrideBindingClick(bindOwner, false, key, "JarStickButton" .. i, "LeftButton")
                end
            end
            -- same command the Escape key runs
            SetOverrideBinding(bindOwner, false, mod .. "PADFORWARD", "TOGGLEGAMEMENU")
            SetOverrideBindingClick(bindOwner, false, mod .. "PADBACK", "JarStickSelect", "LeftButton")
            SetOverrideBindingClick(bindOwner, false, mod .. mouseKey, "JarStickMouseToggle", "LeftButton")
            SetOverrideBinding(bindOwner, false, mod .. jumpKey, "JUMP")
        end
    end)
end

ApplyLayout = function()
    RunWhenSafe("layout", function()
        -- first run, or the old corner-anchored format
        if not db.left.x or db.left.point or not db.right.x or db.right.point then
            DefaultPositions()
        end
        for key, c in pairs(clusters) do
            local pos = db[key]
            c:SetScale(db.scale)
            c:ClearAllPoints()
            c:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
        end
    end)
end

local function ResetPositions()
    DefaultPositions()
    ApplyLayout()
end

local mover
local function ApplyLock()
    for _, c in pairs(clusters) do
        c:EnableMouse(not db.locked)
        c.bg:SetShown(not db.locked)
    end
    if mover and db.locked then mover:Hide() end
end

-- L2+R2+X: unlocked, the left stick drags the left cluster and the right one mirrors it.
-- the mover eats the movement stick while its up so the character stays put
local moveX, moveY = 0, 0

local function MoveClusters(_, elapsed)
    if moveX * moveX + moveY * moveY < 0.04 then return end
    local s = db.scale
    local step = 400 * elapsed / s
    local hw, hh = UIParent:GetWidth() / 2 / s, UIParent:GetHeight() / 2 / s
    db.left.x = math.max(-hw, math.min(hw, db.left.x + moveX * step))
    db.left.y = math.max(-hh, math.min(hh, db.left.y + moveY * step))
    if db.mirror then MirrorFrom("left") end
    ApplyLayout()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function CreateMover()
    mover = CreateFrame("Frame", "JarStickMover", UIParent)
    mover:Hide()
    mover:EnableGamePadStick(true)
    -- returning true lets the stick through, same as blizzards own stick listener
    mover:SetScript("OnGamePadStick", function(_, stick, x, y)
        if stick ~= "Movement" then return true end
        moveX, moveY = x, y
        return false
    end)
    mover:SetScript("OnUpdate", MoveClusters)
end

local function SetPadMove(on)
    if on and InCombatLockdown() then
        Print("the clusters can't move in combat")
        return
    end
    db.locked = not on
    ApplyLock()
    moveX, moveY = 0, 0
    mover:SetShown(on)
    if overlay == "SPECIAL" then buttons[3].special:SetText(on and "Lock" or "Unlock") end
    Print(on and "clusters unlocked, the left stick moves them. L2 + R2 + X locks" or "clusters locked")
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- hide blizzard bars 1-3, Bartender4 HideBlizzard style. one way per session
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

local function HideBarFrame(frame, clearEvents)
    if not frame then return end
    if clearEvents then
        frame:UnregisterAllEvents()
    end
    if frame.system then
        PurgeKey(frame, "isShownExternal")
    end
    if frame.HideBase then
        frame:HideBase()
    else
        frame:Hide()
    end
    frame:SetParent(UIHider)
end

local function HideBarButton(button)
    if not button then return end
    button:Hide()
    button:UnregisterAllEvents()
    button:SetAttribute("statehidden", true)
    button.bar = nil
end

HideBlizzardBars = function()
    if hiddenBars or not db.hideBlizzard then return end
    RunWhenSafe("hidebars", function()
        if hiddenBars then return end
        hiddenBars = true
        UIHider = CreateFrame("Frame")
        UIHider:Hide()

        HideBarFrame(MainMenuBar, false)   -- <= 11.2.5
        HideBarFrame(MainActionBar, false) -- >= 12.0
        for i = 1, 12 do
            HideBarButton(_G["ActionButton" .. i])
        end
        if MainMenuBar then
            MainMenuBar:UnregisterEvent("PLAYER_REGEN_ENABLED")
            MainMenuBar:UnregisterEvent("PLAYER_REGEN_DISABLED")
            MainMenuBar:UnregisterEvent("ACTIONBAR_SHOWGRID")
            MainMenuBar:UnregisterEvent("ACTIONBAR_HIDEGRID")
        end

        HideBarFrame(MultiBarBottomLeft, true)
        HideBarFrame(MultiBarBottomRight, true)
        for i = 1, 12 do
            HideBarButton(_G["MultiBarBottomLeftButton" .. i])
            HideBarButton(_G["MultiBarBottomRightButton" .. i])
        end
    end)
end

local function ToggleHideBlizzard()
    if db.hideBlizzard then
        HideBlizzardBars()
    elseif hiddenBars then
        Print("Blizzard bars come back after a /reload")
    end
end

ApplyAll = function()
    ApplyCamera()
    ApplyActionCam()
    ApplyLayout()
    ApplyLock()
    ApplyBindings()
    RefreshGlyphs()
    RefreshPageDriver()
    ToggleHideBlizzard()
    if ns.ApplyInteract then ns.ApplyInteract() end
    if ns.UpdateReticle then ns.UpdateReticle() end
end

-- profiles ------------------------------------------------------------------
-- live settings are per character, named profiles are account wide copies

local function CopyTable(src)
    local t = {}
    for k, v in pairs(src) do
        t[k] = type(v) == "table" and CopyTable(v) or v
    end
    return t
end

local function MergeDefaults(t)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            t[k] = t[k] or {}
            for k2, v2 in pairs(v) do
                if t[k][k2] == nil then t[k][k2] = v2 end
            end
        elseif t[k] == nil then
            t[k] = v
        end
    end
end

-- back to a clean slate: blizzard cvars, then JarStick defaults on top
local function ResetAll()
    ResetPadCVars()
    wipe(db)
    MergeDefaults(db)
    ns.charDB.profile = nil
    ApplyPadCVars()
    ApplyDevice()
    ApplyAll()
    Print("controller settings reset to defaults")
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function ProfileNames()
    local names = {}
    for name in pairs(ns.acct.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function SaveProfile(name)
    name = strtrim(name or "")
    if name == "" then
        Print("give the profile a name")
        return false
    end
    ns.acct.profiles[name] = CopyTable(db)
    ns.charDB.profile = name
    Print("profile '" .. name .. "' saved")
    if ns.RefreshConfig then ns.RefreshConfig() end
    return true
end

local function LoadProfile(name)
    name = strtrim(name or "")
    local src = ns.acct.profiles[name]
    if not src then
        Print("no profile called '" .. name .. "'")
        return false
    end
    -- same table, Interact.lua and Config.lua hold a ref to it
    wipe(db)
    for k, v in pairs(CopyTable(src)) do
        db[k] = v
    end
    MergeDefaults(db)
    ns.charDB.profile = name
    ApplyAll()
    Print("profile '" .. name .. "' loaded")
    if ns.RefreshConfig then ns.RefreshConfig() end
    return true
end

local function DeleteProfile(name)
    name = strtrim(name or "")
    if not ns.acct.profiles[name] then
        Print("no profile called '" .. name .. "'")
        return false
    end
    ns.acct.profiles[name] = nil
    if ns.charDB.profile == name then
        ns.charDB.profile = nil
    end
    Print("profile '" .. name .. "' deleted")
    if ns.RefreshConfig then ns.RefreshConfig() end
    return true
end

-- setup ---------------------------------------------------------------------

local function ApplyMarks()
    RunWhenSafe("marks", function()
        for key, sp in pairs(SPECIAL) do
            local m = sp.mark and _G["JarStickMark" .. sp.mark]
            if m then m:SetAttribute("macrotext", "/tm " .. (db.marks[key] or 8)) end
        end
    end)
end

-- select held: the page swap itself is secure (JarStickSelect below), this is the
-- insecure side. camera freezes so the right stick can drive the wheel, triggers zoom
local function OnSelectDown()
    selectHeld = true
    UpdateOverlay()
    SetPageLabel()
    StartZoom()
    if ns.WheelSelect then ns.WheelSelect(true) end
end

local function OnSelectUp()
    selectHeld = false
    UpdateOverlay()
    SetPageLabel()
    StopZoom()
    if ns.WheelSelect then ns.WheelSelect(false) end
end

-- a panel opened from the wheel gets the cursor, closing it takes it away again
local cursorPanel
local function PanelShown(frame)
    if not ns.wheelOpening or not frame or frame == cursorPanel then return end
    cursorPanel = frame
    if not frame.jarstickHooked then
        frame.jarstickHooked = true
        frame:HookScript("OnHide", function(self)
            if cursorPanel == self then
                cursorPanel = nil
                SetMouseMode(false)
            end
        end)
    end
    SetMouseMode(true)
end

local function HookPanels()
    hooksecurefunc("ShowUIPanel", PanelShown)
    -- bags and the game menu dont go through the panel manager
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1", "GameMenuFrame" }) do
        local f = _G[name]
        if f then
            f:HookScript("OnShow", PanelShown)
        end
    end
end

local function Init()
    clusters.left = CreateCluster("left", "Left")
    clusters.right = CreateCluster("right", "Right")
    for i, def in ipairs(BUTTONS) do
        buttons[i] = CreateButton(i, def)
    end
    ns.panels = {}
    for side, def in pairs(PANELS) do
        ns.panels[side] = CreatePanel(side, def)
    end

    bindOwner = CreateFrame("Frame", "JarStickBindings", UIParent)

    -- special layer B: favorite mount, or dismount
    local mount = CreateFrame("Button", "JarStickMount", UIParent, "SecureActionButtonTemplate")
    mount:SetAttribute("type", "macro")
    mount:SetAttribute("macrotext", MOUNT_MACRO)
    mount:RegisterForClicks("AnyDown")

    -- raid markers for the special layer dpad, /tm toggles it on the target
    for key, sp in pairs(SPECIAL) do
        if sp.mark then
            local m = CreateFrame("Button", "JarStickMark" .. sp.mark, UIParent, "SecureActionButtonTemplate")
            m:SetAttribute("type", "macro")
            m:RegisterForClicks("AnyDown")
            m.padKey = key
        end
    end
    ApplyMarks()

    CreateHelperButton("JarStickMouseToggle", ToggleMouseMode)
    -- L2+R2 face buttons
    CreateHelperButton("JarStickBookSpells", function() ns.ToggleBook("spells") end)
    CreateHelperButton("JarStickBookTalents", function() ns.ToggleBook("talents") end)
    CreateHelperButton("JarStickPadMove", function() SetPadMove(db.locked) end)
    CreateMover()
    zoomer = CreateFrame("Frame")
    zoomer:Hide()
    zoomer:SetScript("OnUpdate", ZoomOnUpdate)

    CreateDriver()

    -- select: flips the driver to the select page in the restricted env, so it works in combat
    local sel = CreateFrame("Button", "JarStickSelect", UIParent, "SecureHandlerClickTemplate")
    sel:RegisterForClicks("AnyDown", "AnyUp")
    sel:SetFrameRef("driver", driver)
    sel:SetAttribute("_onclick", [[
        local d = self:GetFrameRef("driver")
        d:SetAttribute("selheld", down and 1 or 0)
        d:RunAttribute("apply")
        -- start backs out of the wheel while select is held
        if down then
            self:SetBindingClick(true, "PADFORWARD", "JarStickWheelCancel", "LeftButton")
        else
            self:ClearBindings()
        end
    ]])
    sel:HookScript("OnClick", function(_, _, down)
        if down then OnSelectDown() else OnSelectUp() end
    end)
    ApplyLayout()
    ApplyLock()
    ApplyBindings()
    HookPanels()
    C_Timer.NewTicker(0.25, function()
        UpdateModeLabel()
        UpdateOverlay()
    end)
    C_Timer.NewTicker(0.1, function() CheckEmulation(0.1) end)
    -- live while the layer is held
    C_Timer.NewTicker(0.1, function()
        if overlay == "PARTY" then UpdatePartyHealth() end
    end)
    -- L1 is bound to the ring's button, so it has to exist as soon as the bindings do
    if ns.InitRing then ns.InitRing() end
    if ns.InitInteract then
        local fn = ns.InitInteract
        ns.InitInteract = nil
        fn()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("GAME_PAD_CONNECTED")
events:RegisterEvent("GAME_PAD_DISCONNECTED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("LFG_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns.acct.profiles = ns.acct.profiles or {}
        ns.charDB.settings = ns.charDB.settings or {}
        db = ns.charDB.settings
        -- first versions kept settings account wide, carry them over once.
        -- these are meant to live account wide though, stickBase holds the real stick scales
        local ACCOUNT_KEYS = { profiles = true, padReport = true, debugLog = true, stickBase = true, imported = true }
        if next(db) == nil then
            for k, v in pairs(ns.acct) do
                if not ACCOUNT_KEYS[k] then db[k] = v end
            end
        end
        for k in pairs(ns.acct) do
            -- if k ~= "profiles" and k ~= "padReport" and k ~= "debugLog" then ns.acct[k] = nil end
            if not ACCOUNT_KEYS[k] then ns.acct[k] = nil end
        end
        MergeDefaults(db)
        -- select menu became the wheel, L2/R2 pages became the dpad bars
        db.selectMenu = nil
        db.pages.l2, db.pages.r2 = nil, nil
        ns.db = db
        RunWhenSafe("init", Init)
    elseif event == "PLAYER_LOGIN" then
        ApplyPadCVars()
        ApplyDevice()
        ApplyActionCam(true)
        HideBlizzardBars()
    elseif event == "CVAR_UPDATE" then
        -- something else changed one of our pad cvars (queueing for a dungeon reset the
        -- alt emulation on Jar's client), say who and put it back
        local want = PAD_CVARS[arg1]
        if db and not rearming and want ~= nil and tostring(C_CVar.GetCVar(arg1)) ~= tostring(want) then
            Log(arg1 .. " changed to " .. tostring(C_CVar.GetCVar(arg1)) .. ", setting it back to " .. tostring(want))
            C_Timer.After(0, function() C_CVar.SetCVar(arg1, tostring(want)) end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "LFG_UPDATE" then
        -- belt and braces: re-assert the cvars we own
        if db then
            for cvar, value in pairs(PAD_CVARS) do
                if tostring(C_CVar.GetCVar(cvar)) ~= tostring(value) then
                    if ns.debug then Log(event .. ": " .. cvar .. " was " .. tostring(C_CVar.GetCVar(cvar))) end
                    C_CVar.SetCVar(cvar, tostring(value))
                end
            end
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if #buttons > 0 then UpdateOverlay() end
    elseif event == "GAME_PAD_CONNECTED" or event == "GAME_PAD_DISCONNECTED" then
        -- ids can shuffle on a replug, give the list a second to settle
        C_Timer.After(1, ApplyDevice)
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushSafeQueue()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- last chance before lockdown, the clusters cant move in combat
        if mover and mover:IsShown() then SetPadMove(false) end
    end
end)

-- for Interact.lua and Config.lua
ns.RunWhenSafe = RunWhenSafe
ns.ApplyCamera = ApplyCamera
ns.ApplyActionCam = ApplyActionCam
ns.ApplyObjectIcon = ApplyObjectIcon
ns.ApplyBindings = ApplyBindings
ns.ApplyMarks = ApplyMarks
ns.ApplyLayout = ApplyLayout
ns.MirrorFrom = MirrorFrom
ns.ResetPositions = ResetPositions
ns.ApplyLock = ApplyLock
ns.RefreshGlyphs = RefreshGlyphs
ns.RefreshPageDriver = RefreshPageDriver
ns.PageName = PageName
ns.ToggleHideBlizzard = ToggleHideBlizzard
ns.ResetPadCVars = ResetPadCVars
ns.ToggleMouseMode = ToggleMouseMode
ns.GetLockActionBars = GetLockActionBars
ns.SetLockActionBars = SetLockActionBars
ns.GetForceXInput = GetForceXInput
ns.SetForceXInput = SetForceXInput
ns.DeviceList = DeviceList
ns.ApplyDevice = ApplyDevice
ns.PadReport = PadReport
ns.ResetAll = ResetAll
ns.ProfileNames = ProfileNames
ns.SaveProfile = SaveProfile
ns.LoadProfile = LoadProfile
ns.DeleteProfile = DeleteProfile
ns.CurrentProfile = function() return ns.charDB.profile end
ns.Print = Print

-- for Book.lua and Wheel.lua
ns.buttons = buttons
ns.BUTTON_KEYS = {}
ns.KEY_INDEX = {}
for i, def in ipairs(BUTTONS) do
    ns.BUTTON_KEYS[i] = def.key
    ns.KEY_INDEX[def.key] = i
end
ns.PANEL_DEFS = PANELS
ns.NUM_SLOTS = NUM_SLOTS
ns.BAR_KEYS = BAR_KEYS
ns.BAR_INDEX = {}
for i, key in ipairs(BAR_KEYS) do ns.BAR_INDEX[key] = i end
ns.SetBar = SetBar
ns.CurPage = function() return driver and driver:GetAttribute("curpage") or 1 end
ns.CurRow = function() return driver and tonumber(driver:GetAttribute("state-row")) or 0 end
-- dpad key that shows this page, nil if none does
ns.BarKeyForPage = function(page)
    if page == 1 or (driver and page == driver:GetAttribute("basepage") and driver:GetAttribute("takeover") ~= 1) then
        return "PADDUP"
    end
    for i = 2, 4 do
        if db.bars[BAR_KEYS[i]] == page then return BAR_KEYS[i] end
    end
end
ns.SelectHeld = function() return selectHeld end
ns.HealthCurve = HealthCurve
ns.DispelColor = DispelColor

local panelWas
ns.SetPlaceMode = function(mode)
    if mode and not ns.placeMode then
        panelWas = { L = ns.panels.L:IsShown(), R = ns.panels.R:IsShown() }
        ns.placeMode = mode
        ns.panels.L:Show()
        ns.panels.R:Show()
    elseif not mode and ns.placeMode then
        ns.placeMode = nil
        for side, p in pairs(ns.panels) do p:SetShown(panelWas[side]) end
    else
        ns.placeMode = mode
    end
    PaintPlace()
end

-- the party ring wants the right stick too
ns.FreezeCamera = function(on)
    cameraFrozen = on
    if on then
        C_CVar.SetCVar("GamePadCameraYawSpeed", "0")
        C_CVar.SetCVar("GamePadCameraPitchSpeed", "0")
    elseif not zoomer:IsShown() then
        ApplyCamera()
    end
end

ns.SlashCommand = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ApplyLock()
        Print(db.locked and "clusters locked" or "clusters unlocked, drag them with the mouse")
    elseif cmd == "mouse" then
        ToggleMouseMode()
    elseif cmd == "reset" then
        ResetPadCVars()
    elseif cmd == "resetall" then
        ResetAll()
    elseif cmd == "pad" then
        PadReport()
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        ns.acct.debugLog = {}
        Print("debug " .. (ns.debug and "on: prints interact/menu state changes, saved on /reload" or "off"))
    elseif cmd == "ring" then
        if ns.TestRing then ns.TestRing() end
    elseif cmd == "book" or cmd == "spells" then
        ns.ToggleBook("spells")
    elseif cmd == "talents" then
        ns.ToggleBook("talents")
    elseif cmd == "ui" then
        if ns.UIReport then ns.UIReport() end
    elseif cmd == "save" then
        SaveProfile(rest)
    elseif cmd == "load" then
        LoadProfile(rest)
    elseif cmd == "delete" then
        DeleteProfile(rest)
    elseif cmd == "list" then
        local names = ProfileNames()
        Print(#names > 0 and ("profiles: " .. table.concat(names, ", ")) or "no saved profiles")
    else
        ns.OpenSettings()
    end
end

ns.loadHooks[#ns.loadHooks + 1] = function() events:GetScript("OnEvent")(events, "ADDON_LOADED", ADDON) end
end
