-- Itsu:UI config window + minimap button
-- modules add a panel with ns.RegisterPanel, the builder below does the layout

local _, ns = ...
local UI = ns.UI

local WINDOW_W, WINDOW_H = 760, 660
local SIDEBAR_W = 150
local CONTENT_W = 540
-- minimap button + title bar icon
local CONFIG_ICON = "Interface\\AddOns\\ItsuUI\\textures\\icon.tga"

local function NewLabel(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(ns.GetFont(), size, "")
    fs:SetTextColor(unpack(color))
    return fs
end

-------------------------------------------------------------------------------
-- Builder, one per panel. y goes down as widgets get added
-------------------------------------------------------------------------------
local Builder = {}
Builder.__index = Builder

function Builder:Place(widget, height)
    widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y)
    self.y = self.y - height
    self.content:SetHeight(math.abs(self.y) + 20)
end

function Builder:Spacer(height)
    self.y = self.y - height
end

function Builder:OnRefresh(fn)
    self.refreshers[#self.refreshers + 1] = fn
end

function Builder:Refresh()
    self.refreshing = true
    for _, fn in ipairs(self.refreshers) do fn() end
    self.refreshing = false
end

function Builder:Custom(height)
    local f = CreateFrame("Frame", nil, self.content)
    f:SetSize(CONTENT_W, height)
    self:Place(f, height)
    return f
end

function Builder:Header(text)
    self:Spacer(10)
    local f = self:Custom(26)
    local label = NewLabel(f, 10, UI.textDim)
    label:SetPoint("LEFT", 0, 0)
    label:SetText(string.upper(text))
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    line:SetColorTexture(UI.border[1], UI.border[2], UI.border[3], 0.5)
    return f
end

-- text can be a string or a function that gets re-read on refresh
function Builder:Text(text, color)
    local f = self:Custom(20)
    local label = NewLabel(f, 11, color or UI.textDim)
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    if type(text) == "function" then
        self:OnRefresh(function() label:SetText(text()) end)
        label:SetText(text())
    else
        label:SetText(text)
    end
    f.label = label
    return f
end

-- wrapped text, as tall as it needs to be
function Builder:Note(text, color)
    local f = CreateFrame("Frame", nil, self.content)
    local label = NewLabel(f, 11, color or UI.textDim)
    label:SetPoint("TOPLEFT", 0, -2)
    label:SetWidth(CONTENT_W)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    local h = math.max(20, math.ceil(label:GetStringHeight()) + 8)
    f:SetSize(CONTENT_W, h)
    self:Place(f, h)
    return f
end

function Builder:Check(text, get, set)
    local f = self:Custom(26)
    local box = CreateFrame("Button", nil, f)
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 0, 0)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetSize(12, 12)
    mark:SetPoint("CENTER")
    mark:SetColorTexture(unpack(UI.accent))
    local label = NewLabel(f, 11, UI.text)
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(text)

    local function Sync()
        local on = get() and true or false
        mark:SetShown(on)
        if on then
            bg:SetColorTexture(UI.accentDim[1], UI.accentDim[2], UI.accentDim[3], 0.3)
        else
            bg:SetColorTexture(unpack(UI.checkOff))
        end
    end
    box:SetScript("OnClick", function()
        set(not get())
        Sync()
    end)
    self:OnRefresh(Sync)
    Sync()
    return f
end

