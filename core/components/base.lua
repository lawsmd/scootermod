local addonName, addon = ...

addon.Components = addon.Components or {}
addon.ComponentInitializers = addon.ComponentInitializers or {}
addon.ComponentsUtil = addon.ComponentsUtil or {}

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

local function getIconBorderContainer(frame)
    local st = getState(frame)
    return st and st.ScooterIconBorderContainer or nil
end

local function setIconBorderContainer(frame, container)
    local st = getState(frame)
    if st then
        st.ScooterIconBorderContainer = container
    end
end

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
    cleanup(getIconBorderContainer(icon))
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

function addon.ApplyIconBorderStyle(frame, styleKey, opts)
    if not frame then return "none" end

    Util.CleanupIconBorderAttachments(frame)

    local targetFrame = frame
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        local parent = frame:GetParent() or UIParent
        local container = getIconBorderContainer(frame)
        if not container then
            container = CreateFrame("Frame", nil, parent)
            setIconBorderContainer(frame, container)
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
    -- Zero‑Touch: do not create per-component SavedVariables tables just by linking.
    -- Only assign existing persisted tables; otherwise leave component.db nil.
    local profile = self.db and self.db.profile
    local components = profile and rawget(profile, "components") or nil
    for id, component in pairs(self.Components) do
        local persisted = components and rawget(components, id) or nil
        if persisted then
            component.db = persisted
        else
            -- Provide a lightweight proxy so UI code can read/write without nil checks.
            -- Reads return nil (so UI falls back to defaults). First write creates the real table.
            if not component._ScootDBProxy then
                local proxy = {}
                setmetatable(proxy, {
                    __index = function(_, key)
                        local real = component.db
                        if real and real ~= proxy then
                            return real[key]
                        end
                        return nil
                    end,
                    __newindex = function(_, key, value)
                        local realDb = addon:EnsureComponentDB(component)
                        if realDb then
                            rawset(realDb, key, value)
                        end
                    end,
                    __pairs = function()
                        local real = component.db
                        if real and real ~= proxy then
                            return pairs(real)
                        end
                        return function() return nil end
                    end,
                })
                component._ScootDBProxy = proxy
            end
            component.db = component._ScootDBProxy
        end
    end
end

function addon:EnsureComponentDB(componentOrId)
    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end
    if not component or not component.id then
        return nil
    end
    local profile = self.db and self.db.profile
    if not profile then
        return nil
    end
    local components = rawget(profile, "components")
    if type(components) ~= "table" then
        components = {}
        profile.components = components
    end
    local db = rawget(components, component.id)
    if type(db) ~= "table" then
        db = {}
        components[component.id] = db
    end
    component.db = db
    return db
end

