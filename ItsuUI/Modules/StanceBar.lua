-- Itsu:UI: stance bar (stances, forms, auras...), replaces blizz's

local _, ns = ...

ns.RegisterModule("stance", "Stance Bar", function()

local DB = ns.db.stance
local LibKeyBound = LibStub("LibKeyBound-1.0")
local DEFAULTS = {
    size = 30,
    padding = 4,
    vertical = false,
    x = 0,
    y = 186, -- just above the action bars
    showKeybinds = true,
}
for k, v in pairs(DEFAULTS) do
    if DB[k] == nil then DB[k] = v end
end

local MAX_FORMS = 10 -- blizz's bar has 10 too
local bar
local buttons = {}

local function UpdateState()
    for i = 1, math.min(GetNumShapeshiftForms(), MAX_FORMS) do
        local btn = buttons[i]
        local texture, isActive, isCastable = GetShapeshiftFormInfo(i)
        local shade = isCastable and 1 or 0.4
        btn.icon:SetTexture(texture)
        btn.icon:SetVertexColor(shade, shade, shade)
        btn.border:SetColorTexture(unpack(isActive and ns.UI.accent or ns.UI.border))
        CooldownFrame_Set(btn.cooldown, GetShapeshiftFormCooldown(i))
    end
end

local function UpdateHotkeys()
    for i, btn in ipairs(buttons) do
        local key = DB.showKeybinds and GetBindingKey("SHAPESHIFTBUTTON" .. i)
        btn.hotkey:SetFont(ns.GetFont(), math.max(8, DB.size * 0.3), "OUTLINE")
        btn.hotkey:SetText(key and GetBindingText(key, 1) or "")
    end
end

-- anything secure in here, so it waits for combat to end
local function ApplyLayout()
    ns.RunWhenSafe("stance", function()
        local unlocked = ns.db.general.unlocked
        local numForms = math.min(GetNumShapeshiftForms(), MAX_FORMS)
        local pitch = DB.size + DB.padding
        local length = math.max(numForms * pitch - DB.padding, 1)

        bar:ClearAllPoints()
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", DB.x, DB.y)
        bar:SetSize(DB.vertical and DB.size or length, DB.vertical and length or DB.size)
        bar:EnableMouse(unlocked)
        bar.unlockBox:SetShown(unlocked and numForms > 0)
        bar.label:SetShown(unlocked and numForms > 0)

        for i, btn in ipairs(buttons) do
            btn:SetShown(i <= numForms)
            if i <= numForms then
                local _, _, _, spellID = GetShapeshiftFormInfo(i)
                local offset = (i - 1) * pitch
                btn:SetSize(DB.size, DB.size)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", bar, "TOPLEFT", DB.vertical and 0 or offset, DB.vertical and -offset or 0)
                btn:SetAttribute("spell", spellID)
                -- out of the way while unlocked so the whole bar drags, bind mode still needs the hover
                btn:EnableMouse(not (unlocked and not LibKeyBound:IsShown()))
            end
        end
    end)
end

local function UpdateAll()
    ApplyLayout()
    UpdateState()
    UpdateHotkeys()
end
ns.OnShared(function()
    if bar then UpdateAll() end
end)

-- same hooks the action bar buttons give LibKeyBound
local function AddKeybindSupport(btn, i)
    local command = "SHAPESHIFTBUTTON" .. i

    btn.GetBindingAction = function() return command end
    btn.GetActionName = function() return "Stance Button " .. i end
    btn.GetHotkey = function()
        local key = GetBindingKey(command)
        return key and GetBindingText(key, 1) or ""
    end
    btn.GetBindings = function()
        local keys = {}
        for k = 1, select("#", GetBindingKey(command)) do
            keys[k] = GetBindingText((select(k, GetBindingKey(command))))
        end
        return #keys > 0 and table.concat(keys, ", ") or nil
    end
    btn.SetKey = function(_, key)
        local result = SetBinding(key, command)
        UpdateHotkeys()
        return result
    end
    btn.ClearBindings = function()
        while GetBindingKey(command) do
            SetBinding(GetBindingKey(command), nil)
        end
        UpdateHotkeys()
    end
end

local function CreateButton(i)
    local btn = CreateFrame("Button", "JarForeverStanceButton" .. i, bar, "SecureActionButtonTemplate")
    btn:SetAttribute("type", "spell")
    -- both so it fires w/ the cast on key down setting on or off
    btn:RegisterForClicks("AnyUp", "AnyDown")

    btn.border = btn:CreateTexture(nil, "BACKGROUND")
    btn.border:SetAllPoints()

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.cooldown = CreateFrame("Cooldown", "JarForeverStanceButton" .. i .. "Cooldown", btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn.icon)

    btn.hotkey = btn.cooldown:CreateFontString(nil, "OVERLAY")
    btn.hotkey:SetFont(ns.GetFont(), 9, "OUTLINE")
    btn.hotkey:SetPoint("TOPRIGHT", -1, -2)

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    AddKeybindSupport(btn, i)
    btn:SetScript("OnEnter", function(self)
        if LibKeyBound:IsShown() then
            LibKeyBound:Set(self)
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetShapeshift(i)
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function CreateBar()
    bar = CreateFrame("Frame", "JarForeverStanceBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked and not InCombatLockdown() then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- measure back from bottom center so it stays put at other resolutions
        DB.x = math.floor(self:GetCenter() - UIParent:GetWidth() / 2 + 0.5)
        DB.y = math.floor(self:GetBottom() + 0.5)
        ApplyLayout()
        ns.RefreshPanel("Stance Bar")
    end)

    bar.unlockBox = bar:CreateTexture(nil, "BACKGROUND")
    bar.unlockBox:SetPoint("TOPLEFT", -2, 2)
    bar.unlockBox:SetPoint("BOTTOMRIGHT", 2, -2)
    bar.unlockBox:SetColorTexture(0, 1, 0, 0.3)

    bar.label = bar:CreateFontString(nil, "OVERLAY")
    bar.label:SetFont(ns.GetFont(), 11, "OUTLINE")
    bar.label:SetTextColor(0, 1, 0)
    bar.label:SetPoint("BOTTOM", bar, "TOP", 0, 4)
    bar.label:SetText("Stance Bar")

    for i = 1, MAX_FORMS do buttons[i] = CreateButton(i) end

    -- same rule blizz uses, gone in vehicles etc
    RegisterStateDriver(bar, "visibility", "[vehicleui][possessbar][overridebar] hide; show")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ns.RunWhenSafe("stancebuild", function()
            -- keybinds still work, they go thru StanceBar:Select and not its buttons
            ns.HideBlizzardBar(StanceBar, true)
            CreateBar()
            UpdateAll()
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
            self:RegisterEvent("SPELLS_CHANGED")
            self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
            self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
            self:RegisterEvent("UPDATE_SHAPESHIFT_USABLE")
            self:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
            self:RegisterEvent("UPDATE_BINDINGS")
            LibKeyBound.RegisterCallback(bar, "LIBKEYBOUND_ENABLED", ApplyLayout)
            LibKeyBound.RegisterCallback(bar, "LIBKEYBOUND_DISABLED", ApplyLayout)
        end)
    elseif event == "UPDATE_BINDINGS" then
        UpdateHotkeys()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_USABLE" or event == "UPDATE_SHAPESHIFT_COOLDOWN" then
        UpdateState()
    else
        UpdateAll()
    end
end)

ns.RegisterPanel(27, "Stance Bar", function(b)
    local function Look(key)
        return function() return DB[key] end,
            function(v) DB[key] = v; UpdateAll() end
    end

    b:Text("Stances, forms, auras etc. Only shows on classes that have them.")
    -- b:Text("Keys are set in Blizzard's keybind menu, in the Action Bars section.")
    local keybindText = "Set Keybinds"
    local row = b:Buttons({
        { keybindText, function() LibKeyBound:Toggle() end, 160, key = "keybind" },
    })
    LibKeyBound.RegisterCallback(row.keybind, "LIBKEYBOUND_ENABLED", function()
        row.keybind.label:SetText("Exit Keybind Mode")
    end)
    LibKeyBound.RegisterCallback(row.keybind, "LIBKEYBOUND_DISABLED", function()
        row.keybind.label:SetText(keybindText)
    end)

    b:Header("Size + Position")
    b:Slider("Button Size", 20, 60, 1, Look("size"))
    b:Slider("Button Padding", 0, 20, 1, Look("padding"))
    b:Toggle("Orientation", { { "Horizontal", false }, { "Vertical", true } }, Look("vertical"))
    b:Slider("Left / Right", -1000, 1000, 1, Look("x"))
    b:Slider("Up From Bottom", 0, 1200, 1, Look("y"))
    b:Text("Or turn on Unlock Frames in General and drag it.")

    b:Header("Text")
    b:Check("Show keybinds", Look("showKeybinds"))
end)

end)
