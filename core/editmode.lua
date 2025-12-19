-- Central suppression check (used only during short post-copy window)
local function _ShouldSuppressWrites()
    local prof = addon and addon.Profiles
    if not prof or not prof.IsPostCopySuppressed then return false end
    return prof:IsPostCopySuppressed()
end
local function _SafePCall(method, frame)
    if frame and type(method) == "string" and type(frame[method]) == "function" then
        pcall(frame[method], frame)
    end
end
local addonName, addon = ...

addon.EditMode = {}

local LEO = LibStub("LibEditModeOverride-1.0")

-- Cache for resolved Edit Mode setting IDs per system
local _resolvedSettingIdCache = {}

local function _lower(s)
    if type(s) ~= "string" then return "" end
    return string.lower(s)
end

local function _GetUnitFrameForUnit(unit)
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then
        return nil
    end

    local idx
    if unit == "Player" then
        idx = EM.Player
    elseif unit == "Target" then
        idx = EM.Target
    elseif unit == "Focus" then
        idx = EM.Focus
    elseif unit == "Pet" then
        idx = EM.Pet
    end

    if not idx then
        return nil
    end

    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
end

--[[----------------------------------------------------------------------------
    Copy helpers (Edit Mode only)
----------------------------------------------------------------------------]]--
-- Copy Unit Frame "Frame Size (Scale)" from one unit to another.
-- Allowed units: "Player", "Target", "Focus". Pet returns success (no-op) because
-- Blizzard does not expose a frame size setting for the pet frame.
-- Returns true on success; false and an error key on failure.
function addon.EditMode.CopyUnitFrameFrameSize(sourceUnit, destUnit)
    local function norm(u)
        if type(u) ~= "string" then return nil end
        u = string.lower(u)
        if u == "player" then return "Player" end
        if u == "target" then return "Target" end
        if u == "focus"  then return "Focus" end
        if u == "pet"    then return "Pet" end
        return nil
    end
    local src = norm(sourceUnit)
    local dst = norm(destUnit)
    if not src or not dst then return false, "invalid_unit" end
    if src == dst then return false, "same_unit" end

    -- Pet frame size is managed internally by Blizzard and does not expose a
    -- configurable Frame Size setting. Treat Pet copy requests as a no-op so
    -- the broader copy flow can continue without surfacing an error.
    if src == "Pet" or dst == "Pet" then
        return true
    end

    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    local UFSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    if not (mgr and EM and EMSys and UFSetting and mgr.GetRegisteredSystemFrame) then return false, "env_unavailable" end

    local function idxFor(unit)
        if unit == "Player" then return EM.Player end
        if unit == "Target" then return EM.Target end
        if unit == "Focus"  then return EM.Focus end
        if unit == "Pet"    then return EM.Pet end
        return nil
    end

    local srcIdx = idxFor(src)
    local dstIdx = idxFor(dst)
    if not srcIdx or not dstIdx then return false, "invalid_unit" end

    local srcFrame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, srcIdx)
    local dstFrame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, dstIdx)
    if not srcFrame or not dstFrame then return false, "frame_missing" end

    -- Read source Frame Size; library is configured to return RAW (100..200)
    local sizeSetting = UFSetting.FrameSize
    local raw = addon.EditMode.GetSetting(srcFrame, sizeSetting)
    if raw == nil then return false, "no_source_value" end
    local v = tonumber(raw) or 100
    -- Safety: convert index 0..20 to raw 100..200 if observed
    if v <= 20 then v = 100 + (v * 5) end
    if v < 100 then v = 100 elseif v > 200 then v = 200 end

    -- Focus destination requires Use Larger Frame to be enabled
    if dst == "Focus" then
        local useLarger = addon.EditMode.GetSetting(dstFrame, UFSetting.UseLargerFrame)
        if not useLarger or tonumber(useLarger) == 0 then
            return false, "focus_requires_larger"
        end
    end

    -- Write to destination and persist via centralized helper (with light panel suppression)
    if addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(dstFrame, sizeSetting, v, {
            suspendDuration = 0.25,
        })
    else
        addon.EditMode.SetSetting(dstFrame, sizeSetting, v)
        if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
        if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
    end
    return true
end

