-- lsm.lua - LibSharedMedia-3.0 registration
local addonName, addon = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
addon.LSM = LSM
addon.LSMAvailable = (LSM ~= nil)

local LSM_PREFIX = "lsm:"
addon.LSM_PREFIX = LSM_PREFIX

function addon.IsLSMKey(key)
    return type(key) == "string" and key:sub(1, 4) == LSM_PREFIX
end

function addon.LSMKeyToName(key)
    if addon.IsLSMKey(key) then
        return key:sub(5)
    end
    return key
end

function addon.LSMNameToKey(name)
    return LSM_PREFIX .. name
end

function addon.LSMFetch(mediatype, key)
    if not LSM then return nil end
    local name = addon.IsLSMKey(key) and addon.LSMKeyToName(key) or key
    local path = LSM:Fetch(mediatype, name, true) -- true = noDefault
    return path
end
