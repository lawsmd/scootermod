local addonName, addon = ...

--------------------------------------------------------------------------------
-- /scoot debug dmv2 cvar — Test 1: CVar data collection
--------------------------------------------------------------------------------

function addon.DebugDMV2CVar()
    if InCombatLockdown() then
        addon:Print("Cannot toggle CVar during combat.")
        return
    end

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        addon:Print("C_DamageMeter API not available.")
        return
    end

    local current = C_CVar.GetCVar("damageMeterEnabled")

    -- First run: CVar is "1" → set to "0" and instruct user
    if current ~= "0" then
        C_CVar.SetCVar("damageMeterEnabled", "0")
        addon:Print("DMV2 CVar Test: Set damageMeterEnabled = 0")
        addon:Print("  Blizzard meter is now hidden.")
        addon:Print("  1) Enter combat (dungeon trash or target dummy)")
        addon:Print("  2) After combat ends, run: /scoot debug dmv2 cvar")
        return
    end

    -- Second run: CVar is "0" → check data, restore, report
    local lines = { "== DMV2 CVar Test ==" }
    table.insert(lines, "CVar was: 0 (Blizzard meter disabled)")

    C_CVar.SetCVar("damageMeterEnabled", "1")
    table.insert(lines, "Restored CVar to: 1")
    table.insert(lines, "")

    local sessionTests = {
        { label = "Overall",  type = Enum.DamageMeterSessionType.Overall },
        { label = "Current",  type = Enum.DamageMeterSessionType.Current },
    }

    local anyData = false
    for _, test in ipairs(sessionTests) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, test.type, Enum.DamageMeterType.DamageDone)
        table.insert(lines, test.label .. " (DamageDone):")
        if not ok or not session then
            table.insert(lines, "  Query failed or returned nil")
        else
            local sourceCount = session.combatSources and #session.combatSources or 0
            table.insert(lines, "  combatSources count: " .. sourceCount)
            table.insert(lines, "  maxAmount: " .. tostring(session.maxAmount))
            table.insert(lines, "  totalAmount: " .. tostring(session.totalAmount))
            table.insert(lines, "  durationSeconds: " .. tostring(session.durationSeconds))
            if sourceCount > 0 then
                anyData = true
                table.insert(lines, "  RESULT: DATA COLLECTED WITH CVAR=0")
            else
                table.insert(lines, "  RESULT: NO DATA (0 sources)")
            end
        end
        table.insert(lines, "")
    end

    if anyData then
        table.insert(lines, "VERDICT: Safe to use CVar disable strategy for V2.")
        table.insert(lines, "  Setting damageMeterEnabled=0 hides the Blizzard UI but the")
        table.insert(lines, "  engine continues collecting combat data via C_DamageMeter.")
    else
        table.insert(lines, "VERDICT: CVar kills data collection — need fallback strategy.")
        table.insert(lines, "  V2 must keep CVar=1 and hide Blizzard's frame via")
        table.insert(lines, "  off-screen positioning or scale trick.")
    end

    addon.DebugShowWindow("DMV2 CVar Test", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- /scoot debug dmv2 api — Tests 2-4: sourceGUID secrecy, SetText, SetValue
--------------------------------------------------------------------------------

-- Reusable hidden test frame (created once, reused across calls)
local testFrame, testBar, testText

local function EnsureTestFrame()
    if testFrame then return end
    testFrame = CreateFrame("Frame", nil, UIParent)
    testFrame:SetSize(200, 20)
    testFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -10000) -- off-screen
    testFrame:Hide()

    testBar = CreateFrame("StatusBar", nil, testFrame)
    testBar:SetSize(180, 16)
    testBar:SetPoint("CENTER")

    testText = testBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    testText:SetPoint("CENTER")
end

local function TestSecret(value)
    -- issecretvalue may not exist on all builds
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        if ok then return result end
    end
    -- Fallback: try tostring — secrets error on tostring in some contexts
    -- but type() always works. If issecretvalue isn't available, we can't be sure.
    return nil -- unknown