-- Discover the numeric setting id at runtime to avoid stale hardcodes
local function ResolveSettingId(frame, logicalKey)
    if not frame or not frame.system or not _G.EditModeSettingDisplayInfoManager then return nil end
    -- Ensure layouts are loaded so the display info table is populated
    -- IMPORTANT: Only call LoadLayouts if not already loaded to avoid cascade of calls
    if LEO and LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if addon and addon.EditMode and addon.EditMode.LoadLayouts then addon.EditMode.LoadLayouts() end
    end
    -- Prefer stable enum constants only for Cooldown Viewer systems
    local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
    if EM and frame and frame.system == (_G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.CooldownViewer) then
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
    if not sys then return nil end

    local auraSystem = _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.AuraFrame
    local cacheKey = logicalKey
    if sys == auraSystem then
        local frameKey
        if frame == _G.BuffFrame then
            frameKey = "buff"
        elseif frame == _G.DebuffFrame then
            frameKey = "debuff"
        else
            frameKey = (frame and frame.GetName and frame:GetName()) or tostring(frame)
        end
        cacheKey = (frameKey or "frame") .. "::" .. tostring(logicalKey)
    end

    _resolvedSettingIdCache[sys] = _resolvedSettingIdCache[sys] or {}
    if _resolvedSettingIdCache[sys][cacheKey] ~= nil then
        return _resolvedSettingIdCache[sys][cacheKey]
    end

    local entries = _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[sys]
    if type(entries) ~= "table" then return nil end

    local lk = _lower(logicalKey)

    local auraEnum = _G.Enum and _G.Enum.EditModeAuraFrameSetting
    if auraEnum and sys == auraSystem then
        local id
        if lk == "orientation" then
            id = auraEnum.Orientation
        elseif lk == "icon_wrap" or lk == "wrap" then
            id = auraEnum.IconWrap
        elseif lk == "icon_direction" or lk == "direction" then
            id = auraEnum.IconDirection
        elseif lk == "icon_size" then
            id = auraEnum.IconSize
        elseif lk == "icon_padding" then
            id = auraEnum.IconPadding
        elseif lk == "icon_limit" or lk == "iconlimit" or lk == "aura_icon_limit" then
            if frame == _G.BuffFrame then
                id = auraEnum.IconLimitBuffFrame
            elseif frame == _G.DebuffFrame then
                id = auraEnum.IconLimitDebuffFrame
            end
        end
        if id ~= nil then
            _resolvedSettingIdCache[sys][cacheKey] = id
            return id
        end
    end
    local pick
    for _, setup in ipairs(entries) do
        local nm = _lower(setup.name or "")
        local tp = setup.type
        if lk == "visibility" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                local count = 0
                if type(setup.options) == "table" then for _ in pairs(setup.options) do count = count + 1 end end
                -- Accept both 3-option (CDM) and 4-option (Action Bars 2-8) dropdowns whose name includes visibility/visible
                if nm:find("visibility", 1, true) or nm:find("visible", 1, true) or count == 3 or count == 4 then
                    pick = pick or setup
                end
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
        elseif lk == "orientation" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown then
                if nm:find("orientation", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "num_rows" then
            if tp == Enum.EditModeSettingDisplayType.Slider then
                if nm:find("row", 1, true) or nm:find("column", 1, true) then
                    pick = pick or setup
                end
            end
        elseif lk == "num_icons" then
            if tp == Enum.EditModeSettingDisplayType.Slider and nm:find("icon", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_size" then
            if tp == Enum.EditModeSettingDisplayType.Slider and (nm:find("icon", 1, true) and nm:find("size", 1, true)) then
                pick = pick or setup
            end
        elseif lk == "icon_padding" then
            if tp == Enum.EditModeSettingDisplayType.Slider and nm:find("padding", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_limit" or lk == "iconlimit" or lk == "aura_icon_limit" then
            if tp == Enum.EditModeSettingDisplayType.Slider and nm:find("limit", 1, true) and nm:find("icon", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_wrap" or lk == "wrap" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown and nm:find("wrap", 1, true) then
                pick = pick or setup
            end
        elseif lk == "icon_direction" or lk == "direction" then
            if tp == Enum.EditModeSettingDisplayType.Dropdown and nm:find("direction", 1, true) and nm:find("icon", 1, true) then
                pick = pick or setup
            end
        elseif lk == "hide_bar_art" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("hide", 1, true) and nm:find("art", 1, true) then
                pick = pick or setup
            end
        elseif lk == "hide_bar_scrolling" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("hide", 1, true) and nm:find("scroll", 1, true) then
                pick = pick or setup
            end
        elseif lk == "always_show_buttons" then
            if tp == Enum.EditModeSettingDisplayType.Checkbox and nm:find("always", 1, true) and nm:find("button", 1, true) then
                pick = pick or setup
            end
        end
    end
    local id = pick and pick.setting or nil
    _resolvedSettingIdCache[sys][cacheKey] = id
    return id
end

-- Expose a safe resolver for other modules (e.g., settings panel builders) that
-- need to query Edit Mode settings for a given component without duplicating
-- the display-info walking logic above.
function addon.EditMode.ResolveSettingIdForComponent(component, logicalKey)
    if not component or not component.frameName then return nil end
    local frame = _G[component.frameName]
    if not frame then return nil end
    return ResolveSettingId(frame, logicalKey)
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
    if _ShouldSuppressWrites() then return end
    if not InCombatLockdown() then
        if addon and addon.SettingsPanel then
            addon.SettingsPanel._protectVisibility = true
            if addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.15) end
        end
        LEO:ApplyChanges()
    else
        LEO:SaveOnly()
    end
end

-- Coalesced ApplyChanges helper: collapse multiple writes into a single apply
local _pendingApplyTimer
function addon.EditMode.RequestApplyChanges(delay)
    local d = tonumber(delay) or 0.2
    -- Cancel any previously scheduled apply
    if _pendingApplyTimer and _pendingApplyTimer.Cancel then
        _pendingApplyTimer:Cancel()
    end
    -- Do not attempt to apply during combat; SaveOnly is handled at write time
    if InCombatLockdown and InCombatLockdown() then return end
    if C_Timer and C_Timer.NewTimer then
        _pendingApplyTimer = C_Timer.NewTimer(d, function()
            if addon and addon.EditMode and addon.EditMode.ApplyChanges then
                addon.EditMode.ApplyChanges()
            end
            _pendingApplyTimer = nil
        end)
    else
        -- Fallback: immediate apply if timer API is unavailable
        if addon and addon.EditMode and addon.EditMode.ApplyChanges then
            addon.EditMode.ApplyChanges()
        end
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
    if _ShouldSuppressWrites() then return end
    LEO:SaveOnly()
end

-- Centralized write helper for Edit Mode–controlled settings.
-- All ScooterMod-initiated writes to Edit Mode should flow through this helper
-- so that SaveOnly / ApplyChanges and panel refresh suppression behave
-- consistently across systems (Cooldown Viewer, Action Bars, Unit Frames, etc.).
--
-- opts:
--   updaters        = { "MethodOnFrame", { frame = otherFrame, method = "Layout" }, ... }
--   suspendDuration = number | nil   -- seconds to suspend panel refresh (optional)
--   applyDelay      = number | nil   -- delay used for RequestApplyChanges (default 0.2)
--   skipSave        = boolean | nil  -- when true, do not call SaveOnly()
--   skipApply       = boolean | nil  -- when true, do not call RequestApplyChanges()
function addon.EditMode.WriteSetting(frame, settingId, value, opts)
    if not frame or settingId == nil then return end
    if not addon.EditMode or not addon.EditMode.SetSetting then return end

    opts = opts or {}

    -- Perform the low-level write
    addon.EditMode.SetSetting(frame, settingId, value)

    -- Run any requested update methods to nudge visuals immediately
    local updaters = opts.updaters
    if type(updaters) == "table" then
        for _, u in ipairs(updaters) do
            if type(u) == "string" then
                _SafePCall(u, frame)
            elseif type(u) == "table" then
                local target = u.frame or frame
                local method = u.method
                if target and type(method) == "string" and type(target[method]) == "function" then
                    pcall(target[method], target)
                end
            end
        end
    end

    -- Optionally suspend Settings panel refresh while Edit Mode churn settles
    local suspendDuration = tonumber(opts.suspendDuration)
    if suspendDuration and suspendDuration > 0 and addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then
        addon.SettingsPanel.SuspendRefresh(suspendDuration)
    end

    -- Persist and coalesce ApplyChanges through the existing helpers
    if not opts.skipSave and addon.EditMode.SaveOnly then
        addon.EditMode.SaveOnly()
    end
    if not opts.skipApply and addon.EditMode.RequestApplyChanges then
        addon.EditMode.RequestApplyChanges(opts.applyDelay or 0.2)
    end
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

    local function markBackSyncSkip(forSetting, count)
        if not component then return end
        component._skipNextBackSync = component._skipNextBackSync or {}
        local key = forSetting or settingId
        local current = component._skipNextBackSync[key]
        local desired = tonumber(count) or 2
        if type(current) == "number" then
            component._skipNextBackSync[key] = math.max(current, desired)
        else
            component._skipNextBackSync[key] = desired
        end
    end

    local setting = component.settings[settingId]
    if not setting or setting.type ~= "editmode" then return false end

    local dbValue = component.db[settingId]
    if dbValue == nil then
        dbValue = setting.default
    end
    if dbValue == nil then return false end

    -- (removed global-propagation of Orientation; each bar updates independently)

    local editModeValue
    -- Convert addon DB value to the value Edit Mode expects
    if settingId == "orientation" then
        -- Resolve orientation setting id dynamically for non-CooldownViewer systems
        setting.settingId = setting.settingId or ResolveSettingId(frame, "orientation") or setting.settingId
        editModeValue = (dbValue == "H") and 0 or 1
    elseif settingId == "columns" then
        editModeValue = tonumber(dbValue) or 12
    elseif component and component.id == "microBar" and settingId == "direction" then
        -- Micro Bar: 'Order' uses 0 = default (Right/Up), 1 = reverse (Left/Down)
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            editModeValue = (dbValue == "left") and 1 or 0 -- default Right => 0
        else
            editModeValue = (dbValue == "down") and 1 or 0 -- default Up => 0
        end
        setting.settingId = setting.settingId or 1
    elseif settingId == "iconWrap" then
        -- Icon Wrap is stored as a simple 0/1 index whose semantics depend on orientation:
        --  Horizontal: 0=Down, 1=Up
        --  Vertical:   0=Left, 1=Right
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_wrap") or setting.settingId
        local o = component.db.orientation or "H"
        local v = tostring(dbValue)
        if o == "H" then
            editModeValue = (v == "up") and 1 or 0
        else
            editModeValue = (v == "right") and 1 or 0
        end
    elseif settingId == "direction" then
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame.system == sysEnum.AuraFrame then
            -- Aura Frame: direction is also a 0/1 index whose meaning depends on orientation:
            --  Horizontal: 0=Left,  1=Right
            --  Vertical:   0=Up,    1=Down
            setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_direction") or setting.settingId
            local o = component.db.orientation or "H"
            local v = tostring(dbValue)
            if o == "H" then
                editModeValue = (v == "right") and 1 or 0
            else
                editModeValue = (v == "up") and 1 or 0
            end
        else
            -- Default mapping used by Cooldown Viewer / Action Bars (orientation-aware)
            local orientation = component.db.orientation or "H"
            if orientation == "H" then
                editModeValue = (dbValue == "right") and 1 or 0
            else
                editModeValue = (dbValue == "up") and 1 or 0
            end
        end
    elseif settingId == "iconPadding" then
        -- WRITING to the library requires the RAW value. Ranges:
        --  - Cooldown Viewer / Action Bars / Tracked Bars: 2–10
        --  - Aura Frame (Buffs/Debuffs): 5–15
        local pad = tonumber(dbValue)
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            if not pad then pad = 10 end
            if pad < 5 then pad = 5 elseif pad > 15 then pad = 15 end
        else
            if not pad then pad = 2 end
            if pad < 2 then pad = 2 elseif pad > 10 then pad = 10 end
        end
        editModeValue = pad
    elseif settingId == "iconLimit" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_limit") or setting.settingId
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        local minV, maxV, defaultV = 1, 32, 8
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            local isBuffFrame = frame == _G.BuffFrame
            minV = isBuffFrame and 2 or 1
            maxV = isBuffFrame and 32 or 16
            defaultV = isBuffFrame and 11 or math.min(math.max(defaultV, minV), maxV)
        end
        local limit = tonumber(dbValue)
        if not limit then limit = defaultV end
        limit = math.floor(limit + 0.5)
        if limit < minV then limit = minV elseif limit > maxV then limit = maxV end
        editModeValue = limit
    elseif settingId == "iconSize" then
        -- Resolve id for non-CDM systems and send raw percent (50–200), snapped to 10.
        -- LibEditModeOverride handles index-vs-raw conversion for systems where Icon Size
        -- behaves like an index slider (e.g., Cooldown Viewer, Aura Frame).
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_size") or setting.settingId
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
    elseif component and component.id == "microBar" and (settingId == "menuSize" or settingId == "eyeSize") then
        -- Micro Bar sliders: library expects RAW values (min..max, step 5)
        local minV = (settingId == "menuSize") and 70 or 50
        local maxV = (settingId == "menuSize") and 200 or 150
        local step = 5
        local raw = tonumber(dbValue) or ((minV + maxV) / 2)
        if raw < minV then raw = minV elseif raw > maxV then raw = maxV end
        raw = minV + math.floor(((raw - minV) / step) + 0.5) * step -- snap to step within range
        setting.settingId = setting.settingId or ((settingId == "menuSize") and 2 or 3)
        markBackSyncSkip()
        addon.EditMode.SetSetting(frame, setting.settingId, raw)
        local updater = (settingId == "menuSize") and frame.UpdateSystemSettingSize or frame.UpdateSystemSettingEyeSize
        if frame and type(updater) == "function" then pcall(updater, frame) end
        if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
        if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
        if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
        return true
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
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
        end

        -- Opacity: unconditionally write, and immediately refresh the system mixin so alpha updates
        if settingId == "opacity" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingOpacity) == "function" then
                pcall(frame.UpdateSystemSettingOpacity, frame)
            end
            wrote = true
            persist()
            return true
        elseif settingId == "displayMode" then
            -- Write and immediately update bar content on the viewer so icon/name hide/show applies without Edit Mode roundtrip
            markBackSyncSkip()
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
        elseif settingId == "orientation" then
            -- Write and immediately update orientation + layout, then apply layout changes
            setting.settingId = setting.settingId or ResolveSettingId(frame, "orientation") or setting.settingId
            if not setting.settingId then
                -- Fallback for Action Bars: orientation is typically the first setting; use 0 when resolution fails
                if type(component.id) == "string" and component.id:match("^actionBar%d$") then
                    setting.settingId = 0
                end
            end
            local emVal = (component.db.orientation == "H") and 0 or 1
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, emVal)
            -- For Stance Bar, skip all immediate updaters to avoid taint; rely on deferred ApplyChanges
            if not (component and component.id == "stanceBar") then
                if frame and type(frame.UpdateSettingMap) == "function" then pcall(frame.UpdateSettingMap, frame) end
                if frame and type(frame.UpdateSystemSettingOrientation) == "function" then pcall(frame.UpdateSystemSettingOrientation, frame) end
                if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
                if frame and type(frame.RefreshGridLayout) == "function" then pcall(frame.RefreshGridLayout, frame) end
                if frame and type(frame.UpdateGridLayout) == "function" then pcall(frame.UpdateGridLayout, frame) end
                if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
                if frame and type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
                if frame and type(frame.GetItemContainerFrame) == "function" then
                    local ic = frame:GetItemContainerFrame()
                    if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
                end
            end
            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.15) end
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
            return true
        elseif settingId == "columns" and type(component.id) == "string" and (component.id:match("^actionBar%d$") or component.id == "stanceBar") then
            -- Action Bars / Stance Bar: "# Rows/Columns" maps to NumRows setting
            local value = tonumber(component.db.columns)
            if not value then value = 1 end
            value = math.floor(math.max(1, math.min(4, value)))
            -- Resolve rows setting id dynamically
            setting.settingId = setting.settingId or ResolveSettingId(frame, "num_rows") or setting.settingId
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, value)
            -- Skip all immediate updaters for Stance Bar to avoid taint
            if not (component and component.id == "stanceBar") then
                if frame and type(frame.UpdateSettingMap) == "function" then pcall(frame.UpdateSettingMap, frame) end
                if frame and type(frame.UpdateSystemSettingNumRows) == "function" then pcall(frame.UpdateSystemSettingNumRows, frame) end
                if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
                if frame and type(frame.RefreshGridLayout) == "function" then pcall(frame.RefreshGridLayout, frame) end
                if frame and type(frame.UpdateGridLayout) == "function" then pcall(frame.UpdateGridLayout, frame) end
                if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
                if frame and type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
                if frame and type(frame.GetItemContainerFrame) == "function" then
                    local ic = frame:GetItemContainerFrame()
                    if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
                end
            end
            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.15) end
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
            return true
        elseif settingId == "numIcons" then
            local value = tonumber(component.db.numIcons)
            if not value then value = 12 end
            value = math.floor(math.max(6, math.min(12, value)))
            setting.settingId = setting.settingId or ResolveSettingId(frame, "num_icons") or setting.settingId
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, value)
            if frame and type(frame.UpdateSettingMap) == "function" then pcall(frame.UpdateSettingMap, frame) end
            if frame and type(frame.UpdateSystemSettingNumIcons) == "function" then pcall(frame.UpdateSystemSettingNumIcons, frame) end
            if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
            if frame and type(frame.RefreshGridLayout) == "function" then pcall(frame.RefreshGridLayout, frame) end
            if frame and type(frame.UpdateGridLayout) == "function" then pcall(frame.UpdateGridLayout, frame) end
            if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
            if frame and type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
            if frame and type(frame.GetItemContainerFrame) == "function" then
                local ic = frame:GetItemContainerFrame()
                if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
            end
            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.15) end
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
            return true
        elseif settingId == "visibilityMode" then
            -- Write and immediately update visible state on the viewer
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingVisibleSetting) == "function" then
                pcall(frame.UpdateSystemSettingVisibleSetting, frame)
            end
            wrote = true
            persist()
            return true
        elseif component and component.id == "microBar" and settingId == "direction" then
            -- Write and immediately update ordering for Micro bar
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingOrder) == "function" then pcall(frame.UpdateSystemSettingOrder, frame) end
            if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
            wrote = true
            persist()
            return true
        elseif settingId == "barVisibility" then
            -- Action Bars (2..8): 4-option visibility
            setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
            local map = { always = 0, combat = 1, not_in_combat = 2, hidden = 3 }
            local idx = map[tostring(dbValue)]
            if idx == nil then idx = 0 end
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, idx)
            if frame and type(frame.UpdateSystemSettingVisibleSetting) == "function" then pcall(frame.UpdateSystemSettingVisibleSetting, frame) end
            wrote = true
            persist()
            return true
        elseif settingId == "hideBarArt" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_art") or setting.settingId
            local v = not not dbValue
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, v and 1 or 0)
            if frame and type(frame.UpdateSystemSettingHideBarArt) == "function" then pcall(frame.UpdateSystemSettingHideBarArt, frame) end
            wrote = true
            persist()
            return true
        elseif settingId == "hideBarScrolling" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_scrolling") or setting.settingId
            local v = not not dbValue
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, v and 1 or 0)
            if frame and type(frame.UpdateSystemSettingHideBarScrolling) == "function" then pcall(frame.UpdateSystemSettingHideBarScrolling, frame) end
            wrote = true
            persist()
            return true
        elseif settingId == "alwaysShowButtons" then
            setting.settingId = setting.settingId or ResolveSettingId(frame, "always_show_buttons") or setting.settingId
            local v = not not dbValue
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, v and 1 or 0)
            if frame and type(frame.UpdateSystemSettingAlwaysShowButtons) == "function" then pcall(frame.UpdateSystemSettingAlwaysShowButtons, frame) end
            wrote = true
            persist()
            return true
        elseif settingId == "iconLimit" then
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if frame and type(frame.UpdateSystemSettingIconLimit) == "function" then pcall(frame.UpdateSystemSettingIconLimit, frame) end
            if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
            if frame and type(frame.RefreshGridLayout) == "function" then pcall(frame.RefreshGridLayout, frame) end
            if frame and type(frame.UpdateGridLayout) == "function" then pcall(frame.UpdateGridLayout, frame) end
            if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
            if frame and type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
            if frame and type(frame.GetItemContainerFrame) == "function" then
                local ic = frame:GetItemContainerFrame()
                if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
            end
            wrote = true
            persist()
            return true
        elseif settingId == "iconSize" then
            markBackSyncSkip(nil, 2)
            addon.EditMode.SetSetting(frame, setting.settingId, editModeValue)
            if not (component and component.id == "stanceBar") then
                if frame and type(frame.UpdateSystemSettingIconSize) == "function" then pcall(frame.UpdateSystemSettingIconSize, frame) end
                if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
                if frame and type(frame.RefreshGridLayout) == "function" then pcall(frame.RefreshGridLayout, frame) end
                if frame and type(frame.UpdateGridLayout) == "function" then pcall(frame.UpdateGridLayout, frame) end
                if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
                if frame and type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
                if frame and type(frame.GetItemContainerFrame) == "function" then
                    local ic = frame:GetItemContainerFrame()
                    if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
                end
            end
            if component and (component.id == "buffs" or component.id == "debuffs") then
                component._pendingAuraIconSizeTarget = editModeValue
                if GetTime then
                    component._pendingAuraIconSizeExpiry = GetTime() + 2.0
                else
                    component._pendingAuraIconSizeExpiry = os and os.time and (os.time() + 2) or nil
                end
            end
            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.15) end
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
            return true
        elseif settingId == "iconPadding" then
            -- Write raw padding value, clamped per system:
            --  - Cooldown Viewer / Action Bars / Tracked Bars: 2..10
            --  - Aura Frame (Buffs/Debuffs): 5..15
            setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_padding") or setting.settingId
            local pad = tonumber(component.db.iconPadding)
            local sysEnum = _G.Enum and _G.Enum.EditModeSystem
            if sysEnum and frame and frame.system == sysEnum.AuraFrame then
                if not pad then pad = 10 end
                if pad < 5 then pad = 5 elseif pad > 15 then pad = 15 end
            else
                if not pad then pad = 2 end
                if pad < 2 then pad = 2 elseif pad > 10 then pad = 10 end
            end
            markBackSyncSkip()
            addon.EditMode.SetSetting(frame, setting.settingId, pad)
            if not (component and component.id == "stanceBar") then
                if frame and type(frame.UpdateSystemSettingIconPadding) == "function" then pcall(frame.UpdateSystemSettingIconPadding, frame) end
                if frame and type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
                if frame and type(frame.RefreshGridLayout) == "function" then pcall(frame.RefreshGridLayout, frame) end
                if frame and type(frame.UpdateGridLayout) == "function" then pcall(frame.UpdateGridLayout, frame) end
                if frame and type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
                if frame and type(frame.UpdateLayout) == "function" then pcall(frame.UpdateLayout, frame) end
                if frame and type(frame.GetItemContainerFrame) == "function" then
                    local ic = frame:GetItemContainerFrame()
                    if ic and type(ic.Layout) == "function" then pcall(ic.Layout, ic) end
                end
            end
            if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.15) end
            if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
            if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
            return true
        end
        -- Others: skip write if no change
        local current = addon.EditMode.GetSetting(frame, setting.settingId)
        if current ~= editModeValue then
            markBackSyncSkip()
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
        if type(setting) == "table" and setting.type == "editmode" then
            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
        end
    end

    -- 3. Coalesce apply to avoid per-tick stalls during rapid changes
    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end

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

