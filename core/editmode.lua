local addonName, addon = ...

addon.EditMode = {}

local LEO = LibStub("LibEditModeOverride-1.0")

-- Cache for resolved Edit Mode setting IDs per system
local _resolvedSettingIdCache = {}

local function _lower(s)
    if type(s) ~= "string" then return "" end
    return string.lower(s)
end

-- Discover the numeric setting id at runtime to avoid stale hardcodes
local function ResolveSettingId(frame, logicalKey)
    if not frame or not frame.system or not _G.EditModeSettingDisplayInfoManager then return nil end
    -- Prefer stable enum constants when available
    local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
    if EM then
        if logicalKey == "visibility" then return EM.VisibleSetting end
        if logicalKey == "show_timer" then return EM.ShowTimer end
        if logicalKey == "show_tooltip" then return EM.ShowTooltips end
        -- No stable enum seen for "Hide when inactive"; fall through to dynamic resolver
        if logicalKey == "orientation" then return EM.Orientation end
        if logicalKey == "columns" then return EM.IconLimit end
        if logicalKey == "direction" then return EM.IconDirection end
        if logicalKey == "iconSize" then return EM.IconSize end
        if logicalKey == "iconPadding" then return EM.IconPadding end
        if logicalKey == "opacity" then return EM.Opacity end
        -- Tracked Bars specific (bar content/display mode)
        if logicalKey == "bar_content" then return EM.BarContent end
    end
    local sys = frame.system
    _resolvedSettingIdCache[sys] = _resolvedSettingIdCache[sys] or {}
    if _resolvedSettingIdCache[sys][logicalKey] ~= nil then
        return _resolvedSettingIdCache[sys][logicalKey]
    end

    local entries = _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[sys]
    if type(entries) ~= "table" then return nil end

    local lk = _lower(logicalKey)
    local pick
    for _, setup in ipairs(entries) do
        local nm = _lower(setup.name or "")
        local tp = setup.type
        if lk == "visibility" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                local count = 0
                if type(setup.options) == "table" then for _ in pairs(setup.options) do count = count + 1 end end
                if (nm:find("visibility", 1, true) or count == 3) then pick = pick or setup end
            end
        elseif lk == "opacity" then
            if tp == Enum.EditModeSettingDisplayType.Slider then
                -- Identify by typical 50..100 range or name containing "opacity"
                local minV = tonumber(setup.minValue)
                local maxV = tonumber(setup.maxValue)
                if (minV == 50 and maxV == 100) or nm:find("opacity", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "bar_content" or lk == "display_mode" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                -- 3-way dropdown; look for name including display/content
                local count = 0
                if type(setup.options) == "table" then for _ in pairs(setup.options) do count = count + 1 end end
                if count == 3 and (nm:find("display", 1, true) or nm:find("content", 1, true)) then
                    pick = pick or setup
                end
            end
        elseif lk == "show_timer" or lk == "showtimer" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and (nm:find("timer", 1, true) or nm:find("countdown", 1, true)) then pick = pick or setup end
        elseif lk == "show_tooltip" or lk == "showtooltip" or lk == "tooltips" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("tooltip", 1, true) then pick = pick or setup end
        elseif lk == "hide_when_inactive" or lk == "hideinactive" or lk == "inactive" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and (nm:find("inactive", 1, true) or nm:find("hide", 1, true)) then pick = pick or setup end
        end
    end
    local id = pick and pick.setting or nil
    _resolvedSettingIdCache[sys][logicalKey] = id
    return id
end

-- Low-level wrappers for LibEditModeOverride
function addon.EditMode.GetSetting(frame, settingId)
    if not LEO or not LEO.GetFrameSetting then return nil end
    if not (LEO.IsReady and LEO:IsReady()) then return nil end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then return nil end
        else
            return nil
        end
    end
    return LEO:GetFrameSetting(frame, settingId)
end

function addon.EditMode.SetSetting(frame, settingId, value)
    if not LEO or not LEO.SetFrameSetting then return nil end
    if not (LEO.IsReady and LEO:IsReady()) then return nil end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then return nil end
        else
            return nil
        end
    end
    LEO:SetFrameSetting(frame, settingId, value)
end

function addon.EditMode.ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
    if not LEO or not LEO.ReanchorFrame then return end
    LEO:ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
end

function addon.EditMode.ApplyChanges()
    if not LEO or not LEO.ApplyChanges then return end
    if not InCombatLockdown() then
        LEO:ApplyChanges()
    else
        LEO:SaveOnly()
    end
end

-- Helper functions
function addon.EditMode.LoadLayouts()
    if not LEO or not LEO.LoadLayouts or not LEO.IsReady then return end
    if not LEO:IsReady() then return end
    if LEO.AreLayoutsLoaded and LEO:AreLayoutsLoaded() then return end
    pcall(LEO.LoadLayouts, LEO)
end

function addon.EditMode.SaveOnly()
    if not LEO or not LEO.SaveOnly then return end
    LEO:SaveOnly()
end

function addon.EditMode.IsReady()
    return LEO and LEO.IsReady and LEO:IsReady()
end

function addon.EditMode.HasEditModeSettings(frame)
    if not LEO then return false end
    if not (LEO.IsReady and LEO:IsReady()) then return false end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then return false end
        else
            return false
        end
    end
    return LEO.HasEditModeSettings and LEO:HasEditModeSettings(frame)
end

--[[----------------------------------------------------------------------------
    State Synchronization Logic
----------------------------------------------------------------------------]]--

-- Back-sync for position
local function roundPositionValue(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
end

--[[----------------------------------------------------------------------------
    Full Sync Functions (Addon DB -> Edit Mode)
----------------------------------------------------------------------------]]--

function addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return false end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    local dbValue = component.db[settingId]
    if dbValue == nil then
        dbValue = setting.default
    end
    if dbValue == nil then return false end

    local editModeValue
    -- Convert addon DB value to the value Edit Mode expects
    if settingId == "orientation" then
        editModeValue = (dbValue == "H") and 0 or 1
    elseif settingId == "columns" then
        editModeValue = tonumber(dbValue) or 12
    elseif settingId == "direction" then
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            editModeValue = (dbValue == "right") and 1 or 0
        else
            editModeValue = (dbValue == "up") and 1 or 0
        end
    elseif settingId == "iconPadding" then
        -- WRITING to the library requires the RAW value.
        editModeValue = tonumber(dbValue) or 2
    elseif settingId == "iconSize" then
        -- Always send raw percentage (50..200), rounded to nearest 10
        local desiredRaw = tonumber(dbValue) or 100
        if desiredRaw < 50 then desiredRaw = 50 end
        if desiredRaw > 200 then desiredRaw = 200 end
        desiredRaw = math.floor(desiredRaw / 10 + 0.5) * 10
        editModeValue = desiredRaw
    elseif settingId == "opacity" then
        -- Write RAW percent (50..100). Library will normalize to index internally if needed.
        local v = tonumber(dbValue) or 100
        if v < 50 then v = 50 elseif v > 100 then v = 100 end
        local emSetting = ResolveSettingId(frame, "opacity")
        if emSetting then setting.settingId = emSetting end
        editModeValue = v
        -- Always resolve the EM setting id for opacity to avoid stale hardcodes
        local resolved = ResolveSettingId(frame, "opacity")
        if resolved then setting.settingId = resolved end
    elseif settingId == "displayMode" then
        -- Map addon values to bar content dropdown: both/icon/name
        setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_content") or ResolveSettingId(frame, "display_mode") or setting.settingId
        local v = tostring(dbValue)
        -- Assume EM dropdown values: 0=Both,1=IconOnly,2=NameOnly (feature-detected at runtime when possible)
        if setting.settingId then
            editModeValue = (v == "icon") and 1 or (v == "name" and 2 or 0)
        end
    elseif settingId == "visibilityMode" then
        -- 0 = always, 1 = only in combat, 2 = hidden
        local v = tostring(dbValue)
        editModeValue = (v == "combat") and 1 or (v == "never" and 2 or 0)
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
    elseif settingId == "showTimer" then
        -- Checkbox mapping for Edit Mode: true/false -> 1/0. We resolve the dynamic setting id so we don't rely on stale enums.
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_timer") or setting.settingId
        local v = not not dbValue
        editModeValue = v and 1 or 0
    elseif settingId == "showTooltip" then
        -- Checkbox mapping for Edit Mode: true/false -> 1/0. Same dynamic id resolution as above.
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_tooltip") or setting.settingId
        local v = not not dbValue
        editModeValue = v and 1 or 0
    elseif settingId == "hideWhenInactive" then
        -- Resolve dynamically; map boolean to 1/0 for Edit Mode API
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_when_inactive") or setting.settingId
        local v = not not dbValue
        editModeValue = v and 1 or 0
    else
        editModeValue = tonumber(dbValue) or 0
    end

    if editModeValue ~= nil then
        local wrote = false
        local function persist()
            if addon.EditMode and addon.EditMode.ApplyChanges then
                addon.EditMode.ApplyChanges() -- wraps SaveOnly in combat; forces EM UI to refresh when out of combat
            end
        end

        -- Opacity: unconditionally write, and immediately refresh the system mixin so alpha updates
        if settingId == "opacity" then
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingOpacity) == "function" then
                pcall(frame.UpdateSystemSettingOpacity, frame)
            end
            wrote = true
            persist()
            return true
        elseif settingId == "displayMode" then
            -- Write and immediately update bar content on the viewer so icon/name hide/show applies without Edit Mode roundtrip
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingBarContent) == "function" then
                pcall(frame.UpdateSystemSettingBarContent, frame)
            end
            -- Nudged relayout to ensure children positions and anchors update
            if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
            if frame and type(frame.GetItemContainerFrame) == "function" then
                local ic = frame:GetItemContainerFrame()
                if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
            end
            wrote = true
            persist()
            return true
        elseif settingId == "visibilityMode" then
            -- Write and immediately update visible state on the viewer
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingVisibleSetting) == "function" then
                pcall(frame.UpdateSystemSettingVisibleSetting, frame)
            end
            wrote = true
            persist()
            return true
        end
        -- Others: skip write if no change
        local current = addon.EditMode.GetSetting(frame, setting.settingId)
        if current ~= editModeValue then
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if settingId == "hideWhenInactive" and frame and type(frame.UpdateSystemSettingHideWhenInactive) == "function" then
                pcall(frame.UpdateSystemSettingHideWhenInactive, frame)
            end
            wrote = true
            persist()
            return true
        end
        return false
    end
    return false