end

local function FormatSecretResult(isSecret)
    if isSecret == true then return "true"
    elseif isSecret == false then return "false"
    else return "unknown (issecretvalue not available)"
    end
end

local function FormatSafeValue(value, isSecret)
    if isSecret == true then return "(secret)" end
    if value == nil then return "nil" end
    return tostring(value)
end

local function RunAPITests()
    local lines = { "== DMV2 API Secrecy Test ==" }
    local inCombat = InCombatLockdown()

    if inCombat then
        table.insert(lines, "Run context: IN COMBAT (results are meaningful)")
    else
        table.insert(lines, "Run context: OUT OF COMBAT (all values non-secret)")
        table.insert(lines, "  Re-run during combat for real secrecy test.")
    end
    table.insert(lines, "")

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        table.insert(lines, "ERROR: C_DamageMeter API not available.")
        return lines
    end

    -- Query two different meter types
    local ok1, sessionDmg = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
    local ok2, sessionHeal = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.HealingDone)

    if not ok1 or not sessionDmg or not sessionDmg.combatSources or #sessionDmg.combatSources == 0 then
        table.insert(lines, "ERROR: No DamageDone data available. Fight something first.")
        if not ok1 then table.insert(lines, "  pcall error: " .. tostring(sessionDmg)) end
        return lines
    end

    local dmgSources = sessionDmg.combatSources
    local healSources = (ok2 and sessionHeal and sessionHeal.combatSources) or {}

    table.insert(lines, string.format("DamageDone sources: %d | HealingDone sources: %d",
        #dmgSources, #healSources))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test 2: Field secrecy on first source
    --------------------------------------------------------------------------
    table.insert(lines, "--- Field Secrecy (DamageDone, source 1) ---")

    local src = dmgSources[1]
    local fields = {
        { name = "sourceGUID",      value = src.sourceGUID,      expected = "unknown" },
        { name = "name",            value = src.name,            expected = "ConditionalSecret" },
        { name = "totalAmount",     value = src.totalAmount,     expected = "secret in combat" },
        { name = "amountPerSecond", value = src.amountPerSecond, expected = "secret in combat" },
        { name = "classFilename",   value = src.classFilename,   expected = "NeverSecret" },
        { name = "specIconID",      value = src.specIconID,      expected = "NeverSecret" },
        { name = "isLocalPlayer",   value = src.isLocalPlayer,   expected = "NeverSecret" },
        { name = "deathRecapID",    value = src.deathRecapID,    expected = "NeverSecret" },
    }

    for _, f in ipairs(fields) do
        local isSecret = TestSecret(f.value)
        local safeVal = FormatSafeValue(f.value, isSecret)
        table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s  (%s)",
            f.name .. ":", type(f.value), FormatSecretResult(isSecret), safeVal, f.expected))
    end
    table.insert(lines, "")

    -- Also test session-level maxAmount
    table.insert(lines, "--- Session-Level Fields ---")
    local maxSecret = TestSecret(sessionDmg.maxAmount)
    table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s",
        "maxAmount:", type(sessionDmg.maxAmount), FormatSecretResult(maxSecret),
        FormatSafeValue(sessionDmg.maxAmount, maxSecret)))
    local totalSecret = TestSecret(sessionDmg.totalAmount)
    table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s",
        "totalAmount:", type(sessionDmg.totalAmount), FormatSecretResult(totalSecret),
        FormatSafeValue(sessionDmg.totalAmount, totalSecret)))
    local durSecret = TestSecret(sessionDmg.durationSeconds)
    table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s",
        "durationSeconds:", type(sessionDmg.durationSeconds), FormatSecretResult(durSecret),
        FormatSafeValue(sessionDmg.durationSeconds, durSecret)))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test 2b: Cross-session GUID correlation
    --------------------------------------------------------------------------
    table.insert(lines, "--- Cross-Session GUID Correlation ---")

    local guidA = src.sourceGUID

    -- Table key test
    local okKey, errKey = pcall(function()
        local t = {}
        t[guidA] = true
        return t[guidA]
    end)
    if okKey then
        table.insert(lines, "  Table key with sourceGUID:   OK (can use as table key)")
    else
        table.insert(lines, "  Table key with sourceGUID:   FAILED — " .. tostring(errKey))
    end

    -- Cross-session comparison
    if #healSources > 0 then
        local guidB = healSources[1].sourceGUID
        local okCmp, errCmp = pcall(function()
            return guidA == guidB
        end)
        if okCmp then
            table.insert(lines, "  Cross-session GUID compare:  OK (comparison succeeded)")
        else
            table.insert(lines, "  Cross-session GUID compare:  FAILED — " .. tostring(errCmp))
        end

        -- Try building a lookup from one and accessing from the other
        local okLookup, errLookup = pcall(function()
            local lookup = {}
            for _, s in ipairs(dmgSources) do
                if s.sourceGUID then lookup[s.sourceGUID] = s end
            end
            local found = 0
            for _, s in ipairs(healSources) do
                if s.sourceGUID and lookup[s.sourceGUID] then found = found + 1 end
            end
            return found
        end)
        if okLookup then
            table.insert(lines, string.format("  GUID lookup (dmg→heal):      OK (%s matches found)", tostring(errLookup)))
        else
            table.insert(lines, "  GUID lookup (dmg→heal):      FAILED — " .. tostring(errLookup))
        end
    else
        table.insert(lines, "  Cross-session compare:       SKIPPED (no HealingDone data)")
        table.insert(lines, "  GUID lookup (dmg→heal):      SKIPPED (no HealingDone data)")
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Tests 3-4: SetText and SetValue on Scoot-owned frames
    --------------------------------------------------------------------------
    table.insert(lines, "--- Scoot-Owned Frame Tests ---")

    EnsureTestFrame()

    -- SetMinMaxValues with potentially secret maxAmount
    local okMM, errMM = pcall(function()
        testBar:SetMinMaxValues(0, sessionDmg.maxAmount)
    end)
    table.insert(lines, string.format("  SetMinMaxValues(0, maxAmount):  %s",
        okMM and "OK" or ("FAILED — " .. tostring(errMM))))

    -- SetValue with secret totalAmount
    local okSV, errSV = pcall(function()
        testBar:SetValue(src.totalAmount)
    end)
    table.insert(lines, string.format("  SetValue(totalAmount):          %s",
        okSV and "OK" or ("FAILED — " .. tostring(errSV))))

    -- SetText with secret name
    local okTN, errTN = pcall(function()
        testText:SetText(src.name)
    end)
    table.insert(lines, string.format("  SetText(name):                  %s",
        okTN and "OK" or ("FAILED — " .. tostring(errTN))))

    -- SetText with secret totalAmount (number → display)
    local okTA, errTA = pcall(function()
        testText:SetText(src.totalAmount)
    end)
    table.insert(lines, string.format("  SetText(totalAmount):           %s",
        okTA and "OK" or ("FAILED — " .. tostring(errTA))))

    -- SetText with secret amountPerSecond
    local okAPS, errAPS = pcall(function()
        testText:SetText(src.amountPerSecond)
    end)
    table.insert(lines, string.format("  SetText(amountPerSecond):       %s",
        okAPS and "OK" or ("FAILED — " .. tostring(errAPS))))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Verdict
    --------------------------------------------------------------------------
    table.insert(lines, "--- VERDICT ---")

    local guidSecret = TestSecret(guidA)
    local guidKeyWorks = okKey
    local guidCmpWorks = (#healSources > 0) and (select(1, pcall(function() return guidA == (healSources[1].sourceGUID) end))) or nil

    if guidSecret == false or (guidKeyWorks and guidCmpWorks) then
        table.insert(lines, "  sourceGUID: NeverSecret (or usable as key/comparable)")
        table.insert(lines, "    -> Strategy C: full multi-column live updates during combat")
    elseif guidSecret == true or (not guidKeyWorks) then
        table.insert(lines, "  sourceGUID: Secret during combat")
        table.insert(lines, "    -> Strategy A: primary column only during combat,")
        table.insert(lines, "       full refresh on combat end")
    else
        table.insert(lines, "  sourceGUID: INCONCLUSIVE (run during combat to get definitive answer)")
    end

    local frameTestsOK = okMM and okSV and okTN and okTA and okAPS
    if frameTestsOK then
        table.insert(lines, "  SetText/SetValue on Scoot frames: All OK")
    else
        table.insert(lines, "  SetText/SetValue on Scoot frames: SOME FAILED (see above)")
    end

    return lines
end

function addon.DebugDMV2API()
    local lines = RunAPITests()
    local output = table.concat(lines, "\n")

    if InCombatLockdown() then
        addon:Print("DMV2 API test collected. Results will show after combat ends.")
        -- Defer showing the window to avoid taint from UI creation during combat
        local waitFrame = CreateFrame("Frame")
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        waitFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            addon.DebugShowWindow("DMV2 API Secrecy Test", output)
        end)
    else
        addon.DebugShowWindow("DMV2 API Secrecy Test", output)
    end
