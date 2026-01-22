-- framestate.lua - Centralized state tracking for Blizzard frames
-- Uses weak-keyed lookup tables to avoid writing properties directly to frames
-- (which would taint them in 12.0 and cause secret value errors)
local addonName, addon = ...

addon.FrameState = addon.FrameState or {}
local FS = addon.FrameState

--------------------------------------------------------------------------------
-- Internal Storage (weak keys so frames can be garbage collected)
--------------------------------------------------------------------------------

local frameData = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Get or create state table for a frame
function FS.Get(frame)
    if not frame then return nil end
    if not frameData[frame] then
        frameData[frame] = {}
    end
    return frameData[frame]
end

-- Check if a frame has state
function FS.Has(frame)
    return frame and frameData[frame] ~= nil
end

-- Get a specific property from frame state (returns nil if not set)
function FS.GetProp(frame, key)
    if not frame or not frameData[frame] then return nil end
    return frameData[frame][key]
end

-- Set a specific property on frame state
function FS.SetProp(frame, key, value)
    if not frame then return end
    if not frameData[frame] then
        frameData[frame] = {}
    end
    frameData[frame][key] = value
end

-- Clear all state for a frame
function FS.Clear(frame)
    if frame then
        frameData[frame] = nil
    end
end

-- Clear a specific property from frame state
function FS.ClearProp(frame, key)
    if frame and frameData[frame] then
        frameData[frame][key] = nil
    end
end

--------------------------------------------------------------------------------
-- Convenience methods for common patterns
--------------------------------------------------------------------------------

-- Check if a hook has been installed (without writing to the frame)
function FS.IsHooked(frame, hookKey)
    return FS.GetProp(frame, hookKey) == true
end

-- Mark a hook as installed
function FS.MarkHooked(frame, hookKey)
    FS.SetProp(frame, hookKey, true)
end

-- Check if an element is marked as hidden
function FS.IsHidden(frame, hiddenKey)
    return FS.GetProp(frame, hiddenKey) == true
end

-- Set hidden state
function FS.SetHidden(frame, hiddenKey, hidden)
    FS.SetProp(frame, hiddenKey, hidden and true or false)
end
