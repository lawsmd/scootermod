local addonName, addon = ...

addon.Components = addon.Components or {}
addon.ComponentInitializers = addon.ComponentInitializers or {}
addon.ComponentsUtil = addon.ComponentsUtil or {}

local Util = addon.ComponentsUtil
local UNIT_FRAME_CATEGORY_TO_UNIT = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus  = "Focus",
    ufPet    = "Pet",
}

-- Combat watcher for FullPowerFrame pending reapplies.
-- When hooks fire during combat (e.g., druid form change), we defer reapplication
-- to avoid tainting the execution context.
local fullPowerFrameCombatWatcher = nil
local pendingFullPowerFrames = {}

local function ensureFullPowerFrameCombatWatcher()
    if fullPowerFrameCombatWatcher then return end
    fullPowerFrameCombatWatcher = CreateFrame("Frame")
    fullPowerFrameCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    fullPowerFrameCombatWatcher:SetScript("OnEvent", function()
        for frame in pairs(pendingFullPowerFrames) do
            if frame and frame._ScootFullPowerPendingReapply and frame._ScootFullPowerApplyState then
                frame._ScootFullPowerPendingReapply = nil
                frame._ScootFullPowerApplyState()
            end
            pendingFullPowerFrames[frame] = nil
        end
    end)
end

local function queueFullPowerFrameReapply(fullPowerFrame)
    if not fullPowerFrame then return end
    ensureFullPowerFrameCombatWatcher()
    pendingFullPowerFrames[fullPowerFrame] = true
end

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = CopyDefaultValue(v)
    end
    return copy
end

local function HideDefaultBarTextures(barFrame, restore)
    if not barFrame or not barFrame.GetRegions then return end
    local function matchesDefaultTexture(region)
        if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then return false end
        local tex = region.GetTexture and region:GetTexture()
        if type(tex) == "string" and tex:find("UI%-HUD%-CoolDownManager") then
            return true
        end
        if region.GetAtlas then
            local atlas = region:GetAtlas()
            if type(atlas) == "string" and atlas:find("UI%-HUD%-CoolDownManager") then
                return true
            end
        end
        return false
    end
    for _, region in ipairs({ barFrame:GetRegions() }) do
        if region and region ~= barFrame.ScooterModBG and region ~= barFrame.ScooterStyledBorder and region ~= (barFrame.ScooterStyledBorder and barFrame.ScooterStyledBorder.Texture) then
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                local layer = region:GetDrawLayer()
                if layer == "OVERLAY" or layer == "ARTWORK" or layer == "BORDER" then
                    if matchesDefaultTexture(region) then
                        region:SetAlpha(restore and 1 or 0)
                    end
                end
            end
        end
    end
end
Util.HideDefaultBarTextures = HideDefaultBarTextures

