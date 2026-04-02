local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- Number Formatting
--------------------------------------------------------------------------------

function DM2._FormatCompact(n)
    if not n or n == 0 then return "0" end
    if n >= 1000000000 then return string.format("%.1fB", n / 1000000000)
    elseif n >= 1000000 then return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then return string.format("%.1fK", n / 1000)
    else return string.format("%.0f", n) end
end

function DM2._FormatDuration(sec)
    if not sec or sec <= 0 then return "0:00" end
    sec = math.floor(sec)
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--------------------------------------------------------------------------------
-- Deaths Aggregation
--
-- Deaths metric returns one entry per death event, not per player.
-- We count occurrences per GUID.
--------------------------------------------------------------------------------

local function CountDeathsPerGUID(deathSession)
    local counts = {}
    if deathSession and deathSession.combatSources then
        for _, source in ipairs(deathSession.combatSources) do
            local guid = source.sourceGUID
            if guid then
                counts[guid] = (counts[guid] or 0) + 1
            end
        end
    end
    return counts
end

--------------------------------------------------------------------------------
-- QueryMergedData — Core data pipeline
--
-- Returns a merged table with all players and their values across all columns.
-- During combat (inCombat=true), only the primary column's meter type is queried.
-- Out of combat, all columns are GUID-correlated.
--------------------------------------------------------------------------------

function DM2._QueryMergedData(sessionType, sessionID, columns, inCombat)
    if not C_DamageMeter then return nil end
    -- Need at least one query API
    if not C_DamageMeter.GetCombatSessionFromType and not C_DamageMeter.GetCombatSessionFromID then
        return nil
    end
    if not columns or #columns == 0 then return nil end

    local FORMATS = DM2.COLUMN_FORMATS

    -- Determine which meter types we need
    local neededTypes
    if inCombat then
        -- Combat: only primary column (all APIs return secret values during combat)
        local def = FORMATS[columns[1].format]
        if not def then return nil end
        neededTypes = {}
        neededTypes[def.primary or def.meterType] = true
    else
        neededTypes = DM2._GetNeededMeterTypes(columns)
    end

    -- Query each meter type (ID-based for specific segments, type-based for Overall/Current)
    local sessions = {}
    for meterType in pairs(neededTypes) do
        local ok, result
        if sessionID then
            ok, result = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
        else
            ok, result = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
        end
        if ok and result then
            sessions[meterType] = result
        end
    end

    -- Get primary session
    local primaryDef = FORMATS[columns[1].format]
    if not primaryDef then return nil end
    local primaryType = primaryDef.primary or primaryDef.meterType
    local primarySession = sessions[primaryType]
    if not primarySession or not primarySession.combatSources or #primarySession.combatSources == 0 then
        return nil
    end

    -- Deaths pre-count (only needed if Deaths column is present and OOC)
    local deathCounts
    if not inCombat and sessions[9] then -- 9 = Deaths
        deathCounts = CountDeathsPerGUID(sessions[9])
    end

    -- Build GUID-keyed lookups for secondary types (OOC only)
    local guidLookups = {}
    if not inCombat then
        for meterType, session in pairs(sessions) do
            if session.combatSources then
                guidLookups[meterType] = {}
                for _, source in ipairs(session.combatSources) do
                    if source.sourceGUID then
                        guidLookups[meterType][source.sourceGUID] = source
                    end
                end
            end
        end
    end

    -- Build merged table
    local merged = {
        playerOrder = {},
        players = {},
        maxAmounts = {},
        durationSeconds = primarySession.durationSeconds,
        sessionType = sessionType,
    }

    -- Collect max amounts per meter type
    for meterType, session in pairs(sessions) do
        merged.maxAmounts[meterType] = session.maxAmount
    end

    -- Iterate primary session (engine-sorted order = rank)
    local seenGUIDs = {}
    for rank, source in ipairs(primarySession.combatSources) do
        -- In combat, sourceGUID is secret — cannot use as table key or compare.
        -- Use rank-based keys and skip duplicate detection entirely.
        local guid = not inCombat and source.sourceGUID or nil
        local key = guid or ("rank_" .. rank)

        -- Skip duplicate GUIDs (OOC only)
        if inCombat or (guid and not seenGUIDs[guid]) then
            if guid then seenGUIDs[guid] = true end

            table.insert(merged.playerOrder, key)

            local player = {
                name = source.name,                   -- secret in combat
                classFilename = source.classFilename, -- NeverSecret
                specIconID = source.specIconID,        -- NeverSecret (may be nil)
                isLocalPlayer = source.isLocalPlayer,  -- NeverSecret
                rank = rank,
                values = {},
            }

            -- Primary column value
            player.values[primaryType] = {
                totalAmount = source.totalAmount,         -- secret in combat
                amountPerSecond = source.amountPerSecond,  -- secret in combat
            }

            -- Deaths special case for primary column
            if primaryDef.isDeaths and deathCounts and guid then
                player.values[primaryType] = {
                    totalAmount = deathCounts[guid] or 0,
                    amountPerSecond = 0,
                }
            end

            -- Secondary columns (OOC only, GUID-correlated)
            if not inCombat and guid then
                for meterType, lookup in pairs(guidLookups) do
                    if meterType ~= primaryType and not player.values[meterType] then
                        local s = lookup[guid]
                        if s then
                            if meterType == 9 and deathCounts then -- Deaths
                                player.values[meterType] = {
                                    totalAmount = deathCounts[guid] or 0,
                                    amountPerSecond = 0,
                                }
                            else
                                player.values[meterType] = {
                                    totalAmount = s.totalAmount,
                                    amountPerSecond = s.amountPerSecond,
                                }
                            end
                        end
                    end
                end
            end

            merged.players[key] = player
        end
    end

    return merged
