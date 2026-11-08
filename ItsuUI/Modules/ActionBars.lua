-- Itsu:UI: G13 / Keyzen / traditional action bars + focus bars

local _, ns = ...

ns.RegisterModule("bars", "Action Bars", function()

local JarsG13BarsDB = ns.db.bars
local JarsG13BarsCharDB = ns.char.bars

-- Libraries
local LibKeyBound = LibStub and LibStub("LibKeyBound-1.0", true)

-- Configuration
local PRIMARY_SIZE = 80      -- 100% size for 3x2 grid
local SIDE_SIZE = 52         -- 66% of primary (0.66 * 80 = 52.8 ≈ 52)
local BOTTOM_SIZE = 40       -- 50% of primary (doubled from 20)
local PADDING = 6            -- Padding between buttons
local SNAP_DISTANCE = 20     -- Distance to snap to center

-- Profile system
local MAX_LAYOUTS = 100
local currentLayoutName = nil
local activeProfile = {}

-- Focus bar profile system (independent of main G13 profiles)
local MAX_FOCUS_LAYOUTS = 100
local NUM_FOCUS_BARS = 2
local currentFocusLayoutName = { nil, nil }
local activeFocusProfile = { {}, {} }

-- Frame references
local mainFrame
local buttons = {}
local focusRowFrame = {}
local focusRowButtons = { {}, {} }

local RunWhenSafe = ns.RunWhenSafe

-- Secure state driver for combat-safe action bar page swapping.
-- Uses WoW's restricted environment so page changes work even in combat.
local stateDriverFrame

-- possess/override/vehicle resolved in the snippet, same as Bartender4
local function GetPageDriverString()
    local pm = activeProfile.pageMap or {}
    local b5 = pm.b5 or 11
    return "[overridebar][vehicleui][possessbar][shapeshift] possess; " ..
        "[bonusbar:5] " .. (b5 == 11 and "dragon" or b5) .. "; " ..
        "[bonusbar:4] " .. (pm.b4 or 10) .. "; " ..
        "[bonusbar:3] " .. (pm.b3 or 9) .. "; " ..
        "[bonusbar:2] " .. (pm.b2 or 8) .. "; " ..
        "[bonusbar:1] " .. (pm.b1 or 7) .. "; " ..
        "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1"
end

local function SetupSecurePageDriver()
    stateDriverFrame = CreateFrame("Frame", "JG13_StateDriver", UIParent, "SecureHandlerStateTemplate")

    -- Register frame refs so the restricted snippet can access buttons 1-12
    for i = 1, 12 do
        stateDriverFrame:SetFrameRef("button" .. i, buttons[i])
    end

    -- Restricted Lua snippet executed on every state change (works in combat)
    stateDriverFrame:SetAttribute("_onstate-page", [[
        local page = newstate
        if newstate == "possess" or newstate == "dragon" then
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
        page = tonumber(page) or 1

        for i = 1, 12 do
            local button = self:GetFrameRef("button" .. i)
            if button then
                button:SetAttribute("action", (page - 1) * 12 + i)
            end
        end
    ]])

    RegisterStateDriver(stateDriverFrame, "page", GetPageDriverString())
end

local function RefreshStateDriver()
    RunWhenSafe("driver", function()
        if not stateDriverFrame then return end
        UnregisterStateDriver(stateDriverFrame, "page")
        RegisterStateDriver(stateDriverFrame, "page", GetPageDriverString())
    end)
end

-- Create a default profile with all look/feel settings
local function CreateDefaultProfile()
    return {
        positionY = 327, -- top lines up with the unit frames
        bgOpacity = 0,
        showKeybinds = true,
        scale = 0.55,
        layoutMode = "G13",
        frameAlpha = 1.0,
        hideOnMouseOut = false,
        pageMap = { b1=7, b2=8, b3=9, b4=10, b5=11 },
        hideBars = {
            MainMenuBar = true,
            MainActionBar = true,
            MultiBarBottomLeft = true,
            MultiBarBottomRight = true,
            MultiBarRight = true,
            MultiBarLeft = true,
            MultiBar5 = true,
            MultiBar6 = true,
            MultiBar7 = true,
        },
    }
end

-- Deep copy a profile table
local function CopyProfile(src)
    local copy = {
        positionY = src.positionY or 327,
        bgOpacity = src.bgOpacity or 0,
        showKeybinds = src.showKeybinds ~= false,
        scale = src.scale or 0.55,
        layoutMode = src.layoutMode or "G13",
        frameAlpha = src.frameAlpha or 1.0,
        hideOnMouseOut = src.hideOnMouseOut or false,
        hideBars = {},
        pageMap = {},
    }
    if src.hideBars then
        for k, v in pairs(src.hideBars) do
            copy.hideBars[k] = v
        end
    end
    local defPageMap = { b1=7, b2=8, b3=9, b4=10, b5=11 }
    if src.pageMap then
        for k, v in pairs(src.pageMap) do copy.pageMap[k] = v end
    end
    for k, v in pairs(defPageMap) do
        if copy.pageMap[k] == nil then copy.pageMap[k] = v end
    end
    return copy
end

-- Get current spec ID (returns 0 if not available)
local function GetCurrentSpecID()
    local spec = C_SpecializationInfo.GetSpecialization()
    if spec then
        return C_SpecializationInfo.GetSpecializationInfo(spec) or 0
    end
    return 0
end

-- Get current spec name
local function GetCurrentSpecName()
    local spec = C_SpecializationInfo.GetSpecialization()
    if spec then
        local _, name = C_SpecializationInfo.GetSpecializationInfo(spec)
        return name or "Unknown"
    end
    return "Unknown"
end

-- Forward declarations for profile UI refresh
local RefreshConfigUI
local RefreshFocusConfigUI = {}

-- Count saved layouts
local function CountLayouts()
    local count = 0
    for _ in pairs(JarsG13BarsDB.layouts) do
        count = count + 1
    end
    return count
end

-- Get sorted layout names
local function GetSortedLayoutNames()
    local names = {}
    for name in pairs(JarsG13BarsDB.layouts) do
        tinsert(names, name)
    end
    table.sort(names)
    return names
end

-- Apply the active profile to the live UI
local ApplyG13Layout     -- forward declaration (defined below)
local ApplyKeyzenLayout  -- forward declaration (defined below)
local ApplyTraditionalLayout
local HideDefaultBars    -- forward declaration (defined below)

local function ApplyLayoutMode()
    RunWhenSafe("layout", function()
        if not mainFrame then return end
        if activeProfile.layoutMode == "Keyzen" then
            ApplyKeyzenLayout(mainFrame)
        elseif activeProfile.layoutMode == "Traditional" then
            ApplyTraditionalLayout(mainFrame)
        else
            ApplyG13Layout(mainFrame)
        end
    end)
end

-- fade check, throttled so its not every frame
local function MouseOutOnUpdate(self, elapsed)
    self.fadeElapsed = (self.fadeElapsed or 0) + elapsed
    if self.fadeElapsed < 0.1 then return end
    self.fadeElapsed = 0
    -- the traditional grid hangs past the frame, so the buttons count too
    local over = self:IsMouseOver()
    for i = 1, 24 do
        if over then break end
        over = buttons[i] and buttons[i]:IsMouseOver()
    end
    if over then
        self:SetAlpha(activeProfile.frameAlpha or 1.0)
    else
        self:SetAlpha(0)
    end
end

local function SetMouseOutFade(frame)
    if activeProfile.hideOnMouseOut then
        frame:SetAlpha(0)
        frame:SetScript("OnUpdate", MouseOutOnUpdate)
    else
        frame:SetAlpha(activeProfile.frameAlpha or 1.0)
        frame:SetScript("OnUpdate", nil)
    end
end

local function ApplyActiveProfile()
    if not mainFrame then return end

    -- Background opacity
    if mainFrame.bg then
        mainFrame.bg:SetColorTexture(0, 0, 0, activeProfile.bgOpacity or 0)
    end

    -- Frame alpha + hide on mouse out
    SetMouseOutFade(mainFrame)

    RunWhenSafe("profile", function()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, activeProfile.positionY or 327)
        mainFrame:SetScale(activeProfile.scale or 0.55)
    end)

    ApplyLayoutMode()
    RefreshStateDriver()
end

-- Persist the current in-memory profile back to SavedVariables
local function PersistActiveProfile()
    if currentLayoutName and JarsG13BarsDB.layouts[currentLayoutName] then
        JarsG13BarsDB.layouts[currentLayoutName] = CopyProfile(activeProfile)
    else
        -- no named layout, keep it as the unnamed current one
        JarsG13BarsDB.currentProfile = CopyProfile(activeProfile)
    end
end

-- Save current active profile as a named layout
local function SaveLayout(name)
    if not name or name == "" then
        print("|cffff8c00Itsu:UI|r Please enter a layout name.")
        return false
    end

    if CountLayouts() >= MAX_LAYOUTS and not JarsG13BarsDB.layouts[name] then
        print("|cffff8c00Itsu:UI|r Maximum " .. MAX_LAYOUTS .. " layouts reached.")
        return false
    end

    JarsG13BarsDB.layouts[name] = CopyProfile(activeProfile)
    currentLayoutName = name
    JarsG13BarsDB.lastActiveLayout = name

    local specID = GetCurrentSpecID()
    if specID and specID > 0 then
        JarsG13BarsDB.specAssociations[specID] = name
    end

    print("|cffff8c00Itsu:UI|r Layout '" .. name .. "' saved" ..
        (specID and specID > 0 and (" for " .. GetCurrentSpecName()) or "") .. ".")
    if RefreshConfigUI then RefreshConfigUI() end
    return true
