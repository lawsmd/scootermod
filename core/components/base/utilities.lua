local addonName, addon = ...

-- Import FrameState helpers from core.lua (promoted via addon.ComponentsUtil._*)
local ensureFS = addon.ComponentsUtil._ensureFS
local getState = addon.ComponentsUtil._getState
local getProp = addon.ComponentsUtil._getProp
local setProp = addon.ComponentsUtil._setProp

local Util = addon.ComponentsUtil

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
            local applyState = frame and getProp(frame, "fullPowerApplyState") or nil
            if frame and getProp(frame, "fullPowerPendingReapply") and applyState then
                setProp(frame, "fullPowerPendingReapply", nil)
                applyState()
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
    -- Use accessor functions for CDM bars (weak-key tables), fall back to direct read for Unit Frame bars
    local mediaState = addon.Media and addon.Media.GetBarFrameState and addon.Media.GetBarFrameState(barFrame)
    local scooterModBG = (mediaState and mediaState.bg) or barFrame.ScooterModBG
    local borderHolder = (addon.BarBorders and addon.BarBorders.GetBorderHolder and addon.BarBorders.GetBorderHolder(barFrame)) or barFrame.ScooterStyledBorder
    for _, region in ipairs({ barFrame:GetRegions() }) do
        if region and region ~= scooterModBG and region ~= borderHolder and region ~= (borderHolder and borderHolder.Texture) then
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
        local st = getState(target)
        if not st then return end
        if not st.fullPowerOrigWidth then
            if target.GetWidth then
                local ok, w = pcall(target.GetWidth, target)
                if ok and w and w > 0 then
                    st.fullPowerOrigWidth = w
                end
            end
        end
        if not st.fullPowerOrigHeight then
            if target.GetHeight then
                local ok, h = pcall(target.GetHeight, target)
                if ok and h and h > 0 then
                    st.fullPowerOrigHeight = h
                end
            end
        end
        if not st.fullPowerOrigScale then
            if target.GetScale then
                local ok, s = pcall(target.GetScale, target)
                if ok and s and s > 0 then
                    st.fullPowerOrigScale = s
                end
            end
        end
        if st.fullPowerOrigAlpha == nil and target.GetAlpha then
            local ok, a = pcall(target.GetAlpha, target)
            if ok and a ~= nil then
                st.fullPowerOrigAlpha = a
            end
        end
    end

    local function applySize(target, desiredScale)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        local st = getState(target)
        if not st then return end
        local baseWidth = st.fullPowerOrigWidth
        local baseHeight = st.fullPowerOrigHeight
        local baseScale = st.fullPowerOrigScale

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
            local restoreAlpha = getProp(target, "fullPowerOrigAlpha")
            if restoreAlpha == nil then
                -- Default baseline: AlertSpikeStay/BigSpikeGlow start at alpha 0.
                restoreAlpha = 0
            end
            if target.SetAlpha then pcall(target.SetAlpha, target, restoreAlpha) end
        end
    end

    local function ensureCaptured()
        if getProp(fullPowerFrame, "fullPowerCaptured") then
            return
        end
        setProp(fullPowerFrame, "fullPowerCaptured", true)
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
        local storedScale = getProp(fullPowerFrame, "fullPowerLatestScale") or 1
        local hidden = not not getProp(fullPowerFrame, "fullPowerHidden")
        applyAll(storedScale, hidden)
    end

    setProp(fullPowerFrame, "fullPowerLatestScale", scaleY)
    if getProp(fullPowerFrame, "fullPowerHidden") == nil then
        setProp(fullPowerFrame, "fullPowerHidden", false)
    end
    setProp(fullPowerFrame, "fullPowerApplyState", applyState)
    -- CRITICAL: Guard against combat. If ApplyFullPowerSpikeScale is called during combat
    -- (e.g., via PRD ApplyStyling triggered by form change), calling applyState() would
    -- modify frames (SetSize, SetAlpha, etc.) and taint the execution context, causing
    -- SetTargetClampingInsets() to be blocked. Defer to after combat.
    if InCombatLockdown and InCombatLockdown() then
        setProp(fullPowerFrame, "fullPowerPendingReapply", true)
        queueFullPowerFrameReapply(fullPowerFrame)
    else
        applyState()
    end

    if type(hooksecurefunc) == "function" and not getProp(fullPowerFrame, "fullPowerHooks") then
        setProp(fullPowerFrame, "fullPowerHooks", true)
        -- CRITICAL: Guard against combat to prevent taint. When these hooks fire during
        -- Blizzard's nameplate setup chain (e.g., druid form change in combat), any frame
        -- modifications (SetSize, SetAlpha, etc.) taint the execution context, causing
        -- SetTargetClampingInsets() to be blocked. See DEBUG.md for details.
        local function reapply()
            if InCombatLockdown and InCombatLockdown() then
                -- Defer to after combat - queue for PLAYER_REGEN_ENABLED
                setProp(fullPowerFrame, "fullPowerPendingReapply", true)
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
    setProp(fullPowerFrame, "fullPowerHidden", not not hidden)
    -- CRITICAL: Guard against combat. Stopping animations and calling applyState() during combat
    -- would taint the execution context, causing SetTargetClampingInsets() to be blocked.
    if InCombatLockdown and InCombatLockdown() then
        -- Just store the hidden state; it will be applied after combat via queued reapply
        setProp(fullPowerFrame, "fullPowerPendingReapply", true)
        queueFullPowerFrameReapply(fullPowerFrame)
        return
    end
    if getProp(fullPowerFrame, "fullPowerHidden") then
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
    local applyState = getProp(fullPowerFrame, "fullPowerApplyState")
    if applyState then
        applyState()
    else
        Util.ApplyFullPowerSpikeScale(ownerFrame, getProp(fullPowerFrame, "fullPowerLatestScale") or 1)
        local applyState2 = getProp(fullPowerFrame, "fullPowerApplyState")
        if applyState2 then
            applyState2()
        end
    end