end

--------------------------------------------------------------------------------
-- Unified number abbreviation (same function used OOC and in combat)
-- Uses AbbreviateNumbers with custom 1K breakpoints for consistency.
--
-- Known limitation: sub-1K amountPerSecond floats (e.g. 423.519) display with
-- raw decimal precision. The C++ AbbreviateNumbers implementation does not
-- round floating-point inputs at the base breakpoint (breakpoint=1,
-- fractionDivisor=1). During combat these values are secrets, so Lua-side
-- rounding (math.floor, string.format) is impossible. Fixing OOC only would
-- create a visible format change on combat transition. Accepted as a
-- limitation of the 12.0 secret value system.
--------------------------------------------------------------------------------

local _abbrevOpts = nil
local function UnifiedAbbreviate(value)
    if not _abbrevOpts and CreateAbbreviateConfig then
        local ok, config = pcall(CreateAbbreviateConfig, {
            { breakpoint = 1000000000, abbreviation = "B", fractionDivisor = 100000000 },
            { breakpoint = 1000000, abbreviation = "M", fractionDivisor = 100000 },
            { breakpoint = 1000, abbreviation = "K", fractionDivisor = 100 },
            { breakpoint = 1, abbreviation = "", fractionDivisor = 1, abbreviationIsGlobal = false },
        })
        if ok and config then _abbrevOpts = { config = config } end
    end
    if AbbreviateNumbers then
        local ok, result = pcall(AbbreviateNumbers, value, _abbrevOpts)
        if ok then return result end
    end
    -- Fallback: try custom formatter (only works on plain numbers, not secrets)
    local fmtOk, fmtResult = pcall(DM2._FormatCompact, value)
    if fmtOk then return fmtResult end
    -- Ultimate fallback: return raw value (SetText will handle secrets)
    return value
end

DM2._UnifiedAbbreviate = UnifiedAbbreviate

--------------------------------------------------------------------------------
-- Format a column value for display (works both OOC and combat)
--------------------------------------------------------------------------------

function DM2._FormatColumnValue(player, formatKey)
    local def = DM2.COLUMN_FORMATS[formatKey]
    if not def then return "" end

    if def.primary then
        -- Combo format: "50K (1.6M)"
        local pVal = player.values[def.primary]
        local sVal = player.values[def.secondary]
        local pNum = pVal and pVal[def.primaryField] or 0
        local sNum = sVal and sVal[def.secondaryField] or 0
        return UnifiedAbbreviate(pNum) .. " (" .. UnifiedAbbreviate(sNum) .. ")"
    end

    -- Simple format
    local val = player.values[def.meterType]
    if not val then return "-" end
    return UnifiedAbbreviate(val[def.valueField] or 0)
end

--- Returns the raw numeric value for a column (used for bar fill).
function DM2._GetColumnValue(player, formatKey)
    local def = DM2.COLUMN_FORMATS[formatKey]
    if not def then return 0 end
    local meterType = def.primary or def.meterType
    local val = player.values[meterType]
    if not val then return 0 end
    return val[def.valueField or "totalAmount"] or 0
end

--- Returns the max amount for a column's meter type.
function DM2._GetColumnMax(mergedData, formatKey)
    local def = DM2.COLUMN_FORMATS[formatKey]
    if not def then return 1 end
    local meterType = def.primary or def.meterType
    return mergedData.maxAmounts[meterType] or 1
end