local function ToggleDefaultIconOverlay(iconFrame, restore)
    if not iconFrame or not iconFrame.GetRegions then return end
    for _, region in ipairs({ iconFrame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            if region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
                region:SetAlpha(restore and 1 or 0)
            end
        end
    end
end
Util.ToggleDefaultIconOverlay = ToggleDefaultIconOverlay

local function ResetIconBorderTarget(target)
    if not target then return end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(target)
    end

    local function wipeTexture(tex)
        if not tex then return end
        tex:Hide()
        if tex.SetTexture then pcall(tex.SetTexture, tex, nil) end
        if tex.SetAtlas then pcall(tex.SetAtlas, tex, nil, true) end
        if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1, 1, 1, 0) end
        if tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
    end

    wipeTexture(target.ScootAtlasBorder)
    wipeTexture(target.ScootTextureBorder)
    wipeTexture(target.ScootAtlasBorderTintOverlay)
    wipeTexture(target.ScootTextureBorderTintOverlay)

    if target.ScootSquareBorderEdges then
        for _, edge in pairs(target.ScootSquareBorderEdges) do
            if edge then edge:Hide() end
        end
    end

    if target.ScootSquareBorder and target.ScootSquareBorder.edges then
        for _, tex in pairs(target.ScootSquareBorder.edges) do
            if tex and tex.Hide then tex:Hide() end
        end
    end
    if target.ScootSquareBorderContainer and target.ScootSquareBorderContainer.Hide then
        target.ScootSquareBorderContainer:Hide()
    end
end
Util.ResetIconBorderTarget = ResetIconBorderTarget

local function CleanupIconBorderAttachments(icon)
    if not icon then return end
    local seen = {}
    local function cleanup(target)
        if target and not seen[target] then
            seen[target] = true
            ResetIconBorderTarget(target)
        end
    end

    cleanup(icon)
    cleanup(icon.ScooterIconBorderContainer)
    cleanup(icon.ScooterAtlasBorderContainer)
    cleanup(icon.ScooterTextureBorderContainer)
end
Util.CleanupIconBorderAttachments = CleanupIconBorderAttachments

local function PlayerInCombat()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        local inCombat = UnitAffectingCombat("player")
        if inCombat then return true end
    end
    return false
end
Util.PlayerInCombat = PlayerInCombat

local function ClampOpacity(value, minValue)
    local v = tonumber(value) or 100
    local minClamp = tonumber(minValue) or 50
    if v < minClamp then
        v = minClamp
    elseif v > 100 then
        v = 100
    end
    return v
end
Util.ClampOpacity = ClampOpacity

local function ApplyFullPowerSpikeScale(ownerFrame, heightScale)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end

    local fullPowerFrame = ownerFrame.FullPowerFrame
    if not fullPowerFrame or (fullPowerFrame.IsForbidden and fullPowerFrame:IsForbidden()) then
        return
    end

    local scaleY = tonumber(heightScale) or 1
    if scaleY <= 0 then
        scaleY = 1
    end
    if scaleY < 0.25 then
        scaleY = 0.25
    elseif scaleY > 6 then
        scaleY = 6
    end

    local spikeFrame = fullPowerFrame.SpikeFrame
    local pulseFrame = fullPowerFrame.PulseFrame

    local function captureDimensions(target)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        if not target._ScootFullPowerOrigWidth then
            if target.GetWidth then
                local ok, w = pcall(target.GetWidth, target)
                if ok and w and w > 0 then
                    target._ScootFullPowerOrigWidth = w
                end
            end
        end
        if not target._ScootFullPowerOrigHeight then
            if target.GetHeight then
                local ok, h = pcall(target.GetHeight, target)
                if ok and h and h > 0 then
                    target._ScootFullPowerOrigHeight = h
                end
            end
        end
        if not target._ScootFullPowerOrigScale then
            if target.GetScale then
                local ok, s = pcall(target.GetScale, target)
                if ok and s and s > 0 then
                    target._ScootFullPowerOrigScale = s
                end
            end
        end
        if target._ScootFullPowerOrigAlpha == nil and target.GetAlpha then
            local ok, a = pcall(target.GetAlpha, target)
            if ok and a ~= nil then
                target._ScootFullPowerOrigAlpha = a
            end
        end
    end

    local function applySize(target, desiredScale)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        local baseWidth = target._ScootFullPowerOrigWidth
        local baseHeight = target._ScootFullPowerOrigHeight
        local baseScale = target._ScootFullPowerOrigScale

        if baseWidth and baseHeight and target.SetSize then
            local newHeight = math.max(1, baseHeight * desiredScale)
            pcall(target.SetSize, target, baseWidth, newHeight)
            return
        end

        local applied = false
        if baseHeight and target.SetHeight then
            local newHeight = math.max(1, baseHeight * desiredScale)
            pcall(target.SetHeight, target, newHeight)
            applied = true
        end
        if baseWidth and target.SetWidth then
            pcall(target.SetWidth, target, baseWidth)
            applied = true
        end

        if not applied and baseScale and target.SetScale then
            local newScale = baseScale * desiredScale
            if newScale < 0.25 then
                newScale = 0.25
            elseif newScale > 6 then
                newScale = 6
            end
            pcall(target.SetScale, target, newScale)
        end
    end

    local function applyHiddenState(target, hidden)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        if hidden then
            if target.Hide then pcall(target.Hide, target) end
            if target.SetAlpha then pcall(target.SetAlpha, target, 0) end
        else
            if target.Show then pcall(target.Show, target) end
            local restoreAlpha = target._ScootFullPowerOrigAlpha
            if restoreAlpha == nil then
                -- Default baseline: AlertSpikeStay/BigSpikeGlow start at alpha 0.
                restoreAlpha = 0
            end
            if target.SetAlpha then pcall(target.SetAlpha, target, restoreAlpha) end
        end
    end

    local function ensureCaptured()
        if fullPowerFrame._ScootFullPowerCaptured then
            return
        end
        fullPowerFrame._ScootFullPowerCaptured = true
        captureDimensions(fullPowerFrame)
        captureDimensions(spikeFrame)
        if spikeFrame then
            captureDimensions(spikeFrame.AlertSpikeStay)
            captureDimensions(spikeFrame.BigSpikeGlow)
        end
        captureDimensions(pulseFrame)
        if pulseFrame then
            captureDimensions(pulseFrame.YellowGlow)
            captureDimensions(pulseFrame.SoftGlow)
        end
    end

    local function applyAll(desiredScale, hidden)
        ensureCaptured()
        if hidden then
            if spikeFrame and spikeFrame.SpikeAnim and spikeFrame.SpikeAnim.Stop then
                pcall(spikeFrame.SpikeAnim.Stop, spikeFrame.SpikeAnim)
            end
            if fullPowerFrame.FadeoutAnim and fullPowerFrame.FadeoutAnim.Stop then
                pcall(fullPowerFrame.FadeoutAnim.Stop, fullPowerFrame.FadeoutAnim)
            end
            if fullPowerFrame.PulseFrame and fullPowerFrame.PulseFrame.PulseAnim and fullPowerFrame.PulseFrame.PulseAnim.Stop then
                pcall(fullPowerFrame.PulseFrame.PulseAnim.Stop, fullPowerFrame.PulseFrame.PulseAnim)
            end
        end
        applySize(fullPowerFrame, desiredScale)
        if spikeFrame then
            applySize(spikeFrame, desiredScale)
            applySize(spikeFrame.AlertSpikeStay, desiredScale)
            applySize(spikeFrame.BigSpikeGlow, desiredScale)
        end
        if pulseFrame then
            applySize(pulseFrame, desiredScale)
            applySize(pulseFrame.YellowGlow, desiredScale)
            applySize(pulseFrame.SoftGlow, desiredScale)
        end

        applyHiddenState(spikeFrame and spikeFrame.AlertSpikeStay, hidden)
        applyHiddenState(spikeFrame and spikeFrame.BigSpikeGlow, hidden)
        if pulseFrame then
            applyHiddenState(pulseFrame, hidden)
            applyHiddenState(pulseFrame.YellowGlow, hidden)
            applyHiddenState(pulseFrame.SoftGlow, hidden)
        end
    end

    local function applyState()
        ensureCaptured()
        local storedScale = fullPowerFrame._ScootFullPowerLatestScale or 1
        local hidden = not not fullPowerFrame._ScootFullPowerHidden
        applyAll(storedScale, hidden)
    end

    fullPowerFrame._ScootFullPowerLatestScale = scaleY
    if fullPowerFrame._ScootFullPowerHidden == nil then
        fullPowerFrame._ScootFullPowerHidden = false
    end
    fullPowerFrame._ScootFullPowerApplyState = applyState
    -- CRITICAL: Guard against combat. If ApplyFullPowerSpikeScale is called during combat
    -- (e.g., via PRD ApplyStyling triggered by form change), calling applyState() would
    -- modify frames (SetSize, SetAlpha, etc.) and taint the execution context, causing
    -- SetTargetClampingInsets() to be blocked. Defer to after combat.
    if InCombatLockdown and InCombatLockdown() then
        fullPowerFrame._ScootFullPowerPendingReapply = true
        queueFullPowerFrameReapply(fullPowerFrame)
    else
        applyState()
    end

    if type(hooksecurefunc) == "function" and not fullPowerFrame._ScootFullPowerHooks then
        fullPowerFrame._ScootFullPowerHooks = true
        -- CRITICAL: Guard against combat to prevent taint. When these hooks fire during
        -- Blizzard's nameplate setup chain (e.g., druid form change in combat), any frame
        -- modifications (SetSize, SetAlpha, etc.) taint the execution context, causing
        -- SetTargetClampingInsets() to be blocked. See DEBUG.md for details.
        local function reapply()
            if InCombatLockdown and InCombatLockdown() then
                -- Defer to after combat - queue for PLAYER_REGEN_ENABLED
                fullPowerFrame._ScootFullPowerPendingReapply = true
                queueFullPowerFrameReapply(fullPowerFrame)
                return
            end
            applyState()
        end
        if fullPowerFrame.Initialize then
            hooksecurefunc(fullPowerFrame, "Initialize", reapply)
        end
        if fullPowerFrame.RemoveAnims then
            hooksecurefunc(fullPowerFrame, "RemoveAnims", reapply)
        end
        if fullPowerFrame.StartAnimIfFull then
            hooksecurefunc(fullPowerFrame, "StartAnimIfFull", reapply)
        end
        if spikeFrame and spikeFrame.SpikeAnim and spikeFrame.SpikeAnim.HookScript then
            spikeFrame.SpikeAnim:HookScript("OnPlay", reapply)
            spikeFrame.SpikeAnim:HookScript("OnFinished", reapply)
        end
        if pulseFrame and pulseFrame.PulseAnim and pulseFrame.PulseAnim.HookScript then
            pulseFrame.PulseAnim:HookScript("OnPlay", reapply)
            pulseFrame.PulseAnim:HookScript("OnFinished", reapply)
        end
    end
end
Util.ApplyFullPowerSpikeScale = ApplyFullPowerSpikeScale

local function SetFullPowerSpikeHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local fullPowerFrame = ownerFrame.FullPowerFrame
    if not fullPowerFrame or (fullPowerFrame.IsForbidden and fullPowerFrame:IsForbidden()) then
        return
    end
    fullPowerFrame._ScootFullPowerHidden = not not hidden
    -- CRITICAL: Guard against combat. Stopping animations and calling applyState() during combat
    -- would taint the execution context, causing SetTargetClampingInsets() to be blocked.
    if InCombatLockdown and InCombatLockdown() then
        -- Just store the hidden state; it will be applied after combat via queued reapply
        fullPowerFrame._ScootFullPowerPendingReapply = true
        queueFullPowerFrameReapply(fullPowerFrame)
        return
    end
    if fullPowerFrame._ScootFullPowerHidden then
        if fullPowerFrame.SpikeFrame and fullPowerFrame.SpikeFrame.SpikeAnim and fullPowerFrame.SpikeFrame.SpikeAnim.Stop then
            pcall(fullPowerFrame.SpikeFrame.SpikeAnim.Stop, fullPowerFrame.SpikeFrame.SpikeAnim)
        end
        if fullPowerFrame.PulseFrame and fullPowerFrame.PulseFrame.PulseAnim and fullPowerFrame.PulseFrame.PulseAnim.Stop then
            pcall(fullPowerFrame.PulseFrame.PulseAnim.Stop, fullPowerFrame.PulseFrame.PulseAnim)
        end
        if fullPowerFrame.FadeoutAnim and fullPowerFrame.FadeoutAnim.Stop then
            pcall(fullPowerFrame.FadeoutAnim.Stop, fullPowerFrame.FadeoutAnim)
        end
    end
    if fullPowerFrame._ScootFullPowerApplyState then
        fullPowerFrame._ScootFullPowerApplyState()
    else
        Util.ApplyFullPowerSpikeScale(ownerFrame, fullPowerFrame._ScootFullPowerLatestScale or 1)
        if fullPowerFrame._ScootFullPowerApplyState then
            fullPowerFrame._ScootFullPowerApplyState()
        end
    end
end
Util.SetFullPowerSpikeHidden = SetFullPowerSpikeHidden

-- Hide/show the Power Bar FeedbackFrame (Builder/Spender animation that flashes when power is spent/gained)
-- This frame shows a quick flash representing the amount of energy/mana/etc. spent or gained.
-- ownerFrame: the ManaBar or ClassNameplateManaBarFrame that contains the FeedbackFrame child
-- hidden: boolean - true to hide the feedback animation, false to restore it
local function SetPowerFeedbackHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local feedbackFrame = ownerFrame.FeedbackFrame
    if not feedbackFrame or (feedbackFrame.IsForbidden and feedbackFrame:IsForbidden()) then
        return
    end
    feedbackFrame._ScootPowerFeedbackHidden = not not hidden
    -- CRITICAL: Guard against combat. Stopping animations and calling Hide() during combat
    -- would taint the execution context, causing SetTargetClampingInsets() to be blocked.
    -- The hook installation below is still safe (hooksecurefunc doesn't cause taint),
    -- but the actual hiding must be deferred.
    local canModifyNow = not (InCombatLockdown and InCombatLockdown())
    if feedbackFrame._ScootPowerFeedbackHidden and canModifyNow then
        -- Stop any running animations and hide the frame
        if feedbackFrame.StopFeedbackAnim then
            pcall(feedbackFrame.StopFeedbackAnim, feedbackFrame)
        end
        -- Hide the textures that make up the feedback animation
        if feedbackFrame.BarTexture then
            pcall(feedbackFrame.BarTexture.Hide, feedbackFrame.BarTexture)
        end
        if feedbackFrame.LossGlowTexture then
            pcall(feedbackFrame.LossGlowTexture.Hide, feedbackFrame.LossGlowTexture)
        end
        if feedbackFrame.GainGlowTexture then
            pcall(feedbackFrame.GainGlowTexture.Hide, feedbackFrame.GainGlowTexture)
        end
        -- NOTE: Do NOT override StartFeedbackAnim - method overrides cause persistent taint
        -- that propagates to the parent StatusBar and causes "blocked from an action" errors.
        -- The animation textures are already hidden above; if they flash briefly, use a
        -- hooksecurefunc to re-hide them after the animation starts:
        -- CRITICAL: This hook MUST have a combat guard because it can fire during form changes
        -- (e.g., druid cat->human) which triggers nameplate updates. Calling Hide()/StopFeedbackAnim()
        -- during combat taints the execution context, blocking SetTargetClampingInsets().
        if _G.hooksecurefunc and not feedbackFrame._ScootFeedbackHooked then
            feedbackFrame._ScootFeedbackHooked = true
            _G.hooksecurefunc(feedbackFrame, "StartFeedbackAnim", function(self, ...)
                -- CRITICAL: Skip during combat to avoid tainting nameplate operations
                if InCombatLockdown and InCombatLockdown() then return end
                if self._ScootPowerFeedbackHidden then
                    -- Re-hide the textures after the animation shows them
                    if self.BarTexture and self.BarTexture.Hide then pcall(self.BarTexture.Hide, self.BarTexture) end
                    if self.LossGlowTexture and self.LossGlowTexture.Hide then pcall(self.LossGlowTexture.Hide, self.LossGlowTexture) end
                    if self.GainGlowTexture and self.GainGlowTexture.Hide then pcall(self.GainGlowTexture.Hide, self.GainGlowTexture) end
                    if self.StopFeedbackAnim then pcall(self.StopFeedbackAnim, self) end
                end
            end)
        end
    else
        -- Restore visibility - the frame will show naturally when StartFeedbackAnim is called
    end
end
Util.SetPowerFeedbackHidden = SetPowerFeedbackHidden

-- Hide/show the Power Bar Spark (e.g., Elemental Shaman Maelstrom indicator)
-- Frame: ManaBar.Spark
-- ownerFrame: the ManaBar frame that contains the Spark child
-- hidden: boolean - true to hide the spark, false to restore it
--
-- IMPORTANT: Uses SetAlpha(0) instead of Hide() to persist through combat.
-- SetAlpha is a purely cosmetic operation that doesn't taint, so we can
-- safely enforce it even during combat when Blizzard's UpdateShown fires.
local function SetPowerBarSparkHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local sparkFrame = ownerFrame.Spark
    if not sparkFrame or (sparkFrame.IsForbidden and sparkFrame:IsForbidden()) then
        return
    end
    
    if hidden then
        -- Mark as hidden and set alpha to 0
        sparkFrame._ScootPowerBarSparkHidden = true
        if sparkFrame.SetAlpha then
            pcall(sparkFrame.SetAlpha, sparkFrame, 0)
        end
        
        -- Install hooks once to re-enforce alpha=0 when Blizzard tries to show the spark
        if _G.hooksecurefunc and not sparkFrame._ScootSparkVisibilityHooked then
            sparkFrame._ScootSparkVisibilityHooked = true
            
            -- Hook Show() - Blizzard may call this directly
            _G.hooksecurefunc(sparkFrame, "Show", function(self)
                if self._ScootPowerBarSparkHidden and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)
            
            -- Hook UpdateShown() - Called frequently by Blizzard's spark logic
            if sparkFrame.UpdateShown then
                _G.hooksecurefunc(sparkFrame, "UpdateShown", function(self)
                    if self._ScootPowerBarSparkHidden and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end
            
            -- Hook SetAlpha() - Re-enforce alpha=0 when Blizzard tries to change it
            _G.hooksecurefunc(sparkFrame, "SetAlpha", function(self, alpha)
                if self._ScootPowerBarSparkHidden and alpha and alpha > 0 then
                    -- Defer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                    if not self._ScootSparkAlphaDeferred then
                        self._ScootSparkAlphaDeferred = true
                        C_Timer.After(0, function()
                            self._ScootSparkAlphaDeferred = nil
                            if self._ScootPowerBarSparkHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
    else
        -- Mark as visible and restore alpha
        sparkFrame._ScootPowerBarSparkHidden = false
        if sparkFrame.SetAlpha then
            pcall(sparkFrame.SetAlpha, sparkFrame, 1)
        end
        -- Let Blizzard's UpdateShown manage visibility from here
        if sparkFrame.UpdateShown then
            pcall(sparkFrame.UpdateShown, sparkFrame)
        end
    end
end
Util.SetPowerBarSparkHidden = SetPowerBarSparkHidden

-- Hide/show the Over Absorb Glow on the Player Health Bar
-- This glow appears on the edge of the health bar when absorb shields exceed max health.
-- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.OverAbsorbGlow
-- ownerFrame: the HealthBar frame that contains the OverAbsorbGlow child
-- hidden: boolean - true to hide the glow, false to restore it
local function SetOverAbsorbGlowHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local glowFrame = ownerFrame.OverAbsorbGlow
    if not glowFrame or (glowFrame.IsForbidden and glowFrame:IsForbidden()) then
        return
    end
    glowFrame._ScootOverAbsorbGlowHidden = not not hidden
    if glowFrame._ScootOverAbsorbGlowHidden then
        -- Hide the glow
        if glowFrame.Hide then
            pcall(glowFrame.Hide, glowFrame)
        end
        if glowFrame.SetAlpha then
            pcall(glowFrame.SetAlpha, glowFrame, 0)
        end
        -- NOTE: Do NOT override Show() on this frame - method overrides cause persistent taint
        -- that propagates to the parent StatusBar and causes "blocked from an action" errors.
        -- SetAlpha(0) is sufficient to make the glow invisible even if Blizzard shows it.
        --
        -- If the glow becomes visible despite alpha 0, use hooksecurefunc instead:
        -- hooksecurefunc(glowFrame, "Show", function(self) if self._ScootOverAbsorbGlowHidden then self:SetAlpha(0) end end)
    else
        -- Restore visibility - the glow will show naturally when Blizzard calls Show
        if glowFrame.SetAlpha then
            pcall(glowFrame.SetAlpha, glowFrame, 1)
        end
    end
end
Util.SetOverAbsorbGlowHidden = SetOverAbsorbGlowHidden

function addon.ApplyIconBorderStyle(frame, styleKey, opts)
    if not frame then return "none" end

    Util.CleanupIconBorderAttachments(frame)

    local targetFrame = frame
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        local parent = frame:GetParent() or UIParent
        local container = frame.ScooterIconBorderContainer
        if not container then
            container = CreateFrame("Frame", nil, parent)
            frame.ScooterIconBorderContainer = container
            container:EnableMouse(false)
        end
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        local strata = parent.GetFrameStrata and parent:GetFrameStrata() or "HIGH"
        container:SetFrameStrata(strata)
        local baseLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 0
        container:SetFrameLevel(baseLevel + 5)
        targetFrame = container
    end

    Util.ResetIconBorderTarget(targetFrame)
    if targetFrame ~= frame then
        Util.ResetIconBorderTarget(frame)
    end

    local key = styleKey or "square"

    local styleDef = addon.IconBorders and addon.IconBorders.GetStyle(key)
    local tintEnabled = opts and opts.tintEnabled
    local requestedColor = opts and opts.color
    local dbTable = opts and opts.db
    local thicknessKey = opts and opts.thicknessKey
    local tintColorKey = opts and opts.tintColorKey
    local defaultThicknessSetting = opts and opts.defaultThickness or 1
    local thickness = tonumber(opts and opts.thickness) or defaultThicknessSetting
    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

    if not styleDef then
        if addon.Borders and addon.Borders.ApplySquare then
            addon.Borders.ApplySquare(targetFrame, {
                size = thickness,
                color = tintEnabled and requestedColor or {0, 0, 0, 1},
                layer = "OVERLAY",
                layerSublevel = 7,
            })
        end
        return "square"
    end

    if styleDef.type == "none" then
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
        return "none"
    end

    if styleDef.allowThicknessInset and dbTable and thicknessKey then
        local stored = tonumber(dbTable[thicknessKey])
        if stored then
            thickness = stored
        end
        if styleDef.defaultThickness and styleDef.defaultThickness ~= defaultThicknessSetting then
            if not stored or stored == defaultThicknessSetting then
                thickness = styleDef.defaultThickness
                dbTable[thicknessKey] = thickness
            end
        end
    elseif dbTable and thicknessKey then
        dbTable[thicknessKey] = thickness
    end

    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

    if dbTable and thicknessKey then
        dbTable[thicknessKey] = thickness
    end

    local function copyColor(color)
        if type(color) ~= "table" then
            return {1, 1, 1, 1}
        end
        return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    end

    local defaultColor = copyColor(styleDef.defaultColor or (styleDef.type == "square" and {0, 0, 0, 1}) or {1, 1, 1, 1})
    if type(requestedColor) ~= "table" then
        if dbTable and tintColorKey and type(dbTable[tintColorKey]) == "table" then
            requestedColor = dbTable[tintColorKey]
        else
            requestedColor = defaultColor
        end
    end

    local baseColor = copyColor(defaultColor)
    local tintColor = copyColor(requestedColor)
    local baseApplyColor = copyColor(baseColor)
    if styleDef.type == "square" then
        baseApplyColor = tintEnabled and tintColor or baseColor
    end

    local function clamp(val, min, max)
        if val < min then return min end
        if val > max then return max end
        return val
    end

    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    -- Get the borderInset from opts (negative = expand outward, positive = shrink inward)
    local insetValue = tonumber(opts and opts.inset) or 0
    local insetAdjust = 0
    if styleDef.allowThicknessInset then
        -- For custom art borders: use borderInset directly (thickness no longer affects expand)
        -- Positive inset = shrink border inward (reduce expand), negative = expand outward
        insetAdjust = -insetValue
    else
        -- For square borders: inset also applies
        insetAdjust = -insetValue
    end
    local expandX = clamp(baseExpandX + insetAdjust, -8, 8)
    local expandY = clamp(baseExpandY + insetAdjust, -8, 8)

    local appliedTexture

    if styleDef.type == "atlas" then
        addon.Borders.ApplyAtlas(targetFrame, {
            atlas = styleDef.atlas,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = targetFrame.ScootAtlasBorder
    elseif styleDef.type == "texture" then
        addon.Borders.ApplyTexture(targetFrame, {
            texture = styleDef.texture,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = targetFrame.ScootTextureBorder
    else
        addon.Borders.ApplySquare(targetFrame, {
            size = thickness,
            color = baseApplyColor or {0, 0, 0, 1},
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
            expandX = expandX,
            expandY = expandY,
        })
        local container = targetFrame.ScootSquareBorderContainer or targetFrame
        local edges = (container and container.ScootSquareBorderEdges) or targetFrame.ScootSquareBorderEdges
        if edges then
            for _, edge in pairs(edges) do
                if edge and edge.SetColorTexture then
                    edge:SetColorTexture(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, (baseApplyColor[4] == nil and 1) or baseApplyColor[4])
                end
            end
        end
        if targetFrame.ScootAtlasBorderTintOverlay then targetFrame.ScootAtlasBorderTintOverlay:Hide() end
        if targetFrame.ScootTextureBorderTintOverlay then targetFrame.ScootTextureBorderTintOverlay:Hide() end
    end

    if appliedTexture then
        if styleDef.type == "square" and baseApplyColor then
            appliedTexture:SetVertexColor(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, baseApplyColor[4] or 1)
        else
            appliedTexture:SetVertexColor(baseColor[1] or 1, baseColor[2] or 1, baseColor[3] or 1, baseColor[4] or 1)
        end
        appliedTexture:SetAlpha(baseColor[4] or 1)
        if appliedTexture.SetDesaturated then pcall(appliedTexture.SetDesaturated, appliedTexture, false) end
        if appliedTexture.SetBlendMode then pcall(appliedTexture.SetBlendMode, appliedTexture, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end

        local overlay
        if styleDef.type == "atlas" then
            overlay = targetFrame.ScootAtlasBorderTintOverlay
        elseif styleDef.type == "texture" then
            overlay = targetFrame.ScootTextureBorderTintOverlay
        end

        local function clampSublevel(val)
            if val == nil then return nil end
            if val > 7 then return 7 end
            if val < -8 then return -8 end
            return val
        end

        local function ensureOverlay()
            if overlay and overlay:IsObjectType("Texture") then return overlay end
            local layer, sublevel = appliedTexture:GetDrawLayer()
            layer = layer or (styleDef.layer or "OVERLAY")
            sublevel = clampSublevel((sublevel or (styleDef.layerSublevel or 7)) + 1) or clampSublevel((styleDef.layerSublevel or 7))
            local tex = targetFrame:CreateTexture(nil, layer)
            tex:SetDrawLayer(layer, sublevel or 0)
            tex:SetAllPoints(appliedTexture)
            tex:SetVertexColor(1, 1, 1, 1)
            tex:Hide()
            if styleDef.type == "atlas" then
                targetFrame.ScootAtlasBorderTintOverlay = tex
            else
                targetFrame.ScootTextureBorderTintOverlay = tex
            end
            return tex
        end

        if tintEnabled then
            overlay = ensureOverlay()
            local layer, sublevel = appliedTexture:GetDrawLayer()
            local desiredSub = clampSublevel((sublevel or 0) + 1)
            if layer then overlay:SetDrawLayer(layer, desiredSub or clampSublevel(sublevel) or 0) end
            overlay:ClearAllPoints()
            overlay:SetAllPoints(appliedTexture)
            local r = tintColor[1] or 1
            local g = tintColor[2] or 1
            local b = tintColor[3] or 1
            local a = tintColor[4] or 1
            if styleDef.type == "atlas" and styleDef.atlas then
                overlay:SetAtlas(styleDef.atlas, true)
            elseif styleDef.type == "texture" and styleDef.texture then
                overlay:SetTexture(styleDef.texture)
            end
            local avg = (r + g + b) / 3
            local blend = styleDef.tintBlendMode or ((avg >= 0.85) and "ADD" or "BLEND")
            if overlay.SetBlendMode then pcall(overlay.SetBlendMode, overlay, blend) end
            if overlay.SetDesaturated then pcall(overlay.SetDesaturated, overlay, (avg >= 0.85)) end
            overlay:SetVertexColor(r, g, b, a)
            overlay:SetAlpha(a)
            overlay:Show()
            appliedTexture:SetAlpha(0)
        else
            local overlays = {
                frame.ScootAtlasBorderTintOverlay,
                frame.ScootTextureBorderTintOverlay,
            }
            for _, ov in ipairs(overlays) do
                if ov then
                    ov:Hide()
                    if ov.SetTexture then pcall(ov.SetTexture, ov, nil) end
                    if ov.SetAtlas then pcall(ov.SetAtlas, ov, nil) end
                    if ov.SetVertexColor then pcall(ov.SetVertexColor, ov, 1, 1, 1, 0) end
                    if ov.SetBlendMode then pcall(ov.SetBlendMode, ov, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end
                end
            end

            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end

            if styleDef.type == "atlas" and styleDef.atlas then
                addon.Borders.ApplyAtlas(frame, {
                    atlas = styleDef.atlas,
                    color = baseColor,
                    tintColor = baseColor,
                    expandX = expandX,
                    expandY = expandY,
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
                appliedTexture = frame.ScootAtlasBorder
            elseif styleDef.type == "texture" and styleDef.texture then
                addon.Borders.ApplyTexture(frame, {
                    texture = styleDef.texture,
                    color = baseColor,
                    tintColor = baseColor,
                    expandX = expandX,
                    expandY = expandY,
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
                appliedTexture = frame.ScootTextureBorder
            else
                addon.Borders.ApplySquare(frame, {
                    size = thickness,
                    color = baseColor or {0, 0, 0, 1},
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
            end

            if appliedTexture then
                appliedTexture:SetAlpha(baseColor[4] or 1)
                if appliedTexture.SetDesaturated then pcall(appliedTexture.SetDesaturated, appliedTexture, false) end
                if appliedTexture.SetBlendMode then pcall(appliedTexture.SetBlendMode, appliedTexture, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end
                appliedTexture:SetVertexColor(baseColor[1] or 1, baseColor[2] or 1, baseColor[3] or 1, baseColor[4] or 1)
            end
        end
    end

    return styleDef.type
end

local Component = {}
Component.__index = Component

function Component:New(o)
    o = o or {}
    return setmetatable(o, self)
end

function Component:SyncEditModeSettings()
    local frame = _G[self.frameName]
    if not frame then return end

    local changed = false
    for settingId, setting in pairs(self.settings) do
        if type(setting) == "table" and setting.type == "editmode" then
            if addon.EditMode.SyncEditModeSettingToComponent(self, settingId) then
                changed = true
            end
        end
    end

    return changed
end

addon.ComponentPrototype = Component

function addon:RegisterComponent(component)
    self.Components[component.id] = component
end

function addon:RegisterComponentInitializer(initializer)
    if type(initializer) ~= "function" then return end
    table.insert(self.ComponentInitializers, initializer)
end

function addon:InitializeComponents()
    if wipe then
        wipe(self.Components)
    else
        self.Components = {}
    end

    for _, initializer in ipairs(self.ComponentInitializers) do
        pcall(initializer, self)
    end
end

function addon:LinkComponentsToDB()
    for id, component in pairs(self.Components) do
        if not self.db.profile.components[id] then
            self.db.profile.components[id] = {}
        end
        component.db = self.db.profile.components[id]
    end
end

function addon:ApplyStyles()
    -- CRITICAL: Do NOT apply styles during combat - many styling functions call
    -- SetStatusBarTexture, SetVertexColor, SetShown, etc. on protected Blizzard frames,
    -- which taints them and causes "blocked from an action" errors.
    if InCombatLockdown and InCombatLockdown() then
        -- Defer styling until combat ends
        if not self._pendingApplyStyles then
            self._pendingApplyStyles = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    for id, component in pairs(self.Components) do
        if component.ApplyStyling then
            component:ApplyStyling()
        end
    end
    if addon.ApplyAllUnitFrameHealthTextVisibility then
        addon.ApplyAllUnitFrameHealthTextVisibility()
    end
    if addon.ApplyAllUnitFramePowerTextVisibility then
        addon.ApplyAllUnitFramePowerTextVisibility()
    end
    if addon.ApplyAllUnitFrameNameLevelText then
        addon.ApplyAllUnitFrameNameLevelText()
    end
    if addon.ApplyAllUnitFrameBarTextures then
        addon.ApplyAllUnitFrameBarTextures()
    end
    if addon.ApplyAllUnitFramePortraits then
        addon.ApplyAllUnitFramePortraits()
    end
	if addon.ApplyAllUnitFrameClassResources then
		addon.ApplyAllUnitFrameClassResources()
	end
    if addon.ApplyAllUnitFrameCastBars then
        addon.ApplyAllUnitFrameCastBars()
    end
    if addon.ApplyAllUnitFrameBuffsDebuffs then
        addon.ApplyAllUnitFrameBuffsDebuffs()
    end
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
    end
    if addon.ApplyAllThreatMeterVisibility then
        addon.ApplyAllThreatMeterVisibility()
    end
    if addon.ApplyTargetBossIconVisibility then
        addon.ApplyTargetBossIconVisibility()
    end
    if addon.ApplyAllPlayerMiscVisibility then
        addon.ApplyAllPlayerMiscVisibility()
    end
    if addon.ApplyAllUnitFrameScaleMults then
        addon.ApplyAllUnitFrameScaleMults()
    end
    -- Group Frames: Apply raid frame health bar styling
    if addon.ApplyRaidFrameHealthBarStyle then
        addon.ApplyRaidFrameHealthBarStyle()
    end
    -- Group Frames: Apply raid frame text styling
    if addon.ApplyRaidFrameTextStyle then
        addon.ApplyRaidFrameTextStyle()
    end
end

function addon:ApplyEarlyComponentStyles()
    for id, component in pairs(self.Components) do
        if component.ApplyStyling and component.applyDuringInit then
            component:ApplyStyling()
        end
    end
end

function addon:ResetComponentToDefaults(componentOrId)
    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end

    if not component then
        return false, "component_missing"
    end

    if not component.db then
        if type(self.LinkComponentsToDB) == "function" then
            self:LinkComponentsToDB()
        end
    end

    if not component.db then
        return false, "component_db_unavailable"
    end

    local seen = {}
    for settingId, setting in pairs(component.settings or {}) do
        if type(setting) == "table" then
            seen[settingId] = true
            if setting.default ~= nil then
                component.db[settingId] = CopyDefaultValue(setting.default)
            else
                component.db[settingId] = nil
            end
        end
    end

    for key in pairs(component.db) do
        if not seen[key] then
            component.db[key] = nil
        end
    end

    if self.EditMode and self.EditMode.ResetComponentPositionToDefault then
        self.EditMode.ResetComponentPositionToDefault(component)
    end

    if self.EditMode and self.EditMode.SyncComponentToEditMode then
        self.EditMode.SyncComponentToEditMode(component)
    end

    if self.ApplyStyles then
        self:ApplyStyles()
    end

    return true
end

function addon:ResetUnitFrameCategoryToDefaults(categoryKey)
    if type(categoryKey) ~= "string" then
        return false, "invalid_category"
    end

    local unit = UNIT_FRAME_CATEGORY_TO_UNIT[categoryKey]
    if not unit then
        return false, "unknown_unit"
    end

    local profile = self.db and self.db.profile
    if not profile then
        return false, "db_unavailable"
    end

    if profile.unitFrames then
        profile.unitFrames[unit] = nil
        local hasAny = false
        for _ in pairs(profile.unitFrames) do
            hasAny = true
            break
        end
        if not hasAny then
            profile.unitFrames = nil
        end
    end

    if self.EditMode and self.EditMode.ResetUnitFramePosition then
        self.EditMode.ResetUnitFramePosition(unit)
    end

    if self.ApplyUnitFrameBarTexturesFor then
        self.ApplyUnitFrameBarTexturesFor(unit)
    end
    if self.ApplyUnitFrameHealthTextVisibilityFor then
        self.ApplyUnitFrameHealthTextVisibilityFor(unit)
    end
    if self.ApplyUnitFramePowerTextVisibilityFor then
        self.ApplyUnitFramePowerTextVisibilityFor(unit)
    end
    if self.ApplyUnitFrameNameLevelTextFor then
        self.ApplyUnitFrameNameLevelTextFor(unit)
    end
    if self.ApplyUnitFramePortraitFor then
        self.ApplyUnitFramePortraitFor(unit)
    end
    if self.ApplyUnitFrameCastBarFor then
        self.ApplyUnitFrameCastBarFor(unit)
    end
    if self.ApplyUnitFrameBuffsDebuffsFor then
        self.ApplyUnitFrameBuffsDebuffsFor(unit)
    end
    if self.ApplyUnitFrameVisibilityFor then
        self.ApplyUnitFrameVisibilityFor(unit)
    end

    return true
end

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for _, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            if component:SyncEditModeSettings() then
                anyChanged = true
            end
        end
        if addon.EditMode.SyncComponentPositionFromEditMode then
            if addon.EditMode.SyncComponentPositionFromEditMode(component) then
                anyChanged = true
            end
        end
    end

    return anyChanged
end


