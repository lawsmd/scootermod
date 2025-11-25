local addonName, addon = ...

local originalPositions = setmetatable({}, { __mode = "k" })
local originalScales = setmetatable({}, { __mode = "k" })
local layoutHooked = false

local function ensureLayoutHook()
	if layoutHooked then
		return
	end
	local container = _G.PlayerFrameBottomManagedFramesContainer
	if container and _G.hooksecurefunc then
		layoutHooked = true
		_G.hooksecurefunc(container, "Layout", function()
			if addon and addon.ApplyUnitFrameClassResource then
				addon.ApplyUnitFrameClassResource("Player")
			end
		end)
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

local function captureBaseline(frame)
	if not frame or originalPositions[frame] then
		return
	end
	if not frame.GetPoint then
		return
	end
	local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
	if not point then
		return
	end
	originalPositions[frame] = {
		point = point,
		relativeTo = relativeTo,
		relativePoint = relativePoint,
		xOfs = xOfs or 0,
		yOfs = yOfs or 0,
	}
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

local function applyClassResourceForUnit(unit)
	if unit ~= "Player" then
		return
	end

	local cfg = ensureConfig()
	if not cfg then
		return
	end

	if cfg.scale == nil then
		cfg.scale = 100
	end
	if cfg.hide == nil then
		cfg.hide = false
	end

	local frames, _ = resolveClassResourceFrames()
	if #frames == 0 then
		return
	end

	ensureLayoutHook()

	if InCombatLockdown and InCombatLockdown() then
		return
	end

	local offsetX = clampOffset(cfg.offsetX)
	local offsetY = clampOffset(cfg.offsetY)

	for _, frame in ipairs(frames) do
		captureBaseline(frame)
		if frame and not originalScales[frame] and frame.GetScale then
			local ok, scale = pcall(frame.GetScale, frame)
			if ok and scale then
				originalScales[frame] = scale
			else
				originalScales[frame] = 1
			end
		end
	end

	for _, frame in ipairs(frames) do
		local baseline = originalPositions[frame]
		if baseline and frame.ClearAllPoints and frame.SetPoint then
			pcall(frame.ClearAllPoints, frame)
			pcall(frame.SetPoint, frame, baseline.point, baseline.relativeTo, baseline.relativePoint, (baseline.xOfs or 0) + offsetX, (baseline.yOfs or 0) + offsetY)
		end
		local baseScale = originalScales[frame] or 1
		if frame.SetScale then
			local multiplier = clampScale(cfg.scale) / 100
			pcall(frame.SetScale, frame, baseScale * multiplier)
		end
		if cfg.hide then
			pcall(frame.Hide, frame)
		else
			pcall(frame.Show, frame)
		end
	end
end

function addon.ApplyUnitFrameClassResource(unit)
	applyClassResourceForUnit(unit or "Player")
end

function addon.ApplyAllUnitFrameClassResources()
	applyClassResourceForUnit("Player")
end

function addon.UnitFrames_GetPlayerClassResourceTitle()
	local _, label = resolveClassResourceFrames()
	if label and label ~= "" then
		return label
	end
	return "Class Resource"
end

