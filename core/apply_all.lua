local addonName, addon = ...

addon.ApplyAll = addon.ApplyAll or {}
local ApplyAll = addon.ApplyAll
local os_time = _G and _G.time

local FONT_KEYS = { fontFace = true }

-- Bar texture keys vary by system:
-- - Cooldown Manager/PRD use: styleForegroundTexture, styleBackgroundTexture
-- - Unit Frames use: healthBarTexture, healthBarBackgroundTexture, powerBarTexture, powerBarBackgroundTexture
local FG_TEXTURE_KEYS = {
    styleForegroundTexture = true,
    healthBarTexture = true,
    powerBarTexture = true,
}
local BG_TEXTURE_KEYS = {
    styleBackgroundTexture = true,
    healthBarBackgroundTexture = true,
    powerBarBackgroundTexture = true,
}

-- Font settings are stored in deeply nested tables that only get created when
-- the user visits those settings panels. We must ensure these tables exist
-- before ApplyAll can traverse and update their fontFace keys.

-- Unit Frame font structures
local UNIT_FRAME_UNITS = { "Player", "Target", "Focus", "Pet" }
local UNIT_FRAME_TEXT_KEYS = {
    "textHealthPercent",
    "textHealthValue",
    "textPowerPercent",
    "textPowerValue",
    "textName",
    "textLevel",
}

local function ensureUnitFrameFontStructures(profile)
    if not profile then return end
    profile.unitFrames = profile.unitFrames or {}
    
    for _, unit in ipairs(UNIT_FRAME_UNITS) do
        profile.unitFrames[unit] = profile.unitFrames[unit] or {}
        local unitCfg = profile.unitFrames[unit]
        
        -- Ensure all text style tables exist with fontFace key
        for _, textKey in ipairs(UNIT_FRAME_TEXT_KEYS) do
            unitCfg[textKey] = unitCfg[textKey] or {}
            -- Only set fontFace if not already present (preserve existing values)
            if unitCfg[textKey].fontFace == nil then
                unitCfg[textKey].fontFace = "FRIZQT__"
            end
        end
        
        -- Portrait damage text (Player only, but safe to init for all)
        unitCfg.portrait = unitCfg.portrait or {}
        unitCfg.portrait.damageText = unitCfg.portrait.damageText or {}
        if unitCfg.portrait.damageText.fontFace == nil then
            unitCfg.portrait.damageText.fontFace = "FRIZQT__"
        end
        
        -- Cast bar text (Player has castBar, others may have different structure)
        unitCfg.castBar = unitCfg.castBar or {}
        unitCfg.castBar.spellNameText = unitCfg.castBar.spellNameText or {}
        if unitCfg.castBar.spellNameText.fontFace == nil then
            unitCfg.castBar.spellNameText.fontFace = "FRIZQT__"
        end
        unitCfg.castBar.castTimeText = unitCfg.castBar.castTimeText or {}
        if unitCfg.castBar.castTimeText.fontFace == nil then
            unitCfg.castBar.castTimeText.fontFace = "FRIZQT__"
        end
    end
end

-- Unit Frame bar texture keys (stored at root level of each unit config)
local UNIT_FRAME_TEXTURE_KEYS = {
    "healthBarTexture",
    "healthBarBackgroundTexture",
    "powerBarTexture",
    "powerBarBackgroundTexture",
}

local function ensureUnitFrameTextureStructures(profile)
    if not profile then return end
    profile.unitFrames = profile.unitFrames or {}
    
    for _, unit in ipairs(UNIT_FRAME_UNITS) do
        profile.unitFrames[unit] = profile.unitFrames[unit] or {}
        local unitCfg = profile.unitFrames[unit]
        
        -- Ensure all bar texture keys exist with default value
        for _, textureKey in ipairs(UNIT_FRAME_TEXTURE_KEYS) do
            if unitCfg[textureKey] == nil then
                unitCfg[textureKey] = "default"
            end
        end
    end
end

