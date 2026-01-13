--------------------------------------------------------------------------------
-- bars/preemptive.lua
-- Pre-emptive hiding functions and early hook installation
--
-- These functions hide elements BEFORE Blizzard's Update runs, preventing
-- visual "flashes" that occur when relying solely on post-update hooks.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Resolvers = addon.BarsResolvers
local Alpha = addon.BarsAlpha

-- Create module namespace
addon.BarsPreemptive = addon.BarsPreemptive or {}
local Preemptive = addon.BarsPreemptive

--------------------------------------------------------------------------------
-- Pre-emptive Hiding for Target/Focus Frame Elements
--------------------------------------------------------------------------------
-- Called SYNCHRONOUSLY from PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
-- event handlers. Hides elements BEFORE Blizzard's TargetFrame_Update runs.

-- Pre-emptive hide for Target frame elements (ReputationColor, FrameTexture, Flash)
-- This runs SYNCHRONOUSLY from PLAYER_TARGET_CHANGED, BEFORE Blizzard's TargetFrame_Update.
-- The texture might not exist yet at this moment, so we also schedule a micro-delay follow-up.
function Preemptive.hideTargetElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Target")
    if not cfg then return end

    -- Shared computeAlpha for enforcers - re-reads config each call
    local function computeAlpha()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target")
        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
    end

    -- Helper to hide ReputationColor and install enforcer
    local function hideRepColor()
        local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
            if Alpha and Alpha.hookAlphaEnforcer then
                Alpha.hookAlphaEnforcer(repColor, computeAlpha)
            end
        end
    end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        -- Immediate hide (texture may not exist yet)
        hideRepColor()

        -- Hide frame texture immediately
        local ft = Resolvers.resolveUnitFrameFrameTexture("Target")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end

        -- Hide Flash (aggro/threat glow) immediately
        local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
            and _G.TargetFrame.TargetFrameContainer.Flash
        if targetFlash and targetFlash.SetAlpha then
            pcall(targetFlash.SetAlpha, targetFlash, 0)
        end

        -- Schedule a micro-delay follow-up to catch the texture if Blizzard creates it
        -- AFTER our synchronous pre-emptive hide but BEFORE the main deferred styling pass.
        -- This closes the timing gap where ReputationColor becomes visible briefly.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, hideRepColor)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        local ft = Resolvers.resolveUnitFrameFrameTexture("Target")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end
    end
end

-- Pre-emptive hide for Focus frame elements (ReputationColor, FrameTexture, Flash)
-- This runs SYNCHRONOUSLY from PLAYER_FOCUS_CHANGED, BEFORE Blizzard's FocusFrame_Update.
-- The texture might not exist yet at this moment, so we also schedule a micro-delay follow-up.
function Preemptive.hideFocusElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Focus")
    if not cfg then return end

    -- Shared computeAlpha for enforcers - re-reads config each call
    local function computeAlpha()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Focus")
        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
    end

    -- Helper to hide ReputationColor and install enforcer
    local function hideRepColor()
        local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
            if Alpha and Alpha.hookAlphaEnforcer then
                Alpha.hookAlphaEnforcer(repColor, computeAlpha)
            end
        end
    end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        -- Immediate hide (texture may not exist yet)
        hideRepColor()

        -- Hide frame texture immediately
        local ft = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end

        -- Hide Flash (aggro/threat glow) immediately
        local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
            and _G.FocusFrame.TargetFrameContainer.Flash
        if focusFlash and focusFlash.SetAlpha then
            pcall(focusFlash.SetAlpha, focusFlash, 0)
        end

        -- Schedule a micro-delay follow-up to catch the texture if Blizzard creates it
        -- AFTER our synchronous pre-emptive hide but BEFORE the main deferred styling pass.
        -- This closes the timing gap where ReputationColor becomes visible briefly.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, hideRepColor)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        local ft = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Early Alpha Hook Installation
