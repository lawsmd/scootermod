local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Objective Tracker renderer
-- Sections:
--  - Sizing: Height (Edit Mode), Text Size (Edit Mode)
--  - Text: Tabbed (Header, Quest Name, Quest Objective) with Font, Font Style, Font Color (Default/Custom)
--  - Visibility: Opacity (Edit Mode), Opacity In-Combat (Addon)

local function _lower(s)
	if type(s) ~= "string" then return "" end
	return string.lower(s)
end

local function _SafeEntriesForSystem(systemId)
	local mgr = _G.EditModeSettingDisplayInfoManager
	local map = mgr and mgr.systemSettingDisplayInfo
	return (map and map[systemId]) or nil
end

local function ResolveObjectiveTrackerSettingId(kind)
	-- System id 12 is confirmed for Objective Tracker via framestack and preset exports.
	local sys = 12
	local entries = _SafeEntriesForSystem(sys)
	if type(entries) == "table" then
		for _, setup in ipairs(entries) do
			if setup and setup.setting ~= nil and setup.type == _G.Enum.EditModeSettingDisplayType.Slider then
				local nm = _lower(setup.name or "")
				if kind == "height" and nm:find("height", 1, true) then
					return setup.setting
				end
				if kind == "opacity" and nm:find("opacity", 1, true) then
					return setup.setting
				end
				if kind == "textSize" and ((nm:find("text", 1, true) and nm:find("size", 1, true)) or nm:find("font", 1, true)) then
					return setup.setting
				end
			end
		end
	end
	-- Fallbacks (expected stable): 0=height, 1=opacity, 2=text size.
	if kind == "height" then return 0 end
	if kind == "opacity" then return 1 end
	if kind == "textSize" then return 2 end
	return nil
end

local function GetSliderMeta(settingId)
	local sys = 12
	local entries = _SafeEntriesForSystem(sys)
	if type(entries) ~= "table" then return nil end
	for _, setup in ipairs(entries) do
		if setup and setup.setting == settingId and setup.type == _G.Enum.EditModeSettingDisplayType.Slider then
			return tonumber(setup.minValue), tonumber(setup.maxValue), tonumber(setup.stepSize), setup.name
		end
	end
	return nil
end

