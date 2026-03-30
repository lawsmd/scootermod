-- modules.lua - Component-level module toggle system
-- Provides per-category enable/disable toggles that gate initialization.
-- Disabled modules never register event handlers, install hooks, or create proxy DBs.
local _, addon = ...

--------------------------------------------------------------------------------
-- Component ID → Category Mapping
--------------------------------------------------------------------------------

local COMPONENT_TO_CATEGORY = {
    -- Action Bars
    actionBar1 = "actionBars", actionBar2 = "actionBars", actionBar3 = "actionBars",
    actionBar4 = "actionBars", actionBar5 = "actionBars", actionBar6 = "actionBars",
    actionBar7 = "actionBars", actionBar8 = "actionBars",
    microBar = "actionBars", stanceBar = "actionBars", petBar = "actionBars",
    -- Buffs/Debuffs
    buffs = "buffsDebuffs", debuffs = "buffsDebuffs",
    -- Cooldown Manager
    essentialCooldowns = "cooldownManager", utilityCooldowns = "cooldownManager",
    trackedBuffs = "cooldownManager", trackedBars = "cooldownManager",
    customGroup1 = "cooldownManager", customGroup2 = "cooldownManager",
    customGroup3 = "cooldownManager", customGroup4 = "cooldownManager",
    customGroup5 = "cooldownManager",
    -- Damage Meter
    damageMeter = "damageMeter",
    damageMeterV2 = "damageMeter",
    -- Extra Abilities
    extraAbilities = "extraAbilities",
    -- Minimap
    minimapStyle = "minimap",
    -- Notes
    notes = "notes",
    -- Objective Tracker
    objectiveTracker = "objectiveTracker",
    -- Personal Resource Display
    prdGlobal = "prd", prdHealth = "prd", prdPower = "prd", prdClassResource = "prd",
    -- Scrolling Combat Text
    sctDamage = "sct",
    -- Tooltip
    tooltip = "tooltip",
}

--- Returns the module category for a component ID.
--- Handles dynamic class aura IDs (classAura_*) via prefix check.
function addon:GetComponentCategory(componentId)
    if not componentId then return nil end
    local cat = COMPONENT_TO_CATEGORY[componentId]
    if cat then return cat end
    if componentId:sub(1, 10) == "classAura_" then
        return "classAuras"
    end
    return nil
end

--------------------------------------------------------------------------------
-- Category Definitions (for UI)
--------------------------------------------------------------------------------

addon.MODULE_CATEGORY_ORDER = {
    "actionBars",
    "buffsDebuffs",
    "classAuras",
    "cooldownManager",
    "damageMeter",
    "extraAbilities",
    "groupFrames",
    "minimap",
    "notes",
    "objectiveTracker",
    "prd",
    "sct",
    "tooltip",
    "unitFrames",
}