--------------------------------------------------------------------------------
-- Install alpha enforcement hooks on Target/Focus frame elements during
-- PLAYER_ENTERING_WORLD, BEFORE the first target is acquired.

function Preemptive.installEarlyAlphaHooks()
    -- Helper to compute alpha based on useCustomBorders setting
    local function makeComputeAlpha(unit)
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
            return (cfg2 and cfg2.useCustomBorders) and 0 or 1
        end
    end

    local function makeComputeAlphaWithBorder(unit)
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
            local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
            return hide and 0 or 1
        end
    end

    -- Target frame elements
    do
        -- ReputationColor
        local targetRepColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if targetRepColor and not targetRepColor._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(targetRepColor, makeComputeAlpha("Target"))
        end

        -- FrameTexture
        local targetFT = Resolvers.resolveUnitFrameFrameTexture("Target")
        if targetFT and not targetFT._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(targetFT, makeComputeAlphaWithBorder("Target"))
        end

        -- Flash (aggro/threat glow)
        local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
            and _G.TargetFrame.TargetFrameContainer.Flash
        if targetFlash and not targetFlash._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(targetFlash, makeComputeAlpha("Target"))
        end
    end

    -- Focus frame elements
    do
        -- ReputationColor
        local focusRepColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if focusRepColor and not focusRepColor._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(focusRepColor, makeComputeAlpha("Focus"))
        end

        -- FrameTexture
        local focusFT = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if focusFT and not focusFT._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(focusFT, makeComputeAlphaWithBorder("Focus"))
        end

        -- Flash (aggro/threat glow)
        local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
            and _G.FocusFrame.TargetFrameContainer.Flash
        if focusFlash and not focusFlash._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(focusFlash, makeComputeAlpha("Focus"))
        end
    end

    -- Also do initial hide pass for currently configured settings
    Preemptive.hideTargetElements()
    Preemptive.hideFocusElements()

    -- Install hooks on Blizzard's TargetFrame_Update and FocusFrame_Update to catch
    -- any updates that might show ReputationColor during combat or target changes.
    -- These run AFTER Blizzard's update, so we re-hide immediately.
    if _G.hooksecurefunc and type(_G.TargetFrame_Update) == "function" then
        if not addon._ScootTargetFrameUpdateHooked then
            addon._ScootTargetFrameUpdateHooked = true
            _G.hooksecurefunc("TargetFrame_Update", function()
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames")
                local cfg = unitFrames and rawget(unitFrames, "Target")
                if cfg and cfg.useCustomBorders then
                    local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if repColor and repColor.SetAlpha then
                        pcall(repColor.SetAlpha, repColor, 0)
                        -- Ensure enforcer is installed on this (possibly new) object
                        if Alpha and Alpha.hookAlphaEnforcer then
                            Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha("Target"))
                        end
                    end
                end
            end)
        end
    end

    if _G.hooksecurefunc and type(_G.FocusFrame_Update) == "function" then
        if not addon._ScootFocusFrameUpdateHooked then
            addon._ScootFocusFrameUpdateHooked = true
            _G.hooksecurefunc("FocusFrame_Update", function()
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames")
                local cfg = unitFrames and rawget(unitFrames, "Focus")
                if cfg and cfg.useCustomBorders then
                    local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if repColor and repColor.SetAlpha then
                        pcall(repColor.SetAlpha, repColor, 0)
                        -- Ensure enforcer is installed on this (possibly new) object
                        if Alpha and Alpha.hookAlphaEnforcer then
                            Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha("Focus"))
                        end
                    end
                end
            end)
        end
    end

    --------------------------------------------------------------------------------
    -- CRITICAL: Hook CheckFaction method directly on TargetFrame/FocusFrame
    --------------------------------------------------------------------------------
    -- When UNIT_FACTION fires (e.g., neutral mob becomes hostile), Blizzard calls
    -- CheckFaction() and CheckLevel() DIRECTLY - NOT through Update(). This means
    -- our TargetFrame_Update hook never fires. We must hook these methods directly.

    -- Helper to re-hide elements after CheckFaction/CheckLevel
    -- This handles ReputationColor, Flash, AND LevelText/NameText
    local function rehideTargetElements()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Target")
        if not cfg then return end

        -- Re-hide ReputationColor (if useCustomBorders is enabled)
        if cfg.useCustomBorders then
            local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetAlpha then
                pcall(repColor.SetAlpha, repColor, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha("Target"))
                end
            end

            -- Re-hide Flash (threat glow)
            local flash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
                and _G.TargetFrame.TargetFrameContainer.Flash
            if flash and flash.SetAlpha then
                pcall(flash.SetAlpha, flash, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(flash, makeComputeAlpha("Target"))
                end
            end
        end

        -- Re-hide LevelText (if levelTextHidden is enabled)
        -- CheckLevel() calls levelText:Show() which overrides our hiding
        if cfg.levelTextHidden == true then
            local levelFS = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
            if levelFS and levelFS.SetShown then
                pcall(levelFS.SetShown, levelFS, false)
            end
        end

        -- Re-hide NameText (if nameTextHidden is enabled)
        if cfg.nameTextHidden == true then
            local nameFS = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.Name
            if nameFS and nameFS.SetShown then
                pcall(nameFS.SetShown, nameFS, false)
            end
        end
    end

    local function rehideFocusElements()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Focus")
        if not cfg then return end

        -- Re-hide ReputationColor (if useCustomBorders is enabled)
        if cfg.useCustomBorders then
            local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetAlpha then
                pcall(repColor.SetAlpha, repColor, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha("Focus"))
                end
            end

            -- Re-hide Flash (threat glow)
            local flash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
                and _G.FocusFrame.TargetFrameContainer.Flash
            if flash and flash.SetAlpha then
                pcall(flash.SetAlpha, flash, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(flash, makeComputeAlpha("Focus"))
                end
            end
        end

        -- Re-hide LevelText (if levelTextHidden is enabled)
        -- CheckLevel() calls levelText:Show() which overrides our hiding
        if cfg.levelTextHidden == true then
            local levelFS = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
            if levelFS and levelFS.SetShown then
                pcall(levelFS.SetShown, levelFS, false)
            end
        end

        -- Re-hide NameText (if nameTextHidden is enabled)
        if cfg.nameTextHidden == true then
            local nameFS = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.Name
            if nameFS and nameFS.SetShown then
                pcall(nameFS.SetShown, nameFS, false)
            end
        end
    end

    -- Hook CheckFaction on TargetFrame (called when UNIT_FACTION fires)
    if _G.TargetFrame and _G.TargetFrame.CheckFaction and not addon._ScootTargetCheckFactionHooked then
        addon._ScootTargetCheckFactionHooked = true
        _G.hooksecurefunc(_G.TargetFrame, "CheckFaction", rehideTargetElements)
    end

    -- Hook CheckLevel on TargetFrame (also called when UNIT_FACTION fires)
    if _G.TargetFrame and _G.TargetFrame.CheckLevel and not addon._ScootTargetCheckLevelHooked then
        addon._ScootTargetCheckLevelHooked = true
        _G.hooksecurefunc(_G.TargetFrame, "CheckLevel", rehideTargetElements)
    end

    -- Hook CheckFaction on FocusFrame
    if _G.FocusFrame and _G.FocusFrame.CheckFaction and not addon._ScootFocusCheckFactionHooked then
        addon._ScootFocusCheckFactionHooked = true
        _G.hooksecurefunc(_G.FocusFrame, "CheckFaction", rehideFocusElements)
    end

    -- Hook CheckLevel on FocusFrame
    if _G.FocusFrame and _G.FocusFrame.CheckLevel and not addon._ScootFocusCheckLevelHooked then
        addon._ScootFocusCheckLevelHooked = true
        _G.hooksecurefunc(_G.FocusFrame, "CheckLevel", rehideFocusElements)
    end

    --------------------------------------------------------------------------------
    -- Hook SetVertexColor on ReputationColor for extra robustness
    --------------------------------------------------------------------------------
    -- CheckFaction calls SetVertexColor to change the reputation strip color.
    -- If Blizzard changes the color, we know they're updating the texture,
    -- so we should re-enforce our alpha hiding.

    local targetRepColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
    if targetRepColor and targetRepColor.SetVertexColor and not targetRepColor._ScootSetVertexColorHooked then
        targetRepColor._ScootSetVertexColorHooked = true
        _G.hooksecurefunc(targetRepColor, "SetVertexColor", function(self)
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames")
            local cfg = unitFrames and rawget(unitFrames, "Target")
            if cfg and cfg.useCustomBorders and self and self.SetAlpha then
                pcall(self.SetAlpha, self, 0)
            end
        end)
    end

    local focusRepColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
    if focusRepColor and focusRepColor.SetVertexColor and not focusRepColor._ScootSetVertexColorHooked then
        focusRepColor._ScootSetVertexColorHooked = true
        _G.hooksecurefunc(focusRepColor, "SetVertexColor", function(self)
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames")
            local cfg = unitFrames and rawget(unitFrames, "Focus")
            if cfg and cfg.useCustomBorders and self and self.SetAlpha then
                pcall(self.SetAlpha, self, 0)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Pre-emptive Hiding for Boss Frame Elements
--------------------------------------------------------------------------------
-- Boss frames (Boss1TargetFrame through Boss5TargetFrame) can appear/update
-- during combat. Unlike Target/Focus which have dedicated PLAYER_X_CHANGED events,
-- Boss frames update via INSTANCE_ENCOUNTER_ENGAGE_UNIT and UPDATE_BOSS_FRAMES.
-- These events fire during combat, but our handlers currently skip applying
-- during combat lockdown. These functions provide direct hooks to catch updates.

-- Pre-emptive hide for all Boss frame elements (ReputationColor, FrameTexture, Flash)
function Preemptive.hideBossElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Boss")
    if not cfg then return end

    -- Shared computeAlpha for enforcers - re-reads config each call
    local function computeAlpha()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Boss")
        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
    end

    local function computeAlphaWithBorder()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Boss")
        local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
        return hide and 0 or 1
    end

    -- Helper to hide ReputationColor on a specific Boss frame and install enforcer
    local function hideRepColorOnBoss(bossFrame)
        if not bossFrame then return end
        local repColor = bossFrame.TargetFrameContent
            and bossFrame.TargetFrameContent.TargetFrameContentMain
            and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
            if Alpha and Alpha.hookAlphaEnforcer then
                Alpha.hookAlphaEnforcer(repColor, computeAlpha)
            end
        end
    end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            if bossFrame then
                -- Hide ReputationColor immediately
                hideRepColorOnBoss(bossFrame)

                -- Hide FrameTexture immediately
                local ft = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                if ft and ft.SetAlpha then
                    pcall(ft.SetAlpha, ft, 0)
                    if Alpha and Alpha.hookAlphaEnforcer then
                        Alpha.hookAlphaEnforcer(ft, computeAlphaWithBorder)
                    end
                end

                -- Hide Flash (aggro/threat glow) immediately
                local flash = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.Flash
                if flash and flash.SetAlpha then
                    pcall(flash.SetAlpha, flash, 0)
                    if Alpha and Alpha.hookAlphaEnforcer then
                        Alpha.hookAlphaEnforcer(flash, computeAlpha)
                    end
                end
            end
        end

        -- Schedule a micro-delay follow-up to catch textures if Blizzard creates them
        -- AFTER our synchronous pre-emptive hide
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                for i = 1, 5 do
                    local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                    hideRepColorOnBoss(bossFrame)
                end
            end)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            if bossFrame then
                local ft = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                if ft and ft.SetAlpha then
                    pcall(ft.SetAlpha, ft, 0)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Boss Frame Hook Installation
--------------------------------------------------------------------------------
-- Install hooks on Boss frame methods to catch updates during combat.

function Preemptive.installBossFrameHooks()
    local function makeComputeAlpha()
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, "Boss")
            return (cfg2 and cfg2.useCustomBorders) and 0 or 1
        end
    end

    -- Helper to re-hide Boss elements after Blizzard updates
    local function rehideBossElements()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Boss")
        if not cfg or not cfg.useCustomBorders then return end

        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            if bossFrame then
                -- Re-hide ReputationColor
                local repColor = bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                if repColor and repColor.SetAlpha then
                    pcall(repColor.SetAlpha, repColor, 0)
                    if Alpha and Alpha.hookAlphaEnforcer then
                        Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha())
                    end
                end

                -- Re-hide Flash
                local flash = bossFrame.TargetFrameContainer
                    and bossFrame.TargetFrameContainer.Flash
                if flash and flash.SetAlpha then
                    pcall(flash.SetAlpha, flash, 0)
                end
            end
        end
    end

    -- Install hooks on individual Boss frames
    for i = 1, 5 do
        local bossFrame = _G["Boss" .. i .. "TargetFrame"]
        if bossFrame then
            -- Hook OnShow to re-hide elements when the frame becomes visible
            if not bossFrame._ScootBossOnShowHooked then
                bossFrame._ScootBossOnShowHooked = true
                bossFrame:HookScript("OnShow", function()
                    -- Small delay to let Blizzard finish setting up the frame
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, rehideBossElements)
                    else
                        rehideBossElements()
                    end
                end)
            end

            -- Hook CheckFaction if it exists (called when faction/reputation updates)
            if bossFrame.CheckFaction and not bossFrame._ScootBossCheckFactionHooked then
                bossFrame._ScootBossCheckFactionHooked = true
                _G.hooksecurefunc(bossFrame, "CheckFaction", rehideBossElements)
            end

            -- Hook SetVertexColor on ReputationColor for extra robustness
            local repColor = bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetVertexColor and not repColor._ScootSetVertexColorHooked then
                repColor._ScootSetVertexColorHooked = true
                _G.hooksecurefunc(repColor, "SetVertexColor", function(self)
                    local db = addon and addon.db and addon.db.profile
                    local unitFrames = db and rawget(db, "unitFrames")
                    local cfg = unitFrames and rawget(unitFrames, "Boss")
                    if cfg and cfg.useCustomBorders and self and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end

            -- Install early alpha enforcer on ReputationColor
            if repColor and not repColor._ScootAlphaEnforcerHooked then
                Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha())
            end
        end
    end

    -- Hook BossTargetFrameContainer's UpdateShownState if available
    -- This is called when boss frames are shown/hidden during encounters
    local container = _G.BossTargetFrameContainer
    if container and container.UpdateShownState and not addon._ScootBossContainerUpdateHooked then
        addon._ScootBossContainerUpdateHooked = true
        _G.hooksecurefunc(container, "UpdateShownState", function()
            -- Small delay to let Blizzard finish updating
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, rehideBossElements)
            else
                rehideBossElements()
            end
        end)
    end

    -- Do initial hide pass for currently configured settings
    Preemptive.hideBossElements()
end

-- Expose to addon namespace for backwards compatibility
addon.PreemptiveHideTargetElements = Preemptive.hideTargetElements
addon.PreemptiveHideFocusElements = Preemptive.hideFocusElements
addon.PreemptiveHideBossElements = Preemptive.hideBossElements
addon.InstallEarlyUnitFrameAlphaHooks = Preemptive.installEarlyAlphaHooks
addon.InstallBossFrameHooks = Preemptive.installBossFrameHooks

return Preemptive