end
Util.SetFullPowerSpikeHidden = SetFullPowerSpikeHidden

-- Hide/show the Power Bar FeedbackFrame (Builder/Spender animation that flashes when power is spent/gained)
-- This frame shows a quick flash representing the amount of energy/mana/etc. spent or gained.
-- ownerFrame: the ManaBar or ClassNameplateManaBarFrame that contains the FeedbackFrame child
-- hidden: boolean - true to hide the feedback animation, false to restore it
--
-- APPROACH: Set alpha=0 on the FeedbackFrame parent container.
-- Parent frame alpha multiplies with child alpha values, making all child textures invisible.
local function SetPowerFeedbackHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local feedbackFrame = ownerFrame.FeedbackFrame
    if not feedbackFrame or (feedbackFrame.IsForbidden and feedbackFrame:IsForbidden()) then
        return
    end

    setProp(feedbackFrame, "powerFeedbackHidden", not not hidden)

    if feedbackFrame.SetAlpha then
        feedbackFrame:SetAlpha(hidden and 0 or 1)
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
        setProp(sparkFrame, "powerBarSparkHidden", true)
        if sparkFrame.SetAlpha then
            pcall(sparkFrame.SetAlpha, sparkFrame, 0)
        end

        -- Install hooks once to re-enforce alpha=0 when Blizzard tries to show the spark
        if _G.hooksecurefunc and not getProp(sparkFrame, "sparkVisibilityHooked") then
            setProp(sparkFrame, "sparkVisibilityHooked", true)

            -- Hook Show() - Blizzard may call this directly
            _G.hooksecurefunc(sparkFrame, "Show", function(self)
                if getProp(self, "powerBarSparkHidden") and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)

            -- Hook UpdateShown() - Called frequently by Blizzard's spark logic
            if sparkFrame.UpdateShown then
                _G.hooksecurefunc(sparkFrame, "UpdateShown", function(self)
                    if getProp(self, "powerBarSparkHidden") and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end

            -- Hook SetAlpha() - Re-enforce alpha=0 when Blizzard tries to change it
            -- CRITICAL: Use immediate re-enforcement with recursion guard, NOT C_Timer.After(0)
            -- Deferring causes visible flickering (texture visible for one frame before hiding)
            _G.hooksecurefunc(sparkFrame, "SetAlpha", function(self, alpha)
                if getProp(self, "powerBarSparkHidden") and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        -- Mark as visible and restore alpha
        setProp(sparkFrame, "powerBarSparkHidden", false)
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

-- Hide/show the Mana Cost Prediction overlay bar (Player only)
-- This bar shows the predicted mana/power cost of the currently casting spell.
-- Frame: ManaBar.ManaCostPredictionBar
-- ownerFrame: the ManaBar frame that contains the ManaCostPredictionBar child
-- hidden: boolean - true to hide the prediction bar, false to restore it
--
-- IMPORTANT: Uses SetAlpha(0) instead of Hide() to persist through combat.
-- SetAlpha is a purely cosmetic operation that doesn't taint.
local function SetManaCostPredictionHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local predictionBar = ownerFrame.ManaCostPredictionBar
    if not predictionBar or (predictionBar.IsForbidden and predictionBar:IsForbidden()) then
        return
    end

    if hidden then
        -- Mark as hidden and set alpha to 0
        setProp(predictionBar, "manaCostPredictionHidden", true)
        if predictionBar.SetAlpha then
            pcall(predictionBar.SetAlpha, predictionBar, 0)
        end

        -- Install hooks once to re-enforce alpha=0 when Blizzard tries to show the prediction bar
        if _G.hooksecurefunc and not getProp(predictionBar, "manaCostPredictionHooked") then
            setProp(predictionBar, "manaCostPredictionHooked", true)

            -- Hook Show() - Blizzard may call this directly
            _G.hooksecurefunc(predictionBar, "Show", function(self)
                if getProp(self, "manaCostPredictionHidden") and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)

            -- Hook SetAlpha() - Re-enforce alpha=0 when Blizzard tries to change it
            -- CRITICAL: Use immediate re-enforcement with recursion guard, NOT C_Timer.After(0)
            -- Deferring causes visible flickering (texture visible for one frame before hiding)
            _G.hooksecurefunc(predictionBar, "SetAlpha", function(self, alpha)
                if getProp(self, "manaCostPredictionHidden") and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        -- Mark as visible and restore alpha
        setProp(predictionBar, "manaCostPredictionHidden", false)
        if predictionBar.SetAlpha then
            pcall(predictionBar.SetAlpha, predictionBar, 1)
        end
    end
end
Util.SetManaCostPredictionHidden = SetManaCostPredictionHidden

-- Hide/show only the Power Bar textures (fill + background) while keeping text visible
-- This enables a "number-only" display mode like WeakAuras used to provide.
-- ownerFrame: the ManaBar/PowerBar frame
-- hidden: boolean - true to hide textures only, false to restore them
--
-- IMPORTANT: Uses SetAlpha(0) with persistent hooks to survive combat and Blizzard updates.
-- SetAlpha is cosmetic and doesn't taint, so we can enforce it during combat.
local function SetPowerBarTextureOnlyHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end

    -- Resolve the fill texture: prefer .texture named child, fall back to GetStatusBarTexture()
    local fillTex = ownerFrame.texture or (ownerFrame.GetStatusBarTexture and ownerFrame:GetStatusBarTexture())
    -- Resolve background texture
    local bgTex = ownerFrame.Background
    -- Player-only overlay: Mana cost prediction bar (new Blizzard visual that sits on top of the power bar)
    -- Frame path (player): PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaCostPredictionBar
    local manaCostPredictionBar = ownerFrame.ManaCostPredictionBar

    -- Helper to install alpha enforcement hooks on a texture
    local function installAlphaHook(tex, flagName)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flagName .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        -- Hook SetAlpha with immediate re-enforcement using a recursion guard
        -- CRITICAL: Do NOT use C_Timer.After(0, ...) here - that defers to the next frame,
        -- causing visible flickering. Immediate enforcement with a guard flag ensures
        -- the texture stays hidden within the same Lua execution tick.
        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end

        -- Also hook Show() in case Blizzard calls it
        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        -- Mark textures as hidden and set alpha to 0
        if fillTex then
            setProp(fillTex, "powerBarFillHidden", true)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 0) end
            installAlphaHook(fillTex, "powerBarFillHidden")
        end

        if bgTex then
            setProp(bgTex, "powerBarBGHidden", true)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 0) end
            installAlphaHook(bgTex, "powerBarBGHidden")
        end

        -- Also hide Blizzard's mana cost prediction overlay bar (player only).
        -- We hide the whole overlay frame via alpha=0; parent alpha multiplication keeps all child textures hidden.
        if manaCostPredictionBar then
            setProp(manaCostPredictionBar, "powerBarManaCostPredHidden", true)
            if manaCostPredictionBar.SetAlpha then
                pcall(manaCostPredictionBar.SetAlpha, manaCostPredictionBar, 0)
            end
            installAlphaHook(manaCostPredictionBar, "powerBarManaCostPredHidden")
        end

        -- Also hide ScooterMod's custom background if present
        if ownerFrame.ScooterModBG then
            setProp(ownerFrame.ScooterModBG, "powerBarScootBGHidden", true)
            if ownerFrame.ScooterModBG.SetAlpha then pcall(ownerFrame.ScooterModBG.SetAlpha, ownerFrame.ScooterModBG, 0) end
            installAlphaHook(ownerFrame.ScooterModBG, "powerBarScootBGHidden")
        end

        -- Also hide the power foreground overlay if present
        local st = getState(ownerFrame)
        if st and st.powerFill then
            st.powerFill:Hide()
        end
    else
        -- Mark textures as visible and restore alpha
        if fillTex then
            setProp(fillTex, "powerBarFillHidden", false)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 1) end
        end

        if bgTex then
            setProp(bgTex, "powerBarBGHidden", false)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 1) end
        end

        if manaCostPredictionBar then
            setProp(manaCostPredictionBar, "powerBarManaCostPredHidden", false)
            if manaCostPredictionBar.SetAlpha then
                pcall(manaCostPredictionBar.SetAlpha, manaCostPredictionBar, 1)
            end
        end

        if ownerFrame.ScooterModBG then
            setProp(ownerFrame.ScooterModBG, "powerBarScootBGHidden", false)
            -- Don't restore alpha here - let the background styling code handle it
        end

        -- Restore power foreground overlay if it's active
        local st = getState(ownerFrame)
        if st and st.powerFill and st.powerOverlayActive then
            st.powerFill:Show()
        end
    end
