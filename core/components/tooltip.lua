local addonName, addon = ...

-- Tooltip Component: Manages GameTooltip text styling
-- The GameTooltip creates FontStrings dynamically: GameTooltipTextLeft1, GameTooltipTextLeft2, etc.
-- TextLeft1 is typically the "title/name" line and uses GameTooltipHeaderText by default.
--
-- NOTE: We intentionally do NOT customize color or position:
-- - Color: Tooltip text is dynamically colored by the game (item quality, spell schools, etc.)
-- - Position: Tooltip layout is static and repositioning text would break the layout
--
-- ALIGNMENT STRATEGY (2025-11-26, updated):
-- The GameTooltipHeaderText font object has justifyH="LEFT" baked in. When Blizzard's C code
-- calls SetFontObject internally, it resets alignment.
--
-- We use TooltipDataProcessor.AddTooltipPostCall to apply alignment AFTER all tooltip data
-- processing is complete. CRITICAL: We apply synchronously (no deferred timer) because
-- spell/ability tooltips update continuously for cooldown timers, and deferred timers
-- cause flickering as they race with the next rebuild cycle.

-- Helper: Apply font face/size/style to a FontString
local function ApplyFontSettings(fontString, config, defaultSize)
    if not fontString or not fontString.SetFont then return end

    config = config or {}
    local defaults = {
        size = defaultSize or 14,
        style = "OUTLINE",
        fontFace = "FRIZQT__",
    }

    -- Resolve font face
    local face = addon.ResolveFontFace and addon.ResolveFontFace(config.fontFace or defaults.fontFace)
        or (select(1, _G.GameFontNormal:GetFont()))

    -- Apply font attributes (font face, size, style only)
    local size = tonumber(config.size) or defaults.size
    local style = config.style or defaults.style
    pcall(fontString.SetFont, fontString, face, size, style)
end

-- Helper: Apply alignment and width to a FontString for centering/right-align
local function ApplyAlignmentSettings(fontString, tooltip, config)
    if not fontString or not fontString.SetJustifyH then return end

    config = config or {}
    local alignment = (config.alignment or "LEFT")
    if type(alignment) == "string" then
        alignment = alignment:upper()
    else
        alignment = "LEFT"
    end
    if alignment ~= "LEFT" and alignment ~= "CENTER" and alignment ~= "RIGHT" then
        alignment = "LEFT"
    end

    -- Apply horizontal alignment
    pcall(fontString.SetJustifyH, fontString, alignment)

    -- For CENTER/RIGHT alignment, expand the FontString width to the tooltip's inner width
    -- so the text has room to align within. Without this, a narrow FontString would still
    -- appear left-aligned even with SetJustifyH("CENTER").
    if alignment ~= "LEFT" and tooltip and tooltip.GetWidth and fontString.SetWidth then
        local w = tooltip:GetWidth()
        if w and w > 20 then
            local inner = w - 20 -- 10px left + 10px right padding
            pcall(fontString.SetWidth, fontString, inner)
        end
    end
end

-- Track whether we've registered the TooltipDataProcessor hook
local tooltipProcessorHooked = false

-- Register the TooltipDataProcessor post-call hook (runs after ALL tooltip data is processed)
local function RegisterTooltipPostProcessor()
    if tooltipProcessorHooked then return end
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then
        -- Fallback: TooltipDataProcessor not available (unlikely in retail)
        return false
    end

    tooltipProcessorHooked = true

    -- Register for ALL tooltip types so we catch every tooltip update
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, tooltipData)
        -- Only process GameTooltip
        if tooltip ~= GameTooltip then return end

        local comp = addon.Components and addon.Components.tooltip
        if not comp or not comp.db then return end

        local titleFS = _G["GameTooltipTextLeft1"]
        if not titleFS then return end

        local cfg = comp.db.textTitle or {}

        -- Apply font settings synchronously
        ApplyFontSettings(titleFS, cfg, 14)

        -- Apply alignment synchronously - NO DEFERRED TIMER
        -- Deferred timers cause flickering on spell tooltips because they race with
        -- the continuous TOOLTIP_DATA_UPDATE cycle for cooldown/charge display.
        -- The TooltipDataProcessor callback runs AFTER ProcessLines() completes,
        -- so the font object has already been set and we can override alignment now.
        ApplyAlignmentSettings(titleFS, tooltip, cfg)
    end)

    return true
end

local function ApplyTooltipStyling(self)
    local tooltip = _G["GameTooltip"]
    if not tooltip then return end

    local db = self.db or {}

    -- Clean up deprecated settings (color and offset were removed)
    if db.textTitle then
        db.textTitle.color = nil
        db.textTitle.offset = nil
    end

    -- Ensure TooltipDataProcessor hook is registered
    RegisterTooltipPostProcessor()

    -- Apply Name/Title styling (GameTooltipTextLeft1) - initial application
    local titleFS = _G["GameTooltipTextLeft1"]
    if titleFS then
        local cfg = db.textTitle or {}
        ApplyFontSettings(titleFS, cfg, 14)
        ApplyAlignmentSettings(titleFS, tooltip, cfg)
    end

    -- NOTE: We intentionally do NOT add backup hooks on FontString methods or OnShow.
    -- Those deferred timers conflict with the TooltipDataProcessor approach and cause
    -- flickering on spell/ability tooltips that update continuously.
    -- The TooltipDataProcessor.AddTooltipPostCall hook handles all data-driven tooltips.
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local tooltipComponent = Component:New({
        id = "tooltip",
        name = "Tooltip",
        frameName = "GameTooltip",
        settings = {
            -- Text Title settings (font, size, style, alignment)
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 14,
                style = "OUTLINE",
                alignment = "LEFT",
            }, ui = { hidden = true }}, -- Hidden because we use tabbed UI instead

            -- Marker for enabling Text section in generic renderer
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyTooltipStyling,
    })

    self:RegisterComponent(tooltipComponent)
end)
