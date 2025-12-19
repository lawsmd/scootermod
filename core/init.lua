local addonName, addon = ...

addon.FeatureToggles = addon.FeatureToggles or {}
addon.FeatureToggles.enablePRD = addon.FeatureToggles.enablePRD or false

local function purgeDisabledPRDComponents(db)
    if addon.FeatureToggles and addon.FeatureToggles.enablePRD then
        return
    end
    local profile = db and db.profile
    local components = profile and profile.components
    if not components then
        return
    end
    local removed = {}
    for _, key in ipairs({"prdGlobal", "prdHealth", "prdPower", "prdClassResource"}) do
        if components[key] ~= nil then
            components[key] = nil
            table.insert(removed, key)
        end
    end
    if #removed > 0 then
        local message = string.format("PRD disabled – purged SavedVariables for: %s", table.concat(removed, ", "))
        if addon.DebugPrint then
            addon.DebugPrint("[ScooterMod]", message)
        elseif addon.Print then
            addon:Print(message)
        end
    end
end

function addon:OnInitialize()
    C_AddOns.LoadAddOn("Blizzard_Settings")
    -- Warm up bundled fonts early to avoid first-open rendering differences
    if addon.PreloadFonts then addon.PreloadFonts() end
    -- 1. Define components and populate self.Components
    self:InitializeComponents()
    
    -- Explicitly require the new ScrollingCombatText component file (if loaded via TOC, this is handled)
    -- but we ensure its initializer runs if it used the RegisterComponent pattern


    -- 2. Create the database, using the component list to build defaults
    self.db = LibStub("AceDB-3.0"):New("ScooterModDB", self:GetDefaults(), true)
    purgeDisabledPRDComponents(self.db)

    if self.Profiles and self.Profiles.Initialize then
        self.Profiles:Initialize()
    end
    if self.Rules and self.Rules.Initialize then
        self.Rules:Initialize()
    end

    -- 3. Now that DB exists, link components to their DB tables
    self:LinkComponentsToDB()

    -- 4. Allow components that only need global resources to apply immediately (before world load)
    if self.ApplyEarlyComponentStyles then
        self:ApplyEarlyComponentStyles()
    end

    -- 5. Register for events
    self:RegisterEvents()
end