function panel.RenderObjectiveTracker()
	local render = function()
		local component = addon.Components and addon.Components.objectiveTracker
		if not component then return end

		local f = panel.frame
		local right = f and f.RightPane
		if not f or not right or not right.Display then return end

		-- Ensure the component's Edit Mode setting IDs are correct for this client build.
		do
			local sidHeight = ResolveObjectiveTrackerSettingId("height")
			local sidOpacity = ResolveObjectiveTrackerSettingId("opacity")
			local sidTextSize = ResolveObjectiveTrackerSettingId("textSize")
			if component.settings and component.settings.height then component.settings.height.settingId = sidHeight end
			if component.settings and component.settings.opacity then component.settings.opacity.settingId = sidOpacity end
			if component.settings and component.settings.textSize then component.settings.textSize.settingId = sidTextSize end
		end

		local init = {}

		local function addHeader(sectionKey, headerName)
			local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = headerName,
				sectionKey = sectionKey,
				componentId = "objectiveTracker",
				expanded = panel:IsSectionExpanded("objectiveTracker", sectionKey),
			})
			expInitializer.GetExtent = function() return 30 end
			table.insert(init, expInitializer)
		end

		local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
		local function applyNow()
			if addon and addon.ApplyStyles then addon:ApplyStyles() end
		end
		local function refreshOpacityNow()
			if addon and addon.RefreshOpacityState then
				addon:RefreshOpacityState()
			else
				applyNow()
			end
		end

		local function addEditModeSlider(sectionKey, label, settingKey, settingIdFallback)
			local emSettingId = (component.settings and component.settings[settingKey] and component.settings[settingKey].settingId) or settingIdFallback
			local minV, maxV, step = GetSliderMeta(emSettingId)
			-- Defensive fallback ranges (should be overwritten by display info in normal retail)
			if minV == nil or maxV == nil or step == nil then
				if settingKey == "opacity" then
					minV, maxV, step = 0, 100, 1
				elseif settingKey == "textSize" then
					minV, maxV, step = 6, 32, 1
				else
					minV, maxV, step = 200, 800, 1
				end
			end

			local options = Settings.CreateSliderOptions(minV, maxV, step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmtInt)

			local setting = CreateLocalSetting(label, "number",
				function()
					-- Prefer DB value when present; otherwise read live Edit Mode value for a truthful initial display.
					local v = component.db and component.db[settingKey]
					if v ~= nil then
						v = tonumber(v)
						-- Back-compat normalization:
						-- Older builds could persist Objective Tracker Height as an index (0..N) instead of raw (400..1000).
						-- If we see an in-range index-like value, convert it to raw immediately so the slider label matches
						-- the real height and the next write doesn't "jump" to max.
						if settingKey == "height" and v ~= nil and minV ~= nil and maxV ~= nil and step ~= nil then
							if v >= 0 and v < minV and step > 0 then
								local maxIndex = math.floor(((maxV - minV) / step) + 0.5)
								if v <= maxIndex then
									local converted = minV + (v * step)
									component.db[settingKey] = converted
									v = converted
								end
							end
						end
						-- Back-compat normalization:
						-- Some clients persist Objective Tracker Text Size as an index (0..N) instead of raw (12..20).
						-- If we see an index-like value, convert it immediately so the slider and styling remain correct.
						if settingKey == "textSize" and v ~= nil and minV ~= nil and maxV ~= nil and step ~= nil then
							if v >= 0 and v < minV and step > 0 then
								local maxIndex = math.floor(((maxV - minV) / step) + 0.5)
								if v <= maxIndex then
									local converted = minV + (v * step)
									component.db[settingKey] = converted
									v = converted
								end
							end
						end
						return v
					end
					local frame = _G[component.frameName]
					if addon.EditMode and addon.EditMode.GetSetting and frame and emSettingId ~= nil then
						local raw = addon.EditMode.GetSetting(frame, emSettingId)
						return tonumber(raw)
					end
					return nil
				end,
				function(v)
					component.db[settingKey] = tonumber(v)
					if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
						addon.EditMode.SyncComponentSettingToEditMode(component, settingKey)
					end
				end,
				nil
			)

			local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = "objectiveTracker" })
			row.GetExtent = function() return 34 end
			row:AddShownPredicate(function()
				return panel:IsSectionExpanded("objectiveTracker", sectionKey)
			end)
			do
				local base = row.InitFrame
				row.InitFrame = function(selfInit, frame)
					if base then base(selfInit, frame) end
					if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
					if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
					if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
				end
			end
			table.insert(init, row)
		end

		local function addAddonSlider(sectionKey, label, dbKey, minV, maxV, step, defaultValue, onApply)
			local options = Settings.CreateSliderOptions(minV, maxV, step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmtInt)

			local setting = CreateLocalSetting(label, "number",
				function()
					local v = component.db and component.db[dbKey]
					v = tonumber(v)
					if v == nil then
						return tonumber(defaultValue)
					end
					return v
				end,
				function(v)
					component.db[dbKey] = tonumber(v)
					if type(onApply) == "function" then
						onApply()
					else
						applyNow()
					end
				end,
				defaultValue
			)

			local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = "objectiveTracker" })
			row.GetExtent = function() return 34 end
			row:AddShownPredicate(function()
				return panel:IsSectionExpanded("objectiveTracker", sectionKey)
			end)
			do
				local base = row.InitFrame
				row.InitFrame = function(selfInit, frame)
					if base then base(selfInit, frame) end
					if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
					if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
					if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
				end
			end
			table.insert(init, row)
		end

		-- Sizing: Height + Text Size (Edit Mode)
		addHeader("Sizing", "Sizing")
		addEditModeSlider("Sizing", "Height", "height", 0)
		addEditModeSlider("Sizing", "Text Size", "textSize", 2)

		-- Style: Header background controls
		addHeader("Style", "Style")
		do
			-- Hide Header Backgrounds
			do
				local label = "Hide Header Backgrounds"
				local setting = CreateLocalSetting(label, "boolean",
					function()
						local v = component.db and component.db.hideHeaderBackgrounds
						return not not v
					end,
					function(v)
						component.db.hideHeaderBackgrounds = not not v
						applyNow()
					end,
					false
				)
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {}, componentId = "objectiveTracker" })
				initCb.GetExtent = function() return 26 end
				initCb:AddShownPredicate(function()
					return panel:IsSectionExpanded("objectiveTracker", "Style")
				end)
				do
					local base = initCb.InitFrame
					initCb.InitFrame = function(selfInit, frame)
						if base then base(selfInit, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite then
							local cb = frame.Checkbox or frame.CheckBox or frame.Control
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
						end
					end
				end
				table.insert(init, initCb)
			end

			-- Tint Header Background (checkbox + swatch)
			do
				local function getTintColor()
					local c = (component.db and type(component.db.tintHeaderBackgroundColor) == "table" and component.db.tintHeaderBackgroundColor) or {1, 1, 1, 1}
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end

				local tintSetting = CreateLocalSetting("Tint Header Background", "boolean",
					function()
						local v = component.db and component.db.tintHeaderBackgroundEnable
						return not not v
					end,
					function(v)
						component.db.tintHeaderBackgroundEnable = not not v
						applyNow()
					end,
					false
				)

				local tintInit = CreateCheckboxWithSwatchInitializer(
					tintSetting,
					"Tint Header Background",
					getTintColor,
					function(r, g, b, a)
						component.db.tintHeaderBackgroundColor = { r or 1, g or 1, b or 1, a or 1 }
						applyNow()
					end,
					8
				)
				tintInit.GetExtent = function() return 26 end
				tintInit:AddShownPredicate(function()
					return panel:IsSectionExpanded("objectiveTracker", "Style")
				end)
				do
					local base = tintInit.InitFrame
					tintInit.InitFrame = function(selfInit, frame)
						if base then base(selfInit, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite then
							local cb = frame.Checkbox or frame.CheckBox or frame.Control
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							if frame.Text then panel.ApplyRobotoWhite(frame.Text) end
						end
					end
				end
				table.insert(init, tintInit)
			end
		end

		-- Text: Tabbed section
		addHeader("Text", "Text")
		do
			local data = {
				sectionTitle = "",
				tabAText = "Header",
				tabBText = "Quest Name",
				tabCText = "Quest Objective",
			}

			local function fontOptions()
				return addon.BuildFontOptionsContainer()
			end

			local function styleOptions()
				local c = Settings.CreateControlTextContainer()
				c:Add("NONE", "Regular")
				c:Add("OUTLINE", "Outline")
				c:Add("THICKOUTLINE", "Thick Outline")
				return c:GetData()
			end

			local function colorModeOptions()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("custom", "Custom")
				return c:GetData()
			end

			local function ensureConfig(db, key, defaults)
				db[key] = db[key] or {}
				local t = db[key]
				if t.fontFace == nil then t.fontFace = defaults.fontFace end
				if t.style == nil then t.style = defaults.style end
				if t.colorMode == nil then t.colorMode = defaults.colorMode end
				if type(t.color) ~= "table" then t.color = { defaults.color[1], defaults.color[2], defaults.color[3], defaults.color[4] } end
				return t
			end

			local function buildPage(pageFrame, dbKey, defaults)
				local yRef = { y = -50 }
				local db = component.db

				-- 1) Font (dropdown w/ font picker)
				do
					local label = "Font"
					local setting = CreateLocalSetting(label, "string",
						function()
							local t = (type(db[dbKey]) == "table") and db[dbKey] or nil
							return (t and t.fontFace) or defaults.fontFace
						end,
						function(v)
							local t = ensureConfig(db, dbKey, defaults)
							t.fontFace = v or defaults.fontFace
							applyNow()
						end,
						defaults.fontFace
					)
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = setting, options = fontOptions })
					local fDrop = CreateFrame("Frame", nil, pageFrame, "SettingsDropdownControlTemplate")
					fDrop.GetElementData = function() return initDrop end
					fDrop:SetPoint("TOPLEFT", 4, yRef.y)
					fDrop:SetPoint("TOPRIGHT", -16, yRef.y)
					initDrop:InitFrame(fDrop)
					local lbl = fDrop and (fDrop.Text or fDrop.Label)
					if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
					if fDrop.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(fDrop.Control) end
					if fDrop.Control and fDrop.Control.Dropdown and addon and addon.InitFontDropdown then
						addon.InitFontDropdown(fDrop.Control.Dropdown, setting, fontOptions)
					end
					yRef.y = yRef.y - 34
				end

				-- 2) Font Style
				do
					local label = "Font Style"
					local setting = CreateLocalSetting(label, "string",
						function()
							local t = (type(db[dbKey]) == "table") and db[dbKey] or nil
							return (t and t.style) or defaults.style
						end,
						function(v)
							local t = ensureConfig(db, dbKey, defaults)
							t.style = v or defaults.style
							applyNow()
						end,
						defaults.style
					)
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = setting, options = styleOptions })
					local fDrop = CreateFrame("Frame", nil, pageFrame, "SettingsDropdownControlTemplate")
					fDrop.GetElementData = function() return initDrop end
					fDrop:SetPoint("TOPLEFT", 4, yRef.y)
					fDrop:SetPoint("TOPRIGHT", -16, yRef.y)
					initDrop:InitFrame(fDrop)
					local lbl = fDrop and (fDrop.Text or fDrop.Label)
					if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
					if fDrop.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(fDrop.Control) end
					yRef.y = yRef.y - 34
				end

				-- 3) Font Color (Default/Custom + inline swatch)
				do
					panel.DropdownWithInlineSwatch(pageFrame, yRef, {
						label = "Font Color",
						getMode = function()
							local t = (type(db[dbKey]) == "table") and db[dbKey] or nil
							return (t and t.colorMode) or defaults.colorMode
						end,
						setMode = function(v)
							local t = ensureConfig(db, dbKey, defaults)
							t.colorMode = v or defaults.colorMode
							applyNow()
						end,
						getColor = function()
							local t = (type(db[dbKey]) == "table") and db[dbKey] or nil
							local c = (t and type(t.color) == "table" and t.color) or defaults.color
							return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
						end,
						setColor = function(r, g, b, a)
							local t = ensureConfig(db, dbKey, defaults)
							t.color = { r or 1, g or 1, b or 1, a or 1 }
							applyNow()
						end,
						options = colorModeOptions,
						insideButton = true,
					})
					yRef.y = yRef.y - 34
				end
			end

			data.build = function(frame)
				local db = component.db
				-- Note: the DB proxy auto-creates on first write; do not eagerly create here.
				if type(db) ~= "table" then return end

				buildPage(frame.PageA, "textHeader", {
					fontFace = "FRIZQT__",
					style = "OUTLINE",
					colorMode = "default",
					color = { 1, 1, 1, 1 },
				})
				buildPage(frame.PageB, "textQuestName", {
					fontFace = "FRIZQT__",
					style = "OUTLINE",
					colorMode = "default",
					color = { 1, 1, 1, 1 },
				})
				buildPage(frame.PageC, "textQuestObjective", {
					fontFace = "FRIZQT__",
					style = "OUTLINE",
					colorMode = "default",
					color = { 0.8, 0.8, 0.8, 1 },
				})
			end

			local tabbedInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
			tabbedInit.GetExtent = function() return 170 end
			tabbedInit:AddShownPredicate(function()
				return panel:IsSectionExpanded("objectiveTracker", "Text")
			end)
			table.insert(init, tabbedInit)
		end

		-- Visibility: Opacity (Edit Mode)
		addHeader("Visibility", "Visibility")
		addEditModeSlider("Visibility", "Background Opacity", "opacity", 1)
		addAddonSlider("Visibility", "Opacity In-Instance-Combat", "opacityInInstanceCombat", 0, 100, 1, 100, refreshOpacityNow)

		if right.SetTitle then
			right:SetTitle("Objective Tracker")
		end
		right:Display(init)
	end

	return { mode = "list", render = render, componentId = "objectiveTracker" }
end


