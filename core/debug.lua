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
    Profile export (AceDB -> copyable Lua table)

    Purpose:
      - Produce a deterministic, copy/paste friendly Lua table literal for a given
        AceDB profile (usually the current profile).
      - Intended for preset ingestion into core/presets.lua (ScooterUI/ScooterDeck).
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

