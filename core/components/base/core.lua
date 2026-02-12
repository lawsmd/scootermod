local addonName, addon = ...

addon.Components = addon.Components or {}
addon.ComponentInitializers = addon.ComponentInitializers or {}
addon.ComponentsUtil = addon.ComponentsUtil or {}

local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

local Util = addon.ComponentsUtil
local UNIT_FRAME_CATEGORY_TO_UNIT = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus  = "Focus",
    ufPet    = "Pet",
}

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = CopyDefaultValue(v)
    end
    return copy
end

-- Metatable fallback: unset keys return their registered defaults.
local function attachSettingsDefaults(db, component)
    if not db or not component then return end
    local settings = component.settings
    if not settings then return end
    if getmetatable(db) then return end  -- don't clobber proxy's metatable
    setmetatable(db, {
        __index = function(_, key)
            local meta = settings[key]
            if type(meta) == "table" and meta.default ~= nil then
                return meta.default
            end
        end,
    })
end

local Component = {}
Component.__index = Component

function Component:New(o)
    o = o or {}
    return setmetatable(o, self)
end

function Component:SyncEditModeSettings()
    local frame = _G[self.frameName]
    if not frame then return end

    local changed = false
    for settingId, setting in pairs(self.settings) do
        if type(setting) == "table" and setting.type == "editmode" then
            if addon.EditMode.SyncEditModeSettingToComponent(self, settingId) then
                changed = true
            end
        end
    end

    return changed
end

addon.ComponentPrototype = Component

function addon:RegisterComponent(component)
    self.Components[component.id] = component
end

function addon:RegisterComponentInitializer(initializer)
    if type(initializer) ~= "function" then return end
    table.insert(self.ComponentInitializers, initializer)
end

function addon:InitializeComponents()
    if wipe then
        wipe(self.Components)
    else
        self.Components = {}
    end

    for _, initializer in ipairs(self.ComponentInitializers) do
        pcall(initializer, self)
    end
end

function addon:LinkComponentsToDB()
    -- Zero-Touch: only assign pre-existing persisted tables.
    local profile = self.db and self.db.profile
    local components = profile and rawget(profile, "components") or nil
    for id, component in pairs(self.Components) do
        local persisted = components and rawget(components, id) or nil
        if persisted then
            component.db = persisted
            attachSettingsDefaults(persisted, component)
        else
            -- Proxy: reads return nil, first write materializes the real table.
            if not component._ScootDBProxy then
                local proxy = {}
                setmetatable(proxy, {
                    __index = function(_, key)
                        local real = component.db
                        if real and real ~= proxy then
                            return real[key]
                        end
                        return nil
                    end,
                    __newindex = function(_, key, value)
                        local realDb = addon:EnsureComponentDB(component)
                        if realDb then
                            rawset(realDb, key, value)
                        end
                    end,
                    __pairs = function()
                        local real = component.db
                        if real and real ~= proxy then
                            return pairs(real)
                        end
                        return function() return nil end
                    end,
                })
                component._ScootDBProxy = proxy
            end
            component.db = component._ScootDBProxy
        end
    end
end

function addon:EnsureComponentDB(componentOrId)
    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end
    if not component or not component.id then
        return nil
    end
    local profile = self.db and self.db.profile
    if not profile then
        return nil
    end
    local components = rawget(profile, "components")
    if type(components) ~= "table" then
        components = {}
        profile.components = components
    end
    local db = rawget(components, component.id)
    if type(db) ~= "table" then
        db = {}
        components[component.id] = db
    end
    component.db = db
    attachSettingsDefaults(db, component)
    return db
end

function addon:ClearFrameLevelState()
    -- Best-effort cleanup on profile switch. Clears hook flags so hidden states
    -- stop being enforced (full restore requires reload).
    local function safeAlpha(fs)
        if fs and fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
    end
    local function clearTextFlags(fs)
        if not fs then return end
        -- Clear FrameState hidden flags
        local fstate = ensureFS()
        if fstate then
            fstate.SetHidden(fs, "healthText", false)
            fstate.SetHidden(fs, "powerText", false)
            fstate.SetHidden(fs, "healthTextCenter", false)
            fstate.SetHidden(fs, "powerTextCenter", false)
            fstate.SetHidden(fs, "totName", false)
            fstate.SetHidden(fs, "altPowerText", false)
        end
        safeAlpha(fs)
    end

    if self._ufHealthTextFonts then
        for _, cache in pairs(self._ufHealthTextFonts) do
            clearTextFlags(cache and cache.leftFS)
            clearTextFlags(cache and cache.rightFS)
            clearTextFlags(cache and cache.textStringFS)
        end
    end
    if self._ufPowerTextFonts then
        for _, cache in pairs(self._ufPowerTextFonts) do
            clearTextFlags(cache and cache.leftFS)
            clearTextFlags(cache and cache.rightFS)
            clearTextFlags(cache and cache.textStringFS)
        end
    end

    clearTextFlags(_G.PlayerFrameHealthBarTextLeft)
    clearTextFlags(_G.PlayerFrameHealthBarTextRight)
    clearTextFlags(_G.PlayerFrameManaBarTextLeft)
    clearTextFlags(_G.PlayerFrameManaBarTextRight)
    clearTextFlags(_G.PetFrameHealthBarTextLeft)
    clearTextFlags(_G.PetFrameHealthBarTextRight)
    clearTextFlags(_G.PetFrameManaBarTextLeft)
    clearTextFlags(_G.PetFrameManaBarTextRight)

    self._ufTextBaselines = nil
    self._ufPowerTextBaselines = nil
    self._ufNameLevelTextBaselines = nil
    self._ufNameContainerBaselines = nil
    self._ufNameBackdropBaseWidth = nil
    self._ufToTNameTextBaseline = nil

    self._ufHealthTextFonts = nil
    self._ufPowerTextFonts = nil
