-- Itsu:UI: game menu (micro menu) in the bottom right corner + hides blizz's bag bar

local _, ns = ...

ns.RegisterModule("gameMenu", "Game Menu", function()

local DB = ns.db.gameMenu
local DEFAULTS = { moved = true, x = -7, y = 4, hideBags = true, minimal = true, greyIcons = true }
for k, v in pairs(DEFAULTS) do
    if DB[k] == nil then DB[k] = v end
end

local RunWhenSafe = ns.RunWhenSafe

local bagHider = CreateFrame("Frame")
bagHider:Hide()

-- on forever the main bar hangs off the micro menu, and stance + pet bars off the main bar.
-- retail anchors it on its own (no MAIN_ACTION_BAR_OFFSET_X there), nothing to pin
local function PinMainBar()
    if not MAIN_ACTION_BAR_OFFSET_X then return end
    if not MainActionBar:IsInDefaultPosition() then return end
    local x = MICRO_MENU_ANCHOR_OFFSET_X - MicroMenuContainer:GetWidth() / 2 + MAIN_ACTION_BAR_OFFSET_X
    local y = MICRO_MENU_ANCHOR_OFFSET_Y + MAIN_ACTION_BAR_OFFSET_Y
    MainActionBar:ClearAllPoints()
    MainActionBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", x, y)
end

-- flat square behind each button, once per button
local function SkinButton(button)
    if button.jfBorder then return end
    button.jfBorder = button:CreateTexture(nil, "BACKGROUND", nil, -3)
    button.jfBorder:SetPoint("TOPLEFT", 3, -5)
    button.jfBorder:SetPoint("BOTTOMRIGHT", -3, 5)
    button.jfBorder:SetColorTexture(unpack(ns.UI.border))

    button.jfFill = button:CreateTexture(nil, "BACKGROUND", nil, -2)
    button.jfFill:SetPoint("TOPLEFT", button.jfBorder, "TOPLEFT", 1, -1)
    button.jfFill:SetPoint("BOTTOMRIGHT", button.jfBorder, "BOTTOMRIGHT", -1, 1)
    button.jfFill:SetColorTexture(unpack(ns.UI.header))

    button:HookScript("OnEnter", function(self)
        self.jfFill:SetColorTexture(unpack(ns.UI.btnHover))
    end)
    button:HookScript("OnLeave", function(self)
        self.jfFill:SetColorTexture(unpack(ns.UI.header))
    end)
end

-- blizz only shows/hides these art bits, it never touches alpha so this sticks
local function ApplyLook()
    local artAlpha = DB.minimal and 0 or 1
    if MicroMenu.BorderArt then MicroMenu.BorderArt:SetAlpha(artAlpha) end
    if MicroMenu.BackgroundArt then MicroMenu.BackgroundArt:SetAlpha(artAlpha) end

    local grey = DB.minimal and DB.greyIcons
    for _, button in ipairs({ MicroMenu:GetChildren() }) do
        if button.Background then
            SkinButton(button)
            button.jfBorder:SetShown(DB.minimal)
            button.jfFill:SetShown(DB.minimal)
            button.Background:SetAlpha(artAlpha)
            button.PushedBackground:SetAlpha(artAlpha)
            if button.Shadow then button.Shadow:SetAlpha(artAlpha) end
            if button.PushedShadow then button.PushedShadow:SetAlpha(artAlpha) end
            for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetHighlightTexture() }) do
                tex:SetDesaturated(grey)
            end
        end
    end
end

local function Apply()
    RunWhenSafe("gameMenu", function()
        if DB.moved then
            MicroMenuContainer:ClearAllPoints()
            MicroMenuContainer:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", DB.x, DB.y)
            -- no position yet this early, the login + zone in passes get it
            if MicroMenuContainer:GetCenter() then
                MicroMenuContainer:Layout()
            end
            PinMainBar()
        end
        ApplyLook()
        if DB.hideBags then
            BagsBar:SetParent(bagHider)
        else
            BagsBar:SetParent(UIParent)
            -- default spot is right of the menu, thats off screen from the corner
            if DB.moved then
                BagsBar:ClearAllPoints()
                BagsBar:SetPoint("BOTTOMRIGHT", MicroMenuContainer, "TOPRIGHT", 0, 4)
            end
        end
    end)
end

-- edit mode puts these back whenever a layout applies, so go again after it does
hooksecurefunc(MicroMenuContainer, "ApplySystemAnchor", Apply)
hooksecurefunc(BagsBar, "ApplySystemAnchor", Apply)
hooksecurefunc(MainActionBar, "ApplySystemAnchor", Apply)
hooksecurefunc(EditModeManagerFrame, "UpdateBottomActionBarPositions", Apply)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", Apply)

ns.RegisterPanel(65, "Game Menu", function(b)
    b:Header("Game Menu")
    b:Check("Keep the game menu in the bottom right corner",
        function() return DB.moved end,
        function(v)
            DB.moved = v
            if v then
                Apply()
            else
                -- hand it back to edit mode
                RunWhenSafe("gameMenuOff", function()
                    MicroMenuContainer:ApplySystemAnchor()
                    MicroMenuContainer:Layout()
                    EditModeManagerFrame:UpdateBottomActionBarPositions()
                end)
            end
        end)
    b:Slider("Left / Right", -1000, 0, 1,
        function() return DB.x end,
        function(v) DB.x = v; Apply() end)
    b:Slider("Up / Down", 0, 600, 1,
        function() return DB.y end,
        function(v) DB.y = v; Apply() end)

    b:Header("Look")
    b:Check("Minimal buttons  (flat squares, no Blizzard frame art)",
        function() return DB.minimal end,
        function(v) DB.minimal = v; ApplyLook() end)
    b:Check("Grey icons",
        function() return DB.greyIcons end,
        function(v) DB.greyIcons = v; ApplyLook() end)

    b:Header("Bag Bar")
    b:Check("Hide Blizzard's bag bar",
        function() return DB.hideBags end,
        function(v)
            DB.hideBags = v
            if v then
                Apply()
            else
                RunWhenSafe("gameMenuBags", function()
                    BagsBar:SetParent(UIParent)
                    BagsBar:ApplySystemAnchor()
                    Apply()
                end)
            end
        end)
    b:Text("The bag window doesnt show your bag slots. Turn this off to swap a bag out.")

    b:Spacer(8)
    b:Buttons({ { "Reset Position", function()
        DB.x, DB.y = DEFAULTS.x, DEFAULTS.y
        Apply()
        b:Refresh()
    end } })
end)

end)