end

-- Load a named layout into activeProfile
local function LoadLayout(name)
    if not name or not JarsG13BarsDB.layouts[name] then
        print("|cffff8c00Itsu:UI|r Layout '" .. (name or "nil") .. "' not found.")
        return false
    end

    activeProfile = CopyProfile(JarsG13BarsDB.layouts[name])
    currentLayoutName = name
    JarsG13BarsDB.lastActiveLayout = name

    local specID = GetCurrentSpecID()
    if specID and specID > 0 then
        JarsG13BarsDB.specAssociations[specID] = name
    end

    print("|cffff8c00Itsu:UI|r Layout '" .. name .. "' loaded" ..
        (specID and specID > 0 and (" for " .. GetCurrentSpecName()) or "") .. ".")
    ApplyActiveProfile()
    HideDefaultBars()
    if RefreshConfigUI then RefreshConfigUI() end
    return true
end

-- Load the layout associated with the current spec
local function LoadSpecLayout()
    local specID = GetCurrentSpecID()
    if specID and specID > 0 then
        local layoutName = JarsG13BarsDB.specAssociations[specID]
        if layoutName and JarsG13BarsDB.layouts[layoutName] then
            activeProfile = CopyProfile(JarsG13BarsDB.layouts[layoutName])
            currentLayoutName = layoutName
            print("|cffff8c00Itsu:UI|r Loaded layout '" .. layoutName .. "' for " .. GetCurrentSpecName() .. ".")
            return
        end
    end

    -- No spec association found - try to restore last active layout
    local lastLayout = JarsG13BarsDB.lastActiveLayout
    if lastLayout and JarsG13BarsDB.layouts[lastLayout] then
        activeProfile = CopyProfile(JarsG13BarsDB.layouts[lastLayout])
        currentLayoutName = lastLayout
        print("|cffff8c00Itsu:UI|r Restored layout '" .. lastLayout .. "'.")
        return
    end

    -- No layout found - use the unnamed one or defaults
    if JarsG13BarsDB.currentProfile then
        activeProfile = CopyProfile(JarsG13BarsDB.currentProfile)
    else
        activeProfile = CreateDefaultProfile()
    end
    currentLayoutName = nil
end

-- Delete a named layout
local function DeleteLayout(name)
    if not name or not JarsG13BarsDB.layouts[name] then
        return false
    end

    JarsG13BarsDB.layouts[name] = nil

    for specID, layoutName in pairs(JarsG13BarsDB.specAssociations) do
        if layoutName == name then
            JarsG13BarsDB.specAssociations[specID] = nil
        end
    end

    if currentLayoutName == name then
        currentLayoutName = nil
    end

    if JarsG13BarsDB.lastActiveLayout == name then
        JarsG13BarsDB.lastActiveLayout = nil
    end

    print("|cffff8c00Itsu:UI|r Layout '" .. name .. "' deleted.")
    if RefreshConfigUI then RefreshConfigUI() end
    return true
end

-- ============================================================
-- FOCUS BAR PROFILE SYSTEM (independent of main G13 profiles)
-- ============================================================

local function CreateDefaultFocusProfile()
    return {
        enabled = false,
        slots = {},
        buttonSize = 40,
        padding = 4,
        posX = 0,
        posY = -200,
        bgOpacity = 0.3,
        locked = true,
        nonInteractive = false,
        combatOnly = false,
        orientation = "horizontal",
    }
end

local function CopyFocusProfile(src)
    local copy = {
        enabled = src.enabled or false,
        buttonSize = src.buttonSize or 40,
        padding = src.padding or 4,
        posX = src.posX or 0,
        posY = src.posY or -200,
        bgOpacity = src.bgOpacity or 0.3,
        locked = src.locked ~= false,
        nonInteractive = src.nonInteractive or false,
        combatOnly = src.combatOnly or false,
        orientation = src.orientation or "horizontal",
        slots = {},
    }
    if src.slots then
        for _, s in ipairs(src.slots) do
            table.insert(copy.slots, s)
        end
    end
    return copy
end

local function GetFocusDBTables(barIndex)
    if barIndex == 2 then
        return JarsG13BarsCharDB.focus2Layouts,
               JarsG13BarsCharDB.focus2SpecAssociations,
               "focus2LastActiveLayout",
               "focus2CurrentProfile"
    end
    return JarsG13BarsCharDB.focusLayouts,
           JarsG13BarsCharDB.focusSpecAssociations,
           "focusLastActiveLayout",
           "focusCurrentProfile"
end

local function CountFocusLayouts(barIndex)
    local layouts = GetFocusDBTables(barIndex)
    local count = 0
    for _ in pairs(layouts) do
        count = count + 1
    end
    return count
end

local function GetSortedFocusLayoutNames(barIndex)
    local layouts = GetFocusDBTables(barIndex)
    local names = {}
    for name in pairs(layouts) do
        tinsert(names, name)
    end
    table.sort(names)
    return names
end

local function PersistActiveFocusProfile(barIndex)
    local layouts, _, _, currentKey = GetFocusDBTables(barIndex)
    local name = currentFocusLayoutName[barIndex]
    if name and layouts[name] then
        layouts[name] = CopyFocusProfile(activeFocusProfile[barIndex])
    else
        JarsG13BarsCharDB[currentKey] = CopyFocusProfile(activeFocusProfile[barIndex])
    end
end

-- Forward declare BuildFocusRow (defined later)
local BuildFocusRow

local function SaveFocusLayout(barIndex, name)
    if not name or name == "" then
        print("|cffff8c00Itsu:UI|r Please enter a focus layout name.")
        return false
    end
    local layouts, specAssoc, lastActiveKey = GetFocusDBTables(barIndex)
    if CountFocusLayouts(barIndex) >= MAX_FOCUS_LAYOUTS and not layouts[name] then
        print("|cffff8c00Itsu:UI|r Maximum " .. MAX_FOCUS_LAYOUTS .. " focus layouts reached.")
        return false
    end

    layouts[name] = CopyFocusProfile(activeFocusProfile[barIndex])
    currentFocusLayoutName[barIndex] = name
    JarsG13BarsCharDB[lastActiveKey] = name

    local specID = GetCurrentSpecID()
    if specID and specID > 0 then
        specAssoc[specID] = name
    end

    print("|cffff8c00Itsu:UI|r Focus " .. barIndex .. " layout '" .. name .. "' saved" ..
        (specID and specID > 0 and (" for " .. GetCurrentSpecName()) or "") .. ".")
    if RefreshFocusConfigUI[barIndex] then RefreshFocusConfigUI[barIndex]() end
    return true
end

local function LoadFocusLayout(barIndex, name)
    local layouts, specAssoc, lastActiveKey = GetFocusDBTables(barIndex)
    if not name or not layouts[name] then
        print("|cffff8c00Itsu:UI|r Focus " .. barIndex .. " layout '" .. (name or "nil") .. "' not found.")
        return false
    end

    activeFocusProfile[barIndex] = CopyFocusProfile(layouts[name])
    currentFocusLayoutName[barIndex] = name
    JarsG13BarsCharDB[lastActiveKey] = name

    local specID = GetCurrentSpecID()
    if specID and specID > 0 then
        specAssoc[specID] = name
    end

    print("|cffff8c00Itsu:UI|r Focus " .. barIndex .. " layout '" .. name .. "' loaded" ..
        (specID and specID > 0 and (" for " .. GetCurrentSpecName()) or "") .. ".")
    if BuildFocusRow then BuildFocusRow(barIndex) end
    if RefreshFocusConfigUI[barIndex] then RefreshFocusConfigUI[barIndex](true) end
    return true
end

local function LoadFocusSpecLayout(barIndex)
    local layouts, specAssoc, lastActiveKey, currentKey = GetFocusDBTables(barIndex)
    local specID = GetCurrentSpecID()
    if specID and specID > 0 then
        local layoutName = specAssoc[specID]
        if layoutName and layouts[layoutName] then
            activeFocusProfile[barIndex] = CopyFocusProfile(layouts[layoutName])
            currentFocusLayoutName[barIndex] = layoutName
            print("|cffff8c00Itsu:UI|r Loaded focus " .. barIndex .. " layout '" .. layoutName .. "' for " .. GetCurrentSpecName() .. ".")
            return
        end
    end

    local lastLayout = JarsG13BarsCharDB[lastActiveKey]
    if lastLayout and layouts[lastLayout] then
        activeFocusProfile[barIndex] = CopyFocusProfile(layouts[lastLayout])
        currentFocusLayoutName[barIndex] = lastLayout
        return
    end

    if JarsG13BarsCharDB[currentKey] then
        activeFocusProfile[barIndex] = CopyFocusProfile(JarsG13BarsCharDB[currentKey])
    else
        activeFocusProfile[barIndex] = CreateDefaultFocusProfile()
    end
    currentFocusLayoutName[barIndex] = nil
end

local function DeleteFocusLayout(barIndex, name)
    local layouts, specAssoc, lastActiveKey = GetFocusDBTables(barIndex)
    if not name or not layouts[name] then
        return false
    end

    layouts[name] = nil

    for specID, layoutName in pairs(specAssoc) do
        if layoutName == name then
            specAssoc[specID] = nil
        end
    end

    if currentFocusLayoutName[barIndex] == name then
        currentFocusLayoutName[barIndex] = nil
    end
    if JarsG13BarsCharDB[lastActiveKey] == name then
        JarsG13BarsCharDB[lastActiveKey] = nil
    end

    print("|cffff8c00Itsu:UI|r Focus " .. barIndex .. " layout '" .. name .. "' deleted.")
    if RefreshFocusConfigUI[barIndex] then RefreshFocusConfigUI[barIndex]() end
    return true
