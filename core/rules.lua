local addonName, addon = ...

addon.Rules = addon.Rules or {}
local Rules = addon.Rules

local ACTIONS = {}
local SPEC_CACHE = nil
local SPEC_BY_ID = nil

local function ensureProfile()
    local db = addon.db
    local profile = db and db.profile
    if not profile then
        return nil
    end

    profile.rules = profile.rules or {}
    profile.rulesState = profile.rulesState or {}
    profile.rulesState.nextId = profile.rulesState.nextId or 1

    return profile
end

local function getRulesTable()
    local profile = ensureProfile()
    if not profile then
        return {}
    end

    local rules = profile.rules
    if type(rules) ~= "table" then
        rules = {}
        profile.rules = rules
    end

    -- Normalize array holes to keep deterministic ordering
    local cleaned = {}
    for _, entry in ipairs(rules) do
        table.insert(cleaned, entry)
    end
    profile.rules = cleaned
    return cleaned
end

local function getRuleState()
    local profile = ensureProfile()
    local state = profile and profile.rulesState
    if not state then
        return nil
    end
    state.nextId = state.nextId or 1
    return state
end

local function nextRuleId()
    local state = getRuleState()
    if not state then
        return "rule-0001"
    end
    local id = string.format("rule-%04d", state.nextId)
    state.nextId = state.nextId + 1
    return id
end

-- Normalize a value based on the action's valueType
local function normalizeValue(value, valueType)
    if valueType == "boolean" then
        return value and true or false
    elseif valueType == "number" then
        return tonumber(value) or 0
    elseif valueType == "color" then
        -- Color values are tables {r, g, b, a}
        if type(value) == "table" then
            return value
        end
        return { 1, 1, 1, 1 }  -- Default white
    else
        -- For string/dropdown values, return as-is
        return value
    end
end

local function getClassColorHex(fileID)
    local colors = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) or {}
    local color = colors[fileID]
    if not color then
        return "ffffffff"
    end
    local r = math.floor((color.r or 1) * 255 + 0.5)
    local g = math.floor((color.g or 1) * 255 + 0.5)
    local b = math.floor((color.b or 1) * 255 + 0.5)
    return string.format("ff%02x%02x%02x", r, g, b)
end

