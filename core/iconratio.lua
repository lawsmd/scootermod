-- iconratio.lua - Icon dimension calculations
local addonName, addon = ...
-- tallWideRatio slider: -67 (3x wide) to 0 (square) to +67 (3x tall).

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
    -- Action Bars
    actionBar = 45,
    petBar = 30,
    stanceBar = 30,
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

return IconRatio
