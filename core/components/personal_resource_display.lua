local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil or {}

local pendingCombatComponents = {}
local combatWatcherFrame

local function ensureCombatWatcher()
    if combatWatcherFrame or not CreateFrame then
        return
    end
    combatWatcherFrame = CreateFrame("Frame")
    combatWatcherFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatcherFrame:SetScript("OnEvent", function()
        for component in pairs(pendingCombatComponents) do
            pendingCombatComponents[component] = nil
            component._awaitingCombatEnd = nil
            if component.ApplyStyling then
                component:ApplyStyling()
            end
        end
    end)
end

local function isRestricted()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return true
    end
    return false
end

local function queueAfterCombat(component)
    if not component then
        return
    end
    if component._awaitingCombatEnd then
        pendingCombatComponents[component] = true
        return
    end
    component._awaitingCombatEnd = true
    ensureCombatWatcher()
    pendingCombatComponents[component] = true
end

local function getPlayerPlate()
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        return nil
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "player", issecure and issecure())
    if not ok then
        plate = nil
    end
    if plate and plate.IsForbidden and plate:IsForbidden() then
        return nil
    end
    return plate
end

-- Track the last nameplate we applied PRD styling to, so we can clean up
-- when WoW recycles that nameplate frame to a different unit.
local lastStyledPRDPlate = nil

-- Remove PRD styling from a nameplate that is no longer the player's PRD.
-- This handles the case where WoW recycles a nameplate frame from the player
-- to an enemy unit - without cleanup, the enemy would inherit our styling.
local function cleanupOldPRDStyling(oldPlate)
    if not oldPlate then
        return
    end

    local uf = oldPlate.UnitFrame
    if not uf then
        return
    end

    local container = uf.HealthBarsContainer
    if not container then
        return
    end

    local healthBar = container.healthBar or container.HealthBar
    if healthBar then
        -- Remove ScooterModBG
        if healthBar.ScooterModBG then
            pcall(healthBar.ScooterModBG.Hide, healthBar.ScooterModBG)
            pcall(healthBar.ScooterModBG.SetAlpha, healthBar.ScooterModBG, 0)
        end
        -- Remove borders
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            pcall(addon.BarBorders.ClearBarFrame, healthBar)
        end
        if addon.Borders and addon.Borders.HideAll then
            pcall(addon.Borders.HideAll, healthBar)
        end
        -- Clear stored alpha values so they don't persist
        healthBar._ScooterPRDHealthAlpha = nil
    end

    -- Also clean container-level styling
    container._ScooterPRDHealthAlpha = nil
    container._ScooterModBaseWidth = nil
    container._ScooterModBaseHeight = nil
    container._ScooterModWidthDelta = nil
end

-- Check if the player's PRD has moved to a different nameplate frame,
-- and clean up the old one if so. This prevents styling from leaking
-- to enemy nameplates when WoW recycles nameplate frames.
local function ensurePRDCleanup()
    local currentPlayerPlate = getPlayerPlate()

    -- If we previously styled a different plate, clean it up
    if lastStyledPRDPlate and lastStyledPRDPlate ~= currentPlayerPlate then
        cleanupOldPRDStyling(lastStyledPRDPlate)
    end

    -- Update tracking
    lastStyledPRDPlate = currentPlayerPlate

    return currentPlayerPlate
end

-- PRD re-application via events.
--
-- CRITICAL: We cannot use hooksecurefunc on any nameplate-related functions because
-- hook callbacks that run during Blizzard's nameplate setup chain taint the execution
-- context, causing SetTargetClampingInsets() to be blocked.
--
-- Instead, we use EVENT HANDLERS to re-apply styling. Events fire in separate execution
-- contexts and don't cause taint. We use:
-- - NAME_PLATE_UNIT_ADDED: Fires when a nameplate appears (after setup completes)
-- - PLAYER_TARGET_CHANGED: PRD may move when targeting changes
-- - PLAYER_REGEN_DISABLED/ENABLED: PRD visibility often changes with combat state
--
-- We use C_Timer.After(0, ...) to defer styling to the next frame, ensuring we're
-- completely outside any Blizzard execution chain.

local prdEventFrame = nil
local prdRegisteredComponents = {}

local function scheduleComponentApply(component)
    if not component or not component.ApplyStyling then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if component and component.ApplyStyling then
                component:ApplyStyling()
            end
        end)
    end
end

local function onPRDEvent(self, event, ...)
    -- Defer all styling to next frame to ensure we're outside any execution chain
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            for component, _ in pairs(prdRegisteredComponents) do
                if component and component.ApplyStyling then
                    component:ApplyStyling()
                end
            end
        end)
    end
end

local function ensureEventFrame()
    if prdEventFrame then
        return prdEventFrame
    end
    
    prdEventFrame = CreateFrame("Frame")
    prdEventFrame:SetScript("OnEvent", onPRDEvent)
    
    -- Register events that indicate PRD state may have changed
    -- These fire AFTER Blizzard's nameplate setup completes
    prdEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    prdEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    prdEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    prdEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    prdEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    prdEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    prdEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    return prdEventFrame
end