end

-- Initialize saved variables (migrate from flat to profile-based structure)
local function InitDB()
    if not JarsG13BarsDB then
        JarsG13BarsDB = {}
    end

    -- Initialize profile tables
    if not JarsG13BarsDB.layouts then
        JarsG13BarsDB.layouts = {}
    end
    if not JarsG13BarsDB.specAssociations then
        JarsG13BarsDB.specAssociations = {}
    end
    if not JarsG13BarsDB.lastActiveLayout then
        JarsG13BarsDB.lastActiveLayout = nil
    end

    -- Initialize focus bar profile tables
    if not JarsG13BarsCharDB.focusLayouts then
        JarsG13BarsCharDB.focusLayouts = {}
    end
    if not JarsG13BarsCharDB.focusSpecAssociations then
        JarsG13BarsCharDB.focusSpecAssociations = {}
    end
    -- Focus bar 2
    if not JarsG13BarsCharDB.focus2Layouts then
        JarsG13BarsCharDB.focus2Layouts = {}
    end
    if not JarsG13BarsCharDB.focus2SpecAssociations then
        JarsG13BarsCharDB.focus2SpecAssociations = {}
    end

end

-- Hide default action bars, Bartender4 HideBlizzard style. only once
local hiddenParts = {}

local HideActionBarFrame = ns.HideBlizzardBar

local function HideActionButton(button)
    if not button then return end
    button:Hide()
    button:UnregisterAllEvents()
    button:SetAttribute("statehidden", true)
    button.bar = nil
end

HideDefaultBars = function()
    RunWhenSafe("hidebars", function()
        -- Bar 2 (slots 61-72) always goes, JG13 buttons 13-24 replace it
        if not hiddenParts.bar2 then
            HideActionBarFrame(MultiBarBottomLeft, true)
            for i = 1, 12 do
                HideActionButton(_G["MultiBarBottomLeftButton" .. i])
            end
            hiddenParts.bar2 = true
        end

        if activeProfile.hideBars and activeProfile.hideBars.MainActionBar then
            if not hiddenParts.main then
                HideActionBarFrame(MainMenuBar, false)   -- <= 11.2.5
                HideActionBarFrame(MainActionBar, false) -- >= 12.0
                for i = 1, 12 do
                    HideActionButton(_G["ActionButton" .. i])
                end
                if MainMenuBar then
                    MainMenuBar:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    MainMenuBar:UnregisterEvent("PLAYER_REGEN_DISABLED")
                    MainMenuBar:UnregisterEvent("ACTIONBAR_SHOWGRID")
                    MainMenuBar:UnregisterEvent("ACTIONBAR_HIDEGRID")
                end
                hiddenParts.main = true
            end
        elseif hiddenParts.main and not hiddenParts.warned then
            -- cant un-hide cleanly, needs a reload
            print("|cffff8c00Itsu:UI|r Blizzard main bar comes back after a /reload.")
            hiddenParts.warned = true
        end
    end)
end

-- one binding command per button: ACTIONBUTTONn for 1-12, MULTIACTIONBAR1BUTTONn for 13-24
local function GetButtonBindCommand(index)
    if index <= 12 then
        return "ACTIONBUTTON" .. index
    end
    return "MULTIACTIONBAR1BUTTON" .. (index - 12)
end

local function UpdateButtonHotkey(button)
    if not button.HotKey or not button.bindCommand then return end
    local key = activeProfile.showKeybinds and GetBindingKey(button.bindCommand)
    local text = key and GetBindingText(key, 1) or ""
    if text ~= "" and text:byte() > 31 then
        button.HotKey:SetText(text)
        button.HotKey:Show()
    else
        button.HotKey:SetText("")
        button.HotKey:Hide()
    end
end

-- Function to update keybind visibility
local function UpdateKeybinds()
    for i = 1, 24 do
        if buttons[i] then UpdateButtonHotkey(buttons[i]) end
    end
end

-- Function to setup override bindings
local inReassignBindings = false
local function UpdateOverrideBindings()
    if not mainFrame then return end
    RunWhenSafe("bindings", function()
        if inReassignBindings then return end
        inReassignBindings = true

        ClearOverrideBindings(mainFrame)
        -- JarStick owns the gamepad, dont grab pad keys out from under it
        local padOwned = C_AddOns.IsAddOnLoaded("JarStick")
        for i = 1, 24 do
            local button = buttons[i]
            local command = GetButtonBindCommand(i)
            for k = 1, select("#", GetBindingKey(command)) do
                local key = select(k, GetBindingKey(command))
                local isPad = key and key:gsub("^.*%-", ""):match("^PAD")
                if key and key ~= "" and not (padOwned and isPad) then
                    -- Use "Keybind" as the mouse button for keybind clicks
                    SetOverrideBindingClick(mainFrame, false, key, button:GetName(), "Keybind")
                end
            end
        end

        inReassignBindings = false
    end)
end

-- Create a single action button
local function CreateActionButton(parent, index, size)
    local button = CreateFrame("CheckButton", "JG13_Button" .. index, parent, "ActionBarButtonTemplate")
    button:SetSize(size, size)
    button.baseAction = index  -- Store the base action for reference
    button.bindCommand = GetButtonBindCommand(index)

    -- Setup action button
    button:SetAttribute("type", "action")
    button:RegisterForClicks("AnyUp")

    if index <= 12 then
        -- Buttons 1-12: Mirror Blizzard's main action bar (ActionButton1-12)
        -- The hook will sync these to match Blizzard's dynamic paging
        button:SetAttribute("action", index)
    else
        -- Buttons 13-24: Mirror ActionBar 2 (MultiBarBottomLeft, slots 61-72)
        -- local multiBarAction = 72 + (index - 12)
        local multiBarAction = 60 + (index - 12)
        button:SetAttribute("action", multiBarAction)
    end
    button:SetAttribute("commandName", button.bindCommand)

    -- blizz UpdateHotkeys looks up ACTIONBUTTON<id>, put our label back after it
    if button.UpdateHotkeys then
        hooksecurefunc(button, "UpdateHotkeys", UpdateButtonHotkey)
    end
    
    -- Ensure the button's hit rectangle matches its size
    button:SetHitRectInsets(0, 0, 0, 0)
    
    -- Hide all background/border elements and resize borders that show
    if button.Border then 
        button.Border:ClearAllPoints()
        button.Border:SetAllPoints(button)
    end
    if button.IconBorder then
        button.IconBorder:ClearAllPoints()
        button.IconBorder:SetAllPoints(button)
    end
    if button.NormalTexture then 
        button.NormalTexture:ClearAllPoints()
        button.NormalTexture:SetAllPoints(button)
        button.NormalTexture:SetTexCoord(0, 1, 0, 1)
        -- Make it fully transparent but keep it to define the button boundary
        button.NormalTexture:SetVertexColor(1, 1, 1, 0)
    end
    if button.FloatingBG then button.FloatingBG:Hide() end
    if button.SlotArt then button.SlotArt:Hide() end
    if button.SlotBackground then button.SlotBackground:Hide() end
    if button.IconMask then button.IconMask:Hide() end
    if button.Flash then
        button.Flash:ClearAllPoints()
        button.Flash:SetAllPoints(button)
    end
    if button.NewActionTexture then
        button.NewActionTexture:ClearAllPoints()
        button.NewActionTexture:SetAllPoints(button)
    end
    if button.SpellHighlightTexture then
        button.SpellHighlightTexture:ClearAllPoints()
        button.SpellHighlightTexture:SetAllPoints(button)
    end
    if button.CheckedTexture then
        button.CheckedTexture:ClearAllPoints()
        button.CheckedTexture:SetAllPoints(button)
    end
    
    -- Set highlight texture to cover entire button
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button)
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetTexCoord(0, 1, 0, 1)
        highlight:SetBlendMode("ADD")
    end
    
    -- Set pushed texture to cover entire button - create custom one
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    local pushed = button:GetPushedTexture()
    if pushed then
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
        pushed:SetVertexColor(0, 0, 0, 0.5)  -- Semi-transparent black overlay
        pushed:SetDrawLayer("OVERLAY", 1)
    end
    
    -- Icon - fill entire button with no insets
    if button.icon then
        button.icon:SetTexCoord(0, 1, 0, 1)
        button.icon:ClearAllPoints()
        button.icon:SetAllPoints(button)
        button.icon:SetDrawLayer("BACKGROUND", 0)
    end
    
    -- Cooldown - fill entire button
    if not button.cooldown then
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    end
    button.cooldown:ClearAllPoints()
    button.cooldown:SetAllPoints(button)
    button.cooldown:SetDrawEdge(false)
    
    -- Count text - MASSIVE and center-justified
    if button.Count then
        button.Count:ClearAllPoints()
        button.Count:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.Count:SetJustifyH("CENTER")
        button.Count:SetJustifyV("MIDDLE")
        button.Count:SetWordWrap(false)
        button.Count:SetWidth(0)  -- No width restriction
        button.Count:SetHeight(0) -- No height restriction
        local fontFace, _, fontFlags = button.Count:GetFont()
        -- Use default font if current font is not available
        if not fontFace or fontFace == "" then
            fontFace = ns.GetFont()
            fontFlags = "OUTLINE"
        end
        button.Count:SetFont(fontFace, math.max(24, size * 0.7), fontFlags or "OUTLINE")
    end
    
    -- Hotkey text - Keep small
    if button.HotKey then
        local fontFace, _, fontFlags = button.HotKey:GetFont()
        -- Use default font if current font is not available
        if not fontFace or fontFace == "" then
            fontFace = ns.GetFont()
            fontFlags = "OUTLINE"
        end
        button.HotKey:SetFont(fontFace, math.max(8, size * 0.2), fontFlags)
    end
    
    -- Name text (macro/spell name)
    if button.Name then
        local fontFace, _, fontFlags = button.Name:GetFont()
        if not fontFace or fontFace == "" then
            fontFace = ns.GetFont()
            fontFlags = "OUTLINE"
        end
        button.Name:SetFont(fontFace, math.max(8, size * 0.15), fontFlags)
    end
    
    -- LibKeyBound support for keybinding
    button.GetBindingAction = function(self)
        return self.bindCommand
    end

    button.GetHotkey = function(self)
        local key = GetBindingKey(self.bindCommand)
        if key then
            return GetBindingText(key, 1)
        end
        return ""
    end
    
    button.GetActionName = function(self)
        if self.baseAction and self.baseAction <= 12 then
            return "Action Button " .. self.baseAction
        elseif self.baseAction and self.baseAction <= 24 then
            return "Bar 2 Button " .. (self.baseAction - 12)
        end
        return "Button " .. (self.baseAction or "?")
    end
    
    button.SetKey = function(self, key)
        local action = self:GetBindingAction()
        if action then
            local result = SetBinding(key, action)
            if result then
                UpdateKeybinds()
                C_Timer.After(0, UpdateOverrideBindings)
            end
            return result
        end
        return false
    end
    
    button.GetBindings = function(self)
        local bindings = {}
        local action = self:GetBindingAction()
        if action then
            for i = 1, select("#", GetBindingKey(action)) do
                local key = select(i, GetBindingKey(action))
                if key and key ~= "" then
                    tinsert(bindings, key)
                end
            end
        end
        return unpack(bindings)
    end
    
    button.ClearBindings = function(self)
        local action = self:GetBindingAction()
        if action then
            while GetBindingKey(action) do
                SetBinding(GetBindingKey(action), nil)
            end
            UpdateKeybinds()
        end
    end
    
    -- Hook OnEnter for LibKeyBound
    button:HookScript("OnEnter", function(self)
        if LibKeyBound and LibKeyBound:IsShown() then
            LibKeyBound:Set(self)
        end
    end)
    
    return button
