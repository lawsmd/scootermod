local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments

-- Unit Frames: Apply Portrait positioning (X/Y offsets)
do
	-- Resolve portrait frame for a given unit
	local function resolvePortraitFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContainer and root.PlayerFrameContainer.PlayerPortrait or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.Portrait or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.Portrait or nil
		elseif unit == "Pet" then
			return _G.PetPortrait
		elseif unit == "TargetOfTarget" then
			local tot = _G.TargetFrameToT
			return tot and tot.Portrait or nil
		end
		return nil
	end

	-- Resolve portrait mask frame for a given unit
	local function resolvePortraitMaskFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContainer and root.PlayerFrameContainer.PlayerPortraitMask or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.PortraitMask or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.PortraitMask or nil
		elseif unit == "Pet" then
			local root = _G.PetFrame
			return root and root.PortraitMask or nil
		elseif unit == "TargetOfTarget" then
			local tot = _G.TargetFrameToT
			return tot and tot.PortraitMask or nil
		end
		return nil
	end

	-- Resolve portrait corner icon frame for a given unit (Player-only)
	local function resolvePortraitCornerIconFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentContextual and root.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon or nil
		end
		-- Target/Focus/Pet don't appear to have corner icons
		return nil
	end

	-- Resolve portrait rest loop frame for a given unit (Player-only)
	local function resolvePortraitRestLoopFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentContextual and root.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop or nil
		end
		-- Target/Focus/Pet don't appear to have rest loops
		return nil
	end

	-- Resolve portrait status texture frame for a given unit (Player-only)
	local function resolvePortraitStatusTextureFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.StatusTexture or nil
		end
		-- Target/Focus/Pet don't appear to have status textures
		return nil
	end

	-- Resolve damage text (HitText) frame for a given unit (Player and Pet)
	local function resolveDamageTextFrame(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.HitIndicator and root.PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText or nil
		elseif unit == "Pet" then
			-- PetHitIndicator is directly available as a global and as PetFrame.feedbackText
			return _G.PetHitIndicator or (_G.PetFrame and _G.PetFrame.feedbackText)
		end
		-- Target/Focus don't have damage text
		return nil
	end

	-- Resolve boss portrait frame texture for a given unit (Target/Focus only)
	-- This texture appears when targeting a boss and needs to be hidden along with the portrait
	local function resolveBossPortraitFrameTexture(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.BossPortraitFrameTexture or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContainer and root.TargetFrameContainer.BossPortraitFrameTexture or nil
		end
		-- Player/Pet don't have BossPortraitFrameTexture
		return nil
	end

	-- Resolve pet attack mode texture (Pet only)
	-- This texture appears when the pet is in attack mode and needs to be hidden when custom borders are enabled
	local function resolvePetAttackModeTexture(unit)
		if unit == "Pet" then
			return _G.PetAttackModeTexture
		end
		return nil
	end

	-- Resolve pet frame flash (Pet only)
	-- This texture flashes when the pet takes damage and needs to be hidden when custom borders are enabled
	local function resolvePetFrameFlash(unit)
		if unit == "Pet" then
			return _G.PetFrameFlash
		end
		return nil
	end

	-- Store original positions (per frame, not per unit, to handle frame recreation)
	local originalPositions = {}
	-- NOTE: We do NOT capture original scales because frames may retain our applied scale across reloads.
	-- Portrait frames have no Edit Mode scale setting, so baseline is always 1.0.
	-- Store original texture coordinates (per frame, not per unit, to handle frame recreation)
	local originalTexCoords = {}
	-- Store original alpha values (per frame, not per unit, to handle frame recreation)
	local originalAlphas = {}
	-- Store original mask atlas (per frame, not per unit, to handle frame recreation)
	local originalMaskAtlas = {}

	-- Pet portrait overlays are driven by Blizzard and may re-show/recreate in combat.
	-- Keep them hidden safely via SetAlpha(0) + hooksecurefunc re-enforcement (no Hide/Show).
	local function applyStickyOverlayAlpha(texture, hidden, visibleAlpha)
		if not texture then return end
		if visibleAlpha == nil then visibleAlpha = 1.0 end

		-- Install hooks once per texture instance.
		if not texture._ScooterPetOverlayHooked and _G.hooksecurefunc then
			texture._ScooterPetOverlayHooked = true

			-- If Blizzard shows the texture, force alpha back to 0 when we want it hidden.
			_G.hooksecurefunc(texture, "Show", function(self)
				-- Avoid taint propagation: do not mutate PetFrame textures during combat.
				if InCombatLockdown and InCombatLockdown() then return end
				if not self._ScooterPetOverlayHidden then return end

				-- Enforce both frame alpha and vertex alpha, since Blizzard may drive visibility via SetVertexColor.
				if self.SetAlpha then
					pcall(self.SetAlpha, self, 0)
				end
				if self.SetVertexColor then
					-- Preserve current RGB if available; just zero vertex alpha.
					if self.GetVertexColor then
						local ok, r, g, b = pcall(self.GetVertexColor, self)
						if ok then
							pcall(self.SetVertexColor, self, r or 1, g or 1, b or 1, 0)
							return
						end
					end
					pcall(self.SetVertexColor, self, 1, 1, 1, 0)
				end
			end)

			-- If Blizzard uses SetShown(true), treat it like Show().
			if texture.SetShown then
				_G.hooksecurefunc(texture, "SetShown", function(self, shown)
					if InCombatLockdown and InCombatLockdown() then return end
					if not shown or not self._ScooterPetOverlayHidden then return end
					if self.SetAlpha then
						pcall(self.SetAlpha, self, 0)
					end
					if self.SetVertexColor then
						if self.GetVertexColor then
							local ok, r, g, b = pcall(self.GetVertexColor, self)
							if ok then
								pcall(self.SetVertexColor, self, r or 1, g or 1, b or 1, 0)
								return
							end
						end
						pcall(self.SetVertexColor, self, 1, 1, 1, 0)
					end
				end)
			end

			-- If Blizzard sets alpha > 0, schedule a correction to avoid recursion loops.
			_G.hooksecurefunc(texture, "SetAlpha", function(self, alpha)
				if InCombatLockdown and InCombatLockdown() then return end
				if self._ScooterPetOverlayHidden and alpha and alpha > 0 then
					if not self._ScooterPetOverlayAlphaDeferred then
						self._ScooterPetOverlayAlphaDeferred = true
						if _G.C_Timer and _G.C_Timer.After then
							_G.C_Timer.After(0, function()
								self._ScooterPetOverlayAlphaDeferred = nil
								if self._ScooterPetOverlayHidden and self.SetAlpha then
									pcall(self.SetAlpha, self, 0)
								end
							end)
						else
							-- Fallback: immediate is safe because alpha=0 won't re-trigger the correction path.
							self._ScooterPetOverlayAlphaDeferred = nil
							if self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end
					end
				end
			end)

			-- Blizzard often drives glow visibility via vertex alpha (SetVertexColor's 4th param),
			-- not frame alpha (SetAlpha). Example: PetAttackModeTexture pulses in PetFrame:OnUpdate.
			-- If we don't hook this, the glow can reappear despite alpha=0.
			if texture.SetVertexColor then
				_G.hooksecurefunc(texture, "SetVertexColor", function(self, r, g, b, a)
					if InCombatLockdown and InCombatLockdown() then return end
					if not self._ScooterPetOverlayHidden then
						return
					end

					-- Treat nil alpha as "visible" (Blizzard sometimes omits alpha, defaulting to 1).
					if a == 0 then
						return
					end

					-- Enforce immediately (hooksecurefunc runs *after* Blizzard's call), with a recursion guard.
					-- This prevents a one-frame flash when Blizzard pulses the vertex alpha every OnUpdate tick.
					if self._ScooterPetOverlayApplyingVertex then
						return
					end
					self._ScooterPetOverlayApplyingVertex = true
					if self.SetVertexColor then
						-- Preserve color channels, force vertex alpha to 0.
						pcall(self.SetVertexColor, self, r or 1, g or 1, b or 1, 0)
					end
					self._ScooterPetOverlayApplyingVertex = nil
				end)
			end
		end

		-- Apply current desired state immediately (and set the sticky flag).
		if InCombatLockdown and InCombatLockdown() then
			-- Out-of-combat only: avoid mutating PetFrame textures during combat.
			return
		end
		if hidden then
			texture._ScooterPetOverlayHidden = true
			if texture.SetAlpha then
				pcall(texture.SetAlpha, texture, 0)
			end
		else
			texture._ScooterPetOverlayHidden = false
			if texture.SetAlpha then
				pcall(texture.SetAlpha, texture, visibleAlpha)
			end
		end
	end

	local function EnforcePetOverlays()
		-- PetFrame is managed/protected by Edit Mode. Never touch its overlays during combat;
		-- defer and let PLAYER_REGEN_ENABLED apply any pending enforcement.
		if InCombatLockdown and InCombatLockdown() then
			addon._pendingPetOverlaysEnforce = true
			return
		end
		local db = addon and addon.db and addon.db.profile
		if not db or not db.unitFrames or not db.unitFrames.Pet then
			return
		end

		local ufCfg = db.unitFrames.Pet
		local portraitCfg = ufCfg.portrait or {}

		local hidePortrait = (portraitCfg.hidePortrait == true)
		local useCustomBorders = (ufCfg.useCustomBorders == true)

		-- Portrait opacity is stored as percent (1-100)
		local opacityPct = tonumber(portraitCfg.opacity) or 100
		if opacityPct < 1 then opacityPct = 1 elseif opacityPct > 100 then opacityPct = 100 end
		local opacityValue = opacityPct / 100.0

		local petAttackModeTexture = _G.PetAttackModeTexture
		local petFrameFlash = _G.PetFrameFlash

		-- Capture original alpha for newly created texture instances (frame recreation).
		if petAttackModeTexture and not originalAlphas[petAttackModeTexture] then
			originalAlphas[petAttackModeTexture] = petAttackModeTexture:GetAlpha() or 1.0
		end
		if petFrameFlash and not originalAlphas[petFrameFlash] then
			originalAlphas[petFrameFlash] = petFrameFlash:GetAlpha() or 1.0
		end

		if petAttackModeTexture then
			local hidden = hidePortrait or useCustomBorders
			local visibleAlpha = (originalAlphas[petAttackModeTexture] or 1.0) * opacityValue
			applyStickyOverlayAlpha(petAttackModeTexture, hidden, visibleAlpha)
		end

		if petFrameFlash then
			local hidden = hidePortrait or useCustomBorders
			local visibleAlpha = (originalAlphas[petFrameFlash] or 1.0) * opacityValue
			applyStickyOverlayAlpha(petFrameFlash, hidden, visibleAlpha)

			-- Some builds drive the red glow via sub-texture regions under PetFrameFlash.
			-- Enforce sticky alpha on immediate texture regions too (cheap + robust).
			if petFrameFlash.GetRegions then
				for _, region in ipairs({ petFrameFlash:GetRegions() }) do
					if region and region.GetObjectType and region:GetObjectType() == "Texture" then
						if not originalAlphas[region] and region.GetAlpha then
							originalAlphas[region] = region:GetAlpha() or 1.0
						end
						local regionVisibleAlpha = (originalAlphas[region] or 1.0) * opacityValue
						applyStickyOverlayAlpha(region, hidden, regionVisibleAlpha)
					end
				end
			end
		end
	end

	-- Expose a public helper so init.lua event handlers can re-enforce sticky pet overlays.
	function addon.UnitFrames_EnforcePetOverlays()
		EnforcePetOverlays()
	end

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].portrait = db.unitFrames[unit].portrait or {}
		local ufCfg = db.unitFrames[unit]
		local cfg = ufCfg.portrait

		local portraitFrame = resolvePortraitFrame(unit)
		if not portraitFrame then return end

		local maskFrame = resolvePortraitMaskFrame(unit)
		-- Corner icon only exists for Player frame
		local cornerIconFrame = (unit == "Player") and resolvePortraitCornerIconFrame(unit) or nil
		-- Rest loop only exists for Player frame
		local restLoopFrame = (unit == "Player") and resolvePortraitRestLoopFrame(unit) or nil
		-- Status texture only exists for Player frame
		local statusTextureFrame = (unit == "Player") and resolvePortraitStatusTextureFrame(unit) or nil
		-- Boss portrait frame texture only exists for Target/Focus frames
		local bossPortraitFrameTexture = (unit == "Target" or unit == "Focus") and resolveBossPortraitFrameTexture(unit) or nil
		-- Pet attack mode texture only exists for Pet frame
		local petAttackModeTexture = (unit == "Pet") and resolvePetAttackModeTexture(unit) or nil
		-- Pet frame flash only exists for Pet frame
		local petFrameFlash = (unit == "Pet") and resolvePetFrameFlash(unit) or nil

		-- Capture original positions on first access
		if not originalPositions[portraitFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = portraitFrame:GetPoint()
			if point then
				originalPositions[portraitFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		-- Capture mask position if it exists
		if maskFrame and not originalPositions[maskFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = maskFrame:GetPoint()
			if point then
				originalPositions[maskFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		-- Capture corner icon position if it exists
		if cornerIconFrame and not originalPositions[cornerIconFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = cornerIconFrame:GetPoint()
			if point then
				originalPositions[cornerIconFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		local origPortrait = originalPositions[portraitFrame]
		if not origPortrait then return end

		local origMask = maskFrame and originalPositions[maskFrame] or nil
		local origCornerIcon = cornerIconFrame and originalPositions[cornerIconFrame] or nil

		-- NOTE: Portrait scale baseline is always 1.0 (no Edit Mode scale setting for portraits)
		-- We do NOT capture frame:GetScale() because the frame may retain our applied scale across reloads

		-- Get portrait texture
		-- For unit frames, the portraitFrame IS the texture itself (not a frame containing a texture)
		-- Check if it's a Texture directly, otherwise try GetPortrait() or GetRegions()
		local portraitTexture = nil
		if portraitFrame.GetObjectType and portraitFrame:GetObjectType() == "Texture" then
			-- The frame itself is the texture (unit frame portraits)
			portraitTexture = portraitFrame
		elseif portraitFrame.GetPortrait then
			-- PortraitFrameMixin frames have GetPortrait() method
			portraitTexture = portraitFrame:GetPortrait()
		elseif portraitFrame.GetRegions then
			-- Fallback: search regions for a texture
			for _, region in ipairs({ portraitFrame:GetRegions() }) do
				if region and region.GetObjectType and region:GetObjectType() == "Texture" then
					portraitTexture = region
					break
				end
			end
		end

		-- Capture original texture coordinates on first access
		if portraitTexture and not originalTexCoords[portraitFrame] then
			-- GetTexCoord returns 8 values: ulX, ulY, blX, blY, urX, urY, brX, brY
			-- Extract bounds from corner coordinates
			local ulX, ulY, blX, blY, urX, urY, brX, brY = portraitTexture:GetTexCoord()
			-- Extract min/max from all corners to get bounding box
			local left = math.min(ulX or 0, blX or 0, urX or 0, brX or 0)
			local right = math.max(ulX or 1, blX or 1, urX or 1, brX or 1)
			local top = math.min(ulY or 0, blY or 0, urY or 0, brY or 0)
			local bottom = math.max(ulY or 1, blY or 1, urY or 1, brY or 1)
			originalTexCoords[portraitFrame] = {
				left = left,
				right = right,
				top = top,
				bottom = bottom,
			}
		end

		-- Capture original alpha on first access
		if not originalAlphas[portraitFrame] then
			originalAlphas[portraitFrame] = portraitFrame:GetAlpha() or 1.0
		end
		if maskFrame and not originalAlphas[maskFrame] then
			originalAlphas[maskFrame] = maskFrame:GetAlpha() or 1.0
		end
		if cornerIconFrame and not originalAlphas[cornerIconFrame] then
			originalAlphas[cornerIconFrame] = cornerIconFrame:GetAlpha() or 1.0
		end
		if restLoopFrame and not originalAlphas[restLoopFrame] then
			originalAlphas[restLoopFrame] = restLoopFrame:GetAlpha() or 1.0
		end
		if statusTextureFrame and not originalAlphas[statusTextureFrame] then
			originalAlphas[statusTextureFrame] = statusTextureFrame:GetAlpha() or 1.0
		end
		if bossPortraitFrameTexture and not originalAlphas[bossPortraitFrameTexture] then
			originalAlphas[bossPortraitFrameTexture] = bossPortraitFrameTexture:GetAlpha() or 1.0
		end
		if petAttackModeTexture and not originalAlphas[petAttackModeTexture] then
			originalAlphas[petAttackModeTexture] = petAttackModeTexture:GetAlpha() or 1.0
		end
		if petFrameFlash and not originalAlphas[petFrameFlash] then
			originalAlphas[petFrameFlash] = petFrameFlash:GetAlpha() or 1.0
		end

		local origPortraitAlpha = originalAlphas[portraitFrame] or 1.0
		local origMaskAlpha = maskFrame and (originalAlphas[maskFrame] or 1.0) or nil
		local origCornerIconAlpha = cornerIconFrame and (originalAlphas[cornerIconFrame] or 1.0) or nil
		local origRestLoopAlpha = restLoopFrame and (originalAlphas[restLoopFrame] or 1.0) or nil
		local origStatusTextureAlpha = statusTextureFrame and (originalAlphas[statusTextureFrame] or 1.0) or nil
		local origBossPortraitFrameTextureAlpha = bossPortraitFrameTexture and (originalAlphas[bossPortraitFrameTexture] or 1.0) or nil
		local origPetAttackModeTextureAlpha = petAttackModeTexture and (originalAlphas[petAttackModeTexture] or 1.0) or nil
		local origPetFrameFlashAlpha = petFrameFlash and (originalAlphas[petFrameFlash] or 1.0) or nil

		-- Capture original mask atlas on first access (for Player only - to support full circle mask)
		if maskFrame and unit == "Player" and not originalMaskAtlas[maskFrame] then
			if maskFrame.GetAtlas then
				local ok, atlas = pcall(maskFrame.GetAtlas, maskFrame)
				if ok and atlas then
					originalMaskAtlas[maskFrame] = atlas
				else
					-- Fallback: use known default Player mask atlas
					originalMaskAtlas[maskFrame] = "UI-HUD-UnitFrame-Player-Portrait-Mask"
				end
			else
				-- Fallback: use known default Player mask atlas
				originalMaskAtlas[maskFrame] = "UI-HUD-UnitFrame-Player-Portrait-Mask"
			end
		end

		local origMaskAtlas = maskFrame and (originalMaskAtlas[maskFrame] or nil) or nil

		-- Get offsets from config
		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0

		-- Get scale from config (100-200%, stored as percentage)
		local scalePct = tonumber(cfg.scale) or 100
		local scaleMultiplier = scalePct / 100.0

		-- Get zoom from config (100-200%, stored as percentage)
		-- 100% = no zoom (full texture), > 100% = zoom in (crop edges)
		-- Note: Zoom out (< 100%) is not supported - portrait textures are at full bounds (0,1,0,1)
		local zoomPct = tonumber(cfg.zoom) or 100
		if zoomPct < 100 then zoomPct = 100 elseif zoomPct > 200 then zoomPct = 200 end

		-- Get visibility settings from config
		local hidePortrait = (cfg.hidePortrait == true)
		local hideRestLoop = (cfg.hideRestLoop == true)
		local hideStatusTexture = (cfg.hideStatusTexture == true)
		local hideCornerIcon = (cfg.hideCornerIcon == true)
		local opacityPct = tonumber(cfg.opacity) or 100
		if opacityPct < 1 then opacityPct = 1 elseif opacityPct > 100 then opacityPct = 100 end
		local opacityValue = opacityPct / 100.0

		-- Get full circle mask setting (Player only)
		local useFullCircleMask = (unit == "Player") and (cfg.useFullCircleMask == true) or false

		-- Apply offsets relative to original positions (portrait, mask, and corner icon together)
		-- NOTE: Pet positioning disabled - PetFrame is a managed frame; moving portrait causes entire frame to move
		local function applyPosition()
			if unit == "Pet" then
				-- Skip positioning for Pet - causes entire frame to move due to managed frame layout system
				return
			end
			if not InCombatLockdown() then
				-- Move portrait frame
				portraitFrame:ClearAllPoints()
				portraitFrame:SetPoint(origPortrait.point, origPortrait.relativeTo, origPortrait.relativePoint, origPortrait.xOfs + offsetX, origPortrait.yOfs + offsetY)

				-- Move mask frame if it exists
				-- For Target/Focus/Pet, anchor mask to portrait to keep them locked together
				-- Pet's mask is already anchored to portrait in XML, so we maintain that relationship
				-- For Player, use original anchor to maintain proper positioning
				if maskFrame and origMask then
					maskFrame:ClearAllPoints()
					if unit == "Target" or unit == "Focus" or unit == "Pet" then
						-- Anchor mask to portrait frame to prevent drift
						-- Use TOPLEFT/BOTTOMRIGHT anchoring to match XML structure (Pet) or CENTER (Target/Focus)
						if unit == "Pet" then
							-- Pet mask uses TOPLEFT and BOTTOMRIGHT anchors to match portrait bounds
							maskFrame:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
							maskFrame:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
						else
							-- Target/Focus: Use CENTER to CENTER anchoring with 0,0 offset to keep them perfectly aligned
							maskFrame:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
						end
					else
						-- Player: use original anchor
						maskFrame:SetPoint(origMask.point, origMask.relativeTo, origMask.relativePoint, origMask.xOfs + offsetX, origMask.yOfs + offsetY)
					end
				end

				-- Move corner icon frame if it exists (Player only)
				if cornerIconFrame and origCornerIcon and unit == "Player" then
					cornerIconFrame:ClearAllPoints()
					cornerIconFrame:SetPoint(origCornerIcon.point, origCornerIcon.relativeTo, origCornerIcon.relativePoint, origCornerIcon.xOfs + offsetX, origCornerIcon.yOfs + offsetY)
				end
			end
		end

		-- Apply scaling to portrait, mask, and corner icon frames
		-- Baseline is always 1.0 for portraits (no Edit Mode scale setting)
		local function applyScale()
			if not InCombatLockdown() then
				-- Scale portrait frame (baseline 1.0 × multiplier)
				portraitFrame:SetScale(scaleMultiplier)

				-- Scale mask frame if it exists
				if maskFrame then
					maskFrame:SetScale(scaleMultiplier)
				end

				-- Scale corner icon frame if it exists (Player only)
				if cornerIconFrame and unit == "Player" then
					cornerIconFrame:SetScale(scaleMultiplier)
				end
			end
		end

		-- Apply zoom to portrait texture via SetTexCoord
		local function applyZoom()
			if not portraitTexture then 
				-- Debug: log if texture not found
				if addon.debug then
					print("ScooterMod: Portrait zoom - texture not found for", unit)
				end
				return 
			end
			
			-- Re-capture original coordinates if not stored yet (handles texture recreation)
			if not originalTexCoords[portraitFrame] then
				local ulX, ulY, blX, blY, urX, urY, brX, brY = portraitTexture:GetTexCoord()
				local left = math.min(ulX or 0, blX or 0, urX or 0, brX or 0)
				local right = math.max(ulX or 1, blX or 1, urX or 1, brX or 1)
				local top = math.min(ulY or 0, blY or 0, urY or 0, brY or 0)
				local bottom = math.max(ulY or 1, blY or 1, urY or 1, brY or 1)
				originalTexCoords[portraitFrame] = {
					left = left,
					right = right,
					top = top,
					bottom = bottom,
				}
			end
			
			local origCoords = originalTexCoords[portraitFrame]
			if not origCoords then return end

			-- Calculate zoom: 100% = no change, > 100% = zoom in (crop edges), < 100% = zoom out (limited)
			-- For zoom in: crop equal amounts from all sides
			-- For zoom out: we can't show beyond texture bounds, so we'll limit it
			local zoomFactor = zoomPct / 100.0
			
			if zoomFactor == 1.0 then
				-- No zoom: restore original coordinates
				if portraitTexture.SetTexCoord then
					portraitTexture:SetTexCoord(origCoords.left, origCoords.right, origCoords.top, origCoords.bottom)
				end
			elseif zoomFactor > 1.0 then
				-- Zoom in: crop edges (e.g., 150% = show center 66.7% = crop 16.7% from each side)
				local cropAmount = (zoomFactor - 1.0) / (2.0 * zoomFactor)
				local origWidth = origCoords.right - origCoords.left
				local origHeight = origCoords.bottom - origCoords.top
				local newLeft = origCoords.left + (origWidth * cropAmount)
				local newRight = origCoords.right - (origWidth * cropAmount)
				local newTop = origCoords.top + (origHeight * cropAmount)
				local newBottom = origCoords.bottom - (origHeight * cropAmount)
				
				if portraitTexture.SetTexCoord then
					portraitTexture:SetTexCoord(newLeft, newRight, newTop, newBottom)
					-- Debug output
					if addon.debug then
						print(string.format("ScooterMod: Portrait zoom %d%% for %s - coords: %.3f,%.3f,%.3f,%.3f", zoomPct, unit, newLeft, newRight, newTop, newBottom))
					end
				end
			else
				-- Zoom out: show more (limited by texture bounds)
				-- LIMITATION: If original coordinates are already at full bounds (0,1,0,1),
				-- we cannot zoom out because there are no additional pixels to show.
				-- The texture coordinate system is clamped to [0,1] range.
				local origWidth = origCoords.right - origCoords.left
				local origHeight = origCoords.bottom - origCoords.top
				
				-- Check if we're already at full bounds - if so, zoom out is not possible
				local isFullBounds = (origCoords.left <= 0.001 and origCoords.right >= 0.999 and 
				                      origCoords.top <= 0.001 and origCoords.bottom >= 0.999)
				
				if isFullBounds then
					-- Already at full texture bounds - zoom out has no effect
					-- Just restore original coordinates (which are already full bounds)
					if portraitTexture.SetTexCoord then
						portraitTexture:SetTexCoord(origCoords.left, origCoords.right, origCoords.top, origCoords.bottom)
					end
					-- Debug output to explain limitation
					if addon.debug then
						print(string.format("ScooterMod: Portrait zoom out %d%% for %s - limited by full texture bounds (0,1,0,1)", zoomPct, unit))
					end
				else
					-- Original coordinates are NOT at full bounds, so we can expand within available space
					local origCenterX = origCoords.left + (origWidth / 2.0)
					local origCenterY = origCoords.top + (origHeight / 2.0)
					local newWidth = origWidth / zoomFactor
					local newHeight = origHeight / zoomFactor
					local newLeft = math.max(0, origCenterX - (newWidth / 2.0))
					local newRight = math.min(1, origCenterX + (newWidth / 2.0))
					local newTop = math.max(0, origCenterY - (newHeight / 2.0))
					local newBottom = math.min(1, origCenterY + (newHeight / 2.0))
					
					if portraitTexture.SetTexCoord then
						portraitTexture:SetTexCoord(newLeft, newRight, newTop, newBottom)
						if addon.debug then
							print(string.format("ScooterMod: Portrait zoom out %d%% for %s - coords: %.3f,%.3f,%.3f,%.3f", zoomPct, unit, newLeft, newRight, newTop, newBottom))
						end
					end
				end
			end
		end

		-- Apply mask atlas change (Player only - full circle mask)
		local function applyMask()
			if maskFrame and unit == "Player" and origMaskAtlas then
				if useFullCircleMask then
					-- Change to full circle mask
					if maskFrame.SetAtlas then
						pcall(maskFrame.SetAtlas, maskFrame, "CircleMask", false)
					end
				else
					-- Restore original mask (with square corner)
					if maskFrame.SetAtlas then
						pcall(maskFrame.SetAtlas, maskFrame, origMaskAtlas, false)
					end
				end
			end
		end

		-- Apply portrait border using custom textures
		local function applyBorder()
			if not portraitFrame then return end
			
			-- Get parent frame for creating border texture (portrait is a Texture, not a Frame)
			local parentFrame = portraitFrame:GetParent()
			if not parentFrame then return end
			
			-- Use a unique key for storing border texture on parent frame
			local borderKey = "ScootPortraitBorder_" .. tostring(unit)
			local borderTexture = parentFrame[borderKey]
			
			-- Border is enabled only when the per-portrait toggle is on AND the portrait itself is not hidden.
			-- This ensures Portrait → Visibility → "Hide Portrait" also hides any custom border art.
			local borderEnabled = cfg.portraitBorderEnable and not hidePortrait
			if not borderEnabled then
				-- Hide border if disabled
				if borderTexture then
					borderTexture:Hide()
				end
				return
			end
			
			local borderStyle = cfg.portraitBorderStyle or "texture_c"
			-- Treat "default" as "texture_c" for backwards compatibility
			if borderStyle == "default" then
				borderStyle = "texture_c"
			end
			
			-- Map style keys to texture paths
			local textureMap = {
				texture_c = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\texture_c.tga",
				texture_s = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\texture_s.tga",
				rare_c = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\rare_c.tga",
				rare_s = "Interface\\AddOns\\ScooterMod\\media\\portraitborder\\rare_s.tga",
			}
			
			local texturePath = textureMap[borderStyle]
			if not texturePath then return end
			
			-- Create border texture if it doesn't exist
			if not borderTexture then
				borderTexture = parentFrame:CreateTexture(nil, "OVERLAY")
				parentFrame[borderKey] = borderTexture
			end
			
			-- Set texture
			borderTexture:SetTexture(texturePath)
			
			-- Get border thickness (1-16)
			local thickness = tonumber(cfg.portraitBorderThickness) or 1
			if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
			
			-- Calculate expand based on thickness (negative values expand outward/outset)
			-- Thickness 1 = minimal expansion, thickness 16 = maximum expansion
			-- Increased multiplier to push borders further out from portrait edge to align with portrait circle
			local baseOutset = 4.0  -- Base outset to align with portrait edge
			local expandX = -(baseOutset + (thickness * 2.0))
			local expandY = -(baseOutset + (thickness * 2.0))
			
			-- Position border to match portrait with expansion
			borderTexture:ClearAllPoints()
			borderTexture:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", expandX, -expandY)
			borderTexture:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -expandX, expandY)
			
			-- Apply color based on color mode
			local colorMode = cfg.portraitBorderColorMode or "texture"
			local r, g, b, a = 1, 1, 1, 1
			
			if colorMode == "custom" then
				-- Custom: use tint color
				local tintColor = cfg.portraitBorderTintColor or {1, 1, 1, 1}
				r, g, b, a = tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1
			elseif colorMode == "class" then
				-- Class Color: use player's class color
				if addon.GetClassColorRGB then
					local cr, cg, cb = addon.GetClassColorRGB(unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet")))
					r, g, b, a = cr or 1, cg or 1, cb or 1, 1
				else
					r, g, b, a = 1, 1, 1, 1
				end
			elseif colorMode == "texture" then
				-- Texture Original: preserve texture's original colors (white = no tint)
				r, g, b, a = 1, 1, 1, 1
			end
			
			borderTexture:SetVertexColor(r, g, b, a)
			
			-- Set draw layer to appear above portrait
			borderTexture:SetDrawLayer("OVERLAY", 7)
			
			-- Show border
			borderTexture:Show()
		end

		local function applyVisibility()
			-- If "Hide Portrait" is checked, hide everything (ignore individual flags)
			-- Otherwise, check individual flags for each element
			
			-- Portrait frame: hidden if "Hide Portrait" is checked
			local portraitHidden = hidePortrait
			local finalAlpha = portraitHidden and 0.0 or (origPortraitAlpha * opacityValue)
			
			if portraitFrame.SetAlpha then
				portraitFrame:SetAlpha(finalAlpha)
			end
			if portraitHidden and portraitFrame.Hide then
				portraitFrame:Hide()
			end

			-- Mask frame: hidden if "Hide Portrait" is checked
			if maskFrame then
				local maskHidden = hidePortrait
				local maskAlpha = maskHidden and 0.0 or (origMaskAlpha * opacityValue)
				if maskFrame.SetAlpha then
					maskFrame:SetAlpha(maskAlpha)
				end
				if maskHidden and maskFrame.Hide then
					maskFrame:Hide()
				end
			end

			-- Corner icon frame: hidden if "Hide Portrait" OR "Hide Corner Icon" is checked (Player only)
			if cornerIconFrame and unit == "Player" then
				local iconHidden = hidePortrait or hideCornerIcon
				local iconAlpha = iconHidden and 0.0 or (origCornerIconAlpha * opacityValue)
				if cornerIconFrame.SetAlpha then
					cornerIconFrame:SetAlpha(iconAlpha)
				end
				if iconHidden and cornerIconFrame.Hide then
					cornerIconFrame:Hide()
				end
			end

			-- Rest loop frame: hidden if "Hide Portrait" OR "Hide Rest Loop/Animation" is checked (Player only)
			if restLoopFrame and unit == "Player" then
				local restHidden = hidePortrait or hideRestLoop
				local restAlpha = restHidden and 0.0 or (origRestLoopAlpha * opacityValue)
				if restLoopFrame.SetAlpha then
					restLoopFrame:SetAlpha(restAlpha)
				end
				if restHidden and restLoopFrame.Hide then
					restLoopFrame:Hide()
				end
			end

			-- Status texture frame: hidden if "Hide Portrait" OR "Hide Status Texture" is checked,
			-- or when global Use Custom Borders is enabled for the Player frame.
			if statusTextureFrame and unit == "Player" then
				local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
				local statusHidden = hidePortrait or hideStatusTexture or useCustomBorders
				local statusAlpha = statusHidden and 0.0 or (origStatusTextureAlpha * opacityValue)
				if statusTextureFrame.SetAlpha then
					statusTextureFrame:SetAlpha(statusAlpha)
				end
				if statusHidden and statusTextureFrame.Hide then
					statusTextureFrame:Hide()
				end
			end

			-- Boss portrait frame texture: hidden if "Hide Portrait" is checked (Target/Focus only)
			-- This texture appears when targeting a boss and shows as a boss-specific portrait frame overlay
			if bossPortraitFrameTexture and (unit == "Target" or unit == "Focus") then
				local bossTexHidden = hidePortrait
				local bossTexAlpha = bossTexHidden and 0.0 or (origBossPortraitFrameTextureAlpha * opacityValue)
				if bossPortraitFrameTexture.SetAlpha then
					bossPortraitFrameTexture:SetAlpha(bossTexAlpha)
				end
				if bossTexHidden and bossPortraitFrameTexture.Hide then
					bossPortraitFrameTexture:Hide()
				elseif not bossTexHidden and bossPortraitFrameTexture.Show then
					bossPortraitFrameTexture:Show()
				end
			end

			-- Pet attack mode texture: hidden if "Hide Portrait" is checked OR "Use Custom Borders" is enabled (Pet only)
			-- This texture appears around the pet portrait when the pet is in attack mode
			if petAttackModeTexture and unit == "Pet" then
				local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
				local petAttackHidden = hidePortrait or useCustomBorders
				local petAttackVisibleAlpha = (origPetAttackModeTextureAlpha * opacityValue)
				applyStickyOverlayAlpha(petAttackModeTexture, petAttackHidden, petAttackVisibleAlpha)
			end

			-- Pet frame flash: hidden if "Hide Portrait" is checked OR "Use Custom Borders" is enabled (Pet only)
			-- This texture flashes when the pet takes damage
			if petFrameFlash and unit == "Pet" then
				local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
				local petFlashHidden = hidePortrait or useCustomBorders
				local petFlashVisibleAlpha = (origPetFrameFlashAlpha * opacityValue)
				applyStickyOverlayAlpha(petFrameFlash, petFlashHidden, petFlashVisibleAlpha)
			end
		end

		-- Apply damage text styling (Player and Pet)
		local function applyDamageText()
			if unit ~= "Player" and unit ~= "Pet" then return end
			local damageTextFrame = resolveDamageTextFrame(unit)
			if not damageTextFrame then return end

			local damageTextDisabled = cfg.damageTextDisabled == true
			
			-- Instead of hiding the frame (which breaks Blizzard's CombatFeedback system),
			-- set alpha to 0 to make it invisible when disabled. This prevents the feedbackStartTime nil error.
			-- We use alpha instead of SetShown because Blizzard's CombatFeedback_OnUpdate expects the frame
			-- to exist and be managed by their system.
			if damageTextDisabled then
				if damageTextFrame.SetAlpha then
					pcall(damageTextFrame.SetAlpha, damageTextFrame, 0)
				end
				-- Skip styling when disabled
				return
			end

			local damageTextCfg = cfg.damageText or {}
			
			-- Hook SetTextHeight to re-apply our custom font size after Blizzard changes it
			-- CRITICAL: We use hooksecurefunc instead of method override to avoid taint. Method overrides
			-- cause taint that spreads through the execution context, blocking protected functions
			-- like SetTargetClampingInsets() during nameplate setup. See DEBUG.md for details.
			-- Store the unit key on the frame so the hook knows which config to read
			damageTextFrame._scooterUnitKey = unit
			if not damageTextFrame._scooterSetTextHeightHooked then
				damageTextFrame._scooterSetTextHeightHooked = true
				
				hooksecurefunc(damageTextFrame, "SetTextHeight", function(self, height)
					-- Guard against recursion (though we use SetFont, not SetTextHeight, to apply)
					if self._scooterApplyingTextHeight then return end
					
					-- Check if we have custom settings (use stored unit key)
					local unitKey = self._scooterUnitKey or "Player"
					local db = addon and addon.db and addon.db.profile
					if db and db.unitFrames and db.unitFrames[unitKey] and db.unitFrames[unitKey].portrait then
						local cfg = db.unitFrames[unitKey].portrait
						local damageTextCfg = cfg.damageText or {}
						local customSize = tonumber(damageTextCfg.size)
						if customSize then
							-- Re-apply our custom size using SetFont (overrides what Blizzard just set)
							local customFace = addon.ResolveFontFace and addon.ResolveFontFace(damageTextCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
							local customStyle = tostring(damageTextCfg.style or "OUTLINE")
							self._scooterApplyingTextHeight = true
							if addon.ApplyFontStyle then
								addon.ApplyFontStyle(self, customFace, customSize, customStyle)
							elseif self.SetFont then
								pcall(self.SetFont, self, customFace, customSize, customStyle)
							end
							self._scooterApplyingTextHeight = nil
						end
					end
					-- If no custom settings configured, Blizzard's size remains (hook does nothing)
				end)
			end
			
			-- Initialize baseline storage
			addon._ufDamageTextBaselines = addon._ufDamageTextBaselines or {}
			local function ensureBaseline(fs, key)
				addon._ufDamageTextBaselines[key] = addon._ufDamageTextBaselines[key] or {}
				local b = addon._ufDamageTextBaselines[key]
				if b.point == nil then
					if fs and fs.GetPoint then
						local p, relTo, rp, x, y = fs:GetPoint(1)
						b.point = p or "CENTER"
						b.relTo = relTo or (fs.GetParent and fs:GetParent()) or nil
						b.relPoint = rp or b.point
						b.x = tonumber(x) or 0
						b.y = tonumber(y) or 0
					else
						b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or nil, "CENTER", 0, 0
					end
				end
				return b
			end

			-- Apply text styling
			local face = addon.ResolveFontFace and addon.ResolveFontFace(damageTextCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
			local size = tonumber(damageTextCfg.size) or 14
			local outline = tostring(damageTextCfg.style or "OUTLINE")
			if addon.ApplyFontStyle then
				addon.ApplyFontStyle(damageTextFrame, face, size, outline)
			elseif damageTextFrame.SetFont then
				pcall(damageTextFrame.SetFont, damageTextFrame, face, size, outline)
			end

			-- Determine color based on colorMode
			local c = nil
			local colorMode = damageTextCfg.colorMode or "default"
			if colorMode == "class" then
				-- Class Color: use player's class color (for Pet, still use player's class)
				if addon.GetClassColorRGB then
					local cr, cg, cb = addon.GetClassColorRGB("player")
					c = { cr or 1, cg or 1, cb or 1, 1 }
				else
					c = {1.0, 0.82, 0.0, 1} -- fallback to default yellow
				end
			elseif colorMode == "custom" then
				-- Custom: use stored color
				c = damageTextCfg.color or {1.0, 0.82, 0.0, 1}
			else
				-- Default: use Blizzard's default yellow color (1.0, 0.82, 0.0)
				c = damageTextCfg.color or {1.0, 0.82, 0.0, 1}
			end
			if damageTextFrame.SetTextColor then
				pcall(damageTextFrame.SetTextColor, damageTextFrame, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			end

			-- Apply offset
			local ox = (damageTextCfg.offset and tonumber(damageTextCfg.offset.x)) or 0
			local oy = (damageTextCfg.offset and tonumber(damageTextCfg.offset.y)) or 0
			if damageTextFrame.ClearAllPoints and damageTextFrame.SetPoint then
				local b = ensureBaseline(damageTextFrame, unit .. ":damageText")
				damageTextFrame:ClearAllPoints()
				damageTextFrame:SetPoint(b.point or "CENTER", b.relTo or (damageTextFrame.GetParent and damageTextFrame:GetParent()) or nil, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
			end
		end

		if InCombatLockdown() then
			-- Pet overlays are combat-driven and may appear during combat; enforce sticky alpha immediately.
			-- This path only uses SetAlpha + hooksecurefunc on the texture itself (combat-safe).
			if unit == "Pet" then
				EnforcePetOverlays()
			end
			-- Defer application until out of combat
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.1, function()
					if not InCombatLockdown() then
						applyPosition()
						applyScale()
						applyZoom()
						applyMask()
						applyBorder()
						applyVisibility()
						applyDamageText()
					end
				end)
			end
		else
			applyPosition()
			applyScale()
			applyZoom()
			applyMask()
			applyBorder()
			applyVisibility()
			applyDamageText()
		end
	end

	function addon.ApplyUnitFramePortraitFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFramePortraits()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
		applyForUnit("TargetOfTarget")
	end

	-- Hook portrait updates to reapply zoom when Blizzard updates portraits
	-- Hook UnitFramePortrait_Update which is called when portraits need refreshing
	if _G.UnitFramePortrait_Update then
		_G.hooksecurefunc("UnitFramePortrait_Update", function(unitFrame)
			if unitFrame and unitFrame.unit then
				local unit = unitFrame.unit
				local unitKey = nil
				if unit == "player" then unitKey = "Player"
				elseif unit == "target" then unitKey = "Target"
				elseif unit == "focus" then unitKey = "Focus"
				elseif unit == "pet" then unitKey = "Pet"
				elseif unit == "targettarget" then unitKey = "TargetOfTarget"
				end
				if unitKey then
					-- Defer zoom reapplication to next frame to ensure texture is ready
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							applyForUnit(unitKey)
						end)
					end
				end
			end
		end)
	end

	-- Hook Blizzard's CombatFeedback system to prevent showing damage text when disabled
	-- We need to hook both OnCombatEvent (when damage happens) and OnUpdate (animation loop)
	-- CombatFeedback_OnCombatEvent receives PlayerFrame/PetFrame as 'self', and frame.feedbackText is the HitText
	-- CombatFeedback_OnUpdate also receives PlayerFrame/PetFrame as 'self'
	if _G.CombatFeedback_OnCombatEvent then
		_G.hooksecurefunc("CombatFeedback_OnCombatEvent", function(self, event, flags, amount, type)
			-- Check if this is PlayerFrame or PetFrame
			local playerFrame = _G.PlayerFrame
			local petFrame = _G.PetFrame
			local unitKey = nil
			if self and self == playerFrame then
				unitKey = "Player"
			elseif self and self == petFrame then
				unitKey = "Pet"
			end
			
			if unitKey and self.feedbackText then
				-- PetFrame is managed/protected by Edit Mode. Avoid any in-combat writes to its
				-- feedback text (SetAlpha/SetFont) to prevent taint propagation that can later
				-- block protected Edit Mode methods like PetFrame:HideBase().
				if unitKey == "Pet" and InCombatLockdown and InCombatLockdown() then
					return
				end
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames[unitKey] and db.unitFrames[unitKey].portrait then
					local cfg = db.unitFrames[unitKey].portrait
					local damageTextDisabled = cfg.damageTextDisabled == true
					
					if damageTextDisabled then
						-- Immediately set alpha to 0 if disabled, preventing it from being visible
						-- This happens after Blizzard sets feedbackStartTime, so it won't cause nil errors
						if self.feedbackText.SetAlpha then
							pcall(self.feedbackText.SetAlpha, self.feedbackText, 0)
						end
					else
						-- Override Blizzard's font size with our custom size
						-- Blizzard calls SetTextHeight(fontHeight) which sets the text region height
						-- We need to use SetFont() with our custom size instead, which sets the actual font size
						-- SetFont will properly scale the text, while SetTextHeight just scales the region (causing pixelation)
						local damageTextCfg = cfg.damageText or {}
						local customSize = tonumber(damageTextCfg.size) or 14
						local customFace = addon.ResolveFontFace and addon.ResolveFontFace(damageTextCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
						local customStyle = tostring(damageTextCfg.style or "OUTLINE")
						
						-- Use SetFont to set the actual font size (not SetTextHeight which just scales the region)
						-- This must be called after Blizzard's SetTextHeight to override it
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(self.feedbackText, customFace, customSize, customStyle)
						elseif self.feedbackText.SetFont then
							pcall(self.feedbackText.SetFont, self.feedbackText, customFace, customSize, customStyle)
						end
					end
				end
			end
		end)
	end

	-- Hook CombatFeedback_OnUpdate to continuously keep alpha at 0 when disabled
	-- This is critical because OnUpdate runs every frame and will override our alpha setting
	-- OnUpdate receives PlayerFrame/PetFrame as 'self'
	if _G.CombatFeedback_OnUpdate then
		_G.hooksecurefunc("CombatFeedback_OnUpdate", function(self, elapsed)
			-- Check if this is PlayerFrame or PetFrame
			local playerFrame = _G.PlayerFrame
			local petFrame = _G.PetFrame
			local unitKey = nil
			if self and self == playerFrame then
				unitKey = "Player"
			elseif self and self == petFrame then
				unitKey = "Pet"
			end
			
			if unitKey and self.feedbackText then
				if unitKey == "Pet" and InCombatLockdown and InCombatLockdown() then
					return
				end
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames[unitKey] and db.unitFrames[unitKey].portrait then
					local damageTextDisabled = db.unitFrames[unitKey].portrait.damageTextDisabled == true
					if damageTextDisabled then
						-- Continuously force alpha to 0, overriding Blizzard's animation
						-- This runs after Blizzard's SetAlpha calls, so it will override them
						if self.feedbackText.SetAlpha then
							pcall(self.feedbackText.SetAlpha, self.feedbackText, 0)
						end
					end
				end
			end
		end)
	end
	
	-- Also hook SetPortraitTexture as a fallback
	if _G.SetPortraitTexture then
		_G.hooksecurefunc("SetPortraitTexture", function(texture, unit)
			if unit and (unit == "player" or unit == "target" or unit == "focus" or unit == "pet" or unit == "targettarget") then
				local unitKey = nil
				if unit == "player" then unitKey = "Player"
				elseif unit == "target" then unitKey = "Target"
				elseif unit == "focus" then unitKey = "Focus"
				elseif unit == "pet" then unitKey = "Pet"
				elseif unit == "targettarget" then unitKey = "TargetOfTarget"
				end
				if unitKey then
					-- Defer zoom reapplication to next frame to ensure texture is ready
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							applyForUnit(unitKey)
						end)
					end
				end
			end
		end)
	end

	-- Keep the Player Frame status halo hidden when ScooterMod wants it hidden.
	local function EnforcePlayerStatusTextureVisibility()
		local db = addon and addon.db and addon.db.profile
		if not db then
			return
		end

		local ufCfg = db.unitFrames and db.unitFrames.Player
		if not ufCfg then
			return
		end

		local portraitCfg = ufCfg.portrait or {}
		local hidePortrait = portraitCfg.hidePortrait == true
		local hideStatusTexture = portraitCfg.hideStatusTexture == true
		local useCustomBorders = ufCfg.useCustomBorders == true

		if not (hidePortrait or hideStatusTexture or useCustomBorders) then
			-- Respect Blizzard visuals when no ScooterMod rule wants it hidden.
			return
		end

		local playerFrame = _G.PlayerFrame
		local main = playerFrame and playerFrame.PlayerFrameContent and playerFrame.PlayerFrameContent.PlayerFrameContentMain
		local statusTexture = main and main.StatusTexture
		if not statusTexture then
			return
		end

		if statusTexture.SetAlpha then
			statusTexture:SetAlpha(0)
		end
		if statusTexture.Hide then
			statusTexture:Hide()
		end
	end

	if _G.PlayerFrame_UpdateStatus then
		_G.hooksecurefunc("PlayerFrame_UpdateStatus", EnforcePlayerStatusTextureVisibility)
	end
end

