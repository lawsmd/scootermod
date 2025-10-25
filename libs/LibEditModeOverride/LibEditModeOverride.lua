-- Copyright 2022-2023 plusmouse. Licensed under terms found in LICENSE file.

-- NOTE (ScooterMod local modifications):
-- We embed a lightly customized copy of this library. Changes include:
--  1) A per-setting compatibility flag to force index-based slider semantics
--     (some client builds appear to store Cooldown Viewer Opacity as index-from-min).
--  2) Post SetFrameSetting immediate refresh for common Cooldown Viewer settings to
--     ensure visible updates without requiring ApplyChanges/UI reopen.
-- Rationale: In late 2025, the upstream v8 changed slider validation to use real
-- min/max ranges. That fixed Icon Padding (2..10) and Icon Size (50..200) but exposed
-- an opacity persistence quirk for certain clients. Our opt-in flag allows select
-- settings (Opacity) to be handled as index-based while leaving others raw.
-- Maintenance: Treat this as a local fork. Updating the library from upstream will
-- overwrite these helpers; consider a git-managed fork if further divergence is needed.
local lib = LibStub:NewLibrary("LibEditModeOverride-1.0", 10)

if not lib then return end

local activeLayoutPending = false

local pointGetter = CreateFrame("Frame", nil, UIParent)

local FRAME_ERROR = "This frame isn't used by edit mode"
local LOAD_ERROR = "You need to call LibEditModeOverride:LoadLayouts first"
local EDIT_ERROR = "Active layout is not editable"
local READY_ERROR = "You need to wait for EDIT_MODE_LAYOUTS_UPDATED"

local layoutInfo
local reconciledLayouts = false

local function GetSystemByID(systemID, systemIndex)
  -- Get the system by checking each one for the right system id
  for _, system in pairs(layoutInfo.layouts[layoutInfo.activeLayout].systems) do
    if system.system == systemID and system.systemIndex == systemIndex then
      return system
    end
  end
end

local function GetSystemByFrame(frame)
  assert(frame and type(frame) == "table" and frame.IsObjectType and frame:IsObjectType("Frame"), "Frame required")

  local systemID = frame.system
  local systemIndex = frame.systemIndex

  return GetSystemByID(systemID, systemIndex)
end

local function GetParameterRestrictions(frame, setting)
  local systemRestrictions = EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[frame.system]
  for _, setup in ipairs(systemRestrictions) do
    if setup.setting == setting then
      return setup
    end
  end
  return nil
end

-- Optional per-setting compatibility override (ScooterMod local):
-- Allow callers to force index-based handling for specific (system, setting) pairs.
lib._forceIndexBased = lib._forceIndexBased or {}

-- SliderIsIndexBased(frame, setting, restrictions)
-- Determines whether a slider should be treated as index-based for both Set/Get operations.
-- This function is the SINGLE source of truth for the index-mode decision so callers do not
-- duplicate conversions. When true:
--   - SetFrameSetting accepts raw and normalizes to index 0..N (based on step/min/max)
--   - GetFrameSetting converts the stored index back to raw for callers
-- Notes for ScooterMod maintainers:
--   - We only force index mode for Cooldown Viewer Opacity (compat flag below) and Icon Size (allowlist)
--   - Do not re-convert in addon code; rely on this function + overrides to perform all translations
local function SliderIsIndexBased(frame, setting, restrictions)
  if not restrictions or restrictions.type ~= Enum.EditModeSettingDisplayType.Slider or not restrictions.stepSize then
    return false
  end
  -- Caller-provided override (compat mode). When true, sliders are treated as index-based:
  --  - SetFrameSetting: raw inputs within [min,max] are normalized to index 0..N
  --  - GetFrameSetting: stored index is converted back to raw via min + idx*step
  local sys = frame and frame.system
  -- Allow ScooterMod to force index-based handling (used for Cooldown Viewer Opacity on affected clients)
  if sys and lib._forceIndexBased and lib._forceIndexBased[sys] and lib._forceIndexBased[sys][setting] then
    return true
  end
  -- Explicit allowlist: Only treat Cooldown Viewer Icon Size as index-based for our use case
  if frame and frame.system == Enum.EditModeSystem.CooldownViewer and setting == Enum.EditModeCooldownViewerSetting.IconSize then
    return true
  end
  return false
