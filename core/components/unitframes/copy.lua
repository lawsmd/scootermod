local addonName, addon = ...

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

local function getOffsetX(setting)
    if type(setting) ~= "table" then
        return nil
    end
    local offset = setting.offset
    if type(offset) ~= "table" then
        return nil
    end
    return offset.x
end

local function setOffsetX(setting, value)
    if type(setting) ~= "table" then
        return
    end
    local offset = setting.offset
    if type(offset) ~= "table" then
        if value == nil then
            return
        end
        offset = {}
        setting.offset = offset
    end
    offset.x = value
end

local function canonicalUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local lower = string.lower(unit)
    if lower == "player" then return "Player" end
    if lower == "target" then return "Target" end
    if lower == "focus"  then return "Focus"  end
    if lower == "pet"    then return "Pet"    end
    return nil
end

local unitCaps = {
    Player = {
        orientation = "left",
        hasCastBar = true,
        supportsSpellNameText = true,
        supportsCastTimeText = true,
        supportsShowCastTime = true,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = true,
        supportsPortraitStatusTexture = true,
        supportsPortraitCornerIcon = true,
        supportsFullCircleMask = true,
        supportsDamageText = true,
        supportsIconPadding = true,
    },
    Target = {
        orientation = "right",
        hasCastBar = true,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = true,
    },
    Focus = {
        orientation = "right",
        hasCastBar = true,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = true,
    },
    Pet = {
        orientation = "left",
        hasCastBar = false,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = false,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = false,
    },
}

local copyKeysRoot = {
    "scaleMult",
    "useCustomBorders",
    "healthBarTexture",
    "healthBarBackgroundTexture",
    "healthBarBackgroundColorMode",
    "healthBarBackgroundTint",
    "healthBarBackgroundOpacity",
    "healthBarBorderStyle",
    "healthBarBorderTintEnable",
    "healthBarBorderTintColor",
    "healthBarBorderThickness",
    "healthBarBorderInset",
    "healthPercentHidden",
    "healthValueHidden",
    "textHealthPercent",
    "textHealthValue",
    "powerBarOffsetX",
    "powerBarOffsetY",
    "powerBarWidthPct",
    "powerBarHeightPct",
    "powerBarTexture",
    "powerBarBackgroundTexture",
    "powerBarBackgroundColorMode",
    "powerBarBackgroundTint",
    "powerBarBackgroundOpacity",
    "powerBarBorderStyle",
    "powerBarBorderTintEnable",
    "powerBarBorderTintColor",
    "powerBarBorderThickness",
    "powerBarBorderInset",
    "powerPercentHidden",
    "powerValueHidden",
    "textPowerPercent",
    "textPowerValue",
    "nameBackdropEnabled",
    "nameBackdropTexture",
    "nameBackdropWidthPct",
    "nameBackdropOpacity",
    "nameBackdropBorderEnabled",
    "nameBackdropBorderStyle",
    "nameBackdropBorderTintEnable",
    "nameBackdropBorderTintColor",
    "nameBackdropBorderThickness",
    "nameBackdropBorderInset",
    "nameTextHidden",
    "textName",
    "levelTextHidden",
    "textLevel",
}

local preserveXOffsetKeys = {
    textHealthPercent = true,
    textHealthValue = true,
    textPowerPercent = true,
    textPowerValue = true,
    textName = true,
    textLevel = true,
}

local castBarCommonKeys = {
    "widthPct",
    "castBarTexture",
    "castBarColorMode",
    "castBarTint",
    "castBarBackgroundTexture",
    "castBarBackgroundColorMode",
    "castBarBackgroundTint",
    "castBarBackgroundOpacity",
    "castBarBorderEnable",
    "castBarBorderStyle",
    "castBarBorderColorMode",
    "castBarBorderTintColor",
    "castBarBorderThickness",
    "castBarBorderInset",
    "iconDisabled",
    "iconHeight",
    "iconWidth",
    "iconBarPadding",
    "iconBorderEnable",
    "iconBorderStyle",
    "iconBorderThickness",
    "iconBorderTintEnable",
    "iconBorderTintColor",
    "castBarSparkHidden",
    "castBarSparkColorMode",
    "castBarSparkTint",
}

