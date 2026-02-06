local addonName, addon = ...

--------------------------------------------------------------------------------
-- Icon Ratio Utility
--------------------------------------------------------------------------------
-- Provides centralized ratio-based icon dimension calculations for all
-- icon-based components (CDM, Auras, UF Buffs/Debuffs).
--
-- The tallWideRatio slider ranges from -67 to +67:
--   - Center (0): Square icons (1:1)
--   - Far Left (-67): Icons 3x wider than tall (height = baseSize * 0.33)
--   - Far Right (+67): Icons 3x taller than wide (width = baseSize * 0.33)
--------------------------------------------------------------------------------

addon.IconRatio = addon.IconRatio or {}
local IconRatio = addon.IconRatio

-- Base sizes for each component (used when ratio = 0 for square icons)
IconRatio.BASE_SIZES = {
    essentialCooldowns = 50,
    utilityCooldowns = 30,
    trackedBuffs = 40,
    trackedBars = 30,
    buffs = 30,
    debuffs = 30,
    -- Unit Frame buffs/debuffs use the same base as player buffs
    targetBuffsDebuffs = 30,
    focusBuffsDebuffs = 30,
}

--- Calculate icon dimensions based on base size and ratio
-- @param baseSize number - The base size in pixels (used for the "long" dimension)
-- @param ratio number - The tall/wide ratio (-67 to +67)
-- @return width number, height number - The calculated dimensions
function IconRatio.CalculateDimensions(baseSize, ratio)
    baseSize = tonumber(baseSize) or 30
    ratio = tonumber(ratio) or 0

    -- Clamp ratio to valid range
    if ratio < -67 then ratio = -67 end
    if ratio > 67 then ratio = 67 end

    if ratio == 0 then
        -- Square icons
        return baseSize, baseSize
    elseif ratio < 0 then
        -- Wide: shrink height (ratio is negative, so add it to reduce)
        -- At -67, heightFactor = 1 + (-67/100) = 0.33
        local heightFactor = 1 + (ratio / 100)
        return baseSize, baseSize * math.max(0.33, heightFactor)
    else
        -- Tall: shrink width (ratio is positive, so subtract it to reduce)
        -- At +67, widthFactor = 1 - (67/100) = 0.33
        local widthFactor = 1 - (ratio / 100)
        return baseSize * math.max(0.33, widthFactor), baseSize
    end
end

--- Get dimensions for a specific component
-- @param componentId string - The component identifier
-- @param ratio number - The tall/wide ratio (-67 to +67)
-- @param customBaseSize number|nil - Optional override for base size
-- @return width number, height number - The calculated dimensions
function IconRatio.GetDimensionsForComponent(componentId, ratio, customBaseSize)
    local baseSize = customBaseSize or IconRatio.BASE_SIZES[componentId] or 30
    return IconRatio.CalculateDimensions(baseSize, ratio)
end

--- Convert legacy iconWidth/iconHeight to approximate tallWideRatio
-- Used for migrating existing saved variables
-- @param width number - The legacy icon width
-- @param height number - The legacy icon height
-- @param defaultSize number - The default base size for the component
-- @return ratio number - The approximate ratio value (-67 to +67)
function IconRatio.MigrateFromWidthHeight(width, height, defaultSize)
    width = tonumber(width)
    height = tonumber(height)
    defaultSize = tonumber(defaultSize) or 30

    if not width or not height then
        return 0
    end

    -- If both match default, it's square
    if width == defaultSize and height == defaultSize then
        return 0
    end

    -- If width == height, it's square (even if different from default)
    if width == height then
        return 0
    end

    -- Determine the aspect ratio
    local aspectRatio = width / height

    if aspectRatio > 1 then
        -- Wider than tall: negative ratio
        -- aspectRatio = baseSize / (baseSize * heightFactor) = 1 / heightFactor
        -- heightFactor = 1 / aspectRatio
        -- ratio = (heightFactor - 1) * 100
        local heightFactor = 1 / aspectRatio
        local ratio = (heightFactor - 1) * 100
        return math.max(-67, math.min(0, math.floor(ratio + 0.5)))
    else
        -- Taller than wide: positive ratio
        -- aspectRatio = (baseSize * widthFactor) / baseSize = widthFactor
        -- ratio = (1 - widthFactor) * 100
        local widthFactor = aspectRatio
        local ratio = (1 - widthFactor) * 100
        return math.max(0, math.min(67, math.floor(ratio + 0.5)))
    end
end

return IconRatio