-- Cooldown Manager components use inline fallbacks for text settings, so they
-- don't get initialized by GetDefaults(). We must create them explicitly.
local COOLDOWN_COMPONENT_IDS = {
    "essentialCooldowns",
    "utilityCooldowns",
    "trackedBuffs",
    "trackedBars",
}
-- Common text keys used by cooldown components (trackedBars uses textName/textDuration)
local COOLDOWN_TEXT_KEYS = {
    "textStacks",
    "textCooldown",
    "textCharges",
    "textName",
    "textDuration",
}

-- Auras (buffs/debuffs) text settings
local AURA_COMPONENT_IDS = {
    "buffs",
    "debuffs",
}
local AURA_TEXT_KEYS = {
    "textCount",
    "textDuration",
}

-- Nameplates text settings
local NAMEPLATE_COMPONENT_IDS = {
    "nameplatesUnit",
}

local function ensureComponentFontStructures(profile)
    if not profile then return end
    profile.components = profile.components or {}
    
    -- Cooldown Manager components
    for _, componentId in ipairs(COOLDOWN_COMPONENT_IDS) do
        profile.components[componentId] = profile.components[componentId] or {}
        local cfg = profile.components[componentId]
        for _, textKey in ipairs(COOLDOWN_TEXT_KEYS) do
            cfg[textKey] = cfg[textKey] or {}
            if cfg[textKey].fontFace == nil then
                cfg[textKey].fontFace = "FRIZQT__"
            end
        end
    end
    
    -- Auras (buffs/debuffs) components
    for _, componentId in ipairs(AURA_COMPONENT_IDS) do
        profile.components[componentId] = profile.components[componentId] or {}
        local cfg = profile.components[componentId]
        for _, textKey in ipairs(AURA_TEXT_KEYS) do
            cfg[textKey] = cfg[textKey] or {}
            if cfg[textKey].fontFace == nil then
                cfg[textKey].fontFace = "FRIZQT__"
            end
        end
    end
    
    -- Nameplates component
    for _, componentId in ipairs(NAMEPLATE_COMPONENT_IDS) do
        profile.components[componentId] = profile.components[componentId] or {}
        local cfg = profile.components[componentId]
        cfg.textName = cfg.textName or {}
        if cfg.textName.fontFace == nil then
            cfg.textName.fontFace = "FRIZQT__"
        end
    end
    
    -- NOTE: Scrolling Combat Text (sctDamage) is intentionally excluded from Apply All.
    -- SCT font changes require a full game restart (not just /reload), so users must
    -- change SCT fonts directly via the Scrolling Combat Text settings panel to see
    -- the restart warning. See SCROLLINGCOMBATTEXT.md for details.
    
    -- Tooltip component (text settings tables)
    profile.components.tooltip = profile.components.tooltip or {}
    local tcfg = profile.components.tooltip
    tcfg.textTitle = tcfg.textTitle or {}
    if tcfg.textTitle.fontFace == nil then tcfg.textTitle.fontFace = "FRIZQT__" end

    tcfg.textEverythingElse = tcfg.textEverythingElse or {}
    if tcfg.textEverythingElse.fontFace == nil then tcfg.textEverythingElse.fontFace = "FRIZQT__" end

    tcfg.textComparison = tcfg.textComparison or {}
    if tcfg.textComparison.fontFace == nil then tcfg.textComparison.fontFace = "FRIZQT__" end
end

local function ensureState()
    local db = addon.db
    local profile = db and db.profile
    if not profile then
        return nil
    end
    profile.applyAll = profile.applyAll or {}
    local state = profile.applyAll
    if state.fontPending == nil then
        state.fontPending = "FRIZQT__"
    end
    if state.barTexturePending == nil then
        state.barTexturePending = "default"
    end
    return state, profile
end