end
Util.SetPowerBarTextureOnlyHidden = SetPowerBarTextureOnlyHidden

-- Hide/restore the Health Bar fill texture and background while keeping text overlays visible.
-- Mirrors SetPowerBarTextureOnlyHidden but uses health-specific flag names.
local function SetHealthBarTextureOnlyHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end

    local fillTex = ownerFrame.texture or (ownerFrame.GetStatusBarTexture and ownerFrame:GetStatusBarTexture())
    local bgTex = ownerFrame.Background or ownerFrame.background

    local function installAlphaHook(tex, flagName)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flagName .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        if fillTex then
            setProp(fillTex, "healthBarFillHidden", true)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 0) end
            installAlphaHook(fillTex, "healthBarFillHidden")
        end

        if bgTex then
            setProp(bgTex, "healthBarBGHidden", true)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 0) end
            installAlphaHook(bgTex, "healthBarBGHidden")
        end

        if ownerFrame.ScooterModBG then
            setProp(ownerFrame.ScooterModBG, "healthBarScootBGHidden", true)
            if ownerFrame.ScooterModBG.SetAlpha then pcall(ownerFrame.ScooterModBG.SetAlpha, ownerFrame.ScooterModBG, 0) end
            installAlphaHook(ownerFrame.ScooterModBG, "healthBarScootBGHidden")
        end
    else
        if fillTex then
            setProp(fillTex, "healthBarFillHidden", false)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 1) end
        end

        if bgTex then
            setProp(bgTex, "healthBarBGHidden", false)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 1) end
        end

        if ownerFrame.ScooterModBG then
            setProp(ownerFrame.ScooterModBG, "healthBarScootBGHidden", false)
        end
    end