end

-- This is the main function for pushing the addon's state to Edit Mode.
function addon.EditMode.SyncComponentToEditMode(component)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return end

    if addon.EditMode._syncingEM then return end
    addon.EditMode._syncingEM = true

    -- Ensure layouts are loaded before we attempt to write
    addon.EditMode.LoadLayouts()

    -- 1. Sync Position
    local x = component.db.positionX or 0
    local y = component.db.positionY or 0
    addon.EditMode.ReanchorFrame(frame, "CENTER", "UIParent", "CENTER", x, y)

    -- 2. Sync all other Edit Mode settings
    for settingId, setting in pairs(component.settings) do
        if setting.type == "editmode" then
            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
        end
    end

    -- 3. Apply all changes atomically
    addon.EditMode.ApplyChanges()

    -- Hold the syncing guard briefly to avoid back-sync races from SaveLayouts callbacks
    local function clearGuard()
        addon.EditMode._syncingEM = false
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, clearGuard)
    else
        clearGuard()
    end
end


--[[----------------------------------------------------------------------------
    Back-Sync Functions (Edit Mode -> Addon DB)
----------------------------------------------------------------------------]]--

-- Syncs a single simple setting from Edit Mode to the addon DB
function addon.EditMode.SyncEditModeSettingToComponent(component, settingId)
    local frame = _G[component.frameName]
    if not frame or not addon.EditMode.HasEditModeSettings(frame) then return false end

    if addon.EditMode._syncingEM then return false end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    -- Resolve dynamic ids if needed
    if settingId == "visibilityMode" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
    elseif settingId == "showTimer" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_timer") or setting.settingId
    elseif settingId == "showTooltip" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "show_tooltip") or setting.settingId
    elseif settingId == "hideWhenInactive" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_when_inactive") or setting.settingId
    elseif settingId == "opacity" then
        -- Use stable enum if present; fallback unnecessary for opacity since it is fixed index 5
        if not setting.settingId then
            local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
            if EM and EM.Opacity then setting.settingId = EM.Opacity else setting.settingId = 5 end
        end
    end

    local editModeValue = addon.EditMode.GetSetting(frame, setting.settingId)
    if editModeValue == nil then return false end

    local dbValue
    -- Convert Edit Mode value to the value addon DB expects
    if settingId == "orientation" then
        dbValue = (editModeValue == 0) and "H" or "V"
    elseif settingId == "columns" then
        dbValue = math.max(1, math.min(20, tonumber(editModeValue) or 12))
    elseif settingId == "direction" then
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            dbValue = (editModeValue == 1) and "right" or "left"
        else
            dbValue = (editModeValue == 1) and "up" or "down"
        end
    elseif settingId == "iconPadding" then
        -- Library now returns raw value (2-10); store directly
        dbValue = tonumber(editModeValue) or 2
    elseif settingId == "iconSize" then
        -- Adaptive read: support either index (0-15) or raw (50-200)
        local v = tonumber(editModeValue) or 100
        if v <= 15 then
            dbValue = (v * 10) + 50
        else
            dbValue = v
        end
    elseif settingId == "opacity" then
        -- Read RAW percent (50..100). Library returns raw even if internally stored as index.
        local resolved = ResolveSettingId(frame, "opacity")
        if resolved then setting.settingId = resolved end
        local v = tonumber(editModeValue)
        if v == nil then return false end
        v = math.floor(v + 0.5)
        if v < 50 then v = 50 elseif v > 100 then v = 100 end
        dbValue = v
    elseif settingId == "visibilityMode" then
        -- 0 = always, 1 = only in combat, 2 = hidden
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil and frame and type(frame.visibleSetting) ~= "nil" then v = frame.visibleSetting end
        if v == nil then return false end
        if v == 1 then dbValue = "combat" elseif v == 2 then dbValue = "never" else dbValue = "always" end
    elseif settingId == "showTimer" then
        -- Back-sync from Edit Mode: 1/0 -> true/false
        dbValue = (tonumber(editModeValue) or 0) == 1 and true or false
    elseif settingId == "showTooltip" then
        -- Back-sync from Edit Mode: 1/0 -> true/false
        dbValue = (tonumber(editModeValue) or 0) == 1 and true or false
    elseif settingId == "hideWhenInactive" then
        -- Back-sync from Edit Mode: 1/0 -> true/false
        dbValue = (tonumber(editModeValue) or 0) == 1 and true or false
    elseif settingId == "displayMode" then
        -- Back-sync from Edit Mode dropdown to addon values: 0=both,1=icon,2=name (fallback assumption)
        setting.settingId = setting.settingId or ResolveSettingId(frame, "bar_content") or ResolveSettingId(frame, "display_mode") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == 1 then dbValue = "icon" elseif v == 2 then dbValue = "name" else dbValue = "both" end
        if component.db[settingId] ~= dbValue then component.db[settingId] = dbValue return true end
        return false
    else
        dbValue = tonumber(editModeValue) or 0
    end

    if component.db[settingId] ~= dbValue then
        component.db[settingId] = dbValue
        return true -- Indicates a change was made
    end
    return false
