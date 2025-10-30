local addonName, addon = ...

function addon:OnInitialize()
    C_AddOns.LoadAddOn("Blizzard_Settings")
    -- Warm up bundled fonts early to avoid first-open rendering differences
    if addon.PreloadFonts then addon.PreloadFonts() end
    -- 1. Define components and populate self.Components
    self:InitializeComponents()

    -- 2. Create the database, using the component list to build defaults
    self.db = LibStub("AceDB-3.0"):New("ScooterModDB", self:GetDefaults(), true)

    if self.Profiles and self.Profiles.Initialize then
        self.Profiles:Initialize()
    end

    -- 3. Now that DB exists, link components to their DB tables
    self:LinkComponentsToDB()

    -- 4. Register for events
    self:RegisterEvents()
end

function addon:GetDefaults()
    local defaults = {
        profile = {
            components = {}
        },
        char = {
            specProfiles = {
                enabled = false,
                assignments = {}
            }
        }
    }

    for id, component in pairs(self.Components) do
        defaults.profile.components[id] = {}
        for settingId, setting in pairs(component.settings) do
            defaults.profile.components[id][settingId] = setting.default
        end
    end

    return defaults
end

function addon:RegisterEvents()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    
    -- Apply dropdown stepper fixes
    self:ApplyDropdownStepperFixes()
end

function addon:ApplyDropdownStepperFixes()
    -- Ensure dropdown steppers (left/right arrows) refresh enable/disable state after selection changes
    do
        local mixin = _G.SettingsDropdownControlMixin
        if mixin and type(mixin.OnSettingValueChanged) == "function" and not addon._dropdownReinitPatched then
            local original = mixin.OnSettingValueChanged
            mixin.OnSettingValueChanged = function(self, setting, value)
                if original then pcall(original, self, setting, value) end
                -- Reinitialize dropdown so steppers recalc based on current selection and options order
                if self and type(self.InitDropdown) == "function" then
                    pcall(self.InitDropdown, self)
                end
                -- Immediately refresh stepper enabled state and again next frame to catch async updates
                if self and self.Control and type(self.Control.UpdateSteppers) == "function" then
                    pcall(self.Control.UpdateSteppers, self.Control)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            pcall(self.Control.UpdateSteppers, self.Control)
                        end)
                    end
                end
            end
            addon._dropdownReinitPatched = true
        end
    end

    -- Also force stepper refresh immediately after arrow clicks by extending DropdownWithSteppersMixin
    do
        local mixin = _G.DropdownWithSteppersMixin
        if mixin and not addon._dropdownStepperPatched then
            local origInc = mixin.Increment
            local origDec = mixin.Decrement
            mixin.Increment = function(self, ...)
                if origInc then pcall(origInc, self, ...) end
                if self and self.Dropdown and type(self.Dropdown.Update) == "function" then
                    pcall(self.Dropdown.Update, self.Dropdown)
                end
                if type(self.UpdateSteppers) == "function" then
                    pcall(self.UpdateSteppers, self)
                end
            end
            mixin.Decrement = function(self, ...)
                if origDec then pcall(origDec, self, ...) end
                if self and self.Dropdown and type(self.Dropdown.Update) == "function" then
                    pcall(self.Dropdown.Update, self.Dropdown)
                end
                if type(self.UpdateSteppers) == "function" then
                    pcall(self.UpdateSteppers, self)
                end
            end
            addon._dropdownStepperPatched = true
        end
    end

    -- Ensure dropdown emits an OnUpdate after selection via arrows so steppers reflect edges immediately
    do
        local mixin = _G.DropdownButtonMixin
        if mixin and type(mixin.Pick) == "function" and not addon._dropdownSignalUpdatePatched then
            local originalPick = mixin.Pick
            mixin.Pick = function(self, description, ...)
                local responded = false
                if originalPick then
                    responded = originalPick(self, description, ...)
                end
                -- After a selection is picked, explicitly signal an update so steppers recompute
                if self and type(self.SignalUpdate) == "function" then
                    pcall(self.SignalUpdate, self)
                end
                return responded
            end
            addon._dropdownSignalUpdatePatched = true
        end
    end
end