function Builder:Slider(text, minVal, maxVal, step, get, set, fmt)
    local builder = self
    local f = self:Custom(46)
    fmt = fmt or function(v) return tostring(v) end

    local label = NewLabel(f, 11, UI.text)
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(text)
    local value = NewLabel(f, 11, UI.accent)
    value:SetPoint("TOPRIGHT", 0, 0)

    local track = f:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
    track:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    track:SetColorTexture(unpack(UI.sliderBg))

    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetColorTexture(unpack(UI.sliderFill))

    local slider = CreateFrame("Slider", nil, f, "MinimalSliderTemplate")
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 6)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -6)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local thumb = slider:GetThumbTexture() or slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(unpack(UI.accent))
    slider:SetThumbTexture(thumb)
    if slider.NineSlice then slider.NineSlice:Hide() end
    if slider.Background then slider.Background:Hide() end

    local function Show(v)
        value:SetText(fmt(v))
        local pct = (v - minVal) / (maxVal - minVal)
        fill:SetWidth(math.max(1, pct * track:GetWidth()))
    end

    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        Show(v)
        if not builder.refreshing then set(v) end
    end)
    -- track has no width til its shown
    f:SetScript("OnShow", function() Show(get()) end)

    self:OnRefresh(function()
        slider:SetValue(get())
        Show(get())
    end)
    self.refreshing = true
    slider:SetValue(get())
    self.refreshing = false
    return f
end

function Builder:Dropdown(text, getText, setupMenu)
    local f = self:Custom(52)
    local label = NewLabel(f, 11, UI.text)
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(text)
    local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    dd:SetWidth(CONTENT_W)
    dd:SetDefaultText(getText())
    dd:SetupMenu(setupMenu)
    self:OnRefresh(function()
        dd:GenerateMenu()
        dd:SetDefaultText(getText())
    end)
    return f
end

function Builder:NewButton(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop(ns.BACKDROP)
    btn:SetBackdropColor(unpack(UI.btnNormal))
    btn:SetBackdropBorderColor(unpack(UI.border))
    btn.label = NewLabel(btn, 11, UI.accent)
    btn.label:SetPoint("CENTER")
    btn.label:SetText(text)
    btn:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(UI.btnHover)) end)
    btn:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(UI.btnNormal)) end)
    btn:SetScript("OnMouseDown", function(s) s:SetBackdropColor(unpack(UI.btnPress)) end)
    btn:SetScript("OnMouseUp", function(s) s:SetBackdropColor(unpack(UI.btnHover)) end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- row of buttons, list = { {text, fn}, {text, fn} }
function Builder:Buttons(list)
    local f = self:Custom(36)
    local x = 0
    for _, item in ipairs(list) do
        local width = item[3] or 140
        local btn = self:NewButton(f, item[1], width, 28, item[2])
        btn:SetPoint("LEFT", x, 0)
        x = x + width + 8
        if item.key then f[item.key] = btn end
    end
    return f
end

-- radio style row, options = { {label, value}, ... }
function Builder:Toggle(text, options, get, set)
    local f = self:Custom(34)
    local label = NewLabel(f, 11, UI.text)
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)

    local btns = {}
    local function Sync()
        for _, b in ipairs(btns) do
            if b.value == get() then
                b:SetBackdropColor(UI.accentDim[1], UI.accentDim[2], UI.accentDim[3], 0.4)
                b.label:SetTextColor(unpack(UI.accent))
            else
                b:SetBackdropColor(unpack(UI.btnNormal))
                b.label:SetTextColor(unpack(UI.textDim))
            end
        end
    end
    local x = 180
    for _, opt in ipairs(options) do
        local b = self:NewButton(f, opt[1], 100, 26, function()
            set(opt[2])
            Sync()
        end)
        b.value = opt[2]
        b:SetPoint("LEFT", x, 0)
        -- no hover color on these, it fights the selected state
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
        b:SetScript("OnMouseDown", nil)
        b:SetScript("OnMouseUp", nil)
        btns[#btns + 1] = b
        x = x + 106
    end
    self:OnRefresh(Sync)
    Sync()
    return f
end

-- click to go to the next value, options = { {label, value}, ... }
function Builder:Cycle(text, options, get, set)
    local f = self:Custom(32)
    local label = NewLabel(f, 11, UI.text)
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)

    local btn
    local function Sync()
        local cur = get()
        local shown = cur
        for _, opt in ipairs(options) do
            if opt[2] == cur then shown = opt[1] end
        end
        btn.label:SetText(shown)
    end
    btn = self:NewButton(f, "", 200, 26, function()
        local cur, nextIndex = get(), 1
        for i, opt in ipairs(options) do
            if opt[2] == cur then nextIndex = i % #options + 1 end
        end
        set(options[nextIndex][2])
        Sync()
    end)
    btn:SetPoint("LEFT", 180, 0)
    self:OnRefresh(Sync)
    Sync()
    return f