end

local function GetLayoutIndex(layoutName)
  for index, layout in ipairs(layoutInfo.layouts) do
    if layout.layoutName == layoutName then
      return index
    end
  end
end

local function GetHighestIndex()
  local highestLayoutIndexByType = {};
  for index, layoutInfo in ipairs(layoutInfo.layouts) do
    if not highestLayoutIndexByType[layoutInfo.layoutType] or highestLayoutIndexByType[layoutInfo.layoutType] < index then
      highestLayoutIndexByType[layoutInfo.layoutType] = index;
    end
  end
  return highestLayoutIndexByType
end

function lib:SetGlobalSetting(setting, value)
  C_EditMode.SetAccountSetting(setting, value)
end

function lib:GetGlobalSetting(setting)
  local currentSettings = C_EditMode.GetAccountSettings()

  for _, s in ipairs(currentSettings) do
    if s.setting == setting then
      return s.value
    end
  end
end

function lib:HasEditModeSettings(frame)
  return GetSystemByFrame(frame) ~= nil
end

-- Set an option found in the Enum.EditMode enumerations
function lib:SetFrameSetting(frame, setting, value)
  assert(lib:CanEditActiveLayout(), EDIT_ERROR)
  local system = GetSystemByFrame(frame)

  assert(system, FRAME_ERROR)

  assert(value == math.floor(value), "Non-negative integer values only")

  local restrictions = GetParameterRestrictions(frame, setting)

  if restrictions then
    if restrictions.type == Enum.EditModeSettingDisplayType.Dropdown then
      local min, max
      for _, option in pairs(restrictions.options) do
        if min == nil or min > option.value then
          min = option.value
        end
        if max == nil or max < option.value then
          max = option.value
        end
      end
      assert(min <= value and value <= max, string.format("Value %s invalid for this setting: min %s, max %s", value, min, max))
    elseif restrictions.type == Enum.EditModeSettingDisplayType.Checkbox then
      assert(value == 0 or value == 1, string.format("Value %s invalid for this setting: min %s, max %s", value, 0, 1))
    elseif restrictions.type == Enum.EditModeSettingDisplayType.Slider then
      if SliderIsIndexBased(frame, setting, restrictions) then
        -- Slider with step size stores an index internally. Accept raw inputs and normalize to index.
        local rawMin = restrictions.minValue
        local rawMax = restrictions.maxValue
        local step = restrictions.stepSize
        local maxIndex = math.floor((rawMax - rawMin) / step + 0.5)
        -- If the value looks like raw (within rawMin..rawMax), convert to index; otherwise assume caller provided index
        if value >= rawMin and value <= rawMax then
          local idx = math.floor(((value - rawMin) / step) + 0.5)
          if idx < 0 then idx = 0 end
          if idx > maxIndex then idx = maxIndex end
          value = idx
        end
        assert(0 <= value and value <= maxIndex, string.format("Value %s invalid for this setting: min %s, max %s", value, 0, maxIndex))
      else
        -- No step size: treat as raw numeric within min/max
        local min = restrictions.minValue
        local max = restrictions.maxValue
        assert(min <= value and value <= max, string.format("Value %s invalid for this setting: min %s, max %s", value, min, max))
      end
    else
      error("Internal Error: Unknown setting restrictions")
    end
  end

  for _, item in pairs(system.settings) do
    if item.setting == setting then
      item.value = value
    end
  end

  -- Proactively refresh the live frame for well-known settings to ensure visible updates without requiring UI reopen.
  -- Note: immediate calls prevent visual desync and checkbox 'bounce' in external settings UIs.
  if frame and frame.system == Enum.EditModeSystem.CooldownViewer then
    if setting == Enum.EditModeCooldownViewerSetting.Opacity and frame.UpdateSystemSettingOpacity then
      pcall(frame.UpdateSystemSettingOpacity, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.IconSize and frame.UpdateSystemSettingIconSize then
      pcall(frame.UpdateSystemSettingIconSize, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.IconPadding and frame.UpdateSystemSettingIconPadding then
      pcall(frame.UpdateSystemSettingIconPadding, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.IconDirection and frame.UpdateSystemSettingIconDirection then
      pcall(frame.UpdateSystemSettingIconDirection, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.IconLimit and frame.UpdateSystemSettingIconLimit then
      pcall(frame.UpdateSystemSettingIconLimit, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.Orientation and frame.UpdateSystemSettingOrientation then
      pcall(frame.UpdateSystemSettingOrientation, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.ShowTimer and frame.UpdateSystemSettingShowTimer then
      pcall(frame.UpdateSystemSettingShowTimer, frame)
    elseif setting == Enum.EditModeCooldownViewerSetting.ShowTooltips and frame.UpdateSystemSettingShowTooltips then
      pcall(frame.UpdateSystemSettingShowTooltips, frame)
    end
    if frame.UpdateLayout then pcall(frame.UpdateLayout, frame) end
    -- Nudge Edit Mode Manager to re-evaluate control values when it's open
    if _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown() and _G.EditModeManagerFrame.RefreshSystems then
      pcall(_G.EditModeManagerFrame.RefreshSystems, _G.EditModeManagerFrame)
    end
  end
end

function lib:GetFrameSetting(frame, setting)
  local system = GetSystemByFrame(frame)

  assert(system, FRAME_ERROR)

  for _, item in pairs(system.settings) do
    if item.setting == setting then
      local restrictions = GetParameterRestrictions(frame, setting)
      if restrictions and SliderIsIndexBased(frame, setting, restrictions) then
        -- Convert stored index to raw value for callers
        local rawMin = restrictions.minValue
        local step = restrictions.stepSize
        local idx = item.value or 0
        return rawMin + (idx * step)
      end
      -- IMPORTANT: Some edit-mode UIs internally store Opacity as an index but present raw percent.
      -- We normalize here to raw when we can infer the typical 50..100 range with step 1.
      if restrictions and restrictions.type == Enum.EditModeSettingDisplayType.Slider and setting == Enum.EditModeCooldownViewerSetting.Opacity then
        local v = item.value
        -- If value looks like index (0..50), convert to 50..100;
        -- if it already looks raw (50..100), pass through.
        if type(v) == "number" then
          if v >= 0 and v <= 50 then return 50 + v end
          if v >= 50 and v <= 100 then return v end
        end
      end
      return item.value
    end
  end
  return nil
end

function lib:ReanchorFrame(frame, ...)
  assert(lib:CanEditActiveLayout(), EDIT_ERROR)
  local system = GetSystemByFrame(frame)

  assert(system, FRAME_ERROR)

  system.isInDefaultPosition = false

  pointGetter:ClearAllPoints()
  pointGetter:SetPoint(...)
  local anchorInfo = system.anchorInfo

  anchorInfo.point, anchorInfo.relativeTo, anchorInfo.relativePoint, anchorInfo.offsetX, anchorInfo.offsetY = pointGetter:GetPoint(1)
  anchorInfo.relativeTo = anchorInfo.relativeTo:GetName()
end

function lib:AreLayoutsLoaded()
  return layoutInfo ~= nil
end

function lib:IsReady()
  return EditModeManagerFrame.accountSettings ~= nil
end

function lib:LoadLayouts()
  assert(lib:IsReady(), READY_ERROR)
  layoutInfo = C_EditMode.GetLayouts()

  if not reconciledLayouts then
    local anyChanged = false
    for _, layout in ipairs(layoutInfo.layouts) do
      anyChanged = anyChanged or EditModeManagerFrame:ReconcileWithModern(layout)
    end
    if not anyChanged then
      reconciledLayouts = true
    end
  end

  local tmp = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
  tAppendAll(tmp, layoutInfo.layouts);
  layoutInfo.layouts = tmp
end

function lib:SaveOnly()
  assert(layoutInfo, LOAD_ERROR)
  C_EditMode.SaveLayouts(layoutInfo)
  if activeLayoutPending then
    C_EditMode.SetActiveLayout(layoutInfo.activeLayout)
    activeLayoutPending = false
  end
  reconciledLayouts = true -- Would have updated for new/old systems in LoadLayouts
end

function lib:ApplyChanges()
  assert(not InCombatLockdown(), "Cannot move frames in combat")
  assert(lib:IsReady(), READY_ERROR)
  lib:SaveOnly()

  if not issecurevariable(DropDownList1, "numButtons") then
    ShowUIPanel(AddonList)
    HideUIPanel(AddonList)
  end

  ShowUIPanel(EditModeManagerFrame)
  HideUIPanel(EditModeManagerFrame)
end

function lib:DoesLayoutExist(layoutName)
  assert(layoutInfo, LOAD_ERROR)
  return GetLayoutIndex(layoutName) ~= nil
end

function lib:AddLayout(layoutType, layoutName)
  assert(layoutInfo, LOAD_ERROR)
  assert(layoutName and layoutName ~= "", "Non-empty string required")
  assert(not lib:DoesLayoutExist(layoutName), "Layout should not already exist")

  local newLayout = CopyTable(layoutInfo.layouts[1]) -- Modern layout

  newLayout.layoutType = layoutType
  newLayout.layoutName = layoutName

  local highestLayoutIndexByType = GetHighestIndex()

  local newLayoutIndex;
  if highestLayoutIndexByType[layoutType] then
    newLayoutIndex = highestLayoutIndexByType[layoutType] + 1;
  elseif (layoutType == Enum.EditModeLayoutType.Character) and highestLayoutIndexByType[Enum.EditModeLayoutType.Account] then
    newLayoutIndex = highestLayoutIndexByType[Enum.EditModeLayoutType.Account] + 1;
  else
    newLayoutIndex = Enum.EditModePresetLayoutsMeta.NumValues + 1;
  end

  table.insert(layoutInfo.layouts, newLayoutIndex, newLayout)
  self:SetActiveLayout(layoutName)
end

function lib:DeleteLayout(layoutName)
  assert(layoutInfo, LOAD_ERROR)
  local index = GetLayoutIndex(layoutName)
  assert(index ~= nil, "Can't delete layout as it doesn't exist")

  assert(layoutInfo.layouts[index].layoutType ~= Enum.EditModeLayoutType.Preset, "Cannot delete preset layouts")

  table.remove(layoutInfo.layouts, index)
  C_EditMode.OnLayoutDeleted(index)
end

function lib:GetEditableLayoutNames()
  assert(layoutInfo, LOAD_ERROR)
  local names = {}
  for _, layout in ipairs(layoutInfo.layouts) do
    if layout.layoutType ~= Enum.EditModeLayoutType.Preset then
      table.insert(names, layout.layoutName)
    end
  end

  return names
end

function lib:GetPresetLayoutNames()
  assert(layoutInfo, LOAD_ERROR)
  local names = {}
  for _, layout in ipairs(layoutInfo.layouts) do
    if layout.layoutType == Enum.EditModeLayoutType.Preset then
      table.insert(names, layout.layoutName)
    end
  end

  return names
end

function lib:CanEditActiveLayout()
  assert(layoutInfo, LOAD_ERROR)
  return layoutInfo.layouts[layoutInfo.activeLayout].layoutType ~= Enum.EditModeLayoutType.Preset
end

function lib:SetActiveLayout(layoutName)
  assert(layoutInfo, LOAD_ERROR)
  assert(lib:DoesLayoutExist(layoutName), "Layout must exist")

  local index = GetLayoutIndex(layoutName)

  layoutInfo.activeLayout = index

  activeLayoutPending = true
end

function lib:GetActiveLayout()
  assert(layoutInfo, LOAD_ERROR)
  return layoutInfo.layouts[layoutInfo.activeLayout].layoutName
end
