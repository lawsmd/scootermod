local addonName, addon = ...

-- Damage Meters Component
-- Targets Blizzard's Damage Meter frame (DamageMeter, Edit Mode system) and provides:
-- - Edit Mode settings: Style, Frame Width/Height, Bar Height, Padding, Opacity, Background, Text Size, Visibility, Show Spec Icon, Show Class Color
-- - Addon-only settings: Bar textures, fonts, colors, borders, etc.
--
-- Zero-Touch invariant:
-- - If the profile has no persisted table for this component, ApplyStyling must do nothing.
-- - Even if the component DB exists due to Edit Mode changes, addon-only styling should only apply
--   when the specific config tables exist.

local function SafeSetAlpha(frame, alpha)
    if not frame or not frame.SetAlpha then return false end
    return pcall(frame.SetAlpha, frame, alpha)
end

local function SafeSetShown(region, shown)
    if not region then return end
    if region.SetShown then
        pcall(region.SetShown, region, shown and true or false)
        return
    end
    if shown then
        if region.Show then pcall(region.Show, region) end
    else
        if region.Hide then pcall(region.Hide, region) end
    end
end

local function PlayerInCombat()
    if addon and addon.ComponentsUtil and type(addon.ComponentsUtil.PlayerInCombat) == "function" then
        return addon.ComponentsUtil.PlayerInCombat()
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        return UnitAffectingCombat("player") and true or false
    end
    return false
end

local function GetClassColor(classToken)
    if not classToken then return 1, 1, 1, 1 end
    local colors = _G.RAID_CLASS_COLORS
    if colors and colors[classToken] then
        local c = colors[classToken]
        return c.r or 1, c.g or 1, c.b or 1, 1
    end
    return 1, 1, 1, 1
end

