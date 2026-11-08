-- Itsu:UI: keyboard bars or controller, one at a time.
-- both use the same action slots, so each mode keeps its own copy of what was in them.
-- every character remembers the mode it last played. log in under the other mode
-- (or switch, which reloads) and its slots get saved for the old mode and the new
-- mode's copy goes back in. nothing is touched when the mode didnt change

local _, ns = ...

-- pages 11-12 (121-144) are skyriding and possess, the game fills those itself
local function Slots()
    local s = {}
    for slot = 1, 180 do
        if slot < 121 or slot > 144 then s[#s + 1] = slot end
    end
    return s
end
local SLOTS = Slots()

function ns.BarMode()
    return ns.db.modules.controller and "controller" or "bars"
end

-- what a slot holds, in a form that still means the same thing after a relog
local function ReadSlot(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not kind then return false end
    if kind == "macro" then
        -- macro indexes shift when macros are added, names dont
        local name = GetMacroInfo(id)
        return name and { kind = kind, name = name } or false
    elseif kind == "summonmount" then
        local _, spellID = C_MountJournal.GetMountInfoByID(id)
        return spellID and { kind = "spell", id = spellID } or false
    end
    return { kind = kind, id = id, sub = sub }
end

local function Same(a, b)
    if not a or not b then return not a and not b end
    return a.kind == b.kind and a.id == b.id and a.name == b.name
end

local function FlyoutSlot(flyoutID)
    local bank = Enum.SpellBookSpellBank.Player
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
            local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
            if info and info.itemType == Enum.SpellBookItemType.Flyout and info.actionID == flyoutID then
                return slot
            end
        end
    end
end

local function PickupSaved(e)
    if e.kind == "spell" then
        C_Spell.PickupSpell(e.id)
    elseif e.kind == "item" then
        C_Item.PickupItem(e.id)
    elseif e.kind == "macro" then
        local idx = GetMacroIndexByName(e.name)
        if idx and idx > 0 then PickupMacro(idx) end
    elseif e.kind == "equipmentset" then
        C_EquipmentSet.PickupEquipmentSet(e.id)
    elseif e.kind == "summonpet" and C_PetJournal then
        C_PetJournal.PickupPet(e.id)
    elseif e.kind == "flyout" then
        local slot = FlyoutSlot(e.id)
        if slot then C_SpellBook.PickupSpellBookItem(slot, Enum.SpellBookSpellBank.Player) end
    end
end

-- retail keeps action bars per spec, so a copy per spec
local function SpecKey()
    local idx = C_SpecializationInfo.GetSpecialization()
    local specID = idx and C_SpecializationInfo.GetSpecializationInfo(idx)
    return tostring(specID or 0)
end

local function SaveLayout(mode)
    ns.char.layouts = ns.char.layouts or {}
    local byMode = ns.char.layouts[mode] or {}
    ns.char.layouts[mode] = byMode
    local t = {}
    for _, slot in ipairs(SLOTS) do t[slot] = ReadSlot(slot) end
    byMode[SpecKey()] = t
end

-- false when this mode has nothing saved yet, the slots just carry over then
local function RestoreLayout(mode)
    local byMode = ns.char.layouts and ns.char.layouts[mode]
    local saved = byMode and byMode[SpecKey()]
    if not saved then return false end
    ClearCursor()
    for _, slot in ipairs(SLOTS) do
        local want = saved[slot]
        if not Same(want, ReadSlot(slot)) then
            if want then
                PickupSaved(want)
                -- whatever was in the slot comes back on the cursor, drop it
                if GetCursorInfo() then PlaceAction(slot) end
            end
            -- should be empty, or the saved thing is gone (spell unlearned, macro deleted)
            if not Same(want, ReadSlot(slot)) and GetActionInfo(slot) then PickupAction(slot) end
            ClearCursor()
        end
    end
    return true
end

-- the mode each spec's bars were last laid out for. a spec not seen yet still has
-- whatever it had before tracking started (barModeStart)
local function SwapIfModeChanged()
    ns.RunWhenSafe("barmode", function()
        local mode, key = ns.BarMode(), SpecKey()
        local char = ns.char
        char.barModeBySpec = char.barModeBySpec or {}
        char.barModeStart = char.barModeStart or char.barMode or mode
        local last = char.barModeBySpec[key] or char.barModeStart
        if last ~= mode then
            SaveLayout(last)
            if RestoreLayout(mode) then
                print("|cffff8c00Itsu:UI|r " .. (mode == "controller" and "controller" or "keyboard") .. " action bars put back")
            end
        end
        char.barModeBySpec[key] = mode
        char.barMode = mode
    end)
end

-- the switch itself is just the module flags and a reload, the swap happens on the way back in
function ns.SetBarMode(mode)
    if mode == ns.BarMode() then return end
    if InCombatLockdown() then
        print("|cffff8c00Itsu:UI|r can't switch bars in combat")
        return
    end
    ns.db.modules.bars = mode == "bars"
    ns.db.modules.controller = mode == "controller"
    ReloadUI()
end

StaticPopupDialogs.JARFOREVER_BARMODE = {
    text = "Switch to %s? This reloads the UI. Each mode keeps its own action bar layout.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data) ns.SetBarMode(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function ns.AskBarMode(mode)
    if mode == ns.BarMode() then return end
    StaticPopup_Show("JARFOREVER_BARMODE", mode == "controller" and "controller mode" or "keyboard bars", nil, mode)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
-- a spec (or dual spec group) swap loads that spec's own bars, they might still be the other mode's
ev:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
ev:SetScript("OnEvent", function(self, event, isLogin, isReload)
    if event == "PLAYER_ENTERING_WORLD" then
        if not (isLogin or isReload) then return end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
    -- action slot info isnt always there right away, after a login or a swap
    C_Timer.After(2, SwapIfModeChanged)
end)
