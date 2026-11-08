-- Itsu:UI: screen grid overlay for lining stuff up

local _, ns = ...

ns.RegisterModule("grid", "Screen Grid", function()

local GRID_COLOR = { 1, 1, 1, 0.15 }
local CENTER_COLOR = { 1, 0.55, 0, 0.4 }

local gridFrame
local gridLines = {}
local usedLines = 0

local function Spacing()
    return ns.db.grid.spacing or 50
end

-- reuse textures, they cant be freed so dont keep making new ones
local function NextLine(c, a, lw, lh)
    usedLines = usedLines + 1
    local line = gridLines[usedLines]
    if not line then
        line = gridFrame:CreateTexture(nil, "OVERLAY")
        gridLines[usedLines] = line
    end
    line:ClearAllPoints()
    line:SetColorTexture(c[1], c[2], c[3], a)
    line:SetSize(lw, lh)
    line:Show()
    return line
end

local function DrawGrid()
    for i = 1, #gridLines do gridLines[i]:Hide() end
    usedLines = 0

    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = w / 2, h / 2
    local spacing = Spacing()
    local a = GRID_COLOR[4]

    -- out from center
    for i = 1, math.ceil(cx / spacing) do
        local off = i * spacing
        NextLine(GRID_COLOR, a, 1, h):SetPoint("TOPLEFT", gridFrame, "TOPLEFT", cx + off, 0)
        NextLine(GRID_COLOR, a, 1, h):SetPoint("TOPLEFT", gridFrame, "TOPLEFT", cx - off, 0)
    end
    for i = 1, math.ceil(cy / spacing) do
        local off = i * spacing
        NextLine(GRID_COLOR, a, w, 1):SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -(cy + off))
        NextLine(GRID_COLOR, a, w, 1):SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -(cy - off))
    end

    -- crosshair + thirds
    NextLine(CENTER_COLOR, CENTER_COLOR[4], 2, h):SetPoint("TOP", gridFrame, "TOP", 0, 0)
    NextLine(CENTER_COLOR, CENTER_COLOR[4], w, 2):SetPoint("LEFT", gridFrame, "LEFT", 0, 0)
    for _, frac in ipairs({ 1/3, 2/3 }) do
        NextLine(CENTER_COLOR, CENTER_COLOR[4] * 0.5, 1, h):SetPoint("TOPLEFT", gridFrame, "TOPLEFT", w * frac, 0)
        NextLine(CENTER_COLOR, CENTER_COLOR[4] * 0.5, w, 1):SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -h * frac)
    end
end

local function EnsureFrame()
    if gridFrame then return end
    gridFrame = CreateFrame("Frame", "JarGridOverlay", UIParent)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:SetFrameStrata("TOOLTIP")
    gridFrame:EnableMouse(false)
    gridFrame:Hide()
end

ns.grid = {
    IsShown = function() return gridFrame and gridFrame:IsShown() end,
    Toggle = function()
        EnsureFrame()
        if gridFrame:IsShown() then
            gridFrame:Hide()
        else
            DrawGrid() -- redraw incase ui scale/res changed
            gridFrame:Show()
        end
    end,
    SetSpacing = function(v)
        ns.db.grid.spacing = v
        if gridFrame and gridFrame:IsShown() then DrawGrid() end
    end,
}

SLASH_JARGRID1 = "/grid"
SlashCmdList["JARGRID"] = function()
    ns.grid.Toggle()
    ns.RefreshPanel("Tools")
end

end)