end

--------------------------------------------------------------------------------
-- Focus Row System
--------------------------------------------------------------------------------

local function GetFocusRowConfig(barIndex)
    return activeFocusProfile[barIndex]
end

local function GetOrCreateFocusRowConfig(barIndex)
    if not activeFocusProfile[barIndex] or not activeFocusProfile[barIndex].slots then
        activeFocusProfile[barIndex] = CreateDefaultFocusProfile()
    end
    return activeFocusProfile[barIndex]
end

local focusBtnCounter = 0
local focusBtnPool = {}  -- recycled focus button frames
local focusRebuildTimer = { nil, nil }  -- debounce handle for BuildFocusRow per bar

-- One-time visual setup for a freshly created focus button
local function InitFocusButtonVisuals(btn)
    if btn.Border then btn.Border:ClearAllPoints(); btn.Border:SetAllPoints(btn) end
    if btn.IconBorder then btn.IconBorder:ClearAllPoints(); btn.IconBorder:SetAllPoints(btn) end
    if btn.NormalTexture then
        btn.NormalTexture:ClearAllPoints()
        btn.NormalTexture:SetAllPoints(btn)
        btn.NormalTexture:SetTexCoord(0, 1, 0, 1)
        btn.NormalTexture:SetVertexColor(1, 1, 1, 0)
    end
    if btn.FloatingBG then btn.FloatingBG:Hide() end
    if btn.SlotArt then btn.SlotArt:Hide() end
    if btn.SlotBackground then btn.SlotBackground:Hide() end
    if btn.IconMask then btn.IconMask:Hide() end
    if btn.Flash then btn.Flash:ClearAllPoints(); btn.Flash:SetAllPoints(btn) end
    if btn.NewActionTexture then btn.NewActionTexture:ClearAllPoints(); btn.NewActionTexture:SetAllPoints(btn) end
    if btn.SpellHighlightTexture then btn.SpellHighlightTexture:ClearAllPoints(); btn.SpellHighlightTexture:SetAllPoints(btn) end
    if btn.CheckedTexture then btn.CheckedTexture:ClearAllPoints(); btn.CheckedTexture:SetAllPoints(btn) end

    local highlight = btn:GetHighlightTexture()
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetAllPoints(btn)
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetTexCoord(0, 1, 0, 1)
        highlight:SetBlendMode("ADD")
    end

    btn:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    local pushed = btn:GetPushedTexture()
    if pushed then
        pushed:ClearAllPoints()
        pushed:SetAllPoints(btn)
        pushed:SetVertexColor(0, 0, 0, 0.5)
        pushed:SetDrawLayer("OVERLAY", 1)
    end

    if btn.icon then
        btn.icon:SetTexCoord(0, 1, 0, 1)
        btn.icon:ClearAllPoints()
        btn.icon:SetAllPoints(btn)
        btn.icon:SetDrawLayer("BACKGROUND", 0)
    end

    if not btn.cooldown then
        btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    end
    btn.cooldown:ClearAllPoints()
    btn.cooldown:SetAllPoints(btn)
    btn.cooldown:SetDrawEdge(false)
end

-- Recycle a button back into the pool
local focusPoolParent = CreateFrame("Frame")
focusPoolParent:Hide()

local function ReleaseFocusButton(btn)
    btn:Hide()
    -- btn:UnregisterAllEvents()
    -- btn:SetParent(nil)
    btn:SetParent(focusPoolParent)
    btn:ClearAllPoints()
    btn:EnableMouse(true)
    table.insert(focusBtnPool, btn)
end

-- Get a focus button from the pool or create a new one
local function AcquireFocusButton(parent, slotID, size)
    local btn = table.remove(focusBtnPool)
    if not btn then
        -- No pooled button available — create a new one
        focusBtnCounter = focusBtnCounter + 1
        btn = CreateFrame("CheckButton", "JG13_FocusBtn" .. focusBtnCounter, parent, "ActionBarButtonTemplate")
        btn:RegisterForClicks("AnyUp")
        btn:SetHitRectInsets(0, 0, 0, 0)
        InitFocusButtonVisuals(btn)
    else
        -- Recycled — re-parent and re-register events
        btn:SetParent(parent)
    end

    btn:SetSize(size, size)
    btn:SetAttribute("type", "action")
    btn:SetAttribute("action", slotID)

    -- Scale fonts to current size
    if btn.Count then
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.Count:SetJustifyH("CENTER")
        btn.Count:SetJustifyV("MIDDLE")
        btn.Count:SetWordWrap(false)
        btn.Count:SetWidth(0)
        btn.Count:SetHeight(0)
        local fontFace, _, fontFlags = btn.Count:GetFont()
        if not fontFace or fontFace == "" then
            fontFace = ns.GetFont()
            fontFlags = "OUTLINE"
        end
        btn.Count:SetFont(fontFace, math.max(24, size * 0.7), fontFlags or "OUTLINE")
    end

    if btn.HotKey then
        local fontFace, _, fontFlags = btn.HotKey:GetFont()
        if not fontFace or fontFace == "" then
            fontFace = ns.GetFont()
            fontFlags = "OUTLINE"
        end
        btn.HotKey:SetFont(fontFace, math.max(8, size * 0.2), fontFlags)
    end

    if btn.Name then
        local fontFace, _, fontFlags = btn.Name:GetFont()
        if not fontFace or fontFace == "" then
            fontFace = ns.GetFont()
            fontFlags = "OUTLINE"
        end
        btn.Name:SetFont(fontFace, math.max(8, size * 0.15), fontFlags)
    end

    btn:Show()
    return btn
end

-- its own lock box or the unlock in general
local function IsFocusRowUnlocked(cfg)
    return not cfg.locked or ns.db.general.unlocked
end

