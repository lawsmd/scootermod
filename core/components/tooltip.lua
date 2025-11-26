local addonName, addon = ...

-- Tooltip Component: Manages GameTooltip text styling
-- The GameTooltip creates FontStrings dynamically: GameTooltipTextLeft1, GameTooltipTextLeft2, etc.
-- TextLeft1 is typically the "title/name" line and uses GameTooltipHeaderText by default.
--
-- NOTE: We intentionally do NOT customize:
-- - Color: Tooltip text is dynamically colored by the game (item quality, spell schools, etc.)
-- - Position: Tooltip layout is static and repositioning text would break the layout
-- - Alignment: See TOOLTIPGAME.md - alignment requires width expansion which causes infinite
--   growth on spell/ability tooltips that update continuously for cooldowns/charges.
--
-- SUPPORTED CUSTOMIZATIONS:
-- - Font face (family)
-- - Font size
-- - Font style (OUTLINE, THICKOUTLINE, etc.)

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

        -- Apply settings for lines 1 through 7
        for i = 1, 7 do
            local fontString = _G["GameTooltipTextLeft"..i]
            if fontString then
                -- DB keys: textTitle (line 1), textLine2 (line 2), etc.
                local key = (i == 1) and "textTitle" or ("textLine"..i)
                local cfg = comp.db[key] or {}
                
                -- Apply font settings synchronously
                -- Line 1 defaults to 14pt, others default to 12pt (standard body size)
                ApplyFontSettings(fontString, cfg, (i == 1) and 14 or 12)
            end
        end
    end)

    return true
end

local function ApplyTooltipStyling(self)
    local tooltip = _G["GameTooltip"]
    if not tooltip then return end

    local db = self.db or {}

    -- Clean up deprecated settings
    if db.textTitle then
        db.textTitle.color = nil
        db.textTitle.offset = nil
        db.textTitle.alignment = nil -- Removed feature - see TOOLTIPGAME.md
    end

    -- Ensure TooltipDataProcessor hook is registered
    RegisterTooltipPostProcessor()

    -- Apply styling to existing lines (GameTooltipTextLeft1..7)
    for i = 1, 7 do
        local fontString = _G["GameTooltipTextLeft"..i]
        if fontString then
            local key = (i == 1) and "textTitle" or ("textLine"..i)
            local cfg = db[key] or {}
            ApplyFontSettings(fontString, cfg, (i == 1) and 14 or 12)
        end
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local tooltipComponent = Component:New({
        id = "tooltip",
        name = "Tooltip",
        frameName = "GameTooltip",
        settings = {
            -- Line 1 (Title) settings
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 14,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Line 2 settings
            textLine2 = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Line 3 settings
            textLine3 = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Line 4 settings
            textLine4 = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Line 5 settings
            textLine5 = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Line 6 settings
            textLine6 = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Line 7 settings
            textLine7 = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Marker for enabling Text section in generic renderer
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyTooltipStyling,
    })

    self:RegisterComponent(tooltipComponent)
end)
