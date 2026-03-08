-- classauras/cdmborrow.lua - CDM icon hiding, mixin hooks, rescan logic
local addonName, addon = ...

local CA = addon.ClassAuras

-- Local aliases (resolved at load time — core.lua loads first)
local GetDB = CA._GetDB
local auraTracking = CA._auraTracking
local CacheAuraIdentity = CA._CacheAuraIdentity
local playerClassToken = CA._playerClassToken

--------------------------------------------------------------------------------
-- CDM Borrow: Hide CDM icons via SetAlpha(0)
--------------------------------------------------------------------------------
-- When Class Auras takes over display, we hide the corresponding CDM icon
-- to avoid duplicates. Duration comes from DurationObject, stacks from direct scan or GetAuraApplicationDisplayCount.

-- CDM Borrow subsystem: hides CDM icons via SetAlphaFromBoolean when Class Auras
-- takes over display. Duration/timing data comes from DurationObject API (live C++ object).
local cdmBorrow = {
    hookInstalled = false,
}
-- Track which CDM item frames already have Show/SetShown hooks installed
local hookedItemFrames = setmetatable({}, { __mode = "k" })
-- Track CDM item frames we've hidden via SetAlphaFromBoolean -- itemFrame -> auraId
local hiddenItemFrames = setmetatable({}, { __mode = "k" })

local function searchViewer(viewerName, spellId)
    local viewer = _G[viewerName]
    if not viewer then return nil end
    local ok, children = pcall(function() return { viewer:GetChildren() } end)
    if not ok or not children then return nil end
    for _, child in ipairs(children) do
        -- GetBaseSpellID() is a plain Lua table read (self.cooldownInfo.spellID),
        -- populated by Blizzard's untainted code -- returns real data even in combat.
        local idOk, childSpellId = pcall(function() return child:GetBaseSpellID() end)
        if idOk and childSpellId == spellId then
            return child
        end
    end
    -- Fallback: search linkedSpellIDs (e.g., 188389 Flame Shock is linked under base 470411)
    for _, child in ipairs(children) do
        local ciOk, found = pcall(function()
            local ci = child:GetCooldownInfo()
            if ci and ci.linkedSpellIDs then
                for _, lid in ipairs(ci.linkedSpellIDs) do
                    if lid == spellId then return true end
                end
            end
            return false
        end)
        if ciOk and found then
            return child
        end
    end
    return nil
end

local function FindCDMItemForSpell(spellId)
    -- Search icon layout first (most common), then bar layout
    return searchViewer("BuffIconCooldownViewer", spellId)
        or searchViewer("BuffBarCooldownViewer", spellId)
end

local function BindCDMBorrowTarget(itemFrame, aura)
    -- Install Show/SetShown hooks to re-apply alpha when CDM redisplays the icon
    if not hookedItemFrames[itemFrame] then
        hookedItemFrames[itemFrame] = true

        hooksecurefunc(itemFrame, "Show", function(self)
            if hiddenItemFrames[self] then
                self:SetAlphaFromBoolean(false, 1, 0)
            end
        end)

        hooksecurefunc(itemFrame, "SetShown", function(self, shown)
            if shown and hiddenItemFrames[self] then
                self:SetAlphaFromBoolean(false, 1, 0)
            end
        end)
    end

    -- Apply or remove CDM icon hiding
    local db = GetDB(aura)
    if db and db.enabled and (db.hideFromCDM ~= false) then
        itemFrame:SetAlphaFromBoolean(false, 1, 0)
        hiddenItemFrames[itemFrame] = aura.id
    elseif hiddenItemFrames[itemFrame] then
        itemFrame:SetAlphaFromBoolean(true, 1, 0)
        hiddenItemFrames[itemFrame] = nil
    end
end

local function RestoreHiddenCDMFrames(auraId)
    for frame, id in pairs(hiddenItemFrames) do
        if id == auraId then
            frame:SetAlphaFromBoolean(true, 1, 0)
            hiddenItemFrames[frame] = nil
        end
    end
end