local function ensureHooks(component)
    -- Register component for event-based re-application
    if component._hooksInstalled then
        return
    end
    component._hooksInstalled = true
    
    -- Set up the event frame (shared across all PRD components)
    ensureEventFrame()
    
    -- Register this component for event-driven updates
    prdRegisteredComponents[component] = true
end

local MAX_OFFSET = 500
local MIN_HEALTH_BAR_WIDTH = 60
local MAX_HEALTH_BAR_WIDTH = 600
local MIN_HEALTH_BAR_HEIGHT = 4
local MAX_HEALTH_BAR_HEIGHT = 60
local MIN_POWER_BAR_WIDTH = 40
local MAX_POWER_BAR_WIDTH = 600
local MIN_POWER_BAR_HEIGHT = 4
local MAX_POWER_BAR_HEIGHT = 40
local MIN_CLASS_RESOURCE_SCALE_PERCENT = 50
local MAX_CLASS_RESOURCE_SCALE_PERCENT = 150

-- Capture default CVar values to restore them if Static Mode is disabled
local defaultTopInset = (GetCVarDefault and GetCVarDefault("nameplateSelfTopInset")) or 0.5
local defaultBottomInset = (GetCVarDefault and GetCVarDefault("nameplateSelfBottomInset")) or 0.2


-- Power Bar height management.
--
-- CRITICAL: We no longer hook OnSizeChanged or any other nameplate-related methods.
--
-- The problem: ANY hooksecurefunc callback that runs during Blizzard's nameplate setup
-- chain (including OnSizeChanged which fires when SetShown() is called) will taint the
-- execution context, causing SetTargetClampingInsets() to be blocked.
--
-- Instead, power bar height is applied directly via SetHeight() in applyPowerOffsets().
-- This height may be reset by Blizzard during spec changes, instance transitions, etc.,
-- but that's preferable to causing taint errors. Users can re-apply via settings or /reload.
--
-- NOTE: Width control was removed entirely because Blizzard's SetupClassNameplateBars()
-- continuously re-applies TOPLEFT+TOPRIGHT anchors which control width via the layout system.
-- Power bar width now automatically follows the health bar width.

local function ensurePowerBarHooks(component)
    -- INTENTIONALLY EMPTY: No hooks are installed to avoid taint.
    -- Height is applied directly in applyPowerOffsets().
    -- See comment block above for explanation.
end

local function clampOffsetValue(value)
    local v = tonumber(value) or 0
    if v < -MAX_OFFSET then
        v = -MAX_OFFSET
    elseif v > MAX_OFFSET then
        v = MAX_OFFSET
    end
    return v
end

local function clampValue(value, minValue, maxValue)
    if minValue and value < minValue then
        value = minValue
    end
    if maxValue and value > maxValue then
        value = maxValue
    end
    return value
end

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copyValue(v)
    end
    return out
end

local function ensureSettingValue(component, key)
    if not component then
        return nil
    end
    local db = component.db
    if db and db[key] ~= nil then
        return db[key]
    end
    local setting = component.settings and component.settings[key]
    if not setting then
        return db and db[key] or nil
    end
    local default = copyValue(setting.default)
    if db and default ~= nil then
        db[key] = copyValue(default)
        return db[key]
    end
    return default
end

local function ensureColorSetting(component, key, fallback)
    local value = ensureSettingValue(component, key)
    local base = fallback or {1, 1, 1, 1}
    if type(value) ~= "table" then
        value = copyValue(base)
    end
    return {
        value[1] or base[1] or 1,
        value[2] or base[2] or 1,
        value[3] or base[3] or 1,
        value[4] or base[4] or 1,
    }
end

local function setSettingValue(component, key, value)
    if not component or not component.db then
        return
    end
    if type(value) == "table" then
        component.db[key] = copyValue(value)
    else
        component.db[key] = value
    end
end

local function clearBarBorder(bar)
    if not bar then
        return
    end
    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
        addon.BarBorders.ClearBarFrame(bar)
    end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(bar)
    end
end

local function storeOriginalAlpha(frame, storageKey)
    if not frame or not frame.GetAlpha then
        return
    end
    storageKey = storageKey or "_ScooterPRDOrigAlpha"
    if frame[storageKey] ~= nil then
        return
    end
    local ok, alpha = pcall(frame.GetAlpha, frame)
    frame[storageKey] = ok and (alpha or 1) or 1
end

local function applyHiddenAlpha(frame, hidden, storageKey)
    if not frame or not frame.SetAlpha then
        return
    end
    storageKey = storageKey or "_ScooterPRDOrigAlpha"
    if hidden then
        storeOriginalAlpha(frame, storageKey)
        pcall(frame.SetAlpha, frame, 0)
    else
        local original = frame[storageKey]
        if original == nil then
            original = 1
        end
        pcall(frame.SetAlpha, frame, original)
    end
end

