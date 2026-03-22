local addonName, addon = ...

--[[----------------------------------------------------------------------------
    Class Auras: UNIT_AURA event counter (lightweight diagnostic)

    Purpose:
      Tracks how many UNIT_AURA events fire per unit token since login/reload.
      Displayed in the Class Auras debug dump to confirm events are reaching us.
----------------------------------------------------------------------------]]--

local caUnitAuraCounts = {}   -- [unitToken] = count
local caUnitAuraFrame = CreateFrame("Frame")
caUnitAuraFrame:RegisterEvent("UNIT_AURA")
caUnitAuraFrame:SetScript("OnEvent", function(_, _, unit)
    if unit then
        caUnitAuraCounts[unit] = (caUnitAuraCounts[unit] or 0) + 1
    end
end)

--[[----------------------------------------------------------------------------
    Class Auras debug dump

    Purpose:
      Diagnostic dump for the Class Auras system, showing registered auras,
      CDM borrow state, and CDM Tracked Buffs probe results.

    Usage:
      /scoot debug classauras
      /scoot debug ca
----------------------------------------------------------------------------]]--

function addon.DebugDumpClassAuras()
    local CA = addon.ClassAuras
    if not CA then
        addon.DebugShowWindow("Class Auras Debug", "Class Auras module not loaded.")
        return
    end

    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== Class Auras Debug ===")
    push("")

    -- Player info
    local _, playerClass = UnitClass("player")
    push("Player Class: " .. tostring(playerClass))

    -- Target info
    local targetName = UnitName("target")
    local targetGUID = UnitGUID("target")
    if targetName and targetGUID then
        push("Current Target: " .. tostring(targetName) .. " (GUID: " .. tostring(targetGUID) .. ")")
    else
        push("Current Target: No Target")
    end

    -- Secret restrictions
    local hasSecrets = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
    push("Secrets Restricted: " .. tostring(hasSecrets or false))
    push("In Combat: " .. tostring(InCombatLockdown()))

    -- CDM Borrow state
    local cdmBorrowState = CA._cdmBorrow
    push("CDM Borrow Hooks Installed: " .. tostring(cdmBorrowState and cdmBorrowState.hookInstalled or false))
    push("")

    -- Registered auras
    local classAuras = CA._classAuras and CA._classAuras[playerClass]
    if not classAuras or #classAuras == 0 then
        push("--- No Registered Auras for " .. tostring(playerClass) .. " ---")
    else
        push("--- Registered Auras ---")
        push("")

        for _, aura in ipairs(classAuras) do
            push("[" .. tostring(aura.id) .. "] " .. tostring(aura.label))

            -- Aura definition
            push("  spellId: " .. tostring(aura.auraSpellId) .. " | cdmSpellId: " .. tostring(aura.cdmSpellId or "same as auraSpellId") .. " | unit: " .. tostring(aura.unit) .. " | filter: " .. tostring(aura.filter))

            -- DB state
            local comp = addon.Components and addon.Components["classAura_" .. aura.id]
            local db = comp and comp.db
            push("  enabled: " .. tostring(db and db.enabled))

            -- Container state
            local state = CA._activeAuras and CA._activeAuras[aura.id]
            if state and state.container then
                local shown = state.container:IsShown()
                local scale = state.container:GetScale()
                push("  container: exists, shown=" .. tostring(shown) .. ", scale=" .. tostring(scale))

                -- Position
                local ok, point, _, _, x, y = pcall(state.container.GetPoint, state.container, 1)
                if ok and point then
                    push("  position: " .. tostring(point) .. " " .. tostring(math.floor((x or 0) + 0.5)) .. ", " .. tostring(math.floor((y or 0) + 0.5)))
                else
                    push("  position: unknown")
                end

                -- Element state
                if state.elements then
                    for _, elem in ipairs(state.elements) do
                        if elem.type == "text" then
                            local textOk, text = pcall(function() return elem.widget:GetText() end)
                            local textStr = (not textOk and "<error>") or (issecretvalue and issecretvalue(text) and "<SECRET>") or tostring(text or "")
                            push("  text element [" .. tostring(elem.def.source or "?") .. "]: " .. textStr)
                        elseif elem.type == "texture" then
                            push("  texture element: shown=" .. tostring(elem.widget:IsShown()))
                        end
                    end
                end
            else
                push("  container: NOT created")
            end

            -- CDM Borrow state
            push("  cdmBorrow: " .. tostring(aura.cdmBorrow or false))
            if aura.cdmBorrow then
                local itemFrame = CA._rescanForCDMBorrow and nil -- don't trigger rescan
                -- Read-only probe for CDM item
                pcall(function()
                    local viewer = _G.BuffIconCooldownViewer
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    if viewer then
                        local children = { viewer:GetChildren() }
                        for _, child in ipairs(children) do
                            local idOk, childSpellId = pcall(function() return child:GetBaseSpellID() end)
                            if idOk and childSpellId == cdmId then
                                local shown = child:IsShown()
                                push("  CDM icon found: YES (shown=" .. tostring(shown) .. ")")
                                return
                            end
                        end
                    end
                    push("  CDM icon found: NO — Ensure the spell (or its passive) is in CDM > Tracked Buffs")
                end)
            end

            push("")
        end
    end

    -- ================================================================
    -- CDM Viewer Full Dump — list ALL items with all spell ID fields
    -- ================================================================
    push("")
    push("--- CDM Viewer Full Dump ---")
    push("")

    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
        local viewer = _G[viewerName]
        if not viewer then
            push("[" .. viewerName .. "] NOT FOUND (global is nil)")
        else
            push("[" .. viewerName .. "]")
            local ok, children = pcall(function() return { viewer:GetChildren() } end)
            if not ok then
                push("  GetChildren() FAILED: " .. tostring(children))
            elseif not children or #children == 0 then
                push("  No children (empty viewer)")
            else
                push("  Children count: " .. #children)
                -- Secret-safe tostring: returns "<SECRET>" instead of propagating taint
                local function safeStr(val)
                    if issecretvalue and issecretvalue(val) then return "<SECRET>" end
                    return tostring(val)
                end

                for i, child in ipairs(children) do
                    local line = "  [" .. i .. "] "

                    -- GetBaseSpellID (plain table read: cooldownInfo.spellID)
                    local baseOk, baseId = pcall(function() return child:GetBaseSpellID() end)
                    if baseOk then
                        line = line .. "baseSpellID=" .. safeStr(baseId)
                    else
                        line = line .. "baseSpellID=ERROR"
                    end

                    -- GetSpellID (resolution chain: aura → linked → override → base)
                    local spellOk, spellId = pcall(function() return child:GetSpellID() end)
                    if spellOk then
                        line = line .. " | spellID=" .. safeStr(spellId)
                    else
                        line = line .. " | spellID=ERROR"
                    end

                    -- cooldownInfo deep dump (plain table reads)
                    local ciOk, ciDump = pcall(function()
                        local ci = child:GetCooldownInfo()
                        if not ci then return "nil" end
                        local parts = {}
                        table.insert(parts, "spellID=" .. safeStr(ci.spellID))
                        if ci.linkedSpellIDs then
                            local ids = {}
                            for _, lid in ipairs(ci.linkedSpellIDs) do
                                table.insert(ids, safeStr(lid))
                            end
                            table.insert(parts, "linkedSpellIDs={" .. table.concat(ids, ",") .. "}")
                        end
                        if ci.linkedSpellID then
                            table.insert(parts, "linkedSpellID=" .. safeStr(ci.linkedSpellID))
                        end
                        if ci.overrideSpellID then
                            table.insert(parts, "overrideSpellID=" .. safeStr(ci.overrideSpellID))
                        end
                        if ci.overrideTooltipSpellID then
                            table.insert(parts, "overrideTooltipSpellID=" .. safeStr(ci.overrideTooltipSpellID))
                        end
                        return table.concat(parts, " | ")
                    end)
                    if ciOk and type(ciDump) == "string" then
                        line = line .. " | ci={" .. ciDump .. "}"
                    end

                    -- Shown state
                    local shownOk, isShown = pcall(child.IsShown, child)
                    if shownOk then
                        line = line .. " | shown=" .. tostring(isShown)
                    end

                    push(line)
                end
            end
        end
        push("")
    end

    -- Match tries (replay the exact logic from FindCDMItemForSpell)
    push("--- Match Replay for Registered Auras ---")
    push("")
    if classAuras then
        for _, aura in ipairs(classAuras) do
            if aura.cdmBorrow then
                local cdmId = aura.cdmSpellId or aura.auraSpellId
                push("[" .. aura.id .. "] Searching for cdmSpellId=" .. tostring(aura.cdmSpellId) .. ", auraSpellId=" .. tostring(aura.auraSpellId))

                -- Replay primary search (per-child pcall so one secret doesn't abort the loop)
                local primaryFrame = nil
                for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
                    local viewer = _G[viewerName]
                    if viewer then
                        local childOk, children = pcall(function() return { viewer:GetChildren() } end)
                        if childOk and children then
                            for ci, child in ipairs(children) do
                                local idOk, baseId = pcall(function() return child:GetBaseSpellID() end)
                                if idOk then
                                    local isSecret = issecretvalue and issecretvalue(baseId)
                                    if isSecret then
                                        push("  " .. viewerName .. " child[" .. ci .. "] baseSpellID=<SECRET> — skipped")
                                    elseif baseId == cdmId then
                                        push("  PRIMARY MATCH: " .. viewerName .. " child[" .. ci .. "] baseSpellID=" .. tostring(baseId) .. " == " .. tostring(cdmId))
                                        primaryFrame = child
                                    end
                                end
                            end
                        end
                    end
                end
                if not primaryFrame then
                    push("  PRIMARY: no match for " .. tostring(cdmId))
                end

                -- Replay fallback search
                if not primaryFrame and aura.cdmSpellId and aura.auraSpellId then
                    local fallbackFrame = nil
                    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
                        local viewer = _G[viewerName]
                        if viewer then
                            local childOk, children = pcall(function() return { viewer:GetChildren() } end)
                            if childOk and children then
                                for ci, child in ipairs(children) do
                                    local idOk, baseId = pcall(function() return child:GetBaseSpellID() end)
                                    if idOk then
                                        local isSecret = issecretvalue and issecretvalue(baseId)
                                        if isSecret then
                                            -- already reported above
                                        elseif baseId == aura.auraSpellId then
                                            push("  FALLBACK MATCH: " .. viewerName .. " child[" .. ci .. "] baseSpellID=" .. tostring(baseId) .. " == " .. tostring(aura.auraSpellId))
                                            fallbackFrame = child
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not fallbackFrame then
                        push("  FALLBACK: no match for " .. tostring(aura.auraSpellId))
                    end
                end
                push("")
            end
        end
    end

    -- safePush: guards against secret/tainted values leaking into the lines table.
    -- tostring(secret) produces a tainted string that passes normal string ops
    -- but fails in table.concat. Use table.concat itself as the definitive test.
    local function safePush(s)
        local ok = pcall(function()
            if type(s) ~= "string" then s = tostring(s) end
            table.concat({s}) -- definitive test: fails on tainted strings
        end)
        if ok and type(s) == "string" then
            table.insert(lines, s)
        else
            table.insert(lines, "<secret value>")
        end
    end

    -- ================================================================
    -- UNIT_AURA Event Counter
    -- ================================================================
    safePush("")
    safePush("--- UNIT_AURA Event Counter (since reload) ---")
    safePush("")
    local hasAny = false
    for unit, count in pairs(caUnitAuraCounts) do
        safePush("  " .. tostring(unit) .. ": " .. tostring(count) .. " events")
        hasAny = true
    end
    if not hasAny then
        safePush("  (no UNIT_AURA events received yet)")
    end

    -- ================================================================
    -- A. ForEachAura Probe
    -- ================================================================
    safePush("")
    safePush("--- ForEachAura Probe ---")
    safePush("")

    -- Test ForEachAura directly
    local feaOk, feaErr = pcall(function()
        AuraUtil.ForEachAura("target", "HARMFUL", nil, function(auraData)
            return true -- stop after first
        end)
    end)
    safePush("AuraUtil.ForEachAura(target, HARMFUL): " .. (feaOk and "OK" or ("FAILED: " .. tostring(feaErr))))

    -- Test GetAuraSlots directly to isolate the failure point
    local gasOk, gasErr = pcall(function()
        if C_UnitAuras and C_UnitAuras.GetAuraSlots then
            local slots = C_UnitAuras.GetAuraSlots("target", "HARMFUL")
            return slots
        end
        return "API not found"
    end)
    if gasOk then
        safePush("C_UnitAuras.GetAuraSlots(target, HARMFUL): OK (returned: " .. type(gasErr) .. ")")
    else
        safePush("C_UnitAuras.GetAuraSlots(target, HARMFUL): FAILED: " .. tostring(gasErr))
    end

    -- ================================================================
    -- B. Alternative API Probes
    -- ================================================================
    safePush("")
    safePush("--- Alternative API Probes ---")
    safePush("")

    -- Probe: GetAuraDataByIndex (AllowedWhenTainted)
    safePush("[GetAuraDataByIndex] Scanning target HARMFUL slots 1-40:")
    local gadiFound = 0
    local gadiSpell1221389 = false
    for i = 1, 40 do
        local ok, result = pcall(function()
            return C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL")
        end)
        if ok and result then
            gadiFound = gadiFound + 1
            local spellOk, spellId = pcall(function() return result.spellId end)
            local nameOk, spellName = pcall(function() return result.name end)
            local stackOk, stacks = pcall(function() return result.applications end)

            local isSecretSpell = spellOk and issecretvalue and issecretvalue(spellId)
            local isSecretName = nameOk and issecretvalue and issecretvalue(spellName)
            local isSecretStack = stackOk and issecretvalue and issecretvalue(stacks)

            local spellIdStr = (not spellOk and "<error>") or (isSecretSpell and "<SECRET>") or tostring(spellId)
            local nameStr = (not nameOk and "<error>") or (isSecretName and "<SECRET>") or tostring(spellName)
            local stackStr = (not stackOk and "<error>") or (isSecretStack and "<SECRET>") or tostring(stacks)

            safePush("  [" .. i .. "] spellId=" .. spellIdStr .. (isSecretSpell and " (SECRET)" or "") .. " name=" .. nameStr .. " stacks=" .. stackStr)

            -- Check for our target spell
            if spellOk and not isSecretSpell then
                pcall(function()
                    if spellId == 1221389 then gadiSpell1221389 = true end
                end)
            end
        elseif ok then
            break -- nil result = no more auras
        else
            safePush("  [" .. i .. "] ERROR: " .. tostring(result))
            break
        end
    end
    safePush("  Total found: " .. gadiFound .. " | Spell 1221389 found: " .. tostring(gadiSpell1221389))

    -- Probe: GetDebuffDataByIndex (AllowedWhenTainted)
    safePush("")
    safePush("[GetDebuffDataByIndex] Scanning target PLAYER slots 1-40:")
    local gddiFound = 0
    local gddiSpell1221389 = false
    for i = 1, 40 do
        local ok, result = pcall(function()
            return C_UnitAuras.GetDebuffDataByIndex("target", i, "PLAYER")
        end)
        if ok and result then
            gddiFound = gddiFound + 1
            local spellOk, spellId = pcall(function() return result.spellId end)
            local nameOk, spellName = pcall(function() return result.name end)
            local stackOk, stacks = pcall(function() return result.applications end)

            local isSecretSpell = spellOk and issecretvalue and issecretvalue(spellId)
            local isSecretName = nameOk and issecretvalue and issecretvalue(spellName)
            local isSecretStack = stackOk and issecretvalue and issecretvalue(stacks)

            local spellIdStr = (not spellOk and "<error>") or (isSecretSpell and "<SECRET>") or tostring(spellId)
            local nameStr = (not nameOk and "<error>") or (isSecretName and "<SECRET>") or tostring(spellName)
            local stackStr = (not stackOk and "<error>") or (isSecretStack and "<SECRET>") or tostring(stacks)

            safePush("  [" .. i .. "] spellId=" .. spellIdStr .. (isSecretSpell and " (SECRET)" or "") .. " name=" .. nameStr .. " stacks=" .. stackStr)

            if spellOk and not isSecretSpell then
                pcall(function()
                    if spellId == 1221389 then gddiSpell1221389 = true end
                end)
            end
        elseif ok then
            break
        else
            safePush("  [" .. i .. "] ERROR: " .. tostring(result))
            break
        end
    end
    safePush("  Total found: " .. gddiFound .. " | Spell 1221389 found: " .. tostring(gddiSpell1221389))

    -- Probe: GetUnitAuraBySpellID (AllowedWhenTainted + RequiresNonSecretAura)
    safePush("")
    safePush("[GetUnitAuraBySpellID] Direct lookup for spell 1221389 on target:")
    local byIdOk, byIdResult = pcall(function()
        return C_UnitAuras.GetUnitAuraBySpellID("target", 1221389)
    end)
    if byIdOk then
        if byIdResult then
            local nameOk, spellName = pcall(function() return byIdResult.name end)
            local stackOk, stacks = pcall(function() return byIdResult.applications end)
            local nameStr = (not nameOk and "<error>") or (issecretvalue and issecretvalue(spellName) and "<SECRET>") or tostring(spellName)
            local stackStr = (not stackOk and "<error>") or (issecretvalue and issecretvalue(stacks) and "<SECRET>") or tostring(stacks)
            safePush("  Result: FOUND | name=" .. nameStr .. " stacks=" .. stackStr)

            -- Check if fields are secret
            local fields = { "spellId", "name", "applications", "duration", "expirationTime" }
            local secretFields = {}
            for _, field in ipairs(fields) do
                pcall(function()
                    local val = byIdResult[field]
                    if val ~= nil and issecretvalue and issecretvalue(val) then
                        table.insert(secretFields, field)
                    end
                end)
            end
            if #secretFields > 0 then
                safePush("  Secret fields: " .. table.concat(secretFields, ", "))
            else
                safePush("  Secret fields: none detected")
            end
        else
            safePush("  Result: nil (aura not present or API returned nothing)")
        end
    else
        safePush("  Result: FAILED: " .. tostring(byIdResult))
    end

    -- ================================================================
    -- CDM Tracked Buffs Probe
    -- ================================================================
    safePush("")
    safePush("--- CDM Tracked Buffs Probe ---")
    safePush("")

    -- Check BuffIconCooldownViewer existence
    local cdmViewer = _G.BuffIconCooldownViewer
    safePush("BuffIconCooldownViewer: " .. (cdmViewer and "exists" or "NOT FOUND"))

    if cdmViewer then
        -- Enumerate children
        local cdmChildrenOk, cdmChildren = pcall(function() return { cdmViewer:GetChildren() } end)
        if cdmChildrenOk and cdmChildren then
            safePush("Children count: " .. tostring(#cdmChildren))
            safePush("")

            local freezingFound = false
            for i, child in ipairs(cdmChildren) do
                -- GetBaseSpellID() probe
                local spellIdOk, spellId = pcall(function() return child:GetBaseSpellID() end)
                local isSecret = spellIdOk and issecretvalue and issecretvalue(spellId)
                local spellIdStr = (not spellIdOk and "<error>") or (isSecret and "<SECRET>") or tostring(spellId)

                -- cooldownInfo.spellID direct table access probe
                local directOk, directSpellId = pcall(function()
                    return child.cooldownInfo and child.cooldownInfo.spellID
                end)
                local isDirectSecret = directOk and issecretvalue and issecretvalue(directSpellId)
                local directStr = (not directOk and "<error>") or (isDirectSecret and "<SECRET>") or tostring(directSpellId)

                -- GetApplicationsFontString() probe
                local fsOk, appFS = pcall(function() return child:GetApplicationsFontString() end)
                local fsStr = fsOk and (appFS and "exists" or "nil") or "<error>"

                -- Applications text GetText() probe
                local textStr = "<N/A>"
                if fsOk and appFS then
                    local textOk, text = pcall(function() return appFS:GetText() end)
                    if textOk then
                        local textSecretCheck = false
                        pcall(function()
                            if issecretvalue and text and issecretvalue(text) then
                                textSecretCheck = true
                            end
                        end)
                        if textSecretCheck then
                            textStr = "<SECRET>"
                        else
                            textStr = tostring(text or "")
                        end
                    else
                        textStr = "<error: " .. tostring(text) .. ">"
                    end
                end

                -- IsShown() probe
                local shownOk, isShown = pcall(function() return child:IsShown() end)
                local shownStr = shownOk and tostring(isShown) or "<error>"

                safePush("  [" .. i .. "] GetBaseSpellID()=" .. spellIdStr .. (isSecret and " (SECRET)" or "") ..
                    " | direct=" .. directStr ..
                    " | AppFS=" .. fsStr ..
                    " | text=" .. textStr ..
                    " | shown=" .. shownStr)

                -- Check for Freezing (1221389)
                if spellIdOk and not isSecret then
                    pcall(function()
                        if spellId == 1221389 then
                            freezingFound = true
                            safePush("    ^^ FREEZING (1221389) MATCH ^^")
                        end
                    end)
                end
            end

            safePush("")
            safePush("Freezing (1221389) found in CDM: " .. tostring(freezingFound))
        else
            safePush("GetChildren() failed: " .. tostring(cdmChildren))
        end
    end

    -- Mixin globals check
    safePush("")
    safePush("Mixin globals:")
    safePush("  CooldownViewerBuffIconItemMixin: " .. ((_G.CooldownViewerBuffIconItemMixin and "EXISTS") or "NOT FOUND"))
    safePush("  CooldownViewerItemMixin: " .. ((_G.CooldownViewerItemMixin and "EXISTS") or "NOT FOUND"))

    local buffMixin = _G.CooldownViewerBuffIconItemMixin
    if buffMixin then
        safePush("  .RefreshData: " .. (buffMixin.RefreshData and "exists" or "NOT FOUND"))
        safePush("  .GetBaseSpellID: " .. (buffMixin.GetBaseSpellID and "exists" or "NOT FOUND"))
        safePush("  .GetApplicationsFontString: " .. (buffMixin.GetApplicationsFontString and "exists" or "NOT FOUND"))
    end

    local baseMixin = _G.CooldownViewerItemMixin
    if baseMixin then
        safePush("  .OnAuraInstanceInfoCleared: " .. (baseMixin.OnAuraInstanceInfoCleared and "exists" or "NOT FOUND"))
    end

    -- ================================================================
    -- C. Secret Predicate Checks
    -- ================================================================
    safePush("")
    safePush("--- Secret Predicate Checks ---")
    safePush("")

    local hasRestrictions = false
    pcall(function()
        hasRestrictions = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
    end)
    safePush("C_Secrets.HasSecretRestrictions(): " .. tostring(hasRestrictions))

    local aurasSecret = "N/A"
    pcall(function()
        if C_Secrets and C_Secrets.ShouldAurasBeSecret then
            aurasSecret = tostring(C_Secrets.ShouldAurasBeSecret())
        end
    end)
    safePush("C_Secrets.ShouldAurasBeSecret(): " .. aurasSecret)

    local issecretAvailable = (type(issecretvalue) == "function") and "yes" or "no"
    safePush("issecretvalue() available: " .. issecretAvailable)

    addon.DebugShowWindow("Class Auras Debug", table.concat(lines, "\n"))
end
