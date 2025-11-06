local addonName, addon = ...

addon.ClassColors = {
	DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
	DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
	DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
	EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
	HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
	MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
	MONK        = { r = 0.00, g = 1.00, b = 0.59 },
	PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
	PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
	ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
	SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
	WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
	WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

-- Default stock colors used by Blizzard UI when bars are not class- or custom-colored
addon.HealthDefaultColor = { r = 0.00, g = 1.00, b = 0.00 }

-- Static fallback map for power colors (sourced from Blizzard UI: PowerBarColorUtil.lua)
-- Used only when the global PowerBarColor table is unavailable at runtime
addon.PowerColors = {
	MANA = { r = 0.00, g = 0.00, b = 1.00 },
	RAGE = { r = 1.00, g = 0.00, b = 0.00 },
	FOCUS = { r = 1.00, g = 0.50, b = 0.25 },
	ENERGY = { r = 1.00, g = 1.00, b = 0.00 },
	COMBO_POINTS = { r = 1.00, g = 0.96, b = 0.41 },
	RUNES = { r = 0.50, g = 0.50, b = 0.50 },
	RUNIC_POWER = { r = 0.00, g = 0.82, b = 1.00 },
	SOUL_SHARDS = { r = 0.50, g = 0.32, b = 0.55 },
	LUNAR_POWER = { r = 0.30, g = 0.52, b = 0.90 },
	HOLY_POWER = { r = 0.95, g = 0.90, b = 0.60 },
	MAELSTROM = { r = 0.00, g = 0.50, b = 1.00 },
	INSANITY = { r = 0.40, g = 0.00, b = 0.80 },
	CHI = { r = 0.71, g = 1.00, b = 0.92 },
	ARCANE_CHARGES = { r = 0.10, g = 0.10, b = 0.98 },
	FURY = { r = 0.788, g = 0.259, b = 0.992 },
	PAIN = { r = 1.00, g = 0.61176470588235, b = 0.00 }, -- 255/255,156/255,0
	-- Numeric fallbacks (indices from Blizzard)
	[0] = { r = 0.00, g = 0.00, b = 1.00 }, -- MANA
	[1] = { r = 1.00, g = 0.00, b = 0.00 }, -- RAGE
	[2] = { r = 1.00, g = 0.50, b = 0.25 }, -- FOCUS
	[3] = { r = 1.00, g = 1.00, b = 0.00 }, -- ENERGY
	[4] = { r = 0.71, g = 1.00, b = 0.92 }, -- CHI
	[5] = { r = 0.50, g = 0.50, b = 0.50 }, -- RUNES
	[6] = { r = 0.00, g = 0.82, b = 1.00 }, -- RUNIC_POWER
	[7] = { r = 0.50, g = 0.32, b = 0.55 }, -- SOUL_SHARDS
	[8] = { r = 0.30, g = 0.52, b = 0.90 }, -- LUNAR_POWER
	[9] = { r = 0.95, g = 0.90, b = 0.60 }, -- HOLY_POWER
	[11] = { r = 0.00, g = 0.50, b = 1.00 }, -- MAELSTROM
	[13] = { r = 0.40, g = 0.00, b = 0.80 }, -- INSANITY
	[17] = { r = 0.788, g = 0.259, b = 0.992 }, -- FURY
	[18] = { r = 1.00, g = 0.61176470588235, b = 0.00 }, -- PAIN
}

function addon.GetDefaultHealthColorRGB()
	local c = addon.HealthDefaultColor
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return 0, 1, 0
end

function addon.GetPowerColorRGB(unitOrPower)
	local tokenOrIndex = nil
	if type(unitOrPower) == "string" then
		if UnitPowerType and (unitOrPower == "player" or unitOrPower == "target" or unitOrPower == "focus" or unitOrPower == "pet") then
			local idx, tok = UnitPowerType(unitOrPower)
			tokenOrIndex = tok or idx
		else
			tokenOrIndex = unitOrPower
		end
	elseif type(unitOrPower) == "number" then
		tokenOrIndex = unitOrPower
	end

	local c = nil
	if _G.PowerBarColor and tokenOrIndex ~= nil then
		c = _G.PowerBarColor[tokenOrIndex] or _G.PowerBarColor[tonumber(tokenOrIndex) or -1]
	end
	if not c and tokenOrIndex ~= nil then
		c = addon.PowerColors[tokenOrIndex] or addon.PowerColors[tonumber(tokenOrIndex) or -1]
	end
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return 1, 1, 1
end

function addon.GetClassColorRGB(unitOrClassToken)
	local classToken = nil
	if type(unitOrClassToken) == "string" then
		-- Prefer unit id (e.g., "player") when provided
		if UnitClass and (unitOrClassToken == "player" or unitOrClassToken == "target" or unitOrClassToken == "focus" or unitOrClassToken == "pet") then
			local _, token = UnitClass(unitOrClassToken)
			classToken = token
		else
			classToken = unitOrClassToken
		end
	end
	if type(classToken) ~= "string" then
		return 1, 1, 1 -- fallback white
	end
	-- Use our static table first; fall back to RAID_CLASS_COLORS when available
	local c = addon.ClassColors[classToken]
	if not c and _G.RAID_CLASS_COLORS then c = _G.RAID_CLASS_COLORS[classToken] end
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return 1, 1, 1
end