local function copyShowCastTimeSetting(srcUnit, dstUnit)
    local srcCap = unitCaps[srcUnit]
    local dstCap = unitCaps[dstUnit]
    if not (srcCap and dstCap and srcCap.supportsShowCastTime and dstCap.supportsShowCastTime) then
        return
    end
    local mgr = _G and _G.EditModeManagerFrame
    local EMSys = _G and _G.Enum and _G.Enum.EditModeSystem
    local settingEnum = _G and _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.ShowCastTime
    if not (mgr and EMSys and mgr.GetRegisteredSystemFrame and settingEnum) then
        return
    end
    local frame = mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
    if not frame then
        return
    end
    if not (addon.EditMode and addon.EditMode.GetSetting) then
        return
    end
    local raw = addon.EditMode.GetSetting(frame, settingEnum)
    if raw == nil then
        return
    end
    local value = tonumber(raw) or 0
    value = (value ~= 0) and 1 or 0
    if addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(frame, settingEnum, value, {
            updaters = { "UpdateSystemSettingShowCastTime" },
            suspendDuration = 0.25,
        })
    elseif addon.EditMode and addon.EditMode.SetSetting then
        addon.EditMode.SetSetting(frame, settingEnum, value)
        if type(frame.UpdateSystemSettingShowCastTime) == "function" then
            pcall(frame.UpdateSystemSettingShowCastTime, frame)
        end
        if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
        if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
    end
end

