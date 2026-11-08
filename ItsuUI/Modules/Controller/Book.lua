-- Itsu:UI controller mode, started from JarStick. edit it here
-- JarStick book: spellbook and talents on the pad, out of combat only
-- Spells: X picks a spell up, then press the pad button you want it on (L2/R2/Select for pages,
-- L1/R1 for the spare grids). Talents: loadouts, two-way choices, and the trees as a grid.
-- Keys come in through the Interact.lua handler (JarStickUIKey), the cursor and legend are shared.

local _, jf = ...
jf.jsParts = jf.jsParts or {}
jf.jsParts[#jf.jsParts + 1] = function(ns, ADDON)

local PALETTE = {
    bg = { 0.10, 0.10, 0.12, 0.95 },
    header = { 0.15, 0.15, 0.18, 1 },
    tab = { 0.14, 0.14, 0.17, 1 },
    accent = { 1.0, 0.55, 0.0, 1 },
    text = { 0.95, 0.95, 0.95, 1 },
    textDim = { 0.70, 0.70, 0.70, 1 },
    border = { 0.20, 0.20, 0.22, 1 },
}
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
local EDGE2 = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 }

local W, H = 560, 480
local BODY_W, BODY_H = 530, 328
local COLS, ROWS = 6, 4
local CELL_W, CELL_H = 86, 80
local TREE_H = BODY_H - 26 -- under the "Class tree / Points left" line
local NODE_MAX = 42
local GOLD, GREEN, GREY = { 1, 0.82, 0 }, { 0.25, 0.83, 0.29 }, { 0.33, 0.33, 0.36 }

local BANK = Enum.SpellBookSpellBank.Player
local T_SPELL, T_FLYOUT = Enum.SpellBookItemType.Spell, Enum.SpellBookItemType.Flyout
local N_SELECTION, N_SUBTREE = Enum.TraitNodeType.Selection, Enum.TraitNodeType.SubTreeSelection
local DPAD = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }
local CLEAR = {} -- the "clear slot" tile

local book, main, banner, body, foot
local tabFrames = {}
local state = { sec = "spells", tab = { spells = 2, talents = 2 }, cur = {}, top = {}, unplaced = false }
local place -- { clearing, grid = { side, idx } } while placing
local lastGrid

local function Glyph(key)
    return ns.Glyph and ns.Glyph(key) or key
end

local function Err(msg)
    UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
end

-- small builders ------------------------------------------------------------

local function Text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

-- spells ----------------------------------------------------------------------

local spellTabs = {}

