local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

panel.builders = panel.builders or {}
panel.common = panel.common or {}
local common = panel.common

-- Ensure callers can safely query expansion state even if mixins failed to load.
if type(panel.IsSectionExpanded) ~= "function" then
	function panel:IsSectionExpanded(componentId, sectionKey)
		self._expanded = self._expanded or {}
		self._expanded[componentId] = self._expanded[componentId] or {}
		local v = self._expanded[componentId][sectionKey]
		if v == nil then v = false end
		return v
	end
end

-- Temporarily block mousewheel input on the right-hand scroll frame during short
-- layout windows (e.g., immediate scroll after toggling a checkbox).
function panel:PauseScrollWheel(duration)
	local f = self.frame
	local sl = f and f.RightPane and f.RightPane.ScrollFrame
	if not sl then return end
	if not sl._wheelBlocker then
		local blocker = CreateFrame("Frame", nil, sl)
		blocker:SetAllPoints(sl)
		blocker:EnableMouse(true)
		blocker:EnableMouseWheel(true)
		blocker:SetScript("OnMouseWheel", function() end)
		blocker:Hide()
		sl._wheelBlocker = blocker
	end
	local blocker = sl._wheelBlocker
	blocker:Show()
	if blocker._timer and blocker._timer.Cancel then blocker._timer:Cancel() end
	blocker._timer = C_Timer.NewTimer(duration or 0.25, function()
		if blocker then blocker:Hide() end
	end)
end

local function buildAuraWrapOptions(component)
	local container = Settings.CreateControlTextContainer()
	local orientation = (component and component.db and component.db.orientation) or "H"
	if orientation == "H" then
		container:Add("down", "Down")
		container:Add("up", "Up")
	else
		container:Add("left", "Left")
		container:Add("right", "Right")
	end
	return container:GetData()
end

local function buildAuraDirectionOptions(component)
	local container = Settings.CreateControlTextContainer()
	local orientation = (component and component.db and component.db.orientation) or "H"
	if orientation == "H" then
		container:Add("left", "Left")
		container:Add("right", "Right")
	else
		container:Add("down", "Down")
		container:Add("up", "Up")
	end
	return container:GetData()
end

local function buildDirectionOptions(component)
	local orientation = (component and component.db and component.db.orientation) or "H"
	local container = Settings.CreateControlTextContainer()
	if orientation == "H" then
		container:Add("left", "Left")
		container:Add("right", "Right")
	else
		container:Add("up", "Up")
		container:Add("down", "Down")
	end
	return container:GetData()
end

local function ensureDirectionValue(component)
	if not component or not component.db then return end
	local orientation = component.db.orientation or "H"
	local dir = component.db.direction
	if orientation == "H" then
		if dir ~= "left" and dir ~= "right" then
			dir = "right"
			component.db.direction = dir
		end
	else
		if dir ~= "up" and dir ~= "down" then
			dir = "up"
			component.db.direction = dir
		end
	end
	return dir
end

local function ensureWrapValue(component)
	if not component or not component.db then return end
	local orientation = component.db.orientation or "H"
	local wrap = component.db.iconWrap
	if orientation == "H" then
		if wrap ~= "down" and wrap ~= "up" then
			wrap = "down"
			component.db.iconWrap = wrap
		end
	else
		if wrap ~= "left" and wrap ~= "right" then
			wrap = "left"
			component.db.iconWrap = wrap
		end
	end
	return wrap
end

local function getFrameLabel(frame)
	local lbl = frame and (frame.Text or frame.Label)
	if not lbl and frame and frame.GetRegions then
		local regions = { frame:GetRegions() }
		for i = 1, #regions do
			local r = regions[i]
			if r and r.IsObjectType and r:IsObjectType("FontString") then
				lbl = r
				break
			end
		end
	end
	return lbl
end

local function applyColumnsLabel(component, frame)
	if not component or not frame then return end
	local orientation = (component.db and component.db.orientation) or "H"
	local labelText = (orientation == "H") and "# Columns" or "# Rows"
	local lbl = getFrameLabel(frame)
	if lbl and lbl.SetText then
		lbl:SetText(labelText)
		if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
	end
	local initializer = frame.GetElementData and frame:GetElementData()
	if initializer and initializer.data then
		initializer.data.name = labelText
	end
end

