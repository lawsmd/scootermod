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