-- Position-only sync: Use this when ONLY position (X/Y) changed.
-- This avoids the cascade of syncing all Edit Mode settings (orientation, columns, etc.)
-- which would trigger many ResolveSettingId calls and LoadLayouts() invocations.
-- NOTE: This function handles SaveOnly/ApplyChanges internally - callers should NOT
-- call SaveOnly/RequestApplyChanges again after calling this function.
function addon.EditMode.SyncComponentPositionToEditMode(component)
    if not component then return end
    local frame = _G[component.frameName]
    if not frame then return end

    -- Guard against re-entry during sync
    if addon.EditMode._syncingPosition then return end
    addon.EditMode._syncingPosition = true

    -- Only load layouts if not already loaded (avoid cascade)
    if LEO and LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        addon.EditMode.LoadLayouts()
    end

    -- Sync Position only
    local x = component.db.positionX or 0
    local y = component.db.positionY or 0
    addon.EditMode.ReanchorFrame(frame, "CENTER", "UIParent", "CENTER", x, y)

    -- Coalesce apply to avoid per-tick stalls during rapid changes
    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end

    -- Clear guard after a brief delay to avoid back-sync races
    local function clearGuard()
        addon.EditMode._syncingPosition = false
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, clearGuard)
    else
        clearGuard()
    end