function addon:GetDefaults()
    local defaults = {
        profile = {
            applyAll = {
                fontPending = "FRIZQT__",
                barTexturePending = "default",
                lastFontApplied = nil,
                lastTextureApplied = nil,
            },
            minimap = {
                hide = false,
                minimapPos = 220,
            },
            components = {},
            rules = {},
            rulesState = {
                baselines = {},
                nextId = 1,
            },
            groupFrames = {
                raid = {
                    healthBarTexture = "default",
                    healthBarColorMode = "default",
                    healthBarTint = {1, 1, 1, 1},
                    healthBarBackgroundTexture = "default",
                    healthBarBackgroundColorMode = "default",
                    healthBarBackgroundTint = {0, 0, 0, 1},
                    healthBarBackgroundOpacity = 50,
                },
            },
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
        local settings = component.settings or {}
        for settingId, setting in pairs(settings) do
            -- Some entries in component.settings are boolean flags or helper values rather than
            -- full setting descriptors. Only copy those that are tables with an explicit default.
            if type(setting) == "table" and setting.default ~= nil then
                defaults.profile.components[id][settingId] = setting.default
            end
        end
    end

    return defaults
end

function addon:RegisterEvents()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    -- Ensure Unit Frame styling is re-applied when target/focus units change
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED")
    -- Pet lifecycle / pet overlays
    self:RegisterEvent("UNIT_PET")
    self:RegisterEvent("PET_UI_UPDATE")
    self:RegisterEvent("PET_ATTACK_START")
    self:RegisterEvent("PET_ATTACK_STOP")
    -- Pet threat changes drive PetFrameFlash via UnitFrame_UpdateThreatIndicator
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    -- Re-evaluate Rules when player levels up (for playerLevel trigger type)
    self:RegisterEvent("PLAYER_LEVEL_UP")
    -- Combat state changes for opacity updates (priority: With Target > In Combat > Out of Combat)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Apply dropdown stepper fixes
    self:ApplyDropdownStepperFixes()
end

-- Refresh opacity state for all elements affected by combat/target priority
-- This is safe to call during combat as SetAlpha is not a protected function
function addon:RefreshOpacityState()
    -- Update Unit Frame visibility/opacity
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
    end
    -- Update all components that have opacity settings (CDM, Action Bars, Auras, etc.)
    for id, component in pairs(self.Components) do
        if component.ApplyStyling and component.settings then
            -- Check for opacity settings with various naming conventions:
            -- - CDM uses: opacity, opacityOutOfCombat, opacityWithTarget
            -- - Action Bars use: barOpacity, barOpacityOutOfCombat, barOpacityWithTarget
            -- - Auras use: opacity, opacityOutOfCombat, opacityWithTarget
            local hasOpacity = component.settings.opacity or
                component.settings.opacityInCombat or
                component.settings.opacityOutOfCombat or
                component.settings.opacityWithTarget or
                component.settings.barOpacity or
                component.settings.barOpacityOutOfCombat or
                component.settings.barOpacityWithTarget
            if hasOpacity then
                pcall(component.ApplyStyling, component)
            end
        end
    end
end

function addon:PLAYER_REGEN_DISABLED()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            self:RefreshOpacityState()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    else
        self:RefreshOpacityState()
        if addon.UnitFrames_EnforcePetOverlays then
            addon.UnitFrames_EnforcePetOverlays()
        end
    end
end

function addon:UNIT_PET(event, unit)
    if unit ~= "player" then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    elseif addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
end

function addon:PET_UI_UPDATE()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    elseif addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
end

function addon:PET_ATTACK_START()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    elseif addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
end

function addon:PET_ATTACK_STOP()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    elseif addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
end

function addon:UNIT_THREAT_SITUATION_UPDATE(event, unit)
    if unit ~= "pet" then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    elseif addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
end

function addon:PLAYER_REGEN_ENABLED()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            -- Handle deferred styling if ApplyStyles was called during combat
            if self._pendingApplyStyles then
                self._pendingApplyStyles = nil
                self:ApplyStyles()
            else
                -- Just refresh opacity state
                self:RefreshOpacityState()
            end
        end)
    else
        if self._pendingApplyStyles then
            self._pendingApplyStyles = nil
            self:ApplyStyles()
        else
            self:RefreshOpacityState()
        end
    end
end

function addon:ApplyDropdownStepperFixes()
    -- IMPORTANT: Use hooksecurefunc instead of direct method replacement to avoid taint.
    -- Direct replacement of Blizzard mixin methods spreads taint to any code path that
    -- calls those methods, causing "blocked from an action" errors for protected functions
    -- like FocusUnit(), ClearFocus(), etc.
    --
    -- CRITICAL: All hook actions are deferred via C_Timer.After(0, ...) to break the
    -- execution context chain. Without this deferral, taint can propagate to unrelated
    -- Blizzard UI systems (e.g., Spell Book) causing "blocked from an action" errors
    -- on protected functions like Frame:SetWidth(). See DEBUG.md for details.

    -- Ensure dropdown steppers (left/right arrows) refresh enable/disable state after selection changes
    do
        local mixin = _G.SettingsDropdownControlMixin
        if mixin and type(mixin.OnSettingValueChanged) == "function" and not addon._dropdownReinitPatched then
            hooksecurefunc(mixin, "OnSettingValueChanged", function(self, setting, value)
                -- Capture references for deferred execution
                local dropdown = self
                local control = self and self.Control
                -- Defer all actions to break taint propagation chain
                C_Timer.After(0, function()
                    -- Reinitialize dropdown so steppers recalc based on current selection and options order
                    if dropdown and type(dropdown.InitDropdown) == "function" then
                        pcall(dropdown.InitDropdown, dropdown)
                    end
                    -- Refresh stepper enabled state
                    if control and type(control.UpdateSteppers) == "function" then
                        pcall(control.UpdateSteppers, control)
                        -- Second refresh next frame to catch async updates
                        C_Timer.After(0, function()
                            if control and type(control.UpdateSteppers) == "function" then
                                pcall(control.UpdateSteppers, control)
                            end
                        end)
                    end
                end)
            end)
            addon._dropdownReinitPatched = true
        end
    end

    -- Also force stepper refresh immediately after arrow clicks by extending DropdownWithSteppersMixin
    do
        local mixin = _G.DropdownWithSteppersMixin
        if mixin and not addon._dropdownStepperPatched then
            if type(mixin.Increment) == "function" then
                hooksecurefunc(mixin, "Increment", function(self, ...)
                    -- Capture references for deferred execution
                    local stepper = self
                    local dropdown = self and self.Dropdown
                    -- Defer to break taint propagation chain
                    C_Timer.After(0, function()
                        if dropdown and type(dropdown.Update) == "function" then
                            pcall(dropdown.Update, dropdown)
                        end
                        if stepper and type(stepper.UpdateSteppers) == "function" then
                            pcall(stepper.UpdateSteppers, stepper)
                        end
                    end)
                end)
            end
            if type(mixin.Decrement) == "function" then
                hooksecurefunc(mixin, "Decrement", function(self, ...)
                    -- Capture references for deferred execution
                    local stepper = self
                    local dropdown = self and self.Dropdown
                    -- Defer to break taint propagation chain
                    C_Timer.After(0, function()
                        if dropdown and type(dropdown.Update) == "function" then
                            pcall(dropdown.Update, dropdown)
                        end
                        if stepper and type(stepper.UpdateSteppers) == "function" then
                            pcall(stepper.UpdateSteppers, stepper)
                        end
                    end)
                end)
            end
            addon._dropdownStepperPatched = true
        end
    end

    -- Ensure dropdown emits an OnUpdate after selection via arrows so steppers reflect edges immediately
    do
        local mixin = _G.DropdownButtonMixin
        if mixin and type(mixin.Pick) == "function" and not addon._dropdownSignalUpdatePatched then
            hooksecurefunc(mixin, "Pick", function(self, description, ...)
                -- Capture reference for deferred execution
                local button = self
                -- Defer to break taint propagation chain
                C_Timer.After(0, function()
                    -- After a selection is picked, explicitly signal an update so steppers recompute
                    if button and type(button.SignalUpdate) == "function" then
                        pcall(button.SignalUpdate, button)
                    end
                end)
            end)
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
    
    -- NOTE: We previously had a method override on EditModeManagerFrame.NotifyChatOfLayoutChange
    -- to suppress incorrect layout announcements during spec switches. This was removed because
    -- method overrides cause PERSISTENT TAINT that propagates to unrelated Blizzard code.
    -- In 11.2.7, this taint was blocking ActionButton:SetAttribute() calls in the new
    -- "press and hold" system. The cosmetic benefit of suppressing announcements is not worth
    -- breaking core action bar functionality. See DEBUG.md "Golden Rules for Taint Prevention".
    
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
    if self.Rules and self.Rules.OnPlayerLogin then
        self.Rules:OnPlayerLogin()
    end
    self:ApplyStyles()
    -- Deferred reapply of Player textures to catch any Blizzard resets after initial apply
    -- This ensures textures persist even if Blizzard updates the frame after our initial styling
    if C_Timer and C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameBarTexturesFor("Player")
        end)
    end
    -- Deferred reapply of Player name/level text visibility to catch Blizzard resets
    -- (e.g., PlayerFrame_Update, PlayerFrame_UpdateRolesAssigned) that run after initial styling
    if C_Timer and C_Timer.After and addon.ApplyUnitFrameNameLevelTextFor then
        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameNameLevelTextFor("Player")
        end)
    end
    -- Deferred reapply of Player health/power bar text visibility to catch Blizzard resets
    -- (TextStatusBarMixin:UpdateTextStringWithValues shows LeftText/RightText after initial styling)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Player")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Player")
            end
        end)
        -- Additional longer-delay reapply specifically for instance loading transitions.
        -- When entering instances, Blizzard's unit frame updates can run significantly later
        -- than the 0.1s delay, resetting fonts via SetFontObject. This secondary pass ensures
        -- custom text styling (font face/size/color) persists through instance loading.
        C_Timer.After(0.5, function()
            if addon.ApplyAllUnitFrameHealthTextVisibility then
                addon.ApplyAllUnitFrameHealthTextVisibility()
            end
            if addon.ApplyAllUnitFramePowerTextVisibility then
                addon.ApplyAllUnitFramePowerTextVisibility()
            end
            -- Also reapply bar textures for Player to catch Alternate Power Bar text styling
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor("Player")
            end
        end)
    end