local function applyIconLimitLabel(component, frame)
	if not component or not frame then return end
	local orientation = (component.db and component.db.orientation) or "H"
	local labelText = (orientation == "H") and "Icons per Row" or "Icons per Column"
	local lbl = getFrameLabel(frame)
	if lbl and lbl.SetText then
		lbl:SetText(labelText)
		if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
	end
	local initializer = frame.GetElementData and frame:GetElementData()
	if initializer and initializer.data then
		initializer.data.name = labelText
	end
end

panel._orientationWidgets = panel._orientationWidgets or {}

local function ensureOrientationBucket(componentId)
	panel._orientationWidgets = panel._orientationWidgets or {}
	if componentId and not panel._orientationWidgets[componentId] then
		panel._orientationWidgets[componentId] = { columns = {}, direction = {}, iconWrap = {}, iconLimit = {} }
	end
	return componentId and panel._orientationWidgets[componentId]
end

function panel:PrepareOrientationWidgets(componentId)
	if not componentId then return end
	self._orientationWidgets = self._orientationWidgets or {}
	self._orientationWidgets[componentId] = { columns = {}, direction = {}, iconWrap = {}, iconLimit = {} }
end

function panel:RegisterOrientationWidget(componentId, kind, frame)
	if not componentId or not frame then return end
	local bucket = ensureOrientationBucket(componentId)
	if not bucket then return end
	bucket[kind] = bucket[kind] or {}
	bucket[kind][frame] = true
end

local function enumerateOrientationFrames(bucket, kind)
	if not bucket then return function() end end
	local frames = {}
	for frame in pairs(bucket[kind] or {}) do
		table.insert(frames, frame)
	end
	return ipairs(frames)
end

function panel:RefreshOrientationWidgets(component)
	local comp = component
	if type(comp) ~= "table" then
		comp = addon.Components and addon.Components[component]
	end
	if not comp or not comp.id then return end
	local bucket = self._orientationWidgets and self._orientationWidgets[comp.id]
	if not bucket then return end

	for _, frame in enumerateOrientationFrames(bucket, "columns") do
		applyColumnsLabel(comp, frame)
	end

	for _, frame in enumerateOrientationFrames(bucket, "iconLimit") do
		applyIconLimitLabel(comp, frame)
	end

	for _, frame in enumerateOrientationFrames(bucket, "direction") do
		local initializer = frame.GetElementData and frame:GetElementData()
		if initializer and initializer.data then
			if comp.id == "buffs" or comp.id == "debuffs" then
				initializer.data.options = function()
					return buildAuraDirectionOptions(comp)
				end
			else
				initializer.data.options = function()
					return buildDirectionOptions(comp)
				end
			end
		end
		ensureDirectionValue(comp)
		if frame.InitDropdown then
			frame:InitDropdown()
		end
		local setting = frame.GetSetting and frame:GetSetting()
		if setting and frame.Control and frame.Control.Dropdown and frame.Control.Dropdown.SetSelectedValue then
			local current = setting and setting.GetValue and setting:GetValue()
			if current ~= nil then
				frame.Control.Dropdown:SetSelectedValue(current)
			end
		end
	end

	for _, frame in enumerateOrientationFrames(bucket, "iconWrap") do
		local initializer = frame.GetElementData and frame:GetElementData()
		if initializer and initializer.data then
			initializer.data.options = function()
				return buildAuraWrapOptions(comp)
			end
		end
		ensureWrapValue(comp)
		if frame.InitDropdown then
			frame:InitDropdown()
		end
		local setting = frame.GetSetting and frame:GetSetting()
		if setting and frame.Control and frame.Control.Dropdown and frame.Control.Dropdown.SetSelectedValue then
			local current = setting and setting.GetValue and setting:GetValue()
			if current ~= nil then
				frame.Control.Dropdown:SetSelectedValue(current)
			end
		end
	end
end

common.BuildAuraWrapOptions = buildAuraWrapOptions
common.BuildAuraDirectionOptions = buildAuraDirectionOptions
common.BuildDirectionOptions = buildDirectionOptions
common.EnsureDirectionValue = ensureDirectionValue
common.EnsureWrapValue = ensureWrapValue
common.GetFrameLabel = getFrameLabel
common.ApplyColumnsLabel = applyColumnsLabel
common.ApplyIconLimitLabel = applyIconLimitLabel
common.EnumerateOrientationFrames = enumerateOrientationFrames