end


--[[----------------------------------------------------------------------------
    Aura Frame Icon Size Late Backfill
----------------------------------------------------------------------------]]--
local function _AuraBackfillDebugEnabled()
    return addon and addon._dbgAuraIconSize
end

local function _AuraBackfillLog(fmt, ...)
    if not _AuraBackfillDebugEnabled() then return end
    addon.EditMode._auraIconSizeLog = addon.EditMode._auraIconSizeLog or {}
    local prefix = ""
    if type(GetTime) == "function" then
        prefix = string.format("[%.3f] ", GetTime())
    end
    local message = fmt and string.format(fmt, ...) or ""
    table.insert(addon.EditMode._auraIconSizeLog, prefix .. message)
end

local _pendingAuraIconSizeBackfill = {}

local function _ClampAuraIconSizePercent(pct)
    if not pct then return nil end
    pct = tonumber(pct)
    if not pct then return nil end
    pct = math.floor(pct + 0.5)
    if pct < 50 then pct = 50 elseif pct > 200 then pct = 200 end
    local step = 10
    local snapped = step * math.floor((pct / step) + 0.5)
    if snapped < 50 then snapped = 50 elseif snapped > 200 then snapped = 200 end
    return snapped
end

local function _ReadAuraFrameIconPercent(frame)
    if not frame or not frame.AuraContainer then return nil end
    local scale = tonumber(frame.AuraContainer.iconScale)
    if not scale then return nil end
    return _ClampAuraIconSizePercent(scale * 100)
end