end

function Builder:NewEditBox(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    box:SetFontObject(ChatFontNormal)
    box:SetAutoFocus(false)
    box:SetMaxLetters(50)
    box:SetTextInsets(8, 8, 0, 0)
    box:SetBackdrop(ns.BACKDROP)
    box:SetBackdropColor(unpack(UI.sliderBg))
    box:SetBackdropBorderColor(unpack(UI.border))
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    return box
end

-- label + text box, get is re-read on refresh
function Builder:Input(text, get)
    local f = self:Custom(34)
    local label = NewLabel(f, 11, UI.text)
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)
    local box = self:NewEditBox(f, 340, 26)
    box:SetPoint("LEFT", 180, 0)
    box:SetText(get() or "")
    self:OnRefresh(function() box:SetText(get() or "") end)
    f.box = box
    return f
end

-------------------------------------------------------------------------------
-- Shared menu helper, long media lists need to scroll
-------------------------------------------------------------------------------
function ns.BuildMediaMenu(root, mediaType, get, set)
    root:SetScrollMode(400)
    for _, name in ipairs(ns.LSM:List(mediaType)) do
        root:CreateRadio(name,
            function() return get() == name end,
            function() set(name) end)
    end
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local window, activeTab
local tabs = {}

-- sidebar rows, a group only lists its pages while one of them is open
local sideRows, openGroup = {}, nil
local function LayoutSidebar()
    local row = 0
    for _, r in ipairs(sideRows) do
        local show = r.head or not r.group or r.group == openGroup
        r.frame:SetShown(show)
        if show then
            r.frame:SetPoint("TOPLEFT", 0, -6 - row * 30)
            row = row + 1
        end
        if r.head then r.frame.label:SetText((r.group == openGroup and "- " or "+ ") .. r.group) end
    end
end

local function ShowTab(tab)
    if activeTab then
        activeTab.panel:Hide()
        activeTab.button.bg:SetColorTexture(0, 0, 0, 0)
        activeTab.button.label:SetTextColor(unpack(UI.text))
    end
    activeTab = tab
    if openGroup ~= tab.info.group then
        openGroup = tab.info.group
        LayoutSidebar()
    end
    tab.button.bg:SetColorTexture(UI.accentDim[1], UI.accentDim[2], UI.accentDim[3], 0.4)
    tab.button.label:SetTextColor(unpack(UI.accent))

    -- build on first look so opening the window stays quick
    if not tab.builder then
        local content = CreateFrame("Frame", nil, tab.scroll)
        content:SetSize(CONTENT_W, 1)
        tab.scroll:SetScrollChild(content)
        tab.builder = setmetatable({ content = content, y = 0, refreshers = {} }, Builder)
        tab.info.build(tab.builder)
    else
        tab.builder:Refresh()
    end
    tab.panel:Show()
end