local function applyPRDStatusBarStyle(component, statusBar, barKind)
    if not component or not statusBar then
        return
    end
    if addon._ApplyToStatusBar then
        local textureKey = ensureSettingValue(component, "styleForegroundTexture") or "default"
        local colorMode = ensureSettingValue(component, "styleForegroundColorMode") or "default"
        local tint = ensureColorSetting(component, "styleForegroundTint", {1, 1, 1, 1})
        addon._ApplyToStatusBar(statusBar, textureKey, colorMode, tint, "player", barKind, "player")
    end
    if addon._ApplyBackgroundToStatusBar then
        local bgTexture = ensureSettingValue(component, "styleBackgroundTexture") or "default"
        local colorMode = ensureSettingValue(component, "styleBackgroundColorMode") or "default"
        local tint = ensureColorSetting(component, "styleBackgroundTint", {0, 0, 0, 1})
        local opacity = ensureSettingValue(component, "styleBackgroundOpacity")
        opacity = tonumber(opacity) or 50
        opacity = clampValue(math.floor(opacity + 0.5), 0, 100)
        setSettingValue(component, "styleBackgroundOpacity", opacity)
        addon._ApplyBackgroundToStatusBar(statusBar, bgTexture, colorMode, tint, opacity, "player", barKind)
    end
end

local function applyPRDBarBorder(component, statusBar)
    if not component or not statusBar then
        return
    end
    local db = component.db or {}
    local styleKey = db.borderStyle or "square"
    if styleKey == "none" then
        clearBarBorder(statusBar)
        return
    end
    local tintEnabled = db.borderTintEnable and true or false
    local tintColor = ensureColorSetting(component, "borderTintColor", {1, 1, 1, 1})
    local thickness = tonumber(db.borderThickness) or 1
    thickness = clampValue(math.floor(thickness + 0.5), 1, 16)
    local inset = tonumber(db.borderInset) or 0
    inset = clampValue(math.floor(inset + 0.5), -4, 4)
    setSettingValue(component, "borderThickness", thickness)
    setSettingValue(component, "borderInset", inset)
    local color
    if tintEnabled then
        color = tintColor
    else
        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        if styleDef then
            color = {1, 1, 1, 1}
        else
            color = {0, 0, 0, 1}
        end
    end
    if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
        if addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(statusBar)
        end
        local handled = addon.BarBorders.ApplyToBarFrame(statusBar, styleKey, {
            color = color,
            thickness = thickness,
            levelOffset = 1,
            inset = inset,
        })
        if handled then
            -- Hide any old square border that may have been applied previously
            if addon.Borders and addon.Borders.HideAll then
                addon.Borders.HideAll(statusBar)
            end
            return
        end
    end
    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
        addon.BarBorders.ClearBarFrame(statusBar)
    end
    if addon.Borders and addon.Borders.ApplySquare then
        local fallbackColor = tintEnabled and tintColor or {0, 0, 0, 1}
        local baseY = (thickness <= 1) and 0 or 1
        local baseX = 1
        local expandY = baseY - inset
        local expandX = baseX - inset
        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
        addon.Borders.ApplySquare(statusBar, {
            size = thickness,
            color = fallbackColor,
            layer = "OVERLAY",
            layerSublevel = 3,
            expandX = expandX,
            expandY = expandY,
        })
    end
end

local function applyPRDHealthVisuals(component, container)
    if not component or not container then
        return
    end
    local statusBar = container.healthBar or container.HealthBar
    if not statusBar then
        return
    end
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    applyHiddenAlpha(container, hide, "_ScooterPRDHealthAlpha")
    applyHiddenAlpha(statusBar, hide, "_ScooterPRDHealthAlpha")
    if statusBar.ScooterModBG then
        applyHiddenAlpha(statusBar.ScooterModBG, hide, "_ScooterPRDHealthAlpha")
    end
    if hide then
        clearBarBorder(statusBar)
        return
    end
    applyPRDStatusBarStyle(component, statusBar, "health")
    applyPRDBarBorder(component, statusBar)
end

local function applyPRDPowerVisuals(component, frame)
    if not component or not frame then
        return
    end
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    applyHiddenAlpha(frame, hide, "_ScooterPRDPowerAlpha")
    if frame.ScooterModBG then
        applyHiddenAlpha(frame.ScooterModBG, hide, "_ScooterPRDPowerAlpha")
    end
    if hide then
        clearBarBorder(frame)
        return
    end
    applyPRDStatusBarStyle(component, frame, "power")
    applyPRDBarBorder(component, frame)
end

local function applyPRDClassResourceVisibility(component, frame)
    if not component or not frame then
        return
    end
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    applyHiddenAlpha(frame, hide, "_ScooterPRDClassResourceAlpha")
end

local function applyScaleToFrame(frame, multiplier, component)
    if not frame or type(multiplier) ~= "number" or multiplier <= 0 then
        return
    end
    if not frame.SetScale then
        return
    end

    if not frame._ScooterModBaseScale then
        local base = 1
        if frame.GetScale then
            local ok, existing = pcall(frame.GetScale, frame)
            if ok and existing then
                base = existing
            end
        end
        frame._ScooterModBaseScale = base or 1
    end

    local baseScale = frame._ScooterModBaseScale or 1
    local desired = baseScale * multiplier

    local current
    if frame.GetScale then
        local ok, existing = pcall(frame.GetScale, frame)
        if ok and existing then
            current = existing
        end
    end
    if current and math.abs(current - desired) < 0.0001 then
        return
    end

    local ok = pcall(frame.SetScale, frame, desired)
    if not ok then
        queueAfterCombat(component)
    end
