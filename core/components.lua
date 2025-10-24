local addonName, addon = ...

addon.Components = {}

local Component = {}

-- Shared styling for Cooldown Viewer-style components (icons, borders, text, padding, visibility, opacity)
local function ApplyCooldownViewerStyling(self)
    local frame = _G[self.frameName]
    if not frame then return end

    local width = self.db.iconWidth or (self.settings.iconWidth and self.settings.iconWidth.default)
    local height = self.db.iconHeight or (self.settings.iconHeight and self.settings.iconHeight.default)
    local spacing = self.db.iconPadding or (self.settings.iconPadding and self.settings.iconPadding.default)

    for _, child in ipairs({ frame:GetChildren() }) do
        if width and height and child.SetSize then child:SetSize(width, height) end
        if self.db.borderEnable then
            local style = self.db.borderStyle or "square"
            if type(style) == "string" and style:find("^atlas:") and addon.Borders and addon.Borders.ApplyAtlas then
                local key = style:sub(7)
                if key and #key > 0 then
                    local t = tonumber(self.db.borderThickness) or 1
                    if t < 1 then t = 1 elseif t > 16 then t = 16 end
                    local extra = -math.floor(((t - 1) / 15) * 2 + 0.5)
                    local tint = (self.db.borderTintEnable and (self.db.borderTintColor or {1,1,1,1})) or nil
                    addon.Borders.ApplyAtlas(child, { atlas = key, extraPadding = extra, tintColor = tint })
                else
                    if addon.Borders and addon.Borders.ApplySquare then
                        addon.Borders.ApplySquare(child, { size = self.db.borderThickness or 1, color = {0,0,0,1} })
                    end
                end
            elseif addon.Borders and addon.Borders.ApplySquare then
                local col = {0,0,0,1}
                if self.db.borderTintEnable and type(self.db.borderTintColor) == "table" then
                    col = { self.db.borderTintColor[1] or 1, self.db.borderTintColor[2] or 1, self.db.borderTintColor[3] or 1, self.db.borderTintColor[4] or 1 }
                end
                addon.Borders.ApplySquare(child, { size = self.db.borderThickness or 1, color = col })
            end
        else
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(child) end
        end

        -- Text styling (Charges/Cooldowns for icon viewers; Name/Duration for bar viewers)
        do
            local defaultFace = (select(1, GameFontNormal:GetFont()))
            local function findFontStringOn(obj)
                if not obj then return nil end
                if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
                if obj.GetRegions then
                    local n = (obj.GetNumRegions and obj.GetNumRegions(obj)) or 0
                    for i = 1, n do
                        local r = select(i, obj:GetRegions())
                        if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
                    end
                end
                if obj.GetChildren then
                    local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                    for i = 1, m do
                        local c = select(i, obj:GetChildren())
                        local found = findFontStringOn(c)
                        if found then return found end
                    end
                end
                return nil
            end
            local function findFontStringByNameHint(root, hint)
                local target = nil
                local function scan(obj)
                    if not obj or target then return end
                    if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                        local nm = obj.GetName and obj:GetName() or ""
                        if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                            target = obj; return
                        end
                    end
                    if obj.GetRegions then
                        local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                        for i = 1, n do
                            local r = select(i, obj:GetRegions())
                            if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                                local nm = r.GetName and r:GetName() or ""
                                if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                                    target = r; return
                                end
                            end
                        end
                    end
                    if obj.GetChildren then
                        local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                        for i = 1, m do
                            local c = select(i, obj:GetChildren())
                            scan(c)
                            if target then return end
                        end
                    end
                end
                scan(root)
                return target
            end

            if self.id == "trackedBars" then
                -- Bars: style Name and Duration font strings
                local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar or child
                local nameFS = (barFrame and barFrame.Name) or findFontStringByNameHint(barFrame or child, "Bar.Name") or findFontStringByNameHint(child, "Name")
                local durFS  = (barFrame and barFrame.Duration) or findFontStringByNameHint(barFrame or child, "Bar.Duration") or findFontStringByNameHint(child, "Duration")

                if nameFS and nameFS.SetFont then
                    local cfg = self.db.textName or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                    pcall(nameFS.SetDrawLayer, nameFS, "OVERLAY", 10)
                    nameFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE")
                    local c = cfg.color or {1,1,1,1}
                    if nameFS.SetTextColor then nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                    if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, "LEFT") end
                    local ox = (cfg.offset and cfg.offset.x) or 0
                    local oy = (cfg.offset and cfg.offset.y) or 0
                    -- Only override positioning when a non-zero offset is requested; preserve stock anchors at 0,0
                    if (ox ~= 0 or oy ~= 0) and nameFS.ClearAllPoints and nameFS.SetPoint then
                        nameFS:ClearAllPoints()
                        local anchorTo = barFrame or child
                        nameFS:SetPoint("LEFT", anchorTo, "LEFT", ox, oy)
                    end
                end

                if durFS and durFS.SetFont then
                    local cfg = self.db.textDuration or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                    pcall(durFS.SetDrawLayer, durFS, "OVERLAY", 10)
                    durFS:SetFont(face, tonumber(cfg.size) or 14, cfg.style or "OUTLINE")
                    local c = cfg.color or {1,1,1,1}
                    if durFS.SetTextColor then durFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                    if durFS.SetJustifyH then pcall(durFS.SetJustifyH, durFS, "RIGHT") end
                    local ox = (cfg.offset and cfg.offset.x) or 0
                    local oy = (cfg.offset and cfg.offset.y) or 0
                    if (ox ~= 0 or oy ~= 0) and durFS.ClearAllPoints and durFS.SetPoint then
                        durFS:ClearAllPoints()
                        local anchorTo = barFrame or child
                        durFS:SetPoint("RIGHT", anchorTo, "RIGHT", ox, oy)
                    end
                end
            else
                -- Icon viewers: style stacks/applications and cooldown
                local cdFS = (child.Cooldown and findFontStringOn(child.Cooldown)) or findFontStringByNameHint(child, "Cooldown")
                local stacksFS = (child.ChargeCount and findFontStringOn(child.ChargeCount))
                    or (child.Applications and findFontStringOn(child.Applications))
                    or findFontStringByNameHint(child, "Applications")

                if stacksFS and stacksFS.SetFont then
                    local cfg = self.db.textStacks or { size = 16, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                    pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
                    stacksFS:SetFont(face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE")
                    local c = cfg.color or {1,1,1,1}
                    if stacksFS.SetTextColor then stacksFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                    if stacksFS.ClearAllPoints and stacksFS.SetPoint then
                        stacksFS:ClearAllPoints()
                        local ox = (cfg.offset and cfg.offset.x) or 0
                        local oy = (cfg.offset and cfg.offset.y) or 0
                        stacksFS:SetPoint("CENTER", child, "CENTER", ox, oy)
                    end
                end

                if cdFS and cdFS.SetFont then
                    local cfg = self.db.textCooldown or { size = 16, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
                    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace or "FRIZQT__") or defaultFace
                    pcall(cdFS.SetDrawLayer, cdFS, "OVERLAY", 10)
                    cdFS:SetFont(face, tonumber(cfg.size) or 16, cfg.style or "OUTLINE")
                    local c = cfg.color or {1,1,1,1}
                    if cdFS.SetTextColor then cdFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                    if cdFS.ClearAllPoints and cdFS.SetPoint then
                        cdFS:ClearAllPoints()
                        local ox = (cfg.offset and cfg.offset.x) or 0
                        local oy = (cfg.offset and cfg.offset.y) or 0
                        cdFS:SetPoint("CENTER", child, "CENTER", ox, oy)
                    end
                end
            end
        end

        -- Tracked Bars: apply exploratory sizing/spacing (bar width and icon/bar padding)
        if self.id == "trackedBars" then
            local barFrame = child.GetBarFrame and child:GetBarFrame() or child.Bar
            local iconFrame = child.GetIconFrame and child:GetIconFrame() or child.Icon
            if barFrame and iconFrame then
                local desiredPad = tonumber(self.db.iconBarPadding or (self.settings.iconBarPadding and self.settings.iconBarPadding.default) or 0) or 0
                local desiredWidthOverride = tonumber(self.db.barWidth)

                -- Capture current layout state
                local rightPoint, rightRelTo, rightRelPoint, rx, ry
                if barFrame.GetNumPoints and barFrame.GetPoint then
                    local n = barFrame:GetNumPoints()
                    for i = 1, n do
                        local p, rt, rp, ox, oy = barFrame:GetPoint(i)
                        if p == "RIGHT" then rightPoint, rightRelTo, rightRelPoint, rx, ry = p, rt, rp, ox, oy break end
                    end
                end
                local currentWidth = (barFrame.GetWidth and barFrame:GetWidth()) or nil
                local currentGap
                if barFrame.GetLeft and iconFrame.GetRight then
                    local bl = barFrame:GetLeft()
                    local ir = iconFrame:GetRight()
                    if bl and ir then currentGap = bl - ir end
                end
                local deltaPad = (currentGap and (desiredPad - currentGap)) or 0
                local deltaWidth = 0
                if desiredWidthOverride and desiredWidthOverride > 0 and currentWidth then
                    deltaWidth = desiredWidthOverride - currentWidth
                end

                -- Re-anchor to maintain width while changing gap (and optionally apply width override)
                if barFrame.ClearAllPoints and barFrame.SetPoint then
                    barFrame:ClearAllPoints()
                    -- Shift RIGHT by deltaPad and deltaWidth to keep overall width while changing left gap, then apply desired width change
                    if rightPoint and rightRelTo then
                        barFrame:SetPoint("RIGHT", rightRelTo, rightRelPoint or "RIGHT", (rx or 0) + deltaPad + deltaWidth, ry or 0)
                    else
                        barFrame:SetPoint("RIGHT", child, "RIGHT", deltaPad + deltaWidth, 0)
                    end
                    -- Set LEFT gap to icon
                    barFrame:SetPoint("LEFT", iconFrame, "RIGHT", desiredPad, 0)
                end
            end
        end
    end

    -- Padding adjustments on the item container
    do
        local ic = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
        if ic and spacing ~= nil then
            if ic.childXPadding ~= nil then ic.childXPadding = spacing end
            if ic.childYPadding ~= nil then ic.childYPadding = spacing end
            if ic.iconPadding ~= nil then ic.iconPadding = spacing end
            if type(ic.MarkDirty) == "function" then pcall(ic.MarkDirty, ic) end
        end
    end

    if frame.UpdateLayout then pcall(frame.UpdateLayout, frame) end
    local ic2 = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
    if ic2 and type(ic2.UpdateLayout) == "function" then pcall(ic2.UpdateLayout, ic2) end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local ic3 = (frame.GetItemContainerFrame and frame:GetItemContainerFrame()) or frame
            if ic3 and ic3.UpdateLayout then pcall(ic3.UpdateLayout, ic3) end
        end)
    end

    -- Visibility (mode only)
    do
        local mode = self.db.visibilityMode or (self.settings.visibilityMode and self.settings.visibilityMode.default) or "always"
        if mode == "never" then
            if frame.Hide then pcall(frame.Hide, frame) end
        elseif mode == "combat" then
            local show = (type(UnitAffectingCombat) == "function") and UnitAffectingCombat("player") or false
            if frame.SetShown then pcall(frame.SetShown, frame, show) end
        else
            if frame.Show then pcall(frame.Show, frame) end
        end
    end

    -- Opacity immediate local visual update
    do
        local op = tonumber(self.db.opacity or (self.settings.opacity and self.settings.opacity.default) or 100) or 100
        if op < 50 then op = 50 elseif op > 100 then op = 100 end
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, op / 100) end
    end
