local addonName, addon = ...

-- Lightweight copy window for debug dumps (separate from Table Inspector copy)
local function ShowDebugCopyWindow(title, text)
    if not addon.DebugCopyWindow then
        local f = CreateFrame("Frame", "ScooterDebugCopyWindow", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(780, 540)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() f:StartMoving() end)
        f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 6, 0)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 42)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false)
        eb:SetWidth(720)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(eb)
        f.EditBox = eb
        local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyBtn:SetSize(100, 22)
        copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
        copyBtn:SetText("Copy All")
        copyBtn:SetScript("OnClick", function()
            f.EditBox:HighlightText()
            f.EditBox:SetFocus()
        end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        closeBtn:SetText(CLOSE or "Close")
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        addon.DebugCopyWindow = f
    end
    local f = addon.DebugCopyWindow
    if f.title then f.title:SetText(title or "Scooter Debug") end
    if f.EditBox then f.EditBox:SetText(text or "") end
    f:Show()
    if f.EditBox then f.EditBox:HighlightText(); f.EditBox:SetFocus() end
end

function addon.DebugShowWindow(title, payload)
    if type(payload) == "table" then
        payload = table.concat(payload, "\n")
    end
    ShowDebugCopyWindow(title, payload or "")
end

local function ResolveFrameByKey(key)
    key = tostring(key or ""):lower()
    local map = {
        ab1 = "MainActionBar",
        ab2 = "MultiBarBottomLeft",
        ab3 = "MultiBarBottomRight",
        ab4 = "MultiBarRight",
        ab5 = "MultiBarLeft",
        ab6 = "MultiBar5",
        ab7 = "MultiBar6",
        ab8 = "MultiBar7",
        essential = "EssentialCooldownViewer",
        utility = "UtilityCooldownViewer",
        -- New debug targets
        micro = "MicroMenuContainer",
        stance = "StanceBar",
        -- Aura Frame
        buffs  = "BuffFrame",
        debuffs = "DebuffFrame",
        -- Objective Tracker
        tracker = "ObjectiveTrackerFrame",
        objectivetracker = "ObjectiveTrackerFrame",
        -- Unit Frames
        player = "PlayerFrame",
        target = "TargetFrame",
        focus  = "FocusFrame",
        pet    = "PetFrame",
    }
    -- Special-case resolution for Unit Frames using Edit Mode's registry for reliability
    if key == "player" or key == "target" or key == "focus" or key == "pet" then
        local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
        local EMSys = _G.Enum and _G.Enum.EditModeSystem
        local mgr = _G.EditModeManagerFrame
        local idx = EM and (
            key == "player" and EM.Player or
            key == "target" and EM.Target or
            key == "focus"  and EM.Focus  or
            key == "pet"    and EM.Pet    or nil)
        if mgr and idx and EMSys and mgr.GetRegisteredSystemFrame then
            local f = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
            if f then return f, (map[key] or key) end
        end
    end
    local name = map[key] or key -- allow raw global name
    return _G[name], name
end

local function DumpEditModeSettingsForFrame(frame, frameName)
    local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
    if not (LEO and LEO.IsReady and LEO:IsReady()) then
        return "Edit Mode is not ready. Open Edit Mode once to initialize."
    end
    if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    if not frame or not frame.system then
        return string.format("Frame not found or not Edit Mode managed: %s", tostring(frameName))
    end
    local lines = {}
    local function push(s) table.insert(lines, s) end
    push(string.format("Frame: %s  system=%s index=%s", tostring(frameName), tostring(frame.system), tostring(frame.systemIndex)))

    -- Special Aura Frame dump for Buffs/Debuffs to troubleshoot Orientation/Wrap/Direction.
    local sysEnum = _G.Enum and _G.Enum.EditModeSystem
    local dirEnum = _G.Enum and _G.Enum.AuraFrameIconDirection
    if sysEnum and frame.system == sysEnum.AuraFrame and dirEnum then
        local LEO = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO and LEO.IsReady and LEO:IsReady() then
            if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
            local function safeGet(settingLogical)
                local id = addon.EditMode and addon.EditMode.ResolveSettingIdForComponent and addon.EditMode.ResolveSettingIdForComponent({ frameName = frameName }, settingLogical)
                if not id then return "id=nil", nil end
                local ok, v = pcall(function() return LEO:GetFrameSetting(frame, id) end)
                if not ok then return string.format("id=%s error", tostring(id)), nil end
                return string.format("id=%s value=%s", tostring(id), tostring(v)), v
            end

            push("")
            push("== Aura Frame Orientation/Wrap/Direction (raw) ==")
            local orientStr, orientVal = safeGet("orientation")
            local wrapStr,   wrapVal   = safeGet("icon_wrap")
            local dirStr,    dirVal    = safeGet("icon_direction")
            push("Orientation: "..orientStr)
            push("IconWrap   : "..wrapStr)
            push("IconDir    : "..dirStr)

            local function mapDirEnum(v)
                if v == dirEnum.Up then return "Up"
                elseif v == dirEnum.Down then return "Down"
                elseif v == dirEnum.Left then return "Left"
                elseif v == dirEnum.Right then return "Right"
                end
                return tostring(v)
            end

            if wrapVal ~= nil or dirVal ~= nil then
                push("")
                push("Interpreted (AuraFrameIconDirection):")
                push("  Wrap enum -> "..mapDirEnum(wrapVal))
                push("  Dir  enum -> "..mapDirEnum(dirVal))
            end

            -- Also dump ScooterMod DB snapshot for Buffs component if present.
            if addon.Components and addon.Components.buffs then
                local c = addon.Components.buffs
                push("")
                push("ScooterMod Buffs DB snapshot:")
                push("  orientation = "..tostring(c.db and c.db.orientation))
                push("  iconWrap    = "..tostring(c.db and c.db.iconWrap))
                push("  direction   = "..tostring(c.db and c.db.direction))
            end
        else
            push("")
            push("Aura Frame: LibEditModeOverride not ready; raw dump unavailable.")
        end
        push("")
        push("-- Full Edit Mode setting list follows --")
    end
    local entries = _G.EditModeSettingDisplayInfoManager and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo and _G.EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[frame.system]
    if type(entries) ~= "table" then
        push("No setting display info available for this system.")
        return table.concat(lines, "\n")
    end
    -- Sort by setting id for stability
    table.sort(entries, function(a,b) return (a.setting or 0) < (b.setting or 0) end)
    for _, setup in ipairs(entries) do
        local id = setup.setting
        local name = setup.name or "(unnamed)"
        local tp = setup.type
        local val
        local ok, v = pcall(function() return LEO:GetFrameSetting(frame, id) end)
        if ok then val = v else val = "<error>" end
        if tp == Enum.EditModeSettingDisplayType.Slider then
            local minV = setup.minValue; local maxV = setup.maxValue; local step = setup.stepSize
            push(string.format("[%s] %s (Slider min=%s max=%s step=%s) = %s", tostring(id), name, tostring(minV), tostring(maxV), tostring(step), tostring(val)))
        elseif tp == Enum.EditModeSettingDisplayType.Dropdown then
            local opts = ""
            if type(setup.options) == "table" then
                local buf = {}
                for _, opt in ipairs(setup.options) do table.insert(buf, string.format("%s:%s", tostring(opt.value), tostring(opt.text or opt.value))) end
                opts = table.concat(buf, ", ")
            end
            push(string.format("[%s] %s (Dropdown options=%s) = %s", tostring(id), name, opts, tostring(val)))
        elseif tp == Enum.EditModeSettingDisplayType.Checkbox then
            push(string.format("[%s] %s (Checkbox 0/1) = %s", tostring(id), name, tostring(val)))
        else
            push(string.format("[%s] %s (type=%s) = %s", tostring(id), name, tostring(tp), tostring(val)))
        end
    end
    return table.concat(lines, "\n")
end

function addon.DebugDump(target)
    local frame, name = ResolveFrameByKey(target)
    local dump = DumpEditModeSettingsForFrame(frame, name)
    ShowDebugCopyWindow("Edit Mode Settings - "..tostring(name), dump)
end

--[[----------------------------------------------------------------------------
    Off-screen drag debugging

    Purpose:
      The off-screen unlock feature is sensitive to which exact frame Edit Mode
      is dragging (system wrapper vs. proxy/handle vs. underlying unit frame).
      This dump prints clamp state + anchor summary for Player/Target candidates.

    Usage:
      /scoot debug offscreen
----------------------------------------------------------------------------]]--

local function _SafeName(f)
    if not f then return "<nil>" end
    if f.GetName then
        local ok, n = pcall(f.GetName, f)
        if ok and n and n ~= "" then return n end
    end
    return tostring(f)
end

local function _SafeBoolCall(f, methodName)
    if not (f and f[methodName]) then return "<no:"..methodName..">" end
    local ok, v = pcall(f[methodName], f)
    if not ok then return "<err>" end
    return v and true or false
end

local function _SafeClampInsets(f)
    if not (f and f.GetClampRectInsets) then return "<no:GetClampRectInsets>" end
    local ok, l, r, t, b = pcall(f.GetClampRectInsets, f)
    if not ok then return "<err>" end
    return string.format("l=%s r=%s t=%s b=%s", tostring(l or 0), tostring(r or 0), tostring(t or 0), tostring(b or 0))
end

local function _SafePointSummary(f)
    if not (f and f.GetNumPoints and f.GetPoint) then return "<no:GetPoint>" end
    local okN, n = pcall(f.GetNumPoints, f)
    if not okN or not n or n <= 0 then return "<no_points>" end
    local ok, point, relTo, relPoint, xOfs, yOfs = pcall(f.GetPoint, f, 1)
    if not ok or not point then return "<err>" end
    return string.format("%s -> %s %s (x=%s y=%s) (#pts=%d)",
        tostring(point),
        _SafeName(relTo),
        tostring(relPoint or point),
        tostring(xOfs or 0),
        tostring(yOfs or 0),
        tonumber(n) or 0
    )
end

local function _CollectOffscreenCandidates(unitKey)
    local out, seen = {}, {}
    local function add(f)
        if not f or type(f) ~= "table" then return end
        if seen[f] then return end
        seen[f] = true
        table.insert(out, f)
    end

    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    local idx = EM and ((unitKey == "Player" and EM.Player) or (unitKey == "Target" and EM.Target) or nil) or nil
    local reg = (mgr and idx and EMSys and mgr.GetRegisteredSystemFrame) and mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx) or nil
    add(reg)
    if reg then
        add(rawget(reg, "DragHandle"))
        add(rawget(reg, "dragHandle"))
        add(rawget(reg, "Selection"))
        add(rawget(reg, "selection"))
        add(rawget(reg, "Mover"))
        add(rawget(reg, "mover"))
        add(rawget(reg, "SystemFrame"))
        add(rawget(reg, "systemFrame"))
        add(rawget(reg, "frame"))
        add(rawget(reg, "managedFrame"))
        if reg.GetChildren then
            local kids = { reg:GetChildren() }
            for i = 1, math.min(#kids, 20) do
                add(kids[i])
            end
        end
    end
    add(unitKey == "Player" and _G.PlayerFrame or nil)
    add(unitKey == "Target" and _G.TargetFrame or nil)

    -- parent chain (bounded)
    for i = 1, #out do
        local f = out[i]
        local p = (f and f.GetParent) and f:GetParent() or nil
        if p and type(p) == "table" then
            add(p)
            local pp = (p.GetParent and p:GetParent()) or nil
            if pp and type(pp) == "table" then add(pp) end
        end
    end

    return out, reg
end

function addon.DebugOffscreenUnlockDump()
    local lines = {}
    local function push(s) table.insert(lines, s) end

    local profile = addon and addon.db and addon.db.profile
    local uf = profile and rawget(profile, "unitFrames")
    push("ScooterMod Off-screen Unlock Debug")
    push("Note: This is a diagnostic dump. Copy/paste into chat with your agent if needed.")
    push("")

    for _, unitKey in ipairs({ "Player", "Target" }) do
        local unitCfg = (type(uf) == "table") and rawget(uf, unitKey) or nil
        local misc = (type(unitCfg) == "table") and rawget(unitCfg, "misc") or nil
        local allow = (type(misc) == "table") and (rawget(misc, "allowOffscreenDrag") == true) or false
        local legacy = (type(misc) == "table") and (tonumber(rawget(misc, "containerOffsetX") or 0) or 0) or 0

        push("== "..unitKey.." ==")
        push("DB: allowOffscreenDrag="..tostring(allow).."  legacy_containerOffsetX="..tostring(legacy))

        local candidates, reg = _CollectOffscreenCandidates(unitKey)
        push("RegisteredSystemFrame: ".._SafeName(reg))
        push("Candidates: "..tostring(#candidates))

        for i, f in ipairs(candidates) do
            local hasClamp = (f and f.SetClampedToScreen) and true or false
            local hasInsets = (f and f.SetClampRectInsets) and true or false
            push(string.format("  [%02d] %s", i, _SafeName(f)))
            push("       hasSetClampedToScreen="..tostring(hasClamp).."  hasSetClampRectInsets="..tostring(hasInsets))
            push("       IsClampedToScreen="..tostring(_SafeBoolCall(f, "IsClampedToScreen")))
            push("       ClampInsets="..tostring(_SafeClampInsets(f)))
            -- ScooterMod runtime flags (if any)
            local active = f and rawget(f, "_ScootOffscreenUnclampActive")
            local enforce = f and rawget(f, "_ScootOffscreenEnforceEnabled")
            push("       ScootFlags: active="..tostring(active).." enforce="..tostring(enforce))
            push("       Point1="..tostring(_SafePointSummary(f)))
        end

        push("")
    end

    ShowDebugCopyWindow("Off-screen Unlock Debug", table.concat(lines, "\n"))
end

--[[----------------------------------------------------------------------------
    Profile export (AceDB -> copyable Lua table)

    Purpose:
      - Produce a deterministic, copy/paste friendly Lua table literal for a given
        AceDB profile (usually the current profile).
      - Intended for preset ingestion into the preset payload files under core/preset_*.lua
        (for example core/preset_scooterui.lua).
----------------------------------------------------------------------------]]--

local function _IsIdentifierKey(s)
    return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function _SortKeysStable(keys)
    local typeOrder = {
        number = 1,
        string = 2,
        boolean = 3,
        table = 4,
        userdata = 5,
        ["function"] = 6,
        thread = 7,
        ["nil"] = 8,
    }
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        local oa, ob = typeOrder[ta] or 99, typeOrder[tb] or 99
        if oa ~= ob then return oa < ob end
        if ta == "number" then return a < b end
        if ta == "string" then return a < b end
        if ta == "boolean" then return (a == false and b == true) end
        return tostring(a) < tostring(b)
    end)
end

local function _SerializeLuaValue(value, indent, visited, depth)
    indent = indent or 0
    visited = visited or {}
    depth = depth or 0

    local t = type(value)
    if t == "nil" then return "nil" end
    if t == "boolean" then return value and "true" or "false" end
    if t == "number" then
        -- Preserve numeric fidelity (avoid locale formatting); tostring is fine in WoW Lua.
        return tostring(value)
    end
    if t == "string" then
        return string.format("%q", value)
    end
    if t ~= "table" then
        -- Unsupported types should not appear in AceDB profiles, but guard anyway.
        return "nil --[[unsupported:" .. t .. "]]"
    end

    if visited[value] then
        -- Cycles are unexpected in AceDB; keep the output valid Lua.
        return "nil --[[cycle]]"
    end
    if depth > 25 then
        return "nil --[[max_depth]]"
    end
    visited[value] = true

    local pad = string.rep("  ", indent)
    local padIn = string.rep("  ", indent + 1)

    -- Detect simple array (1..n) with no extra keys to keep output compact.
    local isArray = true
    local maxIndex = 0
    local count = 0
    for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            isArray = false
            break
        end
        if k > maxIndex then maxIndex = k end
        count = count + 1
    end
    if isArray and count ~= maxIndex then
        isArray = false
    end

    local out = {}
    table.insert(out, "{\n")

    if isArray then
        for i = 1, maxIndex do
            local v = value[i]
            table.insert(out, padIn)
            table.insert(out, _SerializeLuaValue(v, indent + 1, visited, depth + 1))
            table.insert(out, ",\n")
        end
    else
        local keys = {}
        for k in pairs(value) do
            table.insert(keys, k)
        end
        _SortKeysStable(keys)

        for _, k in ipairs(keys) do
            local v = value[k]
            local keyExpr
            if _IsIdentifierKey(k) then
                keyExpr = k
            else
                local kt = type(k)
                if kt == "string" then
                    keyExpr = "[" .. string.format("%q", k) .. "]"
                elseif kt == "number" or kt == "boolean" then
                    keyExpr = "[" .. tostring(k) .. "]"
                else
                    -- Fall back to stringifying the key to keep the output valid.
                    keyExpr = "[" .. string.format("%q", tostring(k)) .. "]"
                end
            end

            table.insert(out, padIn)
            table.insert(out, keyExpr)
            table.insert(out, " = ")
            table.insert(out, _SerializeLuaValue(v, indent + 1, visited, depth + 1))
            table.insert(out, ",\n")
        end
    end

    table.insert(out, pad)
    table.insert(out, "}")
    visited[value] = nil
    return table.concat(out, "")
end

function addon.DebugExportProfile(profileName)
    if not addon or not addon.db then
        ShowDebugCopyWindow("ScooterMod Profile Export", "AceDB not initialized.")
        return
    end

    local db = addon.db
    local key = profileName
    if type(key) ~= "string" or key == "" then
        if db.GetCurrentProfile then
            key = db:GetCurrentProfile()
        end
    end
    if type(key) ~= "string" or key == "" then
        key = "<unknown>"
    end

    local profile
    if db.profiles and db.profiles[key] then
        profile = db.profiles[key]
    else
        -- Fallback to currently active profile table (includes live unsaved changes).
        profile = db.profile
    end

    if type(profile) ~= "table" then
        ShowDebugCopyWindow("ScooterMod Profile Export - " .. tostring(key), "Profile table not found.")
        return
    end

    local snapshot = CopyTable(profile)
    local header = table.concat({
        "-- ScooterMod profile export",
        "-- Profile: " .. tostring(key),
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
        "",
    }, "\n")

    local payload = _SerializeLuaValue(snapshot, 0, {}, 0)
    ShowDebugCopyWindow("ScooterMod Profile Export - " .. tostring(key), header .. payload)

    -- Persist the last export into SavedVariables so preset ingestion can be
    -- performed without manual copy/paste (run export, then /reload or logout).
    -- NOTE: This is stored in AceDB.global intentionally (not per-profile).
    if db and db.global then
        db.global.presetCaptures = db.global.presetCaptures or {}
        db.global.presetCaptures.profile = {
            profileKey = key,
            capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
            payload = payload,
        }
        if _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
            local ok, hash = pcall(_G.C_Crypto.Hash, "SHA256", payload)
            if ok and type(hash) == "string" and hash ~= "" then
                db.global.presetCaptures.profile.sha256 = string.lower(hash)
            end
        end
    end
end

local function _FindLayoutInfoByName(layoutName)
    if not _G.C_EditMode or type(_G.C_EditMode.GetLayouts) ~= "function" then
        return nil, "C_EditMode.GetLayouts unavailable."
    end
    local li = _G.C_EditMode.GetLayouts()
    if not (li and type(li.layouts) == "table") then
        return nil, "Unable to read layouts."
    end
    if type(layoutName) == "string" and layoutName ~= "" then
        for _, layout in ipairs(li.layouts) do
            if layout and layout.layoutName == layoutName then
                return layout
            end
        end
        return nil, "Layout not found: " .. tostring(layoutName)
    end
    local idx = li.activeLayout
    local active = idx and li.layouts and li.layouts[idx]
    if not active then
        return nil, "Active layout not found."
    end
    return active
end

function addon.DebugExportEditModeLayout(layoutName)
    if not addon or not addon.db then
        ShowDebugCopyWindow("Edit Mode Layout Export", "AceDB not initialized.")
        return
    end
    if not _G.C_EditMode or type(_G.C_EditMode.ConvertLayoutInfoToString) ~= "function" then
        ShowDebugCopyWindow("Edit Mode Layout Export", "C_EditMode.ConvertLayoutInfoToString API unavailable.")
        return
    end

    local layoutInfo, err = _FindLayoutInfoByName(layoutName)
    if not layoutInfo then
        ShowDebugCopyWindow("Edit Mode Layout Export", err or "Unable to resolve layout.")
        return
    end

    local ok, exportString = pcall(_G.C_EditMode.ConvertLayoutInfoToString, layoutInfo)
    if not ok or type(exportString) ~= "string" or exportString == "" then
        ShowDebugCopyWindow("Edit Mode Layout Export", "Export failed: " .. tostring(exportString))
        return
    end

    local name = layoutInfo.layoutName or layoutName or "Active"
    local header = table.concat({
        "-- Edit Mode layout export (Blizzard Share string)",
        "-- Layout: " .. tostring(name),
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
        "",
    }, "\n")

    ShowDebugCopyWindow("Edit Mode Layout Export - " .. tostring(name), header .. exportString)

    -- Persist to SavedVariables for agent ingestion (run export, then /reload or logout).
    local db = addon.db
    db.global = db.global or {}
    db.global.presetCaptures = db.global.presetCaptures or {}
    db.global.presetCaptures.editMode = {
        layoutName = name,
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        export = exportString,
    }
    if _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
        local okHash, hash = pcall(_G.C_Crypto.Hash, "SHA256", exportString)
        if okHash and type(hash) == "string" and hash ~= "" then
            db.global.presetCaptures.editMode.sha256 = string.lower(hash)
        end
    end
end

function addon.DebugExportEditModeLayoutTable(layoutName)
    if not addon or not addon.db then
        ShowDebugCopyWindow("Edit Mode Layout Export (Table)", "AceDB not initialized.")
        return
    end
    if not _G.C_EditMode or type(_G.C_EditMode.GetLayouts) ~= "function" then
        ShowDebugCopyWindow("Edit Mode Layout Export (Table)", "C_EditMode.GetLayouts API unavailable.")
        return
    end

    local layoutInfo, err = _FindLayoutInfoByName(layoutName)
    if not layoutInfo then
        ShowDebugCopyWindow("Edit Mode Layout Export (Table)", err or "Unable to resolve layout.")
        return
    end

    local snapshot = CopyTable(layoutInfo)
    local name = snapshot.layoutName or layoutName or "Active"

    local shaLine = nil
    if _G.C_EditMode and type(_G.C_EditMode.ConvertLayoutInfoToString) == "function" and _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
        local okExport, exportString = pcall(_G.C_EditMode.ConvertLayoutInfoToString, snapshot)
        if okExport and type(exportString) == "string" and exportString ~= "" then
            local okHash, hash = pcall(_G.C_Crypto.Hash, "SHA256", exportString)
            if okHash and type(hash) == "string" and hash ~= "" then
                shaLine = "-- SHA256: " .. string.lower(hash)
            end
        end
    end

    local headerParts = {
        "-- Edit Mode layout export (raw layout table)",
        "-- Layout: " .. tostring(name),
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
    }
    if shaLine then table.insert(headerParts, shaLine) end
    table.insert(headerParts, "")
    local header = table.concat(headerParts, "\n")

    local payload = _SerializeLuaValue(snapshot, 0, {}, 0)
    ShowDebugCopyWindow("Edit Mode Layout Export (Table) - " .. tostring(name), header .. payload)

    -- Persist to SavedVariables for agent ingestion (run export, then /reload or logout).
    local db = addon.db
    db.global = db.global or {}
    db.global.presetCaptures = db.global.presetCaptures or {}
    db.global.presetCaptures.editModeLayout = {
        layoutName = name,
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        payload = payload,
    }

    if shaLine then
        db.global.presetCaptures.editModeLayout.sha256 = shaLine:gsub("^%-%- SHA256:%s*", "")
    end
end

--[[----------------------------------------------------------------------------
    ConsolePort export (SavedVariables -> copyable Lua table)

    Purpose:
      - Capture a deterministic snapshot of ConsolePort-related SavedVariables
        for ingestion into ScooterDeck preset payloads.
      - We intentionally avoid exporting keybindings and action loadouts since
        they are often character-specific and can be disruptive when imported.

    Usage:
      /scoot debug consoleport export
----------------------------------------------------------------------------]]--

local function _SafeCopyGlobal(name)
    local v = _G[name]
    if type(v) == "table" then
        return CopyTable(v)
    end
    if v ~= nil then
        -- Preserve non-table values, but keep the payload valid.
        return v
    end
    return nil
end

function addon.DebugExportConsolePortProfile()
    if not addon or not addon.db then
        ShowDebugCopyWindow("ConsolePort Export", "AceDB not initialized.")
        return
    end

    -- ConsolePort base addon must be loaded for these globals to exist.
    if not _G.ConsolePort and not _G.ConsolePortSettings then
        ShowDebugCopyWindow("ConsolePort Export", "ConsolePort does not appear to be loaded on this client.")
        return
    end

    local payloadTable = {
        -- ConsolePort.toc: SavedVariables
        ConsolePortSettings = _SafeCopyGlobal("ConsolePortSettings"),
        ConsolePortDevices = _SafeCopyGlobal("ConsolePortDevices"),
        ConsolePortShared = _SafeCopyGlobal("ConsolePortShared"),
        ConsolePortBindingIcons = _SafeCopyGlobal("ConsolePortBindingIcons"),

        -- ConsolePort.toc: SavedVariablesPerCharacter (exported for completeness; may be used by rings)
        ConsolePortUtility = _SafeCopyGlobal("ConsolePortUtility"),
        ConsolePortUtilityDeprecated = _SafeCopyGlobal("ConsolePortUtilityDeprecated"),

        -- ConsolePort_Bar addon SavedVariables (if installed/loaded)
        ConsolePort_BarLayout = _SafeCopyGlobal("ConsolePort_BarLayout"),
        ConsolePort_BarPresets = _SafeCopyGlobal("ConsolePort_BarPresets"),
        -- Intentionally omitted: ConsolePort_BarLoadout (action placement / macros)
    }

    -- Trim nil keys so the output stays small and deterministic.
    for k, v in pairs(CopyTable(payloadTable)) do
        if v == nil then
            payloadTable[k] = nil
        end
    end

    local header = table.concat({
        "-- ConsolePort export (SavedVariables snapshot)",
        "-- Captured: " .. (date and date("%Y-%m-%d %H:%M:%S") or "unknown"),
        "-- Note: bindings and action loadouts are intentionally omitted.",
        "",
    }, "\n")

    local payload = _SerializeLuaValue(payloadTable, 0, {}, 0)
    ShowDebugCopyWindow("ConsolePort Export", header .. payload)

    -- Persist to SavedVariables for ingestion (run export, then /reload or logout).
    local db = addon.db
    db.global = db.global or {}
    db.global.presetCaptures = db.global.presetCaptures or {}
    db.global.presetCaptures.consolePort = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        payload = payload,
    }
    if _G.C_Crypto and type(_G.C_Crypto.Hash) == "function" then
        local okHash, hash = pcall(_G.C_Crypto.Hash, "SHA256", payload)
        if okHash and type(hash) == "string" and hash ~= "" then
            db.global.presetCaptures.consolePort.sha256 = string.lower(hash)
        end
    end
end

--[[----------------------------------------------------------------------------
    Table Inspector copy support

    Purpose:
      - Attach a "Copy" button to Blizzard's Table Inspector (/tinspect)
      - Provide /scoot attr command to dump Table Inspector or Frame Stack content

    Usage:
      /scoot attr
----------------------------------------------------------------------------]]--

local function SafeCall(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

-- 12.0 secret value handling: some getters return "secret" values that cannot be
-- used in string operations, comparisons, or arithmetic. We detect these by
-- attempting the operation in a pcall. IMPORTANT: Even comparing a secret to nil
-- can fail, so ALL operations must be wrapped in pcall.

-- Returns a guaranteed-safe string, or fallback if the value is a secret
-- IMPORTANT: In 12.0, even tostring(secret) can return a "tainted" value that
-- passes initial checks but fails in table.concat. We must verify the result
-- is a real Lua string type AND can be used in string operations.
local function safeString(value, fallback)
    fallback = fallback or "<secret>"
    local result
    local ok = pcall(function()
        -- Check if value is nil (comparison can fail on secrets)
        if value == nil then return end
        -- Try to convert to string
        local str = tostring(value)
        -- Verify it's actually a string type (not a secret masquerading as one)
        if type(str) ~= "string" then return end
        -- Verify it can be used in string operations
        local test = str .. ""
        -- Verify it has reasonable content (not a weird secret representation)
        if #test < 0 then return end -- length check
        -- Final test: can we format it?
        local formatted = string.format("%s", str)
        if type(formatted) ~= "string" then return end
        result = str
    end)
    -- Double-check the result is actually usable
    if ok and result and type(result) == "string" then
        -- One more pcall to verify the result is truly usable
        local finalOk = pcall(function()
            local _ = result .. ""
            local _ = string.format("%s", result)
        end)
        if finalOk then
            return result
        end
    end
    return fallback
end

-- Alias for compatibility
local function safeToString(value)
    return safeString(value, "<secret>")
end

-- Returns true only if the value can be safely used as a string
local function isUsableValue(value)
    local ok = pcall(function()
        if value == nil then return end
        local str = tostring(value)
        local _ = str .. ""
    end)
    return ok
end

-- Alias for compatibility
local function isUsableString(value)
    return isUsableValue(value)
end

local function GetDebugNameSafe(obj)
    if not obj then return nil end
    local ok, result = pcall(function()
        if not obj.GetDebugName then return nil end
        local name = obj:GetDebugName()
        if name == nil then return nil end
        -- Verify it's usable
        local _ = name .. ""
        return name
    end)
    if ok and result then
        return result
    end
    return nil
end

local function TableInspectorBuildDump(focusedTable)
    if not focusedTable then return "[No Table Selected]" end

    local out = {}
    local function push(line)
        local safeLine = safeString(line, "[unreadable]")
        if type(safeLine) == "string" then
            table.insert(out, safeLine)
        end
    end

    -- 12.0 STRATEGY: Instead of pairs() iteration (which returns secrets),
    -- call specific known frame methods directly. These are more likely to work.

    push("Frame Information")
    push(string.rep("-", 60))

    -- Try to get basic identity info via explicit method calls
    local function tryGet(label, fn)
        local ok, val = pcall(fn)
        if ok and val ~= nil then
            -- Verify the value is usable (not a secret)
            local strOk, str = pcall(function()
                local s = tostring(val)
                local _ = s .. "" -- verify string ops work
                return s
            end)
            if strOk and str then
                push(label .. ": " .. str)
                return true
            end
        end
        return false
    end

    -- Identity
    tryGet("Name", function() return focusedTable:GetName() end)
    tryGet("DebugName", function() return focusedTable:GetDebugName() end)
    tryGet("ObjectType", function() return focusedTable:GetObjectType() end)

    -- Dimensions (these often work)
    tryGet("Width", function() return focusedTable:GetWidth() end)
    tryGet("Height", function() return focusedTable:GetHeight() end)
    tryGet("Scale", function() return focusedTable:GetScale() end)
    tryGet("EffectiveScale", function() return focusedTable:GetEffectiveScale() end)
    tryGet("Alpha", function() return focusedTable:GetAlpha() end)

    -- Visibility/State
    tryGet("IsShown", function() return focusedTable:IsShown() end)
    tryGet("IsVisible", function() return focusedTable:IsVisible() end)
    tryGet("IsProtected", function() return focusedTable:IsProtected() end)
    tryGet("IsForbidden", function() return focusedTable:IsForbidden() end)

    -- Frame Level/Strata
    tryGet("FrameLevel", function() return focusedTable:GetFrameLevel() end)
    tryGet("FrameStrata", function() return focusedTable:GetFrameStrata() end)

    -- Parent info
    local parent = SafeCall(function() return focusedTable:GetParent() end)
    if parent then
        tryGet("Parent", function() return parent:GetDebugName() or parent:GetName() or "<unnamed>" end)
    end

    -- Build ancestry chain (this is the most useful part for copying frame paths)
    local ancestry = {}
    local current = focusedTable
    local depth = 0
    while current and depth < 20 do
        local name = GetDebugNameSafe(current)
        table.insert(ancestry, 1, name or "<unnamed>")
        current = SafeCall(function() return current:GetParent() end)
        depth = depth + 1
    end

    -- Add a clean "Full Path" line at the top for easy copying
    if #ancestry > 0 then
        push("")
        push("Full Path (for copying):")
        local pathOk, fullPath = pcall(table.concat, ancestry, ".")
        if pathOk and fullPath then
            push(fullPath)
        end
    end

    push("")
    push("Ancestry (indented):")
    for i, name in ipairs(ancestry) do
        local indent = string.rep("  ", i - 1)
        push(indent .. name)
    end

    -- Anchor points (often partially readable)
    -- IMPORTANT: numPoints might be a secret - extract as safe number inside pcall
    local safeNumPoints = 0
    pcall(function()
        local np = focusedTable:GetNumPoints()
        if np and type(np) == "number" and np > 0 then
            safeNumPoints = np
        end
    end)
    if safeNumPoints > 0 then
        push("")
        push("Anchor Points:")
        for i = 1, safeNumPoints do
            local point, relTo, relPoint, x, y = SafeCall(function()
                return focusedTable:GetPoint(i)
            end)
            if point then
                local parts = {}
                -- Point name (usually works)
                local pointOk, pointStr = pcall(tostring, point)
                if pointOk then table.insert(parts, pointStr) end

                -- Relative frame
                if relTo then
                    local relName = GetDebugNameSafe(relTo) or "<frame>"
                    table.insert(parts, "-> " .. relName)
                end

                -- Relative point (may be secret)
                if relPoint then
                    local rpOk, rpStr = pcall(tostring, relPoint)
                    if rpOk then table.insert(parts, "(" .. rpStr .. ")") end
                end

                -- Offsets (often secrets in 12.0)
                if x and y and type(x) == "number" and type(y) == "number" then
                    local offsetOk, offsetStr = pcall(string.format, "%.1f, %.1f", x, y)
                    if offsetOk then table.insert(parts, "offset: " .. offsetStr) end
                end

                if #parts > 0 then
                    local lineOk, line = pcall(table.concat, parts, " ")
                    if lineOk then push("  [" .. i .. "] " .. line) end
                end
            end
        end
    end

    -- Children (GetDebugName usually works on child references)
    -- Wrap everything in pcall to handle any secret contamination
    pcall(function()
        local children = { focusedTable:GetChildren() }
        if children and #children > 0 then
            push("")
            push("Children:")
            for _, child in ipairs(children) do
                local childName = GetDebugNameSafe(child)
                if childName then
                    push("  " .. childName)
                end
            end
        end
    end)

    -- Regions
    pcall(function()
        local regions = { focusedTable:GetRegions() }
        if regions and #regions > 0 then
            push("")
            push("Regions:")
            for _, region in ipairs(regions) do
                local regionName = GetDebugNameSafe(region)
                local regionType = nil
                pcall(function() regionType = region:GetObjectType() end)
                if regionName or regionType then
                    local desc = regionName or "<unnamed>"
                    if regionType then desc = desc .. " (" .. regionType .. ")" end
                    push("  " .. desc)
                end
            end
        end
    end)

    -- Final assembly
    local ok, result = pcall(table.concat, out, "\n")
    if ok and type(result) == "string" then
        return result
    end
    return "[Error building dump - secret values detected]"
end

-- Separate copy window for Table Inspector (reuse pattern from ShowDebugCopyWindow)
local function ShowTableInspectorCopyWindow(title, text)
    if not addon.TableInspectorCopyWindow then
        local f = CreateFrame("Frame", "ScooterTableInspectorCopyWindow", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(740, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() f:StartMoving() end)
        f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 6, 0)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 42)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false)
        eb:SetWidth(680)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(eb)
        f.EditBox = eb
        local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyBtn:SetSize(100, 22)
        copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
        copyBtn:SetText("Copy All")
        copyBtn:SetScript("OnClick", function()
            f.EditBox:HighlightText()
            f.EditBox:SetFocus()
        end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        closeBtn:SetText(CLOSE or "Close")
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        addon.TableInspectorCopyWindow = f
    end
    local f = addon.TableInspectorCopyWindow
    if f.title then f.title:SetText(title or "Copied Output") end
    if f.EditBox then f.EditBox:SetText(text or "") end
    f:Show()
    if f.EditBox then f.EditBox:HighlightText(); f.EditBox:SetFocus() end
end

-- Extract text directly from FrameStackTooltip's displayed lines
-- This reads what Blizzard is actually showing, bypassing GetDebugName() secrets
-- IMPORTANT: Must be defined before AttachTableInspectorCopyButton which calls it
--
-- 12.0 CRITICAL: GetText() returns secret values even on Blizzard's own tooltips.
-- We must wrap ALL operations (including type() checks) in pcall because
-- comparing or type-checking a secret value throws an error.
local function ExtractFrameStackTooltipText()
    local fs = _G.FrameStackTooltip
    if not fs then return nil end

    local lines = {}

    -- Helper: safely extract text from a FontString, returns nil if secret/unavailable
    local function safeGetText(fontString)
        if not fontString then return nil end
        local result = nil
        pcall(function()
            if not fontString.GetText then return end
            local raw = fontString:GetText()
            -- ALL checks must be inside pcall because type()/comparisons fail on secrets
            if raw == nil then return end
            if type(raw) ~= "string" then return end
            if raw == "" then return end
            -- Final verification: try string operation
            local _ = raw .. ""
            result = raw
        end)
        return result
    end

    -- Try numbered text lines like GameTooltip pattern (most reliable)
    -- FrameStackTooltip has TextLeft1, TextLeft2, etc.
    for i = 1, 30 do
        local leftLine = fs["TextLeft" .. i] or _G["FrameStackTooltipTextLeft" .. i]
        local text = safeGetText(leftLine)
        if text then
            table.insert(lines, text)
        end
    end

    -- Also try LinesContainer if present and we got nothing
    local linesContainer = fs.LinesContainer
    if linesContainer and #lines == 0 then
        pcall(function()
            local children = { linesContainer:GetChildren() }
            for _, child in ipairs(children) do
                if child and child.GetRegions then
                    local regions = { child:GetRegions() }
                    for _, region in ipairs(regions) do
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            local text = safeGetText(region)
                            if text then
                                table.insert(lines, text)
                            end
                        end
                    end
                end
            end
        end)
    end

    if #lines > 0 then
        local ok, result = pcall(table.concat, lines, "\n")
        return ok and result or nil
    end
    return nil
end

local function AttachTableInspectorCopyButton()
    local parent = _G.TableAttributeDisplay
    if not parent or parent.ScooterCopyButton then return end
    local btn = CreateFrame("Button", "ScooterAttrCopyButton", parent, "UIPanelButtonTemplate")
    btn:SetSize(80, 20)
    btn:SetText("Copy")
    -- Place just beneath the window, slightly offset
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -6)
    btn:SetScript("OnClick", function()
        local focused = parent.focusedTable
        -- If framestack is active, prioritize extracting its visible text
        local fs = _G.FrameStackTooltip
        local frameStackText = (fs and fs:IsShown()) and ExtractFrameStackTooltipText() or nil

        local dump
        if frameStackText then
            -- Combine framestack text with table dump
            local tableDump = TableInspectorBuildDump(focused)
            dump = "=== FrameStack Visible Text ===\n" .. frameStackText .. "\n\n" .. tableDump
        else
            dump = TableInspectorBuildDump(focused)
        end
        ShowTableInspectorCopyWindow("Table Attributes", dump)
    end)
    parent.ScooterCopyButton = btn