function addon.EditMode.QueueAuraIconSizeBackfill(componentId, opts)
    if componentId ~= "buffs" and componentId ~= "debuffs" then return end
    if not C_Timer or not C_Timer.After then return end
    if _pendingAuraIconSizeBackfill[componentId] then return end
    local origin = opts and opts.origin
    local attempt = (opts and opts.attempt) or 0
    local retryDelays = opts and opts.retryDelays
    if type(retryDelays) ~= "table" then
        retryDelays = nil
    end

    local delay = opts and tonumber(opts.delay) or 1.2
    if delay < 0 then delay = 0 end

    _pendingAuraIconSizeBackfill[componentId] = true

    if _AuraBackfillDebugEnabled() and attempt == 0 then
        addon.EditMode._auraIconSizeLog = {}
    end
    _AuraBackfillLog("QueueAuraIconSizeBackfill start component=%s origin=%s attempt=%d delay=%.2fs", tostring(componentId), tostring(origin), attempt, delay)

    local titlePrefix = (componentId == "buffs") and "Buffs" or (componentId == "debuffs" and "Debuffs" or tostring(componentId or "Aura"))

    C_Timer.After(delay, function()
        _pendingAuraIconSizeBackfill[componentId] = nil
        if not addon or not addon.Components then return end
        _AuraBackfillLog("Timer fired component=%s origin=%s attempt=%d", tostring(componentId), tostring(origin), attempt)

        local updated = false

        local function scheduleRetry(nextAttempt, reason, overrideDelay)
            if not nextAttempt then return false end
            local nextDelay = overrideDelay
            if not nextDelay and retryDelays and retryDelays[nextAttempt] then
                nextDelay = retryDelays[nextAttempt]
            end
            if not nextDelay then return false end
            if nextDelay < 0 then nextDelay = 0 end
            _AuraBackfillLog("Scheduling retry attempt=%d in %.2fs (reason=%s)", nextAttempt, nextDelay, tostring(reason or "retry"))
            addon.EditMode.QueueAuraIconSizeBackfill(componentId, {
                delay = nextDelay,
                origin = reason or origin or "retry",
                attempt = nextAttempt,
                retryDelays = retryDelays,
            })
            return true
        end

        local function refreshPanelIfVisible()
            local panel = addon and addon.SettingsPanel
            if not panel then return end
            local frame = panel.frame
            if not frame or not frame:IsShown() then return end
            if frame.CurrentCategory ~= componentId then return end

            -- Force-clear CurrentCategory to ensure SelectCategory treats this as a fresh selection,
            -- bypassing any potential same-category optimizations.
            frame.CurrentCategory = nil

            -- Invalidate the right pane so the next render rebuilds controls with fresh bindings.
            local rightPane = panel.RightPane
            if not (rightPane and rightPane.Invalidate) and frame.RightPane and frame.RightPane.Invalidate then
                rightPane = frame.RightPane
            end
            if rightPane and rightPane.Invalidate then
                rightPane:Invalidate()
            end

            -- Use SelectCategory to force a full re-bind of settings controls, mirroring the "tab switch"
            -- behavior that reliably updates stale sliders on panel open.
            if panel.SelectCategory then
                panel.SelectCategory(componentId)
            elseif panel.RefreshCurrentCategoryDeferred then
                panel.RefreshCurrentCategoryDeferred()
            end
        end

        if addon.EditMode and addon.EditMode._syncingEM then
            _AuraBackfillLog("Still syncing with Edit Mode; scheduling retry")
            local nextAttempt = attempt + 1
            local guardOrigin = (origin and (tostring(origin) .. ":guard")) or "retry_guard"
            if not scheduleRetry(nextAttempt, guardOrigin) then
                scheduleRetry(nextAttempt, guardOrigin, 0.2)
            end
            return
        end

        local component = addon.Components[componentId]
        if not component or not component.db then return end

        if addon.EditMode and addon.EditMode.SyncEditModeSettingToComponent then
            local before = component.db.iconSize
            local changed = addon.EditMode.SyncEditModeSettingToComponent(component, "iconSize")
            _AuraBackfillLog("SyncEditModeSettingToComponent returned changed=%s (db before=%s after=%s)", tostring(changed), tostring(before), tostring(component.db.iconSize))
            if changed then
                refreshPanelIfVisible()
                if _AuraBackfillDebugEnabled() and addon.DebugShowWindow then
                    addon.DebugShowWindow(string.format("%s Icon Size Backfill (%s)", titlePrefix, tostring(origin or "Sync")), addon.EditMode._auraIconSizeLog)
                end
                return
            end
        end

        local frame = _G[component.frameName]
        if not frame then return end

        local percent = _ReadAuraFrameIconPercent(frame)
        _AuraBackfillLog("AuraContainer iconScale-derived percent=%s", tostring(percent))
        if not percent then return end

        if component._pendingAuraIconSizeTarget then
            local expire = component._pendingAuraIconSizeExpiry
            local now = GetTime and GetTime() or nil
            if expire and now and now >= expire then
                component._pendingAuraIconSizeTarget = nil
                component._pendingAuraIconSizeExpiry = nil
                _AuraBackfillLog("Pending target expired; clearing guard")
            else
                local target = component._pendingAuraIconSizeTarget
                if target and math.abs(percent - target) >= 0.5 then
                    _AuraBackfillLog("Pending target %s differs from fallback percent=%s; retrying instead of reverting", tostring(target), tostring(percent))
                    local nextAttempt = attempt + 1
                    if scheduleRetry(nextAttempt, "pending_target") then return end
                    return
                end
            end
        end

        if component.db.iconSize ~= percent then
            _AuraBackfillLog("Updating component.db.iconSize from %s to %s via fallback", tostring(component.db.iconSize), tostring(percent))
            component.db.iconSize = percent
            updated = true
            if component._pendingAuraIconSizeTarget and math.abs((tonumber(component._pendingAuraIconSizeTarget) or 0) - percent) < 0.5 then
                component._pendingAuraIconSizeTarget = nil
                component._pendingAuraIconSizeExpiry = nil
            end
            refreshPanelIfVisible()
        else
            _AuraBackfillLog("No change to component.db.iconSize (already %s)", tostring(percent))
            refreshPanelIfVisible()
        end

        if _AuraBackfillDebugEnabled() and addon.DebugShowWindow then
            addon.DebugShowWindow(string.format("%s Icon Size Backfill (%s)", titlePrefix, tostring(origin or "Fallback")), addon.EditMode._auraIconSizeLog)
        end

        if not updated then
            local nextAttempt = attempt + 1
            if scheduleRetry(nextAttempt, (origin and (tostring(origin) .. ":poll")) or "retry_poll") then
                return
            end
        end
    end)
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

    if component._skipNextBackSync and component._skipNextBackSync[settingId] then
        local remaining = component._skipNextBackSync[settingId]
        if type(remaining) == "number" then
            if remaining <= 1 then
                component._skipNextBackSync[settingId] = nil
            else
                component._skipNextBackSync[settingId] = remaining - 1
            end
        else
            component._skipNextBackSync[settingId] = nil
        end
        return false
    end

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
    elseif settingId == "iconWrap" then
        -- Aura Frame and any other systems that expose an "Icon Wrap" dropdown
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_wrap") or setting.settingId
    elseif settingId == "direction" then
        -- Aura Frame "Icon Direction" and other systems sharing the logical key
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_direction") or setting.settingId
    end

    if settingId == "orientation" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "orientation") or setting.settingId
    end
    local editModeValue = addon.EditMode.GetSetting(frame, setting.settingId)
    if editModeValue == nil then return false end
    local initialEditModeValue = editModeValue

    local dbValue
    -- Convert Edit Mode value to the value addon DB expects
    if settingId == "orientation" then
        dbValue = (editModeValue == 0) and "H" or "V"
    elseif settingId == "columns" then
        if type(component.id) == "string" and component.id:match("^actionBar%d$") then
            -- Action Bars: back-sync #Rows/Columns from the NumRows setting
            local rowsSetting = ResolveSettingId(frame, "num_rows")
            local v = rowsSetting and addon.EditMode.GetSetting(frame, rowsSetting) or editModeValue
            dbValue = math.max(1, math.min(4, tonumber(v) or 1))
        else
            -- Cooldown Viewer: standard 1..20 columns/rows
            dbValue = math.max(1, math.min(20, tonumber(editModeValue) or 12))
        end
    elseif settingId == "numIcons" then
        local iconsSetting = ResolveSettingId(frame, "num_icons")
        local v = iconsSetting and addon.EditMode.GetSetting(frame, iconsSetting) or editModeValue
        dbValue = math.max(6, math.min(12, tonumber(v) or 12))
    elseif settingId == "iconWrap" then
        -- Decode Icon Wrap 0/1 index back into semantic value based on orientation:
        --  Horizontal: 0=Down, 1=Up
        --  Vertical:   0=Left, 1=Right
        -- NOTE: For Aura Frame we may have just performed a Scooter-initiated
        -- orientation remap in AceDB. In that narrow case, the settings panel
        -- marks component._skipNextAuraBackSync and we skip this readback once
        -- to avoid clobbering the freshly remapped DB state with a stale EM snapshot.
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame.system == sysEnum.AuraFrame and component._skipNextAuraBackSync then
            component._skipNextAuraBackSync = nil
            return false
        end

        local o = component.db.orientation or "H"
        local v = tonumber(editModeValue) or 0
        if o == "H" then
            dbValue = (v == 1) and "up" or "down"
        else
            dbValue = (v == 1) and "right" or "left"
        end
    elseif component and component.id == "microBar" and settingId == "direction" then
        -- Micro Bar: 0 = default (Right/Up), 1 = reverse (Left/Down)
        setting.settingId = setting.settingId or 1
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        local orientation = component.db.orientation or "H"
        if orientation == "H" then
            dbValue = (tonumber(v) == 1) and "left" or "right"
        else
            dbValue = (tonumber(v) == 1) and "down" or "up"
        end
        if component.db[settingId] ~= dbValue then component.db[settingId] = dbValue return true end
        return false
    elseif settingId == "direction" then
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame.system == sysEnum.AuraFrame then
            if component._skipNextAuraBackSync then
                component._skipNextAuraBackSync = nil
                return false
            end
            -- Aura Frame: decode 0/1 index according to current orientation:
            --  Horizontal: 0=Left,  1=Right
            --  Vertical:   0=Up,    1=Down
            local orientation = component.db.orientation or "H"
            local v = tonumber(editModeValue) or 0
            if orientation == "H" then
                dbValue = (v == 1) and "right" or "left"
            else
                dbValue = (v == 1) and "up" or "down"
            end
        else
            -- Default mapping used by Cooldown Viewer / Action Bars (orientation-aware)
            local orientation = component.db.orientation or "H"
            if orientation == "H" then
                dbValue = (editModeValue == 1) and "right" or "left"
            else
                dbValue = (editModeValue == 1) and "up" or "down"
            end
        end
    elseif settingId == "iconPadding" then
        -- Library returns raw value; clamp per system:
        --  - Cooldown Viewer / Action Bars / Tracked Bars: 2–10
        --  - Aura Frame (Buffs/Debuffs): 5–15
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        local v = tonumber(editModeValue)
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            if not v then v = 10 end
            if v < 5 then v = 5 elseif v > 15 then v = 15 end
        else
            if not v then v = 2 end
            if v < 2 then v = 2 elseif v > 10 then v = 10 end
        end
        dbValue = v
    elseif settingId == "iconLimit" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_limit") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil then return false end
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        local minV, maxV = 1, 32
        if sysEnum and frame and frame.system == sysEnum.AuraFrame then
            local isBuffFrame = frame == _G.BuffFrame
            minV = isBuffFrame and 2 or 1
            maxV = isBuffFrame and 32 or 16
        end
        v = tonumber(v) or minV
        v = math.floor(v + 0.5)
        if v < minV then v = minV elseif v > maxV then v = maxV end
        dbValue = v
    elseif settingId == "iconSize" then
        -- Resolve id for non-CDM systems and adapt index-vs-raw semantics.
        -- LibEditModeOverride converts index-based sliders back to raw for callers when
        -- SliderIsIndexBased returns true, so most systems will simply return 50–200 here.
        -- For Aura Frame we additionally sample the live iconScale, which is authoritative.
        local sysEnum = _G.Enum and _G.Enum.EditModeSystem
        if sysEnum and frame and frame.system == sysEnum.AuraFrame and frame.AuraContainer and frame.AuraContainer.iconScale then
            -- Aura Frame: derive percent directly from the live iconScale on the AuraContainer.
            local scale = tonumber(frame.AuraContainer.iconScale) or 1
            local pct = math.floor((scale * 100) + 0.5)
            if pct < 50 then pct = 50 elseif pct > 200 then pct = 200 end
            dbValue = pct
            if (component.id == "buffs" or component.id == "debuffs") and _AuraBackfillDebugEnabled() then
                _AuraBackfillLog("Sync iconSize: AuraContainer.iconScale=%.3f -> pct=%s (editModeValue=%s)", scale or 0, tostring(pct), tostring(initialEditModeValue))
            end
        else
            setting.settingId = setting.settingId or ResolveSettingId(frame, "icon_size") or setting.settingId
            local raw = addon.EditMode.GetSetting(frame, setting.settingId)
            local v = tonumber(raw) or tonumber(editModeValue) or 100

            -- Heuristic: if the value looks like an index (0–15), convert to 50–200; otherwise
            -- assume it is already a raw percent.
            if v <= 15 then
                dbValue = (v * 10) + 50
            else
                dbValue = v
            end
            if (component.id == "buffs" or component.id == "debuffs") and _AuraBackfillDebugEnabled() then
                _AuraBackfillLog("Sync iconSize: LEO raw=%s editModeValue=%s -> dbValue=%s", tostring(raw), tostring(initialEditModeValue), tostring(dbValue))
            end
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
    elseif component and component.id == "microBar" and (settingId == "menuSize" or settingId == "eyeSize") then
        -- Library returns RAW values when index-based mode is enabled
        setting.settingId = setting.settingId or ((settingId == "menuSize") and 2 or 3)
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        local minV = (settingId == "menuSize") and 70 or 50
        local maxV = (settingId == "menuSize") and 200 or 150
        local step = 5
        v = tonumber(v) or minV
        if v < minV then v = minV elseif v > maxV then v = maxV end
        v = minV + math.floor(((v - minV) / step) + 0.5) * step
        dbValue = v
    elseif settingId == "visibilityMode" then
        -- 0 = always, 1 = only in combat, 2 = hidden
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil and frame and type(frame.visibleSetting) ~= "nil" then v = frame.visibleSetting end
        if v == nil then return false end
        if v == 1 then dbValue = "combat" elseif v == 2 then dbValue = "never" else dbValue = "always" end
    elseif settingId == "barVisibility" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "visibility") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        if v == nil and frame and type(frame.visibleSetting) ~= "nil" then v = frame.visibleSetting end
        if v == nil then return false end
        if v == 1 then dbValue = "combat" elseif v == 2 then dbValue = "not_in_combat" elseif v == 3 then dbValue = "hidden" else dbValue = "always" end
    elseif settingId == "hideBarArt" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_art") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        dbValue = (tonumber(v) or 0) == 1 and true or false
    elseif settingId == "hideBarScrolling" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "hide_bar_scrolling") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        dbValue = (tonumber(v) or 0) == 1 and true or false
    elseif settingId == "alwaysShowButtons" then
        setting.settingId = setting.settingId or ResolveSettingId(frame, "always_show_buttons") or setting.settingId
        local v = addon.EditMode.GetSetting(frame, setting.settingId)
        dbValue = (tonumber(v) or 0) == 1 and true or false
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
        if (component.id == "buffs" or component.id == "debuffs") and settingId == "iconSize" and _AuraBackfillDebugEnabled() then
            _AuraBackfillLog("Sync result: updating component.db.iconSize from %s to %s", tostring(component.db[settingId]), tostring(dbValue))
        end
        component.db[settingId] = dbValue
        if settingId == "iconSize" and component and (component.id == "buffs" or component.id == "debuffs") then
            local pending = component._pendingAuraIconSizeTarget
            if pending and math.abs((tonumber(dbValue) or 0) - pending) <= 0.5 then
                component._pendingAuraIconSizeTarget = nil
                component._pendingAuraIconSizeExpiry = nil
            end
        end
        if addon and addon.SettingsPanel and type(addon.SettingsPanel.RefreshDynamicSettingWidgets) == "function" then
            if settingId == "orientation" or settingId == "direction" or settingId == "iconWrap" then
                addon.SettingsPanel:RefreshDynamicSettingWidgets(component)
            end
        end
        if addon and addon.SettingsPanel and type(addon.SettingsPanel.HandleEditModeBackSync) == "function" then
            addon.SettingsPanel:HandleEditModeBackSync(component.id, settingId)
        end
        return true -- Indicates a change was made
    end
    if (component.id == "buffs" or component.id == "debuffs") and settingId == "iconSize" and _AuraBackfillDebugEnabled() then
        _AuraBackfillLog("Sync result: no change (component.db.iconSize already %s)", tostring(dbValue))
    end
    return false