local function LoadSpells()
    wipe(spellTabs)
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if line and not line.shouldHide and not line.offSpecID and not line.isGuild then
            local t = { name = line.name, items = {} }
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
                if info and not info.isPassive and not info.isOffSpec and (info.itemType == T_SPELL or info.itemType == T_FLYOUT) then
                    t.items[#t.items + 1] = { slot = slot, info = info }
                end
            end
            if #t.items > 0 then spellTabs[#spellTabs + 1] = t end
        end
    end
end

-- slot -> what to press for it: dpad bar, trigger, face button. or the bar name
local ROW_KEYS = { false, "PADLTRIGGER", "PADRTRIGGER" }
local function SlotKeys(slot)
    local page, idx = math.floor((slot - 1) / 12) + 1, (slot - 1) % 12 + 1
    local row, face = math.floor((idx - 1) / 4) + 1, (idx - 1) % 4 + 1
    local combo = (ROW_KEYS[row] and Glyph(ROW_KEYS[row]) or "") .. Glyph(ns.BUTTON_KEYS[face])
    local dir = ns.BarKeyForPage(page)
    if dir then return Glyph(dir) .. combo end
    if page == ns.db.pages.sel then return Glyph("PADBACK") .. combo end
    return ns.PageName(page) .. " #" .. idx
end

local function WhereIs(item)
    if item.info.itemType ~= T_SPELL then return end
    local slots = C_ActionBar.FindSpellActionButtons(item.info.actionID)
    if not slots or not slots[1] then return end
    -- prefer a pad reachable one
    for _, s in ipairs(slots) do
        local k = SlotKeys(s)
        if not k:find("#") then return k end
    end
    return SlotKeys(slots[1])
end

local function SpellList()
    local t = spellTabs[state.tab.spells]
    local list = { CLEAR }
    for _, item in ipairs(t and t.items or {}) do
        item.where = WhereIs(item)
        if not (state.unplaced and item.where) then list[#list + 1] = item end
    end
    return list
end

-- cursor contents for the banner
local function CursorLabel()
    local kind, a, _, c = GetCursorInfo()
    if kind == "spell" then
        local id = c or a
        return C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
    elseif kind == "item" then
        return C_Item.GetItemNameByID(a), C_Item.GetItemIconByID(a)
    elseif kind == "macro" then
        local name, icon = GetMacroInfo(a)
        return name, icon
    elseif kind then
        return kind:gsub("^%l", string.upper), 134400
    end
end

-- talents ---------------------------------------------------------------------

local tal = { trees = {}, choices = {}, tabs = { "Loadouts", "Choices" }, snap = {} }

local function SpecID()
    local idx = GetSpecialization()
    return idx and (GetSpecializationInfo(idx))
end

local function EntryLook(configID, entryID)
    local e = entryID and C_Traits.GetEntryInfo(configID, entryID)
    if not e then return "?", { tex = 134400 } end
    if e.subTreeID then
        local st = C_Traits.GetSubTreeInfo(configID, e.subTreeID)
        return st and st.name or "?", { atlas = st and st.iconElementID }
    end
    local def = e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
    local spellID = def and def.spellID
    local name = def and def.overrideName or (spellID and C_Spell.GetSpellName(spellID)) or "?"
    local icon = def and def.overrideIcon or (spellID and C_Spell.GetSpellTexture(spellID)) or 134400
    return name, { tex = icon }, spellID
end

local function NodeKey(info)
    return info.ranksPurchased .. ":" .. (info.activeEntry and info.activeEntry.entryID or 0)
end

local function Snapshot()
    local cfg = tal.configID
    if not cfg or C_Traits.ConfigHasStagedChanges(cfg) then return end
    wipe(tal.snap)
    for _, tree in pairs(tal.trees) do
        for _, n in ipairs(tree.nodes) do tal.snap[n.id] = NodeKey(n.info) end
    end
end

local function Staged(n)
    return tal.snap[n.id] and tal.snap[n.id] ~= NodeKey(n.info)
end

-- smallest step between positions, and the range
local function MinGap(set)
    local v = {}
    for k in pairs(set) do v[#v + 1] = k end
    table.sort(v)
    local g = math.huge
    for i = 2, #v do g = math.min(g, v[i] - v[i - 1]) end
    return g, v[1], v[#v]
end

-- one blizzard tree holds class, spec and hero nodes. currency [1] = class, [2] = spec
local function LoadTalents()
    local cfg = C_ClassTalents.GetActiveConfigID()
    tal.configID = cfg
    wipe(tal.trees)
    wipe(tal.choices)
    tal.tabs = { "Loadouts", "Choices" }
    if not cfg then return end
    local treeID = C_Traits.GetConfigInfo(cfg).treeIDs[1]
    tal.treeID = treeID
    local cur = C_Traits.GetTreeCurrencyInfo(cfg, treeID, false) or {}
    local classCur, specCur = cur[1] and cur[1].traitCurrencyID, cur[2] and cur[2].traitCurrencyID
    local heroSub = C_ClassTalents.GetActiveHeroTalentSpec()
    local specName = select(2, GetSpecializationInfo(GetSpecialization() or 1)) or "Spec"
    local heroInfo = heroSub and C_Traits.GetSubTreeInfo(cfg, heroSub)

    local trees = {
        Class = { label = "Class", cur = classCur, nodes = {} },
        Spec = { label = specName, cur = specCur, nodes = {} },
        Hero = { label = heroInfo and heroInfo.name or "Hero", cur = heroInfo and heroInfo.traitCurrencyID, nodes = {} },
    }
    local heroChoice
    for _, id in ipairs(C_Traits.GetTreeNodes(treeID)) do
        local info = C_Traits.GetNodeInfo(cfg, id)
        if info and info.ID ~= 0 and info.isVisible then
            local where
            if info.type == N_SUBTREE then
                heroChoice = { id = id, info = info, tree = "Hero" }
                heroChoice.name, heroChoice.icon = EntryLook(cfg, info.activeEntry and info.activeEntry.entryID or info.entryIDs[1])
            elseif info.subTreeID then
                if info.subTreeID == heroSub then where = "Hero" end
            else
                local cost = C_Traits.GetNodeCost(cfg, id)
                where = (cost and cost[1] and cost[1].ID == specCur) and "Spec" or "Class"
            end
            if where then
                local n = { id = id, info = info, tree = where }
                local entry = info.activeEntry and info.activeEntry.entryID or info.entryIDs[1]
                n.name, n.icon, n.spellID = EntryLook(cfg, entry)
                if info.type == N_SELECTION and info.entryIDs[2] then
                    local other = info.entryIDs[1] == entry and info.entryIDs[2] or info.entryIDs[1]
                    n.name2, n.icon2 = EntryLook(cfg, other)
                end
                table.insert(trees[where].nodes, n)
                if info.type == N_SELECTION and info.ranksPurchased > 0 and info.entryIDs[2] then
                    table.insert(tal.choices, n)
                end
            end
        end
    end
    if heroChoice and heroChoice.info.entryIDs[2] then table.insert(tal.choices, 1, heroChoice) end

    for key, t in pairs(trees) do
        if #t.nodes > 0 then
            -- same shape as blizzards tree. width fits the window, height scrolls with the cursor
            local xs, ys = {}, {}
            for _, n in ipairs(t.nodes) do
                xs[n.info.posX], ys[n.info.posY] = true, true
            end
            local gx, minX, maxX = MinGap(xs)
            local gy, minY, maxY = MinGap(ys)
            -- t.size = math.floor(math.min(34, BODY_W / cols * 0.7, (BODY_H - 30) / rows * 0.72))
            local s = NODE_MAX
            if maxX > minX then s = math.min(s, math.floor(gx * BODY_W / (maxX - minX) / 1.2)) end
            s = math.max(s, 20)
            local px = maxX > minX and (BODY_W - s) / (maxX - minX) or 0
            local py = maxY > minY and math.max(s * 1.45 / gy, (TREE_H - s) / (maxY - minY)) or 0
            for _, n in ipairs(t.nodes) do
                n.x = maxX > minX and (n.info.posX - minX) * px or (BODY_W - s) / 2
                n.y = (n.info.posY - minY) * py
            end
            t.size, t.height = s, (maxY - minY) * py + s
            tal.trees[key] = t
        end
    end
    for _, key in ipairs({ "Class", "Spec", "Hero" }) do
        if tal.trees[key] then tal.tabs[#tal.tabs + 1] = key end
    end
    if not next(tal.snap) then Snapshot() end
end

local function PointsLeft(tree)
    if not tree.cur then return "?" end
    for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(tal.configID, tal.treeID, false) or {}) do
        if c.traitCurrencyID == tree.cur then return c.quantity end
    end
    return "?"
end

local function PendingCount()
    local c = 0
    for _, t in pairs(tal.trees) do
        for _, n in ipairs(t.nodes) do
            if Staged(n) then c = c + 1 end
        end
    end
    return c
end

local function Loadouts()
    local spec = SpecID()
    local list = {}
    for _, id in ipairs(spec and C_ClassTalents.GetConfigIDsBySpecID(spec) or {}) do
        local info = C_Traits.GetConfigInfo(id)
        list[#list + 1] = { id = id, name = info and info.name or ("Loadout " .. id) }
    end
    return list, spec and C_ClassTalents.GetLastSelectedSavedConfigID(spec)
end

-- window ----------------------------------------------------------------------

local cells, rows, choiceRows, nodeBtns, lines = {}, {}, {}, {}, {}
local header, emptyText, treeClip, treeContent

local function CurTab()
    if state.sec == "spells" then
        local t = spellTabs[state.tab.spells]
        return t and t.name or "", "spells:" .. state.tab.spells
    end
    local name = tal.tabs[state.tab.talents] or "Loadouts"
    return name, "talents:" .. name
end

local function Cur()
    local _, key = CurTab()
    return state.cur[key] or 1, key
end

local function SetCur(v)
    local _, key = CurTab()
    state.cur[key] = v
end

local function ShowFoot(icon, name, sub, right)
    if type(icon) == "table" then
        if icon.atlas then foot.icon:SetAtlas(icon.atlas) else foot.icon:SetTexture(icon.tex) end
    else
        foot.icon:SetTexture(icon)
    end
    foot.icon:SetShown(icon ~= nil)
    foot.name:SetText(name or "")
    foot.sub:SetText(sub or "")
    foot.right:SetText(right or "")
end

local function HideBody()
    for _, c in ipairs(cells) do c:Hide() end
    for _, r in ipairs(rows) do r:Hide() end
    for _, r in ipairs(choiceRows) do r:Hide() end
    for _, b in ipairs(nodeBtns) do b:Hide() end
    for _, l in ipairs(lines) do l:Hide() end
    header:Hide()
    emptyText:Hide()
    treeClip:Hide()
end

local function Cell(i)
    if cells[i] then return cells[i] end
    local c = CreateFrame("Button", nil, body)
    c:SetSize(CELL_W, CELL_H)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    c:SetPoint("TOPLEFT", (BODY_W - COLS * CELL_W) / 2 + col * CELL_W, -row * (CELL_H + 2))
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(44, 44)
    c.box:SetPoint("TOP", 0, -2)
    c.icon = c.box:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.x = Text(c.box, "GameFontNormalHuge", 0.8, 0.2, 0.2)
    c.x:SetPoint("CENTER")
    c.x:SetText("X")
    c.bind = Text(c.box, "GameFontHighlightSmall")
    c.bind:SetPoint("BOTTOM", c.box, "BOTTOM", 0, 1)
    c.name = Text(c, "GameFontHighlightSmall")
    c.name:SetPoint("TOP", c.box, "BOTTOM", 0, -3)
    c.name:SetWidth(CELL_W - 4)
    c.name:SetMaxLines(2)
    c:SetScript("OnClick", function(self)
        SetCur(self.index)
        ns.BookKey("PAD3")
    end)
    cells[i] = c
    return c
end

local function Row(pool, i, height, gap)
    if pool[i] then return pool[i] end
    local r = CreateFrame("Button", nil, body, "BackdropTemplate")
    r:SetSize(BODY_W, height)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * (height + gap))
    r:SetBackdrop(BACKDROP)
    r:SetBackdropColor(1, 1, 1, 0.03)
    r:SetBackdropBorderColor(unpack(PALETTE.border))
    pool[i] = r
    return r
end

local function ScrollTo(cur, perRow, visRows, key)
    local top = state.top[key] or 0
    local row = math.floor((cur - 1) / perRow)
    if row < top then top = row elseif row >= top + visRows then top = row - visRows + 1 end
    state.top[key] = top
    return top
end

local function PaintSpells()
    local list = SpellList()
    local cur, key = Cur()
    cur = math.max(1, math.min(cur, #list))
    SetCur(cur)
    local top = ScrollTo(cur, COLS, ROWS, key)
    local hlFrame
    for i = 1, COLS * ROWS do
        local c, idx = Cell(i), top * COLS + i
        local item = list[idx]
        c.index = idx
        if item then
            if item == CLEAR then
                c.icon:SetColorTexture(0.07, 0.07, 0.09, 1)
                c.x:Show()
                c.bind:SetText("")
                c.name:SetText("Clear slot")
                c.icon:SetDesaturated(false)
                c.icon:SetAlpha(1)
            else
                c.icon:SetTexture(item.info.iconID)
                c.x:Hide()
                c.bind:SetText(item.where or "")
                c.name:SetText(item.info.name)
                c.icon:SetDesaturated(item.where ~= nil)
                c.icon:SetAlpha(item.where and 0.55 or 1)
            end
            c:Show()
            if idx == cur then hlFrame = c.box end
        else
            c:Hide()
        end
    end
    if #list == 1 then
        emptyText:SetText("Everything on this tab is on a button")
        emptyText:Show()
    end
    ns.Highlight(hlFrame)
    local item = list[cur]
    if item == CLEAR then
        ShowFoot(nil, "Clear slot", "Pick this, then press the button to empty", "")
    elseif item then
        local spellID = item.info.spellID or item.info.actionID
        local desc = item.info.itemType == T_SPELL and C_Spell.GetSpellDescription(spellID) or ""
        ShowFoot(item.info.iconID, item.info.name, desc ~= "" and desc or (item.info.subName or ""),
            item.where and ("On " .. item.where) or "|cff3ed34aNot on a button|r")
    end
end

local function PaintLoadouts()
    local list, active = Loadouts()
    local cur = math.max(1, math.min(Cur(), #list))
    SetCur(cur)
    local hlFrame
    for i, l in ipairs(list) do
        if i > 6 then break end
        local r = Row(rows, i, 44, 6)
        if not r.name then
            r.name = Text(r, "GameFontHighlightLarge")
            r.name:SetPoint("LEFT", 14, 0)
            r.pill = Text(r, "GameFontNormal", unpack(PALETTE.accent))
            r.pill:SetPoint("RIGHT", -14, 0)
        end
        r.name:SetText(l.name)
        r.pill:SetText(l.id == active and "ACTIVE" or "")
        r:Show()
        if i == cur then hlFrame = r end
    end
    if #list == 0 then
        emptyText:SetText("No saved loadouts for this spec")
        emptyText:Show()
    end
    ns.Highlight(hlFrame)
    local l = list[cur]
    ShowFoot(nil, l and l.name or "", l and (l.id == active and "Active loadout" or "X loads it, with the usual cast") or "", "")
end

local function SetLook(tex, look)
    if look.atlas then tex:SetAtlas(look.atlas) else tex:SetTexture(look.tex) end
end

local function PaintChoices()
    local list = tal.choices
    local cur, key = Cur()
    cur = math.max(1, math.min(cur, #list))
    SetCur(cur)
    local top = ScrollTo(cur, 1, 5, key)
    local hlFrame
    for i = 1, 5 do
        local n = list[top + i]
        local r = Row(choiceRows, i, 58, 6)
        if not r.label then
            r.label = Text(r, "GameFontNormalSmall", unpack(PALETTE.textDim))
            r.label:SetPoint("LEFT", 10, 0)
            r.label:SetWidth(60)
            r.label:SetJustifyH("LEFT")
            r.opt = {}
            for k = 1, 2 do
                local o = CreateFrame("Frame", nil, r, "BackdropTemplate")
                o:SetSize(200, 46)
                o:SetPoint("LEFT", k == 1 and 70 or 320, 0)
                o:SetBackdrop(EDGE2)
                o.icon = o:CreateTexture(nil, "ARTWORK")
                o.icon:SetSize(34, 34)
                o.icon:SetPoint("LEFT", 6, 0)
                o.name = Text(o, "GameFontHighlight")
                o.name:SetPoint("LEFT", o.icon, "RIGHT", 8, 0)
                o.name:SetWidth(150)
                o.name:SetJustifyH("LEFT")
                r.opt[k] = o
            end
            r.arrows = Text(r, "GameFontHighlight")
            r.arrows:SetPoint("CENTER", r, "LEFT", 295, 0)
        end
        if n then
            r.label:SetText(n.tree == "Hero" and "HERO" or (tal.trees[n.tree] and tal.trees[n.tree].label or n.tree):upper())
            r.arrows:SetText(Glyph("PADDLEFT") .. Glyph("PADDRIGHT"))
            local active = n.info.activeEntry and n.info.activeEntry.entryID
            for k = 1, 2 do
                local eid = n.info.entryIDs[k]
                local name, look = EntryLook(tal.configID, eid)
                local o = r.opt[k]
                SetLook(o.icon, look)
                o.name:SetText(name)
                local on = eid == active
                local staged = on and Staged(n)
                o:SetAlpha(on and 1 or 0.4)
                o:SetBackdropBorderColor(staged and PALETTE.accent[1] or GOLD[1], staged and PALETTE.accent[2] or GOLD[2], staged and 0 or GOLD[3], on and 1 or 0)
            end
            r:Show()
            if top + i == cur then hlFrame = r end
        else
            r:Hide()
        end
    end
    if #list == 0 then
        emptyText:SetText("No two-way talents learned yet")
        emptyText:Show()
    end
    ns.Highlight(hlFrame)
    local n, p = list[cur], PendingCount()
    local pend = p > 0 and ("|cffff8c00" .. p .. " pending, " .. Glyph("PAD4") .. " applies|r") or ""
    if n then
        ShowFoot(n.icon, n.name, (n.tree == "Hero" and "Hero spec" or "Choice node") .. ", " .. Glyph("PADDLEFT") .. Glyph("PADDRIGHT") .. " swaps", pend)
    else
        ShowFoot(nil, "", "", pend)
    end
end

local function NodeBtn(i)
    if nodeBtns[i] then return nodeBtns[i] end
    local b = CreateFrame("Button", nil, treeContent, "BackdropTemplate")
    b:SetBackdrop(EDGE2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon2 = b:CreateTexture(nil, "ARTWORK")
    b.icon2:SetPoint("TOPRIGHT", 2, 2)
    b.rank = Text(b, "NumberFontNormal")
    b.rank:SetPoint("BOTTOMRIGHT", 4, -3)
    b:SetFrameLevel(treeContent:GetFrameLevel() + 5)
    b:SetScript("OnClick", function(self)
        SetCur(self.index)
        if ns.BookRefresh then ns.BookRefresh() end
    end)
    nodeBtns[i] = b
    return b
end

local function Line(i)
    if lines[i] then return lines[i] end
    local l = treeContent:CreateLine(nil, "BACKGROUND")
    lines[i] = l
    return l
end

local function PaintTree(key)
    local tree = tal.trees[key]
    if not tree then return end
    local cur = math.max(1, math.min(Cur(), #tree.nodes))
    SetCur(cur)
    header.left:SetText(tree.label .. " tree")
    header.right:SetText("Points left " .. tostring(PointsLeft(tree)))
    header:Show()
    local byID, s = {}, tree.size

    -- keep the cursor node in view, the tree is taller than the window now
    local at = tree.nodes[cur]
    local top = state.top["tree:" .. key] or 0
    if at.y - 8 < top then
        top = at.y - 8
    elseif at.y + s + 8 > top + TREE_H then
        top = at.y + s + 8 - TREE_H
    end
    top = math.max(0, math.min(top, tree.height - TREE_H))
    state.top["tree:" .. key] = top
    treeContent:SetHeight(tree.height)
    treeContent:ClearAllPoints()
    treeContent:SetPoint("TOPLEFT", treeClip, "TOPLEFT", 0, top)
    treeClip.up:SetShown(top > 0)
    treeClip.down:SetShown(top + TREE_H < tree.height - 1)
    treeClip:Show()

    for i, n in ipairs(tree.nodes) do
        local b = NodeBtn(i)
        b.index = i
        b:SetSize(s, s)
        b.icon2:SetSize(math.floor(s * 0.38), math.floor(s * 0.38))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", treeContent, "TOPLEFT", n.x, -n.y)
        SetLook(b.icon, n.icon)
        local info = n.info
        local learned, avail = info.ranksPurchased > 0, info.isAvailable or info.canPurchaseRank
        local split = info.type == N_SELECTION and not learned and n.icon2
        b.icon:SetTexCoord(0, split and 0.5 or 1, 0, 1)
        b.icon2:SetShown(info.type == N_SELECTION and n.icon2 ~= nil)
        if n.icon2 then SetLook(b.icon2, n.icon2) end
        b.icon:SetDesaturated(not learned and not avail)
        b.icon:SetAlpha((learned or avail) and 1 or 0.5)
        local c = Staged(n) and PALETTE.accent or learned and GOLD or avail and GREEN or GREY
        b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        b.rank:SetText(info.maxRanks > 1 and (info.ranksPurchased .. "/" .. info.maxRanks) or "")
        b:Show()
        byID[n.id] = b
    end
    local li = 0
    for _, n in ipairs(tree.nodes) do
        for _, e in ipairs(n.info.visibleEdges or {}) do
            local to = byID[e.targetNode]
            if to then
                li = li + 1
                local l, on = Line(li), n.info.ranksPurchased > 0 and e.isActive
                l:SetStartPoint("CENTER", byID[n.id])
                l:SetEndPoint("CENTER", to)
                l:SetThickness(on and 3 or 2)
                l:SetColorTexture(on and GOLD[1] or 0.3, on and GOLD[2] or 0.3, on and GOLD[3] or 0.33, 1)
                l:Show()
            end
        end
    end
    ns.Highlight(nodeBtns[cur])
    local n = tree.nodes[cur]
    local info = n.info
    local status = info.ranksPurchased > 0 and (info.type == N_SELECTION and "Learned, X swaps the pick" or "Learned")
        or (info.isAvailable or info.canPurchaseRank) and "Available" or "Locked"
    local kind = info.type == N_SELECTION and "Choice" or (n.spellID and C_Spell.IsSpellPassive(n.spellID)) and "Passive" or "Active"
    if info.maxRanks > 1 then kind = kind .. ", rank " .. info.ranksPurchased .. "/" .. info.maxRanks end
    local p = PendingCount()
    ShowFoot(n.icon, n.name, kind .. ". " .. status, p > 0 and ("|cffff8c00" .. p .. " pending|r") or "")
end

local function PaintTabs()
    local names = {}
    if state.sec == "spells" then
        for _, t in ipairs(spellTabs) do names[#names + 1] = t.name end
    else
        for _, k in ipairs(tal.tabs) do names[#names + 1] = tal.trees[k] and tal.trees[k].label or k end
    end
    local n = #names
    local w = (BODY_W - 60 - (n - 1) * 4) / math.max(n, 1)
    for i = 1, math.max(n, #tabFrames) do
        local t = tabFrames[i]
        if not t and i <= n then
            t = CreateFrame("Button", nil, main, "BackdropTemplate")
            t:SetHeight(28)
            t:SetBackdrop(BACKDROP)
            t.text = Text(t, "GameFontHighlight")
            t.text:SetPoint("CENTER")
            t:SetScript("OnClick", function(self)
                state.tab[state.sec] = self.index
                ns.BookRefresh()
            end)
            tabFrames[i] = t
        end
        if t then
            t.index = i
            t:SetShown(i <= n)
            if i <= n then
                t:SetWidth(w)
                t:SetPoint("TOPLEFT", main, "TOPLEFT", 15 + 30 + (i - 1) * (w + 4), -44)
                t.text:SetText(names[i])
                local on = i == state.tab[state.sec]
                t:SetBackdropColor(on and 0.35 or PALETTE.tab[1], on and 0.19 or PALETTE.tab[2], on and 0.02 or PALETTE.tab[3], 1)
                t:SetBackdropBorderColor(on and PALETTE.accent[1] or PALETTE.border[1], on and PALETTE.accent[2] or PALETTE.border[2], on and PALETTE.accent[3] or PALETTE.border[3], 1)
                t.text:SetTextColor(unpack(on and PALETTE.text or PALETTE.textDim))
            end
        end
    end
    main.l1:SetText(Glyph("PADLSHOULDER"))
    main.r1:SetText(Glyph("PADRSHOULDER"))
    local sp = state.sec == "spells"
    main.sect:SetText(Glyph("PADLTRIGGER") .. (sp and " |cffffffffSpells|r  |cff888888Talents|r " or " |cff888888Spells|r  |cffffffffTalents|r ") .. Glyph("PADRTRIGGER"))
end

-- placing ---------------------------------------------------------------------

-- the driver already moved the face buttons, just read where they point
local ROW_SLOTS = { [0] = "1-4", "5-8", "9-12" }
local function PlacePage()
    return ns.CurPage(), ns.CurRow()
end

local function UpdateBanner()
    if not place then return end
    local name, icon
    if place.clearing then
        name, icon = "Clearing a slot", nil
    else
        name, icon = CursorLabel()
        name = "Placing " .. (name or "?")
    end
    banner.icon:SetTexture(icon or 136813)
    banner.title:SetText(name)
    local g = place.grid
    if g then
        banner.how:SetText(("Lands on %s, slot %d. %s drops it, %s back to the diamonds.")
            :format(ns.PageName(ns.PANEL_DEFS[g.side].page), g.idx, Glyph("PAD3"), Glyph("PADFORWARD")))
    else
        local page, row = PlacePage()
        banner.how:SetText(("Press a face button. Lands on %s, slots %s. D-pad picks the bar, hold %s or %s for slots 5-8 / 9-12, %s %s for the grids.")
            :format(ns.PageName(page), ROW_SLOTS[row] or "1-4", Glyph("PADLTRIGGER"), Glyph("PADRTRIGGER"),
                Glyph("PADLSHOULDER"), Glyph("PADRSHOULDER")))
    end
end

local function EndPlace(cancel)
    if not place then return end
    if cancel and not place.clearing then ClearCursor() end
    place = nil
    ns.SetPlaceMode(nil)
    banner:Hide()
    main:Show()
    ns.BookRefresh()
    ns.RefreshLegend()
end

local function StartPlace(clearing)
    place = { clearing = clearing }
    main:Hide()
    banner:Show()
    ns.Highlight(nil)
    ns.SetPlaceMode("slots")
    UpdateBanner()
    ns.RefreshLegend()
end

local function Drop(btn)
    local slot = btn and btn:GetAttribute("action")
    if not slot then return end
    if place.clearing then
        PickupAction(slot)
        ClearCursor()
        Err("Slot cleared")
        EndPlace()
        return
    end
    PlaceAction(slot)
    -- whatever was there is on the cursor now, keep carrying it
    C_Timer.After(0.05, function()
        if not place then return end
        if GetCursorInfo() then
            UpdateBanner()
        else
            EndPlace()
        end
    end)
end

local function GridKey(key)
    local g = place.grid
    local col, row = (g.idx - 1) % 4, math.floor((g.idx - 1) / 4)
    if key == "PADDUP" then
        row = (row + 2) % 3
    elseif key == "PADDDOWN" then
        row = (row + 1) % 3
    elseif key == "PADDLEFT" then
        col = col - 1
        if col < 0 then col, g.side = 3, g.side == "R" and "L" or "R" end
    elseif key == "PADDRIGHT" then
        col = col + 1
        if col > 3 then col, g.side = 0, g.side == "L" and "R" or "L" end
    elseif key == "PADLSHOULDER" or key == "PADRSHOULDER" then
        g.side = key == "PADLSHOULDER" and "L" or "R"
    elseif key == "PAD3" then
        Drop(ns.panels[g.side].buttons[g.idx])
        return
    else
        return
    end
    g.idx = row * 4 + col + 1
    lastGrid = { side = g.side, idx = g.idx }
end

local function PlaceKey(key)
    if key == "PADFORWARD" then
        if place.grid then
            place.grid = nil
            ns.SetPlaceMode("slots")
        else
            EndPlace(true)
            return
        end
    elseif place.grid then
        GridKey(key)
    elseif ns.BAR_INDEX[key] then
        -- dpad switches the bar like it does outside the book
        ns.SetBar(ns.BAR_INDEX[key])
    elseif key == "PADLSHOULDER" or key == "PADRSHOULDER" then
        -- bumpers point up into their grid
        local side = key == "PADLSHOULDER" and "L" or "R"
        place.grid = { side = side, idx = (lastGrid and lastGrid.side == side) and lastGrid.idx or 1 }
        ns.SetPlaceMode("grid")
    else
        local i = ns.KEY_INDEX[key]
        if not i or i > ns.NUM_SLOTS then return end
        Drop(ns.buttons[i])
        return
    end
    if place then
        ns.Highlight(place.grid and ns.panels[place.grid.side].buttons[place.grid.idx] or nil)
        UpdateBanner()
        ns.RefreshLegend()
    end
end

-- talent actions ---------------------------------------------------------------

local function Retalent()
    LoadTalents()
    ns.BookRefresh()
end

local function Apply()
    local cfg = tal.configID
    if not cfg or not C_Traits.ConfigHasStagedChanges(cfg) then
        Err("No changes to apply")
        return
    end
    local spec = SpecID()
    if C_ClassTalents.CommitConfig(spec and C_ClassTalents.GetLastSelectedSavedConfigID(spec)) then
        Err("Changing talents")
    else
        Err("Couldn't apply talents right now")
    end
end

local function Revert()
    if tal.configID and C_Traits.ConfigHasStagedChanges(tal.configID) then
        C_Traits.RollbackConfig(tal.configID)
        Err("Changes reverted")
    end
    Retalent()
end

local function TreeKey(key)
    local tree = tal.trees[CurTab()]
    if not tree then return end
    local cur = Cur()
    local n = tree.nodes[cur]
    if DPAD[key] then
        -- nearest node that way, sideways drift costs double
        local vx, vy = 0, 0
        if key == "PADDUP" then vy = -1 elseif key == "PADDDOWN" then vy = 1 elseif key == "PADDLEFT" then vx = -1 else vx = 1 end
        local best, score = cur, math.huge
        for i, m in ipairs(tree.nodes) do
            local dx, dy = m.x - n.x, m.y - n.y
            local fwd, side = dx * vx + dy * vy, math.abs(dx * vy - dy * vx)
            if fwd > 0 and fwd + side * 2 < score then best, score = i, fwd + side * 2 end
        end
        SetCur(best)
        return
    end
    local cfg, info = tal.configID, n.info
    if key == "PAD3" then
        local ok
        if info.type == N_SELECTION then
            local active = info.activeEntry and info.activeEntry.entryID
            local nextEntry = (active == info.entryIDs[1] and info.entryIDs[2]) or info.entryIDs[1]
            ok = C_Traits.SetSelection(cfg, n.id, active and nextEntry or info.entryIDs[1])
        else
            ok = C_Traits.PurchaseRank(cfg, n.id)
        end
        if not ok then Err("Can't learn that one yet") end
        Retalent()
    elseif key == "PAD1" then
        local ok
        if info.type == N_SELECTION then
            ok = C_Traits.SetSelection(cfg, n.id, nil)
        else
            ok = C_Traits.RefundRank(cfg, n.id)
        end
        if not ok then Err("Something else depends on that one") end
        Retalent()
    elseif key == "PAD4" then
        Apply()
    end
end

local function ChoiceKey(key)
    local n = tal.choices[Cur()]
    local count = #tal.choices
    if key == "PADDUP" then
        SetCur(math.max(1, Cur() - 1))
    elseif key == "PADDDOWN" then
        SetCur(math.min(count, Cur() + 1))
    elseif n and (key == "PADDLEFT" or key == "PADDRIGHT") then
        local want = n.info.entryIDs[key == "PADDLEFT" and 1 or 2]
        local active = n.info.activeEntry and n.info.activeEntry.entryID
        if want and want ~= active then
            if not C_Traits.SetSelection(tal.configID, n.id, want) then Err("Can't swap that right now") end
            Retalent()
        end
    elseif key == "PAD4" then
        Apply()
    elseif key == "PAD1" then
        Revert()
    end
end

local function LoadoutKey(key)
    local list, active = Loadouts()
    local cur = Cur()
    if key == "PADDUP" then
        SetCur(math.max(1, cur - 1))
    elseif key == "PADDDOWN" then
        SetCur(math.min(#list, cur + 1))
    elseif key == "PAD3" and list[cur] then
        local l = list[cur]
        if l.id == active then
            Err(l.name .. " is already active")
            return
        end
        local result = C_ClassTalents.LoadConfig(l.id, true)
        if result == Enum.LoadConfigResult.Error then
            Err("Couldn't load " .. l.name)
        else
            C_ClassTalents.UpdateLastSelectedSavedConfigID(SpecID(), l.id)
            if result == Enum.LoadConfigResult.Ready then C_ClassTalents.CommitConfig(l.id) end
            Err("Loading " .. l.name)
        end
    end
end

local function SpellKey(key)
    local list = SpellList()
    local cur, n = Cur(), #list
    if key == "PADDLEFT" then
        SetCur(cur > 1 and cur - 1 or n)
    elseif key == "PADDRIGHT" then
        SetCur(cur < n and cur + 1 or 1)
    elseif key == "PADDUP" then
        if cur - COLS >= 1 then SetCur(cur - COLS) end
    elseif key == "PADDDOWN" then
        SetCur(math.min(cur + COLS, n))
    elseif key == "PAD4" then
        state.unplaced = not state.unplaced
        SetCur(1)
    elseif key == "PAD3" then
        local item = list[cur]
        if item == CLEAR then
            StartPlace(true)
        elseif item then
            ClearCursor()
            C_SpellBook.PickupSpellBookItem(item.slot, BANK)
            if GetCursorInfo() then
                StartPlace(false)
            else
                Err("Can't pick that one up")
            end
        end
    end
end

-- entry points ------------------------------------------------------------------

local function Paint()
    if not book:IsShown() then return end
    if place then
        ns.Highlight(place.grid and ns.panels[place.grid.side].buttons[place.grid.idx] or nil)
        UpdateBanner()
        return
    end
    if state.tab[state.sec] > #(state.sec == "spells" and spellTabs or tal.tabs) then state.tab[state.sec] = 1 end
    HideBody()
    PaintTabs()
    if state.sec == "spells" then
        PaintSpells()
    else
        local tab = CurTab()
        if tab == "Loadouts" then
            PaintLoadouts()
        elseif tab == "Choices" then
            PaintChoices()
        else
            PaintTree(tab)
        end
    end
end
ns.BookRefresh = Paint

ns.BookShown = function()
    return book and book:IsShown()
end

ns.BookKey = function(key)
    if place then return PlaceKey(key) end
    if key == "PADFORWARD" or key == "PAD2" then
        book:Hide()
        return
    end
    if key == "PADLSHOULDER" or key == "PADRSHOULDER" then
        local n = #(state.sec == "spells" and spellTabs or tal.tabs)
        if n > 0 then
            state.tab[state.sec] = (state.tab[state.sec] + (key == "PADRSHOULDER" and 0 or n - 2)) % n + 1
        end
    elseif state.sec == "spells" then
        SpellKey(key)
    else
        local tab = CurTab()
        if tab == "Loadouts" then
            LoadoutKey(key)
        elseif tab == "Choices" then
            ChoiceKey(key)
        else
            TreeKey(key)
        end
    end
    if not place then Paint() end
end

ns.BookLegend = function()
    local function E(key, text) return Glyph(key) .. " " .. text end
    local nav = Glyph("PADDUP") .. Glyph("PADDDOWN")
    if place and place.grid then
        return { E("PAD3", "Drop here"), nav .. " Move", Glyph("PADLSHOULDER") .. Glyph("PADRSHOULDER") .. " Grid", E("PADFORWARD", "Back") }
    elseif place then
        return { Glyph("PAD1") .. Glyph("PAD2") .. Glyph("PAD3") .. Glyph("PAD4") .. " Place",
            Glyph("PADDUP") .. Glyph("PADDRIGHT") .. " Bar", Glyph("PADLTRIGGER") .. Glyph("PADRTRIGGER") .. " Hold for 5-12",
            Glyph("PADLSHOULDER") .. Glyph("PADRSHOULDER") .. " Grids", E("PADFORWARD", "Cancel") }
    elseif state.sec == "spells" then
        return { E("PAD3", "Pick up"), E("PAD4", state.unplaced and "Show all" or "Unplaced only"), E("PAD2", "Close"), nav .. " Move" }
    end
    local tab = CurTab()
    if tab == "Loadouts" then
        return { E("PAD3", "Load"), E("PAD2", "Close"), nav .. " Pick" }
    elseif tab == "Choices" then
        return { Glyph("PADDLEFT") .. Glyph("PADDRIGHT") .. " Swap", E("PAD4", "Apply"), E("PAD1", "Revert"), E("PAD2", "Close") }
    end
    return { E("PAD3", "Learn"), E("PAD1", "Unlearn"), E("PAD4", "Apply"), E("PAD2", "Close"), nav .. " Move" }
end

-- sec: "spells" or "talents"
ns.OpenBook = function(sec)
    if InCombatLockdown() then
        Err("The book is out of combat only")
        return
    end
    state.sec = sec or state.sec
    LoadSpells()
    LoadTalents()
    book:SetScale(ns.db.configScale or 1)
    book:Show()
    Paint()
end

ns.ToggleBook = function(sec)
    if book:IsShown() and (not sec or sec == state.sec) then
        book:Hide()
    else
        ns.OpenBook(sec)
    end
end

-- frames ------------------------------------------------------------------------

local function Build()
    book = CreateFrame("Frame", "JarStickBook", UIParent)
    book:SetSize(W, H)
    book:SetPoint("CENTER", 0, 40)
    book:SetFrameStrata("DIALOG")
    book:SetClampedToScreen(true)
    book:Hide()
    table.insert(UISpecialFrames, "JarStickBook")

    main = CreateFrame("Frame", nil, book, "BackdropTemplate")
    main:SetAllPoints()
    main:SetBackdrop(BACKDROP)
    main:SetBackdropColor(unpack(PALETTE.bg))
    main:SetBackdropBorderColor(unpack(PALETTE.border))
    main:EnableMouse(true)

    local titleBar = main:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(34)
    titleBar:SetColorTexture(unpack(PALETTE.header))
    local accent = main:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    accent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(unpack(PALETTE.accent))
    local title = Text(main, "GameFontNormalHuge", unpack(PALETTE.text))
    title:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    title:SetText("Itsu:UI")
    main.sect = Text(main, "GameFontHighlightLarge")
    main.sect:SetPoint("RIGHT", titleBar, "RIGHT", -44, 0)
    local close = CreateFrame("Button", nil, main)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -5, -5)
    close.text = Text(close, "GameFontNormalHuge", unpack(PALETTE.textDim))
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("\195\151")
    close:SetScript("OnClick", function() book:Hide() end)

    main.l1 = Text(main, "GameFontHighlight")
    main.l1:SetPoint("TOPLEFT", 16, -50)
    main.r1 = Text(main, "GameFontHighlight")
    main.r1:SetPoint("TOPRIGHT", -16, -50)

    body = CreateFrame("Frame", nil, main)
    body:SetSize(BODY_W, BODY_H)
    body:SetPoint("TOPLEFT", 15, -82)

    header = CreateFrame("Frame", nil, body)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(20)
    header.left = Text(header, "GameFontHighlight")
    header.left:SetPoint("LEFT")
    header.right = Text(header, "GameFontHighlight", unpack(PALETTE.textDim))
    header.right:SetPoint("RIGHT")
    emptyText = Text(body, "GameFontHighlightLarge", unpack(PALETTE.textDim))
    emptyText:SetPoint("CENTER", 0, -20)

    treeClip = CreateFrame("Frame", nil, body)
    treeClip:SetPoint("TOPLEFT", 0, -26)
    treeClip:SetSize(BODY_W, TREE_H)
    treeClip:SetClipsChildren(true)
    treeContent = CreateFrame("Frame", nil, treeClip)
    treeContent:SetSize(BODY_W, TREE_H)
    treeClip.up = Text(header, "GameFontDisableSmall")
    treeClip.up:SetPoint("CENTER", header, "CENTER", 0, 0)
    treeClip.up:SetText("more above")
    treeClip.down = Text(main, "GameFontDisableSmall")
    treeClip.down:SetPoint("TOP", treeClip, "BOTTOM", 0, -1)
    treeClip.down:SetText("more below")
    treeClip:Hide()

    foot = CreateFrame("Frame", nil, main, "BackdropTemplate")
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(68)
    foot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    foot:SetBackdropColor(0, 0, 0, 0.35)
    foot.icon = foot:CreateTexture(nil, "ARTWORK")
    foot.icon:SetSize(40, 40)
    foot.icon:SetPoint("LEFT", 14, 0)
    foot.right = Text(foot, "GameFontHighlight", unpack(PALETTE.textDim))
    foot.right:SetPoint("RIGHT", -14, 0)
    foot.name = Text(foot, "GameFontNormalLarge", unpack(PALETTE.text))
    foot.name:SetPoint("TOPLEFT", foot.icon, "TOPRIGHT", 12, 2)
    foot.name:SetPoint("RIGHT", foot.right, "LEFT", -10, 0)
    foot.name:SetJustifyH("LEFT")
    foot.sub = Text(foot, "GameFontHighlightSmall", unpack(PALETTE.textDim))
    foot.sub:SetPoint("TOPLEFT", foot.name, "BOTTOMLEFT", 0, -3)
    foot.sub:SetPoint("RIGHT", foot.right, "LEFT", -10, 0)
    foot.sub:SetJustifyH("LEFT")
    foot.sub:SetMaxLines(2)

    banner = CreateFrame("Frame", nil, book, "BackdropTemplate")
    banner:SetSize(540, 80)
    banner:SetPoint("TOP", 0, 10)
    banner:SetBackdrop(BACKDROP)
    banner:SetBackdropColor(unpack(PALETTE.bg))
    banner:SetBackdropBorderColor(unpack(PALETTE.accent))
    banner.icon = banner:CreateTexture(nil, "ARTWORK")
    banner.icon:SetSize(48, 48)
    banner.icon:SetPoint("LEFT", 16, 0)
    banner.title = Text(banner, "GameFontNormalHuge", unpack(PALETTE.text))
    banner.title:SetPoint("TOPLEFT", banner.icon, "TOPRIGHT", 14, 0)
    banner.how = Text(banner, "GameFontHighlight", unpack(PALETTE.textDim))
    banner.how:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -4)
    banner.how:SetWidth(440)
    banner.how:SetJustifyH("LEFT")
    banner:Hide()
    -- page under the triggers can change any frame, keep the text honest
    local lastPage
    banner:SetScript("OnUpdate", function()
        local page, row = PlacePage()
        local p = page .. ":" .. row
        if p ~= lastPage then
            lastPage = p
            UpdateBanner()
        end
    end)

    book:SetScript("OnHide", function()
        if place then EndPlace(true) end
        if tal.configID and C_Traits.ConfigHasStagedChanges(tal.configID) and not InCombatLockdown() then
            C_Traits.RollbackConfig(tal.configID)
            Err("Unapplied talent changes dropped")
        end
        ns.Highlight(nil)
    end)
end

Build()

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("CURSOR_CHANGED")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
ev:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
ev:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("SELECTED_LOADOUT_CHANGED")
ev:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
local pending
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_REGEN_DISABLED" then
        -- regen disabled fires just before lockdown, last chance to put things back
        if place then EndPlace(true) end
        if book:IsShown() then book:Hide() end
        return
    end
    if not book:IsShown() then return end
    if event == "CURSOR_CHANGED" then
        if place and not place.clearing then
            C_Timer.After(0.05, function()
                if place and not place.clearing and not GetCursorInfo() then EndPlace() end
            end)
        end
        return
    end
    if event == "MODIFIER_STATE_CHANGED" then
        -- L2 / R2 taps flip the section, held while placing they pick the page
        if not place and arg2 == 1 then
            if arg1 == "LSHIFT" or arg1 == "RSHIFT" then
                state.sec = "spells"
                Paint()
                ns.RefreshLegend()
            elseif arg1 == "LCTRL" or arg1 == "RCTRL" then
                state.sec = "talents"
                Paint()
                ns.RefreshLegend()
            end
        end
        return
    end
    if event == "TRAIT_CONFIG_UPDATED" then
        -- a commit landed, new baseline
        wipe(tal.snap)
    end
    -- bursts of these come together, repaint once
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = nil
        if not book:IsShown() then return end
        LoadSpells()
        LoadTalents()
        Paint()
    end)
end)

end