-- Apply styling to a single entry (bar) in the damage meter
local function ApplySingleEntryStyle(entry, db)
    if not entry or not db then return end

    local statusBar = entry.StatusBar or entry.bar or entry
    if not statusBar then return end

    -- Bar texture
    if db.barTexture and addon and addon.ResolveBarTexture then
        local texturePath = addon.ResolveBarTexture(db.barTexture)
        if texturePath and statusBar.SetStatusBarTexture then
            pcall(statusBar.SetStatusBarTexture, statusBar, texturePath)
        end
    end

    -- Bar foreground color (or class color)
    local showClassColor = db.showClassColor
    if showClassColor then
        -- Get class token from entry data
        local classToken = entry.classToken or entry.class or (entry.data and entry.data.classToken)
        if classToken then
            local r, g, b = GetClassColor(classToken)
            if statusBar.SetStatusBarColor then
                pcall(statusBar.SetStatusBarColor, statusBar, r, g, b, 1)
            end
        end
    elseif db.barForegroundColor then
        local c = db.barForegroundColor
        if statusBar.SetStatusBarColor then
            pcall(statusBar.SetStatusBarColor, statusBar, c[1] or 1, c[2] or 0.8, c[3] or 0, c[4] or 1)
        end
    end

    -- Bar background color
    if db.barBackgroundColor then
        local bg = statusBar.Background or statusBar.bg or statusBar.background
        if bg and bg.SetVertexColor then
            local c = db.barBackgroundColor
            pcall(bg.SetVertexColor, bg, c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, c[4] or 0.8)
        end
    end

    -- Custom bar border
    if db.barUseCustomBorder and db.barBorderStyle then
        -- Hide Blizzard's default border
        local blizzBorder = statusBar.BackgroundEdge or statusBar.Border or statusBar.border
        if blizzBorder then
            SafeSetAlpha(blizzBorder, 0)
        end

        -- Apply custom border (implementation depends on available border system)
        if addon and addon.ApplyBarBorder then
            local borderOpts = {
                style = db.barBorderStyle,
                thickness = db.barBorderThickness or 1,
                color = db.barBorderTintEnabled and db.barBorderTintColor or nil,
            }
            addon.ApplyBarBorder(statusBar, borderOpts)
        end
    else
        -- Restore Blizzard's border
        local blizzBorder = statusBar.BackgroundEdge or statusBar.Border or statusBar.border
        if blizzBorder then
            SafeSetAlpha(blizzBorder, 1)
        end
    end

    -- Name text styling
    local nameFS = statusBar.Name or statusBar.name or (entry.Name)
    if nameFS and db.textNames then
        local cfg = db.textNames
        if cfg.fontFace and addon and addon.ResolveFontFace then
            local face = addon.ResolveFontFace(cfg.fontFace)
            local size = cfg.fontSize or 12
            local flags = cfg.fontStyle or "OUTLINE"
            if nameFS.SetFont then
                pcall(nameFS.SetFont, nameFS, face, size, flags)
            end
        end
        if cfg.color and nameFS.SetTextColor then
            local c = cfg.color
            pcall(nameFS.SetTextColor, nameFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
    end

    -- Value text styling (DPS/HPS numbers)
    local valueFS = statusBar.Value or statusBar.value or (entry.Value)
    if valueFS and db.textNumbers then
        local cfg = db.textNumbers
        if cfg.fontFace and addon and addon.ResolveFontFace then
            local face = addon.ResolveFontFace(cfg.fontFace)
            local size = cfg.fontSize or 12
            local flags = cfg.fontStyle or "OUTLINE"
            if valueFS.SetFont then
                pcall(valueFS.SetFont, valueFS, face, size, flags)
            end
        end
        if cfg.color and valueFS.SetTextColor then
            local c = cfg.color
            pcall(valueFS.SetTextColor, valueFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
    end

    -- Spec icon styling
    local iconFrame = entry.IconFrame or entry.icon or entry.SpecIcon
    if iconFrame then
        if db.showSpecIcon == false then
            SafeSetShown(iconFrame, false)
        else
            SafeSetShown(iconFrame, true)

            -- Icon border
            if db.iconBorderEnabled and db.iconBorderColor then
                local border = iconFrame.Border or iconFrame.border
                if border then
                    SafeSetShown(border, true)
                    if border.SetVertexColor then
                        local c = db.iconBorderColor
                        pcall(border.SetVertexColor, border, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                    end
                end
            end

            -- Icon background
            if db.iconBackgroundColor then
                local bg = iconFrame.Background or iconFrame.bg
                if bg and bg.SetVertexColor then
                    local c = db.iconBackgroundColor
                    pcall(bg.SetVertexColor, bg, c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, c[4] or 0.8)
                end
            end
        end
    end
end

-- Apply window-level styling (border, background)
local function ApplyWindowStyling(window, db)
    if not window or not db then return end

    -- Window border
    if db.windowShowBorder then
        -- Apply border using addon border system if available
        if addon and addon.ApplyFrameBorder then
            local borderOpts = {
                style = db.windowBorderStyle or "default",
                color = db.windowBorderColor,
                thickness = db.windowBorderThickness or 1,
            }
            addon.ApplyFrameBorder(window, borderOpts)
        end
    end

    -- Window background
    if db.windowCustomBackdrop and db.windowBackdropTexture then
        -- Apply custom backdrop
        if window.SetBackdrop and addon and addon.ResolveBackdropTexture then
            local texturePath = addon.ResolveBackdropTexture(db.windowBackdropTexture)
            if texturePath then
                local backdrop = {
                    bgFile = texturePath,
                    edgeFile = nil,
                    tile = true,
                    tileSize = 16,
                    edgeSize = 0,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                }
                pcall(window.SetBackdrop, window, backdrop)

                if db.windowBackdropColor and window.SetBackdropColor then
                    local c = db.windowBackdropColor
                    pcall(window.SetBackdropColor, window, c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, c[4] or 0.9)
                end
            end
        end
    end
end

-- Apply title/header text styling
local function ApplyTitleStyling(dmFrame, db)
    if not dmFrame or not db then return end

    local titleCfg = db.textTitle
    if not titleCfg then return end

    -- Find title text elements
    local titleTargets = {}

    -- Common title locations
    if dmFrame.Header and dmFrame.Header.Text then
        table.insert(titleTargets, dmFrame.Header.Text)
    end
    if dmFrame.Title then
        table.insert(titleTargets, dmFrame.Title)
    end
    if dmFrame.TitleText then
        table.insert(titleTargets, dmFrame.TitleText)
    end

    -- Dropdown text (mode selector)
    if dmFrame.ModeDropdown then
        local dropdown = dmFrame.ModeDropdown
        if dropdown.Text then
            table.insert(titleTargets, dropdown.Text)
        end
    end

    for _, fs in ipairs(titleTargets) do
        if fs and fs.SetFont then
            if titleCfg.fontFace and addon and addon.ResolveFontFace then
                local face = addon.ResolveFontFace(titleCfg.fontFace)
                local baseSize = 12
                local scale = (titleCfg.textSize or 100) / 100
                local size = baseSize * scale
                local flags = titleCfg.fontStyle or "OUTLINE"
                pcall(fs.SetFont, fs, face, size, flags)
            end
            if titleCfg.color and fs.SetTextColor then
                local c = titleCfg.color
                pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
        end
    end
end

-- Hook entry acquisition to style new entries
local function HookEntryAcquisition(component)
    local dmFrame = _G.DamageMeter
    if not dmFrame or dmFrame._ScooterDMHooked then return end
    dmFrame._ScooterDMHooked = true

    -- Coalesce re-application to one per frame
    local function requestApply()
        if component._ScooterDMApplyQueued then return end
        component._ScooterDMApplyQueued = true
        _G.C_Timer.After(0, function()
            component._ScooterDMApplyQueued = nil
            if component and component.ApplyStyling then
                component:ApplyStyling()
            end
        end)
    end

    -- Hook ScrollBox Update for entry styling
    local sessionWindow = dmFrame.SessionWindow or dmFrame
    if sessionWindow and sessionWindow.ScrollBox then
        hooksecurefunc(sessionWindow.ScrollBox, "Update", function(scrollBox)
            _G.C_Timer.After(0, function()
                if not component.db then return end
                if scrollBox.ForEachFrame then
                    pcall(scrollBox.ForEachFrame, scrollBox, function(entryFrame)
                        ApplySingleEntryStyle(entryFrame, component.db)
                    end)
                end
            end)
        end)
    end

    -- Hook Update/Refresh methods
    if type(dmFrame.Update) == "function" then
        hooksecurefunc(dmFrame, "Update", requestApply)
    end
    if type(dmFrame.Refresh) == "function" then
        hooksecurefunc(dmFrame, "Refresh", requestApply)
    end
    if type(dmFrame.UpdateData) == "function" then
        hooksecurefunc(dmFrame, "UpdateData", requestApply)
    end
end

-- Main styling function
local function ApplyDamageMeterStyling(self)
    local dmFrame = _G.DamageMeter
    if not dmFrame then return end

    -- Install hooks on first styling pass
    HookEntryAcquisition(self)

    -- Zero-Touch: if still on proxy DB, do nothing
    if self._ScootDBProxy and self.db == self._ScootDBProxy then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    -- Combat-safe: defer non-critical styling during combat
    if PlayerInCombat() then
        return
    end

    -- Apply title/header styling
    ApplyTitleStyling(dmFrame, db)

    -- Apply window styling
    ApplyWindowStyling(dmFrame, db)

    -- Style all visible entries
    local sessionWindow = dmFrame.SessionWindow or dmFrame
    if sessionWindow and sessionWindow.ScrollBox and sessionWindow.ScrollBox.ForEachFrame then
        pcall(sessionWindow.ScrollBox.ForEachFrame, sessionWindow.ScrollBox, function(entryFrame)
            ApplySingleEntryStyle(entryFrame, db)
        end)
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local damageMeter = Component:New({
        id = "damageMeter",
        name = "Damage Meter",
        frameName = "DamageMeter",
        settings = {
            -- Edit Mode-managed settings (11 total)
            -- Style dropdown: Default(0), Bordered(1), Thin(2)
            style = { type = "editmode", settingId = nil, default = 0, ui = { hidden = true } },
            -- Layout settings
            frameWidth = { type = "editmode", settingId = nil, default = 300, ui = { hidden = true } },
            frameHeight = { type = "editmode", settingId = nil, default = 200, ui = { hidden = true } },
            barHeight = { type = "editmode", settingId = nil, default = 20, ui = { hidden = true } },
            padding = { type = "editmode", settingId = nil, default = 4, ui = { hidden = true } },
            -- Transparency/Opacity settings
            opacity = { type = "editmode", settingId = nil, default = 100, ui = { hidden = true } },
            background = { type = "editmode", settingId = nil, default = 80, ui = { hidden = true } },
            -- Text size
            textSize = { type = "editmode", settingId = nil, default = 100, ui = { hidden = true } },
            -- Visibility dropdown: Always(0), InCombat(1), Hidden(2)
            visibility = { type = "editmode", settingId = nil, default = 0, ui = { hidden = true } },
            -- Checkboxes
            showSpecIcon = { type = "editmode", settingId = nil, default = true, ui = { hidden = true } },
            showClassColor = { type = "editmode", settingId = nil, default = true, ui = { hidden = true } },

            -- Addon-only settings (bar styling)
            barTexture = { type = "addon", default = "default", ui = { hidden = true } },
            barForegroundColor = { type = "addon", default = { 1, 0.8, 0, 1 }, ui = { hidden = true } },
            barBackgroundColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 }, ui = { hidden = true } },

            -- Bar border settings
            barUseCustomBorder = { type = "addon", default = false, ui = { hidden = true } },
            barBorderStyle = { type = "addon", default = "default", ui = { hidden = true } },
            barBorderTintEnabled = { type = "addon", default = false, ui = { hidden = true } },
            barBorderTintColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            barBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },

            -- Icon settings
            iconBorderEnabled = { type = "addon", default = false, ui = { hidden = true } },
            iconBorderColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            iconBackgroundColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 }, ui = { hidden = true } },

            -- Text settings - Title (header/dropdown)
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                textSize = 100,
                color = { 1, 1, 1, 1 },
            }, ui = { hidden = true }},

            -- Text settings - Names (player names on bars)
            textNames = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                fontSize = 12,
                color = { 1, 1, 1, 1 },
            }, ui = { hidden = true }},

            -- Text settings - Numbers (DPS/HPS values)
            textNumbers = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                fontSize = 12,
                color = { 1, 1, 1, 1 },
            }, ui = { hidden = true }},

            -- Window border settings
            windowShowBorder = { type = "addon", default = false, ui = { hidden = true } },
            windowBorderStyle = { type = "addon", default = "default", ui = { hidden = true } },
            windowBorderColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            windowBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },

            -- Window background settings
            windowCustomBackdrop = { type = "addon", default = false, ui = { hidden = true } },
            windowBackdropTexture = { type = "addon", default = "default", ui = { hidden = true } },
            windowBackdropColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.9 }, ui = { hidden = true } },
        },
        ApplyStyling = ApplyDamageMeterStyling,
    })

    self:RegisterComponent(damageMeter)
end)