function addon:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
    -- Initialize Edit Mode integration
    addon.EditMode.Initialize()
    -- Ensure fonts are preloaded even if initialization order changes
    if addon.PreloadFonts then addon.PreloadFonts() end
    -- Force index-mode for Opacity on Cooldown Viewer systems (compat path); safe no-op if already set
    do
        local LEO_local = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_local and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeCooldownViewerSetting then
            local sys = _G.Enum.EditModeSystem.CooldownViewer
            local setting = _G.Enum.EditModeCooldownViewerSetting.Opacity
            LEO_local._forceIndexBased = LEO_local._forceIndexBased or {}
            LEO_local._forceIndexBased[sys] = LEO_local._forceIndexBased[sys] or {}
            -- Enable compat mode so both write/read paths use raw<->index consistently under the hood
            LEO_local._forceIndexBased[sys][setting] = true
        end
    end
    
    -- Install a lightweight suppression wrapper so Blizzard doesn't announce the wrong layout name
    -- on spec-driven switches where we immediately apply our assigned profile.
    if _G.EditModeManagerFrame and not addon._chatHooked then
        local originalNotify = _G.EditModeManagerFrame.NotifyChatOfLayoutChange
        if type(originalNotify) == "function" then
            _G.EditModeManagerFrame.NotifyChatOfLayoutChange = function(self, ...)
				local desired = addon and addon.Profiles and addon.Profiles._pendingSpecTarget
				local info = self.GetActiveLayoutInfo and self:GetActiveLayoutInfo()
				local activeName = info and info.layoutName
				if desired then
					if activeName ~= desired then
						-- Skip this one incorrect announcement; our subsequent apply will print correctly.
						addon.Profiles._pendingSpecTarget = nil
						return
					end
					-- Clear flag when allowing correct announcement as well
					addon.Profiles._pendingSpecTarget = nil
				end
				return originalNotify(self, ...)
            end
            addon._chatHooked = true
        end
    end
    
    -- Use centralized sync function
    addon.EditMode.RefreshSyncAndNotify("PLAYER_ENTERING_WORLD")
    if self.Profiles then
        if self.Profiles.TryPendingSync then
            self.Profiles:TryPendingSync()
        end
        if self.Profiles.OnPlayerSpecChanged then
            self.Profiles:OnPlayerSpecChanged()
        end
    end
    self:ApplyStyles()
end

function addon:EDIT_MODE_LAYOUTS_UPDATED()
    -- Use centralized sync function
    addon.EditMode.RefreshSyncAndNotify("EDIT_MODE_LAYOUTS_UPDATED")
    if self.Profiles and self.Profiles.RequestSync then
        self.Profiles:RequestSync("EDIT_MODE_LAYOUTS_UPDATED")
    end
    self:ApplyStyles()
end

function addon:PLAYER_SPECIALIZATION_CHANGED(event, unit)
    if unit and unit ~= "player" then
        return
    end
    if self.Profiles and self.Profiles.OnPlayerSpecChanged then
        self.Profiles:OnPlayerSpecChanged()
    end
end

-- Debug Tools: Table Inspector copy support ----------------------------------