local function CreateWindow()
    if window then return window end

    table.sort(ns.panelList, function(a, b) return a.order < b.order end)

    local f = CreateFrame("Frame", "JarForeverConfig", UIParent, "BackdropTemplate")
    window = f
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER")
    f:SetBackdrop(ns.BACKDROP)
    f:SetBackdropColor(unpack(UI.bg))
    f:SetBackdropBorderColor(unpack(UI.border))
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetScale(ns.db.general.configScale)
    f:Hide()
    tinsert(UISpecialFrames, "JarForeverConfig")

    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetBackdrop(ns.BACKDROP)
    titleBar:SetBackdropColor(unpack(UI.header))
    titleBar:SetBackdropBorderColor(unpack(UI.border))

    local titleIcon = titleBar:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(24, 24)
    titleIcon:SetPoint("LEFT", 8, 0)
    titleIcon:SetTexture(CONFIG_ICON)

    local title = NewLabel(titleBar, 13, UI.accent)
    title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
    title:SetText("Itsu:UI")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(32, 32)
    closeBtn:SetPoint("RIGHT", 0, 0)
    local closeTxt = NewLabel(closeBtn, 14, UI.textDim)
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText("x")
    closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1, 0.35, 0.35) end)
    closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(unpack(UI.textDim)) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_W)
    local sideBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sideBg:SetAllPoints()
    sideBg:SetColorTexture(unpack(UI.header))

    -- panels in a group get a heading row and sit indented under it.
    -- clicking the heading opens the groups first page
    local lastGroup
    for i, info in ipairs(ns.panelList) do
        if info.group and info.group ~= lastGroup then
            local group = info.group
            local head = CreateFrame("Button", nil, sidebar)
            head:SetSize(SIDEBAR_W, 30)
            head.label = NewLabel(head, 11, UI.textDim)
            head.label:SetPoint("LEFT", 14, 0)
            head:SetScript("OnEnter", function() head.label:SetTextColor(unpack(UI.text)) end)
            head:SetScript("OnLeave", function() head.label:SetTextColor(unpack(UI.textDim)) end)
            head:SetScript("OnClick", function()
                for _, t in ipairs(tabs) do
                    if t.info.group == group then
                        ShowTab(t)
                        return
                    end
                end
            end)
            sideRows[#sideRows + 1] = { frame = head, head = true, group = group }
        end
        lastGroup = info.group
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, 30)
        sideRows[#sideRows + 1] = { frame = btn, group = info.group }
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0, 0, 0, 0)
        btn.label = NewLabel(btn, 11, UI.text)
        btn.label:SetPoint("LEFT", info.group and 26 or 14, 0)
        btn.label:SetText(info.group and ("> " .. info.name) or info.name)

        local panel = CreateFrame("Frame", nil, f)
        panel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 14, -8)
        panel:SetPoint("BOTTOMRIGHT", -8, 8)
        panel:Hide()
        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", -28, 0)

        local tab = { info = info, button = btn, panel = panel, scroll = scroll }
        tabs[info.name] = tab
        tabs[i] = tab
        btn:SetScript("OnClick", function() ShowTab(tab) end)
    end
    LayoutSidebar()

    f:SetScript("OnShow", function()
        if activeTab then activeTab.builder:Refresh() end
    end)
    return f
end

function ns.OpenConfig(tabName)
    local f = CreateWindow()
    f:Show()
    f:Raise()
    local tab = tabName and tabs[tabName] or activeTab or tabs[1]
    if tab then ShowTab(tab) end
end

function ns.ToggleConfig()
    if window and window:IsShown() then
        window:Hide()
    else
        ns.OpenConfig()
    end
end

function ns.RefreshPanel(name)
    local tab = tabs[name]
    if tab and tab.builder and window:IsShown() and activeTab == tab then
        tab.builder:Refresh()
    end
end