end
-- Syncs the frame's position from Edit Mode to the addon DB
function addon.EditMode.SyncComponentPositionFromEditMode(component)
    local frame = _G[component.frameName]
    if not frame then return false end

    local offsetX, offsetY
    if frame.GetCenter and UIParent and UIParent.GetCenter then
        local fx, fy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if fx and fy and ux and uy then
            offsetX = roundPositionValue(fx - ux)
            offsetY = roundPositionValue(fy - uy)
        end
    end

    if offsetX == nil or offsetY == nil then return false end

    local changed = false
    if component.db.positionX ~= offsetX then
        component.db.positionX = offsetX
        changed = true
    end
    if component.db.positionY ~= offsetY then
        component.db.positionY = offsetY
        changed = true
    end

    return changed
end

--[[----------------------------------------------------------------------------
    Initialization and Event Handling
----------------------------------------------------------------------------]]--

-- Centralized helper to run all back-sync operations
function addon.EditMode.RefreshSyncAndNotify(origin)
    if LEO and LEO.IsReady and LEO:IsReady() and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end

    addon:SyncAllEditModeSettings()

    if addon and addon.Profiles and addon.Profiles.RefreshFromEditMode then
        addon.Profiles:RefreshFromEditMode(origin)
    end

    -- If settings UI is open, refresh the active category to reflect new values
    if addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
        addon.SettingsPanel.RefreshCurrentCategoryDeferred()
    end

    if addon._dbgSync and origin then
        print("ScooterMod RefreshSyncAndNotify origin=" .. tostring(origin))
    end