end
-- Syncs the frame's position from Edit Mode to the addon DB
function addon.EditMode.SyncComponentPositionFromEditMode(component)
    if not component or not component.frameName then
        return false
    end
    if component.disablePositionSync then
        return false
    end
    local hasPositionSettings = component.settings
        and component.settings.positionX
        and component.settings.positionY
    if not hasPositionSettings then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return false
    end
    local frame = _G[component.frameName]
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end

    local offsetX, offsetY
    if frame.GetCenter and UIParent and UIParent.GetCenter then
        local okFrame, fx, fy = pcall(frame.GetCenter, frame)
        local okParent, ux, uy = pcall(UIParent.GetCenter, UIParent)
        if fx and fy and ux and uy then
            offsetX = roundPositionValue(fx - ux)
            offsetY = roundPositionValue(fy - uy)
        end
    end

    if offsetX == nil or offsetY == nil then return false end

    -- If this position matches a very recent Scooter-authored write (e.g., from
    -- the X/Y numeric text inputs), skip writing it back into the DB. This
    -- avoids a redundant Settings row reinitialization that would otherwise
    -- steal focus from the text box shortly after the user edits it.
    local recent = component._recentPositionWrite
    if recent and (recent.x ~= nil and recent.y ~= nil) then
        local now = type(GetTime) == "function" and GetTime() or nil
        if now and recent.time and (now - recent.time) <= 0.6 then
            if recent.x == offsetX and recent.y == offsetY then
                return false
            end
        end
    end

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

function addon.EditMode.ResetComponentPositionToDefault(component)
    if not component or not component.frameName then
        return false, "missing_component"
    end

    local frame = _G[component.frameName]
    if not frame then
        return false, "frame_missing"
    end

    if addon.EditMode and addon.EditMode.LoadLayouts then
        pcall(addon.EditMode.LoadLayouts)
    end

    local usedSystemReset = false
    if type(frame.ResetToDefaultPosition) == "function" then
        local ok = pcall(frame.ResetToDefaultPosition, frame)
        if ok then
            usedSystemReset = true
        end
    end

    if not usedSystemReset then
        local preset = _G.EditModePresetLayoutManager
        if preset and preset.GetModernSystemAnchorInfo and frame.system and frame.systemIndex then
            local anchorInfo = preset:GetModernSystemAnchorInfo(frame.system, frame.systemIndex)
            if anchorInfo then
                local relativeTo = anchorInfo.relativeTo
                if type(relativeTo) == "string" then
                    relativeTo = _G[relativeTo]
                end
                if not relativeTo then
                    relativeTo = UIParent
                end
                addon.EditMode.ReanchorFrame(frame,
                    anchorInfo.point or "CENTER",
                    relativeTo,
                    anchorInfo.relativePoint or "CENTER",
                    anchorInfo.offsetX or 0,
                    anchorInfo.offsetY or 0)
                usedSystemReset = true
            end
        end
        if not usedSystemReset then
            return false, "anchor_unavailable"
        end
    end

    local function syncPosition()
        if addon.EditMode and addon.EditMode.SyncComponentPositionFromEditMode then
            addon.EditMode.SyncComponentPositionFromEditMode(component)
        end
    end

    syncPosition()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, syncPosition)
    end

    if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end

    return true
