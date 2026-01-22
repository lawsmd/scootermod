-- Legacy stub: logic moved to modular builders (core_renderer, cdm_components,
-- prd_components, tooltip). This file is intentionally minimal to
-- avoid double-defining renderers after the refactor.
local addonName, addon = ...
addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Ensure panel.builders table exists; createComponentRenderer now lives in
-- core_renderer.lua and is loaded earlier via TOC ordering.
panel.builders = panel.builders or {}
