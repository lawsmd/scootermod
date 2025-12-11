local addonName, addon = ...

-- Unit Frames: Toggle Health % (LeftText) and Value (RightText) visibility per unit
do
    -- Cache for resolved health text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufHealthTextFonts = addon._ufHealthTextFonts or {}

    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			-- Fallback for environments where Edit Mode indices aren't available
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if EM then
			idx = (unit == "Player" and EM.Player)
				or (unit == "Target" and EM.Target)
				or (unit == "Focus" and EM.Focus)
				or (unit == "Pet" and EM.Pet)
		end
		if idx then
			return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
		end
		-- If no index was resolved (older builds lacking EM.Pet), try known globals
		if unit == "Pet" then return _G.PetFrame end
		return nil
    end

    local function findFontStringByNameHint(root, hint)
        if not root then return nil end
        local target
        local function scan(obj)
            if not obj or target then return end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
                if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                    target = obj; return
                end
            end
            if obj.GetRegions then
                local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                for i = 1, n do
                    local r = select(i, obj:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                        local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
                        if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                            target = r; return
                        end
                    end
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    scan(c)
                    if target then return end
                end
            end
        end
        scan(root)
        return target
    end

    -- Resolve health bar for this unit
    local function resolveHealthBarForVisibility(frame, unit)
        if unit == "Pet" then return _G.PetFrameHealthBar end
        if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then
            return frame.HealthBarsContainer.HealthBar
        end
        -- Try direct paths
        if unit == "Player" then
            local root = _G.PlayerFrame
            if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar then
                return root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar then
                return root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar then
                return root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            end
        end
        return nil
    end

    -- Helper: determine whether the current player's spec uses an Alternate Power Bar.
    -- We intentionally key off spec IDs so the check is cheap and future‑proof.
    -- Specs covered (per user guidance):
    --   - Balance Druid      (specID = 102, class = DRUID)
    --   - Shadow Priest      (specID = 258, class = PRIEST)
    --   - Brewmaster Monk    (specID = 268, class = MONK)
    --   - Elemental Shaman   (specID = 262, class = SHAMAN)
    local function playerHasAlternatePowerBar()
        if not UnitClass or not GetSpecialization or not GetSpecializationInfo then
            return false
        end
        local _, classToken = UnitClass("player")
        if not classToken then
            return false
        end
        local specIndex = GetSpecialization()
        if not specIndex then
            return false
        end
        local specID = select(1, GetSpecializationInfo(specIndex))
        if not specID then
            return false
        end

        -- Map of class -> set of specIDs that use the global AlternatePowerBar.
        local altSpecsByClass = {
            DRUID  = { [102] = true },  -- Balance
            PRIEST = { [258] = true },  -- Shadow
            MONK   = { [268] = true },  -- Brewmaster
            SHAMAN = { [262] = true },  -- Elemental
        }

        local classSpecs = altSpecsByClass[classToken]
        return classSpecs and classSpecs[specID] or false
    end

    -- Expose for UI modules (builders.lua) to gate the Alternate Power Bar section.
    addon.UnitFrames_PlayerHasAlternatePowerBar = playerHasAlternatePowerBar

    -- Hook UpdateTextString to reapply visibility after Blizzard's updates.
    -- IMPORTANT: Use hooksecurefunc so we don't replace the method and taint
    -- secure StatusBar instances used by Blizzard (Combat Log, unit frames, etc.).
    local function hookHealthBarUpdateTextString(bar, unit)
        if not bar or bar._ScooterHealthTextVisibilityHooked then return end
        bar._ScooterHealthTextVisibilityHooked = true
        if _G.hooksecurefunc then
            _G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
                if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then
                    addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
                end
            end)
        end
    end

    -- Hook SetFontObject on a FontString to reapply full text styling when Blizzard resets fonts.
    -- This is critical for instance loading where Blizzard's UpdateTextStringWithValues or similar
    -- resets the font to default via SetFontObject().
    local function hookHealthTextFontReset(fs, unit, textType)
        if not fs or fs._ScooterHealthTextFontResetHooked then return end
        fs._ScooterHealthTextFontResetHooked = true
        if _G.hooksecurefunc then
            -- Hook SetFontObject - called by Blizzard when resetting fonts
            _G.hooksecurefunc(fs, "SetFontObject", function(self, ...)
                -- Defer reapply to avoid conflicts with Blizzard's ongoing update
                if not self._ScooterHealthTextFontReapplyDeferred then
                    self._ScooterHealthTextFontReapplyDeferred = true
                    C_Timer.After(0, function()
                        self._ScooterHealthTextFontReapplyDeferred = nil
                        -- Reapply full text styling (font + visibility) for this unit
                        if addon and addon.ApplyAllUnitFrameHealthTextVisibility then
                            addon.ApplyAllUnitFrameHealthTextVisibility()
                        end
                    end)
                end
            end)
        end
    end

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]
        local frame = getUnitFrameFor(unit)
        if not frame then return end
        
        -- Resolve health bar and hook its UpdateTextString if not already hooked
        local hb = resolveHealthBarForVisibility(frame, unit)
        if hb then
            hookHealthBarUpdateTextString(hb, unit)
        end
        
		local leftFS
		local rightFS
		if unit == "Pet" then
			leftFS = _G.PetFrameHealthBarTextLeft or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
			rightFS = _G.PetFrameHealthBarTextRight or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
		end
        -- Full resolution path (may scan children/regions). This should only run during
        -- explicit styling passes (ApplyStyles), not on every health text update.
		leftFS = leftFS
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
            or findFontStringByNameHint(frame, "HealthBarsContainer.LeftText")
            or findFontStringByNameHint(frame, ".LeftText")
            or findFontStringByNameHint(frame, "HealthBarTextLeft")
		rightFS = rightFS
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
            or findFontStringByNameHint(frame, "HealthBarsContainer.RightText")
            or findFontStringByNameHint(frame, ".RightText")
            or findFontStringByNameHint(frame, "HealthBarTextRight")

        -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
        addon._ufHealthTextFonts[unit] = {
            leftFS = leftFS,
            rightFS = rightFS,
        }

        -- Install font reset hooks to reapply styling when Blizzard calls SetFontObject
        hookHealthTextFontReset(leftFS, unit, "left")
        hookHealthTextFontReset(rightFS, unit, "right")

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
        local function applyHealthTextVisibility(fs, hidden)
            if not fs then return end
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fs._ScooterHealthTextVisibilityHooked then
                    fs._ScooterHealthTextVisibilityHooked = true
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            if self._ScooterHealthTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            if self._ScooterHealthTextHidden and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not self._ScooterHealthTextAlphaDeferred then
                                    self._ScooterHealthTextAlphaDeferred = true
                                    C_Timer.After(0, function()
                                        self._ScooterHealthTextAlphaDeferred = nil
                                        if self._ScooterHealthTextHidden and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            if self._ScooterHealthTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fs._ScooterHealthTextHidden = true
            else
                fs._ScooterHealthTextHidden = false
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Apply current visibility once as part of the styling pass.
        applyHealthTextVisibility(leftFS, cfg.healthPercentHidden == true)
        applyHealthTextVisibility(rightFS, cfg.healthValueHidden == true)

        -- Apply styling (font/size/style/color/offset) with stable baseline anchoring
        addon._ufTextBaselines = addon._ufTextBaselines or {}
        local function ensureBaseline(fs, key)
            addon._ufTextBaselines[key] = addon._ufTextBaselines[key] or {}
            local b = addon._ufTextBaselines[key]
            if b.point == nil then
                if fs and fs.GetPoint then
                    local p, relTo, rp, x, y = fs:GetPoint(1)
                    b.point = p or "CENTER"
                    b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
                    b.relPoint = rp or b.point
                    b.x = tonumber(x) or 0
                    b.y = tonumber(y) or 0
                else
                    b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
                end
            end
            return b
        end

        -- Helper to force FontString redraw after alignment change
        local function forceTextRedraw(fs)
            if fs and fs.GetText and fs.SetText then
                local txt = fs:GetText()
                if txt then
                    fs:SetText("")
                    fs:SetText(txt)
                end
            end
        end

        local function applyTextStyle(fs, styleCfg, baselineKey)
            if not fs or not styleCfg then return end
            local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
            local size = tonumber(styleCfg.size) or 14
            local outline = tostring(styleCfg.style or "OUTLINE")
            if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
            local c = styleCfg.color or {1,1,1,1}
            if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

            -- Determine default alignment based on whether this is left (%) or right (value) text
            local defaultAlign = "LEFT"
            if baselineKey and baselineKey:find(":right") then
                defaultAlign = "RIGHT"
            end
            local alignment = styleCfg.alignment or defaultAlign

            -- Set explicit width on FontString to enable alignment (use full parent bar width)
            local parentBar = fs:GetParent()
            if parentBar and parentBar.GetWidth then
                local barWidth = parentBar:GetWidth()
                if barWidth and barWidth > 0 then
                    -- Use full bar width so alignment spans the entire bar
                    if fs.SetWidth then
                        pcall(fs.SetWidth, fs, barWidth)
                    end
                end
            end

            -- Apply text alignment
            if fs.SetJustifyH then
                pcall(fs.SetJustifyH, fs, alignment)
            end

            -- Offset relative to a stable baseline anchor captured at first apply this session
            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
            if fs.ClearAllPoints and fs.SetPoint then
                local b = ensureBaseline(fs, baselineKey)
                fs:ClearAllPoints()
                fs:SetPoint(b.point or "CENTER", b.relTo or (fs.GetParent and fs:GetParent()) or frame, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
            end

            -- Force redraw to apply alignment visually
            forceTextRedraw(fs)
        end

        if leftFS then applyTextStyle(leftFS, cfg.textHealthPercent or {}, unit .. ":left") end
        if rightFS then applyTextStyle(rightFS, cfg.textHealthValue or {}, unit .. ":right") end
    end

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    -- Uses SetAlpha instead of SetShown to avoid taint during combat.
    function addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]

        local cache = addon._ufHealthTextFonts and addon._ufHealthTextFonts[unit]
        if not cache then
            -- If we haven't resolved fonts yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown.
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
        local function applyVisibility(fs, hidden)
            if not fs then return end
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fs._ScooterHealthTextVisibilityHooked then
                    fs._ScooterHealthTextVisibilityHooked = true
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            if self._ScooterHealthTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            if self._ScooterHealthTextHidden and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not self._ScooterHealthTextAlphaDeferred then
                                    self._ScooterHealthTextAlphaDeferred = true
                                    C_Timer.After(0, function()
                                        self._ScooterHealthTextAlphaDeferred = nil
                                        if self._ScooterHealthTextHidden and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            if self._ScooterHealthTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fs._ScooterHealthTextHidden = true
            else
                fs._ScooterHealthTextHidden = false
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        applyVisibility(leftFS, cfg.healthPercentHidden == true)
        applyVisibility(rightFS, cfg.healthValueHidden == true)
    end

	function addon.ApplyAllUnitFrameHealthTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
	end

    -- Copy addon-only Unit Frame text settings from source unit to destination unit
    function addon.CopyUnitFrameTextSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]
        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end
        local keys = {
            "healthPercentHidden",
            "healthValueHidden",
            "textHealthPercent",
            "textHealthValue",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(destUnit) end
        return true
    end
end

	-- Unit Frames: Toggle Power % (LeftText when present) and Value (RightText) visibility per unit
do
    -- Cache for resolved power text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufPowerTextFonts = addon._ufPowerTextFonts or {}

	local function getUnitFrameFor(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if EM then
			idx = (unit == "Player" and EM.Player)
				or (unit == "Target" and EM.Target)
				or (unit == "Focus" and EM.Focus)
				or (unit == "Pet" and EM.Pet)
		end
		if idx then
			return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
		end
		if unit == "Pet" then return _G.PetFrame end
		return nil
	end

	local function findFontStringByNameHint(root, hint)
		if not root then return nil end
		local target
		local function scan(obj)
			if not obj or target then return end
			if obj.GetObjectType and obj:GetObjectType() == "FontString" then
				local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
				if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
					target = obj; return
				end
			end
			if obj.GetRegions then
				local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
				for i = 1, n do
					local r = select(i, obj:GetRegions())
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
						if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
							target = r; return
						end
					end
				end
			end
			if obj.GetChildren then
				local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
				for i = 1, m do
					local c = select(i, obj:GetChildren())
					scan(c)
					if target then return end
				end
			end
		end
		scan(root)
		return target
	end

	-- Resolve the content main frame for anchoring name backdrop
	local function resolveUFContentMain_NLT(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
		return nil
	end

	-- Resolve the Health Bar status bar for anchoring name backdrop
	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
		return nil
	end

	-- Resolve power bar for this unit
	local function resolvePowerBarForVisibility(frame, unit)
		if unit == "Pet" then return _G.PetFrameManaBar end
		if frame and frame.ManaBar then return frame.ManaBar end
		-- Try direct paths
		if unit == "Player" then
			local root = _G.PlayerFrame
			if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar then
				return root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
			end
		elseif unit == "Target" then
			local root = _G.TargetFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		end
		return nil
	end

	-- Hook UpdateTextString to reapply visibility after Blizzard's updates.
	-- Use hooksecurefunc so we don't replace the method and taint secure StatusBars.
	local function hookPowerBarUpdateTextString(bar, unit)
		if not bar or bar._ScooterPowerTextVisibilityHooked then return end
		bar._ScooterPowerTextVisibilityHooked = true
		if _G.hooksecurefunc then
			_G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
				if addon and addon.ApplyUnitFramePowerTextVisibilityFor then
					addon.ApplyUnitFramePowerTextVisibilityFor(unit)
				end
			end)
		end
	end

	-- Hook SetFontObject on a FontString to reapply full text styling when Blizzard resets fonts.
	-- This is critical for instance loading where Blizzard resets fonts via SetFontObject().
	local function hookPowerTextFontReset(fs, unit, textType)
		if not fs or fs._ScooterPowerTextFontResetHooked then return end
		fs._ScooterPowerTextFontResetHooked = true
		if _G.hooksecurefunc then
			_G.hooksecurefunc(fs, "SetFontObject", function(self, ...)
				-- Defer reapply to avoid conflicts with Blizzard's ongoing update
				if not self._ScooterPowerTextFontReapplyDeferred then
					self._ScooterPowerTextFontReapplyDeferred = true
					C_Timer.After(0, function()
						self._ScooterPowerTextFontReapplyDeferred = nil
						-- Reapply full text styling (font + visibility) for this unit
						if addon and addon.ApplyAllUnitFramePowerTextVisibility then
							addon.ApplyAllUnitFramePowerTextVisibility()
						end
					end)
				end
			end)
		end
	end

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		local cfg = db.unitFrames[unit]
		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve power bar and hook its UpdateTextString if not already hooked
		local pb = resolvePowerBarForVisibility(frame, unit)
		if pb then
			hookPowerBarUpdateTextString(pb, unit)
		end

		-- Attempt to resolve power bar text regions
		local leftFS
		local rightFS
		if unit == "Pet" then
			-- Pet uses standalone globals more often
			leftFS = _G.PetFrameManaBarTextLeft
			rightFS = _G.PetFrameManaBarTextRight
		end

        -- Full resolution path (may scan children/regions). This should only run during
        -- explicit styling passes (ApplyStyles), not on every power text update.
		leftFS = leftFS
			or (frame.ManaBar and frame.ManaBar.LeftText)
			or findFontStringByNameHint(frame, "ManaBar.LeftText")
			or findFontStringByNameHint(frame, ".LeftText")
			or findFontStringByNameHint(frame, "ManaBarTextLeft")
		rightFS = rightFS
			or (frame.ManaBar and frame.ManaBar.RightText)
			or findFontStringByNameHint(frame, "ManaBar.RightText")
			or findFontStringByNameHint(frame, ".RightText")
			or findFontStringByNameHint(frame, "ManaBarTextRight")

        -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
        addon._ufPowerTextFonts[unit] = {
            leftFS = leftFS,
            rightFS = rightFS,
        }

        -- Install font reset hooks to reapply styling when Blizzard calls SetFontObject
        hookPowerTextFontReset(leftFS, unit, "left")
        hookPowerTextFontReset(rightFS, unit, "right")

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
        local function applyPowerTextVisibility(fs, hidden)
            if not fs then return end
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fs._ScooterPowerTextVisibilityHooked then
                    fs._ScooterPowerTextVisibilityHooked = true
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            if self._ScooterPowerTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            if self._ScooterPowerTextHidden and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not self._ScooterPowerTextAlphaDeferred then
                                    self._ScooterPowerTextAlphaDeferred = true
                                    C_Timer.After(0, function()
                                        self._ScooterPowerTextAlphaDeferred = nil
                                        if self._ScooterPowerTextHidden and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        -- This catches code paths that don't go through UpdateTextString (e.g. target changes out of combat)
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            if self._ScooterPowerTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fs._ScooterPowerTextHidden = true
            else
                fs._ScooterPowerTextHidden = false
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

		-- Visibility: tolerate missing LeftText on some classes/specs (no-op)
		-- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
		local powerBarHidden = (cfg.powerBarHidden == true)
		applyPowerTextVisibility(leftFS, powerBarHidden or (cfg.powerPercentHidden == true))
		applyPowerTextVisibility(rightFS, powerBarHidden or (cfg.powerValueHidden == true))

		-- Styling
		addon._ufPowerTextBaselines = addon._ufPowerTextBaselines or {}
		local function ensureBaseline(fs, key)
			addon._ufPowerTextBaselines[key] = addon._ufPowerTextBaselines[key] or {}
			local b = addon._ufPowerTextBaselines[key]
			if b.point == nil then
				if fs and fs.GetPoint then
					local p, relTo, rp, x, y = fs:GetPoint(1)
					b.point = p or "CENTER"
					b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
					b.relPoint = rp or b.point
					b.x = tonumber(x) or 0
					b.y = tonumber(y) or 0
				else
					b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
				end
			end
			return b
		end

		-- Helper to force FontString redraw after alignment change
		local function forceTextRedraw(fs)
			if fs and fs.GetText and fs.SetText then
				local txt = fs:GetText()
				if txt then
					fs:SetText("")
					fs:SetText(txt)
				end
			end
		end

		local function applyTextStyle(fs, styleCfg, baselineKey)
			if not fs or not styleCfg then return end
			local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
			local size = tonumber(styleCfg.size) or 14
			local outline = tostring(styleCfg.style or "OUTLINE")
			if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
			local c = styleCfg.color or {1,1,1,1}
			if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

			-- Determine default alignment based on whether this is left (%) or right (value) text
			local defaultAlign = "LEFT"
			if baselineKey and baselineKey:find("%-right") then
				defaultAlign = "RIGHT"
			end
			local alignment = styleCfg.alignment or defaultAlign

			-- Set explicit width on FontString to enable alignment (use full parent bar width)
			local parentBar = fs:GetParent()
			if parentBar and parentBar.GetWidth then
				local barWidth = parentBar:GetWidth()
				if barWidth and barWidth > 0 then
					-- Use full bar width so alignment spans the entire bar
					if fs.SetWidth then
						pcall(fs.SetWidth, fs, barWidth)
					end
				end
			end

			-- Apply text alignment
			if fs.SetJustifyH then
				pcall(fs.SetJustifyH, fs, alignment)
			end

			local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
			if fs.ClearAllPoints and fs.SetPoint then
				local b = ensureBaseline(fs, baselineKey)
				fs:ClearAllPoints()
				fs:SetPoint(b.point or "CENTER", b.relTo or (fs.GetParent and fs:GetParent()) or frame, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
			end

			-- Force redraw to apply alignment visually
			forceTextRedraw(fs)
		end

		if leftFS then applyTextStyle(leftFS, cfg.textPowerPercent or {}, unit .. ":power-left") end
		if rightFS then applyTextStyle(rightFS, cfg.textPowerValue or {}, unit .. ":power-right") end
	end

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    -- Uses SetAlpha instead of SetShown to avoid taint during combat.
	function addon.ApplyUnitFramePowerTextVisibilityFor(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        db.unitFrames = db.unitFrames or {}
        db.unitFrames[unit] = db.unitFrames[unit] or {}
        local cfg = db.unitFrames[unit]

        local cache = addon._ufPowerTextFonts and addon._ufPowerTextFonts[unit]
        if not cache then
            -- If we haven't resolved fonts yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown.
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
        local function applyVisibility(fs, hidden)
            if not fs then return end
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fs._ScooterPowerTextVisibilityHooked then
                    fs._ScooterPowerTextVisibilityHooked = true
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            if self._ScooterPowerTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            if self._ScooterPowerTextHidden and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not self._ScooterPowerTextAlphaDeferred then
                                    self._ScooterPowerTextAlphaDeferred = true
                                    C_Timer.After(0, function()
                                        self._ScooterPowerTextAlphaDeferred = nil
                                        if self._ScooterPowerTextHidden and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            if self._ScooterPowerTextHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fs._ScooterPowerTextHidden = true
            else
                fs._ScooterPowerTextHidden = false
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Visibility: tolerate missing LeftText on some classes/specs (no-op)
        -- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
		local powerBarHidden = (cfg.powerBarHidden == true)
        applyVisibility(leftFS, powerBarHidden or (cfg.powerPercentHidden == true))
        applyVisibility(rightFS, powerBarHidden or (cfg.powerValueHidden == true))
	end

	function addon.ApplyAllUnitFramePowerTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
	end

	-- Optional helper mirroring health text settings copy (no-op if missing)
	function addon.CopyUnitFramePowerTextSettings(sourceUnit, destUnit)
		local db = addon and addon.db and addon.db.profile
		if not db then return false end
		db.unitFrames = db.unitFrames or {}
		local src = db.unitFrames[sourceUnit]
		if not src then return false end
		db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
		local dst = db.unitFrames[destUnit]
		local function deepcopy(v)
			if type(v) ~= "table" then return v end
			local out = {}
			for k, vv in pairs(v) do out[k] = deepcopy(vv) end
			return out
		end
		local keys = {
			"powerPercentHidden",
			"powerValueHidden",
			"textPowerPercent",
			"textPowerValue",
		}
		for _, k in ipairs(keys) do
			if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
		end
		if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(destUnit) end
		return true
	end
end

--- Unit Frames: Apply Name & Level Text styling (visibility, font, size, style, color, offset)
do
	local function getUnitFrameFor(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if unit == "Player" then idx = EM.Player
		elseif unit == "Target" then idx = EM.Target
		elseif unit == "Focus" then idx = EM.Focus
		elseif unit == "Pet" then idx = EM.Pet
		end
		if not idx then return nil end
		return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
	end

	-- Local resolvers for this block (backdrop anchoring helpers)
	local function resolveUFContentMain_NLT(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
		return nil
	end

	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
		return nil
	end

	local function findFontStringByNameHint(root, hint)
		if not (root and hint) then return nil end
		local target = nil
		local function scan(obj)
			if not obj then return end
			if target then return end
			if obj.IsObjectType and obj:IsObjectType("FontString") then
				local nm = obj.GetName and obj:GetName() or ""
				if type(nm) == "string" and string.find(nm, hint, 1, true) then
					target = obj
					return
				end
			end
			if obj.GetChildren then
				local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
				for i = 1, m do
					local c = select(i, obj:GetChildren())
					scan(c)
					if target then return end
				end
			end
		end
		scan(root)
		return target
	end

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		local cfg = db.unitFrames[unit]
		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve Name and Level FontStrings
		local nameFS, levelFS
		
	-- Try direct child access first (most common)
	if unit == "Player" then
		nameFS = _G.PlayerName
		levelFS = _G.PlayerLevelText
	elseif unit == "Target" then
		-- Target uses nested content structure
		local targetFrame = _G.TargetFrame
		if targetFrame and targetFrame.TargetFrameContent and targetFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = targetFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = targetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Focus" then
		-- Focus reuses Target's content structure naming (TargetFrameContent, not FocusFrameContent!)
		local focusFrame = _G.FocusFrame
		if focusFrame and focusFrame.TargetFrameContent and focusFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = focusFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = focusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Pet" then
		-- Pet uses global FontString names (PetName is a direct global, not nested)
		nameFS = _G.PetName
		-- Pet frame doesn't have a LevelText FontString (no level display)
		levelFS = nil
	end

		-- Fallback: search by name hints
		if not nameFS then nameFS = findFontStringByNameHint(frame, "Name") end
		if not levelFS then levelFS = findFontStringByNameHint(frame, "LevelText") end

		-- Apply visibility using SetShown (Name/Level text are NOT StatusBar children,
		-- so they don't have the taint issue that Health/Power bar text has)
		if nameFS and nameFS.SetShown then pcall(nameFS.SetShown, nameFS, not cfg.nameTextHidden) end
		if levelFS and levelFS.SetShown then pcall(levelFS.SetShown, levelFS, not cfg.levelTextHidden) end

		-- Apply styling
		addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
		local function ensureBaseline(fs, key)
			addon._ufNameLevelTextBaselines[key] = addon._ufNameLevelTextBaselines[key] or {}
			local b = addon._ufNameLevelTextBaselines[key]
			if b.point == nil then
				if fs and fs.GetPoint then
					local p, relTo, rp, x, y = fs:GetPoint(1)
					b.point = p or "CENTER"
					b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
					b.relPoint = rp or b.point
					b.x = tonumber(x) or 0
					b.y = tonumber(y) or 0
				else
					b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
				end
			end
			return b
		end

		-- Optional: widen the name container for Target/Focus to reduce truncation.
		-- This adjusts the Name FontString's width and anchor so the right edge
		-- stays aligned relative to the ReputationColor strip while growing left.
		-- NOTE: This function MUST incorporate the configured offset values because it
		-- runs AFTER applyTextStyle() and overwrites the position set there.
		addon._ufNameContainerBaselines = addon._ufNameContainerBaselines or {}
		local function applyNameContainerWidth(unitKey, nameFSLocal)
			if not nameFSLocal then return end
			-- Only Target/Focus currently support this control; Player/Pet keep stock behavior.
			if unitKey ~= "Target" and unitKey ~= "Focus" then return end

			local unitCfg = db.unitFrames[unitKey] or {}
			local styleCfg = unitCfg.textName or {}
			local pct = tonumber(styleCfg.containerWidthPct) or 100

			-- Clamp slider semantics to [80,150] (matches UI slider).
			if pct < 80 then pct = 80 elseif pct > 150 then pct = 150 end

			-- Read configured offset values (same as applyTextStyle uses)
			local configOffsetX = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local configOffsetY = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0

			local key = unitKey .. ":nameContainer"
			local baseline = addon._ufNameContainerBaselines[key]
			if not baseline then
				baseline = {}
				baseline.width = nameFSLocal.GetWidth and nameFSLocal:GetWidth() or 90
				if nameFSLocal.GetPoint then
					local p, relTo, rp, x, y = nameFSLocal:GetPoint(1)
					baseline.point = p or "TOPLEFT"
					baseline.relTo = relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame
					baseline.relPoint = rp or baseline.point
					baseline.x = tonumber(x) or 0
					baseline.y = tonumber(y) or 0
				else
					baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y =
						"TOPLEFT", (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame, "TOPLEFT", 0, 0
				end
				addon._ufNameContainerBaselines[key] = baseline
			end

			-- Read configured alignment (Target/Focus only)
			local alignment = styleCfg.alignment or "LEFT"

			-- Helper to force FontString redraw after alignment change
			local function forceTextRedraw(fs)
				if fs and fs.GetText and fs.SetText then
					local txt = fs:GetText()
					if txt then
						fs:SetText("")
						fs:SetText(txt)
					end
				end
			end

			-- When at 100%, restore original width/anchor (with offset) and bail.
			if pct == 100 then
				if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint and baseline.width then
					nameFSLocal:SetWidth(baseline.width)
					-- Apply text alignment within the container
					if nameFSLocal.SetJustifyH then
						pcall(nameFSLocal.SetJustifyH, nameFSLocal, alignment)
					end
					nameFSLocal:ClearAllPoints()
					nameFSLocal:SetPoint(
						baseline.point or "TOPLEFT",
						baseline.relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
						baseline.relPoint or baseline.point or "TOPLEFT",
						(baseline.x or 0) + configOffsetX,
						(baseline.y or 0) + configOffsetY
					)
					-- Force redraw to apply alignment visually
					forceTextRedraw(nameFSLocal)
				end
				return
			end

			local baseWidth = baseline.width or (nameFSLocal.GetWidth and nameFSLocal:GetWidth()) or 90
			local newWidth = math.floor((baseWidth * pct / 100) + 0.5)

			-- Default behavior: scale the width and preserve left anchor.
			local point, relTo, relPoint, xOff, yOff =
				baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y

			-- If we can find the canonical ReputationColor strip, keep right margin stable
			-- by nudging the TOPLEFT X offset leftwards as width grows.
			local main = resolveUFContentMain_NLT(unitKey)
			local rep = main and main.ReputationColor or nil
			if rep and relTo == rep and (point == "TOPLEFT" or point == "LEFT") then
				-- Right edge offset remains unchanged; only the left edge moves.
				local delta = newWidth - baseWidth
				xOff = (xOff or 0) - delta
			end

			if nameFSLocal.SetWidth then
				nameFSLocal:SetWidth(newWidth)
			end
			-- Apply text alignment within the container
			if nameFSLocal.SetJustifyH then
				pcall(nameFSLocal.SetJustifyH, nameFSLocal, alignment)
			end
			if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint then
				nameFSLocal:ClearAllPoints()
				nameFSLocal:SetPoint(
					point or "TOPLEFT",
					relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
					relPoint or point or "TOPLEFT",
					(xOff or 0) + configOffsetX,
					(yOff or 0) + configOffsetY
				)
			end
			-- Force redraw to apply alignment visually
			forceTextRedraw(nameFSLocal)
		end

	local function applyTextStyle(fs, styleCfg, baselineKey)
		if not fs or not styleCfg then return end
		local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
		local size = tonumber(styleCfg.size) or 14
		local outline = tostring(styleCfg.style or "OUTLINE")
		if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
		-- Determine color based on colorMode
		local c = nil
		local colorMode = styleCfg.colorMode or "default"
		if colorMode == "class" then
			-- Class Color: use player's class color
			if addon.GetClassColorRGB then
				local unitForClass = unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet"))
				local cr, cg, cb = addon.GetClassColorRGB(unitForClass)
				c = { cr or 1, cg or 1, cb or 1, 1 }
			else
				c = {1.0, 0.82, 0.0, 1} -- fallback to default yellow
			end
		elseif colorMode == "custom" then
			-- Custom: use stored color
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		else
			-- Default: use Blizzard's default yellow color (1.0, 0.82, 0.0) instead of white
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		end
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
		local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
		local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
		if fs.ClearAllPoints and fs.SetPoint then
			local b = ensureBaseline(fs, baselineKey)
			fs:ClearAllPoints()
			fs:SetPoint(b.point or "CENTER", b.relTo or (fs.GetParent and fs:GetParent()) or frame, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
		end
	end

	if nameFS then
		applyTextStyle(nameFS, cfg.textName or {}, unit .. ":name")
		-- Apply optional name container width adjustment (Target/Focus only).
		applyNameContainerWidth(unit, nameFS)
	end
	if levelFS then 
		applyTextStyle(levelFS, cfg.textLevel or {}, unit .. ":level")
		
		-- For Player level text, Blizzard uses SetVertexColor (not SetTextColor!) which requires special handling
		-- Blizzard constantly resets the level color, so we use hooksecurefunc to re-apply our custom color
		-- CRITICAL: We use hooksecurefunc instead of method override to avoid taint. Method overrides
		-- cause taint that spreads through the execution context, blocking protected functions
		-- like SetTargetClampingInsets() during nameplate setup. See DEBUG.md for details.
		if unit == "Player" and levelFS then
			-- Install hook once (hooksecurefunc runs AFTER Blizzard's SetVertexColor)
			if not levelFS._scooterVertexColorHooked then
				levelFS._scooterVertexColorHooked = true
				
				hooksecurefunc(levelFS, "SetVertexColor", function(self, r, g, b, a)
					-- Guard against recursion since we call SetVertexColor inside the hook
					if self._scooterApplyingVertexColor then return end
					
					-- Check if we have a custom color configured
					local db = addon and addon.db and addon.db.profile
					if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.textLevel and db.unitFrames.Player.textLevel.color then
						local c = db.unitFrames.Player.textLevel.color
						-- Re-apply our custom color (overrides what Blizzard just set)
						self._scooterApplyingVertexColor = true
						pcall(self.SetVertexColor, self, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						self._scooterApplyingVertexColor = nil
					end
					-- If no custom color configured, Blizzard's color remains (hook does nothing)
				end)
			end
			
			-- Apply our color immediately if configured
			if cfg.textLevel and cfg.textLevel.color then
				local c = cfg.textLevel.color
				levelFS._scooterApplyingVertexColor = true
				pcall(levelFS.SetVertexColor, levelFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
				levelFS._scooterApplyingVertexColor = nil
			end
		end
	end
		-- Name Backdrop: texture strip anchored to top edge of the Health Bar at the lowest z-order
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local cfg = db.unitFrames[unit] or {}
			local texKey = cfg.nameBackdropTexture or ""
			-- Default to disabled backdrop unless explicitly enabled in the profile.
			local enabledBackdrop = not not cfg.nameBackdropEnabled
			local colorMode = cfg.nameBackdropColorMode or "default" -- default | texture | custom
			local tint = cfg.nameBackdropTint or {1,1,1,1}
			local opacity = tonumber(cfg.nameBackdropOpacity) or 50
			if opacity < 0 then opacity = 0 elseif opacity > 100 then opacity = 100 end
			local opacityAlpha = opacity / 100
			local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
			local holderKey = "ScooterNameBackdrop_" .. tostring(unit)
			local tex = main and main[holderKey] or nil
			if main and not tex then
				tex = main:CreateTexture(nil, "BACKGROUND", nil, -8)
				main[holderKey] = tex
			end
			if tex then
				if hb and resolvedPath and enabledBackdrop then
					-- Compute a baseline width and apply user width percentage independently of Health Bar width
					local base = tonumber(cfg.nameBackdropBaseWidth)
				if not base or base <= 0 then
					local hbw = (hb.GetWidth and hb:GetWidth()) or 0
					base = hbw
					-- Persist baseline for stability across live changes
					cfg.nameBackdropBaseWidth = base
				end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
					tex:ClearAllPoints()
					-- Anchor to RIGHT edge for Target/Focus so the strip grows left from the portrait side
					if unit == "Target" or unit == "Focus" then
						tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					else
						tex:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
					end
					tex:SetSize(desiredWidth, 16)
					tex:SetTexture(resolvedPath)
					if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
					if tex.SetHorizTile then tex:SetHorizTile(false) end
					if tex.SetVertTile then tex:SetVertTile(false) end
					if tex.SetTexCoord then tex:SetTexCoord(0,1,0,1) end
					-- Color behavior mirrors bar backgrounds:
					--  - texture  => preserve original colors (white vertex)
					--  - default  => use default background color (black)
					--  - custom   => use tint (including alpha)
					do
						local r, g, b = 1, 1, 1
						if colorMode == "texture" then
							r, g, b = 1, 1, 1
						elseif colorMode == "default" then
							-- Unit frame default background is black
							r, g, b = 0, 0, 0
						elseif colorMode == "custom" and type(tint) == "table" then
							r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
						end
						if tex.SetVertexColor then tex:SetVertexColor(r, g, b, 1) end
						if tex.SetAlpha then tex:SetAlpha(opacityAlpha) end
					end
					tex:Show()
				else
					tex:Hide()
				end
			end
		end
		-- Name Backdrop Border: draw a border around the same region
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local cfg = db.unitFrames[unit] or {}
			local styleKey = cfg.nameBackdropBorderStyle or "square"
			-- Align border gating with UI defaults: disabled until explicitly enabled.
			local localEnabled = not not cfg.nameBackdropBorderEnabled
			local globalEnabled = not not cfg.useCustomBorders
			local useBorders = localEnabled and globalEnabled
			local thickness = tonumber(cfg.nameBackdropBorderThickness) or 1
			if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
			local inset = tonumber(cfg.nameBackdropBorderInset) or 0
			if inset < -8 then inset = -8 elseif inset > 8 then inset = 8 end
			local tintEnabled = not not cfg.nameBackdropBorderTintEnable
			local tintColor = cfg.nameBackdropBorderTintColor or {1,1,1,1}

			local borderKey = "ScooterNameBackdropBorder_" .. tostring(unit)
			local borderFrame = main and main[borderKey] or nil
			if main and not borderFrame then
				local template = BackdropTemplateMixin and "BackdropTemplate" or nil
				borderFrame = CreateFrame("Frame", nil, main, template)
				main[borderKey] = borderFrame
			end
			if borderFrame and hb and useBorders then
				-- Match border width to the same baseline-derived width as backdrop
				local base = tonumber(cfg.nameBackdropBaseWidth)
				if not base or base <= 0 then
					local hbw = (hb.GetWidth and hb:GetWidth()) or 0
					base = hbw
					cfg.nameBackdropBaseWidth = base
				end
				local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
				if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
				local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
				borderFrame:ClearAllPoints()
				-- Anchor to RIGHT edge for Target/Focus so the border grows left from the portrait side
				if unit == "Target" or unit == "Focus" then
					borderFrame:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
				else
					borderFrame:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
				end
				borderFrame:SetSize(desiredWidth, 16)
				local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey) or nil
				local styleTexture = styleDef and styleDef.texture or nil
				local thicknessScale = (styleDef and styleDef.thicknessScale) or 1.0
				local DEFAULT_REF = 18
				local DEFAULT_MULT = 1.35
				local h = (borderFrame.GetHeight and borderFrame:GetHeight()) or 16
				if h < 1 then h = DEFAULT_REF end
				local edgeSize = math.floor((thickness * DEFAULT_MULT * thicknessScale * (h / DEFAULT_REF)) + 0.5)
				if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 48 then edgeSize = 48 end

				if styleKey == "square" or not styleTexture then
					-- Clear any previous backdrop-based border before applying square edges
					if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					if addon.Borders and addon.Borders.ApplySquare then
						addon.Borders.ApplySquare(borderFrame, {
							size = edgeSize,
							color = tintEnabled and (tintColor or {1,1,1,1}) or {1,1,1,1},
							layer = "OVERLAY",
							layerSublevel = 7,
							expand = -(inset),
						})
					end
					borderFrame:Show()
				else
					-- Clear any previous square edges before applying a backdrop-based border
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					local ok = false
					if borderFrame.SetBackdrop then
						local insetPx = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + (tonumber(inset) or 0))
						local bd = {
							bgFile = nil,
							edgeFile = styleTexture,
							tile = false,
							edgeSize = edgeSize,
							insets = { left = insetPx, right = insetPx, top = insetPx, bottom = insetPx },
						}
						ok = pcall(borderFrame.SetBackdrop, borderFrame, bd)
					end
					if ok and borderFrame.SetBackdropBorderColor then
						local c = tintEnabled and tintColor or {1,1,1,1}
						borderFrame:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
					end
					if not ok then
						borderFrame:Hide()
					else
						borderFrame:Show()
					end
				end
			elseif borderFrame then
				-- Fully clear both border types on disable
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
				if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
				borderFrame:Hide()
			end
		end
	end

	function addon.ApplyUnitFrameNameLevelTextFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFrameNameLevelText()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
	end

	-- Hook TargetFrame_Update, FocusFrame_Update, and Player frame update functions
	-- to reapply name/level text styling (including visibility and alignment) after
	-- Blizzard's updates reset properties.
	-- Use hooksecurefunc to avoid taint; defer reapply by one frame to ensure
	-- Blizzard's update has fully completed.
	local _nameLevelTextHooksInstalled = false
	local function installNameLevelTextHooks()
		if _nameLevelTextHooksInstalled then return end
		_nameLevelTextHooksInstalled = true

		-- Player frame hooks: PlayerFrame_Update and PlayerFrame_UpdateRolesAssigned
		-- can reset level text visibility. Hook both to ensure our settings persist.
		if _G.hooksecurefunc then
			-- PlayerFrame_Update calls PlayerFrame_UpdateLevel which sets the level text
			if type(_G.PlayerFrame_Update) == "function" then
				_G.hooksecurefunc("PlayerFrame_Update", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							if addon.ApplyUnitFrameNameLevelTextFor then
								addon.ApplyUnitFrameNameLevelTextFor("Player")
							end
						end)
					end
				end)
			end
			
			-- PlayerFrame_UpdateRolesAssigned directly sets PlayerLevelText:SetShown()
			if type(_G.PlayerFrame_UpdateRolesAssigned) == "function" then
				_G.hooksecurefunc("PlayerFrame_UpdateRolesAssigned", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							if addon.ApplyUnitFrameNameLevelTextFor then
								addon.ApplyUnitFrameNameLevelTextFor("Player")
							end
						end)
					end
				end)
			end
			
			-- PlayerFrame_ToPlayerArt is called when switching from vehicle to player
			if type(_G.PlayerFrame_ToPlayerArt) == "function" then
				_G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							if addon.ApplyUnitFrameNameLevelTextFor then
								addon.ApplyUnitFrameNameLevelTextFor("Player")
							end
						end)
					end
				end)
			end
		end

		if _G.hooksecurefunc and type(_G.TargetFrame_Update) == "function" then
			_G.hooksecurefunc("TargetFrame_Update", function()
				if _G.C_Timer and _G.C_Timer.After then
					_G.C_Timer.After(0, function()
						if addon.ApplyUnitFrameNameLevelTextFor then
							addon.ApplyUnitFrameNameLevelTextFor("Target")
						end
					end)
				end
			end)
		end

		if _G.hooksecurefunc and type(_G.FocusFrame_Update) == "function" then
			_G.hooksecurefunc("FocusFrame_Update", function()
				if _G.C_Timer and _G.C_Timer.After then
					_G.C_Timer.After(0, function()
						if addon.ApplyUnitFrameNameLevelTextFor then
							addon.ApplyUnitFrameNameLevelTextFor("Focus")
						end
					end)
				end
			end)
		end
	end

	-- Install hooks on first style application
	local _origApplyAll = addon.ApplyAllUnitFrameNameLevelText
	addon.ApplyAllUnitFrameNameLevelText = function()
		installNameLevelTextHooks()
		_origApplyAll()
	end
end

