-- Itsu:UI: player, target, focus, ToT, pet + party frames

local _, ns = ...

ns.RegisterModule("unitFrames", "Unit Frames", function()

local JarUnitFramesDB = ns.db.unitFrames
local RunWhenSafe = ns.RunWhenSafe

-- Default values (will be applied in PLAYER_LOGIN after SavedVariables load)
local defaults = {
    showPlayerFrame = true,
    showTargetFrame = true,
    showPetFrame = true,
    showFocusFrame = true,
    showTargetTargetFrame = true,
    frameScale = 0.9,
    showPercentages = true,
    fontSize = 12,
    showLevel = true,
    enableAuraTooltips = true,   -- Show tooltip when hovering buff/debuff icons
    showTargetItemLevel = true,    -- Show target's item level (players only)
    mirrorTargetPosition = true,
    playerPos = { point = "BOTTOM", x = -278.8, y = 154.8 },
    targetPos = { point = "BOTTOM", x = 278.8, y = 154.8 },
    focusPos = { point = "TOPLEFT", x = 500, y = -20 },
    focusWidth = 220,
    focusShowBuffs = true,
    focusShowDebuffs = true,
    totPos = { point = "BOTTOM", x = 471.8, y = 171.7 },
    totWidth = 150,
    totShowBuffs = true,
    totShowDebuffs = true,
    petPos = { point = "TOPLEFT", x = 20, y = -200 },
    petWidth = 150,
    petShowBuffs = true,
    petShowDebuffs = true,
    hidePlayerPermanentBuffs = false,  -- Hide player buffs without timers
    hideTargetPermanentBuffs = false,  -- Hide target buffs without timers
    playerDebuffFilter = "HARMFUL",
    targetDebuffFilter = "HARMFUL",
    focusDebuffFilter  = "HARMFUL|RAID",
    totDebuffFilter    = "HARMFUL|RAID",
    petDebuffFilter    = "HARMFUL",
    partyDebuffFilter  = "HARMFUL|RAID",
    playerMaxDebuffs = 40,
    targetMaxDebuffs = 40,
    showPartyFrames = true,
    partyPos = { point = "TOPLEFT", x = 20, y = -300 },
    partyWidth = 150,
    partyPadding = 5,
    partyShowOnlyMyBuffs = true,
    playerWidth = 220,
    targetWidth = 220,
}

-- per frame sizes + aura spots. "tot" is target of target
local FRAME_KEYS = { "player", "target", "focus", "tot", "pet", "party" }
-- normal aura icon size, the scale sliders go 70-130% of this
local AURA_SIZE = { player = 20, target = 20, focus = 18, tot = 18, pet = 18, party = 18 }
-- these line their name + auras up on the right edge
local MIRRORED = { target = true, focus = true }
for _, k in ipairs(FRAME_KEYS) do
    defaults[k .. "Health"] = 20
    defaults[k .. "Power"] = 8
    defaults[k .. "BuffPos"] = k == "party" and "right" or "above"
    defaults[k .. "DebuffPos"] = k == "party" and "left" or "below"
    defaults[k .. "BuffScale"] = 1
    defaults[k .. "DebuffScale"] = 1
    if defaults[k .. "ShowBuffs"] == nil then defaults[k .. "ShowBuffs"] = true end
    if defaults[k .. "ShowDebuffs"] == nil then defaults[k .. "ShowDebuffs"] = true end
end

-- Frame references
local playerFrame, targetFrame, petFrame, focusFrame, targetTargetFrame
local partyFrames = {}

-- Lookup table for player's units (used to avoid secret value comparison errors)
local myUnits = { player = true, pet = true, vehicle = true }

-- Item level display: request inspect on target change, show result when ready
local pendingGUID

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local function CalcInspectItemLevel(unit)
    local total, count = 0, 0
    for _, slot in ipairs(EQUIP_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            -- local ilvl = GetDetailedItemLevelInfo(link)
            local ilvl = C_Item.GetDetailedItemLevelInfo(link)
            if ilvl and ilvl > 0 then
                total = total + ilvl
                count = count + 1
            end
        end
    end
    if count > 0 then return math.floor(total / count + 0.5) end
    return nil
end

local function ShowIlvl(ilvl)
    if not targetFrame or not targetFrame.ilvlText then return end
    if ilvl and ilvl > 0 and JarUnitFramesDB.showTargetItemLevel then
        targetFrame.ilvlText:SetText("ilvl " .. ilvl)
        targetFrame.ilvlText:Show()
    else
        targetFrame.ilvlText:Hide()
    end
end

local function RequestTargetItemLevel()
    pendingGUID = nil
    if not JarUnitFramesDB.showTargetItemLevel then return end
    if not UnitExists("target") or not UnitIsPlayer("target") then return end
    if not CanInspect("target") then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    local guid = UnitGUID("target")
    if issecretvalue(guid) then return end
    pendingGUID = guid
    NotifyInspect("target")
end

-- still the same target we asked about?
local function IsPendingTarget()
    local guid = UnitGUID("target")
    return pendingGUID and not issecretvalue(guid) and guid == pendingGUID
end

local function TryReadInspectIlvl(attempt)
    if not IsPendingTarget() then
        pendingGUID = nil
        return
    end
    local ilvl = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
        and C_PaperDollInfo.GetInspectItemLevel("target")
    if not ilvl or ilvl <= 0 then
        ilvl = CalcInspectItemLevel("target")
    end
    if ilvl and ilvl > 0 then
        pendingGUID = nil
        ShowIlvl(ilvl)
    elseif attempt < 4 then
        C_Timer.After(0.5 * attempt, function() TryReadInspectIlvl(attempt + 1) end)
    else
        pendingGUID = nil
    end
end

local function OnInspectReady(guid)
    if not pendingGUID or issecretvalue(guid) or guid ~= pendingGUID then return end
    TryReadInspectIlvl(1)
end

-- Debuff filter presets for config dropdowns
local DEBUFF_FILTER_PRESETS = {
    { label = "All Debuffs",       value = "HARMFUL" },
    { label = "Raid-Relevant",     value = "HARMFUL|RAID" },
    -- { label = "Not Self",          value = "HARMFUL|NOT_SELF" },
    { label = "Not Self",          value = "HARMFUL|!PLAYER" },
}

-- Helper function to restore frame position
local function RestoreFramePosition(frame, savedPosTable)
    if not savedPosTable then return end
    frame:ClearAllPoints()
    frame:SetPoint(savedPosTable.point, UIParent, savedPosTable.point, savedPosTable.x, savedPosTable.y)
end

-- Helper function to update bar textures
local function UpdateFrameTextures(frame)
    local texture = ns.GetTexture()
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar.bg:SetTexture(texture)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar.bg:SetTexture(texture)
end

local function UpdateFrameFonts(frame)
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    
    -- Apply fonts directly
    if frame.healthText then
        frame.healthText:SetFont(font, fontSize, "OUTLINE")
    end
    if frame.name then
        frame.name:SetFont(font, fontSize, "OUTLINE")
    end
    if frame.levelText then
        frame.levelText:SetFont(font, fontSize, "OUTLINE")
    end
    if frame.ilvlText then
        frame.ilvlText:SetFont(font, fontSize, "OUTLINE")
    end
end

-- unit watch drives show/hide, we just turn it on or off
local function SetFrameEnabled(frame, enabled)
    if not frame then return end
    RunWhenSafe(frame, function()
        if enabled then
            RegisterUnitWatch(frame)
        else
            UnregisterUnitWatch(frame)
            frame:Hide()
        end
    end)
end

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL" }
local function RegisterUnitEvents(frame, unit)
    for _, event in ipairs(UNIT_EVENTS) do
        frame:RegisterUnitEvent(event, unit)
    end
end

-- class can be secret in 12.1, dont use it as a key then
local function GetUnitClassColor(unit)
    local _, class = UnitClass(unit)
    if issecretvalue(class) or not class then return end
    return RAID_CLASS_COLORS[class]
end

local function ForEachUnitFrame(fn)
    for _, f in pairs({ playerFrame, targetFrame, focusFrame, targetTargetFrame, petFrame }) do
        fn(f)
    end
    for i = 1, 4 do
        if partyFrames[i] then fn(partyFrames[i]) end
    end
end

local function ApplyFrameScale()
    RunWhenSafe("scale", function()
        for _, f in pairs({ playerFrame, targetFrame, focusFrame, targetTargetFrame, petFrame }) do
            f:SetScale(JarUnitFramesDB.frameScale)
        end
    end)
end

-- mirror around screen center, anchored to CENTER so it cant fly off screen
local function MirrorTargetPosition()
    if not playerFrame or not targetFrame then return end
    RunWhenSafe("mirror", function()
        local s = playerFrame:GetScale()
        local cx, cy = playerFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        JarUnitFramesDB.targetPos = { point = "CENTER", x = -(cx - ux / s), y = cy - uy / s }
        RestoreFramePosition(targetFrame, JarUnitFramesDB.targetPos)
    end)
end

-- 12.1 aura containers, one per buff/debuff row
local auraContainersOK
local function CanUseAuraContainers()
    if auraContainersOK == nil then
        -- auraContainersOK = select(4, GetBuildInfo()) >= 120100
        --     and pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate") or false
        -- forever's build is 16001 so that check always failed, just try it
        auraContainersOK = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not auraContainersOK then
            print("|cffff8c00Itsu:UI|r AuraContainer not available, buffs/debuffs are off")
        end
    end
    return auraContainersOK
end

-- style each AuraButton once, cant touch them later while auras are secret
local function NewAuraButtonInit(o)
    return function(btn)
        btn:SetSize(o.size, o.size)
        btn:SetTooltipAnchorPoint(o.tooltip or "ANCHOR_RIGHT")
        btn:EnableMouse(not o.isBuff or JarUnitFramesDB.enableAuraTooltips)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        btn:SetIcon(icon)

        if o.bordered then
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetAllPoints()
            border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
            border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        end

        -- no cooldown spiral, same as before
        if o.stacks then
            local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            count:SetPoint("BOTTOMRIGHT", 2, 0)
            btn:SetApplicationCount(count, {})
        end
    end
end

-- boss first = a "boss" group then everything else
local function CreateAuraRow(parent, o)
    if not CanUseAuraContainers() then return end

    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    c:SetPoint(o.point, o.relTo, o.relPoint, o.x, o.y)
    c:SetFlowLayoutAnchorPoint(o.point)
    c:SetFlowLayoutGrowthDirection(o.growX, o.growY)
    c:SetFlowLayoutMaximumLineSize(o.perRow * (o.size + 2))
    c.isBuff = o.isBuff
    c.groups = o.bossFirst and { "boss", "auras" } or { "auras" }

    local init = NewAuraButtonInit(o)
    for _, key in ipairs(c.groups) do
        local filters
        if key == "boss" then
            filters = { isBossAura = true }
        elseif o.bossFirst then
            filters = { isBossAura = false }
        elseif o.hidePermanent then
            filters = { maxDuration = math.huge }
        end
        c:AddAuraGroup(key, o.filter, {
            maxFrameCount = o.max,
            initializeFrame = init,
            candidateFilters = filters,
            sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
            sortDirection = AuraContainerSortDirection.Normal,
            layout = { elementSpacing = 2, lineSpacing = 2 },
        })
    end

    c:SetUnit(o.unit)
    c:SetEnabled(o.enabled ~= false)
    return c
end

local function SetAuraRowFilter(c, filter)
    if not c then return end
    for _, key in ipairs(c.groups) do
        c:SetAuraGroupFilterString(key, filter)
    end
end

local function SetAuraRowMax(c, max)
    if not c then return end
    for _, key in ipairs(c.groups) do
        c:SetAuraGroupMaxFrameCount(key, max)
    end
end

local function SetAuraRowShown(c, shown)
    if c then c:SetEnabled(shown) end
end

-- move + scale a buff/debuff row, scaling the container leaves the secret buttons alone.
-- offsets get divided by the scale since theyre in the containers own units
local function PlaceAuraRow(f, c, pos, scale)
    if not c then return end
    local right = MIRRORED[f.key]
    local p
    if pos == "above" then
        p = right and { "BOTTOMRIGHT", f.healthBar, "TOPRIGHT", 0, 2, -1, 1 }
            or { "BOTTOMLEFT", f.healthBar, "TOPLEFT", 0, 2, 1, 1 }
    elseif pos == "below" then
        p = right and { "TOPRIGHT", f.name, "BOTTOMRIGHT", 0, -2, -1, -1 }
            or { "TOPLEFT", f.name, "BOTTOMLEFT", 0, -2, 1, -1 }
    elseif pos == "left" then
        p = { "BOTTOMRIGHT", f.powerBar, "BOTTOMLEFT", -2, 0, -1, 1 }
    else
        p = { "BOTTOMLEFT", f.powerBar, "BOTTOMRIGHT", 2, 0, 1, 1 }
    end
    c:SetScale(scale)
    c:ClearAllPoints()
    c:SetPoint(p[1], p[2], p[3], p[4] / scale, p[5] / scale)
    c:SetFlowLayoutAnchorPoint(p[1])
    c:SetFlowLayoutGrowthDirection(p[6], p[7])
end

-- bar heights, width and aura rows from the db. gaps stay put: 2 between the bars
-- (party has none), name 5 under the power bar
local function ApplyFrameLayout(f)
    if not f or not f.key then return end
    local DB, key = JarUnitFramesDB, f.key
    local w, hp, pw = DB[key .. "Width"], DB[key .. "Health"], DB[key .. "Power"]
    RunWhenSafe("layout" .. f:GetName(), function()
        f.healthBar:SetSize(w, hp)
        f.powerBar:SetSize(w, pw)
        if key == "party" then
            f:SetSize(w, 7 + hp + pw + 10)
        else
            f.powerBar:SetPoint("TOP", 0, -(hp + 2))
            f:SetSize(w, hp + 2 + pw + ((key == "player" or key == "target") and 15 or 0))
        end
        PlaceAuraRow(f, f.buffRow, DB[key .. "BuffPos"], DB[key .. "BuffScale"])
        PlaceAuraRow(f, f.debuffRow, DB[key .. "DebuffPos"], DB[key .. "DebuffScale"])
        SetAuraRowShown(f.buffRow, DB[key .. "ShowBuffs"])
        SetAuraRowShown(f.debuffRow, DB[key .. "ShowDebuffs"])
    end)
end

local function RefreshAuras(frame)
    if not frame then return end
    if frame.buffRow then frame.buffRow:UpdateAllAuras() end
    if frame.debuffRow then frame.debuffRow:UpdateAllAuras() end
end

-- only works while auras arent secret, new buttons pick it up on creation anyway
local function ApplyAuraTooltipSetting(frame)
    local c = frame and frame.buffRow
    if not c or C_Secrets.ShouldAurasBeSecret() then return end
    for i = 1, c:GetAuraGroupFrameCount("auras") do
        c:GetAuraGroupFrame("auras", i):EnableMouse(JarUnitFramesDB.enableAuraTooltips)
    end
end

-- hide blizz frames the 12.1 way (like oUF), no reparenting or OnShow hooks
local function DisableBlizzardFrame(f)
    if not f then return end
    f:UnregisterAllEvents()
    f:SetRolesets("alwaysBlocked")
    local subs = {
        f.healthBar or f.healthbar or f.HealthBar or (f.HealthBarsContainer and f.HealthBarsContainer.healthBar),
        f.manabar or f.ManaBar,
        f.castBar or f.spellbar or f.CastingBarFrame,
        f.BuffFrame or f.AurasFrame,
        f.DebuffFrame,
        f.petFrame or f.PetFrame,
        f.totFrame,
    }
    for _, sub in pairs(subs) do
        sub:UnregisterAllEvents()
    end
end

local function HideBlizzardUnitFrames()
    RunWhenSafe("blizzUnits", function()
        for _, f in pairs({ PlayerFrame, TargetFrame, FocusFrame, PetFrame }) do
            DisableBlizzardFrame(f)
        end
    end)
end

-- party only, and only when ours are on. raid container is left alone
local function HideBlizzardPartyFrames()
    if not JarUnitFramesDB.showPartyFrames then return end
    RunWhenSafe("blizzParty", function()
        if PartyFrame then
            DisableBlizzardFrame(PartyFrame)
            for f in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                DisableBlizzardFrame(f)
            end
        end
        DisableBlizzardFrame(CompactPartyFrame)
        for i = 1, 5 do
            DisableBlizzardFrame(_G["CompactPartyFrameMember" .. i])
        end
    end)
end

-- Update frequency throttle (seconds)
local UPDATE_INTERVAL = 0.1
local timeSinceLastUpdate = 0

-- Forward declarations (locals, not globals)
local UpdatePlayerFrame, UpdateTargetFrame, UpdateFocusFrame, UpdateTargetTargetFrame, UpdatePetFrame, UpdatePartyFrame
local CreateFocusFrame, CreateTargetTargetFrame, CreatePetFrame, CreatePartyFrame, RepositionPartyFrames, SetupFrames

-- Create a custom player frame
local function CreatePlayerFrame()
    -- Get font settings early so they can be used throughout frame creation
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    
    local frame = CreateFrame("Button", "JUF_PlayerFrame", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 45)
    frame:SetAttribute("unit", "player")
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- per unit events, auras are the container's job now
    RegisterUnitEvents(frame, "player")
    frame:SetScript("OnEvent", function() UpdatePlayerFrame() end)
    
    -- Restore position or use default
    if JarUnitFramesDB.playerPos then
        RestoreFramePosition(frame, JarUnitFramesDB.playerPos)
    else
        frame:SetPoint("TOPLEFT", 20, -20)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable (modified for SecureUnitButtonTemplate)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if ns.db.general.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.playerPos.point = point
            JarUnitFramesDB.playerPos.x = x
            JarUnitFramesDB.playerPos.y = y
            
            -- Mirror target frame position if enabled
            if JarUnitFramesDB.mirrorTargetPosition then
                MirrorTargetPosition()
            end
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(220, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)  -- Allow clicks to pass through
    local texture = ns.GetTexture()
    frame.healthBar:SetStatusBarTexture(texture)
    
    -- Get class color for player
    local classColor = GetUnitClassColor("player")
    if classColor then
        frame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
    else
        frame.healthBar:SetStatusBarColor(0, 0.9, 0.8)  -- Fallback
    end
    
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(100)
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    if classColor then
        frame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
    else
        frame.healthBar.bg:SetVertexColor(0, 0.3, 0.3)
    end
    
    -- Health text (right side)
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.healthText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.healthText:SetJustifyH("RIGHT")
    frame.healthText:SetText("100")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)  -- Blue
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(100)
    frame.powerBar:SetScript("OnEnter", function(self)
        if not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("player")
            local maxPower = UnitPowerMax("player")
            local powerType = UnitPowerType("player")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Status icons (combat, resting, role)
    frame.statusIcons = CreateFrame("Frame", nil, frame)
    frame.statusIcons:SetSize(40, 16)
    frame.statusIcons:SetPoint("LEFT", frame.healthBar, "LEFT", 2, 0)
    
    -- Combat icon
    frame.combatIcon = frame.statusIcons:CreateTexture(nil, "OVERLAY")
    frame.combatIcon:SetSize(16, 16)
    frame.combatIcon:SetPoint("LEFT", 0, 0)
    frame.combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    frame.combatIcon:SetTexCoord(0.5, 1.0, 0.0, 0.49)
    frame.combatIcon:Hide()
    
    -- Resting icon
    frame.restingIcon = frame.statusIcons:CreateTexture(nil, "OVERLAY")
    frame.restingIcon:SetSize(16, 16)
    frame.restingIcon:SetPoint("LEFT", 18, 0)
    frame.restingIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    frame.restingIcon:SetTexCoord(0.0, 0.5, 0.0, 0.49)
    frame.restingIcon:Hide()
    
    -- Level text (optional)
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.levelText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    if JarUnitFramesDB.showLevel then
        frame.levelText:SetText(UnitLevel("player"))
    else
        frame.levelText:SetText("")
    end
    
    -- Name text (below the frame)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("Player")
    
    -- Buffs above, debuffs below
    frame.buffRow = CreateAuraRow(frame, {
        unit = "player", filter = "HELPFUL", isBuff = true, max = 40,
        hidePermanent = JarUnitFramesDB.hidePlayerPermanentBuffs,
        size = 20, perRow = 10, bordered = true, stacks = true,
        point = "BOTTOMLEFT", relTo = frame.healthBar, relPoint = "TOPLEFT", x = 0, y = 2, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "player", filter = JarUnitFramesDB.playerDebuffFilter or "HARMFUL", bossFirst = true,
        max = JarUnitFramesDB.playerMaxDebuffs or 40,
        size = 20, perRow = 10, bordered = true, stacks = true,
        point = "TOPLEFT", relTo = frame.healthBar, relPoint = "BOTTOMLEFT", x = 0, y = -35, growX = 1, growY = -1,
    })

    UpdateFrameFonts(frame)
    
    return frame
end

-- Create a custom target frame
local function CreateTargetFrame()
    -- Get font settings early so they can be used throughout frame creation
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    
    local frame = CreateFrame("Button", "JUF_TargetFrame", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 45)
    frame:SetAttribute("unit", "target")
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Register events
    RegisterUnitEvents(frame, "target")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("INSPECT_READY")

    frame:SetScript("OnEvent", function(self, event, arg1)
        if event == "INSPECT_READY" then
            OnInspectReady(arg1)  -- arg1 is the GUID here
        elseif event == "PLAYER_TARGET_CHANGED" then
            ShowIlvl(nil)
            UpdateTargetFrame()
            RefreshAuras(self)
            RequestTargetItemLevel()
        else
            UpdateTargetFrame()
        end
    end)
    
    -- Restore position or use default
    if JarUnitFramesDB.targetPos then
        RestoreFramePosition(frame, JarUnitFramesDB.targetPos)
    else
        frame:SetPoint("TOPLEFT", 260, -20)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable (modified for SecureUnitButtonTemplate)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if ns.db.general.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.targetPos.point = point
            JarUnitFramesDB.targetPos.x = x
            JarUnitFramesDB.targetPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(220, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)  -- Allow clicks to pass through
    local texture = ns.GetTexture()
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(true)  -- Fill from right to left
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
    
    -- Health text (left side)
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Level text (optional)
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.levelText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(true)  -- Fill from right to left
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("target") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("target")
            local maxPower = UnitPowerMax("target")
            local powerType = UnitPowerType("target")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Name text (below the frame, right side)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPRIGHT", frame.powerBar, "BOTTOMRIGHT", 0, -5)
    frame.name:SetJustifyH("RIGHT")
    frame.name:SetText("No Target")

    -- Item level text (below the frame, left side)
    frame.ilvlText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.ilvlText:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.ilvlText:SetJustifyH("LEFT")
    frame.ilvlText:SetTextColor(0.6, 0.8, 1.0)
    frame.ilvlText:Hide()
    
    -- Buffs above, debuffs below, both growing right to left
    frame.buffRow = CreateAuraRow(frame, {
        unit = "target", filter = "HELPFUL", isBuff = true, max = 40,
        hidePermanent = JarUnitFramesDB.hideTargetPermanentBuffs,
        size = 20, perRow = 10, bordered = true, stacks = true, tooltip = "ANCHOR_LEFT",
        point = "BOTTOMRIGHT", relTo = frame.healthBar, relPoint = "TOPRIGHT", x = 0, y = 2, growX = -1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "target", filter = JarUnitFramesDB.targetDebuffFilter or "HARMFUL", bossFirst = true,
        max = JarUnitFramesDB.targetMaxDebuffs or 40,
        size = 20, perRow = 10, bordered = true, stacks = true, tooltip = "ANCHOR_LEFT",
        point = "TOPRIGHT", relTo = frame.healthBar, relPoint = "BOTTOMRIGHT", x = 0, y = -35, growX = -1, growY = -1,
    })

    UpdateFrameFonts(frame)
    return frame
end

-- Create Focus Frame
function CreateFocusFrame()
    local frame = CreateFrame("Button", "JarUnitFrameFocus", UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(220, 30)
    frame:SetAttribute("unit", "focus")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Register events
    RegisterUnitEvents(frame, "focus")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")

    frame:SetScript("OnEvent", function(self, event)
        UpdateFocusFrame()
        if event == "PLAYER_FOCUS_CHANGED" then
            RefreshAuras(self)
        end
    end)
    
    -- Restore position or use default
    if JarUnitFramesDB.focusPos then
        RestoreFramePosition(frame, JarUnitFramesDB.focusPos)
    else
        frame:SetPoint("TOPLEFT", 500, -20)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if ns.db.general.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.focusPos.point = point
            JarUnitFramesDB.focusPos.x = x
            JarUnitFramesDB.focusPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = ns.GetTexture()
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(220, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(true)
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Level text
    frame.levelText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -5, 0)
    frame.levelText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(220, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(true)
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("focus") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("focus")
            local maxPower = UnitPowerMax("focus")
            local powerType = UnitPowerType("focus")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPRIGHT", frame.powerBar, "BOTTOMRIGHT", 0, -5)
    frame.name:SetJustifyH("RIGHT")
    frame.name:SetText("No Focus")
    
    -- Buffs above, debuffs below the name
    frame.buffRow = CreateAuraRow(frame, {
        unit = "focus", filter = "HELPFUL", isBuff = true, max = 40, enabled = JarUnitFramesDB.focusShowBuffs,
        size = 18, perRow = 10,
        point = "BOTTOMRIGHT", relTo = frame.healthBar, relPoint = "TOPRIGHT", x = 0, y = 2, growX = -1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "focus", filter = JarUnitFramesDB.focusDebuffFilter or "HARMFUL|RAID", bossFirst = true,
        max = 40, enabled = JarUnitFramesDB.focusShowDebuffs,
        size = 18, perRow = 10,
        point = "TOPRIGHT", relTo = frame.name, relPoint = "BOTTOMRIGHT", x = 0, y = -2, growX = -1, growY = -1,
    })

    UpdateFrameFonts(frame)
    
    return frame
end

-- Create Target of Target Frame
function CreateTargetTargetFrame()
    local frame = CreateFrame("Button", "JarUnitFrameTargetTarget", UIParent, "SecureUnitButtonTemplate")
    local width = JarUnitFramesDB.totWidth or 150
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "targettarget")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- targettarget has no unit events, so UNIT_TARGET on target + polling in OnUpdate
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterUnitEvent("UNIT_TARGET", "target")

    frame:SetScript("OnEvent", function(self)
        UpdateTargetTargetFrame()
        RefreshAuras(self)
    end)
    
    -- Restore position or use default
    if JarUnitFramesDB.totPos then
        RestoreFramePosition(frame, JarUnitFramesDB.totPos)
    else
        frame:SetPoint("TOPLEFT", 260, -100)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if ns.db.general.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.totPos.point = point
            JarUnitFramesDB.totPos.x = x
            JarUnitFramesDB.totPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = ns.GetTexture()
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(width, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(false)  -- Fill left to right for ToT
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(false)
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("targettarget") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("targettarget")
            local maxPower = UnitPowerMax("targettarget")
            local powerType = UnitPowerType("targettarget")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("No ToT")
    
    -- Buffs above, debuffs below the name
    frame.buffRow = CreateAuraRow(frame, {
        unit = "targettarget", filter = "HELPFUL", isBuff = true, max = 20, enabled = JarUnitFramesDB.totShowBuffs,
        size = 18, perRow = 7,
        point = "BOTTOMLEFT", relTo = frame.healthBar, relPoint = "TOPLEFT", x = 0, y = 2, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "targettarget", filter = JarUnitFramesDB.totDebuffFilter or "HARMFUL|RAID", bossFirst = true,
        max = 20, enabled = JarUnitFramesDB.totShowDebuffs,
        size = 18, perRow = 7,
        point = "TOPLEFT", relTo = frame.name, relPoint = "BOTTOMLEFT", x = 0, y = -2, growX = 1, growY = -1,
    })

    UpdateFrameFonts(frame)
    
    return frame
end

-- Create Pet Frame
function CreatePetFrame()
    local frame = CreateFrame("Button", "JarUnitFramePet", UIParent, "SecureUnitButtonTemplate")
    local width = JarUnitFramesDB.petWidth or 150
    frame:SetSize(width, 30)
    frame:SetAttribute("unit", "pet")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    
    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Register events
    RegisterUnitEvents(frame, "pet")
    frame:RegisterUnitEvent("UNIT_PET", "player")

    frame:SetScript("OnEvent", function(self, event)
        UpdatePetFrame()
        if event == "UNIT_PET" then
            RefreshAuras(self)
        end
    end)
    
    -- Restore position or use default
    if JarUnitFramesDB.petPos then
        RestoreFramePosition(frame, JarUnitFramesDB.petPos)
    else
        frame:SetPoint("TOPLEFT", 20, -200)
    end
    
    frame:SetScale(JarUnitFramesDB.frameScale)
    
    -- Make draggable
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if ns.db.general.unlocked then
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.petPos.point = point
            JarUnitFramesDB.petPos.x = x
            JarUnitFramesDB.petPos.y = y
        end
    end)
    
    -- Drop shadow
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = ns.GetTexture()
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(width, 20)
    frame.healthBar:SetPoint("TOP", 0, 0)
    frame.healthBar:EnableMouse(false)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetStatusBarColor(1, 0, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(0)
    frame.healthBar:SetReverseFill(false)
    
    -- Health bar border
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Health bar background
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.healthText:SetPoint("LEFT", frame.healthBar, "LEFT", 5, 0)
    frame.healthText:SetJustifyH("LEFT")
    frame.healthText:SetText("0")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", 0, -22)
    frame.powerBar:EnableMouse(true)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    frame.powerBar:SetReverseFill(false)
    frame.powerBar:SetScript("OnEnter", function(self)
        if UnitExists("pet") and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local power = UnitPower("pet")
            local maxPower = UnitPowerMax("pet")
            local powerType = UnitPowerType("pet")
            local powerName = _G["POWER_TYPE_" .. (powerType or 0)] or "Power"
            GameTooltip:SetText(powerName, 1, 1, 1)
            GameTooltip:AddLine(BreakUpLargeNumbers(power) .. " / " .. BreakUpLargeNumbers(maxPower), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.powerBar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then
            GameTooltip:Hide()
        end
    end)
    
    -- Power bar border
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Power bar background
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -5)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("No Pet")
    
    -- Buffs above, debuffs below the name
    frame.buffRow = CreateAuraRow(frame, {
        unit = "pet", filter = "HELPFUL", isBuff = true, max = 20, enabled = JarUnitFramesDB.petShowBuffs,
        size = 18, perRow = 7,
        point = "BOTTOMLEFT", relTo = frame.healthBar, relPoint = "TOPLEFT", x = 0, y = 2, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "pet", filter = JarUnitFramesDB.petDebuffFilter or "HARMFUL", bossFirst = true,
        max = 20, enabled = JarUnitFramesDB.petShowDebuffs,
        size = 18, perRow = 7,
        point = "TOPLEFT", relTo = frame.name, relPoint = "BOTTOMLEFT", x = 0, y = -2, growX = 1, growY = -1,
    })

    UpdateFrameFonts(frame)
    return frame
end

-- Create party frame (for party1-4)
function CreatePartyFrame(partyNum)
    local font = ns.GetFont()
    local fontSize = JarUnitFramesDB.fontSize or 12
    local texture = ns.GetTexture()
    local width = JarUnitFramesDB.partyWidth or 150
    
    local frame = CreateFrame("Button", "JUF_PartyFrame"..partyNum, UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(width, 45)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetAttribute("unit", "party"..partyNum)
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")

    -- Proper tooltip handling for SecureUnitButton (prevents taint)
    frame:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Make frame movable when unlocked (use Shift+Drag to avoid conflicts with secure clicks)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.general.unlocked and IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position only for first party frame
        if partyNum == 1 then
            local point, _, _, x, y = self:GetPoint()
            JarUnitFramesDB.partyPos = {point = point, x = x, y = y}
        end
    end)
    
    -- Add visual border when unlocked
    frame.unlockBorder = frame:CreateTexture(nil, "OVERLAY")
    frame.unlockBorder:SetAllPoints()
    frame.unlockBorder:SetColorTexture(0, 1, 0, 0.3)
    frame.unlockBorder:SetShown(ns.db.general.unlocked)
    
    -- Register events
    RegisterUnitEvents(frame, "party"..partyNum)
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")

    frame:SetScript("OnEvent", function(self, event)
        UpdatePartyFrame(partyNum)
        if event == "GROUP_ROSTER_UPDATE" then
            RefreshAuras(self)
        end
    end)
    
    -- Drop shadow background
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND")
    frame.shadow:SetPoint("TOPLEFT", -3, 3)
    frame.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    frame.shadow:SetColorTexture(0, 0, 0, ns.db.general.bgAlpha)
    
    -- Health bar
    frame.healthBar = CreateFrame("StatusBar", nil, frame)
    frame.healthBar:SetSize(width, 20)
    frame.healthBar:SetPoint("TOP", 0, -7)
    frame.healthBar:SetStatusBarTexture(texture)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(100)
    
    frame.healthBar.border = CreateFrame("Frame", nil, frame.healthBar, "BackdropTemplate")
    frame.healthBar.border:SetAllPoints()
    frame.healthBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.healthBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame.healthBar.bg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
    frame.healthBar.bg:SetAllPoints(frame.healthBar)
    frame.healthBar.bg:SetTexture(texture)
    frame.healthBar.bg:SetVertexColor(0, 0.4, 0)
    frame.healthBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Health text
    frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY")
    frame.healthText:SetPoint("RIGHT", frame.healthBar, "RIGHT", -3, 0)
    frame.healthText:SetFont(font, fontSize, "OUTLINE")
    frame.healthText:SetTextColor(1, 1, 0)
    frame.healthText:SetJustifyH("RIGHT")
    frame.healthText:SetText("")
    
    -- Power bar
    frame.powerBar = CreateFrame("StatusBar", nil, frame)
    frame.powerBar:SetSize(width, 8)
    frame.powerBar:SetPoint("TOP", frame.healthBar, "BOTTOM", 0, 0)
    frame.powerBar:SetStatusBarTexture(texture)
    frame.powerBar:SetStatusBarColor(0, 0.4, 1)
    frame.powerBar:SetMinMaxValues(0, 100)
    frame.powerBar:SetValue(0)
    
    frame.powerBar.border = CreateFrame("Frame", nil, frame.powerBar, "BackdropTemplate")
    frame.powerBar.border:SetAllPoints()
    frame.powerBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.powerBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame.powerBar.bg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
    frame.powerBar.bg:SetAllPoints(frame.powerBar)
    frame.powerBar.bg:SetTexture(texture)
    frame.powerBar.bg:SetVertexColor(0, 0, 0.4)
    frame.powerBar.bg:SetAlpha(ns.db.general.bgAlpha)
    
    -- Name text
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("TOPLEFT", frame.powerBar, "BOTTOMLEFT", 0, -2)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetText("Party "..partyNum)
    
    -- Buffs grow right off the power bar, debuffs grow left
    frame.buffRow = CreateAuraRow(frame, {
        unit = "party"..partyNum, filter = JarUnitFramesDB.partyShowOnlyMyBuffs and "HELPFUL|PLAYER" or "HELPFUL",
        isBuff = true, max = 15,
        size = 18, perRow = 5, bordered = true, stacks = true,
        point = "BOTTOMLEFT", relTo = frame.powerBar, relPoint = "BOTTOMRIGHT", x = 2, y = 0, growX = 1, growY = 1,
    })
    frame.debuffRow = CreateAuraRow(frame, {
        unit = "party"..partyNum, filter = JarUnitFramesDB.partyDebuffFilter or "HARMFUL|RAID", bossFirst = true,
        max = 15,
        size = 18, perRow = 5, bordered = true, stacks = true, tooltip = "ANCHOR_LEFT",
        point = "BOTTOMRIGHT", relTo = frame.powerBar, relPoint = "BOTTOMLEFT", x = -2, y = 0, growX = -1, growY = 1,
    })

    UpdateFrameFonts(frame)
    return frame
end

-- Update player frame
function UpdatePlayerFrame()
    if not playerFrame then return end
    
    -- Get player name (NOT secret for player unit)
    local name = UnitName("player")
    if name then
        playerFrame.name:SetText(name)
    end
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel then
        playerFrame.levelText:SetText(UnitLevel("player"))
    else
        playerFrame.levelText:SetText("")
    end
    
    -- Update status icons
    if UnitAffectingCombat("player") then
        playerFrame.combatIcon:Show()
    else
        playerFrame.combatIcon:Hide()
    end
    
    if IsResting() then
        playerFrame.restingIcon:Show()
    else
        playerFrame.restingIcon:Hide()
    end
    
    -- Get health values (these are SECRET values)
    local health = UnitHealth("player")  -- Secret value
    local maxHealth = UnitHealthMax("player")  -- Secret value
    
    -- KEY: Pass secret values DIRECTLY to StatusBar:SetValue()
    -- StatusBar:SetValue() accepts secret values even from tainted code!
    playerFrame.healthBar:SetMinMaxValues(0, maxHealth)
    playerFrame.healthBar:SetValue(health)
    
    -- For text display, we can use concatenation in UNTAINTED code
    -- But tainted code cannot do math/comparison on secrets
    -- Solution: Use StatusBar percentage display or just show bars
    -- Show numeric values with comma separators
    playerFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values (also secret) and color by type
    local power = UnitPower("player")
    local maxPower = UnitPowerMax("player")
    local powerType = UnitPowerType("player")
    
    -- Pass directly to status bar
    playerFrame.powerBar:SetMinMaxValues(0, maxPower)
    playerFrame.powerBar:SetValue(power)
    
    -- Update power bar color based on power type
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        playerFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        playerFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
end

-- Update target frame
function UpdateTargetFrame()
    if not targetFrame then return end
    
    -- unit watch does show/hide now
    if not UnitExists("target") then return end

    -- name can be secret, pass it straight thru
    targetFrame.name:SetText(UnitName("target"))
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel and UnitLevel("target") then
        targetFrame.levelText:SetText(UnitLevel("target"))
    else
        targetFrame.levelText:SetText("")
    end

    -- Update item level display (only show cached value on retarget; fresh request fires separately)
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        ShowIlvl(nil)
    end
    
    -- Get health values (secret)
    local health = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")
    
    -- Pass directly to status bar
    targetFrame.healthBar:SetMinMaxValues(0, maxHealth)
    targetFrame.healthBar:SetValue(health)
    
    -- Show numeric values with comma separators
    targetFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values and color by power type
    local power = UnitPower("target")
    local maxPower = UnitPowerMax("target")
    local powerType = UnitPowerType("target")
    
    targetFrame.powerBar:SetMinMaxValues(0, maxPower)
    targetFrame.powerBar:SetValue(power)
    
    -- Color power bar by power type
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        targetFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        targetFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color by class if player, otherwise by reaction
    if UnitIsPlayer("target") then
        local classColor = GetUnitClassColor("target")
        if classColor then
            targetFrame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            targetFrame.healthBar:SetStatusBarDesaturated(false)
            targetFrame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
        else
            -- Fallback: Red if enemy, green if friendly
            if UnitIsEnemy("player", "target") then
                targetFrame.healthBar:SetStatusBarColor(1, 0, 0)
                targetFrame.healthBar.bg:SetVertexColor(0.3, 0, 0)
            else
                targetFrame.healthBar:SetStatusBarColor(0, 1, 0)
                targetFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
            end
        end
    else
        -- NPC coloring
        local reaction = UnitReaction("target", "player")
        if reaction and reaction <= 3 then
            targetFrame.healthBar:SetStatusBarColor(1, 0, 0)
        elseif reaction and reaction >= 5 then
            targetFrame.healthBar:SetStatusBarColor(0, 1, 0)
        else
            targetFrame.healthBar:SetStatusBarColor(1, 1, 0)
        end
    end
end

-- Update focus frame
function UpdateFocusFrame()
    if not focusFrame then return end
    
    if not UnitExists("focus") then return end

    focusFrame.name:SetText(UnitName("focus"))
    
    -- Update level if enabled
    if JarUnitFramesDB.showLevel and UnitLevel("focus") then
        focusFrame.levelText:SetText(UnitLevel("focus"))
    else
        focusFrame.levelText:SetText("")
    end
    
    -- Get health values
    local health = UnitHealth("focus")
    local maxHealth = UnitHealthMax("focus")
    
    focusFrame.healthBar:SetMinMaxValues(0, maxHealth)
    focusFrame.healthBar:SetValue(health)
    focusFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower("focus")
    local maxPower = UnitPowerMax("focus")
    local powerType = UnitPowerType("focus")
    
    focusFrame.powerBar:SetMinMaxValues(0, maxPower)
    focusFrame.powerBar:SetValue(power)
    
    -- Color power bar
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        focusFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        focusFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color health bar by class/reaction
    if UnitIsPlayer("focus") then
        local classColor = GetUnitClassColor("focus")
        if classColor then
            focusFrame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            focusFrame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
        else
            if UnitIsEnemy("player", "focus") then
                focusFrame.healthBar:SetStatusBarColor(1, 0, 0)
                focusFrame.healthBar.bg:SetVertexColor(0.3, 0, 0)
            else
                focusFrame.healthBar:SetStatusBarColor(0, 1, 0)
                focusFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
            end
        end
    else
        local reaction = UnitReaction("focus", "player")
        if reaction and reaction <= 3 then
            focusFrame.healthBar:SetStatusBarColor(1, 0, 0)
        elseif reaction and reaction >= 5 then
            focusFrame.healthBar:SetStatusBarColor(0, 1, 0)
        else
            focusFrame.healthBar:SetStatusBarColor(1, 1, 0)
        end
    end
end

-- Update target of target frame
function UpdateTargetTargetFrame()
    if not targetTargetFrame then return end
    
    -- unit watch handles visibility
    if not UnitExists("targettarget") then return end

    targetTargetFrame.name:SetText(UnitName("targettarget"))
    
    -- Get health values
    local health = UnitHealth("targettarget")
    local maxHealth = UnitHealthMax("targettarget")
    
    targetTargetFrame.healthBar:SetMinMaxValues(0, maxHealth)
    targetTargetFrame.healthBar:SetValue(health)
    targetTargetFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower("targettarget")
    local maxPower = UnitPowerMax("targettarget")
    local powerType = UnitPowerType("targettarget")
    
    targetTargetFrame.powerBar:SetMinMaxValues(0, maxPower)
    targetTargetFrame.powerBar:SetValue(power)
    
    -- Color power bar
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        targetTargetFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        targetTargetFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color health bar by class/reaction
    if UnitIsPlayer("targettarget") then
        local classColor = GetUnitClassColor("targettarget")
        if classColor then
            targetTargetFrame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            targetTargetFrame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
        else
            if UnitIsEnemy("player", "targettarget") then
                targetTargetFrame.healthBar:SetStatusBarColor(1, 0, 0)
                targetTargetFrame.healthBar.bg:SetVertexColor(0.3, 0, 0)
            else
                targetTargetFrame.healthBar:SetStatusBarColor(0, 1, 0)
                targetTargetFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
            end
        end
    else
        local reaction = UnitReaction("targettarget", "player")
        if reaction and reaction <= 3 then
            targetTargetFrame.healthBar:SetStatusBarColor(1, 0, 0)
        elseif reaction and reaction >= 5 then
            targetTargetFrame.healthBar:SetStatusBarColor(0, 1, 0)
        else
            targetTargetFrame.healthBar:SetStatusBarColor(1, 1, 0)
        end
    end
end

-- Update pet frame
function UpdatePetFrame()
    if not petFrame then return end
    
    if not UnitExists("pet") then return end

    petFrame.name:SetText(UnitName("pet"))
    
    -- Get health values
    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")
    
    petFrame.healthBar:SetMinMaxValues(0, maxHealth)
    petFrame.healthBar:SetValue(health)
    petFrame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower("pet")
    local maxPower = UnitPowerMax("pet")
    local powerType = UnitPowerType("pet")
    
    petFrame.powerBar:SetMinMaxValues(0, maxPower)
    petFrame.powerBar:SetValue(power)
    
    -- Color power bar
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        petFrame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        petFrame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color health bar (green for friendly pet)
    petFrame.healthBar:SetStatusBarColor(0, 1, 0)
    petFrame.healthBar.bg:SetVertexColor(0, 0.3, 0)
end

-- Reposition party frames based on width and padding settings
function RepositionPartyFrames()
    if not partyFrames[1] then return end
    
    local width = JarUnitFramesDB.partyWidth
    local padding = JarUnitFramesDB.partyPadding
    
    -- Clear all anchor points first
    for i = 1, 4 do
        if partyFrames[i] then
            partyFrames[i]:ClearAllPoints()
        end
    end
    
    -- Position first frame
    if JarUnitFramesDB.partyPos then
        partyFrames[1]:SetPoint(JarUnitFramesDB.partyPos.point or "LEFT", UIParent, JarUnitFramesDB.partyPos.point or "LEFT", JarUnitFramesDB.partyPos.x, JarUnitFramesDB.partyPos.y)
    else
        partyFrames[1]:SetPoint("LEFT", UIParent, "LEFT", 50, 0)
    end
    
    -- Set width for all frames and position vertically
    for i = 1, 4 do
        if partyFrames[i] then
            local f = partyFrames[i]
            
            -- Update frame width
            f:SetWidth(width)
            
            -- Update health bar width
            if f.healthBar then
                f.healthBar:SetWidth(width)
            end
            
            -- Update power bar width
            if f.powerBar then
                f.powerBar:SetWidth(width)
            end
            
            -- Position frames 2-4 below the previous frame with padding
            if i > 1 then
                f:SetPoint("TOPLEFT", partyFrames[i-1], "BOTTOMLEFT", 0, -padding)
            end
        end
    end
end

-- Update party frame
function UpdatePartyFrame(partyNum)
    local frame = partyFrames[partyNum]
    if not frame then return end
    
    local unit = "party"..partyNum
    
    -- Check if party member exists (RegisterUnitWatch handles show/hide)
    if not UnitExists(unit) then
        return
    end
    
    -- Update name
    frame.name:SetText(UnitName(unit))
    
    -- Get health values (secret values)
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    
    -- Pass directly to status bar
    frame.healthBar:SetMinMaxValues(0, maxHealth)
    frame.healthBar:SetValue(health)
    
    -- Show numeric values
    frame.healthText:SetText(BreakUpLargeNumbers(health))
    
    -- Get power values
    local power = UnitPower(unit)
    local maxPower = UnitPowerMax(unit)
    local powerType = UnitPowerType(unit)
    
    frame.powerBar:SetMinMaxValues(0, maxPower)
    frame.powerBar:SetValue(power)
    
    -- Color power bar by power type
    local powerColor = PowerBarColor[powerType]
    if powerColor then
        frame.powerBar:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
        frame.powerBar.bg:SetVertexColor(powerColor.r * 0.3, powerColor.g * 0.3, powerColor.b * 0.3)
    end
    
    -- Color by class if player
    local colored = false
    if UnitIsPlayer(unit) then
        local classColor = GetUnitClassColor(unit)
        if classColor then
            frame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            frame.healthBar:SetStatusBarDesaturated(false)
            frame.healthBar.bg:SetVertexColor(classColor.r * 0.3, classColor.g * 0.3, classColor.b * 0.3)
            colored = true
        end
    end
    
    -- If not colored by class, use reaction or default green
    if not colored then
        local reaction = UnitReaction(unit, "player")
        if reaction and reaction <= 3 then
            frame.healthBar:SetStatusBarColor(1, 0, 0)
            frame.healthBar.bg:SetVertexColor(0.3, 0, 0)
        elseif reaction and reaction >= 5 then
            frame.healthBar:SetStatusBarColor(0, 1, 0)
            frame.healthBar.bg:SetVertexColor(0, 0.3, 0)
        else
            frame.healthBar:SetStatusBarColor(1, 1, 0)
            frame.healthBar.bg:SetVertexColor(0.3, 0.3, 0)
        end
    end
end

-- Main update function, also polls ToT since it has no events
local totTick = 0
local function OnUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < UPDATE_INTERVAL then return end
    timeSinceLastUpdate = 0

    if JarUnitFramesDB.showPlayerFrame then
        UpdatePlayerFrame()
    end

    if JarUnitFramesDB.showTargetFrame then
        UpdateTargetFrame()
    end

    if targetTargetFrame and JarUnitFramesDB.showTargetTargetFrame then
        UpdateTargetTargetFrame()
        totTick = totTick + 1
        if totTick >= 5 then
            totTick = 0
            RefreshAuras(targetTargetFrame)
        end
    end
end

local function UpdateAllFrames()
    UpdatePlayerFrame()
    UpdateTargetFrame()
    UpdateFocusFrame()
    UpdateTargetTargetFrame()
    UpdatePetFrame()
    for i = 1, 4 do
        UpdatePartyFrame(i)
    end
    ForEachUnitFrame(RefreshAuras)
end

-- create whatever is enabled (once) and set unit watches. queued in combat
function SetupFrames()
    RunWhenSafe("setup", function()
        playerFrame = playerFrame or CreatePlayerFrame()
        targetFrame = targetFrame or CreateTargetFrame()
        if JarUnitFramesDB.showFocusFrame then
            focusFrame = focusFrame or CreateFocusFrame()
        end
        if JarUnitFramesDB.showTargetTargetFrame then
            targetTargetFrame = targetTargetFrame or CreateTargetTargetFrame()
        end
        if JarUnitFramesDB.showPetFrame then
            petFrame = petFrame or CreatePetFrame()
        end
        if JarUnitFramesDB.showPartyFrames and not partyFrames[1] then
            for i = 1, 4 do
                partyFrames[i] = CreatePartyFrame(i)
            end
            RepositionPartyFrames()
        end

        for key, f in pairs({ player = playerFrame, target = targetFrame, focus = focusFrame, tot = targetTargetFrame, pet = petFrame }) do
            f.key = key
            ApplyFrameLayout(f)
        end
        for i = 1, 4 do
            if partyFrames[i] then
                partyFrames[i].key = "party"
                ApplyFrameLayout(partyFrames[i])
            end
        end

        SetFrameEnabled(playerFrame, JarUnitFramesDB.showPlayerFrame)
        SetFrameEnabled(targetFrame, JarUnitFramesDB.showTargetFrame)
        SetFrameEnabled(focusFrame, JarUnitFramesDB.showFocusFrame)
        SetFrameEnabled(targetTargetFrame, JarUnitFramesDB.showTargetTargetFrame)
        SetFrameEnabled(petFrame, JarUnitFramesDB.showPetFrame)
        for i = 1, 4 do
            SetFrameEnabled(partyFrames[i], JarUnitFramesDB.showPartyFrames)
        end

        UpdateAllFrames()
    end)
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Initialize defaults for any missing fields (after SavedVariables are loaded)
        for key, value in pairs(defaults) do
            if JarUnitFramesDB[key] == nil then
                JarUnitFramesDB[key] = value
            end
        end

        HideBlizzardUnitFrames()
        HideBlizzardPartyFrames()
        SetupFrames()

        self:SetScript("OnUpdate", OnUpdate)

    elseif event == "PLAYER_ENTERING_WORLD" then
        HideBlizzardPartyFrames()
        UpdateAllFrames()

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- blizz party frames can come back when the group changes
        HideBlizzardPartyFrames()

    end
end)

-- Slash commands
SLASH_JARUNITFRAMES1 = "/juf"
SLASH_JARUNITFRAMES2 = "/jarunitframes"
SlashCmdList["JARUNITFRAMES"] = function(msg)
    msg = msg:lower():trim()
    
    if msg == "config" or msg == "" then
        ns.OpenConfig("All Frames")

    elseif msg == "toggle" then
        JarUnitFramesDB.showPlayerFrame = not JarUnitFramesDB.showPlayerFrame
        JarUnitFramesDB.showTargetFrame = not JarUnitFramesDB.showTargetFrame
        
        -- unit watch on/off, queued if in combat
        SetupFrames()
        
        print("|cffff8c00Itsu:UI|r " .. (JarUnitFramesDB.showPlayerFrame and "shown" or "hidden"))
        
    elseif msg == "scale" then
        print("Usage: /juf scale <number> (e.g., /juf scale 1.2)")
        
    elseif msg:match("^scale%s+(.+)") then
        local scale = tonumber(msg:match("^scale%s+(.+)"))
        if scale and scale > 0.5 and scale < 3 then
            JarUnitFramesDB.frameScale = scale
            ApplyFrameScale()
            print("|cffff8c00Itsu:UI|r scale set to " .. scale)
        else
            print("|cffff0000Error:|r Scale must be between 0.5 and 3.0")
        end
        
    elseif msg == "percent" then
        JarUnitFramesDB.showPercentages = not JarUnitFramesDB.showPercentages
        print("|cffff8c00Itsu:UI|r percentages " .. (JarUnitFramesDB.showPercentages and "shown" or "hidden"))
        UpdatePlayerFrame()
        UpdateTargetFrame()
        if focusFrame then
            UpdateFocusFrame()
        end
        if targetTargetFrame then
            UpdateTargetTargetFrame()
        end
        if petFrame then
            UpdatePetFrame()
        end
        
    elseif msg == "buffs" then
        -- List all current player buffs with their spell IDs (secret in combat, so skip then)
        if C_Secrets.ShouldAurasBeSecret() then
            print("|cffff8c00Itsu:UI|r Buffs are hidden right now (combat/instance), try again later")
            return
        end
        local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 40, nil, nil)
        print("|cffff8c00Itsu:UI|r Current Buffs:")
        for i, auraData in ipairs(auras) do
            if not issecretvalue(auraData.name) then
                local stacks = (auraData.applications and auraData.applications > 1) and (" x" .. auraData.applications) or ""
                print("  " .. i .. ". " .. auraData.name .. stacks .. " (ID: " .. auraData.spellId .. ")")
            end
        end
        if #auras == 0 then
            print("  No buffs active")
        end
        
    elseif msg == "showconfig" then
        print("|cffff8c00Itsu:UI|r Current Configuration:")
        print("  showPlayerFrame: " .. tostring(JarUnitFramesDB.showPlayerFrame))
        print("  showTargetFrame: " .. tostring(JarUnitFramesDB.showTargetFrame))
        print("  showPercentages: " .. tostring(JarUnitFramesDB.showPercentages))
        print("  showLevel: " .. tostring(JarUnitFramesDB.showLevel))
        print("  frameScale: " .. tostring(JarUnitFramesDB.frameScale))
        print("  mirrorTargetPosition: " .. tostring(JarUnitFramesDB.mirrorTargetPosition))
        print("  playerPos: point=" .. tostring(JarUnitFramesDB.playerPos.point) .. 
              ", x=" .. tostring(JarUnitFramesDB.playerPos.x) .. 
              ", y=" .. tostring(JarUnitFramesDB.playerPos.y))
        print("  targetPos: point=" .. tostring(JarUnitFramesDB.targetPos.point) .. 
              ", x=" .. tostring(JarUnitFramesDB.targetPos.x) .. 
              ", y=" .. tostring(JarUnitFramesDB.targetPos.y))
        
    else
        print("|cffff8c00Itsu:UI|r commands:")
        print("  /juf - Open config window")
        print("  /juf config - Open config window")
        print("  /juf toggle - Show/hide frames")
        print("  /juf scale <number> - Set frame scale (0.5-2.0)")
        print("  /juf percent - Toggle percentage display")
        print("  /juf buffs - List current buffs with spell IDs")
        print("  /juf showConfig - Display all saved variables")
    end
end

-------------------------------------------------------------------------------
-- Shared settings + config panel
-------------------------------------------------------------------------------
local function ApplyShared()
    local alpha = ns.db.general.bgAlpha
    local unlocked = ns.db.general.unlocked
    ForEachUnitFrame(function(f)
        UpdateFrameTextures(f)
        UpdateFrameFonts(f)
        f.shadow:SetColorTexture(0, 0, 0, alpha)
        f.powerBar.bg:SetAlpha(alpha)
        if f.unlockBorder then
            f.unlockBorder:SetShown(unlocked)
            f.healthBar.bg:SetAlpha(alpha)
        end
    end)
end
ns.OnShared(ApplyShared)

local function RoundTen(v) return math.floor(v / 10 + 0.5) * 10 end

-- the config pages, Unit Frames > All Frames, Player, Target ...
local GROUP = "Unit Frames"

local function FramesOf(key)
    if key == "party" then return partyFrames end
    return { ({ player = playerFrame, target = targetFrame, focus = focusFrame, tot = targetTargetFrame, pet = petFrame })[key] }
end

local function Relayout(key)
    for _, f in ipairs(FramesOf(key)) do ApplyFrameLayout(f) end
end

local SIDES = { { "Above", "above" }, { "Below", "below" }, { "Left", "left" }, { "Right", "right" } }

local function Pct(v) return string.format("%.0f%%", v * 100) end

ns.RegisterPanel(30.1, "All Frames", function(b)
    local DB = JarUnitFramesDB

    b:Header("Text")
    -- +/- 25% around the normal 12
    b:Slider("Font Size  (names, health, level + item level on every frame)", 0.75, 1.25, 0.05,
        function() return (DB.fontSize or 12) / 12 end,
        function(v) DB.fontSize = 12 * v; ForEachUnitFrame(UpdateFrameFonts) end,
        Pct)
    b:Check("Show Level",
        function() return DB.showLevel end,
        function(v) DB.showLevel = v; UpdatePlayerFrame(); UpdateTargetFrame() end)
    b:Check("Show Target Item Level",
        function() return DB.showTargetItemLevel end,
        function(v)
            DB.showTargetItemLevel = v
            if targetFrame and targetFrame.ilvlText then
                if v then
                    RequestTargetItemLevel()
                    UpdateTargetFrame()
                else
                    targetFrame.ilvlText:Hide()
                end
            end
        end)

    b:Header("Frames")
    b:Slider("Frame Scale  (all but party)", 0.5, 2, 0.1,
        function() return DB.frameScale end,
        function(v) DB.frameScale = v; ApplyFrameScale() end,
        function(v) return string.format("%.1f", v) end)
    b:Check("Mirror target position off the player frame",
        function() return DB.mirrorTargetPosition end,
        function(v)
            DB.mirrorTargetPosition = v
            if v then MirrorTargetPosition() end
        end)

    b:Header("Buffs + Debuffs")
    b:Check("Show tooltips when hovering buffs",
        function() return DB.enableAuraTooltips end,
        function(v) DB.enableAuraTooltips = v; ForEachUnitFrame(ApplyAuraTooltipSetting) end)
    b:Note("Sizes, aura positions, icon sizes and filters are on each frame's own page.")
end, GROUP)

-- one page per frame
local PAGES = {
    { key = "player", title = "Player", show = "showPlayerFrame", minW = 150, maxW = 350, maxDebuffs = "playerMaxDebuffs" },
    { key = "target", title = "Target", show = "showTargetFrame", minW = 150, maxW = 350, maxDebuffs = "targetMaxDebuffs" },
    { key = "focus", title = "Focus", show = "showFocusFrame", minW = 150, maxW = 350 },
    { key = "tot", title = "Target of Target", show = "showTargetTargetFrame", minW = 100, maxW = 250 },
    { key = "pet", title = "Pet", show = "showPetFrame", minW = 100, maxW = 250 },
    { key = "party", title = "Party", show = "showPartyFrames", minW = 100, maxW = 250 },
}

local FILTERS = {}
for i, preset in ipairs(DEBUFF_FILTER_PRESETS) do FILTERS[i] = { preset.label, preset.value } end

for i, page in ipairs(PAGES) do
    local key = page.key
    ns.RegisterPanel(30.1 + i / 100, page.title, function(b)
        local DB = JarUnitFramesDB

        local function Slider(text, minV, maxV, step, dbKey, fmt, round)
            b:Slider(text, minV, maxV, step,
                function() return DB[dbKey] end,
                function(v)
                    DB[dbKey] = round and round(v) or v
                    Relayout(key)
                end, fmt)
        end

        -- buffs and debuffs never share a side, the other rows side is left out
        local function AuraSection(label, kind, other)
            local posKey, otherKey = key .. kind .. "Pos", key .. other .. "Pos"
            local base = AURA_SIZE[key]
            b:Header(label)
            b:Check("Show " .. label,
                function() return DB[key .. "Show" .. label] end,
                function(v) DB[key .. "Show" .. label] = v; Relayout(key) end)
            b:Dropdown("Position", function()
                for _, s in ipairs(SIDES) do
                    if s[2] == DB[posKey] then return s[1] end
                end
                return DB[posKey]
            end, function(_, root)
                for _, s in ipairs(SIDES) do
                    if s[2] ~= DB[otherKey] then
                        root:CreateRadio(s[1], function() return DB[posKey] == s[2] end, function()
                            DB[posKey] = s[2]
                            Relayout(key)
                            b:Refresh()
                        end)
                    end
                end
            end)
            Slider("Icon Size", 0.7, 1.3, 0.05, key .. kind .. "Scale",
                function(v) return string.format("%.0f%%  (%.0f px)", v * 100, base * v) end)
        end

        b:Header(page.title)
        b:Check("Show " .. page.title .. " Frame" .. (key == "party" and "s" or ""),
            function() return DB[page.show] end,
            function(v)
                DB[page.show] = v
                if key == "party" then
                    HideBlizzardPartyFrames()
                    -- blocked blizz frames cant be un-blocked without a reload
                    if not v then print("|cff00ff00Itsu:UI|r /reload to get the Blizzard party frames back") end
                end
                SetupFrames()
            end)

        b:Header("Size")
        Slider("Width", page.minW, page.maxW, 10, key .. "Width", nil, RoundTen)
        Slider("Health Height", 10, 60, 1, key .. "Health")
        Slider("Power Height", 5, 35, 1, key .. "Power")
        if key == "party" then
            b:Slider("Space Between Frames", 0, 20, 1,
                function() return DB.partyPadding or 5 end,
                function(v)
                    DB.partyPadding = v
                    RunWhenSafe("partyPos", RepositionPartyFrames)
                end)
        end

        AuraSection("Buffs", "Buff", "Debuff")
        if key == "party" then
            b:Check("Only my buffs",
                function() return DB.partyShowOnlyMyBuffs end,
                function(v)
                    DB.partyShowOnlyMyBuffs = v
                    for n = 1, 4 do
                        SetAuraRowFilter(partyFrames[n] and partyFrames[n].buffRow, v and "HELPFUL|PLAYER" or "HELPFUL")
                    end
                end)
        end

        AuraSection("Debuffs", "Debuff", "Buff")
        b:Cycle("Show", FILTERS,
            function() return DB[key .. "DebuffFilter"] end,
            function(v)
                DB[key .. "DebuffFilter"] = v
                for _, f in ipairs(FramesOf(key)) do SetAuraRowFilter(f.debuffRow, v) end
            end)
        if page.maxDebuffs then
            b:Slider("Max Debuffs", 5, 40, 1,
                function() return DB[page.maxDebuffs] or 40 end,
                function(v)
                    DB[page.maxDebuffs] = v
                    for _, f in ipairs(FramesOf(key)) do SetAuraRowMax(f.debuffRow, v) end
                end)
        end
    end, GROUP)
end

end)