end

function addon.EditMode.ResetUnitFramePosition(unit)
    if type(unit) ~= "string" then
        return false, "missing_unit"
    end

    if addon.EditMode and addon.EditMode.LoadLayouts then
        pcall(addon.EditMode.LoadLayouts)
    end

    local frame = _GetUnitFrameForUnit(unit)
    if not frame then
        return false, "frame_missing"
    end

    local resetOk = false
    if type(frame.ResetToDefaultPosition) == "function" then
        resetOk = pcall(frame.ResetToDefaultPosition, frame) or false
    end

    if not resetOk then
        local preset = _G.EditModePresetLayoutManager
        if preset and preset.GetModernSystemAnchorInfo and frame.system and frame.systemIndex then
            local anchorInfo = preset:GetModernSystemAnchorInfo(frame.system, frame.systemIndex)
            if anchorInfo then
                local relativeTo = anchorInfo.relativeTo
                if type(relativeTo) == "string" then
                    relativeTo = _G[relativeTo]
                end
                if not relativeTo then
                    relativeTo = UIParent
                end
                addon.EditMode.ReanchorFrame(
                    frame,
                    anchorInfo.point or "CENTER",
                    relativeTo,
                    anchorInfo.relativePoint or "CENTER",
                    anchorInfo.offsetX or 0,
                    anchorInfo.offsetY or 0
                )
                resetOk = true
            end
        end

        if not resetOk then
            return false, "anchor_unavailable"
        end
    end

    if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
    if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end

    return true
end

--[[----------------------------------------------------------------------------
    Initialization and Event Handling
----------------------------------------------------------------------------]]--

-- Centralized helper to run all back-sync operations
function addon.EditMode.RefreshSyncAndNotify(origin)
    if LEO and LEO.IsReady and LEO:IsReady() and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end

    addon:SyncAllEditModeSettings()

    if origin and addon.EditMode and addon.EditMode.QueueAuraIconSizeBackfill then
        local lowerOrigin = (type(origin) == "string") and _lower(origin) or ""
        if (lowerOrigin:find("savelayouts", 1, true) or lowerOrigin:find("editmodeexit", 1, true)) and lowerOrigin:find("pass3", 1, true) then
            local delay = 0.35
            if lowerOrigin:find("editmodeexit", 1, true) then
                delay = 0.25
            end
            for _, auraId in ipairs({ "buffs", "debuffs" }) do
                addon.EditMode.QueueAuraIconSizeBackfill(auraId, {
                    delay = delay,
                    origin = origin,
                    retryDelays = { 0.35, 0.75 },
                })
            end
        end
    end

    if addon and addon.Profiles and addon.Profiles.RefreshFromEditMode then
        addon.Profiles:RefreshFromEditMode(origin)
    end

    -- UI NOTE (2025‑11‑17):
    -- We intentionally DO NOT auto-refresh the ScooterMod settings list here.
    -- Full category re-renders (SettingsList:Display) are reserved for STRUCTURAL
    -- changes only (category switch, schema change). Routine Edit Mode saves are
    -- reflected via Settings control bindings and per-row helpers without
    -- rebuilding the entire right-hand pane to avoid visible flicker.

    if addon._dbgSync and origin then
        print("ScooterMod RefreshSyncAndNotify origin=" .. tostring(origin))
    end
end

--[[----------------------------------------------------------------------------
    Preset import helpers (ScooterUI / ScooterDeck)
----------------------------------------------------------------------------]]--
local function computeSha256(blob)
    if type(blob) ~= "string" or blob == "" then
        return nil
    end
    if not C_Crypto or type(C_Crypto.Hash) ~= "function" then
        return nil
    end
    local ok, hash = pcall(C_Crypto.Hash, "SHA256", blob)
    if not ok or type(hash) ~= "string" then
        return nil
    end
    return string.lower(hash)
end

local function verifyHash(expected, blob, label)
    if not expected or expected == "" then
        return true
    end
    local computed = computeSha256(blob or "")
    if not computed then
        return false, string.format("%s hash could not be computed on this client.", label)
    end
    if computed ~= string.lower(expected) then
        return false, string.format("%s hash mismatch (expected %s, got %s).", label, expected, computed)
    end
    return true
end

local function verifyLayoutHash(expected, layoutInfo, label)
    if not expected or expected == "" then
        return true
    end
    if not C_EditMode or type(C_EditMode.ConvertLayoutInfoToString) ~= "function" then
        return false, string.format("%s hash could not be computed on this client (ConvertLayoutInfoToString unavailable).", label)
    end
    local ok, exportString = pcall(C_EditMode.ConvertLayoutInfoToString, layoutInfo)
    if not ok or type(exportString) ~= "string" or exportString == "" then
        return false, string.format("%s hash could not be computed on this client (export conversion failed).", label)
    end
    return verifyHash(expected, exportString, label)
end

