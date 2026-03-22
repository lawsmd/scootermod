--------------------------------------------------------------------------------
-- bars/vehicles.lua
-- Vehicle/AlternatePower frame texture enforcement + Show hooks.
-- Re-enforces hiding of VehicleFrameTexture and AlternatePowerFrameTexture
-- after Blizzard art transitions (vehicle enter/exit).
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

-- OPT-28: Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Enforce VehicleFrameTexture visibility based on Use Custom Borders setting
local function EnforceVehicleFrameTextureVisibility()
    if isEditModeActive() then return end
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames") or nil
    local cfg = unitFrames and rawget(unitFrames, "Player") or nil
    if not cfg then return end
    if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled

    local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
    local vehicleTex = container and container.VehicleFrameTexture
    if vehicleTex and vehicleTex.SetShown then
        pcall(vehicleTex.SetShown, vehicleTex, false)
    end
end

-- Enforce AlternatePowerFrameTexture visibility based on Use Custom Borders setting
local function EnforceAlternatePowerFrameTextureVisibility()
    if isEditModeActive() then return end
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames") or nil
    local cfg = unitFrames and rawget(unitFrames, "Player") or nil
    if not cfg then return end
    if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled

    local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
    local altTex = container and container.AlternatePowerFrameTexture
    if altTex and altTex.SetShown then
        pcall(altTex.SetShown, altTex, false)
    end
end

-- Hook Blizzard's vehicle art transitions to re-enforce hiding.

if not addon._VehicleArtHooksInstalled then
    addon._VehicleArtHooksInstalled = true

    -- Hook PlayerFrame_ToVehicleArt to re-enforce VehicleFrameTexture hiding
    -- Called when entering a vehicle (Blizzard shows VehicleFrameTexture)
    if _G.hooksecurefunc and type(_G.PlayerFrame_ToVehicleArt) == "function" then
        _G.hooksecurefunc("PlayerFrame_ToVehicleArt", function()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, EnforceVehicleFrameTextureVisibility)
            else
                EnforceVehicleFrameTextureVisibility()
            end
        end)
    end

    -- Hook PlayerFrame_ToPlayerArt to re-enforce AlternatePowerFrameTexture hiding
    -- Called when exiting a vehicle (Blizzard shows AlternatePowerFrameTexture)
    if _G.hooksecurefunc and type(_G.PlayerFrame_ToPlayerArt) == "function" then
        _G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, EnforceAlternatePowerFrameTextureVisibility)
            else
                EnforceAlternatePowerFrameTextureVisibility()
            end
        end)
    end

    -- Install Show() hooks directly on the textures for extra coverage.
    -- Catches ANY Show() call, not just those from known Blizzard functions.
    local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer

    -- VehicleFrameTexture Show() hook
    local vehicleTex = container and container.VehicleFrameTexture
    if vehicleTex and not getProp(vehicleTex, "showHooked") then
        setProp(vehicleTex, "showHooked", true)
        hooksecurefunc(vehicleTex, "Show", function(self)
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames") or nil
            local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
            if cfgP and cfgP.useCustomBorders == true then
                if self.Hide then pcall(self.Hide, self) end
            end
        end)
    end

    -- AlternatePowerFrameTexture Show() hook
    local altTex = container and container.AlternatePowerFrameTexture
    if altTex and not getProp(altTex, "showHooked") then
        setProp(altTex, "showHooked", true)
        hooksecurefunc(altTex, "Show", function(self)
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames") or nil
            local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
            if cfgP and cfgP.useCustomBorders == true then
                if self.Hide then pcall(self.Hide, self) end
            end
        end)
    end
end