end

-- Called from init.lua ADDON_LOADED handler
function addon.AttachTableInspectorCopyButton()
    AttachTableInspectorCopyButton()
end

-- NOTE: FrameStackTooltip copy button removed - can't hover and click simultaneously.
-- Use TableAttributeDisplay copy button instead: /fstack -> Alt to select -> Ctrl to inspect -> Copy

-- Expose the attribute dump logic for the slash command (/scoot attr)
function addon.DumpTableAttributes()
    local parent = _G.TableAttributeDisplay
    if parent and parent:IsShown() and parent.focusedTable then
        local dump = TableInspectorBuildDump(parent.focusedTable)
        -- 12.0: Title is now hardcoded in dump; use simple title for window
        ShowTableInspectorCopyWindow("Table Attributes", dump)
        return true
    end
    -- Fallback: if framestack is active, try to inspect highlight and dump
    local fs = _G.FrameStackTooltip
    if fs and fs.highlightFrame then
        local dump = TableInspectorBuildDump(fs.highlightFrame)
        local name = GetDebugNameSafe(fs.highlightFrame) or "Frame"
        -- Wrap title construction in pcall for safety
        local ok, title = pcall(function() return "Frame Attributes - " .. name end)
        ShowTableInspectorCopyWindow(ok and title or "Frame Attributes", dump)
        return true
    end
    return false
end

