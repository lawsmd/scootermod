-- damagemetersv2/editmode.lua - Position save/restore for Edit Mode integration
local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- Position Save/Restore
--------------------------------------------------------------------------------

local function EnsurePositionsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.damageMeterV2Positions then
        profile.damageMeterV2Positions = {}
    end
    return profile.damageMeterV2Positions
end

function DM2._SavePosition(windowIndex, layoutName, point, x, y)
    local positions = EnsurePositionsDB()
    if not positions then return end
    if not positions[layoutName] then
        positions[layoutName] = {}
    end
    positions[layoutName][windowIndex] = {
        point = point,
        x = x,
        y = y,
    }
end

function DM2._RestorePosition(windowIndex, layoutName)
    local positions = EnsurePositionsDB()
    if not positions or not positions[layoutName] then return end
    local pos = positions[layoutName][windowIndex]
    if not pos then return end

    local win = DM2._windows[windowIndex]
    if not win or not win.frame then return end

    win.frame:ClearAllPoints()
    win.frame:SetPoint(pos.point or "BOTTOMLEFT", UIParent, pos.point or "BOTTOMLEFT", pos.x or 0, pos.y or 0)
end

--------------------------------------------------------------------------------
-- LibEditMode Registration
--------------------------------------------------------------------------------

function DM2._InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    for i = 1, DM2.MAX_WINDOWS do
        local win = DM2._windows[i]
        if win and win.frame then
            win.frame.editModeName = "Damage Meter " .. i

            lib:AddFrame(win.frame, function(frame, layoutName, point, x, y)
                if point and x and y then
                    frame:ClearAllPoints()
                    frame:SetPoint(point, UIParent, point, x, y)
                end
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                    if savedPoint then
                        DM2._SavePosition(i, layoutName, savedPoint, savedX, savedY)
                    else
                        DM2._SavePosition(i, layoutName, point, x, y)
                    end
                end
            end, {
                point = "BOTTOMLEFT",
                x = 20,
                y = 200 + (i - 1) * 60,
            }, nil)
        end
    end

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        for i = 1, DM2.MAX_WINDOWS do
            DM2._RestorePosition(i, layoutName)
        end
    end)

    lib:RegisterCallback("enter", function()
        DM2._editModeActive = true
        -- Show all enabled windows for positioning (even "hidden" visibility)
        for i = 1, DM2.MAX_WINDOWS do
            local win = DM2._windows[i]
            local cfg = DM2._GetWindowConfig(i)
            if win and cfg and cfg.enabled then
                win.frame:Show()
            end
        end
    end)

    lib:RegisterCallback("exit", function()
        DM2._editModeActive = false
        -- Restore normal visibility rules
        if DM2._comp then
            for i = 1, DM2.MAX_WINDOWS do
                DM2._UpdateVisibility(i, DM2._comp)
            end
        end
    end)
end