end

function addon:PLAYER_TARGET_CHANGED()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor("Player")
                addon.ApplyUnitFrameBarTexturesFor("Target")
            end
            if addon.ApplyUnitFrameNameLevelTextFor then
                addon.ApplyUnitFrameNameLevelTextFor("Target")
            end
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Target")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Target")
            end
            self:RefreshOpacityState()
            
            C_Timer.After(0.1, function()
                if addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Player")
                end
            end)
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then
            addon.ApplyUnitFrameBarTexturesFor("Player")
            addon.ApplyUnitFrameBarTexturesFor("Target")
        end
        if addon.ApplyUnitFrameNameLevelTextFor then
            addon.ApplyUnitFrameNameLevelTextFor("Target")
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then
            addon.ApplyUnitFrameHealthTextVisibilityFor("Target")
        end
        if addon.ApplyUnitFramePowerTextVisibilityFor then
            addon.ApplyUnitFramePowerTextVisibilityFor("Target")
        end
        self:RefreshOpacityState()
    end
end

function addon:PLAYER_FOCUS_CHANGED()
    -- Re-apply Focus styling after Blizzard rebuilds layout
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor("Focus")
            end
            -- Also apply Name & Level Text visibility to ensure hidden settings persist
            if addon.ApplyUnitFrameNameLevelTextFor then
                addon.ApplyUnitFrameNameLevelTextFor("Focus")
            end
            -- Also apply Health/Power bar text visibility to ensure hidden settings persist
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Focus")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Focus")
            end
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then
            addon.ApplyUnitFrameBarTexturesFor("Focus")
        end
        if addon.ApplyUnitFrameNameLevelTextFor then
            addon.ApplyUnitFrameNameLevelTextFor("Focus")
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then
            addon.ApplyUnitFrameHealthTextVisibilityFor("Focus")
        end
        if addon.ApplyUnitFramePowerTextVisibilityFor then
            addon.ApplyUnitFramePowerTextVisibilityFor("Focus")
        end
    end
end

function addon:PLAYER_LEVEL_UP()
    -- Re-evaluate Rules when player levels up (for playerLevel trigger type)
    if self.Rules and self.Rules.OnPlayerLevelUp then
        self.Rules:OnPlayerLevelUp()
    end
end

function addon:EDIT_MODE_LAYOUTS_UPDATED()
    -- Use centralized sync function
    addon.EditMode.RefreshSyncAndNotify("EDIT_MODE_LAYOUTS_UPDATED")
    if self.Profiles and self.Profiles.RequestSync then
        self.Profiles:RequestSync("EDIT_MODE_LAYOUTS_UPDATED")
    end
    -- Invalidate scale multiplier baselines so they get recaptured with new Edit Mode scale
    if addon.OnUnitFrameScaleMultLayoutsUpdated then
        addon.OnUnitFrameScaleMultLayoutsUpdated()
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
    if self.Rules and self.Rules.OnPlayerSpecChanged then
        self.Rules:OnPlayerSpecChanged()
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

-- Expose the attribute dump logic for the slash command
function addon:DumpTableAttributes()
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
	addon:Print("No Table Inspector window or highlight frame found to dump.")
end
