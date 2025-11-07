local addonName, addon = ...

addon.BarBorders = addon.BarBorders or {}
local BarBorders = addon.BarBorders

local MEDIA_PATH_PREFIX = "Interface\\AddOns\\ScooterMod\\media\\barborder\\"
local DEFAULT_REFERENCE_HEIGHT = 18
local DEFAULT_THICKNESS_MULTIPLIER = 1.35
local MAX_EDGE_SIZE = 48

local CATEGORY_LABELS = {
    traditional = "Traditional",
    clean = "Clean",
}

local STYLE_DEFINITIONS = {
    -- Traditional selections (soft gradients, Blizzard-adjacent)
    { key = "mmtBorder1", label = "mMediaTag Border 1", file = "mborder1.tga", category = "traditional", order = 10, thicknessScale = 1.10, paddingMultiplier = 0.55 },
    { key = "mmtBorder2", label = "mMediaTag Border 2", file = "mborder2.tga", category = "traditional", order = 20, thicknessScale = 1.20, paddingMultiplier = 0.55 },
    { key = "mmtYBorder", label = "mMediaTag Y Border", file = "yborder.tga", category = "traditional", order = 30, thicknessScale = 1.15, paddingMultiplier = 0.55 },
    { key = "mmtYBorder2", label = "mMediaTag Y Border 2", file = "yborder2.tga", category = "traditional", order = 40, thicknessScale = 1.20, paddingMultiplier = 0.55 },
    { key = "mmtYuluSwitch", label = "Yulu Border Switch", file = "YuluBorderSwitch.tga", category = "traditional", order = 50, thicknessScale = 1.30, paddingMultiplier = 0.55 },
    { key = "mmtYuluXI", label = "Yulu Border XI", file = "YuluBorderXI.tga", category = "traditional", order = 60, thicknessScale = 1.30, paddingMultiplier = 0.55 },

    -- Clean, geometric lines
    { key = "mmtPixel", label = "Pixel", file = "pixel.tga", category = "clean", order = 110, thicknessScale = 0.90, paddingMultiplier = 0.40, minEdgeSize = 1 },
    { key = "mmtRound", label = "Round", file = "round.tga", category = "clean", order = 120, thicknessScale = 1.25, paddingMultiplier = 0.50 },
    { key = "mmtSquares", label = "Squares", file = "squares.tga", category = "clean", order = 130, thicknessScale = 1.25, paddingMultiplier = 0.50 },
    { key = "mmtCorners", label = "Corners", file = "corners.tga", category = "clean", order = 140, thicknessScale = 1.35, paddingMultiplier = 0.55 },
    { key = "mmtPencil", label = "Pencil & Ruler", file = "pencilandlieneal.tga", category = "clean", order = 150, thicknessScale = 1.10, paddingMultiplier = 0.50 },
    { key = "mmtPencilMono", label = "Pencil & Ruler (Mono)", file = "pencilandlienealblack.tga", category = "clean", order = 160, thicknessScale = 1.10, paddingMultiplier = 0.50 },
    { key = "mmtWood", label = "Wood", file = "wood.tga", category = "clean", order = 170, thicknessScale = 1.35, paddingMultiplier = 0.55 },

}

local STYLE_MAP = {}
local STYLE_ORDER = {}

