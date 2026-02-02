local addonName, addon = ...

-- Tooltip Component: Manages GameTooltip text styling
-- The GameTooltip creates FontStrings dynamically on BOTH sides of each line:
-- - GameTooltipTextLeft1, GameTooltipTextLeft2, etc. (left side)
-- - GameTooltipTextRight1, GameTooltipTextRight2, etc. (right side)
-- TextLeft1/TextRight1 use GameTooltipHeaderText, others use GameTooltipText by default.
--
-- Right-side text is used for sell prices, armor types, weapon speeds, spell ranges/cooldowns, etc.
--
-- Money displays (sell prices) use MoneyFrames with special structure:
-- - GameTooltipMoneyFrame1, GameTooltipMoneyFrame2, etc.
-- - Each has PrefixText ("Sell Price:"), GoldButton.Text, SilverButton.Text, CopperButton.Text
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

local COMPARISON_TOOLTIP_NAMES = {
    ShoppingTooltip1 = true,
    ShoppingTooltip2 = true,
    ItemRefShoppingTooltip1 = true,
    ItemRefShoppingTooltip2 = true,
}

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

local function CleanupTextConfig(cfg)
    if not cfg then return end
    cfg.color = nil
    cfg.offset = nil
    cfg.alignment = nil -- Removed feature - see TOOLTIPGAME.md
end

local function ShallowCopyFontConfig(src)
    src = src or {}
    return {
        fontFace = src.fontFace,
        size = src.size,
        style = src.style,
    }
end

local function EnsureNewTooltipTextConfigs(db)
    if not db then return end

    -- Migration: use old Line 2 settings as the initial value for Everything Else.
    if db.textEverythingElse == nil then
        db.textEverythingElse = ShallowCopyFontConfig(db.textLine2 or {
            fontFace = "FRIZQT__",
            size = 12,
            style = "OUTLINE",
        })
    end

    if db.textComparison == nil then
        db.textComparison = {
            fontFace = "FRIZQT__",
            size = 12,
            style = "OUTLINE",
        }
    end

    CleanupTextConfig(db.textTitle)
    CleanupTextConfig(db.textEverythingElse)
    CleanupTextConfig(db.textComparison)
end

local function ApplyGameTooltipText(db)
    -- Title / name line (Left1 and Right1 both use title settings)
    local titleFS = _G["GameTooltipTextLeft1"]
    if titleFS then
        ApplyFontSettings(titleFS, db.textTitle or {}, 14)
    end
    local titleRightFS = _G["GameTooltipTextRight1"]
    if titleRightFS then
        ApplyFontSettings(titleRightFS, db.textTitle or {}, 14)
    end

    -- Everything else: lines 2..N (both Left and Right)
    local cfg = db.textEverythingElse or {}
    local i = 2
    while true do
        local leftFS = _G["GameTooltipTextLeft" .. i]
        local rightFS = _G["GameTooltipTextRight" .. i]
        if not leftFS and not rightFS then break end
        
        if leftFS then
            ApplyFontSettings(leftFS, cfg, 12)
        end
        if rightFS then
            ApplyFontSettings(rightFS, cfg, 12)
        end
        i = i + 1
    end

    -- Money frames: Sell Price and similar money displays
    -- GameTooltip can have multiple money frames (GameTooltipMoneyFrame1, GameTooltipMoneyFrame2, etc.)
    local moneyIdx = 1
    while true do
        local moneyFrame = _G["GameTooltipMoneyFrame" .. moneyIdx]
        if not moneyFrame then break end
        
        -- Style the "Sell Price:" prefix text
        local prefixText = moneyFrame.PrefixText or _G["GameTooltipMoneyFrame" .. moneyIdx .. "PrefixText"]
        if prefixText then
            ApplyFontSettings(prefixText, cfg, 12)
        end
        
        -- Style the gold/silver/copper text (they're ButtonText elements on the denomination buttons)
        if moneyFrame.GoldButton and moneyFrame.GoldButton.Text then
            ApplyFontSettings(moneyFrame.GoldButton.Text, cfg, 12)
        end
        if moneyFrame.SilverButton and moneyFrame.SilverButton.Text then
            ApplyFontSettings(moneyFrame.SilverButton.Text, cfg, 12)
        end
        if moneyFrame.CopperButton and moneyFrame.CopperButton.Text then
            ApplyFontSettings(moneyFrame.CopperButton.Text, cfg, 12)
        end
        
        moneyIdx = moneyIdx + 1
    end
end

local function ApplyComparisonTooltipText(tooltip, db)
    if not tooltip or not tooltip.GetName then return end
    local prefix = tooltip:GetName()
    if not prefix or prefix == "" then return end

    -- Line 1 uses Title settings, lines 2+ use Comparison settings
    local titleCfg = db.textTitle or {}
    local comparisonCfg = db.textComparison or {}
    
    local i = 1
    while true do
        local leftFS = _G[prefix .. "TextLeft" .. i]
        local rightFS = _G[prefix .. "TextRight" .. i]
        if not leftFS and not rightFS then break end
        
        -- Use Title settings for line 1, Comparison settings for everything else
        local cfg = (i == 1) and titleCfg or comparisonCfg
        local defaultSize = (i == 1) and 14 or 12
        
        if leftFS then
            ApplyFontSettings(leftFS, cfg, defaultSize)
        end
        if rightFS then
            ApplyFontSettings(rightFS, cfg, defaultSize)
        end
        i = i + 1
    end

    -- Money frames on comparison tooltips (e.g., ShoppingTooltip1MoneyFrame1)
    local moneyIdx = 1
    while true do
        local moneyFrame = _G[prefix .. "MoneyFrame" .. moneyIdx]
        if not moneyFrame then break end
        
        -- Style the prefix text (e.g., "Sell Price:")
        local prefixText = moneyFrame.PrefixText or _G[prefix .. "MoneyFrame" .. moneyIdx .. "PrefixText"]
        if prefixText then
            ApplyFontSettings(prefixText, comparisonCfg, 12)
        end
        
        -- Style the gold/silver/copper text
        if moneyFrame.GoldButton and moneyFrame.GoldButton.Text then
            ApplyFontSettings(moneyFrame.GoldButton.Text, comparisonCfg, 12)
        end
        if moneyFrame.SilverButton and moneyFrame.SilverButton.Text then
            ApplyFontSettings(moneyFrame.SilverButton.Text, comparisonCfg, 12)
        end
        if moneyFrame.CopperButton and moneyFrame.CopperButton.Text then
            ApplyFontSettings(moneyFrame.CopperButton.Text, comparisonCfg, 12)
        end
        
        moneyIdx = moneyIdx + 1
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
        local comp = addon.Components and addon.Components.tooltip
        if not comp or not comp.db then return end

        local db = comp.db
        EnsureNewTooltipTextConfigs(db)

        local tooltipName = tooltip and tooltip.GetName and tooltip:GetName()

        if tooltip == GameTooltip then
            ApplyGameTooltipText(db)

            -- Apply class color to player names if enabled
            if db.classColorPlayerNames then
                -- GetUnit() and UnitIsPlayer() can return/receive secret values in 12.0
                -- Wrap everything in pcall to handle secrets safely
                local ok, _, unitToken = pcall(tooltip.GetUnit, tooltip)
                if ok and unitToken then
                    local isPlayerOk, isPlayer = pcall(UnitIsPlayer, unitToken)
                    if isPlayerOk and isPlayer then
                        local classOk, _, classToken = pcall(UnitClass, unitToken)
                        if classOk and classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                            local classColor = RAID_CLASS_COLORS[classToken]
                            local titleFS = _G["GameTooltipTextLeft1"]
                            if titleFS and titleFS.SetTextColor then
                                pcall(titleFS.SetTextColor, titleFS, classColor.r, classColor.g, classColor.b, 1)
                            end
                        end
                    end
                end
            end
        elseif tooltipName and COMPARISON_TOOLTIP_NAMES[tooltipName] then
            ApplyComparisonTooltipText(tooltip, db)
        else
            return
        end

        -- Hide health bar if setting is enabled (must be done on every tooltip show)
        if tooltip == GameTooltip and db.hideHealthBar then
            local statusBar = _G["GameTooltipStatusBar"]
            if statusBar then statusBar:Hide() end
            local statusBarTexture = _G["GameTooltipStatusBarTexture"]
            if statusBarTexture then statusBarTexture:Hide() end
        end
    end)

    return true