-------------------------------------------------------------------------------
-- General panel
-------------------------------------------------------------------------------
StaticPopupDialogs["JARFOREVER_RESET"] = {
    text = "Reset every Itsu:UI setting and reload?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        JarForeverDB = nil
        JarForeverCharDB = nil
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

ns.RegisterPanel(10, "General", function(b)
    local g = ns.db.general

    b:Header("Look")
    b:Dropdown("Bar Texture  (unit frames, cast bars, combo points)",
        function() return g.texture end,
        function(_, root)
            ns.BuildMediaMenu(root, "statusbar",
                function() return g.texture end,
                function(name) g.texture = name; ns.ApplyShared() end)
        end)
    b:Dropdown("Font  (the whole game + everything in Itsu:UI)",
        function() return g.globalFont end,
        function(_, root)
            local function IsFont(name) return g.globalFont == name end
            local function SetFont(name)
                g.globalFont = name
                ns.ApplyShared()
            end
            root:CreateRadio(ns.FONT_DEFAULT,
                function() return IsFont(ns.FONT_DEFAULT) end,
                function() SetFont(ns.FONT_DEFAULT) end)
            ns.BuildMediaMenu(root, "font", function() return g.globalFont end, SetFont)
        end)
    b:Text("Damage numbers + names over heads change after a relog. Bags + bar numbers need a /reload.")
    b:Slider("Background Opacity  (unit frames, combo points)", 0, 1, 0.05,
        function() return g.bgAlpha end,
        function(v) g.bgAlpha = v; ns.ApplyShared() end,
        function(v) return string.format("%.0f%%", v * 100) end)
    b:Check("Unlock Frames  (drag unit frames, focus bars and combo points, shift+drag party)",
        function() return g.unlocked end,
        function(v) g.unlocked = v; ns.ApplyShared() end)

    b:Header("Action Bars")
    b:Toggle("Bars are for", { { "Keyboard", "bars" }, { "Controller", "controller" } },
        ns.BarMode, ns.AskBarMode)
    b:Text("Switching reloads. Keyboard is the G13 bars, controller is the gamepad layout. Each one keeps its own action slot layout per character, put back when you switch.")

    b:Header("Modules  (changes need a /reload)")
    for _, m in ipairs(ns.moduleList) do
        -- the two action bar modes are the switch above
        if m.key ~= "bars" and m.key ~= "controller" then
            -- say why a module has no tab instead of just leaving it out
            local label = m.label
            if ns.IsModuleBlocked(m.key) then
                label = label .. "  (not running, " .. ns.OLD_ADDONS[m.key] .. " is still on)"
            end
            b:Check(label,
                function() return ns.db.modules[m.key] ~= false end,
                function(v) ns.db.modules[m.key] = v end)
        end
    end

    local old = ns.GetOldAddonsOn()
    if #old > 0 then
        b:Header("Old Addons")
        b:Text("Still turned on: " .. table.concat(old, ", "), UI.accent)
        b:Text("A module wont run while its old addon is on.")
        b:Buttons({ { "Turn Off + Reload", ns.DisableOldAddons, 180 } })
    end

    b:Header("Window")
    b:Slider("Config Window Scale", 0.5, 1.5, 0.05,
        function() return g.configScale end,
        function(v) g.configScale = v; window:SetScale(v) end,
        function(v) return string.format("%.2f", v) end)
    b:Buttons({
        { "Reload UI", function() ReloadUI() end },
        { "Reset Everything", function() StaticPopup_Show("JARFOREVER_RESET") end, 160 },
    })
end)

-------------------------------------------------------------------------------
-- Tools panel, grid + memory list
-------------------------------------------------------------------------------
local function FormatMemory(kb)
    if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
    return string.format("%.0f KB", kb)
end

ns.RegisterPanel(90, "Tools", function(b)
    if ns.grid then
        b:Header("Screen Grid")
        b:Check("Show Grid  (/grid)",
            function() return ns.grid.IsShown() end,
            function() ns.grid.Toggle() end)
        b:Slider("Grid Spacing", 10, 200, 10,
            function() return ns.db.grid.spacing or 50 end,
            function(v) ns.grid.SetSpacing(v) end,
            function(v) return v .. "px" end)
    end

    b:Header("Addon Memory")
    local sortBy = "memory"
    local listParent
    local rows = {}
    local ROW_H = 18

    local function RefreshMemory(rescan)
        if rescan then UpdateAddOnMemoryUsage() end
        local data = {}
        for i = 1, C_AddOns.GetNumAddOns() do
            if C_AddOns.IsAddOnLoaded(i) then
                data[#data + 1] = { name = C_AddOns.GetAddOnInfo(i), memory = GetAddOnMemoryUsage(i) }
            end
        end
        if sortBy == "memory" then
            table.sort(data, function(x, y) return x.memory > y.memory end)
        else
            table.sort(data, function(x, y) return x.name < y.name end)
        end

        local top = data[1] and math.max(data[1].memory, 1) or 1
        if sortBy == "name" then
            for _, d in ipairs(data) do top = math.max(top, d.memory) end
        end
        local total = 0
        for i, d in ipairs(data) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, listParent)
                row:SetHeight(ROW_H)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                row:SetPoint("RIGHT", 0, 0)
                row.name = NewLabel(row, 10, UI.text)
                row.name:SetPoint("LEFT", 4, 0)
                row.mem = NewLabel(row, 10, UI.accent)
                row.mem:SetPoint("RIGHT", -4, 0)
                row.bar = row:CreateTexture(nil, "ARTWORK")
                row.bar:SetHeight(3)
                row.bar:SetPoint("BOTTOMLEFT", 4, 1)
                row.bar:SetColorTexture(unpack(UI.sliderFill))
                rows[i] = row
            end
            row.name:SetText(d.name)
            row.mem:SetText(FormatMemory(d.memory))
            row.bar:SetWidth(math.max(1, d.memory / top * 400))
            row:Show()
            total = total + d.memory
        end
        for i = #data + 1, #rows do rows[i]:Hide() end
        listParent:SetHeight(#data * ROW_H)
        listParent.total:SetText("Total: " .. FormatMemory(total))
        b.content:SetHeight(math.abs(b.y) + #data * ROW_H + 20)
    end

    local bar = b:Buttons({
        { "Refresh", function() RefreshMemory(true) end, 100 },
        { "Sort: Memory", function(self)
            sortBy = sortBy == "memory" and "name" or "memory"
            self.label:SetText(sortBy == "memory" and "Sort: Memory" or "Sort: Name")
            RefreshMemory()
        end, 120 },
    })
    local total = NewLabel(bar, 11, UI.text)
    total:SetPoint("RIGHT", 0, 0)

    listParent = b:Custom(1)
    listParent.total = total
    b:OnRefresh(function() RefreshMemory(true) end)
    RefreshMemory(true)
end)

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------
local function PositionIcon(icon, angle)
    local radius = Minimap:GetWidth() / 2 + 5
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.CreateMinimapButton()
    local icon = CreateFrame("Button", "JarForeverMinimapButton", Minimap)
    ns.minimapButton = icon
    icon:SetSize(32, 32)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(8)
    icon:RegisterForDrag("LeftButton")
    icon:RegisterForClicks("LeftButtonUp")
    PositionIcon(icon, ns.db.general.minimapAngle)

    icon.bg = icon:CreateTexture(nil, "BACKGROUND")
    icon.bg:SetSize(20, 20)
    icon.bg:SetPoint("CENTER")
    icon.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetSize(22, 22)
    icon.texture:SetPoint("CENTER")
    icon.texture:SetTexture(CONFIG_ICON)
    -- round it off so the corners dont poke past the ring
    icon.texture:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetSize(52, 52)
    -- ring art sits in the top left of its texture, not the middle. same anchor blizz uses, scaled to 52
    icon.border:SetPoint("TOPLEFT", icon, "CENTER", -15.5, 14.5)
    icon.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Itsu:UI")
        GameTooltip:AddLine("Click for options", 0.5, 0.5, 1)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnClick", ns.ToggleConfig)

    icon:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(s)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.atan2(py / scale - my, px / scale - mx)
            PositionIcon(s, angle)
            ns.db.general.minimapAngle = angle
        end)
    end)
    icon:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end