end

--------------------------------------------------------------------------------
-- /scoot debug dmv2 fields — Exhaustive mid-combat field dump
-- Purpose: find any non-secret identifier that could correlate players across
-- meter types during combat (solving the rank-drift problem).
--------------------------------------------------------------------------------

local ALL_METER_TYPES = {
    { key = "DamageDone",           enum = Enum.DamageMeterType.DamageDone },
    { key = "Dps",                  enum = Enum.DamageMeterType.Dps },
    { key = "HealingDone",          enum = Enum.DamageMeterType.HealingDone },
    { key = "Hps",                  enum = Enum.DamageMeterType.Hps },
    { key = "Absorbs",              enum = Enum.DamageMeterType.Absorbs },
    { key = "Interrupts",           enum = Enum.DamageMeterType.Interrupts },
    { key = "Dispels",              enum = Enum.DamageMeterType.Dispels },
    { key = "DamageTaken",          enum = Enum.DamageMeterType.DamageTaken },
    { key = "AvoidableDamageTaken", enum = Enum.DamageMeterType.AvoidableDamageTaken },
    { key = "Deaths",               enum = Enum.DamageMeterType.Deaths },
    { key = "EnemyDamageTaken",     enum = Enum.DamageMeterType.EnemyDamageTaken },
}