local function buildPresetInstanceName(preset)
    local base = (preset and preset.name) or "Preset"
    base = base:gsub("^%s+", ""):gsub("%s+$", "")
    if base == "" then base = "Preset" end
    local stamp = date and date("!%Y-%m-%d %H:%M") or tostring(time() or "")
    local name = string.format("%s %s", base, stamp)
    if #name > 32 then
        name = name:sub(1, 32)
    end
    local attempt = name
    local suffix = 2
    local lookup = addon and addon.Profiles and addon.Profiles._layoutLookup or {}
    while lookup[attempt] do
        local trimmed = name
        local avail = math.max(6, 32 - (#tostring(suffix) + 1))
        if #trimmed > avail then
            trimmed = trimmed:sub(1, avail)
        end
        attempt = string.format("%s-%d", trimmed, suffix)
        suffix = suffix + 1
    end
    return attempt
end

local function cloneProfilePayload(preset, layoutName)
    local payload = preset and preset.scooterProfile
    if type(payload) ~= "table" then
        return nil, "Preset ScooterMod profile payload missing."
    end
    local copy = CopyTable(payload)
    copy.__preset = true
    copy.__presetSource = preset.id or preset.name or "preset"
    copy.__presetVersion = preset.version or "PENDING"
    copy.__presetLayout = layoutName
    return copy
end

local function _NormalizeLayoutName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

local function _LayoutNameExists(name)
    if not name then return false end
    if C_EditMode and type(C_EditMode.GetLayouts) == "function" then
        local li = C_EditMode.GetLayouts()
        if li and type(li.layouts) == "table" then
            for _, layout in ipairs(li.layouts) do
                if layout and layout.layoutName == name then
                    return true
                end
            end
        end
    end
    return false
end

local function importConsolePortProfile(preset, profileName)
    if not preset or not preset.consolePortProfile then
        return true
    end
    local cp = _G.ConsolePort
    if not cp then
        return false, "ConsolePort is required for this preset."
    end

    -- Attempt commonly-used import paths; future updates can refine this once the API is finalized.
    local importers = {
        cp.ImportProfile,
        cp.ImportBindingProfile,
        cp.ImportCustomProfile,
        cp.Profiles and cp.Profiles.Import,
    }
    for _, importer in ipairs(importers) do
        if type(importer) == "function" then
            local ok, err = pcall(importer, cp.Profiles or cp, preset.consolePortProfile, profileName)
            if ok then
                return true
            end
            return false, "ConsolePort import failed: " .. tostring(err)
        end
    end

    -- Fallback: stash payload for manual import; do not fail the preset.
    addon.ConsolePortPendingProfile = {
        target = profileName,
        payload = preset.consolePortProfile,
    }
    addon:Print("ConsolePort import API not detected; stored preset payload for manual import.")
    return true
end

function addon.EditMode:ImportPresetLayout(preset, opts)
    opts = opts or {}
    if type(preset) ~= "table" then
        return false, "Preset metadata missing."
    end
    local hasLayoutTable = type(preset.editModeLayout) == "table"
    local hasLegacyExport = type(preset.editModeExport) == "string" and preset.editModeExport ~= ""
    local hasSourceLayoutName = type(preset.sourceLayoutName) == "string" and preset.sourceLayoutName ~= ""
    if hasLegacyExport and not hasLayoutTable then
        return false, "Preset uses legacy Edit Mode export string format. Re-capture the preset with a raw layout table via /scoot debug editmode export and update core/presets.lua."
    end
    if not hasLayoutTable and not hasSourceLayoutName then
        return false, "Preset Edit Mode payload missing (requires editModeLayout or sourceLayoutName)."
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Cannot import presets during combat."
    end
    if not C_EditMode or type(C_EditMode.GetLayouts) ~= "function" or type(C_EditMode.SaveLayouts) ~= "function" then
        return false, "C_EditMode GetLayouts/SaveLayouts API unavailable."
    end
    if not LEO or not (LEO.IsReady and LEO:IsReady()) then
        return false, "Edit Mode library is not ready."
    end

    self.LoadLayouts()

    if hasLayoutTable then
        local okHash, hashErr = verifyLayoutHash(preset.editModeSha256, preset.editModeLayout, "Edit Mode layout")
        if not okHash then return false, hashErr end
    end

    -- Determine target layout/profile name (user-specified or auto-generated)
    local newLayoutName
    if opts and opts.targetName then
        newLayoutName = _NormalizeLayoutName(opts.targetName)
        if not newLayoutName then
            return false, "A name is required."
        end
        if C_EditMode and type(C_EditMode.IsValidLayoutName) == "function" and not C_EditMode.IsValidLayoutName(newLayoutName) then
            return false, HUD_EDIT_MODE_INVALID_LAYOUT_NAME or "Invalid layout name."
        end
        if _LayoutNameExists(newLayoutName) then
            return false, "A layout with that name already exists."
        end
        if addon and addon.db and addon.db.profiles and addon.db.profiles[newLayoutName] then
            return false, "A ScooterMod profile with that name already exists."
        end
    else
        newLayoutName = buildPresetInstanceName(preset)
    end

    local profileCopy, profileErr = cloneProfilePayload(preset, newLayoutName)
    if not profileCopy then
        return false, profileErr
    end
    if opts and opts.dryRun then
        -- Validate that the Edit Mode payload source is available without mutating
        -- layouts or AceDB state. Useful for authoring and CI-style checks.
        if not hasLayoutTable and hasSourceLayoutName then
            local li = C_EditMode.GetLayouts()
            local found = false
            if li and type(li.layouts) == "table" then
                for _, layout in ipairs(li.layouts) do
                    if layout and layout.layoutName == preset.sourceLayoutName then
                        found = true
                        break
                    end
                end
            end
            if not found then
                return false, "Dry run failed: source layout not found: " .. tostring(preset.sourceLayoutName)
            end
        end
        return true, newLayoutName
    end
    if hasLayoutTable then
        local li = C_EditMode.GetLayouts()
        if not (li and type(li.layouts) == "table") then
            return false, "Unable to read layouts."
        end
        local newLayout = CopyTable(preset.editModeLayout)
        newLayout.layoutName = newLayoutName
        newLayout.layoutType = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character or newLayout.layoutType
        newLayout.isPreset = nil
        newLayout.isModified = nil
        table.insert(li.layouts, newLayout)
        C_EditMode.SaveLayouts(li)
    else
        -- Development / authoring fallback:
        -- Clone an existing layout by name using C_EditMode.GetLayouts() + SaveLayouts().
        local li = C_EditMode.GetLayouts()
        if not (li and type(li.layouts) == "table") then
            return false, "Unable to read layouts."
        end
        local source
        for _, layout in ipairs(li.layouts) do
            if layout and layout.layoutName == preset.sourceLayoutName then
                source = layout
                break
            end
        end
        if not source then
            return false, "Source layout not found for preset: " .. tostring(preset.sourceLayoutName)
        end
        local newLayout = CopyTable(source)
        newLayout.layoutName = newLayoutName
        newLayout.layoutType = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character or newLayout.layoutType
        newLayout.isPreset = nil
        newLayout.isModified = nil
        table.insert(li.layouts, newLayout)
        C_EditMode.SaveLayouts(li)
    end

    self.SaveOnly()

    if addon and addon.Profiles and addon.Profiles.RequestSync then
        addon.Profiles:RequestSync("PresetImport")
    end

    if not addon or not addon.db or not addon.db.profiles then
        return false, "AceDB not initialized."
    end
    -- Ensure the profile metadata points at the final layout name (ImportLayout may
    -- return a modified name in some edge cases).
    if type(profileCopy) == "table" then
        profileCopy.__presetLayout = newLayoutName
    end
    addon.db.profiles[newLayoutName] = profileCopy

    if addon.Profiles and addon.Profiles.SwitchToProfile then
        addon.Profiles:SwitchToProfile(newLayoutName, { reason = "PresetImport", force = true })
    end

    local cpOk, cpErr = importConsolePortProfile(preset, newLayoutName)
    if not cpOk then
        addon:Print(cpErr)
    end

    addon:Print(string.format("Imported preset '%s' as new layout '%s'.", preset.name or preset.id or "Preset", newLayoutName))

    if not opts.skipReload and type(ReloadUI) == "function" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, ReloadUI)
        else
            ReloadUI()
        end
    end

    return true, newLayoutName
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

    -- Compatibility: Action Bars Icon Size behaves like an index slider internally on some clients.
    -- Force index-based handling in our embedded LEO so raw 50..200 maps to the correct index.
    local LEO_local2 = LibStub and LibStub("LibEditModeOverride-1.0")
    if LEO_local2 and _G and _G.Enum and _G.Enum.EditModeSystem then
        local candidates = {
            "MainActionBar",
            "MultiBarBottomLeft",
            "MultiBarBottomRight",
            "MultiBarRight",
            "MultiBarLeft",
            "MultiBar5",
            "MultiBar6",
            "MultiBar7",
            "PetActionBar",
        }
        for _, name in ipairs(candidates) do
            local fr = _G[name]
            if fr and addon.EditMode.HasEditModeSettings(fr) then
                local settingId = ResolveSettingId(fr, "icon_size")
                if settingId then
                    local sys = fr.system
                    LEO_local2._forceIndexBased = LEO_local2._forceIndexBased or {}
                    LEO_local2._forceIndexBased[sys] = LEO_local2._forceIndexBased[sys] or {}
                    LEO_local2._forceIndexBased[sys][settingId] = true
                end
            end
        end

        -- Micro Bar (Menu): treat Menu Size and Eye Size as index-based internally
        do
            local micro = _G["MicroMenuContainer"]
            if micro then
                local sys = micro.system or 13
                LEO_local2._forceIndexBased = LEO_local2._forceIndexBased or {}
                LEO_local2._forceIndexBased[sys] = LEO_local2._forceIndexBased[sys] or {}
                -- Known setting ids from runtime dumps
                LEO_local2._forceIndexBased[sys][2] = true -- Menu Size
                LEO_local2._forceIndexBased[sys][3] = true -- Eye Size
            else
                -- Fallback: set by known system id for retail
                local sys = 13
                LEO_local2._forceIndexBased = LEO_local2._forceIndexBased or {}
                LEO_local2._forceIndexBased[sys] = LEO_local2._forceIndexBased[sys] or {}
                LEO_local2._forceIndexBased[sys][2] = true
                LEO_local2._forceIndexBased[sys][3] = true
            end
        end
    end

    -- Treat Unit Frame Frame Size as index-based: Edit Mode stores an index (0..20) while UI presents 100..200.
    do
        local LEO_flag = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_flag and _G and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeUnitFrameSetting then
            local sysUF = _G.Enum.EditModeSystem.UnitFrame
            local settingFS = _G.Enum.EditModeUnitFrameSetting.FrameSize
            LEO_flag._forceIndexBased = LEO_flag._forceIndexBased or {}
            LEO_flag._forceIndexBased[sysUF] = LEO_flag._forceIndexBased[sysUF] or {}
            LEO_flag._forceIndexBased[sysUF][settingFS] = true
        end
    end

    -- Compatibility: Some clients persist Cast Bar Bar Size as an index; treat as index-based to avoid snapping to max.
    do
        local LEO_flag2 = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_flag2 and _G and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeCastBarSetting then
            local sysCB = _G.Enum.EditModeSystem.CastBar
            local settingBS = _G.Enum.EditModeCastBarSetting.BarSize
            LEO_flag2._forceIndexBased = LEO_flag2._forceIndexBased or {}
            LEO_flag2._forceIndexBased[sysCB] = LEO_flag2._forceIndexBased[sysCB] or {}
            LEO_flag2._forceIndexBased[sysCB][settingBS] = true
        end
    end
end