end

local function ApplyTooltipStyling(self)
    local tooltip = _G["GameTooltip"]
    if not tooltip then return end

    local db = self.db or {}

    EnsureNewTooltipTextConfigs(db)

    -- Ensure TooltipDataProcessor hook is registered
    RegisterTooltipPostProcessor()

    -- Apply styling to any already-built tooltip lines
    ApplyGameTooltipText(db)
    ApplyComparisonTooltipText(_G["ShoppingTooltip1"], db)
    ApplyComparisonTooltipText(_G["ShoppingTooltip2"], db)
    ApplyComparisonTooltipText(_G["ItemRefShoppingTooltip1"], db)
    ApplyComparisonTooltipText(_G["ItemRefShoppingTooltip2"], db)

    -- Apply visibility settings: Hide/Show GameTooltipStatusBar (health bar)
    local statusBar = _G["GameTooltipStatusBar"]
    if statusBar then
        if db.hideHealthBar then
            statusBar:Hide()
        else
            statusBar:Show()
        end
    end
    -- Also hide/show the status bar texture (child element)
    local statusBarTexture = _G["GameTooltipStatusBarTexture"]
    if statusBarTexture then
        if db.hideHealthBar then
            statusBarTexture:Hide()
        else
            statusBarTexture:Show()
        end
    end

    -- Apply tooltip scale
    local scale = db.tooltipScale or 1.0
    if tooltip.SetScale then
        tooltip:SetScale(scale)
    end
    -- Also scale comparison tooltips
    for tooltipName in pairs(COMPARISON_TOOLTIP_NAMES) do
        local compTooltip = _G[tooltipName]
        if compTooltip and compTooltip.SetScale then
            compTooltip:SetScale(scale)
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
            -- Name & Title settings (line 1 on GameTooltip)
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 14,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Everything Else settings (lines 2..N on GameTooltip)
            textEverythingElse = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Comparison Tooltips settings (ShoppingTooltip1/2 + ItemRefShoppingTooltip1/2)
            textComparison = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Visibility settings
            hideHealthBar = { type = "addon", default = false, ui = {
                label = "Hide Tooltip Health Bar", widget = "checkbox", section = "Visibility", order = 1
            }},

            -- Class color settings
            classColorPlayerNames = { type = "addon", default = false },

            -- Tooltip scale setting
            tooltipScale = { type = "addon", default = 1.0 },

            -- Marker for enabling Text section in generic renderer
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyTooltipStyling,
    })

    self:RegisterComponent(tooltipComponent)
end)