-- focus row frame is built once per bar and reused
local function GetFocusRowFrame(barIndex)
    if focusRowFrame[barIndex] then return focusRowFrame[barIndex] end

    local f = CreateFrame("Frame", "JG13_FocusRow" .. barIndex, UIParent)
    focusRowFrame[barIndex] = f
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if IsFocusRowUnlocked(activeFocusProfile[barIndex]) and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- dragging can swap the anchor, go by the center so it doesnt jump later
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local x, y = cx - ux, cy - uy
        activeFocusProfile[barIndex].posX = x
        activeFocusProfile[barIndex].posY = y
        PersistActiveFocusProfile(barIndex)
        self.UpdateCoordLabel()
        RunWhenSafe("focusmove" .. barIndex, function()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end)
    end)

    -- Background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()

    -- Unlock border indicator
    local unlockBorder = f:CreateTexture(nil, "OVERLAY", nil, 7)
    unlockBorder:SetPoint("TOPLEFT", -2, 2)
    unlockBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    unlockBorder:SetColorTexture(0, 1, 0, 0.3)
    f.unlockBorder = unlockBorder

    f.nameLabel = f:CreateFontString(nil, "OVERLAY")
    f.nameLabel:SetFont(ns.GetFont(), 11, "OUTLINE")
    f.nameLabel:SetTextColor(0, 1, 0)
    f.nameLabel:SetPoint("BOTTOM", f, "TOP", 0, 20)

    -- Nudge buttons + coords, only shown when unlocked
    local coordLabel = f:CreateFontString(nil, "OVERLAY")
    coordLabel:SetFont(ns.GetFont(), 9, "OUTLINE")
    coordLabel:SetTextColor(0, 1, 0)
    coordLabel:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.coordLabel = coordLabel
    f.UpdateCoordLabel = function()
        coordLabel:SetText(string.format("%.0f, %.0f", activeFocusProfile[barIndex].posX or 0, activeFocusProfile[barIndex].posY or 0))
    end

    local function MakeNudgeBtn(label, dx, dy, anchorPoint, relPoint, offX, offY)
        local nb = CreateFrame("Button", nil, f)
        nb:SetSize(16, 16)
        nb:SetPoint(anchorPoint, f, relPoint, offX, offY)
        local nbt = nb:CreateFontString(nil, "OVERLAY")
        nbt:SetFont(ns.GetFont(), 10, "OUTLINE")
        nbt:SetTextColor(0, 1, 0)
        nbt:SetPoint("CENTER")
        nbt:SetText(label)
        nb:SetScript("OnClick", function()
            activeFocusProfile[barIndex].posX = (activeFocusProfile[barIndex].posX or 0) + dx
            activeFocusProfile[barIndex].posY = (activeFocusProfile[barIndex].posY or 0) + dy
            PersistActiveFocusProfile(barIndex)
            f.UpdateCoordLabel()
            RunWhenSafe("focusmove" .. barIndex, function()
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", activeFocusProfile[barIndex].posX, activeFocusProfile[barIndex].posY)
            end)
        end)
        return nb
    end
    f.nudges = {
        MakeNudgeBtn("^",  0,  1, "BOTTOM", "TOP",    0,  2),
        MakeNudgeBtn("v",  0, -1, "TOP",    "BOTTOM", 0, -2),
        MakeNudgeBtn("<", -1,  0, "RIGHT",  "LEFT",  -2,  0),
        MakeNudgeBtn(">",  1,  0, "LEFT",   "RIGHT",  2,  0),
    }

    f:Hide()
    return f
end

BuildFocusRow = function(barIndex)
    RunWhenSafe("focus" .. barIndex, function()
        for _, btn in ipairs(focusRowButtons[barIndex]) do
            ReleaseFocusButton(btn)
        end
        wipe(focusRowButtons[barIndex])

        local f = GetFocusRowFrame(barIndex)
        local cfg = GetFocusRowConfig(barIndex)
        if not cfg or not cfg.enabled then
            UnregisterStateDriver(f, "visibility")
            f:Hide()
            return
        end

        -- enabled w/ no slots yet still gets a box so you can see it
        local unlocked = IsFocusRowUnlocked(cfg)
        local isEmpty = #cfg.slots == 0

        local size = cfg.buttonSize or 40
        local padding = cfg.padding or 4
        local count = math.max(#cfg.slots, 1)
        local orientation = cfg.orientation or "horizontal"
        local isVertical = (orientation == "vertical")

        local frameW, frameH
        if isVertical then
            frameW = size + 8
            frameH = (size * count) + (padding * (count - 1)) + 8
        else
            frameW = (size * count) + (padding * (count - 1)) + 8
            frameH = size + 8
        end

        f:SetSize(frameW, frameH)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", cfg.posX or 0, cfg.posY or -200)
        f:EnableMouse(unlocked)
        f.bg:SetColorTexture(0, 0, 0, cfg.bgOpacity or 0.3)
        f.unlockBorder:SetShown(unlocked or isEmpty)
        f.nameLabel:SetText("Focus Bar " .. barIndex .. (isEmpty and " (no slots yet)" or ""))
        f.nameLabel:SetShown(unlocked or isEmpty)
        f.coordLabel:SetShown(unlocked)
        f.UpdateCoordLabel()
        for _, nb in ipairs(f.nudges) do
            nb:SetShown(unlocked)
        end

        -- Create buttons
        for i, slotID in ipairs(cfg.slots) do
            local btn = AcquireFocusButton(f, slotID, size)
            if isVertical then
                btn:SetPoint("TOP", f, "TOP", 0, -(4 + (i - 1) * (size + padding)))
            else
                btn:SetPoint("LEFT", f, "LEFT", 4 + (i - 1) * (size + padding), 0)
            end
            -- Non-interactive: disable mouse on buttons so they're display-only
            -- same while unlocked so the whole bar drags
            if cfg.nonInteractive or unlocked then
                btn:EnableMouse(false)
            end
            focusRowButtons[barIndex][i] = btn
        end

        -- Combat-only visibility, secure driver so it works in combat
        if cfg.combatOnly and not unlocked and not isEmpty then
            RegisterStateDriver(f, "visibility", "[combat] show; hide")
        else
            UnregisterStateDriver(f, "visibility")
            f:Show()
        end
    end)
end

-- Debounced version of BuildFocusRow for slider callbacks.
-- Coalesces rapid-fire calls (e.g. dragging a slider) into a single rebuild.
local function BuildFocusRowDebounced(barIndex)
    if focusRebuildTimer[barIndex] then focusRebuildTimer[barIndex]:Cancel() end
    focusRebuildTimer[barIndex] = C_Timer.NewTimer(0.05, function()
        focusRebuildTimer[barIndex] = nil
        BuildFocusRow(barIndex)
    end)
end

-- general's unlock toggle
ns.OnShared(function()
    for i = 1, NUM_FOCUS_BARS do BuildFocusRowDebounced(i) end
end)

-- Layout positioning functions
ApplyG13Layout = function(frame)
    -- Original G13 layout
    local buttonIndex
    local primaryOffsetX = SIDE_SIZE * 2 + PADDING * 2
    local rightOffsetX = primaryOffsetX + (PRIMARY_SIZE * 3 + PADDING * 2) + PADDING
    local bottomOffsetY = -(PRIMARY_SIZE * 2 + PADDING)
    local bottomWidth = BOTTOM_SIZE * 6 + PADDING * 5
    local bottomOffsetX = primaryOffsetX + ((PRIMARY_SIZE * 3 + PADDING * 2) / 2) - (bottomWidth / 2)
    
    -- LEFT SIDE: buttons 13-18 (2x3 grid, medium)
    buttonIndex = 1
    for row = 0, 2 do
        for col = 0, 1 do
            local btn = buttons[12 + buttonIndex]
            if btn then
                btn:ClearAllPoints()
                btn:SetSize(SIDE_SIZE, SIDE_SIZE)
                local xPos = col * (SIDE_SIZE + PADDING)
                local yPos = -row * (SIDE_SIZE + PADDING)
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, yPos)
            end
            buttonIndex = buttonIndex + 1
        end
    end
    
    -- CENTER: buttons 1-6 (3x2 grid, large)
    buttonIndex = 1
    for row = 0, 1 do
        for col = 0, 2 do
            local btn = buttons[buttonIndex]
            if btn then
                btn:ClearAllPoints()
                btn:SetSize(PRIMARY_SIZE, PRIMARY_SIZE)
                local xPos = primaryOffsetX + col * (PRIMARY_SIZE + PADDING)
                local yPos = -row * (PRIMARY_SIZE + PADDING)
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, yPos)
            end
            buttonIndex = buttonIndex + 1
        end
    end
    
    -- RIGHT SIDE: buttons 19-24 (2x3 grid, medium)
    buttonIndex = 7
    for row = 0, 2 do
        for col = 0, 1 do
            local btn = buttons[12 + buttonIndex]
            if btn then
                btn:ClearAllPoints()
                btn:SetSize(SIDE_SIZE, SIDE_SIZE)
                local xPos = rightOffsetX + col * (SIDE_SIZE + PADDING)
                local yPos = -row * (SIDE_SIZE + PADDING)
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, yPos)
            end
            buttonIndex = buttonIndex + 1
        end
    end
    
    -- BOTTOM: buttons 7-12 (6x1 grid, small)
    buttonIndex = 7
    for col = 0, 5 do
        local btn = buttons[buttonIndex]
        if btn then
            btn:ClearAllPoints()
            btn:SetSize(BOTTOM_SIZE, BOTTOM_SIZE)
            local xPos = bottomOffsetX + col * (BOTTOM_SIZE + PADDING)
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, bottomOffsetY)
        end
        buttonIndex = buttonIndex + 1
    end
end

