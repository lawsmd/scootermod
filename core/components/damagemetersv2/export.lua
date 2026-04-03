local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- V2 Export Pipeline
--------------------------------------------------------------------------------

--- Build a meter type array from a window's column config for columnsOverride.
function DM2._GetColumnMeterTypes(windowConfig)
    if not windowConfig or not windowConfig.columns then return nil end
    local types = {}
    local seen = {}
    for _, col in ipairs(windowConfig.columns) do
        local def = DM2.COLUMN_FORMATS[col.format]
        if def then
            local mt = def.primary or def.meterType
            if not seen[mt] then
                seen[mt] = true
                table.insert(types, mt)
            end
            if def.secondary and not seen[def.secondary] then
                seen[def.secondary] = true
                table.insert(types, def.secondary)
            end
        end
    end
    return #types > 0 and types or nil
end

--- Export window data to the High Score arcade display.
function DM2._ExportToWindow(windowIndex)
    if InCombatLockdown() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg then return end

    local sessionType = cfg.sessionType or 0
    local primaryMeterType = DM2._GetPrimaryMeterType(cfg)

    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    if addon.ShowHighScoreWindow then
        addon.ShowHighScoreWindow(data)
    end
end

--- Export window data to chat.
function DM2._ExportToChat(windowIndex)
    if InCombatLockdown() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg then return end
    local comp = DM2._comp
    if not comp then return end

    local sessionType = cfg.sessionType or 0
    local primaryMeterType = DM2._GetPrimaryMeterType(cfg)
    local channel = comp.db.exportChatChannel or "PARTY"
    local lineCount = comp.db.exportChatLineCount or 5

    -- Use the shared export function if available, otherwise fall back to direct gather+send
    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    -- Build messages
    local messages = {}
    local headerName = data.columnNames[1] or "DPS"
    table.insert(messages, string.format("Scoot - %s (%s) [%s]:", headerName, data.sessionLabel, data.FormatDuration(data.duration)))

    local count = math.min(lineCount, #data.playerOrder)
    for i = 1, count do
        local guid = data.playerOrder[i]
        local p = data.players[guid]
        local mt = data.columns[1]
        local val = data.GetDisplayValue(guid, mt)
        local info = addon.FormatPlayerSpecInfo(p)
        local nameStr = info and (p.name .. " " .. info) or p.name
        table.insert(messages, string.format("#%d. %s - %s", i, nameStr, val))
    end

    for _, msg in ipairs(messages) do
        SendChatMessage(msg, channel)
    end
end

--- Export to a specific chat channel with specified line count.
function DM2._ExportToChatChannel(windowIndex, channel, lineCount)
    if InCombatLockdown() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg then return end

    local sessionType = cfg.sessionType or 0
    local primaryMeterType = DM2._GetPrimaryMeterType(cfg)
    lineCount = lineCount or 5

    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    local messages = {}
    local headerName = data.columnNames[1] or "DPS"
    table.insert(messages, string.format("Scoot - %s (%s) [%s]:", headerName, data.sessionLabel, data.FormatDuration(data.duration)))

    local count = math.min(lineCount, #data.playerOrder)
    for i = 1, count do
        local guid = data.playerOrder[i]
        local p = data.players[guid]
        local mt = data.columns[1]
        local val = data.GetDisplayValue(guid, mt)
        local info = addon.FormatPlayerSpecInfo(p)
        local nameStr = info and (p.name .. " " .. info) or p.name
        table.insert(messages, string.format("#%d. %s - %s", i, nameStr, val))
    end

    for _, msg in ipairs(messages) do
        SendChatMessage(msg, channel)
    end
end