local function buildSpecCache()
    if SPEC_CACHE then
        return SPEC_CACHE, SPEC_BY_ID
    end
    SPEC_BY_ID = {}
    SPEC_CACHE = {}

    if type(GetNumClasses) ~= "function" or type(GetClassInfo) ~= "function" then
        return SPEC_CACHE, SPEC_BY_ID
    end

    local totalClasses = GetNumClasses()
    for classIndex = 1, totalClasses do
        local className, classFile, classID = GetClassInfo(classIndex)
        if classID then
            local classEntry = {
                classID = classID,
                name = className or ("Class " .. tostring(classIndex)),
                file = classFile,
                colorHex = getClassColorHex(classFile),
                specs = {},
            }

            local count = type(GetNumSpecializationsForClassID) == "function" and GetNumSpecializationsForClassID(classID) or 0
            for specIndex = 1, count do
                local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classID, specIndex)
                if specID then
                    local specEntry = {
                        classID = classID,
                        className = classEntry.name,
                        classColorHex = classEntry.colorHex,
                        file = classFile,
                        specID = specID,
                        name = specName or ("Spec " .. tostring(specIndex)),
                        icon = specIcon,
                    }
                    table.insert(classEntry.specs, specEntry)
                    SPEC_BY_ID[specID] = specEntry
                end
            end

            table.insert(SPEC_CACHE, classEntry)
        end
    end

    table.sort(SPEC_CACHE, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    return SPEC_CACHE, SPEC_BY_ID
end

local function currentSpecID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

local function applyActionValue(actionId, value, reason)
    local handler = ACTIONS[actionId]
    if not handler or not handler.set then
        return
    end
    local ok, changed = pcall(handler.set, value, reason)
    if not ok then
        if addon and addon.Print then
            addon:Print(string.format("Rules: failed to apply %s (%s)", actionId, tostring(ok)))
        end
        return
    end
    if changed and addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
        addon.SettingsPanel.RefreshCurrentCategoryDeferred()
    end
end

local function registerDefaultActions()
    ACTIONS["prdPower.hideBar"] = {
        id = "prdPower.hideBar",
        valueType = "boolean",
        widget = "checkbox",           -- Matches component.settings[settingId].ui.widget
        componentId = "prdPower",      -- For resolving component reference
        settingId = "hideBar",         -- For resolving setting within component
        defaultValue = false,
        path = { "Personal Resource Display", "Power Bar", "Visibility", "Hide Power Bar" },
        -- uiMeta: Additional metadata for control rendering (sliders need min/max/step, dropdowns need values)
        -- For checkbox, no additional uiMeta needed
        get = function()
            local profile = addon.db and addon.db.profile
            local comp = profile and profile.components and profile.components.prdPower
            if comp and comp.hideBar ~= nil then
                return comp.hideBar
            end
            return false
        end,
        set = function(value)
            local profile = addon.db and addon.db.profile
            if not profile then
                return false
            end
            profile.components = profile.components or {}
            profile.components.prdPower = profile.components.prdPower or {}
            local comp = profile.components.prdPower
            if comp.hideBar == value then
                return false
            end
            comp.hideBar = value and true or false
            local component = addon.Components and addon.Components.prdPower
            if component and component.ApplyStyling then
                pcall(component.ApplyStyling, component)
            elseif addon.ApplyStyles then
                addon:ApplyStyles()
            end
            return true
        end,
    }
end

local function ruleMatches(rule, specID)
    if not rule or rule.enabled == false then
        return false
    end
    local trigger = rule.trigger or {}
    if trigger.type ~= "specialization" then
        return false
    end
    local specs = trigger.specIds
    if type(specs) ~= "table" then
        return false
    end
    for _, id in ipairs(specs) do
        if id == specID then
            return true
        end
    end
    return false
end

function Rules:Initialize()
    if self._initialized then
        return
    end

    registerDefaultActions()
    buildSpecCache()

    if addon.db and addon.db.RegisterCallback then
        addon.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
        addon.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
        addon.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
        addon.db.RegisterCallback(self, "OnNewProfile", "OnProfileChanged")
    end

    self._initialized = true
    self._lastSpecID = currentSpecID()
    self:ApplyAll("Initialize")
end

function Rules:IsInitialized()
    return self._initialized and addon.db ~= nil
end

function Rules:GetRules()
    return getRulesTable()
end

function Rules:GetRuleById(ruleId)
    if not ruleId then
        return nil
    end
    for _, rule in ipairs(getRulesTable()) do
        if rule.id == ruleId then
            return rule
        end
    end
    return nil
end

-- Check if a specific rule is currently active (trigger conditions match)
-- This is used by the UI to show visual feedback on which rules are matching
function Rules:IsRuleActive(ruleId)
    if not self:IsInitialized() then
        return false
    end
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return false
    end
    local specID = currentSpecID()
    return ruleMatches(rule, specID)
end

function Rules:CreateRule(opts)
    local rule = {
        id = nextRuleId(),
        enabled = true,
        trigger = {
            type = "specialization",
            specIds = {},
        },
        action = {
            id = nil,  -- No default action; user must select a target
            value = true,
        },
    }

    if opts then
        if opts.triggerType then
            rule.trigger.type = opts.triggerType
        end
        if opts.specIds then
            rule.trigger.specIds = {}
            for _, id in ipairs(opts.specIds) do
                table.insert(rule.trigger.specIds, id)
            end
        end
        if opts.actionId then
            rule.action.id = opts.actionId
            -- Set default value based on action's valueType
            local handler = ACTIONS[opts.actionId]
            if handler then
                rule.action.value = handler.defaultValue
            end
        end
        if opts.value ~= nil then
            local handler = ACTIONS[rule.action.id]
            local valueType = handler and handler.valueType or "boolean"
            rule.action.value = normalizeValue(opts.value, valueType)
        end
    end

    local rules = getRulesTable()
    table.insert(rules, rule)

    self:ApplyAll("CreateRule")
    return rule
end

function Rules:DeleteRule(ruleId)
    if not ruleId then
        return
    end
    local rules = getRulesTable()
    local changed = false
    for index = #rules, 1, -1 do
        if rules[index].id == ruleId then
            table.remove(rules, index)
            changed = true
            break
        end
    end
    if changed then
        self:ApplyAll("DeleteRule")
    end
end

function Rules:SetRuleEnabled(ruleId, enabled)
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return
    end
    local desired = not not enabled
    if rule.enabled == desired then
        return
    end
    rule.enabled = desired
    self:ApplyAll("ToggleRule")
end

function Rules:SetRuleTriggerSpecs(ruleId, specIdList)
    local rule = self:GetRuleById(ruleId)
    if not rule or rule.trigger.type ~= "specialization" then
        return
    end
    local unique = {}
    local ordered = {}
    for _, specID in ipairs(specIdList or {}) do
        if specID and not unique[specID] then
            unique[specID] = true
            table.insert(ordered, specID)
        end
    end
    rule.trigger.specIds = ordered
    self:ApplyAll("UpdateSpecs")
end

function Rules:ToggleRuleSpec(ruleId, specID)
    local rule = self:GetRuleById(ruleId)
    if not rule or rule.trigger.type ~= "specialization" or not specID then
        return
    end
    rule.trigger.specIds = rule.trigger.specIds or {}
    local found = false
    for idx = #rule.trigger.specIds, 1, -1 do
        if rule.trigger.specIds[idx] == specID then
            table.remove(rule.trigger.specIds, idx)
            found = true
            break
        end
    end
    if not found then
        table.insert(rule.trigger.specIds, specID)
        table.sort(rule.trigger.specIds)
    end
    self:ApplyAll("ToggleSpec")
end

function Rules:SetRuleAction(ruleId, actionId)
    local rule = self:GetRuleById(ruleId)
    if not rule or not ACTIONS[actionId] then
        return
    end
    rule.action = rule.action or {}
    rule.action.id = actionId
    -- Reset value to the action's default when switching targets
    rule.action.value = ACTIONS[actionId].defaultValue
    self:ApplyAll("ChangeAction")
end

function Rules:SetRuleActionValue(ruleId, value)
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return
    end
    rule.action = rule.action or {}
    local actionId = rule.action.id
    local handler = ACTIONS[actionId]
    local valueType = handler and handler.valueType or "boolean"
    local normalized = normalizeValue(value, valueType)
    -- For tables (colors), always update since equality check is complex
    if valueType ~= "color" and rule.action.value == normalized then
        return
    end
    rule.action.value = normalized
    self:ApplyAll("ChangeActionValue")
end

function Rules:GetActionMetadata(actionId)
    return ACTIONS[actionId]
end

function Rules:GetAllActions()
    return ACTIONS
end

function Rules:GetActionPathLabel(actionId)
    local action = ACTIONS[actionId]
    if not action or not action.path then
        return "Select Target"
    end
    return table.concat(action.path, " › ")
end

function Rules:GetSpecBuckets()
    local buckets, specById = buildSpecCache()
    return buckets, specById
end

function Rules:GetSpecSummary(rule)
    rule = rule or {}
    local specIds = rule.trigger and rule.trigger.specIds
    if not specIds or #specIds == 0 then
        return "No specs selected"
    end
    local specs = {}
    buildSpecCache()
    for _, specID in ipairs(specIds) do
        local entry = SPEC_BY_ID and SPEC_BY_ID[specID]
        if entry then
            table.insert(specs, entry.name)
        else
            table.insert(specs, tostring(specID))
        end
    end
    table.sort(specs)
    return table.concat(specs, ", ")
end

local function gatherActionMenu()
    local tree = {}
    local function findChild(list, label)
        for _, node in ipairs(list) do
            if node.text == label then
                return node
            end
        end
        return nil
    end

    for _, action in pairs(ACTIONS) do
        local cursor = tree
        for index, label in ipairs(action.path or { action.id }) do
            local node = findChild(cursor, label)
            if not node then
                node = { text = label, children = {} }
                table.insert(cursor, node)
            end
            if index == #action.path then
                node.actionId = action.id
            end
            cursor = node.children
        end
    end

    return tree
end

function Rules:GetActionMenuTree()
    if not self._actionMenuCache then
        self._actionMenuCache = gatherActionMenu()
    end
    return self._actionMenuCache
end

-- Get available options at a given path depth for breadcrumb navigation
-- pathSegments: array of strings representing the path so far (can be empty for level 1)
-- Returns: array of { text = "label", hasChildren = bool }
function Rules:GetActionsAtPath(pathSegments)
    pathSegments = pathSegments or {}
    local depth = #pathSegments

    local results = {}
    local seen = {}

    for _, action in pairs(ACTIONS) do
        local path = action.path
        if path and #path > depth then
            -- Check if this action's path matches our current path prefix
            local matches = true
            for i = 1, depth do
                if path[i] ~= pathSegments[i] then
                    matches = false
                    break
                end
            end

            if matches then
                local nextSegment = path[depth + 1]
                if nextSegment and not seen[nextSegment] then
                    seen[nextSegment] = true
                    -- Check if this segment has children (more path beyond it)
                    local hasChildren = (#path > depth + 1)
                    table.insert(results, {
                        text = nextSegment,
                        hasChildren = hasChildren,
                    })
                end
            end
        end
    end

    -- Sort alphabetically
    table.sort(results, function(a, b)
        return a.text < b.text
    end)

    return results
end

-- Get the actionId for a complete 4-segment path
-- fullPath: array of 4 strings representing the complete path
-- Returns: actionId string or nil if no matching action
function Rules:GetActionIdForPath(fullPath)
    if not fullPath or #fullPath < 1 then
        return nil
    end

    for actionId, action in pairs(ACTIONS) do
        local path = action.path
        if path and #path == #fullPath then
            local matches = true
            for i = 1, #fullPath do
                if path[i] ~= fullPath[i] then
                    matches = false
                    break
                end
            end
            if matches then
                return actionId
            end
        end
    end

    return nil
end

-- Get the path segments for a given actionId
-- Returns: array of path segments or empty array if not found
function Rules:GetActionPath(actionId)
    local action = ACTIONS[actionId]
    if action and action.path then
        return action.path
    end
    return {}
end

function Rules:ApplyAll(reason)
    if not self:IsInitialized() then
        return
    end

    local currentSpec = currentSpecID()
    if currentSpec ~= self._lastSpecID then
        self._lastSpecID = currentSpec
    end

    -- Only apply values for rules that match the current spec.
    -- When no rule matches, the setting stays at its configured value in the main settings.
    local applied = {}
    local rules = getRulesTable()

    for _, rule in ipairs(rules) do
        local actionId = rule.action and rule.action.id
        local handler = ACTIONS[actionId]
        if handler and ruleMatches(rule, currentSpec) then
            local value = rule.action.value
            value = normalizeValue(value, handler.valueType)
            applied[actionId] = value
        end
    end

    for actionId, value in pairs(applied) do
        applyActionValue(actionId, value, reason)
    end
end

function Rules:OnProfileChanged()
    self._actionMenuCache = nil
    buildSpecCache()
    self:ApplyAll("ProfileChanged")
    -- Refresh UI to show the new profile's rules list
    if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
        addon.SettingsPanel.RefreshCurrentCategoryDeferred()
    end
end

function Rules:OnPlayerSpecChanged()
    self._actionMenuCache = nil
    buildSpecCache()
    self:ApplyAll("SpecChanged")
end

function Rules:OnPlayerLogin()
    buildSpecCache()
    self._lastSpecID = currentSpecID()
    self:ApplyAll("Login")
end

return Rules

