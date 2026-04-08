-- damagemetersv2/combat.lua - Combat mode transitions, segment snapshots, post-combat refresh
local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- Combat Mode Transitions
--------------------------------------------------------------------------------

function DM2._EnterCombatMode()
    DM2._inCombat = true
    DM2._combatStartTime = GetTime()

    for i = 1, DM2.MAX_WINDOWS do
        local win = DM2._windows[i]
        if win and win.mergedData then
            win._preCombatDuration = win.mergedData.durationSeconds or 0
            win.cachedSecondary = win.mergedData
        end
        -- Dim secondary column headers to signal stale data
        if win then
            for c = 2, DM2.MAX_COLUMNS do
                local ch = win.columnHeaders[c]
                if ch then ch:SetTextColor(0.5, 0.5, 0.5, 0.7); ch:SetAlpha(0.5) end
            end
        end
    end
end

function DM2._ExitCombatMode()
    DM2._inCombat = false
    DM2._combatStartTime = 0
    -- Full refresh happens synchronously from REGEN_ENABLED handler
end

--------------------------------------------------------------------------------
-- Combat Update — Primary column only, secret values
--------------------------------------------------------------------------------

function DM2._UpdateWindowCombat(windowIndex)
    local win = DM2._windows[windowIndex]
    if not win or not win.frame:IsShown() then return end

    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg or not cfg.enabled then return end

    local comp = DM2._comp
    if not comp then return end

    -- Query merged data in combat mode (primary column only for type-based sessions)
    local merged = DM2._QueryMergedData(cfg.sessionType, cfg.sessionID, cfg.columns, true)
    if not merged then return end

    -- Store combat merged data (primary column only)
    win.mergedData = merged

    -- Refresh the bar rows display
    DM2._RefreshBarRows(windowIndex, comp)

    -- Update header timer
    DM2._UpdateTimerText(windowIndex)
end

--------------------------------------------------------------------------------
-- OOC Full Update — All columns, GUID-correlated
--------------------------------------------------------------------------------

function DM2._UpdateWindowOOC(windowIndex)
    local win = DM2._windows[windowIndex]
    if not win or not win.frame:IsShown() then return end

    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg or not cfg.enabled then return end

    local comp = DM2._comp
    if not comp then return end

    -- Query merged data OOC (all columns, GUID correlated)
    local merged = DM2._QueryMergedData(cfg.sessionType, cfg.sessionID, cfg.columns, false)
    if not merged then
        -- No data — clear display
        win.mergedData = nil
        DM2._RefreshBarRows(windowIndex, comp)
        DM2._UpdateTimerText(windowIndex)
        return
    end

    win.mergedData = merged
    win.cachedSecondary = nil -- stale cache cleared on fresh data

    -- Refresh display
    DM2._RefreshBarRows(windowIndex, comp)
    DM2._UpdateTimerText(windowIndex)
end

--------------------------------------------------------------------------------
-- Full Refresh All Windows — Called SYNCHRONOUSLY from REGEN_ENABLED
--------------------------------------------------------------------------------

function DM2._FullRefreshAllWindows()
    if not DM2._initialized then return end

    -- Restore secondary column header colors (dimmed during combat)
    local db = DM2._comp and DM2._comp.db
    if db then
        local headerStyle = db.textHeaders or {}
        local useCustom = headerStyle.colorMode == "custom" and headerStyle.color
        for i = 1, DM2.MAX_WINDOWS do
            local win = DM2._windows[i]
            if win then
                for c = 1, DM2.MAX_COLUMNS do
                    local ch = win.columnHeaders[c]
                    if ch then
                        ch:SetAlpha(1)
                        if useCustom then
                            local hc = headerStyle.color
                            ch:SetTextColor(hc[1] or 0.8, hc[2] or 0.8, hc[3] or 0.8, hc[4] or 1)
                        else
                            ch:SetTextColor(0.8, 0.8, 0.8, 1)
                        end
                    end
                end
            end
        end
    end

    for i = 1, DM2.MAX_WINDOWS do
        local cfg = DM2._GetWindowConfig(i)
        if cfg and cfg.enabled then
            DM2._UpdateWindowOOC(i)
        end
    end
end

--------------------------------------------------------------------------------
-- Update All Windows (throttled, called from event handler)
--------------------------------------------------------------------------------

function DM2._UpdateAllWindows()
    if not DM2._initialized then return end

    local inCombat = DM2._inCombat
    for i = 1, DM2.MAX_WINDOWS do
        local cfg = DM2._GetWindowConfig(i)
        if cfg and cfg.enabled then
            if inCombat then
                DM2._UpdateWindowCombat(i)
            else
                DM2._UpdateWindowOOC(i)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Timer Text