local function replaceKeys(root, keys, value, opts)
    if type(root) ~= "table" then
        return 0
    end
    local skipTables = (opts and opts.skipTables) or {}
    local visited = {}
    local changed = 0

    local function traverse(tbl)
        if type(tbl) ~= "table" or visited[tbl] then
            return
        end
        if skipTables[tbl] then
            return
        end
        visited[tbl] = true
        for key, child in pairs(tbl) do
            if keys[key] then
                if tbl[key] ~= value then
                    tbl[key] = value
                    changed = changed + 1
                end
            end
            if type(child) == "table" then
                traverse(child)
            end
        end
    end

    traverse(root)
    return changed
end

local function buildResult(success, changed, reason)
    return {
        ok = success,
        changed = changed or 0,
        reason = reason,
    }
end

function ApplyAll:GetState()
    local state = ensureState()
    return state
end

function ApplyAll:GetPendingFont()
    local state = ensureState()
    return state and state.fontPending or nil
end

function ApplyAll:SetPendingFont(fontKey)
    local state = ensureState()
    if state then
        state.fontPending = fontKey or "FRIZQT__"
    end
end

function ApplyAll:GetPendingBarTexture()
    local state = ensureState()
    return state and state.barTexturePending or nil
end

function ApplyAll:SetPendingBarTexture(textureKey)
    local state = ensureState()
    if state then
        state.barTexturePending = textureKey or "default"
    end
end

function ApplyAll:GetLastFontSummary()
    local state = ensureState()
    return state and state.lastFontApplied or nil
end

function ApplyAll:GetLastBarTextureSummary()
    local state = ensureState()
    return state and state.lastTextureApplied or nil
end

local function recordSummary(target, key, changed)
    if not target then
        return
    end
    target.value = key
    target.changed = changed or 0
    if type(os_time) == "function" then
        target.timestamp = os_time()
    else
        target.timestamp = nil
    end
end

function ApplyAll:ApplyFonts(fontKey, opts)
    local state, profile = ensureState()
    if not state or not profile then
        return buildResult(false, 0, "noProfile")
    end
    local selection = fontKey or state.fontPending
    if not selection or selection == "" then
        return buildResult(false, 0, "noSelection")
    end
    
    -- Ensure font structures exist before traversing.
    -- These nested tables are lazily created when the user visits settings panels,
    -- so we must ensure they exist for ApplyAll to find and update them.
    ensureUnitFrameFontStructures(profile)
    ensureComponentFontStructures(profile)
    
    -- Skip the applyAll state table and sctDamage component.
    -- SCT is excluded because font changes require a full game restart (not /reload),
    -- and users need to see the restart warning when changing SCT fonts directly.
    local skip = { [state] = true }
    if profile.components and profile.components.sctDamage then
        skip[profile.components.sctDamage] = true
    end
    local changed = replaceKeys(profile, FONT_KEYS, selection, { skipTables = skip })
    state.lastFontApplied = state.lastFontApplied or {}
    recordSummary(state.lastFontApplied, selection, changed)
    if opts and opts.updatePending then
        state.fontPending = selection
    end
    local success = changed > 0
    return buildResult(success, changed, success and nil or "noChanges")
end

function ApplyAll:ApplyBarTextures(textureKey, opts)
    local state, profile = ensureState()
    if not state or not profile then
        return buildResult(false, 0, "noProfile")
    end
    local selection = textureKey or state.barTexturePending
    if not selection or selection == "" then
        return buildResult(false, 0, "noSelection")
    end
    
    -- Ensure Unit Frame texture structures exist before traversing.
    -- These are lazily created when the user visits settings panels.
    ensureUnitFrameTextureStructures(profile)
    
    local skip = { [state] = true }
    local fgChanged = replaceKeys(profile, FG_TEXTURE_KEYS, selection, { skipTables = skip })
    local bgChanged = replaceKeys(profile, BG_TEXTURE_KEYS, selection, { skipTables = skip })
    local changed = fgChanged + bgChanged
    state.lastTextureApplied = state.lastTextureApplied or {}
    recordSummary(state.lastTextureApplied, selection, changed)
    if opts and opts.updatePending then
        state.barTexturePending = selection
    end
    local success = changed > 0
    return buildResult(success, changed, success and nil or "noChanges")
end