end

-- Initialize Edit Mode integration
function addon.EditMode.Initialize()
    -- Enable compatibility mode for opacity: treat as index-based in LEO to match client persistence
    local LEO_local = LibStub and LibStub("LibEditModeOverride-1.0")
    if LEO_local and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeCooldownViewerSetting then
        local sys = _G.Enum.EditModeSystem.CooldownViewer
        local setting = _G.Enum.EditModeCooldownViewerSetting.Opacity
        LEO_local._forceIndexBased = LEO_local._forceIndexBased or {}
        LEO_local._forceIndexBased[sys] = LEO_local._forceIndexBased[sys] or {}
        LEO_local._forceIndexBased[sys][setting] = true
    end
    if not addon._hookedSave and type(_G.C_EditMode) == "table" and type(_G.C_EditMode.SaveLayouts) == "function" then
        hooksecurefunc(_G.C_EditMode, "SaveLayouts", function()
            C_Timer.After(0.0, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass1") end end)
            C_Timer.After(0.25, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass2") end end)
            C_Timer.After(0.6, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("SaveLayouts:pass3") end end)
        end)
        addon._hookedSave = true
    end

    if _G.EventRegistry and not addon._editModeCBRegistered then
        local ER = _G.EventRegistry
        if type(ER.RegisterCallback) == "function" then
            ER:RegisterCallback("EditMode.Enter", function()
                -- Do not push on enter; it can cause recursion and frame churn as Blizzard initializes widgets.
            end, addon)
            ER:RegisterCallback("EditMode.Exit", function()
                C_Timer.After(0.1, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass1") end end)
                C_Timer.After(0.5, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass2") end end)
                C_Timer.After(1.0, function() if addon.EditMode then addon.EditMode.RefreshSyncAndNotify("EditModeExit:pass3") end end)
            end, addon)
            addon._editModeCBRegistered = true
        end
    end
end