for _, def in ipairs(STYLE_DEFINITIONS) do
    def.texture = MEDIA_PATH_PREFIX .. def.file
    def.previewWidth = def.previewWidth or 180
    def.previewHeight = def.previewHeight or 18
    def.paddingMultiplier = def.paddingMultiplier or 0.5
    def.thicknessScale = def.thicknessScale or 1.0
    STYLE_MAP[def.key] = def
    STYLE_ORDER[#STYLE_ORDER + 1] = def.key
end

table.sort(STYLE_ORDER, function(a, b)
    local sa = STYLE_MAP[a]
    local sb = STYLE_MAP[b]
    local oa = (sa and sa.order) or 999
    local ob = (sb and sb.order) or 999
    if oa == ob then
        local la = sa and sa.label or ""
        local lb = sb and sb.label or ""
        return la < lb
    end
    return oa < ob
end)

local function cloneColor(color)
    if type(color) ~= "table" then
        return { 1, 1, 1, 1 }
    end
    return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
end

local function ensureBorderFrame(barFrame)
    local holder = barFrame.ScooterStyledBorder
    if not holder then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local parentOverride = rawget(barFrame, "_ScooterBorderContainerParentRef")
        holder = CreateFrame("Frame", nil, parentOverride or barFrame, template)
        holder:SetClipsChildren(false)
        holder:SetIgnoreParentAlpha(false)
        barFrame.ScooterStyledBorder = holder
    end
    local strata = (barFrame._ScooterBorderContainerParentRef or barFrame).GetFrameStrata and (barFrame._ScooterBorderContainerParentRef or barFrame):GetFrameStrata()
    if strata then
        holder:SetFrameStrata(strata)
    end
    local parentForLevel = barFrame._ScooterBorderContainerParentRef or barFrame
    local level = (parentForLevel.GetFrameLevel and parentForLevel:GetFrameLevel()) or 0
    local offset = tonumber(barFrame._ScooterBorderLevelOffset) or 8
    local desiredLevel = tonumber(barFrame._ScooterBorderFixedLevel) or (level + offset)
    holder:SetFrameLevel(desiredLevel)
    return holder
end

local function computeEdgeSize(barFrame, style, thickness)
    local frameHeight = (barFrame and barFrame.GetHeight and barFrame:GetHeight()) or DEFAULT_REFERENCE_HEIGHT
    if frameHeight < 1 then frameHeight = DEFAULT_REFERENCE_HEIGHT end
    local scale = frameHeight / DEFAULT_REFERENCE_HEIGHT
    local multiplier = (style and style.thicknessScale) or 1
    local edgeSize = thickness * DEFAULT_THICKNESS_MULTIPLIER * multiplier * scale
    if style and style.minEdgeSize then
        edgeSize = math.max(style.minEdgeSize, edgeSize)
    end
    if style and style.maxEdgeSize then
        edgeSize = math.min(style.maxEdgeSize, edgeSize)
    end
    if edgeSize > MAX_EDGE_SIZE then edgeSize = MAX_EDGE_SIZE end
    if edgeSize < 1 then edgeSize = 1 end
    return math.floor(edgeSize + 0.5)
end

local function applyBackdrop(holder, style, edgeSize)
    if not holder or not holder.SetBackdrop or not style or not style.texture then
        return false
    end
    local insetMultiplier = style.insetMultiplier or 0.65
    local inset = math.floor(edgeSize * insetMultiplier + 0.5)
    if inset < 0 then inset = 0 end
    local ok = pcall(holder.SetBackdrop, holder, {
        bgFile = nil,
        edgeFile = style.texture,
        tile = false,
        edgeSize = edgeSize,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    return ok
end

local function applyStyle(barFrame, style, color, thickness, skipStateUpdate, inset)
    local holder = ensureBorderFrame(barFrame)
    if not holder then return false end

    -- Edge and padding scale with the bar's height (original behavior)
    local edgeSize = computeEdgeSize(barFrame, style, thickness)
    local paddingMultiplier = style and style.paddingMultiplier or 0.5
    local pad = math.floor(edgeSize * paddingMultiplier + 0.5)
    local insetPx = tonumber(inset) or tonumber(barFrame and barFrame._ScooterBorderInset) or 0
    -- Positive inset pulls the border inward (smaller padding); negative pushes outward
    local padAdj = pad - insetPx
    if padAdj < 0 then padAdj = 0 end

    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -padAdj, padAdj)
    holder:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", padAdj, -padAdj)

    if not applyBackdrop(holder, style, edgeSize) then
        holder:Hide()
        return false
    end

    if holder.SetBackdropBorderColor then
        holder:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if holder.SetBackdropColor then
        holder:SetBackdropColor(0, 0, 0, 0)
    end

    holder:Show()

    if not skipStateUpdate then
        barFrame._ScooterBorderState = {
            styleKey = style.key,
            thickness = thickness,
            color = cloneColor(color),
            inset = insetPx,
        }
    end

    return true
end

local function handleSizeChanged(frame)
    if not frame or not frame._ScooterBorderState then return end
    local state = frame._ScooterBorderState
    if not state.styleKey then return end
    local style = STYLE_MAP[state.styleKey]
    if not style then return end
    local color = cloneColor(state.color)
    local thickness = tonumber(state.thickness) or 1
    applyStyle(frame, style, color, thickness, true, tonumber(state.inset) or 0)
end

local function ensureSizeHook(barFrame)
    if not barFrame or barFrame._ScooterBorderSizeHooked then return end
    if barFrame.HookScript then
        barFrame:HookScript("OnSizeChanged", handleSizeChanged)
        barFrame._ScooterBorderSizeHooked = true
    end
end

local function formatMenuLabel(style, options)
    if not style then return "" end
    local label = style.label or style.key or "Unknown"
    if not (options and options.hideCategoryTag) then
        local cat = style.category and CATEGORY_LABELS[style.category]
        if cat then
            label = string.format("%s [%s]", label, cat)
        end
    end
    local previewHeight = (options and options.previewHeight) or style.previewHeight or 18
    local previewWidth = (options and options.previewWidth) or style.previewWidth or 180
    local preview = string.format("|T%s:%d:%d|t", style.texture, previewHeight, previewWidth)
    return string.format("%s  %s", label, preview)
end

local function buildCategoryFilter(options)
    local includeCategory = options and options.includeCategory
    local filter = {}
    if includeCategory == nil or includeCategory == true then
        for key in pairs(CATEGORY_LABELS) do
            filter[key] = true
        end
    elseif type(includeCategory) == "table" then
        for key in pairs(CATEGORY_LABELS) do
            filter[key] = not not includeCategory[key]
        end
    else
        -- Explicitly disable all categories if includeCategory is false/invalid
        for key in pairs(CATEGORY_LABELS) do
            filter[key] = false
        end
    end
    return filter
end

function BarBorders.GetStyle(key)
    return STYLE_MAP[key]
end

function BarBorders.GetDropdownEntries(options)
    options = options or {}
    local categoryFilter = buildCategoryFilter(options)

    local container
    if _G.Settings and Settings.CreateControlTextContainer then
        container = Settings.CreateControlTextContainer()
    end

    local entries = {}

    local function addEntry(value, text)
        if container then
            container:Add(value, text)
        else
            entries[#entries + 1] = { value = value, text = text }
        end
    end

    addEntry("square", "Default (Square)")

    for _, key in ipairs(STYLE_ORDER) do
        local style = STYLE_MAP[key]
        if style then
            local include = true
            if style.category and categoryFilter[style.category] ~= nil then
                include = categoryFilter[style.category]
            end
            if include then
                addEntry(style.key, formatMenuLabel(style, options))
            end
        end
    end

    if container then
        return container:GetData()
    end
    return entries
end

function BarBorders.ApplyToBarFrame(barFrame, styleKey, options)
    if not barFrame or type(barFrame.GetObjectType) ~= "function" or barFrame:GetObjectType() ~= "StatusBar" then
        return false
    end

    if not styleKey or styleKey == "square" then
        BarBorders.ClearBarFrame(barFrame)
        return false
    end

    local style = STYLE_MAP[styleKey]
    if not style then
        BarBorders.ClearBarFrame(barFrame)
        return false
    end

    ensureSizeHook(barFrame)

    local thickness = tonumber(options and options.thickness) or 1
    if thickness < 1 then thickness = 1 end
    if thickness > 32 then thickness = 32 end

    local color = cloneColor(options and options.color)

    -- Allow callers (e.g., Unit Frames) to request a specific relative level/parent so text stays above borders
    if type(options) == "table" and options.levelOffset then
        barFrame._ScooterBorderLevelOffset = tonumber(options.levelOffset) or 8
    else
        barFrame._ScooterBorderLevelOffset = 8
    end
    if type(options) == "table" and options.containerParent and options.containerParent.GetFrameLevel then
        barFrame._ScooterBorderContainerParentRef = options.containerParent
    else
        barFrame._ScooterBorderContainerParentRef = nil
    end
    barFrame._ScooterBorderInset = tonumber(options and options.inset) or 0

    return applyStyle(barFrame, style, color, thickness, false, barFrame._ScooterBorderInset)
end

function BarBorders.ClearBarFrame(barFrame)
    if not barFrame then return end
    barFrame._ScooterBorderState = nil
    local holder = barFrame.ScooterStyledBorder
    if holder then
        if holder.SetBackdrop then pcall(holder.SetBackdrop, holder, nil) end
        holder:Hide()
    end
end