local function RescanForCDMBorrow()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if aura.cdmBorrow then
            local state = CA._activeAuras[aura.id]
            if state then
                local db = GetDB(aura)
                if not db or not db.enabled then
                    RestoreHiddenCDMFrames(aura.id)
                elseif UnitExists(aura.unit) then
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    local itemFrame = FindCDMItemForSpell(cdmId)
                    if not itemFrame and aura.cdmSpellId and aura.auraSpellId then
                        itemFrame = FindCDMItemForSpell(aura.auraSpellId)
                    end
                    if itemFrame then
                        -- Capture identity (auraInstanceID + unit + activeSpellId) for DurationObject tracking
                        local iid = itemFrame.auraInstanceID
                        local iunit = itemFrame.auraDataUnit
                        if iid and iunit then
                            -- Validate CDM frame's auraInstanceID before storing (prevents stale overwrites)
                            local vOk, vDur = pcall(C_UnitAuras.GetAuraDuration, iunit, iid)
                            if vOk and vDur then
                                local activeSpell = aura.auraSpellId
                                pcall(function()
                                    local fSpell = itemFrame.auraSpellID
                                    if fSpell and not issecretvalue(fSpell) and aura.linkedSpellIds then
                                        for _, lid in ipairs(aura.linkedSpellIds) do
                                            if fSpell == lid then activeSpell = lid; break end
                                        end
                                    end
                                end)
                                local tracked = auraTracking[aura.id]
                                if not tracked or tracked.auraInstanceID ~= iid then
                                    auraTracking[aura.id] = { unit = iunit, auraInstanceID = iid, activeSpellId = activeSpell }
                                    CacheAuraIdentity(iunit, aura.id, iid, activeSpell)
                                end
                            end
                        end
                        BindCDMBorrowTarget(itemFrame, aura)
                    else
                        -- Don't clear auraTracking -- let ScanAura's GetAuraDuration handle stale instances.
                        -- CDM icon may be gone due to target switch, but aura may still exist on original target.
                        RestoreHiddenCDMFrames(aura.id)
                    end
                end
            end
        end
    end
end

local function InstallMixinHooks()
    if cdmBorrow.hookInstalled then return end

    -- Hook SetAuraInstanceInfo to capture auraInstanceID for combat tracking.
    -- When CDM processes an aura in its untainted context, this fires and gives
    -- us the non-secret spellID (from cooldownInfo) and the auraInstanceID.
    local dataMixin = _G.CooldownViewerItemDataMixin
    if dataMixin and dataMixin.SetAuraInstanceInfo then
        hooksecurefunc(dataMixin, "SetAuraInstanceInfo", function(self, auraInfo)
            local ci = self.cooldownInfo
            if not ci then return end
            local spellID = ci.spellID
            if ci.linkedSpellIDs and ci.linkedSpellIDs[1] then
                spellID = ci.linkedSpellIDs[1]
            end
            if not spellID then return end

            local instanceID = auraInfo and auraInfo.auraInstanceID
            local unit = self.auraDataUnit
            if not instanceID or not unit then return end

            local auras = CA._classAuras[playerClassToken]
            if not auras then return end
            for _, aura in ipairs(auras) do
                if aura.cdmBorrow then
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    local auraSpell = auraInfo and auraInfo.spellId
                    local matchesAuraSpell = false
                    if auraSpell then
                        pcall(function()
                            if not issecretvalue(auraSpell) then
                                matchesAuraSpell = (auraSpell == aura.auraSpellId)
                            end
                        end)
                    end
                    if spellID == cdmId or spellID == aura.auraSpellId or matchesAuraSpell then
                        -- Determine activeSpellId from auraInfo.spellId (actual debuff spell)
                        local activeSpell = aura.auraSpellId  -- default to primary
                        if auraInfo and auraInfo.spellId then
                            pcall(function()
                                local infoSpell = auraInfo.spellId
                                if not issecretvalue(infoSpell) then
                                    if infoSpell == aura.auraSpellId then
                                        activeSpell = aura.auraSpellId
                                    elseif aura.linkedSpellIds then
                                        for _, lid in ipairs(aura.linkedSpellIds) do
                                            if infoSpell == lid then activeSpell = lid; break end
                                        end
                                    end
                                end
                            end)
                        end
                        local tracked = auraTracking[aura.id]
                        if not tracked or tracked.auraInstanceID ~= instanceID then
                            auraTracking[aura.id] = { unit = unit, auraInstanceID = instanceID, activeSpellId = activeSpell }
                            CacheAuraIdentity(unit, aura.id, instanceID, activeSpell)
                        end
                        local auraId = aura.id
                        C_Timer.After(0, function()
                            local a = CA._registry[auraId]
                            if a then CA.ScanAura(a) end
                        end)
                        break
                    end
                end
            end
        end)
    end

    -- Hook RefreshData to catch icon pool recycling (for CDM icon alpha re-find)
    local buffMixin = _G.CooldownViewerBuffIconItemMixin
    if buffMixin and buffMixin.RefreshData then
        hooksecurefunc(buffMixin, "RefreshData", function()
            C_Timer.After(0, function() RescanForCDMBorrow() end)
        end)
    end

    -- Hook OnAuraInstanceInfoCleared (for CDM icon alpha re-find)
    local baseMixin = _G.CooldownViewerItemMixin
    if baseMixin and baseMixin.OnAuraInstanceInfoCleared then
        hooksecurefunc(baseMixin, "OnAuraInstanceInfoCleared", function()
            C_Timer.After(0, function() RescanForCDMBorrow() end)
        end)
    end

    -- CooldownFrame_Set/Clear hooks removed -- duration comes from DurationObject API

    cdmBorrow.hookInstalled = true
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

CA._RescanForCDMBorrow = RescanForCDMBorrow
CA._InstallMixinHooks = InstallMixinHooks

-- Expose for debug
CA._cdmBorrow = cdmBorrow
CA._rescanForCDMBorrow = function() RescanForCDMBorrow() end