end

local function getGlobalComponent()
    if not addon or not addon.Components then
        return nil
    end
    return addon.Components.prdGlobal
end

local function resolveGlobalOffsets()
    local component = getGlobalComponent()
    if not component then
        return 0, 0
    end

    local db = component.db or {}
    local settings = component.settings or {}

    local function readAndClamp(key)
        local value = db[key]
        if value == nil and settings[key] then
            value = settings[key].default
        end
        value = clampOffsetValue(value or 0)
        if component.db then
            component.db[key] = value
        end
        return value
    end

    local x = readAndClamp("positionX")
    local y = readAndClamp("positionY")
    return x, y
end

local function resolveGlobalScaleMultiplier()
    local component = getGlobalComponent()
    if component and component.db then
        component.db.scale = 100
    end
    return 1
end

local function resolveClassResourceScale(component)
    if not component then
        return 1
    end
    local settings = component.settings or {}
    local defaultPercent = (settings.scale and settings.scale.default) or 100
    local value = component.db and component.db.scale
    if value == nil then
        value = defaultPercent
    end
    value = tonumber(value) or defaultPercent
    value = clampValue(math.floor(value + 0.5), MIN_CLASS_RESOURCE_SCALE_PERCENT, MAX_CLASS_RESOURCE_SCALE_PERCENT)
    if component.db then
        component.db.scale = value
    end
    return value / 100
end

local function getComponentOffsets(componentId)
    if componentId == "prdHealth" or componentId == "prdPower" or componentId == "prdClassResource" then
        return 0, 0
    end
    if not addon or not addon.Components then
        return 0, 0
    end
    local component = addon.Components[componentId]
    local db = component and component.db
    if not db then
        return 0, 0
    end
    local x = db.positionX
    if x == nil and db.offsetX ~= nil then
        x = db.offsetX
    end
    local y = db.positionY
    if y == nil and db.offsetY ~= nil then
        y = db.offsetY
    end
    return clampOffsetValue(x or 0), clampOffsetValue(y or 0)
end

local function getHealthContainer()
    local plate = getPlayerPlate()
    if not plate or not plate.UnitFrame then
        return nil
    end
    local container = plate.UnitFrame.HealthBarsContainer
    if not container or (container.IsForbidden and container:IsForbidden()) then
        return nil
    end
    return container
end

local function getAggregateOffsetsForFrame(frame)
    if not frame then
        return 0, 0
    end

    local globalX, globalY = resolveGlobalOffsets()
    local hx, hy = getComponentOffsets("prdHealth")
    local px, py = getComponentOffsets("prdPower")

    local container = getHealthContainer()
    if container and frame == container then
        return hx + globalX, hy + globalY
    end

    local powerFrame = NamePlateDriverFrame and NamePlateDriverFrame.GetClassNameplateManaBar and NamePlateDriverFrame:GetClassNameplateManaBar()
    if powerFrame and frame == powerFrame then
        return px + globalX, py + globalY
    end

    local altFrame = NamePlateDriverFrame and NamePlateDriverFrame.GetClassNameplateAlternatePowerBar and NamePlateDriverFrame:GetClassNameplateAlternatePowerBar()
    if altFrame and frame == altFrame then
        local point, relativeTo = altFrame:GetPoint(1)
        if relativeTo == powerFrame then
            return px + globalX, py + globalY
        elseif relativeTo == container then
            return hx + globalX, hy + globalY
        end
        return 0, 0
    end

    return 0, 0
end