ApplyKeyzenLayout = function(frame)
    -- Keyzen keyboard-style layout
    -- Large buttons (01-06) are the fixed center anchor
    local largeOffsetX = SIDE_SIZE * 2 + PADDING * 3
    local largeOffsetY = -(BOTTOM_SIZE + PADDING + SIDE_SIZE + PADDING)
    
    -- Large buttons: 01-06 (3x2 grid) - THE ANCHOR
    local buttonIndex = 1
    for row = 0, 1 do
        for col = 0, 2 do
            local btn = buttons[buttonIndex]
            if btn then
                btn:ClearAllPoints()
                btn:SetSize(PRIMARY_SIZE, PRIMARY_SIZE)
                local xPos = largeOffsetX + col * (PRIMARY_SIZE + PADDING)
                local yPos = largeOffsetY - row * (PRIMARY_SIZE + PADDING)
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, yPos)
            end
            buttonIndex = buttonIndex + 1
        end
    end
    
    -- Small buttons at top: 07, 08, 09 (centered above large buttons)
    local smallTopOffsetX = largeOffsetX + (PRIMARY_SIZE * 3 + PADDING * 2) / 2 - (BOTTOM_SIZE * 3 + PADDING * 2) / 2
    local smallTopOffsetY = 0
    for i = 0, 2 do
        local btn = buttons[7 + i]
        if btn then
            btn:ClearAllPoints()
            btn:SetSize(BOTTOM_SIZE, BOTTOM_SIZE)
            local xPos = smallTopOffsetX + i * (BOTTOM_SIZE + PADDING)
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, smallTopOffsetY)
        end
    end
    
    -- Medium buttons row 2: 13, 15, 20, 22, 24 (evenly spaced with 20 centered above 02)
    local medRow2Y = -(BOTTOM_SIZE + PADDING)
    -- Button 20 centered above button 02 (which is at largeOffsetX + PRIMARY_SIZE + PADDING)
    local btn20X = largeOffsetX + PRIMARY_SIZE + PADDING
    -- Calculate spacing for even distribution
    local rowSpacing = SIDE_SIZE + PADDING
    
    buttons[20]:ClearAllPoints()
    buttons[20]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[20]:SetPoint("TOPLEFT", frame, "TOPLEFT", btn20X, medRow2Y)
    
    buttons[17]:ClearAllPoints()
    buttons[17]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[17]:SetPoint("TOPLEFT", frame, "TOPLEFT", btn20X - rowSpacing, medRow2Y)
    
    buttons[13]:ClearAllPoints()
    buttons[13]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[13]:SetPoint("TOPLEFT", frame, "TOPLEFT", btn20X - rowSpacing * 2, medRow2Y)
    
    buttons[22]:ClearAllPoints()
    buttons[22]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[22]:SetPoint("TOPLEFT", frame, "TOPLEFT", btn20X + rowSpacing, medRow2Y)
    
    buttons[24]:ClearAllPoints()
    buttons[24]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[24]:SetPoint("TOPLEFT", frame, "TOPLEFT", btn20X + rowSpacing * 2, medRow2Y)
    
    -- Medium button row 3 (aligned with L01-L03): 14 (left), 19 (right)
    buttons[14]:ClearAllPoints()
    buttons[14]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[14]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX - SIDE_SIZE - PADDING, largeOffsetY)
    
    buttons[19]:ClearAllPoints()
    buttons[19]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[19]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX + (PRIMARY_SIZE + PADDING) * 3, largeOffsetY)
    
    -- Medium row 4 (aligned with L04-L06): 23, 16 (left), 21 (right)
    -- Move up by half button width to close the gap
    local medRow4Y = largeOffsetY - (PRIMARY_SIZE + PADDING) + SIDE_SIZE/2
    buttons[23]:ClearAllPoints()
    buttons[23]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[23]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX - SIDE_SIZE * 2 - PADDING * 2, medRow4Y)
    
    buttons[16]:ClearAllPoints()
    buttons[16]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[16]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX - SIDE_SIZE - PADDING, medRow4Y)
    
    buttons[21]:ClearAllPoints()
    buttons[21]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[21]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX + (PRIMARY_SIZE + PADDING) * 3, medRow4Y)
    
    -- Bottom row: 15, 18 (left), 10, 11, 12 (small, below button 5)
    -- Move up by full button length to close the gap
    local bottomRowY = medRow4Y - SIDE_SIZE - PADDING
    buttons[15]:ClearAllPoints()
    buttons[15]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[15]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX - SIDE_SIZE * 2 - PADDING * 2, bottomRowY)
    
    buttons[18]:ClearAllPoints()
    buttons[18]:SetSize(SIDE_SIZE, SIDE_SIZE)
    buttons[18]:SetPoint("TOPLEFT", frame, "TOPLEFT", largeOffsetX - SIDE_SIZE - PADDING, bottomRowY)
    
    -- Small buttons 10, 11, 12 below button 5, with button 11 centered under button 5
    local smallBottomOffsetX = largeOffsetX + PRIMARY_SIZE + PADDING + PRIMARY_SIZE/2 - BOTTOM_SIZE - PADDING - BOTTOM_SIZE/2
    local smallBottomOffsetY = largeOffsetY - PRIMARY_SIZE * 2 - PADDING * 2
    for i = 0, 2 do
        local btn = buttons[10 + i]
        if btn then
            btn:ClearAllPoints()
            btn:SetSize(BOTTOM_SIZE, BOTTOM_SIZE)
            local xPos = smallBottomOffsetX + i * (BOTTOM_SIZE + PADDING)
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xPos, smallBottomOffsetY)
        end
    end
end

-- plain 6x4 block, side button size (52). top two rows are bar 1, bottom two bar 2.
-- centered under the same anchor as the others so height from bottom still lines up
ApplyTraditionalLayout = function(frame)
    local cols, size = 6, SIDE_SIZE
    local gridW = cols * size + (cols - 1) * PADDING
    for i = 1, 24 do
        local btn = buttons[i]
        if btn then
            local row, col = math.floor((i - 1) / cols), (i - 1) % cols
            btn:ClearAllPoints()
            btn:SetSize(size, size)
            btn:SetPoint("TOPLEFT", frame, "TOP", -gridW / 2 + col * (size + PADDING), -row * (size + PADDING))
        end
    end
end

-- Create the main frame with all buttons
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "JG13_MainFrame", UIParent)
    frame:SetMovable(false)
    frame:EnableMouse(false)

    -- Calculate frame size
    local primaryWidth = (PRIMARY_SIZE * 3) + (PADDING * 2)
    local primaryHeight = (PRIMARY_SIZE * 2) + PADDING
    local sideWidth = (SIDE_SIZE * 2) + PADDING
    local bottomWidth = (BOTTOM_SIZE * 6) + (PADDING * 5)
    local bottomHeight = BOTTOM_SIZE

    local totalWidth = sideWidth + PADDING + primaryWidth + PADDING + sideWidth
    local totalHeight = primaryHeight + PADDING + bottomHeight

    frame:SetSize(totalWidth, totalHeight)

    -- Set scale from active profile
    frame:SetScale(activeProfile.scale or 0.55)

    -- Set position from active profile
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "BOTTOM", 0, activeProfile.positionY or 327)

    -- Background (for visibility during setup)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, activeProfile.bgOpacity or 0)

    -- Create all buttons first (without positioning)
    for i = 1, 24 do
        buttons[i] = CreateActionButton(frame, i, PRIMARY_SIZE)
    end

    -- Apply layout based on active profile
    if activeProfile.layoutMode == "Keyzen" then
        ApplyKeyzenLayout(frame)
    elseif activeProfile.layoutMode == "Traditional" then
        ApplyTraditionalLayout(frame)
    else
        ApplyG13Layout(frame)
    end

    -- Setup secure state driver for combat-safe page swapping
    SetupSecurePageDriver()

    -- Apply overall frame alpha and hide-on-mouse-out from active profile
    SetMouseOutFade(frame)

    return frame
end

-- Update all buttons - refresh keybinds (page swaps handled by secure state driver)
local function UpdateButtons()
    UpdateKeybinds()
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
eventFrame:RegisterEvent("SPELL_UPDATE_ICON")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
eventFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
eventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")

local firstEnterWorld = true
local lastSpecKey

local function OnModuleLoad()
    InitDB()
    LoadSpecLayout()
    lastSpecKey = GetCurrentSpecID()
    for i = 1, NUM_FOCUS_BARS do LoadFocusSpecLayout(i) end
    HideDefaultBars()
    mainFrame = CreateMainFrame()
    for i = 1, NUM_FOCUS_BARS do BuildFocusRow(i) end

    -- Setup override bindings and update keybinds after a delay to ensure buttons are ready
    C_Timer.After(1, function()
        UpdateOverrideBindings()
        UpdateKeybinds()
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            UpdateButtons()
            -- spec shows up by now, only need this once tho
            if firstEnterWorld and GetCurrentSpecID() > 0 then
                firstEnterWorld = false
                -- talent group might not of been ready at load
                if GetCurrentSpecID() ~= lastSpecKey then
                    lastSpecKey = GetCurrentSpecID()
                    LoadSpecLayout()
                    ApplyActiveProfile()
                    HideDefaultBars()
                end
                for i = 1, NUM_FOCUS_BARS do
                    LoadFocusSpecLayout(i)
                    BuildFocusRow(i)
                end
                if RefreshConfigUI then RefreshConfigUI() end
                for i = 1, NUM_FOCUS_BARS do
                    if RefreshFocusConfigUI[i] then RefreshFocusConfigUI[i](true) end
                end
            end
        end)

    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- these can both fire for 1 swap
        local specKey = GetCurrentSpecID()
        if specKey == lastSpecKey then return end
        lastSpecKey = specKey
        LoadSpecLayout()
        for i = 1, NUM_FOCUS_BARS do LoadFocusSpecLayout(i) end
        ApplyActiveProfile()
        HideDefaultBars()
        UpdateKeybinds()
        for i = 1, NUM_FOCUS_BARS do BuildFocusRow(i) end
        if RefreshConfigUI then RefreshConfigUI() end
        for i = 1, NUM_FOCUS_BARS do
            if RefreshFocusConfigUI[i] then RefreshFocusConfigUI[i](true) end
        end

    elseif event == "UPDATE_BINDINGS" then
        UpdateOverrideBindings()
        UpdateKeybinds()

    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" or
           event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" or
           event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "SPELL_UPDATE_ICON" or
           event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        UpdateButtons()

    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateKeybinds()

    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or
           event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE" or
           event == "ACTIONBAR_UPDATE_STATE" or event == "SPELL_UPDATE_CHARGES" or
           event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTER_COMBAT" or
           event == "PLAYER_LEAVE_COMBAT" then
        -- ActionBarButtonTemplate handles these automatically - no action needed
    end
end)

-- Function to update main frame position
local function UpdateFramePosition(yOffset)
    if mainFrame then
        activeProfile.positionY = yOffset
        PersistActiveProfile()
        RunWhenSafe("profile", function()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, activeProfile.positionY or 327)
            mainFrame:SetScale(activeProfile.scale or 0.55)
        end)
    end