end
Util.SetHealthBarTextureOnlyHidden = SetHealthBarTextureOnlyHidden

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
    setProp(glowFrame, "overAbsorbGlowHidden", not not hidden)

    -- Capture original alpha once so we can restore it when un-hiding.
    if glowFrame.GetAlpha and getProp(glowFrame, "overAbsorbGlowOrigAlpha") == nil then
        local ok, a = pcall(glowFrame.GetAlpha, glowFrame)
        setProp(glowFrame, "overAbsorbGlowOrigAlpha", ok and (a or 1) or 1)
    end

    -- IMPORTANT: Do NOT call Hide()/Show() on this frame.
    -- Hide/Show on protected unitframe children is taint-prone and can later surface as blocked
    -- calls in unrelated Blizzard code paths (e.g., AlternatePowerBar:Hide()).
    --
    -- Approach: enforce invisibility with SetAlpha(0) and persistent hooks.
    if getProp(glowFrame, "overAbsorbGlowHidden") then
        if glowFrame.SetAlpha then
            pcall(glowFrame.SetAlpha, glowFrame, 0)
        end

        if _G.hooksecurefunc and not getProp(glowFrame, "overAbsorbGlowVisibilityHooked") then
            setProp(glowFrame, "overAbsorbGlowVisibilityHooked", true)

            _G.hooksecurefunc(glowFrame, "Show", function(self)
                if getProp(self, "overAbsorbGlowHidden") and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)

            _G.hooksecurefunc(glowFrame, "SetAlpha", function(self, alpha)
                if getProp(self, "overAbsorbGlowHidden") and alpha and alpha > 0 and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        -- Restore alpha; allow Blizzard's visibility logic to drive Show/Hide naturally.
        if glowFrame.SetAlpha then
            local restoreAlpha = getProp(glowFrame, "overAbsorbGlowOrigAlpha")
            if restoreAlpha == nil then restoreAlpha = 1 end
            pcall(glowFrame.SetAlpha, glowFrame, restoreAlpha)
        end
    end
end
Util.SetOverAbsorbGlowHidden = SetOverAbsorbGlowHidden

-- Hide/show the Heal Prediction bar on the Player Health Bar
-- This bar appears when you or a party member is casting a heal on you.
-- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.MyHealPredictionBar
-- ownerFrame: the HealthBar frame that contains the MyHealPredictionBar child
-- hidden: boolean - true to hide the bar, false to restore it
local function SetHealPredictionHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local predictionFrame = ownerFrame.MyHealPredictionBar
    if not predictionFrame or (predictionFrame.IsForbidden and predictionFrame:IsForbidden()) then
        return
    end
    setProp(predictionFrame, "healPredictionHidden", not not hidden)

    -- Capture original alpha once so we can restore it when un-hiding.
    if predictionFrame.GetAlpha and getProp(predictionFrame, "healPredictionOrigAlpha") == nil then
        local ok, a = pcall(predictionFrame.GetAlpha, predictionFrame)
        setProp(predictionFrame, "healPredictionOrigAlpha", ok and (a or 1) or 1)
    end

    -- IMPORTANT: Do NOT call Hide()/Show() on this frame.
    -- Hide/Show on protected unitframe children is taint-prone and can later surface as blocked
    -- calls in unrelated Blizzard code paths.
    --
    -- Approach: enforce invisibility with SetAlpha(0) and persistent hooks.
    if getProp(predictionFrame, "healPredictionHidden") then
        if predictionFrame.SetAlpha then
            pcall(predictionFrame.SetAlpha, predictionFrame, 0)
        end

        if _G.hooksecurefunc and not getProp(predictionFrame, "healPredictionVisibilityHooked") then
            setProp(predictionFrame, "healPredictionVisibilityHooked", true)

            _G.hooksecurefunc(predictionFrame, "Show", function(self)
                if getProp(self, "healPredictionHidden") and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)

            _G.hooksecurefunc(predictionFrame, "SetAlpha", function(self, alpha)
                if getProp(self, "healPredictionHidden") and alpha and alpha > 0 and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        -- Restore alpha; allow Blizzard's visibility logic to drive Show/Hide naturally.
        if predictionFrame.SetAlpha then
            local restoreAlpha = getProp(predictionFrame, "healPredictionOrigAlpha")
            if restoreAlpha == nil then restoreAlpha = 1 end
            pcall(predictionFrame.SetAlpha, predictionFrame, restoreAlpha)
        end
    end
end
Util.SetHealPredictionHidden = SetHealPredictionHidden

--- Hide/show the Health Loss Animation bar on the Player Health Bar
--- This bar shows the dark red "damage taken" animation that fades out.
--- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
--- ownerFrame: the HealthBar frame whose parent (HealthBarsContainer) contains the AnimatedLoss sibling
--- hidden: boolean - true to hide the bar, false to restore it
local function SetHealthLossAnimationHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    -- AnimatedLossBar is a sibling of HealthBar in HealthBarsContainer, not a child
    local parent = ownerFrame.GetParent and ownerFrame:GetParent()
    local animatedLossBar = parent and parent.PlayerFrameHealthBarAnimatedLoss
    if not animatedLossBar or (animatedLossBar.IsForbidden and animatedLossBar:IsForbidden()) then
        return
    end
    setProp(animatedLossBar, "healthLossAnimHidden", not not hidden)

    -- Capture original alpha once so we can restore it when un-hiding.
    if animatedLossBar.GetAlpha and getProp(animatedLossBar, "healthLossAnimOrigAlpha") == nil then
        local ok, a = pcall(animatedLossBar.GetAlpha, animatedLossBar)
        setProp(animatedLossBar, "healthLossAnimOrigAlpha", ok and (a or 1) or 1)
    end

    -- IMPORTANT: Do NOT call Hide()/Show() on this frame.
    -- Hide/Show on protected unitframe children is taint-prone and can later surface as blocked
    -- calls in unrelated Blizzard code paths.
    --
    -- Approach: enforce invisibility with SetAlpha(0) and persistent hooks.
    if getProp(animatedLossBar, "healthLossAnimHidden") then
        if animatedLossBar.SetAlpha then
            pcall(animatedLossBar.SetAlpha, animatedLossBar, 0)
        end

        if _G.hooksecurefunc and not getProp(animatedLossBar, "healthLossAnimVisibilityHooked") then
            setProp(animatedLossBar, "healthLossAnimVisibilityHooked", true)

            _G.hooksecurefunc(animatedLossBar, "Show", function(self)
                if getProp(self, "healthLossAnimHidden") and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)

            _G.hooksecurefunc(animatedLossBar, "SetAlpha", function(self, alpha)
                if getProp(self, "healthLossAnimHidden") and alpha and alpha > 0 then
                    -- Re-apply alpha 0 to enforce invisibility
                    if not getProp(self, "healthLossAnimSettingAlpha") then
                        setProp(self, "healthLossAnimSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "healthLossAnimSettingAlpha", nil)
                    end
                end
            end)
        end
    else
        -- Restore original alpha
        if animatedLossBar.SetAlpha then
            local restoreAlpha = getProp(animatedLossBar, "healthLossAnimOrigAlpha")
            if restoreAlpha == nil then restoreAlpha = 1 end
            pcall(animatedLossBar.SetAlpha, animatedLossBar, restoreAlpha)
        end
    end
end
Util.SetHealthLossAnimationHidden = SetHealthLossAnimationHidden