local KNOWN_FIELDS = {
    "sourceGUID", "sourceCreatureID", "name", "classFilename", "specIconID",
    "totalAmount", "amountPerSecond", "isLocalPlayer", "deathRecapID",
    "deathTimeSeconds", "classification",
}

local function FieldSecrecy(value)
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        if ok then return result end
    end
    return nil
end

local function SafeDisplay(value, isSecret)
    if isSecret == true then return "(secret)" end
    if value == nil then return "nil" end
    return tostring(value)
end

local function RunFieldsDump()
    local lines = { "== DMV2 Exhaustive Field Dump ==" }
    local inCombat = InCombatLockdown()

    if inCombat then
        table.insert(lines, "Context: IN COMBAT — secrecy results are meaningful")
    else
        table.insert(lines, "Context: OUT OF COMBAT — all values non-secret")
        table.insert(lines, "  Re-run DURING COMBAT for real results.")
    end
    table.insert(lines, "")

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        table.insert(lines, "ERROR: C_DamageMeter API not available.")
        return lines
    end

    --------------------------------------------------------------------------
    -- Section 1: All fields on every source, every meter type
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 1: Per-Source Field Dump (Overall)")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    -- Collect sessions and track non-secret fields for later analysis
    local sessionsByType = {}
    local nonSecretFields = {}  -- { fieldName = { count, exampleValue } }

    for _, mt in ipairs(ALL_METER_TYPES) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Overall, mt.enum)
        if ok and session and session.combatSources and #session.combatSources > 0 then
            sessionsByType[mt.key] = session
            table.insert(lines, string.format("--- %s (%d sources) ---", mt.key, #session.combatSources))

            for srcIdx, src in ipairs(session.combatSources) do
                table.insert(lines, string.format("  Source #%d:", srcIdx))
                for _, fieldName in ipairs(KNOWN_FIELDS) do
                    local val = src[fieldName]
                    local isSecret = FieldSecrecy(val)
                    local marker = ""
                    if val ~= nil and isSecret == false then
                        marker = "  *** NON-SECRET ***"
                        if not nonSecretFields[fieldName] then
                            nonSecretFields[fieldName] = { count = 0, values = {} }
                        end
                        nonSecretFields[fieldName].count = nonSecretFields[fieldName].count + 1
                        table.insert(nonSecretFields[fieldName].values, { meterType = mt.key, srcIdx = srcIdx, value = val })
                    end
                    table.insert(lines, string.format("    %-20s type=%-8s secret=%-6s value=%s%s",
                        fieldName, type(val), tostring(isSecret), SafeDisplay(val, isSecret), marker))
                end
            end
            table.insert(lines, "")
        end
    end

    if not next(sessionsByType) then
        table.insert(lines, "ERROR: No session data for any meter type. Fight something first.")
        return lines
    end

    --------------------------------------------------------------------------
    -- Section 2: sourceCreatureID correlation test
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 2: sourceCreatureID Correlation")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    local cidInfo = nonSecretFields["sourceCreatureID"]
    if not cidInfo or cidInfo.count == 0 then
        table.insert(lines, "sourceCreatureID: NOT non-secret (or nil on all sources)")
        table.insert(lines, "  Cannot use as combat correlator.")
    else
        table.insert(lines, string.format("sourceCreatureID: non-secret on %d source(s)", cidInfo.count))
        table.insert(lines, "")

        -- Table key test
        local testVal = cidInfo.values[1].value
        local okKey, errKey = pcall(function()
            local t = {}
            t[testVal] = true
            return t[testVal]
        end)
        table.insert(lines, string.format("  Table key test: %s",
            okKey and "OK — can use as table key" or ("FAILED — " .. tostring(errKey))))

        -- Uniqueness within DamageDone
        local dmgSession = sessionsByType["DamageDone"]
        if dmgSession then
            local cidSet = {}
            local dupes = 0
            local nilCount = 0
            for _, src in ipairs(dmgSession.combatSources) do
                local cid = src.sourceCreatureID
                local cidSecret = FieldSecrecy(cid)
                if cid == nil then
                    nilCount = nilCount + 1
                elseif cidSecret == false then
                    local okStr, cidStr = pcall(tostring, cid)
                    if okStr then
                        if cidSet[cidStr] then dupes = dupes + 1
                        else cidSet[cidStr] = true end
                    end
                end
            end
            table.insert(lines, string.format("  Uniqueness in DamageDone: %d unique, %d duplicates, %d nil",
                (function() local n = 0; for _ in pairs(cidSet) do n = n + 1 end; return n end)(),
                dupes, nilCount))
        end

        -- Cross-metric stability: same player → same creatureID across types?
        table.insert(lines, "")
        table.insert(lines, "  Cross-metric creatureID stability:")
        local dmgLookup = {}
        if dmgSession then
            for i, src in ipairs(dmgSession.combatSources) do
                local cid = src.sourceCreatureID
                local cidSecret = FieldSecrecy(cid)
                if cid ~= nil and cidSecret == false then
                    local okConv, cidKey = pcall(tostring, cid)
                    if okConv then
                        dmgLookup[cidKey] = { index = i, classFilename = src.classFilename }
                    end
                end
            end
        end

        local healSession = sessionsByType["HealingDone"]
        if healSession and next(dmgLookup) then
            local matches = 0
            local misses = 0
            for _, src in ipairs(healSession.combatSources) do
                local cid = src.sourceCreatureID
                local cidSecret = FieldSecrecy(cid)
                if cid ~= nil and cidSecret == false then
                    local okConv, cidKey = pcall(tostring, cid)
                    if okConv then
                        local dmgEntry = dmgLookup[cidKey]
                        if dmgEntry then
                            matches = matches + 1
                            table.insert(lines, string.format("    MATCH: creatureID=%s  dmg_class=%s  heal_class=%s",
                                cidKey, tostring(dmgEntry.classFilename), tostring(src.classFilename)))
                        else
                            misses = misses + 1
                        end
                    end
                end
            end
            table.insert(lines, string.format("    Total: %d matches, %d unmatched heal sources", matches, misses))
        else
            table.insert(lines, "    SKIPPED — need both DamageDone and HealingDone data")
        end
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Section 3: Composite key feasibility
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 3: Composite Key Feasibility")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    local dmgSession = sessionsByType["DamageDone"]
    if dmgSession then
        local classSet = {}
        local classSpecSet = {}
        local totalSources = #dmgSession.combatSources
        for _, src in ipairs(dmgSession.combatSources) do
            local cls = src.classFilename
            local spec = src.specIconID
            local clsSecret = FieldSecrecy(cls)
            local specSecret = FieldSecrecy(spec)
            if clsSecret == false then
                classSet[tostring(cls)] = true
                if specSecret == false and spec ~= nil then
                    classSpecSet[tostring(cls) .. ":" .. tostring(spec)] = true
                end
            end
        end
        local uniqueClass = 0
        for _ in pairs(classSet) do uniqueClass = uniqueClass + 1 end
        local uniqueClassSpec = 0
        for _ in pairs(classSpecSet) do uniqueClassSpec = uniqueClassSpec + 1 end

        table.insert(lines, string.format("  Total sources: %d", totalSources))
        table.insert(lines, string.format("  Unique classFilename values: %d", uniqueClass))
        table.insert(lines, string.format("  Unique classFilename+specIconID combos: %d", uniqueClassSpec))
        if uniqueClassSpec == totalSources then
            table.insert(lines, "  RESULT: classFilename+specIconID IS unique — viable composite key for this group")
        elseif uniqueClass == totalSources then
            table.insert(lines, "  RESULT: classFilename alone IS unique — viable for this group (but fragile in raids)")
        else
            table.insert(lines, "  RESULT: NOT unique — composite key insufficient for this group")
        end

        -- classification values
        table.insert(lines, "")
        table.insert(lines, "  classification values seen:")
        for _, src in ipairs(dmgSession.combatSources) do
            local c = src.classification
            local cSecret = FieldSecrecy(c)
            table.insert(lines, string.format("    class=%s  classification=%s  secret=%s",
                tostring(src.classFilename), SafeDisplay(c, cSecret), tostring(cSecret)))
        end
    else
        table.insert(lines, "  SKIPPED — no DamageDone data")
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Section 4: Raw pairs() dump — discover undocumented fields
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 4: Raw Table Keys (pairs() dump)")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    if dmgSession and dmgSession.combatSources and #dmgSession.combatSources > 0 then
        local src = dmgSession.combatSources[1]
        table.insert(lines, "DamageDone source #1 — all keys via pairs():")
        local okPairs, errPairs = pcall(function()
            local keys = {}
            for k, v in pairs(src) do
                local kSecret = FieldSecrecy(k)
                local vSecret = FieldSecrecy(v)
                table.insert(keys, {
                    key = SafeDisplay(k, kSecret),
                    keyType = type(k),
                    keySecret = tostring(kSecret),
                    valType = type(v),
                    valSecret = tostring(vSecret),
                    valDisplay = SafeDisplay(v, vSecret),
                })
            end
            return keys
        end)
        if okPairs then
            for _, entry in ipairs(errPairs) do
                local marker = (entry.valSecret == "false") and "  *** NON-SECRET ***" or ""
                table.insert(lines, string.format("  key=%-22s ktype=%-8s vtype=%-8s vsecret=%-6s val=%s%s",
                    entry.key, entry.keyType, entry.valType, entry.valSecret, entry.valDisplay, marker))
            end
        else
            table.insert(lines, "  pairs() FAILED — " .. tostring(errPairs))
            table.insert(lines, "  (table may be secret-protected)")
        end

        -- Also try the session-level table
        table.insert(lines, "")
        table.insert(lines, "DamageDone session — all keys via pairs():")
        local okSPairs, errSPairs = pcall(function()
            local keys = {}
            for k, v in pairs(dmgSession) do
                local kSecret = FieldSecrecy(k)
                local vSecret = FieldSecrecy(v)
                if k ~= "combatSources" then -- skip the big array
                    table.insert(keys, {
                        key = SafeDisplay(k, kSecret),
                        keyType = type(k),
                        valType = type(v),
                        valSecret = tostring(vSecret),
                        valDisplay = SafeDisplay(v, vSecret),
                    })
                else
                    table.insert(keys, {
                        key = "combatSources",
                        keyType = "string",
                        valType = "table",
                        valSecret = "n/a",
                        valDisplay = string.format("(table, %d entries)", #v),
                    })
                end
            end
            return keys
        end)
        if okSPairs then
            for _, entry in ipairs(errSPairs) do
                table.insert(lines, string.format("  key=%-22s ktype=%-8s vtype=%-8s vsecret=%-6s val=%s",
                    entry.key, entry.keyType, entry.valType, entry.valSecret, entry.valDisplay))
            end
        else
            table.insert(lines, "  pairs() FAILED — " .. tostring(errSPairs))
        end
    else
        table.insert(lines, "  SKIPPED — no DamageDone data")
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Summary verdict
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SUMMARY")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    local potentialCorrelators = {}
    for fieldName, info in pairs(nonSecretFields) do
        -- Only interesting if it's not one of the already-known NeverSecret display fields
        if fieldName ~= "classFilename" and fieldName ~= "specIconID"
            and fieldName ~= "isLocalPlayer" and fieldName ~= "deathRecapID"
            and fieldName ~= "classification" then
            table.insert(potentialCorrelators, string.format("%s (non-secret on %d sources)", fieldName, info.count))
        end
    end

    if #potentialCorrelators > 0 then
        table.insert(lines, "POTENTIAL NEW CORRELATORS FOUND:")
        for _, desc in ipairs(potentialCorrelators) do
            table.insert(lines, "  -> " .. desc)
        end
        table.insert(lines, "")
        table.insert(lines, "Next step: verify uniqueness and cross-metric stability above.")
    else
        if inCombat then
            table.insert(lines, "NO new non-secret identifiers found during combat.")
            table.insert(lines, "Gray-out mitigation remains the production approach.")
        else
            table.insert(lines, "Run this command DURING COMBAT for meaningful results.")
        end
    end

    -- Always list which known NeverSecret fields were confirmed
    table.insert(lines, "")
    table.insert(lines, "Confirmed NeverSecret fields (already known):")
    for _, fieldName in ipairs({"classFilename", "specIconID", "isLocalPlayer", "deathRecapID", "classification"}) do
        local info = nonSecretFields[fieldName]
        if info then
            table.insert(lines, string.format("  %s — non-secret on %d sources", fieldName, info.count))
        end
    end

    return lines
end

function addon.DebugDMV2Fields()
    local lines = RunFieldsDump()
    local output = table.concat(lines, "\n")

    if InCombatLockdown() then
        addon:Print("DMV2 field dump collected. Results will show after combat ends.")
        local waitFrame = CreateFrame("Frame")
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        waitFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            addon.DebugShowWindow("DMV2 Field Dump", output)
        end)
    else
        addon.DebugShowWindow("DMV2 Field Dump", output)
    end
end