end

function addon:ApplyStyles()
    -- CRITICAL: Styling during combat taints protected frames ("blocked from an action").
    if InCombatLockdown and InCombatLockdown() then
        -- Cast bar hooks are visual-only and safe during combat.
        if addon.EnsureAllUnitFrameCastBarHooks then
            addon.EnsureAllUnitFrameCastBarHooks()
        end
        if not self._pendingApplyStyles then
            self._pendingApplyStyles = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    local profile = self.db and self.db.profile
    local componentsCfg = profile and rawget(profile, "components") or nil
    for id, component in pairs(self.Components) do
        -- Zero-Touch: skip unconfigured components.
        local hasConfig = componentsCfg and rawget(componentsCfg, id) ~= nil
        if hasConfig and component.ApplyStyling then
            component:ApplyStyling()
        end
    end
    if addon.ApplyAllUnitFrameHealthTextVisibility then
        addon.ApplyAllUnitFrameHealthTextVisibility()
    end
    if addon.ApplyAllUnitFramePowerTextVisibility then
        addon.ApplyAllUnitFramePowerTextVisibility()
    end
    if addon.ApplyAllUnitFrameNameLevelText then
        addon.ApplyAllUnitFrameNameLevelText()
    end
    if addon.ApplyAllUnitFrameBarTextures then
        addon.ApplyAllUnitFrameBarTextures()
    end
    if addon.ApplyAllUnitFramePortraits then
        addon.ApplyAllUnitFramePortraits()
    end
	if addon.ApplyAllUnitFrameClassResources then
		addon.ApplyAllUnitFrameClassResources()
	end
    if addon.ApplyAllUnitFrameCastBars then
        addon.ApplyAllUnitFrameCastBars()
    end
    if addon.ApplyAllUnitFrameBuffsDebuffs then
        addon.ApplyAllUnitFrameBuffsDebuffs()
    end
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
    end
    if addon.ApplyAllThreatMeterVisibility then
        addon.ApplyAllThreatMeterVisibility()
    end
    if addon.ApplyTargetBossIconVisibility then
        addon.ApplyTargetBossIconVisibility()
    end
    if addon.ApplyAllPlayerMiscVisibility then
        addon.ApplyAllPlayerMiscVisibility()
    end
    if addon.ApplyPetFrameVisibility then
        addon.ApplyPetFrameVisibility()
    end
	-- Unit Frames: Off-screen drag unlock (Player + Target)
	if addon.ApplyAllUnitFrameOffscreenUnlocks then
		addon.ApplyAllUnitFrameOffscreenUnlocks()
	end
    if addon.ApplyAllUnitFrameScaleMults then
        addon.ApplyAllUnitFrameScaleMults()
    end
    -- ToT/FocusTarget: Apply scale and position (not Edit Mode managed)
    if addon.ApplyAllToTSettings then
        addon.ApplyAllToTSettings()
    end
    if addon.ApplyAllFocusTargetSettings then
        addon.ApplyAllFocusTargetSettings()
    end
    -- Group Frames: Apply raid frame health bar styling
    if addon.ApplyRaidFrameHealthBarStyle then
        addon.ApplyRaidFrameHealthBarStyle()
    end
    -- Group Frames: Apply raid frame status text styling
    if addon.ApplyRaidFrameStatusTextStyle then
        addon.ApplyRaidFrameStatusTextStyle()
    end
    -- Group Frames: Apply raid group title styling (Group Numbers)
    if addon.ApplyRaidFrameGroupTitlesStyle then
        addon.ApplyRaidFrameGroupTitlesStyle()
    end
    -- Group Frames: Apply raid frame combat-safe overlays
    if addon.ApplyRaidFrameHealthOverlays then
        addon.ApplyRaidFrameHealthOverlays()
    end
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
    -- Group Frames: Apply party frame health bar styling
    if addon.ApplyPartyFrameHealthBarStyle then
        addon.ApplyPartyFrameHealthBarStyle()
    end
    -- Group Frames: Apply party frame title styling (Party Title)
    if addon.ApplyPartyFrameTitleStyle then
        addon.ApplyPartyFrameTitleStyle()
    end
    -- Group Frames: Apply party frame combat-safe overlays
    if addon.ApplyPartyFrameHealthOverlays then
        addon.ApplyPartyFrameHealthOverlays()
    end
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
    -- Group Frames: Apply party frame visibility settings (over absorb glow, etc.)
    if addon.ApplyPartyOverAbsorbGlowVisibility then
        addon.ApplyPartyOverAbsorbGlowVisibility()
    end
    -- Group Frames: Apply party frame health bar borders
    if addon.ApplyPartyFrameHealthBarBorders then
        addon.ApplyPartyFrameHealthBarBorders()
    end
    -- Group Frames: Apply raid frame health bar borders
    if addon.ApplyRaidFrameHealthBarBorders then
        addon.ApplyRaidFrameHealthBarBorders()
    end