local function applyHealthOffsets(component)
    -- Clean up any old PRD styling before applying to current plate
    local plate = ensurePRDCleanup()
    if not plate or not plate.UnitFrame then
        return
    end

    local container = plate.UnitFrame.HealthBarsContainer
    if not container or (container.IsForbidden and container:IsForbidden()) then
        return
    end

    local unitFrame = plate.UnitFrame
    if unitFrame then
        unitFrame.customOptions = unitFrame.customOptions or {}
        unitFrame.customOptions.ignoreBarPoints = true
    end
    local offsetX, offsetY = resolveGlobalOffsets()
    local scaleMultiplier = resolveGlobalScaleMultiplier()

    local function safeCall(func, ...)
        local ok = pcall(func, ...)
        if not ok then
            queueAfterCombat(component)
        end
        return ok
    end

    if not safeCall(container.ClearAllPoints, container) then
        return
    end

    local baseLeft, baseRight, baseY = 12, -12, 5
    local baseWidth = container._ScooterModBaseWidth
    if not baseWidth or baseWidth <= 0 then
        baseWidth = (container.GetWidth and container:GetWidth()) or 0
        if (not baseWidth or baseWidth <= 0) and plate.UnitFrame and plate.UnitFrame.GetWidth then
            local parentWidth = plate.UnitFrame:GetWidth()
            if parentWidth and parentWidth > 0 then
                baseWidth = parentWidth - (baseLeft - baseRight)
            end
        end
        if not baseWidth or baseWidth <= 0 then
            baseWidth = 200
        end
        container._ScooterModBaseWidth = baseWidth
    end

    if component.settings and component.settings.barWidth then
        local defaultWidth = math.floor(baseWidth + 0.5)
        if component.settings.barWidth.default ~= defaultWidth then
            component.settings.barWidth.default = defaultWidth
        end
    end

    local storedWidth = component.db and component.db.barWidth
    if not storedWidth or storedWidth < MIN_HEALTH_BAR_WIDTH then
        storedWidth = component.settings and component.settings.barWidth and component.settings.barWidth.default or baseWidth
    end
    storedWidth = clampValue(math.floor((storedWidth or baseWidth) + 0.5), MIN_HEALTH_BAR_WIDTH, MAX_HEALTH_BAR_WIDTH)
    if component.db then
        component.db.barWidth = storedWidth
    end
    local widthBase = storedWidth

    local baseHeight = container._ScooterModBaseHeight
    if not baseHeight or baseHeight <= 0 then
        baseHeight = (container.GetHeight and container:GetHeight()) or 0
        if not baseHeight or baseHeight <= 0 then
            baseHeight = 12
        end
        container._ScooterModBaseHeight = baseHeight
    end

    if component.settings and component.settings.barHeight then
        local defaultHeight = math.floor(baseHeight + 0.5)
        if component.settings.barHeight.default ~= defaultHeight then
            component.settings.barHeight.default = defaultHeight
        end
    end

    local storedHeight = component.db and component.db.barHeight
    if not storedHeight or storedHeight < MIN_HEALTH_BAR_HEIGHT then
        storedHeight = component.settings and component.settings.barHeight and component.settings.barHeight.default or baseHeight
    end
    storedHeight = clampValue(math.floor((storedHeight or baseHeight) + 0.5), MIN_HEALTH_BAR_HEIGHT, MAX_HEALTH_BAR_HEIGHT)
    if component.db then
        component.db.barHeight = storedHeight
    end
    local heightBase = storedHeight

    local desiredWidth = clampValue(widthBase, MIN_HEALTH_BAR_WIDTH, MAX_HEALTH_BAR_WIDTH)
    local desiredHeight = clampValue(heightBase, MIN_HEALTH_BAR_HEIGHT, MAX_HEALTH_BAR_HEIGHT)

    local widthDelta = (desiredWidth - baseWidth) * 0.5
    local leftOffset = (baseLeft + offsetX) - widthDelta
    local rightOffset = (baseRight + offsetX) + widthDelta
    container._ScooterModWidthDelta = widthDelta
    local setter = PixelUtil and PixelUtil.SetPoint
    if setter then
        if not safeCall(setter, container, "LEFT", plate.UnitFrame, "LEFT", leftOffset, baseY + offsetY) then
            return
        end
        if not safeCall(setter, container, "RIGHT", plate.UnitFrame, "RIGHT", rightOffset, baseY + offsetY) then
            return
        end
    else
        if not safeCall(container.SetPoint, container, "LEFT", plate.UnitFrame, "LEFT", leftOffset, baseY + offsetY) then
            return
        end
        if not safeCall(container.SetPoint, container, "RIGHT", plate.UnitFrame, "RIGHT", rightOffset, baseY + offsetY) then
            return
        end
    end

    safeCall(container.SetHeight, container, desiredHeight)

    local statusBar = container.healthBar or container.HealthBar
    if statusBar then
        if statusBar.SetHeight then
            safeCall(statusBar.SetHeight, statusBar, desiredHeight)
        end
        if statusBar.SetAllPoints then
            safeCall(statusBar.SetAllPoints, statusBar, container)
        end
    end

    local mask = container.healthBarMask or container.HealthBarMask or container.mask or container.Mask
    if mask and mask.SetAllPoints then
        safeCall(mask.SetAllPoints, mask, container)
    end

    local background = container.background or container.Background
    if background and background.SetAllPoints then
        safeCall(background.SetAllPoints, background, container)
    end

    applyScaleToFrame(container, scaleMultiplier, component)
    applyPRDHealthVisuals(component, container)
end