function addon.CopyUnitFrameSettings(sourceUnit, destUnit, opts)
    local src = canonicalUnit(sourceUnit)
    local dst = canonicalUnit(destUnit)
    if not src or not dst then
        return false, "invalid_unit"
    end
    if src == dst then
        return false, "same_unit"
    end

    local srcCap = unitCaps[src]
    local dstCap = unitCaps[dst]
    if not srcCap or not dstCap then
        return false, "invalid_unit"
    end

    local db = addon and addon.db and addon.db.profile
    if not db then
        return false, "db_unavailable"
    end
    db.unitFrames = db.unitFrames or {}

    local srcCfg = db.unitFrames[src] or {}
    local dstCfg = db.unitFrames[dst]
    if not dstCfg then
        dstCfg = {}
        db.unitFrames[dst] = dstCfg
    end

    local skipFrameSize = opts and opts.skipFrameSize
    local frameSizeOk, frameSizeErr = true, nil
    if not skipFrameSize and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
        frameSizeOk, frameSizeErr = addon.EditMode.CopyUnitFrameFrameSize(src, dst)
    end

    local function copyRootKey(key)
        if key == "powerBarOffsetX" then
            return
        end
        local prevOffsetX = nil
        if preserveXOffsetKeys[key] then
            prevOffsetX = getOffsetX(dstCfg[key])
        end
        dstCfg[key] = deepCopy(srcCfg[key])
        if preserveXOffsetKeys[key] then
            setOffsetX(dstCfg[key], prevOffsetX)
        end
    end

    for _, key in ipairs(copyKeysRoot) do
        copyRootKey(key)
    end

    local srcPortrait = type(srcCfg.portrait) == "table" and srcCfg.portrait or {}
    dstCfg.portrait = dstCfg.portrait or {}
    local dstPortrait = dstCfg.portrait

    if dstCap.supportsPortraitOffset and srcCap.supportsPortraitOffset then
        dstPortrait.offsetY = deepCopy(srcPortrait.offsetY)
    elseif not dstCap.supportsPortraitOffset then
        dstPortrait.offsetX = nil
        dstPortrait.offsetY = nil
    end

    dstPortrait.hidePortrait = deepCopy(srcPortrait.hidePortrait)

    if dstCap.supportsPortraitRestLoop then
        if srcCap.supportsPortraitRestLoop then
            dstPortrait.hideRestLoop = deepCopy(srcPortrait.hideRestLoop)
        end
    else
        dstPortrait.hideRestLoop = nil
    end

    if dstCap.supportsPortraitStatusTexture then
        if srcCap.supportsPortraitStatusTexture then
            dstPortrait.hideStatusTexture = deepCopy(srcPortrait.hideStatusTexture)
        end
    else
        dstPortrait.hideStatusTexture = nil
    end

    if dstCap.supportsPortraitCornerIcon then
        if srcCap.supportsPortraitCornerIcon then
            dstPortrait.hideCornerIcon = deepCopy(srcPortrait.hideCornerIcon)
        end
    else
        dstPortrait.hideCornerIcon = nil
    end

    dstPortrait.scale = deepCopy(srcPortrait.scale)
    dstPortrait.opacity = deepCopy(srcPortrait.opacity)
    dstPortrait.zoom = deepCopy(srcPortrait.zoom)

    if dstCap.supportsFullCircleMask and srcCap.supportsFullCircleMask then
        dstPortrait.useFullCircleMask = deepCopy(srcPortrait.useFullCircleMask)
    elseif not dstCap.supportsFullCircleMask then
        dstPortrait.useFullCircleMask = nil
    end

    dstPortrait.portraitBorderEnable = deepCopy(srcPortrait.portraitBorderEnable)
    dstPortrait.portraitBorderStyle = deepCopy(srcPortrait.portraitBorderStyle)
    dstPortrait.portraitBorderThickness = deepCopy(srcPortrait.portraitBorderThickness)
    dstPortrait.portraitBorderColorMode = deepCopy(srcPortrait.portraitBorderColorMode)
    dstPortrait.portraitBorderTintColor = deepCopy(srcPortrait.portraitBorderTintColor)

    if dstCap.supportsDamageText and srcCap.supportsDamageText then
        local prevDamageOffsetX = getOffsetX(dstPortrait.damageText)
        dstPortrait.damageTextDisabled = deepCopy(srcPortrait.damageTextDisabled)
        dstPortrait.damageText = deepCopy(srcPortrait.damageText)
        setOffsetX(dstPortrait.damageText, prevDamageOffsetX)
    elseif not dstCap.supportsDamageText then
        dstPortrait.damageTextDisabled = nil
        dstPortrait.damageText = nil
    end

    if not dstCap.hasCastBar then
        dstCfg.castBar = nil
    else
        dstCfg.castBar = dstCfg.castBar or {}
        local dstCast = dstCfg.castBar
        if srcCap.hasCastBar then
            local srcCast = type(srcCfg.castBar) == "table" and srcCfg.castBar or {}
            for _, key in ipairs(castBarCommonKeys) do
                dstCast[key] = deepCopy(srcCast[key])
            end
            if dstCap.supportsSpellNameText and srcCap.supportsSpellNameText then
                local prevSpellNameOffsetX = getOffsetX(dstCast.spellNameText)
                dstCast.spellNameTextDisabled = deepCopy(srcCast.spellNameTextDisabled)
                dstCast.hideSpellNameBackdrop = deepCopy(srcCast.hideSpellNameBackdrop)
                dstCast.spellNameText = deepCopy(srcCast.spellNameText)
                setOffsetX(dstCast.spellNameText, prevSpellNameOffsetX)
            elseif not dstCap.supportsSpellNameText then
                dstCast.spellNameTextDisabled = nil
                dstCast.hideSpellNameBackdrop = nil
                dstCast.spellNameText = nil
            end
            if dstCap.supportsCastTimeText and srcCap.supportsCastTimeText then
                local prevCastTimeOffsetX = getOffsetX(dstCast.castTimeText)
                dstCast.castTimeTextDisabled = deepCopy(srcCast.castTimeTextDisabled)
                dstCast.castTimeText = deepCopy(srcCast.castTimeText)
                setOffsetX(dstCast.castTimeText, prevCastTimeOffsetX)
            elseif not dstCap.supportsCastTimeText then
                dstCast.castTimeTextDisabled = nil
                dstCast.castTimeText = nil
            end
        end
    end

    copyShowCastTimeSetting(src, dst)

    if addon.ApplyUnitFrameScaleMultFor then
        addon.ApplyUnitFrameScaleMultFor(dst)
    end
    if addon.ApplyUnitFrameBarTexturesFor then
        addon.ApplyUnitFrameBarTexturesFor(dst)
    end
    if addon.ApplyUnitFrameHealthTextVisibilityFor then
        addon.ApplyUnitFrameHealthTextVisibilityFor(dst)
    end
    if addon.ApplyUnitFramePowerTextVisibilityFor then
        addon.ApplyUnitFramePowerTextVisibilityFor(dst)
    end
    if addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(dst)
    end
    if addon.ApplyUnitFramePortraitFor then
        addon.ApplyUnitFramePortraitFor(dst)
    end
    if dstCap.hasCastBar and addon.ApplyUnitFrameCastBarFor then
        addon.ApplyUnitFrameCastBarFor(dst)
    end
    if addon.ApplyStyles then
        addon:ApplyStyles()
    end

    return frameSizeOk, frameSizeErr
end