addon.MODULE_CATEGORIES = {
    actionBars = {
        label = "Action Bars",
        subToggles = {
            { id = "actionBar1", label = "Action Bar 1" },
            { id = "actionBar2", label = "Action Bar 2" },
            { id = "actionBar3", label = "Action Bar 3" },
            { id = "actionBar4", label = "Action Bar 4" },
            { id = "actionBar5", label = "Action Bar 5" },
            { id = "actionBar6", label = "Action Bar 6" },
            { id = "actionBar7", label = "Action Bar 7" },
            { id = "actionBar8", label = "Action Bar 8" },
            { id = "microBar", label = "Micro Bar" },
            { id = "petBar", label = "Pet Bar" },
            { id = "stanceBar", label = "Stance Bar" },
        },
    },
    buffsDebuffs = {
        label = "Buffs/Debuffs",
        subToggles = {
            { id = "buffs", label = "Buffs" },
            { id = "debuffs", label = "Debuffs" },
        },
    },
    classAuras = {
        label = "Class Auras",
        -- No sub-toggles on Start Here (dynamic per-class aura IDs)
    },
    cooldownManager = {
        label = "Cooldown Manager",
        subToggles = {
            { id = "essentialCooldowns", label = "Essential Cooldowns" },
            { id = "utilityCooldowns", label = "Utility Cooldowns" },
            { id = "trackedBuffs", label = "Tracked Buffs" },
            { id = "trackedBars", label = "Tracked Bars" },
            { id = "customGroup1", label = "Custom Group 1" },
            { id = "customGroup2", label = "Custom Group 2" },
            { id = "customGroup3", label = "Custom Group 3" },
            { id = "customGroup4", label = "Custom Group 4" },
            { id = "customGroup5", label = "Custom Group 5" },
        },
    },
    damageMeter = {
        label = "Damage Meter",
        mutuallyExclusive = true, -- only one sub-toggle can be ON at a time
        subToggles = {
            { id = "damageMeter", label = "Blizzard Overlay" },
            { id = "damageMeterV2", label = "Custom Frames" },
        },
    },
    extraAbilities = {
        label = "Extra Abilities",
    },
    groupFrames = {
        label = "Group Frames",
        subToggles = {
            { id = "party", label = "Party" },
            { id = "raid", label = "Raid" },
            { id = "auraTracking", label = "Aura Tracking" },
        },
    },
    minimap = {
        label = "Minimap",
    },
    notes = {
        label = "Notes",
    },
    objectiveTracker = {
        label = "Objective Tracker",
    },
    prd = {
        label = "Personal Resource Display",
    },
    sct = {
        label = "Scrolling Combat Text",
    },
    tooltip = {
        label = "Tooltip",
    },
    unitFrames = {
        label = "Unit Frames",
        subToggles = {
            { id = "Player", label = "Player" },
            { id = "Target", label = "Target" },
            { id = "TargetOfTarget", label = "Target of Target" },
            { id = "Focus", label = "Focus" },
            { id = "FocusTarget", label = "Target of Focus" },
            { id = "Pet", label = "Pet" },
            { id = "Boss", label = "Boss" },
        },
    },
}

--------------------------------------------------------------------------------
-- IsModuleEnabled / SetModuleEnabled
--------------------------------------------------------------------------------

--- Check if a module category (and optionally a sub-toggle) is enabled.
--- Returns true for absent keys (upgrade compatibility / fresh installs).
function addon:IsModuleEnabled(category, subId)
    local profile = self.db and self.db.profile
    if not profile then return true end
    local me = profile.moduleEnabled
    if not me then return true end

    local val = me[category]
    if val == nil then return true end     -- absent key = enabled
    if val == false then return false end  -- master off
    if val == true then return true end    -- master on, no sub-toggles

    -- Table form: master + sub-toggles
    if type(val) == "table" then
        if val._enabled == false then return false end  -- master off
        if subId then
            local sub = val[subId]
            return sub == nil or sub == true        -- absent sub = enabled
        end
        return true
    end
    return true
end

--- Set a module toggle value. Handles boolean→table transition for sub-toggles.
function addon:SetModuleEnabled(category, subId, value)
    local profile = self.db and self.db.profile
    if not profile then return end
    if not profile.moduleEnabled then
        profile.moduleEnabled = {}
    end
    local me = profile.moduleEnabled

    if not subId then
        -- Master toggle
        if type(me[category]) == "table" then
            me[category]._enabled = value
        else
            me[category] = value
        end
    else
        -- Sub-toggle: ensure table form
        local current = me[category]
        if type(current) ~= "table" then
            local wasEnabled = current ~= false
            me[category] = { _enabled = wasEnabled }
            current = me[category]
            -- Initialize all sub-toggles to true (preserve current state)
            local catDef = self.MODULE_CATEGORIES[category]
            if catDef and catDef.subToggles then
                for _, sub in ipairs(catDef.subToggles) do
                    current[sub.id] = true
                end
            end
        end
        current[subId] = value
    end
end
