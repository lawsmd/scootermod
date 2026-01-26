local addonName, addon = ...

--[[============================================================================
    ██╗     ███████╗ ██████╗  █████╗  ██████╗██╗   ██╗
    ██║     ██╔════╝██╔════╝ ██╔══██╗██╔════╝╚██╗ ██╔╝
    ██║     █████╗  ██║  ███╗███████║██║      ╚████╔╝
    ██║     ██╔══╝  ██║   ██║██╔══██║██║       ╚██╔╝
    ███████╗███████╗╚██████╔╝██║  ██║╚██████╗   ██║
    ╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝   ╚═╝

    ⚠️  WARNING: THIS IS LEGACY CODE - DO NOT MODIFY ⚠️

    This entire directory (ui/panel/) is the LEGACY UI system.

    The NEW UI is located in: ui/v2/

    This legacy code is kept only for backwards compatibility and will
    eventually be removed. ALL new development should happen in ui/v2/.

    If you are an AI assistant or developer reading this:
    - DO NOT add new features to files in ui/panel/
    - DO NOT modify files in ui/panel/ for new functionality
    - GO TO ui/v2/ for all UI work

============================================================================]]--

addon.SettingsPanel = addon.SettingsPanel or {}

-- LEGACY: This file now intentionally acts as a thin stub. The heavy settings panel
-- builders live under `ui/panel/builders/` and extend `addon.SettingsPanel`
-- when loaded via the TOC.
-- ⚠️ DO NOT MODIFY - Use ui/v2/ instead

-- Component settings list renderers and helpers moved from ScooterSettingsPanel.lua