local function applyPowerOffsets(component)
    local plate = getPlayerPlate()
    if not plate or not plate.UnitFrame then
        return
    end

    local container = plate.UnitFrame.HealthBarsContainer
    if not container or (container.IsForbidden and container:IsForbidden()) then
        return
    end

    local frame = _G.ClassNameplateManaBarFrame or (NamePlateDriverFrame and NamePlateDriverFrame.classNamePlatePowerBar)
    if not frame then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    local scaleMultiplier = resolveGlobalScaleMultiplier()

    local function safeCall(func, ...)
        local ok = pcall(func, ...)
        if not ok then
            queueAfterCombat(component)
        end
        return ok
    end

    -- NOTE: We intentionally do NOT manage anchors or width for the power bar.
    -- Blizzard's SetupClassNameplateBars() continuously re-applies TOPLEFT+TOPRIGHT anchors
    -- which control width via the anchor system. Fighting this causes visible flickering.
    -- Width now follows the health bar automatically via Blizzard's anchoring.

    -- Clear any stored barWidth from old profiles to ensure clean state
    if component.db and component.db.barWidth then
        component.db.barWidth = nil
    end

    -- Height management - this works because OnSizeChanged hook re-applies our height
    local baseHeight = frame._ScooterModBaseHeight
    if not baseHeight or baseHeight <= 0 then
        baseHeight = (frame.GetHeight and frame:GetHeight()) or 0
        if not baseHeight or baseHeight <= 0 then
            baseHeight = 8
        end
        frame._ScooterModBaseHeight = baseHeight
    end

    if component.settings and component.settings.barHeight then
        local defaultHeight = math.floor(baseHeight + 0.5)
        if component.settings.barHeight.default ~= defaultHeight then
            component.settings.barHeight.default = defaultHeight
        end
    end

    local storedHeight = component.db and component.db.barHeight
    if not storedHeight or storedHeight < MIN_POWER_BAR_HEIGHT then
        storedHeight = component.settings and component.settings.barHeight and component.settings.barHeight.default or baseHeight
    end
    storedHeight = clampValue(math.floor((storedHeight or baseHeight) + 0.5), MIN_POWER_BAR_HEIGHT, MAX_POWER_BAR_HEIGHT)
    if component.db then
        component.db.barHeight = storedHeight
    end
    local desiredHeight = storedHeight

    -- Only set height - width is controlled by Blizzard's anchor system
    safeCall(frame.SetHeight, frame, desiredHeight)

    if Util and Util.ApplyFullPowerSpikeScale then
        local spikeScale = 1
        if baseHeight and baseHeight > 0 then
            spikeScale = desiredHeight / baseHeight
        end
        Util.ApplyFullPowerSpikeScale(frame, spikeScale)
        if Util and Util.SetFullPowerSpikeHidden then
            local hideSpikes = (component.db and component.db.hideSpikeAnimations) or (component.db and component.db.hideBar)
            Util.SetFullPowerSpikeHidden(frame, hideSpikes)
        end
        -- Hide power feedback animation (Builder/Spender flash when power is spent/gained)
        if Util and Util.SetPowerFeedbackHidden then
            local hideFeedback = (component.db and component.db.hidePowerFeedback) or (component.db and component.db.hideBar)
            Util.SetPowerFeedbackHidden(frame, hideFeedback)
        end
    end

    local componentScale = resolveClassResourceScale(component)
    applyScaleToFrame(frame, scaleMultiplier * componentScale, component)
    applyPRDPowerVisuals(component, frame)
end

local function resolveClassMechanicFrame()
    if not NamePlateDriverFrame or not NamePlateDriverFrame.GetClassNameplateBar then
        return nil
    end
    local frame = NamePlateDriverFrame:GetClassNameplateBar()
    if frame and frame.IsForbidden and frame:IsForbidden() then
        return nil
    end
    return frame
end

local function getBottomMostPlayerAttachment()
    if not NamePlateDriverFrame then
        return nil
    end
    local plate = getPlayerPlate()
    if not plate or not plate.UnitFrame then
        return nil
    end

    local altPower = NamePlateDriverFrame.GetClassNameplateAlternatePowerBar and NamePlateDriverFrame:GetClassNameplateAlternatePowerBar()
    if altPower and altPower:IsShown() and altPower.GetParent and altPower:GetParent() == plate then
        return altPower
    end

    local power = NamePlateDriverFrame.GetClassNameplateManaBar and NamePlateDriverFrame:GetClassNameplateManaBar()
    if power and power:IsShown() and power.GetParent and power:GetParent() == plate then
        return power
    end

    return plate.UnitFrame.HealthBarsContainer
end

