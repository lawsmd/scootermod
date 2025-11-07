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

local function ResolveFrameByKey(key)
    key = tostring(key or ""):lower()
    local map = {
        ab1 = "MainMenuBar",
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


-- Z-order dump for Unit Frames
local function UFResolveRoots(unit)
    if unit == "player" then return _G.PlayerFrame, "Player" end
    if unit == "target" then return _G.TargetFrame, "Target" end
    if unit == "focus" then return _G.FocusFrame, "Focus" end
    if unit == "pet" then return _G.PetFrame, "Pet" end
    return nil, unit
end

local function UFResolveBarsAndText(root, unitKey)
    local result = {
        hb = nil, hbContainer = nil, hbHolder = nil,
        mb = nil, mbContainer = nil,
        texts = {},
    }
    if not root then return result end
    if unitKey == "Pet" then
        result.hb = _G.PetFrameHealthBar
        result.mb = _G.PetFrameManaBar
        result.hbContainer = _G.PetFrame and _G.PetFrame.HealthBarContainer or nil
        result.mbContainer = _G.PetFrame and _G.PetFrame.ManaBar or nil
        if _G.PetFrameHealthBarText then table.insert(result.texts, _G.PetFrameHealthBarText) end
        if _G.PetFrameHealthBarTextLeft then table.insert(result.texts, _G.PetFrameHealthBarTextLeft) end
        if _G.PetFrameHealthBarTextRight then table.insert(result.texts, _G.PetFrameHealthBarTextRight) end
        if _G.PetFrameManaBarText then table.insert(result.texts, _G.PetFrameManaBarText) end
        if _G.PetFrameManaBarTextLeft then table.insert(result.texts, _G.PetFrameManaBarTextLeft) end
        if _G.PetFrameManaBarTextRight then table.insert(result.texts, _G.PetFrameManaBarTextRight) end
    else
        local main = (root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain)
            or (root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain) or nil
        if main then
            result.hbContainer = main.HealthBarsContainer
            result.hb = result.hbContainer and result.hbContainer.HealthBar or nil
            if unitKey == "Player" then
                result.mbContainer = main.ManaBarArea and main.ManaBarArea.ManaBar or nil
            else
                result.mbContainer = main.ManaBar or nil
            end
            result.mb = result.mbContainer
            if result.hbContainer then
                if result.hbContainer.HealthBarText then table.insert(result.texts, result.hbContainer.HealthBarText) end
                if result.hbContainer.LeftText then table.insert(result.texts, result.hbContainer.LeftText) end
                if result.hbContainer.RightText then table.insert(result.texts, result.hbContainer.RightText) end
            end
            if result.mbContainer then
                if result.mbContainer.ManaBarText then table.insert(result.texts, result.mbContainer.ManaBarText) end
                if result.mbContainer.LeftText then table.insert(result.texts, result.mbContainer.LeftText) end
                if result.mbContainer.RightText then table.insert(result.texts, result.mbContainer.RightText) end
            end
        end
    end
    result.hbHolder = result.hb and result.hb.ScooterStyledBorder or nil
    return result
end

local function formatFrameInfo(f)
    if not f then return "<nil>" end
    local strata = f.GetFrameStrata and f:GetFrameStrata() or "?"
    local lvl = f.GetFrameLevel and f:GetFrameLevel() or 0
    return string.format("strata=%s level=%s name=%s", tostring(strata), tostring(lvl), tostring(f.GetName and f:GetName() or ""))
end

local function formatTextInfo(fs)
    if not fs then return "<nil>" end
    local layer, sub = "?", "?"
    if fs.GetDrawLayer then layer, sub = fs:GetDrawLayer() end
    local parent = fs.GetParent and fs:GetParent() or nil
    local pLevel = parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0
    return string.format("text=%s layer=%s sub=%s parentLevel=%s", tostring(fs.GetName and fs:GetName() or "FontString"), tostring(layer), tostring(sub), tostring(pLevel))
end

function addon.DebugDumpZOrderUF(unit)
    local root, unitKey = UFResolveRoots(unit)
    local lines = {}
    local function push(s) table.insert(lines, s) end
    if not root then
        push("Unit frame not found: "..tostring(unit))
        ShowDebugCopyWindow("UF Z-Order - "..tostring(unit), table.concat(lines, "\n"))
        return
    end
    push("Unit: "..unitKey)
    push("Root: "..formatFrameInfo(root))
    local info = UFResolveBarsAndText(root, unitKey)
    push("HealthBar: "..formatFrameInfo(info.hb))
    push("HealthContainer: "..formatFrameInfo(info.hbContainer))
    push("BorderHolder: "..formatFrameInfo(info.hbHolder))
    push("ManaBar: "..formatFrameInfo(info.mb))
    push("ManaContainer: "..formatFrameInfo(info.mbContainer))
    push("-- Text regions --")
    for _, fs in ipairs(info.texts) do
        push(formatTextInfo(fs))
    end
    ShowDebugCopyWindow("UF Z-Order - "..unitKey, table.concat(lines, "\n"))
end