end

-- Function to update background opacity
local function UpdateBackgroundOpacity(opacity)
    if mainFrame and mainFrame.bg then
        mainFrame.bg:SetColorTexture(0, 0, 0, opacity)
        activeProfile.bgOpacity = opacity
        PersistActiveProfile()
    end
end

-- Function to update frame scale
local function UpdateScale(scale)
    if mainFrame then
        activeProfile.scale = scale
        PersistActiveProfile()
        RunWhenSafe("profile", function()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, activeProfile.positionY or 327)
            mainFrame:SetScale(activeProfile.scale or 0.55)
        end)
    end
end

-- Function to update overall frame alpha
local function UpdateFrameAlpha(alpha)
    if mainFrame then
        activeProfile.frameAlpha = alpha
        if not activeProfile.hideOnMouseOut then
            mainFrame:SetAlpha(alpha)
        end
        PersistActiveProfile()
    end
end

-- Function to apply hide-on-mouse-out behavior
local function ApplyHideOnMouseOut(enabled)
    if not mainFrame then return end
    activeProfile.hideOnMouseOut = enabled
    SetMouseOutFade(mainFrame)
    PersistActiveProfile()
end

-- Slash command
SLASH_JG131 = "/jg13"
SLASH_JG132 = "/jg13bind"
SlashCmdList["JG13"] = function(msg)
    -- keep the raw text so layout names keep their case
    local raw = msg:trim()
    msg = raw:lower()

    if msg == "bind" or msg == "keybind" or msg == "kb" then
        if LibKeyBound then
            LibKeyBound:Toggle()
            if LibKeyBound:IsShown() then
                print("|cffff8c00Itsu:UI|r Keybind mode enabled. Hover over a button and press a key.")
            else
                print("|cffff8c00Itsu:UI|r Keybind mode disabled.")
            end
        end
        return
    end

    if msg:sub(1, 5) == "save " then
        local name = raw:sub(6):trim()
        SaveLayout(name)
        return
    end

    if msg:sub(1, 5) == "load " then
        local name = raw:sub(6):trim()
        LoadLayout(name)
        return
    end

    if msg:sub(1, 7) == "delete " then
        local name = raw:sub(8):trim()
        DeleteLayout(name)
        return
    end

    if msg == "layouts" or msg == "list" then
        local names = GetSortedLayoutNames()
        if #names == 0 then
            print("|cffff8c00Itsu:UI|r No saved layouts.")
        else
            print("|cffff8c00Itsu:UI|r Saved layouts:")
            for _, name in ipairs(names) do
                local marker = (name == currentLayoutName) and " |cff00ffff(active)|r" or ""
                print("  - " .. name .. marker)
            end
        end
        return
    end

    ns.OpenConfig("Action Bars")
end

-------------------------------------------------------------------------------
-- Config panels
-------------------------------------------------------------------------------
local function Percent(v) return string.format("%.0f%%", v * 100) end

-- little keyboard for keybind mode
-- red = locked (menus, sit, sheathe...), yellow = assigned, green = free
if LibKeyBound then
    local SIZE, GAP = 30, 3
    local PITCH = SIZE + GAP
    local ROWS = {
        { indent = 0,            keys = "`1234567890-=" },
        { indent = PITCH * 1.5,  keys = "QWERTYUIOP[]\\" },
        { indent = PITCH * 1.75, keys = "ASDFGHJKL;'" },
        { indent = PITCH * 2.25, keys = "ZXCVBNM,./" },
    }
    -- key, label, column, row
    local ARROWS = {
        { "UP", "^", 1, 2 },
        { "LEFT", "<", 0, 3 }, { "DOWN", "v", 1, 3 }, { "RIGHT", ">", 2, 3 },
    }
    local YELLOW, RED, GREEN = { 1, 0.82, 0 }, { 0.85, 0.2, 0.2 }, { 0.2, 0.75, 0.3 }

    -- retail's interface bindings + the special ones
    local LOCKED = {}
    for action in ([[
        TOGGLEGAMEMENU TOGGLEBACKPACK TOGGLEREAGENTBAG1 TOGGLEBAG1 TOGGLEBAG2 TOGGLEBAG3 TOGGLEBAG4 OPENALLBAGS
        TOGGLECHARACTER0 TOGGLECHARACTER2 TOGGLECURRENCY TOGGLECHARACTER4
        TOGGLESPELLBOOK TOGGLEPROFESSIONBOOK TOGGLEACHIEVEMENT TOGGLEPETBOOK TOGGLETALENTS TOGGLECOOLDOWNVIEWERSETTINGS
        TOGGLEENCOUNTERJOURNAL TOGGLEGROUPFINDER TOGGLEHOUSINGDASHBOARD
        TOGGLEQUESTLOG TOGGLEWORLDMAP TOGGLEWORLDMAPSIZE TOGGLEMINIMAP TOGGLEBATTLEFIELDMINIMAP TOGGLEWORLDSTATESCORES
        TOGGLEGUILDTAB TOGGLESOCIAL TOGGLEFRIENDSTAB TOGGLEWHOTAB TOGGLECHATTAB TOGGLERAIDTAB TOGGLETEXTTOSPEECH
        TOGGLECOLLECTIONS TOGGLECOLLECTIONSMOUNTJOURNAL TOGGLECOLLECTIONSPETJOURNAL TOGGLECOLLECTIONSTOYBOX TOGGLECOLLECTIONSWARDROBE
        SITORSTAND TOGGLESHEATH NAMEPLATES
    ]]):gmatch("%S+") do
        LOCKED[action] = true
    end

    -- no mouse on this one, it cant get in the way of binding
    local keyMap = CreateFrame("Frame", "JarForeverKeyMap", UIParent, "BackdropTemplate")
    keyMap:SetFrameStrata("FULLSCREEN_DIALOG")
    keyMap:SetPoint("CENTER")
    keyMap:SetSize(24 + PITCH * 15.5 - GAP, 24 + PITCH * 4 - GAP + 22)
    keyMap:SetBackdrop(ns.BACKDROP)
    keyMap:SetBackdropColor(unpack(ns.UI.bg))
    keyMap:SetBackdropBorderColor(unpack(ns.UI.border))
    keyMap:Hide()

    local keys = {}
    local function AddKey(key, label, x, row)
        local tex = keyMap:CreateTexture(nil, "ARTWORK")
        tex:SetSize(SIZE, SIZE)
        tex:SetPoint("TOPLEFT", 12 + x, -12 - row * PITCH)
        tex.label = keyMap:CreateFontString(nil, "OVERLAY")
        tex.label:SetPoint("CENTER", tex)
        tex.label:SetFont(ns.GetFont(), 13, "")
        tex.label:SetTextColor(0, 0, 0)
        tex.label:SetText(label)
        keys[key] = tex
    end
    for r, row in ipairs(ROWS) do
        local x = row.indent
        for key in row.keys:gmatch(".") do
            AddKey(key, key, x, r - 1)
            x = x + PITCH
        end
    end
    for _, arrow in ipairs(ARROWS) do
        AddKey(arrow[1], arrow[2], PITCH * (12.5 + arrow[3]), arrow[4])
    end

    local legend = keyMap:CreateFontString(nil, "OVERLAY")
    legend:SetPoint("BOTTOM", 0, 10)
    legend:SetFont(ns.GetFont(), 12, "")

    local function RefreshKeyMap()
        -- whatevers held, same order the binder builds them
        local prefix = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
        local showing = prefix == "" and "No modifier" or prefix:gsub("%-", " + ")

        local font = ns.GetFont()
        legend:SetFont(font, 12, "")
        legend:SetText(showing .. "     |cffd93333Locked|r     |cffffd100Assigned|r     |cff33bf4dFree|r")
        for key, tex in pairs(keys) do
            local action = GetBindingAction(prefix .. key)
            local color = GREEN
            if LOCKED[action] then
                color = RED
            elseif action and action ~= "" then
                color = YELLOW
            end
            tex:SetColorTexture(color[1], color[2], color[3], 1)
            tex.label:SetFont(font, 13, "")
        end
    end

    keyMap:SetScript("OnEvent", RefreshKeyMap)
    keyMap:SetScript("OnShow", function(self)
        self:RegisterEvent("UPDATE_BINDINGS")
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
        RefreshKeyMap()
    end)
    keyMap:SetScript("OnHide", function(self)
        self:UnregisterEvent("UPDATE_BINDINGS")
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end)

    LibKeyBound.RegisterCallback(keyMap, "LIBKEYBOUND_ENABLED", function() keyMap:Show() end)
    LibKeyBound.RegisterCallback(keyMap, "LIBKEYBOUND_DISABLED", function() keyMap:Hide() end)
end