end

function Component:New(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Component:SyncEditModeSettings()
    local frame = _G[self.frameName]
    if not frame then return end

    local changed = false
    for settingId, setting in pairs(self.settings) do
        if setting.type == "editmode" then
            if addon.EditMode.SyncEditModeSettingToComponent(self, settingId) then
                changed = true
            end
        end
    end

    return changed
end

function addon:RegisterComponent(component)
    self.Components[component.id] = component
end

function addon:InitializeComponents()
    local essentialCooldowns = Component:New({
        id = "essentialCooldowns",
        name = "Essential Cooldowns",
        frameName = "EssentialCooldownViewer",
        settings = {
            -- Positioning
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", settingId = 1, default = 12, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 20, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            direction = { type = "editmode", settingId = 2, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 3, dynamicValues = true
            }},
            iconPadding = { type = "editmode", settingId = 4, default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 4
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 5
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 6
            }},
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 50, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 50, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", values = { square = "Square", style_tooltip = "Tooltip", dialog = "Dialog", none = "None" }, section = "Border", order = 4
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility (Edit Mode synced)
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 3
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 4
            }},
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(essentialCooldowns)

    local utilityCooldowns = Component:New({
        id = "utilityCooldowns",
        name = "Utility Cooldowns",
        frameName = "UtilityCooldownViewer",
        settings = {
            -- Positioning
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", settingId = 1, default = 12, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 20, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            direction = { type = "editmode", settingId = 2, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 3, dynamicValues = true
            }},
            iconPadding = { type = "editmode", settingId = 4, default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 4
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 5
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 6
            }},
            -- Sizing (Utility defaults slightly smaller: keep same ranges; visual default can reuse Essential's 100)
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 44, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 44, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", values = { square = "Square", style_tooltip = "Tooltip", dialog = "Dialog", none = "None" }, section = "Border", order = 4
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility / Misc
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 3
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 4
            }},
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(utilityCooldowns)

    local trackedBuffs = Component:New({
        id = "trackedBuffs",
        name = "Tracked Buffs",
        frameName = "BuffIconCooldownViewer",
        settings = {
            -- Positioning
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            direction = { type = "editmode", settingId = 2, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 2, dynamicValues = true
            }},
            iconPadding = { type = "editmode", settingId = 4, default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 3
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 4
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 5
            }},
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            iconWidth = { type = "addon", default = 44, ui = {
                label = "Icon Width", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 2
            }},
            iconHeight = { type = "addon", default = 44, ui = {
                label = "Icon Height", widget = "slider", min = 24, max = 96, step = 1, section = "Sizing", order = 3
            }},
            -- Border
            borderEnable = { type = "addon", default = false, ui = {
                label = "Enable Border", widget = "checkbox", section = "Border", order = 1, tooltip = ""
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", values = { square = "Square", style_tooltip = "Tooltip", dialog = "Dialog", none = "None" }, section = "Border", order = 4
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 16, step = 1, section = "Border", order = 5
            }},
            -- Visibility (Edit Mode synced)
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 3
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 4
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 5
            }},
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBuffs)

    local trackedBars = Component:New({
        id = "trackedBars",
        name = "Tracked Bars",
        frameName = "BuffBarCooldownViewer",
        settings = {
            -- Positioning
            iconPadding = { type = "editmode", settingId = 4, default = 3, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 1
            }},
            iconBarPadding = { type = "addon", default = 0, ui = {
                label = "Icon/Bar Padding", widget = "slider", min = -20, max = 80, step = 1, section = "Positioning", order = 2
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 3
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 4
            }},
            -- Sizing
            iconSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            barWidth = { type = "addon", default = 220, ui = {
                label = "Bar Width", widget = "slider", min = 120, max = 480, step = 2, section = "Sizing", order = 2
            }},
            -- Visibility / Misc (Edit Mode)
            visibilityMode = { type = "editmode", default = "always", ui = {
                label = "Visibility", widget = "dropdown", values = { always = "Always", combat = "Only in Combat", never = "Hidden" }, section = "Misc", order = 1
            }},
            opacity = { type = "editmode", settingId = 5, default = 100, ui = {
                label = "Opacity", widget = "slider", min = 50, max = 100, step = 1, section = "Misc", order = 2
            }},
            displayMode = { type = "editmode", default = "both", ui = {
                label = "Display Mode", widget = "dropdown", values = { both = "Icon & Name", icon = "Icon Only", name = "Name Only" }, section = "Misc", order = 3
            }},
            hideWhenInactive = { type = "editmode", default = false, ui = {
                label = "Hide when inactive", widget = "checkbox", section = "Misc", order = 4
            }},
            showTimer = { type = "editmode", default = true, ui = {
                label = "Show Timer", widget = "checkbox", section = "Misc", order = 5
            }},
            showTooltip = { type = "editmode", default = true, ui = {
                label = "Show Tooltips", widget = "checkbox", section = "Misc", order = 6
            }},
            -- Marker: enable Text section in settings UI for this component
            supportsText = { type = "addon", default = true },
            -- Note: Border section intentionally left empty for now (exploratory later)
        },
        ApplyStyling = ApplyCooldownViewerStyling,
    })
    self:RegisterComponent(trackedBars)
end

function addon:LinkComponentsToDB()
    for id, component in pairs(self.Components) do
        if not self.db.profile.components[id] then
            self.db.profile.components[id] = {}
        end
        component.db = self.db.profile.components[id]
    end
end

function addon:ApplyStyles()
    for id, component in pairs(self.Components) do
        if component.ApplyStyling then
            component:ApplyStyling()
        end
    end
end

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for id, component in pairs(self.Components) do
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