local function Scooter_SafeCall(fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
	return nil
end

local function Scooter_GetDebugNameSafe(obj)
	if not obj then return nil end
	return Scooter_SafeCall(function() return obj.GetDebugName and obj:GetDebugName() or nil end)
end

local function Scooter_TableInspectorBuildDump(focusedTable)
	if not focusedTable then return "[No Table Selected]" end
	local attributes = {}
	local childFrameDisplayed = {}

	local function shouldShow(object)
		-- Attempt to honor widget access checks if available; otherwise allow
		local isWidget = Scooter_SafeCall(function() return C_Widget and C_Widget.IsWidget and C_Widget.IsWidget(object) end)
		local canAccess = Scooter_SafeCall(function() return CanAccessObject and CanAccessObject(object) or true end)
		if isWidget == nil then isWidget = false end
		if canAccess == nil then canAccess = true end
		return (not isWidget) or canAccess
	end

	for key, value in pairs(focusedTable) do
		if shouldShow(key) and shouldShow(value) then
			local vType = type(value)
			local display
			if vType == "number" or vType == "string" or vType == "boolean" then
				display = tostring(value)
			elseif vType == "table" and Scooter_GetDebugNameSafe(value) then
				display = Scooter_GetDebugNameSafe(value)
				vType = "childFrame"
				childFrameDisplayed[value] = true
			elseif vType == "nil" then
				display = "nil"
			else
				display = "N/A"
			end
			table.insert(attributes, { key = key, type = vType, rawValue = value, displayValue = display })
		end
	end

	if focusedTable.GetChildren then
		local children = { focusedTable:GetChildren() }
		for _, child in ipairs(children) do
			if shouldShow(child) and not childFrameDisplayed[child] then
				table.insert(attributes, { key = "N/A", type = "childFrame", rawValue = child, displayValue = Scooter_GetDebugNameSafe(child) or "<child>" })
				childFrameDisplayed[child] = true
			end
		end
	end

	if focusedTable.GetRegions then
		local regions = { focusedTable:GetRegions() }
		for _, region in ipairs(regions) do
			if shouldShow(region) then
				table.insert(attributes, { key = "N/A", type = "region", rawValue = region, displayValue = Scooter_GetDebugNameSafe(region) or "<region>" })
			end
		end
	end

	local typeOrder = { childFrame = 10, boolean = 20, number = 30, string = 40, table = 50, region = 60, ["function"] = 70 }
	table.sort(attributes, function(a, b)
		local ao = typeOrder[a.type] or 500
		local bo = typeOrder[b.type] or 500
		if ao ~= bo then return ao < bo end
		if a.key ~= b.key then return tostring(a.key) < tostring(b.key) end
		return tostring(a.displayValue) < tostring(b.displayValue)
	end)

	local out = {}
	local function push(line) table.insert(out, line) end
	local title = Scooter_SafeCall(function() return TableAttributeDisplay and TableAttributeDisplay.TitleButton and TableAttributeDisplay.TitleButton.Text and TableAttributeDisplay.TitleButton.Text:GetText() end)
	push(string.format("%s", title or "Table Attributes"))
	push(string.rep("-", 60))
	local lastType
	for _, entry in ipairs(attributes) do
		if entry.type ~= lastType then
			push(string.format("%s(s)", entry.type))
			lastType = entry.type
		end
		push(string.format("  %s = %s", tostring(entry.key), tostring(entry.displayValue)))
	end
	return table.concat(out, "\n")
end

local function Scooter_ShowCopyWindow(title, text)
	if not addon.CopyWindow then
		local f = CreateFrame("Frame", "ScooterCopyWindow", UIParent, "BasicFrameTemplateWithInset")
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
		addon.CopyWindow = f
	end
	local f = addon.CopyWindow
	if f.title then f.title:SetText(title or "Copied Output") end
	if f.EditBox then f.EditBox:SetText(text or "") end
	f:Show()
	if f.EditBox then f.EditBox:HighlightText(); f.EditBox:SetFocus() end
end

local function Scooter_AttachAttrCopyButton()
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
		local dump = Scooter_TableInspectorBuildDump(focused)
		local title = (parent.TitleButton and parent.TitleButton.Text and parent.TitleButton.Text:GetText()) or "Table Attributes"
		Scooter_ShowCopyWindow(title, dump)
	end)
	parent.ScooterCopyButton = btn
end

function addon:ADDON_LOADED(event, name)
	if name == "Blizzard_DebugTools" then
		C_Timer.After(0, function() Scooter_AttachAttrCopyButton() end)
	end
end

-- Slash command to dump current inspector selection
SLASH_ATTRCOPY1 = "/attrcopy"
SlashCmdList.ATTRCOPY = function(msg)
	local parent = _G.TableAttributeDisplay
	if parent and parent:IsShown() and parent.focusedTable then
		local dump = Scooter_TableInspectorBuildDump(parent.focusedTable)
		local title = (parent.TitleButton and parent.TitleButton.Text and parent.TitleButton.Text:GetText()) or "Table Attributes"
		Scooter_ShowCopyWindow(title, dump)
		return
	end
	-- Fallback: if framestack is active, try to inspect highlight and dump
	local fs = _G.FrameStackTooltip
	if fs and fs.highlightFrame then
		local dump = Scooter_TableInspectorBuildDump(fs.highlightFrame)
		local name = Scooter_GetDebugNameSafe(fs.highlightFrame) or "Frame"
		Scooter_ShowCopyWindow("Frame Attributes - "..name, dump)
		return
	end
	print("/attrcopy: No Table Inspector window or highlight frame found.")
end