ns.RegisterPanel(20, "Action Bars", function(b)
    b:Header("Profiles")
    b:Text(function()
        return "Spec: " .. GetCurrentSpecName() .. "  |  Layout: " .. (currentLayoutName or "(none)")
    end)
    local nameRow = b:Input("Layout Name", function() return currentLayoutName end)
    b:Buttons({
        { "Save", function()
            local name = nameRow.box:GetText():trim()
            if name ~= "" then SaveLayout(name) end
        end, 100 },
        { "Delete", function()
            local name = nameRow.box:GetText():trim()
            if name ~= "" then DeleteLayout(name) end
        end, 100 },
    })
    b:Dropdown("Load Layout",
        function() return currentLayoutName or "Select a layout..." end,
        function(_, root)
            local names = GetSortedLayoutNames()
            if #names == 0 then
                root:CreateTitle("No saved layouts")
                return
            end
            for _, name in ipairs(names) do
                root:CreateButton(name, function() LoadLayout(name) end)
            end
        end)

    b:Header("Appearance")
    b:Toggle("Layout", { { "G13", "G13" }, { "Keyzen", "Keyzen" }, { "Traditional", "Traditional" } },
        function() return activeProfile.layoutMode end,
        function(v)
            activeProfile.layoutMode = v
            ApplyLayoutMode()
            PersistActiveProfile()
        end)
    b:Slider("Height From Bottom", 0, 2400, 1,
        function() return activeProfile.positionY or 327 end,
        function(v) UpdateFramePosition(math.floor(v)) end)
    b:Slider("Scale", 0.3, 1.5, 0.05,
        function() return activeProfile.scale or 0.55 end,
        UpdateScale, Percent)
    b:Slider("Background Opacity", 0, 1, 0.05,
        function() return activeProfile.bgOpacity or 0 end,
        UpdateBackgroundOpacity, Percent)
    b:Slider("Overall Transparency", 0, 1, 0.05,
        function() return activeProfile.frameAlpha or 1 end,
        UpdateFrameAlpha, Percent)

    b:Header("Behavior")
    b:Check("Hide unless moused over",
        function() return activeProfile.hideOnMouseOut end,
        ApplyHideOnMouseOut)
    b:Check("Show keybinds on buttons",
        function() return activeProfile.showKeybinds end,
        function(v)
            activeProfile.showKeybinds = v
            UpdateKeybinds()
            PersistActiveProfile()
        end)
    b:Check("Hide Blizzard main bar  (coming back needs a /reload)",
        function() return activeProfile.hideBars.MainActionBar ~= false end,
        function(v)
            activeProfile.hideBars.MainActionBar = v
            HideDefaultBars()
            PersistActiveProfile()
        end)

    b:Header("Bar Paging  (which page shows for each form or stance)")
    for i = 1, 5 do
        local key = "b" .. i
        b:Slider("Bonus Bar " .. i, 1, 12, 1,
            function() return activeProfile.pageMap[key] or 1 end,
            function(v)
                activeProfile.pageMap[key] = v
                PersistActiveProfile()
                RefreshStateDriver()
            end,
            function(v) return "Page " .. v end)
    end

    b:Header("Actions")
    local keybindText = "Set Keybinds"
    local row = b:Buttons({
        { keybindText, function()
            if LibKeyBound then
                LibKeyBound:Toggle()
                if LibKeyBound:IsShown() then
                    print("|cffff8c00Itsu:UI|r Hover over a button and press a key to bind it.")
                end
            end
        end, 160, key = "keybind" },
        { "Reset to Defaults", function()
            activeProfile = CreateDefaultProfile()
            currentLayoutName = nil
            JarsG13BarsDB.lastActiveLayout = nil
            PersistActiveProfile()
            ApplyActiveProfile()
            HideDefaultBars()
            UpdateKeybinds()
            if RefreshConfigUI then RefreshConfigUI() end
            print("|cffff8c00Itsu:UI|r Settings reset to default.")
        end, 160 },
    })
    if LibKeyBound then
        LibKeyBound.RegisterCallback(row.keybind, "LIBKEYBOUND_ENABLED", function()
            row.keybind.label:SetText("Exit Keybind Mode")
        end)
        LibKeyBound.RegisterCallback(row.keybind, "LIBKEYBOUND_DISABLED", function()
            row.keybind.label:SetText(keybindText)
        end)
    end

    RefreshConfigUI = function()
        ns.RefreshPanel("Action Bars")
    end
end)

ns.RegisterPanel(25, "Focus Bars", function(b)
    local bar = 1
    local function Cfg() return GetOrCreateFocusRowConfig(bar) end
    local function Save() PersistActiveFocusProfile(bar) end
    local function Changed()
        Save()
        BuildFocusRow(bar)
    end

    -- b:Text("Small extra bars showing any action slots you pick.")
    b:Text("Monitor specific action bar buttons for cooldowns or stacks.")
    b:Text("Each icon shows the ability in the action slot you pick (1-180).")
    b:Text("Tick Non-interactive below if you only want to watch them.")
    b:Toggle("Editing", { { "Bar 1", 1 }, { "Bar 2", 2 } },
        function() return bar end,
        function(v)
            bar = v
            b:Refresh()
        end)

    b:Header("Profiles")
    b:Text(function()
        return "Spec: " .. GetCurrentSpecName() .. "  |  Layout: " .. (currentFocusLayoutName[bar] or "(none)")
    end)
    local nameRow = b:Input("Layout Name", function() return currentFocusLayoutName[bar] end)
    b:Buttons({
        { "Save", function()
            local name = nameRow.box:GetText():trim()
            if name ~= "" then SaveFocusLayout(bar, name) end
        end, 100 },
        { "Delete", function()
            local name = nameRow.box:GetText():trim()
            if name ~= "" then DeleteFocusLayout(bar, name) end
        end, 100 },
    })
    b:Dropdown("Load Layout",
        function() return currentFocusLayoutName[bar] or "Select a focus layout..." end,
        function(_, root)
            local names = GetSortedFocusLayoutNames(bar)
            if #names == 0 then
                root:CreateTitle("No saved focus layouts")
                return
            end
            for _, name in ipairs(names) do
                root:CreateButton(name, function() LoadFocusLayout(bar, name) end)
            end
        end)

    b:Header("Settings")
    b:Check("Enable this bar",
        function() return Cfg().enabled end,
        function(v) Cfg().enabled = v; Changed() end)
    b:Toggle("Orientation", { { "Horizontal", "horizontal" }, { "Vertical", "vertical" } },
        function() return Cfg().orientation or "horizontal" end,
        function(v) Cfg().orientation = v; Changed() end)
    b:Slider("Button Size", 24, 120, 2,
        function() return Cfg().buttonSize or 40 end,
        function(v) Cfg().buttonSize = v; Save(); BuildFocusRowDebounced(bar) end,
        function(v) return v .. "px" end)
    b:Slider("Button Padding", 0, 20, 1,
        function() return Cfg().padding or 4 end,
        function(v) Cfg().padding = v; Save(); BuildFocusRowDebounced(bar) end,
        function(v) return v .. "px" end)
    b:Slider("Background Opacity", 0, 1, 0.05,
        function() return Cfg().bgOpacity or 0.3 end,
        function(v)
            Cfg().bgOpacity = v
            Save()
            if focusRowFrame[bar] and focusRowFrame[bar].bg then
                focusRowFrame[bar].bg:SetColorTexture(0, 0, 0, v)
            end
        end,
        Percent)
    b:Check("Lock position",
        function() return Cfg().locked ~= false end,
        function(v) Cfg().locked = v; Changed() end)
    b:Check("Non-interactive  (display only)",
        function() return Cfg().nonInteractive end,
        function(v) Cfg().nonInteractive = v; Changed() end)
    b:Check("Only show in combat",
        function() return Cfg().combatOnly end,
        function(v) Cfg().combatOnly = v; Changed() end)

    b:Header("Action Slots  (1-180, enter to apply)")
    local MAX_SLOTS = 8
    local rows = {}
    b:Buttons({
        { "+ Add Slot", function()
            local slots = Cfg().slots
            if #slots < MAX_SLOTS then
                table.insert(slots, 1)
                Changed()
                b:Refresh()
            end
        end, 120 },
        { "Reset This Bar", function()
            activeFocusProfile[bar] = CreateDefaultFocusProfile()
            currentFocusLayoutName[bar] = nil
            local _, _, lastActiveKey = GetFocusDBTables(bar)
            JarsG13BarsCharDB[lastActiveKey] = nil
            Changed()
            b:Refresh()
        end, 140 },
    })

    for i = 1, MAX_SLOTS do
        local row = b:Custom(30)
        rows[i] = row

        row.box = b:NewEditBox(row, 60, 24)
        row.box:SetPoint("LEFT", 0, 0)
        row.box:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText())
            local slots = Cfg().slots
            if val and val >= 1 and val <= 180 then
                slots[i] = math.floor(val)
                Changed()
            end
            b:Refresh()
            self:ClearFocus()
        end)

        row.desc = row:CreateFontString(nil, "OVERLAY")
        row.desc:SetFont(ns.GetFont(), 10, "")
        row.desc:SetTextColor(unpack(ns.UI.textDim))
        row.desc:SetPoint("LEFT", row.box, "RIGHT", 8, 0)

        row.remove = b:NewButton(row, "x", 24, 22, function()
            table.remove(Cfg().slots, i)
            Changed()
            b:Refresh()
        end)
        row.remove:SetPoint("LEFT", 200, 0)

        row.up = b:NewButton(row, "^", 24, 22, function()
            local slots = Cfg().slots
            slots[i], slots[i - 1] = slots[i - 1], slots[i]
            Changed()
            b:Refresh()
        end)
        row.up:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    end

    local function SyncRows()
        local slots = Cfg().slots
        for i, row in ipairs(rows) do
            local slotID = slots[i]
            row:SetShown(slotID ~= nil)
            if slotID then
                row.box:SetText(tostring(slotID))
                row.desc:SetText("Bar " .. math.ceil(slotID / 12) .. " Btn " .. ((slotID - 1) % 12 + 1))
                row.up:SetShown(i > 1)
            end
        end
    end
    b:OnRefresh(SyncRows)
    SyncRows()

    local function RefreshFocusPanel()
        ns.RefreshPanel("Focus Bars")
    end
    RefreshFocusConfigUI[1] = RefreshFocusPanel
    RefreshFocusConfigUI[2] = RefreshFocusPanel
end)

OnModuleLoad()

end)