function addon:ClearFrameLevelState()
    -- Best-effort hot cleanup when switching into a Zero‑Touch/empty profile without reload.
    -- This cannot fully restore Blizzard baselines (only a reload can), but it prevents
    -- our persistent hook flags from continuing to enforce hidden states.
    local function safeAlpha(fs)
        if fs and fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
    end
    local function clearTextFlags(fs)
        if not fs then return end
        -- Clear FrameState hidden flags (uses lookup table instead of writing to frames)
        local fstate = ensureFS()
        if fstate then
            fstate.SetHidden(fs, "healthText", false)
            fstate.SetHidden(fs, "powerText", false)
            fstate.SetHidden(fs, "healthTextCenter", false)
            fstate.SetHidden(fs, "powerTextCenter", false)
            fstate.SetHidden(fs, "totName", false)
            fstate.SetHidden(fs, "altPowerText", false)
        end
        safeAlpha(fs)
    end

    -- Clear cached fontstring references and their flags (if available this session).
    if self._ufHealthTextFonts then
        for _, cache in pairs(self._ufHealthTextFonts) do
            clearTextFlags(cache and cache.leftFS)
            clearTextFlags(cache and cache.rightFS)
            clearTextFlags(cache and cache.textStringFS)
        end
    end
    if self._ufPowerTextFonts then
        for _, cache in pairs(self._ufPowerTextFonts) do
            clearTextFlags(cache and cache.leftFS)
            clearTextFlags(cache and cache.rightFS)
            clearTextFlags(cache and cache.textStringFS)
        end
    end

    -- Clear some well-known globals defensively (covers cases where caches weren't built).
    clearTextFlags(_G.PlayerFrameHealthBarTextLeft)
    clearTextFlags(_G.PlayerFrameHealthBarTextRight)
    clearTextFlags(_G.PlayerFrameManaBarTextLeft)
    clearTextFlags(_G.PlayerFrameManaBarTextRight)
    clearTextFlags(_G.PetFrameHealthBarTextLeft)
    clearTextFlags(_G.PetFrameHealthBarTextRight)
    clearTextFlags(_G.PetFrameManaBarTextLeft)
    clearTextFlags(_G.PetFrameManaBarTextRight)

    -- Clear baseline caches so future applies recapture from the current Blizzard state.
    self._ufTextBaselines = nil
    self._ufPowerTextBaselines = nil
    self._ufNameLevelTextBaselines = nil
    self._ufNameContainerBaselines = nil
    self._ufNameBackdropBaseWidth = nil
    self._ufToTNameTextBaseline = nil

    -- Drop caches so visibility-only hooks won't run expensive work and will re-resolve later.
    self._ufHealthTextFonts = nil
    self._ufPowerTextFonts = nil
end

function addon:ApplyStyles()
    -- CRITICAL: Do NOT apply styles during combat - many styling functions call
    -- SetStatusBarTexture, SetVertexColor, SetShown, etc. on protected Blizzard frames,
    -- which taints them and causes "blocked from an action" errors.
    if InCombatLockdown and InCombatLockdown() then
        -- Ensure cast bar persistence hooks are installed even if we defer full styling.
        -- This is a visual-only hook path and is safe to install during combat.
        if addon.EnsureAllUnitFrameCastBarHooks then
            addon.EnsureAllUnitFrameCastBarHooks()
        end
        -- Defer styling until combat ends
        if not self._pendingApplyStyles then
            self._pendingApplyStyles = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    local profile = self.db and self.db.profile
    local componentsCfg = profile and rawget(profile, "components") or nil
    for id, component in pairs(self.Components) do
        -- Zero‑Touch: only apply component styling when the component has an explicit
        -- SavedVariables table (i.e., the user has configured it).
        local hasConfig = componentsCfg and rawget(componentsCfg, id) ~= nil
        if hasConfig and component.ApplyStyling then
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
    if addon.ApplyPetFrameVisibility then
        addon.ApplyPetFrameVisibility()
    end
	-- Unit Frames: Off-screen drag unlock (Player + Target)
	if addon.ApplyAllUnitFrameOffscreenUnlocks then
		addon.ApplyAllUnitFrameOffscreenUnlocks()
	end
    if addon.ApplyAllUnitFrameScaleMults then
        addon.ApplyAllUnitFrameScaleMults()
    end
    -- ToT/FocusTarget: Apply scale and position (not Edit Mode managed)
    if addon.ApplyAllToTSettings then
        addon.ApplyAllToTSettings()
    end
    if addon.ApplyAllFocusTargetSettings then
        addon.ApplyAllFocusTargetSettings()
    end
    -- Group Frames: Apply raid frame health bar styling
    if addon.ApplyRaidFrameHealthBarStyle then
        addon.ApplyRaidFrameHealthBarStyle()
    end
    -- Group Frames: Apply raid frame status text styling
    if addon.ApplyRaidFrameStatusTextStyle then
        addon.ApplyRaidFrameStatusTextStyle()
    end
    -- Group Frames: Apply raid group title styling (Group Numbers)
    if addon.ApplyRaidFrameGroupTitlesStyle then
        addon.ApplyRaidFrameGroupTitlesStyle()
    end
    -- Group Frames: Apply raid frame combat-safe overlays
    if addon.ApplyRaidFrameHealthOverlays then
        addon.ApplyRaidFrameHealthOverlays()
    end
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
    -- Group Frames: Apply party frame health bar styling
    if addon.ApplyPartyFrameHealthBarStyle then
        addon.ApplyPartyFrameHealthBarStyle()
    end
    -- Group Frames: Apply party frame title styling (Party Title)
    if addon.ApplyPartyFrameTitleStyle then
        addon.ApplyPartyFrameTitleStyle()
    end
    -- Group Frames: Apply party frame combat-safe overlays
    if addon.ApplyPartyFrameHealthOverlays then
        addon.ApplyPartyFrameHealthOverlays()
    end
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
    -- Group Frames: Apply party frame visibility settings (over absorb glow, etc.)
    if addon.ApplyPartyOverAbsorbGlowVisibility then
        addon.ApplyPartyOverAbsorbGlowVisibility()
    end
    -- Group Frames: Apply party frame health bar borders
    if addon.ApplyPartyFrameHealthBarBorders then
        addon.ApplyPartyFrameHealthBarBorders()
    end
    -- Group Frames: Apply raid frame health bar borders
    if addon.ApplyRaidFrameHealthBarBorders then
        addon.ApplyRaidFrameHealthBarBorders()
    end
end

function addon:ApplyEarlyComponentStyles()
    local profile = self.db and self.db.profile
    local componentsCfg = profile and rawget(profile, "components") or nil
    for id, component in pairs(self.Components) do
        local hasConfig = componentsCfg and rawget(componentsCfg, id) ~= nil
        if hasConfig and component.ApplyStyling and component.applyDuringInit then
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
        if type(self.EnsureComponentDB) == "function" then
            self:EnsureComponentDB(component)
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
        self.EditMode.SyncComponentToEditMode(component, { skipApply = true })
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