--------------------------------------------------------------------------------

function DM2._UpdateTimerText(windowIndex)
    local win = DM2._windows[windowIndex]
    if not win then return end

    local cfg = DM2._GetWindowConfig(windowIndex)
    if not cfg then return end

    local label = DM2._GetSessionLabel(cfg.sessionType, cfg.sessionID, cfg._sessionName)
    local duration

    if cfg.sessionID then
        -- Specific segment: fixed duration (use cached pre-combat value during combat)
        if DM2._inCombat then
            duration = win._preCombatDuration or 0
        else
            duration = win.mergedData and win.mergedData.durationSeconds
        end
    elseif DM2._inCombat then
        -- Use stopwatch during combat
        local elapsed = GetTime() - DM2._combatStartTime
        local preCombat = win._preCombatDuration or 0
        -- For Overall, add pre-combat duration. For Current, just use elapsed.
        if cfg.sessionType == 0 then -- Overall
            duration = preCombat + elapsed
        else
            duration = elapsed
        end
    else
        -- OOC: read from merged data (authoritative)
        duration = win.mergedData and win.mergedData.durationSeconds
    end

    -- Compute timer string early (needed for title width calculation)
    local comp = DM2._comp
    local db = comp and comp.db
    local timerStr = ""
    if duration and duration > 0 then
        timerStr = "[" .. DM2._FormatDuration(duration) .. "]"
    end
    if win.timerText then
        win.timerText:SetText(timerStr)
    end

    -- Update title text
    local isVertical = db and db.verticalTitleMode

    if isVertical and win.verticalTitle then
        -- Vertical title: stack characters vertically, all caps
        local stacked = label:upper():gsub(".", "%1\n"):sub(1, -2)
        win.verticalTitle:SetText(stacked)
        win.verticalTitle:Show()
        if win.titleText then
            win.titleText:SetText("")
            win.titleText:SetWidth(0)
        end
        win.header:SetHeight(DM2.HEADER_HEIGHT)
    else
        if win.verticalTitle then win.verticalTitle:Hide() end
        if win.titleText then
            local isSegment = cfg.sessionID ~= nil
            if isSegment then
                -- Calculate available title width to prevent column header overlap
                local fw = tonumber(cfg.frameWidth or (db and db.frameWidth)) or 350

                -- Right boundary: before the visible column header text
                local rightBound
                local ch = win.columnHeaders and win.columnHeaders[1]
                if ch and ch:IsShown() then
                    local chW = ch:GetStringWidth()
                    rightBound = (chW and chW > 0) and (fw - chW - 12) or (fw - 60)
                else
                    rightBound = fw - 8
                end

                -- Reserve space for timer text
                local timerW = 0
                if timerStr ~= "" and win.timerText then
                    timerW = (win.timerText:GetStringWidth() or 0) + 8
                end

                local maxTitleWidth = rightBound - 26 - timerW
                if maxTitleWidth < 40 then maxTitleWidth = 40 end

                -- Apply constrained title (word wrap handles multi-word names)
                win.titleText:SetWidth(maxTitleWidth)
                win.titleText:SetText(label)

                -- Single long word without spaces: manual "..." truncation
                if not label:find(" ") then
                    local fullW = win.titleText:GetStringWidth()
                    if fullW and fullW > maxTitleWidth then
                        local trunc = label
                        while #trunc > 1 do
                            trunc = trunc:sub(1, -2)
                            win.titleText:SetText(trunc .. "...")
                            local tw = win.titleText:GetStringWidth()
                            if tw and tw <= maxTitleWidth then break end
                        end
                    end
                end

                -- Expand header height if title wrapped to 2 lines
                local titleH = win.titleText:GetStringHeight() or 15
                if titleH > 20 then
                    win.header:SetHeight(math.max(DM2.HEADER_HEIGHT, titleH + 8))
                else
                    win.header:SetHeight(DM2.HEADER_HEIGHT)
                end
            else
                -- Overall/Current: standard single-line layout
                win.titleText:SetWidth(0)
                win.titleText:SetText(label)
                win.header:SetHeight(DM2.HEADER_HEIGHT)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Reset Handler
--------------------------------------------------------------------------------

function DM2._HandleReset()
    for i = 1, DM2.MAX_WINDOWS do
        local win = DM2._windows[i]
        if win then
            win.mergedData = nil
            win.cachedSecondary = nil
            win.scrollOffset = 0
            win._preCombatDuration = 0
            if DM2._comp then
                DM2._RefreshBarRows(i, DM2._comp)
                DM2._UpdateTimerText(i)
            end
        end
    end
end