end

function addon:ApplyEarlyComponentStyles()
    local profile = self.db and self.db.profile
    local componentsCfg = profile and rawget(profile, "components") or nil
    for id, component in pairs(self.Components) do
        local hasConfig = componentsCfg and rawget(componentsCfg, id) ~= nil
        if hasConfig and component.ApplyStyling and component.applyDuringInit then
            component:ApplyStyling()
        end
    end
end

function addon:ResetComponentToDefaults(componentOrId)
    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end

    if not component then
        return false, "component_missing"
    end

    if not component.db then
        if type(self.EnsureComponentDB) == "function" then
            self:EnsureComponentDB(component)
        end
    end

    if not component.db then
        return false, "component_db_unavailable"
    end

    local seen = {}
    for settingId, setting in pairs(component.settings or {}) do
        if type(setting) == "table" then
            seen[settingId] = true
            if setting.default ~= nil then
                component.db[settingId] = CopyDefaultValue(setting.default)
            else
                component.db[settingId] = nil
            end
        end
    end

    for key in pairs(component.db) do
        if not seen[key] then
            component.db[key] = nil
        end
    end

    if self.EditMode and self.EditMode.ResetComponentPositionToDefault then
        self.EditMode.ResetComponentPositionToDefault(component)
    end

    if self.EditMode and self.EditMode.SyncComponentToEditMode then
        self.EditMode.SyncComponentToEditMode(component, { skipApply = true })
    end

    if self.ApplyStyles then
        self:ApplyStyles()
    end

    return true
end

function addon:ResetUnitFrameCategoryToDefaults(categoryKey)
    if type(categoryKey) ~= "string" then
        return false, "invalid_category"
    end

    local unit = UNIT_FRAME_CATEGORY_TO_UNIT[categoryKey]
    if not unit then
        return false, "unknown_unit"
    end

    local profile = self.db and self.db.profile
    if not profile then
        return false, "db_unavailable"
    end

    if profile.unitFrames then
        profile.unitFrames[unit] = nil
        local hasAny = false
        for _ in pairs(profile.unitFrames) do
            hasAny = true
            break
        end
        if not hasAny then
            profile.unitFrames = nil
        end
    end

    if self.EditMode and self.EditMode.ResetUnitFramePosition then
        self.EditMode.ResetUnitFramePosition(unit)
    end

    if self.ApplyUnitFrameBarTexturesFor then
        self.ApplyUnitFrameBarTexturesFor(unit)
    end
    if self.ApplyUnitFrameHealthTextVisibilityFor then
        self.ApplyUnitFrameHealthTextVisibilityFor(unit)
    end
    if self.ApplyUnitFramePowerTextVisibilityFor then
        self.ApplyUnitFramePowerTextVisibilityFor(unit)
    end
    if self.ApplyUnitFrameNameLevelTextFor then
        self.ApplyUnitFrameNameLevelTextFor(unit)
    end
    if self.ApplyUnitFramePortraitFor then
        self.ApplyUnitFramePortraitFor(unit)
    end
    if self.ApplyUnitFrameCastBarFor then
        self.ApplyUnitFrameCastBarFor(unit)
    end
    if self.ApplyUnitFrameBuffsDebuffsFor then
        self.ApplyUnitFrameBuffsDebuffsFor(unit)
    end
    if self.ApplyUnitFrameVisibilityFor then
        self.ApplyUnitFrameVisibilityFor(unit)
    end

    return true
end

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for _, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            if component:SyncEditModeSettings() then
                anyChanged = true
            end
        end
        if addon.EditMode.SyncComponentPositionFromEditMode then
            if addon.EditMode.SyncComponentPositionFromEditMode(component) then
                anyChanged = true
            end
        end
    end

    return anyChanged
end

addon.ComponentsUtil._ensureFS = ensureFS
addon.ComponentsUtil._getState = getState
addon.ComponentsUtil._getProp = getProp
addon.ComponentsUtil._setProp = setProp
