local addonName, addon = ...

local Util = addon.ComponentsUtil
local PlayerInCombat = Util and Util.PlayerInCombat or function() return InCombatLockdown and InCombatLockdown() end

local function getUiScale()
	local parent = UIParent
	if parent and parent.GetEffectiveScale then
		local scale = parent:GetEffectiveScale()
		if scale and scale > 0 then
			return scale
		end
	end
	return 1
end

local function pixelsToUiUnits(px)
	return (tonumber(px) or 0) / getUiScale()
end

local function clampScreenCoordinate(value)
	local v = tonumber(value) or 0
	if v > 2000 then
		v = 2000
	elseif v < -2000 then
		v = -2000
	end
	return math.floor(v + (v >= 0 and 0.5 or -0.5))
end

local function getFrameScreenOffsets(frame)
	if not (frame and frame.GetCenter and UIParent and UIParent.GetCenter) then
		return 0, 0
	end
	local fx, fy = frame:GetCenter()
	local px, py = UIParent:GetCenter()
	if not (fx and fy and px and py) then
		return 0, 0
	end
	return math.floor((fx - px) + 0.5), math.floor((fy - py) + 0.5)
end

local pendingClassResourceReapply = false
local classResourceCombatWatcher = nil

local function ensureClassResourceCombatWatcher()
	if classResourceCombatWatcher then
		return
	end
	classResourceCombatWatcher = CreateFrame("Frame")
	classResourceCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	classResourceCombatWatcher:SetScript("OnEvent", function()
		if pendingClassResourceReapply then
			pendingClassResourceReapply = false
			if addon.ApplyUnitFrameClassResource then
				addon.ApplyUnitFrameClassResource("Player")
			end
		end
	end)
end

local function queueClassResourceReapply()
	ensureClassResourceCombatWatcher()
	pendingClassResourceReapply = true
end

-- Baseline storage for managed frame offsets
-- NOTE: We do NOT capture frame scales because frames may retain our previously-applied
-- scale across reloads. Class resource frames have no Edit Mode scale, so baseline is always 1.0.
local originalPaddings = setmetatable({}, { __mode = "k" })
local originalAnchors = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local layoutHooked = false

-- Debug helper (disabled by default)
local DEBUG_CLASS_RESOURCE = false
local function debugPrint(...)
	if DEBUG_CLASS_RESOURCE and addon and addon.DebugPrint then
		addon.DebugPrint("[ClassResource]", ...)
	elseif DEBUG_CLASS_RESOURCE then
		print("[ScooterMod ClassResource]", ...)
	end
end

local function safeGetFrame(name)
	local frame = _G[name]
	if frame and frame.IsForbidden and frame:IsForbidden() then
		return nil
	end
	return frame
end

local CLASS_RESOURCE_ENTRIES = {
	{
		label = "Druid Combo Points",
		classes = { DRUID = true },
		frameNames = { "DruidComboPointBarFrame" },
	},
	{
		label = "Rogue Combo Points",
		classes = { ROGUE = true },
		frameNames = { "RogueComboPointBarFrame", "ComboPointPlayerFrame" },
	},
	{
		label = "Paladin Holy Power",
		classes = { PALADIN = true },
		frameNames = { "PaladinPowerBarFrame" },
	},
	{
		label = "Monk Chi",
		classes = { MONK = true },
		frameNames = { "MonkHarmonyBarFrame" },
	},
	{
		label = "Warlock Soul Shards",
		classes = { WARLOCK = true },
		frameNames = { "WarlockPowerFrame" },
	},
	{
		label = "Death Knight Runes",
		classes = { DEATHKNIGHT = true },
		frameNames = { "RuneFrame" },
	},
	{
		label = "Shaman Totems",
		classes = { SHAMAN = true },
		frameNames = { "TotemFrame" },
	},
	{
		label = "Mage Arcane Charges",
		classes = { MAGE = true },
		frameNames = { "MageArcaneChargesFrame" },
	},
	{
		label = "Evoker Essence",
		classes = { EVOKER = true },
		frameNames = { "EssencePlayerFrame" },
	},
}

local CLASS_LABELS = {}
for _, entry in ipairs(CLASS_RESOURCE_ENTRIES) do
	if entry.classes then
		for classToken in pairs(entry.classes) do
			CLASS_LABELS[classToken] = entry.label
		end
	end
end