local function applyClassResourceOffsets(component)
    local frame = resolveClassMechanicFrame()
    if not frame then
        return
    end

    local parent = frame:GetParent()
    if not parent or (parent.IsForbidden and parent:IsForbidden()) then
        return
    end

    local offsetX, offsetY = resolveGlobalOffsets()
    local scaleMultiplier = resolveGlobalScaleMultiplier()

    local function safeCall(func, ...)
        local ok = pcall(func, ...)
        if not ok then
            queueAfterCombat(component)
        end
        return ok
    end

    local setter = PixelUtil and PixelUtil.SetPoint
    local point, relativeTo, relativePoint, baseX, baseY

    local playerPlate = getPlayerPlate()
    if parent == playerPlate then
        relativeTo = getBottomMostPlayerAttachment()
        if not relativeTo then
            return
        end
        point = "TOP"
        relativePoint = "BOTTOM"
        baseX = 0
        baseY = frame.paddingOverride or -4
    else
        local targetPlate = (C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target", issecure and issecure())) or nil
        if targetPlate and targetPlate.UnitFrame and parent == targetPlate then
            relativeTo = targetPlate.UnitFrame.name or targetPlate.UnitFrame
            point = "BOTTOM"
            relativePoint = "TOP"
            baseX = 0
            baseY = 4
        else
            return
        end
    end

    if not relativeTo then
        return
    end

    if relativeTo.IsForbidden and relativeTo:IsForbidden() then
        return
    end

    do
        local relX, relY = getAggregateOffsetsForFrame(relativeTo)
        baseX = (baseX or 0) - relX
        baseY = (baseY or 0) - relY
    end

    if not safeCall(frame.ClearAllPoints, frame) then
        return
    end

    local finalX = (baseX or 0) + offsetX
    local finalY = (baseY or 0) + offsetY

    if setter then
        safeCall(setter, frame, point, relativeTo, relativePoint, finalX, finalY)
    else
        safeCall(frame.SetPoint, frame, point, relativeTo, relativePoint, finalX, finalY)
    end

    local componentScale = resolveClassResourceScale(component)
    applyScaleToFrame(frame, scaleMultiplier * componentScale, component)
    applyPRDClassResourceVisibility(component, frame)
end

local function buildPRDBorderOptions()
    local base = addon.BuildBarBorderOptionsContainer and addon.BuildBarBorderOptionsContainer() or {}
    local hasNone = false
    if type(base) == "table" then
        for _, entry in ipairs(base) do
            if entry and entry.value == "none" then
                hasNone = true
                break
            end
        end
    end
    if Settings and Settings.CreateControlTextContainer then
        local container = Settings.CreateControlTextContainer()
        if not hasNone then
            container:Add("none", "None")
        end
        if type(base) == "table" then
            for _, entry in ipairs(base) do
                if entry and entry.value and entry.text then
                    container:Add(entry.value, entry.text)
                end
            end
        end
        if type(base) ~= "table" or #base == 0 then
            container:Add("square", "Default (Square)")
        end
        return container:GetData()
    end
    local results = {}
    if not hasNone then
        table.insert(results, { value = "none", text = "None" })
    end
    local added = false
    if type(base) == "table" then
        for _, entry in ipairs(base) do
            table.insert(results, entry)
            added = true
        end
    end
    if not added then
        table.insert(results, { value = "square", text = "Default (Square)" })
    end
    return results
end

addon:RegisterComponentInitializer(function(self)
    -- NOTE: The Personal Resource Display (PRD) will be added to Blizzard's Edit Mode
    -- in the Midnight expansion. When that happens, these X/Y Position text entry fields
    -- will need to be converted to EditMode-synced settings (type = "editmode") that
    -- use LibEditModeOverride for bi-directional sync, similar to how we handle
    -- positioning for other EditMode-controlled groups (Cooldown Manager, Action Bars,
    -- Unit Frames, etc.) elsewhere in the addon.
    -- See ADDONCONTEXT/Docs/EDITMODE.md for the canonical Edit Mode sync patterns.
    local global = Component:New({
        id = "prdGlobal",
        name = "PRD — Global",
        frameName = nil,
        settings = {
            staticPosition = { type = "addon", default = false, ui = {
                label = "Minimize Vertical Movement", widget = "checkbox", section = "Positioning", order = 1
            }},
            -- Y Offset slider: Displayed as -50 to 50, stored internally as -50 to 50.
            -- When applying CVars, we transform: (value + 50) / 100 to get the 0-1 range.
            -- -50 = bottom of screen, 0 = center, 50 = top of screen.
            screenPosition = { type = "addon", default = 0, ui = {
                label = "Y Offset", widget = "slider", min = -50, max = 50, step = 1, section = "Positioning", order = 2, hidden = true,
                tooltip = "Sets the preferred vertical position on screen (-50 = Bottom, 0 = Center, 50 = Top)."
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "textEntry", min = -MAX_OFFSET, max = MAX_OFFSET, section = "Positioning", order = 3
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "textEntry", min = -MAX_OFFSET, max = MAX_OFFSET, section = "Positioning", order = 4
            }},
        },
    })
    global.ApplyStyling = function(component)
        if not addon or not addon.Components then
            return
        end
        
        -- Handle Static Position Logic (Vertical Clamping)
        local db = component.db or {}
        local settings = component.settings
        local isStatic = db.staticPosition
        
        -- Update UI visibility states based on lock status
        local visibilityChanged = false
        if settings then
            if settings.positionY and settings.positionY.ui then
                if settings.positionY.ui.hidden ~= isStatic then
                    settings.positionY.ui.hidden = isStatic
                    visibilityChanged = true
                end
            end
            if settings.screenPosition and settings.screenPosition.ui then
                if settings.screenPosition.ui.hidden ~= (not isStatic) then
                    settings.screenPosition.ui.hidden = not isStatic
                    visibilityChanged = true
                end
            end
        end
        
        -- Apply the CVars
        if isStatic then
            -- Calculate a very narrow band to effectively "pin" the PRD to a fixed position.
            -- Screen position is stored as -50 to 50 (bottom to top), with 0 = center.
            -- Transform to 0-1 range: (value + 50) / 100
            local posPercent = ((db.screenPosition or 0) + 50) / 100
            
            -- Insets are measured from the edge:
            -- TopInset: 0 = Top edge, 1 = Bottom edge
            -- BottomInset: 0 = Bottom edge, 1 = Top edge
            
            -- Use an extremely narrow band (0.1% of screen) to effectively pin the position.
            -- The previous 12% band allowed too much camera-angle-based movement.
            local bandHeight = 0.001
            local halfBand = bandHeight / 2
            
            -- Clamp center so the band doesn't go off screen (with a small minimum margin)
            local minMargin = 0.05  -- 5% from edges to keep PRD visible
            if posPercent < minMargin then posPercent = minMargin end
            if posPercent > (1 - minMargin) then posPercent = 1 - minMargin end
            
            -- Calculate insets
            local bottomInset = posPercent - halfBand
            local topInset = 1.0 - (posPercent + halfBand)
            
            -- Only apply CVar changes outside of combat to avoid taint
            if C_CVar and C_CVar.SetCVar and not (InCombatLockdown and InCombatLockdown()) then
                pcall(C_CVar.SetCVar, "nameplateSelfTopInset", topInset)
                pcall(C_CVar.SetCVar, "nameplateSelfBottomInset", bottomInset)
            end
        else
            -- Restore defaults (only outside of combat to avoid taint)
            if C_CVar and C_CVar.SetCVar and not (InCombatLockdown and InCombatLockdown()) then
                pcall(C_CVar.SetCVar, "nameplateSelfTopInset", defaultTopInset)
                pcall(C_CVar.SetCVar, "nameplateSelfBottomInset", defaultBottomInset)
            end
        end
        
        -- Refresh the panel if visibility toggled (deferred to avoid flicker/recursion)
        if visibilityChanged and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
             addon.SettingsPanel.RefreshCurrentCategoryDeferred()
        end

        local comps = addon.Components
        local function apply(target)
            if target and target.ApplyStyling then
                target:ApplyStyling()
            end
        end
        apply(comps.prdHealth)
        apply(comps.prdPower)
        apply(comps.prdClassResource)
    end
    ensureHooks(global)
    self:RegisterComponent(global)

    local health = Component:New({
        id = "prdHealth",
        name = "PRD — Health Bar",
        frameName = nil,
        supportsEmptyStyleSection = true,
        supportsEmptyVisibilitySection = true,
        settings = {
            barWidth = { type = "addon", default = MIN_HEALTH_BAR_WIDTH, ui = {
                label = "Bar Width", widget = "slider", min = MIN_HEALTH_BAR_WIDTH, max = MAX_HEALTH_BAR_WIDTH, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the health bar width."
            }},
            barHeight = { type = "addon", default = MIN_HEALTH_BAR_HEIGHT, ui = {
                label = "Bar Height", widget = "slider", min = MIN_HEALTH_BAR_HEIGHT, max = MAX_HEALTH_BAR_HEIGHT, step = 1, section = "Sizing", order = 2, disableTextInput = true,
                tooltip = "Adjusts the health bar height."
            }},
            styleForegroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundTint = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            styleBackgroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundTint = { type = "addon", default = {0, 0, 0, 1}, ui = { hidden = true }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = { hidden = true }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = buildPRDBorderOptions,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1, 1, 1, 1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 0.34, section = "Border", order = 4,
            }},
            borderInset = { type = "addon", default = 0, ui = { hidden = true }},
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Health Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
        },
    })
    health.ApplyStyling = applyHealthOffsets
    ensureHooks(health)
    self:RegisterComponent(health)

    local power = Component:New({
        id = "prdPower",
        name = "PRD — Power Bar",
        frameName = "ClassNameplateManaBarFrame",
        supportsEmptyStyleSection = true,
        supportsEmptyVisibilitySection = true,
        settings = {
            -- NOTE: Bar Width was removed because Blizzard's SetupClassNameplateBars() continuously
            -- re-applies dual anchors (TOPLEFT+TOPRIGHT) which override any custom width. This caused
            -- visible flickering during combat transitions. Width is now controlled by Health Bar width.
            barHeight = { type = "addon", default = MIN_POWER_BAR_HEIGHT, ui = {
                label = "Bar Height", widget = "slider", min = MIN_POWER_BAR_HEIGHT, max = MAX_POWER_BAR_HEIGHT, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the power bar height."
            }},
            styleForegroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundTint = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            styleBackgroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundTint = { type = "addon", default = {0, 0, 0, 1}, ui = { hidden = true }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = { hidden = true }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = buildPRDBorderOptions,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1, 1, 1, 1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 0.34, section = "Border", order = 4,
            }},
            borderInset = { type = "addon", default = 0, ui = { hidden = true }},
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Power Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
            hideSpikeAnimations = { type = "addon", default = false, ui = {
                label = "Hide Full Bar Animations", widget = "checkbox", section = "Misc", order = 2,
            }},
            hidePowerFeedback = { type = "addon", default = false, ui = {
                label = "Hide Power Feedback", widget = "checkbox", section = "Misc", order = 3,
            }},
        },
    })
    power.ApplyStyling = function(comp)
        -- Ensure power bar hooks are installed on every styling pass (frame may not exist on first pass)
        ensurePowerBarHooks(comp)
        applyPowerOffsets(comp)
    end
    ensureHooks(power)
    self:RegisterComponent(power)

    local classRes = Component:New({
        id = "prdClassResource",
        name = "PRD — Class Resource",
        frameName = nil,
        supportsEmptyVisibilitySection = true,
        settings = {
            scale = { type = "addon", default = 100, ui = {
                label = "Scale", widget = "slider", min = MIN_CLASS_RESOURCE_SCALE_PERCENT, max = MAX_CLASS_RESOURCE_SCALE_PERCENT, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the class resource size."
            }},
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Class Resource", widget = "checkbox", section = "Misc", order = 1,
            }},
        },
    })
    classRes.ApplyStyling = applyClassResourceOffsets
    ensureHooks(classRes)
    self:RegisterComponent(classRes)
end)