local function ensureConfig()
	local db = addon and addon.db and addon.db.profile
	if not db then return nil end
	db.unitFrames = db.unitFrames or {}
	db.unitFrames.Player = db.unitFrames.Player or {}
	db.unitFrames.Player.classResource = db.unitFrames.Player.classResource or {}
	return db.unitFrames.Player.classResource
end

local function resolveClassResourceFrames()
	local classToken = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
	local fallbackLabel = (classToken and CLASS_LABELS[classToken]) or "Class Resource"
	if not classToken then
		return {}, fallbackLabel
	end

	for _, entry in ipairs(CLASS_RESOURCE_ENTRIES) do
		if entry.classes and entry.classes[classToken] then
			local resolved = {}
			local seen = {}
			for _, frameName in ipairs(entry.frameNames or {}) do
				local frame = safeGetFrame(frameName)
				if frame and not seen[frame] then
					resolved[#resolved + 1] = frame
					seen[frame] = true
				end
			end
			if #resolved > 0 then
				return resolved, entry.label
			end
		end
	end

	return {}, fallbackLabel
end

-- Capture original padding values for managed frames
-- NOTE: We do NOT capture scale because frames may retain our applied scale across reloads.
-- Class resource frames have no Edit Mode scale setting, so baseline is always 1.0.
local function captureBaselines(frame)
	if not frame then return end
	
	-- Capture original padding (used by LayoutFrame system for positioning)
	if not originalPaddings[frame] then
		originalPaddings[frame] = {
			leftPadding = frame.leftPadding or 0,
			topPadding = frame.topPadding or 0,
		}
		debugPrint("Captured baseline paddings for", frame:GetName() or "unnamed",
			"left:", originalPaddings[frame].leftPadding,
			"top:", originalPaddings[frame].topPadding)
	end
end

local function captureAnchorState(frame)
	if not frame or originalAnchors[frame] then
		return
	end
	local info = {
		parent = frame:GetParent(),
		points = {},
		leftPadding = frame.leftPadding,
		topPadding = frame.topPadding,
		ignoreManager = frame.IsIgnoringFramePositionManager and frame:IsIgnoringFramePositionManager() or false,
	}
	if frame.GetNumPoints then
		local numPoints = frame:GetNumPoints()
		for i = 1, numPoints do
			local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
			table.insert(info.points, { point, relativeTo, relativePoint, xOfs, yOfs })
		end
	end
	originalAnchors[frame] = info
end

local function restoreAnchorState(frame)
	local info = originalAnchors[frame]
	if not frame or not info then
		return
	end
	-- Note: We do NOT re-parent. The frame stays with its original parent at all times.
	-- We only restore the layout manager state and original anchor points.
	if frame.SetIgnoreFramePositionManager then
		pcall(frame.SetIgnoreFramePositionManager, frame, info.ignoreManager or false)
	end
	if info.points and frame.ClearAllPoints and frame.SetPoint then
		pcall(frame.ClearAllPoints, frame)
		for _, pt in ipairs(info.points) do
			pcall(frame.SetPoint, frame, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", pt[4] or 0, pt[5] or 0)
		end
	end
	if info.leftPadding ~= nil then
		frame.leftPadding = info.leftPadding
	end
	if info.topPadding ~= nil then
		frame.topPadding = info.topPadding
	end
end

local function ensureCustomClassResourceSeed(cfg, frame)
	if not cfg or not cfg.classResourceCustomPositionEnabled or not frame then
		return
	end
	-- Force 0,0 (screen center) for new users to avoid unexpected positioning
	-- Previously tried to seed from current frame position but this caused
	-- the bar to disappear on first enable due to coordinate conversion issues
	if cfg.classResourcePosX == nil then
		cfg.classResourcePosX = 0
	end
	if cfg.classResourcePosY == nil then
		cfg.classResourcePosY = 0
	end
end

local function applyCustomClassResourcePosition(frame, cfg)
	if not frame or not cfg or not cfg.classResourceCustomPositionEnabled then
		return false
	end
	if PlayerInCombat() then
		queueClassResourceReapply()
		return true
	end
	captureAnchorState(frame)
	ensureCustomClassResourceSeed(cfg, frame)
	-- POLICY COMPLIANT: Do NOT re-parent the frame. Instead:
	-- 1. Keep the frame parented where Blizzard placed it
	-- 2. Use SetIgnoreFramePositionManager to prevent layout manager from overriding
	-- 3. Anchor to UIParent for absolute screen positioning (frames CAN anchor to non-parents)
	-- This preserves scale and all other customizations.
	if frame.SetIgnoreFramePositionManager then
		pcall(frame.SetIgnoreFramePositionManager, frame, true)
	end
	if frame.ClearAllPoints and frame.SetPoint then
		pcall(frame.ClearAllPoints, frame)
		local posX = clampScreenCoordinate(cfg.classResourcePosX or 0)
		local posY = clampScreenCoordinate(cfg.classResourcePosY or 0)
		pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", pixelsToUiUnits(posX), pixelsToUiUnits(posY))
	end
	return true
end

local function clampOffset(value)
	local v = tonumber(value) or 0
	if v < -150 then
		return -150
	elseif v > 150 then
		return 150
	end
	return v
end

local function clampScale(value)
	local v = tonumber(value) or 100
	if v < 50 then
		return 50
	elseif v > 150 then
		return 150
	end
	return v
end

-- Hook visibility-restoring functions on a frame to maintain hidden state
-- CRITICAL: We use hooksecurefunc to avoid taint. Method overrides on Blizzard frames
-- cause taint that spreads through the execution context, blocking protected functions
-- like SetTargetClampingInsets() during nameplate setup. See DEBUG.md for details.
local function ensureVisibilityHooks(frame, cfg)
	if not frame or hookedFrames[frame] then return end
	hookedFrames[frame] = true
	
	-- Store reference to config getter for hooks
	frame._ScooterClassResourceCfg = ensureConfig
	
	-- Hook Show to enforce hidden state (runs AFTER Blizzard's Show)
	-- CRITICAL: Combat guard required to avoid tainting nameplate operations during form changes
	if frame.Show then
		hooksecurefunc(frame, "Show", function(self)
			-- Skip during combat to avoid tainting nameplate operations
			if InCombatLockdown and InCombatLockdown() then return end
			local frameCfg = self._ScooterClassResourceCfg and self._ScooterClassResourceCfg()
			if frameCfg and frameCfg.hide then
				self:SetAlpha(0)
				debugPrint("Enforcing hidden via Show hook on", self:GetName() or "unnamed")
			end
		end)
	end
	
	-- Hook SetAlpha to re-enforce hidden state (runs AFTER Blizzard's SetAlpha)
	-- Uses a guard flag to prevent infinite recursion since we call SetAlpha inside the hook
	-- CRITICAL: Combat guard required to avoid tainting nameplate operations during form changes
	if frame.SetAlpha then
		hooksecurefunc(frame, "SetAlpha", function(self, alpha)
			-- Skip during combat to avoid tainting nameplate operations
			if InCombatLockdown and InCombatLockdown() then return end
			-- Guard against recursion
			if self._ScooterClassResourceApplyingAlpha then return end
			
			local frameCfg = self._ScooterClassResourceCfg and self._ScooterClassResourceCfg()
			if frameCfg and frameCfg.hide and alpha ~= 0 then
				-- Frame should be hidden but Blizzard set non-zero alpha; correct it
				self._ScooterClassResourceApplyingAlpha = true
				self:SetAlpha(0)
				self._ScooterClassResourceApplyingAlpha = nil
				debugPrint("Re-enforcing hidden via SetAlpha hook on", self:GetName() or "unnamed")
			end
		end)
	end
	
	debugPrint("Installed visibility hooks on", frame:GetName() or "unnamed")
end

-- Trigger layout update on the managed container
-- Cache the closure to avoid memory allocation on every call
local layoutTriggerClosure = nil
local function triggerLayoutUpdate()
	local container = _G.PlayerFrameBottomManagedFramesContainer
	if container and container.Layout then
		-- Defer to next frame to avoid recursion
		-- CRITICAL: Use cached closure to avoid creating new functions every call
		if not layoutTriggerClosure then
			layoutTriggerClosure = function()
				local c = _G.PlayerFrameBottomManagedFramesContainer
				if c and c.Layout then
					pcall(c.Layout, c)
				end
			end
		end
		C_Timer.After(0, layoutTriggerClosure)
	end
end

-- Set up hook on the layout container to reapply scale after layout
-- CRITICAL: Combat guard required to avoid tainting nameplate operations during form changes
local function ensureLayoutHook()
	if layoutHooked then return end
	
	local container = _G.PlayerFrameBottomManagedFramesContainer
	if container and hooksecurefunc then
		layoutHooked = true
		hooksecurefunc(container, "Layout", function()
			-- Skip during combat to avoid tainting nameplate operations
			if InCombatLockdown and InCombatLockdown() then return end
			-- Reapply scale and visibility after layout completes
			-- Positioning is handled via leftPadding/topPadding which the layout respects
			local cfg = ensureConfig()
			if not cfg then return end
			
			local frames, _ = resolveClassResourceFrames()
			for _, frame in ipairs(frames) do
				-- Reapply scale (layout doesn't override this)
				-- Baseline is always 1.0 for class resources (no Edit Mode scale)
				local multiplier = clampScale(cfg.scale or 100) / 100
				if frame.SetScale then
					pcall(frame.SetScale, frame, multiplier)
				end
				
				-- Reapply visibility
				if cfg.hide then
					pcall(frame.SetAlpha, frame, 0)
				end
			end
			debugPrint("Layout hook fired, reapplied scale and visibility")
		end)
		debugPrint("Installed layout container hook")
	end
end

local function applyClassResourceForUnit(unit)
	if unit ~= "Player" then
		return
	end

	local cfg = ensureConfig()
	if not cfg then
		debugPrint("No config available, skipping apply")
		return
	end

	-- Initialize defaults
	if cfg.scale == nil then cfg.scale = 100 end
	if cfg.hide == nil then cfg.hide = false end
	if cfg.offsetX == nil then cfg.offsetX = 0 end
	if cfg.offsetY == nil then cfg.offsetY = 0 end

	local frames, label = resolveClassResourceFrames()
	if #frames == 0 then
		debugPrint("No frames resolved for class resource:", label)
		return
	end
	
	debugPrint("Applying to", #frames, "frame(s) for", label)

	-- Set up layout hook first
	ensureLayoutHook()

	-- Skip layout-affecting changes during combat
	local inCombat = InCombatLockdown and InCombatLockdown()
	
	local offsetX = clampOffset(cfg.offsetX)
	local offsetY = clampOffset(cfg.offsetY)
	local scaleMultiplier = clampScale(cfg.scale) / 100
	local customPositionActive = cfg.classResourceCustomPositionEnabled == true

	for _, frame in ipairs(frames) do
		captureBaselines(frame)
		ensureVisibilityHooks(frame, cfg)
		if not customPositionActive then
			restoreAnchorState(frame)
		end
		
		local origPadding = originalPaddings[frame] or { leftPadding = 0, topPadding = 0 }
		
		local customHandled = false
		if customPositionActive then
			customHandled = applyCustomClassResourcePosition(frame, cfg)
		end

		-- POSITIONING: Use leftPadding/topPadding only when custom positioning is disabled
		if not customHandled and not inCombat then
			frame.leftPadding = (origPadding.leftPadding or 0) + offsetX
			frame.topPadding = (origPadding.topPadding or 0) - offsetY  -- Negate Y so positive = up
			debugPrint("Set padding for", frame:GetName() or "unnamed",
				"left:", frame.leftPadding, "top:", frame.topPadding)
		end
		
		-- SCALE: Apply scale multiplier - baseline is always 1.0 for class resources (no Edit Mode scale)
		if frame.SetScale then
			pcall(frame.SetScale, frame, scaleMultiplier)
			debugPrint("Set scale for", frame:GetName() or "unnamed", "to", scaleMultiplier)
		end
		
		-- VISIBILITY: Use SetAlpha for managed frames (more reliable than Hide/Show)
		if cfg.hide then
			pcall(frame.SetAlpha, frame, 0)
			debugPrint("Hidden", frame:GetName() or "unnamed", "via SetAlpha(0)")
		else
			pcall(frame.SetAlpha, frame, 1)
			debugPrint("Shown", frame:GetName() or "unnamed", "via SetAlpha(1)")
		end
	end
	
	-- Trigger layout update to apply padding changes when using offsets
	if not inCombat and not customPositionActive and (offsetX ~= 0 or offsetY ~= 0) then
		triggerLayoutUpdate()
	end
end

function addon.ApplyUnitFrameClassResource(unit)
	applyClassResourceForUnit(unit or "Player")
end

function addon.ApplyAllUnitFrameClassResources()
	applyClassResourceForUnit("Player")
end

function addon.UnitFrames_GetClassResourceScreenPosition()
	local frames = resolveClassResourceFrames()
	local frame = frames and frames[1]
	if not frame then
		return 0, 0
	end
	local x, y = getFrameScreenOffsets(frame)
	return clampScreenCoordinate(x), clampScreenCoordinate(y)
end

function addon.UnitFrames_GetPlayerClassResourceTitle()
	local _, label = resolveClassResourceFrames()
	if label and label ~= "" then
		return label
	end
	return "Class Resource"
end

