local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

--[[
Right-side custom settings pane for ScooterMod.

Goals:
 - Replace Blizzard's SettingsListTemplate-based right pane with a fully
   Scooter-owned implementation so EditMode churn cannot cause flicker.
 - Preserve the existing ScooterMod window shell, header behaviors, and
   theming (Roboto + green/white/gray).
 - Provide a simple API to render arrays of Settings element initializers
   (the same objects produced by Settings.CreateElementInitializer /
   Settings.CreateSettingInitializer) without using SettingsListTemplate.
]]

panel.RightPane = panel.RightPane or {}
local RightPane = panel.RightPane

-- Create (if needed) a fixed footer area anchored to the bottom of the right pane.
-- The scroll area is clamped above this footer so scrolling content never overlaps it.
local function EnsureFooter(self)
    if not self or not self.frame then return nil end
    if self.Footer then return self.Footer end

    local footer = CreateFrame("Frame", nil, self.frame)
    footer:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -24, 0) -- align with scrollframe's right inset
    footer:SetHeight(0)
    footer:Hide()
    self.Footer = footer

    return footer
end

-- Create a Rules-style divider (green line segments + small diamond) inside the given parent.
local function EnsureRulesStyleDivider(parent)
    if not parent then return end
    if parent.ScooterDivider then return parent.ScooterDivider end

    local divider = CreateFrame("Frame", nil, parent)
    divider:SetHeight(12)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    local colorR, colorG, colorB, colorA = 0.20, 0.90, 0.30, 0.30

    local lineLeft = divider:CreateTexture(nil, "ARTWORK")
    lineLeft:SetColorTexture(colorR, colorG, colorB, colorA)
    lineLeft:SetHeight(1)
    lineLeft:SetPoint("LEFT", divider, "LEFT", 16, 0)
    lineLeft:SetPoint("RIGHT", divider, "CENTER", -10, 0)

    local lineRight = divider:CreateTexture(nil, "ARTWORK")
    lineRight:SetColorTexture(colorR, colorG, colorB, colorA)
    lineRight:SetHeight(1)
    lineRight:SetPoint("LEFT", divider, "CENTER", 10, 0)
    lineRight:SetPoint("RIGHT", divider, "RIGHT", -16, 0)

    local ornament = divider:CreateTexture(nil, "OVERLAY")
    ornament:SetColorTexture(0.20, 0.90, 0.30, 0.55)
    ornament:SetSize(6, 6)
    ornament:SetPoint("CENTER", divider, "CENTER", 0, 0)
    ornament:SetRotation(math.rad(45))

    divider._lineLeft = lineLeft
    divider._lineRight = lineRight
    divider._ornament = ornament

    parent.ScooterDivider = divider
    return divider
end

-- Initialize the right pane inside the container created by
-- ui/ScooterSettingsPanel.lua. Safe to call multiple times; subsequent
-- calls are ignored once initialized.
function RightPane:Init(ownerFrame, container)
    if self.initialized and self.owner == ownerFrame and self.container == container then
        return
    end

    self.owner = ownerFrame
    self.container = container

    -- Root frame for all right-pane content (header + scroll area)
    local frame = CreateFrame("Frame", nil, container)
    frame:SetAllPoints(container)
    self.frame = frame

    ------------------------------------------------------------------------
    -- Header: title + Copy-from dropdown + Collapse All + CDM button
    ------------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(40)
    self.Header = header

    -- Title (component name, e.g., "Player", "Essential Cooldowns")
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 0, -2)
    title:SetJustifyH("LEFT")
    -- Make the active tab's header label stand out: 50% larger with a thick outline.
    if panel.ApplyRobotoWhite then
        panel.ApplyRobotoWhite(title, 27, "THICKOUTLINE")
    end
    header.Title = title

    -- Collapse All button (right-most header control)
    local collapse = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    collapse:SetSize(110, 22)
    collapse:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    collapse.Text:SetText("Collapse All")
    if panel.ApplyButtonTheme then
        panel.ApplyButtonTheme(collapse)
    end
    header.CollapseAllButton = collapse

    collapse:SetScript("OnClick", function()
        local f = RightPane.owner
        if not f or not f.CatRenderers or not f.CurrentCategory then return end
        local entry = f.CatRenderers[f.CurrentCategory]
        if not entry or not entry.componentId then return end
        local cid = entry.componentId
        panel._expanded = panel._expanded or {}
        panel._expanded[cid] = panel._expanded[cid] or {}
        for sectionKey in pairs(panel._expanded[cid]) do
            panel._expanded[cid][sectionKey] = false
        end
        if panel.RefreshCurrentCategory then
            panel.RefreshCurrentCategory()
        end
    end)

    -- Placeholder for the "Cooldown Manager Settings" button; created lazily
    -- by ScooterSettingsPanel when needed so logic stays centralized there.
    header.ScooterCDMButton = header.ScooterCDMButton or nil

    ------------------------------------------------------------------------
    -- Scroll area
    ------------------------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 0)
    self.ScrollFrame = scrollFrame

    -- Scroll child that actually hosts all rows. IMPORTANT: give this frame an
    -- explicit width that tracks the scroll frame's width; if we leave width at
    -- 0, children anchored LEFT/RIGHT will collapse to 0‑width and appear
    -- "invisible" even though they exist.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetHeight(10)
    scrollFrame:SetScrollChild(content)
    self.Content = content

    -- Keep the scroll child width in sync with the visible scroll area so rows
    -- fill the pane correctly and scrolling/clipping behave like a normal
    -- Settings list.
    local function UpdateContentWidth(sf)
        if not sf or not sf:GetWidth() or not content then return end
        -- Subtract a small padding so we don't overlap the scrollbar groove.
        local w = math.max(1, sf:GetWidth() - 4)
        content:SetWidth(w)
    end
    UpdateContentWidth(scrollFrame)
    scrollFrame:HookScript("OnSizeChanged", function(sf)
        UpdateContentWidth(sf)
        if sf.UpdateScrollChildRect then
            sf:UpdateScrollChildRect()
        end
    end)

    self.rows = self.rows or {}

    -- Fixed footer area (hidden by default). When shown, the scrollFrame's bottom
    -- anchor is adjusted to sit above it so scrolled content never overlaps.
    EnsureFooter(self)

    self.initialized = true
end

-- Update the header title text.
-- Optional tooltipText parameter: if provided, displays a ScooterMod info icon next to the title.
-- The title info icon uses a larger size (40px) for better visibility at the category header level.
function RightPane:SetTitle(text, tooltipText)
    if not self.Header or not self.Header.Title then return end
    self.Header.Title:SetText(text or "")

    -- Handle info icon for category header tooltip
    local header = self.Header
    local TITLE_INFO_ICON_SIZE = 40  -- Larger size for category header visibility
    if tooltipText and tooltipText ~= "" then
        -- Create or reuse the title info icon
        if not header.TitleInfoIcon then
            if panel.CreateInfoIconForLabel then
                -- Use deferred positioning to ensure the title text width is available
                local icon = panel.CreateInfoIconForLabel(header.Title, tooltipText, 8, 0, TITLE_INFO_ICON_SIZE)
                header.TitleInfoIcon = icon
            end
        else
            -- Update existing icon's tooltip text and ensure it's visible
            header.TitleInfoIcon.TooltipText = tooltipText
            -- Update the OnEnter script with new tooltip text
            header.TitleInfoIcon:SetScript("OnEnter", function(self)
                if self.Highlight then self.Highlight:SetAlpha(0.3) end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -22, -22)
                GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
                -- Style tooltip with Roboto white
                if panel and panel.ApplyRobotoWhite then
                    local regions = { GameTooltip:GetRegions() }
                    for i = 1, #regions do
                        local region = regions[i]
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            panel.ApplyRobotoWhite(region, 12)
                        end
                    end
                end
                GameTooltip:Show()
            end)
            header.TitleInfoIcon:Show()
        end

        -- Defer positioning to ensure title text width is computed
        if header.TitleInfoIcon then
            C_Timer.After(0, function()
                if header.TitleInfoIcon and header.Title then
                    header.TitleInfoIcon:ClearAllPoints()
                    local textWidth = header.Title:GetStringWidth() or 0
                    if textWidth > 0 then
                        header.TitleInfoIcon:SetPoint("LEFT", header.Title, "LEFT", textWidth + 8, 0)
                    else
                        header.TitleInfoIcon:SetPoint("LEFT", header.Title, "RIGHT", 8, 0)
                    end
                end
            end)
        end
    else
        -- No tooltip text: hide the info icon if it exists
        if header.TitleInfoIcon then
            header.TitleInfoIcon:Hide()
        end
    end
end

local function AcquireRow(self, index, template, reuseKey)
    self.rows = self.rows or {}
    local row = self.rows[index]
    if row and (row._template ~= template or row._reuseKey ~= reuseKey) then
        -- Template changed; discard the old frame and create a fresh one.
        -- Explicitly hide and detach the previous frame so it cannot remain
        -- visible "behind" the panel when we switch categories.
        row:Hide()
        row:SetParent(nil)
        self.rows[index] = nil
        row = nil
    end
    if not row then
        -- Parent rows to the ScrollFrame's scroll child; the ScrollFrame
        -- handles clipping while we control layout and scrolling behavior.
        row = CreateFrame("Frame", nil, self.Content, template or "Frame")
        self.rows[index] = row
        row._template = template
        row._reuseKey = reuseKey
    else
        row:SetParent(self.Content)
        row._template = template
        row._reuseKey = reuseKey
    end
    return row
end

-- Clear any cached row frames so the next Display call rebuilds widgets fresh.
function RightPane:Invalidate()
    if not self.rows then
        return
    end
    for _, row in ipairs(self.rows) do
        if row then
            row:Hide()
            row:SetParent(nil)
        end
    end
    if type(wipe) == "function" then
        wipe(self.rows)
    else
        self.rows = {}
    end
end

-- Render an array of Settings element initializers into the custom right pane.
-- Each initializer is expected to expose:
--   - .template (string) – frame template name
--   - :InitFrame(frame) – function to initialize the frame
--   - :GetExtent() – optional function returning desired row height
function RightPane:Display(initializers)
    if not self.initialized or not self.frame or not self.Content then return end
    if type(initializers) ~= "table" then return end

    -- Footer is opt-in per page. Default to hidden on each render so it cannot
    -- "stick" when switching categories.
    if self.Footer and self.Footer:IsShown() then
        self:SetFooter({ height = 0 })
    end

    -- Determine the active category/component context so we can scope row reuse.
    -- Some pages use simple element initializers without a `.data` payload; without
    -- a component-scoped fallback reuse key those rows can be incorrectly recycled
    -- across categories, causing "stuck" UI (e.g., Rules' Add Rule button or Apply All
    -- disclaimer text appearing on Manage Profiles).
    local activeComponentId
    do
        local owner = self.owner
        local currentKey = owner and owner.CurrentCategory
        local entry = (currentKey and owner and owner.CatRenderers) and owner.CatRenderers[currentKey] or nil
        activeComponentId = (entry and entry.componentId) or currentKey or "unknown"
    end

    local content = self.Content
    local y = -8
    -- Base vertical gap between consecutive rows (non-tabbed sections).
    -- This intentionally provides generous breathing room now that we own
    -- the pane layout; tabbed sections retain their own internal spacing.
    local baseRowGap = 10
    local index = 1

    -- Instantiate rows
    for _, init in ipairs(initializers) do
        if init then
            -- Respect SettingsSearchableElementMixin:AddShownPredicate by
            -- querying ShouldShow() when available. This mirrors the stock
            -- SettingsListTemplate behavior and is required for collapsible
            -- sections, Spec Profiles rows, and other predicate‑gated rows.
            local shouldShow = true
            if type(init.ShouldShow) == "function" then
                local ok, result = pcall(init.ShouldShow, init)
                if ok and result == false then
                    shouldShow = false
                elseif not ok then
                    shouldShow = false
                end
            end

            if shouldShow then
                -- Resolve the underlying frame template from the initializer.
                local template
                if type(init.GetTemplate) == "function" then
                    local ok, tpl = pcall(init.GetTemplate, init)
                    if ok then
                        template = tpl
                    end
                end
                -- Defensive fallback: use a generic list element if the initializer
                -- doesn't expose a template. All of our ScooterMod initializers
                -- are created via Settings.CreateElementInitializer or
                -- Settings.CreateSettingInitializer so GetTemplate should succeed.
                if type(template) ~= "string" or template == "" then
                    template = "SettingsListElementTemplate"
                end
                local reuseKey
                local slotIndex = index
                do
                    local data = init.data
                    if type(data) == "table" then
                        local componentId = data.componentId or data.ComponentID or data.componentID
                        if componentId and data.settingId then
                            reuseKey = string.format("%s::setting::%s", tostring(componentId), tostring(data.settingId))
                        elseif componentId and data.sectionKey then
                            reuseKey = string.format("%s::section::%s", tostring(componentId), tostring(data.sectionKey))
                        elseif componentId and data.name then
                            reuseKey = string.format("%s::name::%s", tostring(componentId), tostring(data.name))
                        elseif data.settingId then
                            reuseKey = string.format("setting::%s", tostring(data.settingId))
                        elseif data.sectionKey then
                            reuseKey = string.format("section::%s", tostring(data.sectionKey))
                        elseif data.name then
                            reuseKey = string.format("name::%s", tostring(data.name))
                        end
                    end
                end
                -- Fallback: if the initializer doesn't carry identity data, still
                -- scope reuse to the active component/category so rows cannot leak
                -- across pages when switching tabs.
                if not reuseKey then
                    reuseKey = string.format("%s::row::%d::tpl::%s", tostring(activeComponentId), tonumber(slotIndex) or 0, tostring(template))
                end
                local row = AcquireRow(self, slotIndex, template, reuseKey)
                index = slotIndex + 1

                -- Force-hide the row so that Show() at the end of the loop triggers OnShow scripts.
                -- This ensures that recycled frames (e.g. sliders) fully refresh their state/layout.
                row:Hide()

                -- Provide GetElementData/GetElementDataIndex so Blizzard mixins
                -- such as SettingsExpandableSectionMixin can function correctly
                -- without being hosted in a SettingsList ScrollBox.
                -- CRITICAL: Always update GetElementData even on recycled frames
                -- to ensure the current initializer (with correct unit/component
                -- closures) is returned. Otherwise, recycled Unit Frame rows
                -- would return stale initializers with wrong unit keys.
                row.GetElementData = function()
                    return init
                end
                if type(row.GetElementDataIndex) ~= "function" then
                    local thisIndex = index - 1
                    row.GetElementDataIndex = function()
                        return thisIndex
                    end
                end

                row:ClearAllPoints()
                -- Provide extra vertical spacing before/after collapsible section
                -- headers to avoid the cramped look from the stock list layout.
                -- IMPORTANT UX TWEAK (2025-11-18):
                -- - When a section is EXPANDED, keep generous spacing around the header so
                --   controls in that section have breathing room above/below.
                -- - When a section is COLLAPSED, tighten the space that follows the header
                --   so a stack of collapsed headers does not look overly sparse.
                -- - Spacing between the last control in a section and the NEXT section
                --   header remains governed by the baseRowGap; only the gap AFTER a
                --   collapsed header is reduced.
                local topPad, bottomPad = 0, 0
                local gapAfterRow = baseRowGap
                if template == "ScooterExpandableSectionTemplate" then
                    local data = init.data or {}
                    local cid = data.componentId
                    local sectionKey = data.sectionKey
                    local isExpanded = false
                    if cid and sectionKey and panel and type(panel.IsSectionExpanded) == "function" then
                        isExpanded = panel:IsSectionExpanded(cid, sectionKey)
                    end

                    if isExpanded then
                        -- Expanded section: keep the original, more generous padding.
                        topPad = 8
                        bottomPad = 6
                        gapAfterRow = baseRowGap
                    else
                        -- Collapsed section: slightly tighter padding and a smaller
                        -- post-header gap so consecutive headers sit closer together.
                        topPad = 4
                        bottomPad = 2
                        gapAfterRow = 4
                    end
                end

                y = y - topPad
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

                -- Initialize the row via the initializer, guarding against errors.
                if type(init.InitFrame) == "function" then
                    pcall(init.InitFrame, init, row)
                end

                local height
                if type(init.GetExtent) == "function" then
                    local ok, extent = pcall(init.GetExtent, init)
                    if ok then height = tonumber(extent) end
                end
                if not height or height <= 0 then
                    height = row:GetHeight() > 0 and row:GetHeight() or 30
                end
                row:SetHeight(height)
                -- After each row, add its own padding plus a row-specific gap so
                -- standard controls aren't cramped together. Collapsed section headers
                -- use a slightly smaller gap, while expanded sections keep the original
                -- breathing room. Tabbed-section rows are laid out inside their own
                -- frames and are unaffected.
                y = y - height - bottomPad - gapAfterRow

                -- Ensure the row is visible even if the template hid it during InitFrame.
                row:Show()
            end
        end
    end

    -- Hide any leftover rows from prior renders.
    if self.rows then
        for i = index, #self.rows do
            if self.rows[i] then
                self.rows[i]:Hide()
            end
        end
    end

    content:SetHeight(math.max(0, -y + 8))
    if self.ScrollFrame and self.ScrollFrame.UpdateScrollChildRect then
        self.ScrollFrame:UpdateScrollChildRect()
    end
end

-- Show a fixed footer message at the bottom of the right pane.
-- The footer is non-scrolling and reserves space by clamping the scroll area above it.
-- opts:
--   - height (number): footer height in px (required)
--   - onInit(footerFrame): callback to (re)build footer widgets
function RightPane:SetFooter(opts)
    if not self or not self.initialized or not self.frame or not self.ScrollFrame then return end
    opts = opts or {}
    local footer = EnsureFooter(self)
    if not footer then return end

    local height = tonumber(opts.height) or 0
    if height <= 0 then
        -- Disable footer
        footer:Hide()
        footer:SetHeight(0)
        self.ScrollFrame:ClearAllPoints()
        if self.Header then
            self.ScrollFrame:SetPoint("TOPLEFT", self.Header, "BOTTOMLEFT", 0, -4)
        else
            self.ScrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -4)
        end
        self.ScrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -24, 0)
        if self.ScrollFrame.UpdateScrollChildRect then self.ScrollFrame:UpdateScrollChildRect() end
        return
    end

    footer:SetHeight(height)
    footer:Show()

    -- Clamp scroll area above footer
    self.ScrollFrame:ClearAllPoints()
    if self.Header then
        self.ScrollFrame:SetPoint("TOPLEFT", self.Header, "BOTTOMLEFT", 0, -4)
    else
        self.ScrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -4)
    end
    self.ScrollFrame:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)

    if type(opts.onInit) == "function" then
        pcall(opts.onInit, footer)
    end

    if self.ScrollFrame.UpdateScrollChildRect then self.ScrollFrame:UpdateScrollChildRect() end
end

-- Convenience helper: show/hide a centered bottom notice with a Rules-style divider.
-- This is used by the Profiles → Manage page to display a reload requirement.
function RightPane:SetBottomNotice(opts)
    if not self then return end
    opts = opts or {}
    local messageTop = tostring(opts.messageTop or "")
    local messageSuffix = tostring(opts.messageSuffix or "")
    local emphasisWord = tostring(opts.emphasisWord or "")
    local messageBottom = tostring(opts.messageBottom or "")
    local color = opts.color or { 1.0, 0.82, 0.0, 1.0 }
    local height = tonumber(opts.height) or 120

    -- Empty => hide
    if (messageTop == "" and emphasisWord == "" and messageBottom == "") then
        self:SetFooter({ height = 0 })
        return
    end

    self:SetFooter({
        height = height,
        onInit = function(footer)
            -- Divider
            local divider = EnsureRulesStyleDivider(footer)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -2)
            divider:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -2)

            -- Container for text, centered in the footer area
            if not footer.ScooterNoticeContainer then
                local c = CreateFrame("Frame", nil, footer)
                footer.ScooterNoticeContainer = c
            end
            local c = footer.ScooterNoticeContainer
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -6)
            c:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 6)

            local function applyFont(fs, size, flags, forceBold)
                if not fs then return end
                if panel and panel.ApplyRobotoWhite then
                    panel.ApplyRobotoWhite(fs, size, flags)
                end
                if forceBold then
                    local fonts = addon and addon.Fonts or nil
                    if fonts and fonts.ROBOTO_BLD then
                        fs:SetFont(fonts.ROBOTO_BLD, size or 16, flags or "")
                    end
                end
                if fs.SetTextColor then
                    fs:SetTextColor(color[1], color[2], color[3], color[4])
                end
            end

            -- === LINE 1: prefix + bold-underlined word + suffix (inline) ===
            if not footer.ScooterNoticeLine1 then
                footer.ScooterNoticeLine1 = CreateFrame("Frame", nil, c)
            end
            local line1 = footer.ScooterNoticeLine1
            line1:ClearAllPoints()
            line1:SetPoint("TOP", c, "TOP", 0, 0)
            line1:SetHeight(22)

            if not footer.ScooterNoticePrefix then
                footer.ScooterNoticePrefix = line1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                footer.ScooterNoticePrefix:SetJustifyH("LEFT")
                footer.ScooterNoticePrefix:SetJustifyV("TOP")
                footer.ScooterNoticePrefix:SetWordWrap(false)
            end
            if not footer.ScooterNoticeWord then
                footer.ScooterNoticeWord = line1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                footer.ScooterNoticeWord:SetJustifyH("LEFT")
                footer.ScooterNoticeWord:SetJustifyV("TOP")
                footer.ScooterNoticeWord:SetWordWrap(false)
            end
            if not footer.ScooterNoticeSuffix then
                footer.ScooterNoticeSuffix = line1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                footer.ScooterNoticeSuffix:SetJustifyH("LEFT")
                footer.ScooterNoticeSuffix:SetJustifyV("TOP")
                footer.ScooterNoticeSuffix:SetWordWrap(false)
            end

            local topSize = opts.topSize or 16
            local wordSize = opts.wordSize or topSize
            local prefixFS = footer.ScooterNoticePrefix
            local wordFS = footer.ScooterNoticeWord
            local suffixFS = footer.ScooterNoticeSuffix

            applyFont(prefixFS, topSize, "", false)
            applyFont(wordFS, wordSize, "OUTLINE", true)
            applyFont(suffixFS, topSize, "", false)

            prefixFS:SetText(messageTop)
            wordFS:SetText(emphasisWord)
            suffixFS:SetText(messageSuffix)

            prefixFS:ClearAllPoints()
            wordFS:ClearAllPoints()
            suffixFS:ClearAllPoints()

            prefixFS:SetPoint("LEFT", line1, "LEFT", 0, 0)
            wordFS:SetPoint("LEFT", prefixFS, "RIGHT", 0, 0)
            suffixFS:SetPoint("LEFT", wordFS, "RIGHT", 0, 0)

            local showLine1 = (messageTop ~= "" or emphasisWord ~= "" or messageSuffix ~= "")
            line1:SetShown(showLine1)
            prefixFS:SetShown(messageTop ~= "")
            wordFS:SetShown(emphasisWord ~= "")
            suffixFS:SetShown(messageSuffix ~= "")

            -- Center the whole line by sizing the container to the sum of the three widths.
            C_Timer.After(0, function()
                if not line1 or not line1:IsShown() then return end
                local w1 = (prefixFS.GetStringWidth and prefixFS:GetStringWidth()) or 0
                local w2 = (wordFS.GetStringWidth and wordFS:GetStringWidth()) or 0
                local w3 = (suffixFS.GetStringWidth and suffixFS:GetStringWidth()) or 0
                local total = math.max(1, w1 + w2 + w3)
                line1:SetWidth(total)
            end)

            -- Underline for the emphasis word (FontStrings don't support underline flags)
            if not footer.ScooterNoticeUnderline then
                local ul = line1:CreateTexture(nil, "OVERLAY")
                ul:SetColorTexture(color[1], color[2], color[3], math.min(1, (color[4] or 1) * 0.95))
                ul:SetHeight(2)
                footer.ScooterNoticeUnderline = ul
            end
            local ul = footer.ScooterNoticeUnderline
            ul:ClearAllPoints()
            ul:SetPoint("TOP", wordFS, "BOTTOM", 0, -1)
            ul:SetShown(emphasisWord ~= "")
            C_Timer.After(0, function()
                if not ul or not wordFS or not wordFS:IsShown() then return end
                local w = (wordFS.GetStringWidth and wordFS:GetStringWidth()) or 0
                ul:SetWidth(math.max(24, w + 6))
            end)

            -- === PARAGRAPH: wrapped message below ===
            if not footer.ScooterNoticeBottom then
                footer.ScooterNoticeBottom = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                footer.ScooterNoticeBottom:SetJustifyH("CENTER")
                footer.ScooterNoticeBottom:SetJustifyV("TOP")
                footer.ScooterNoticeBottom:SetWordWrap(true)
            end
            local bottomFS = footer.ScooterNoticeBottom
            applyFont(bottomFS, opts.bottomSize or 16, "", false)
            bottomFS:ClearAllPoints()
            bottomFS:SetPoint("TOP", line1, "BOTTOM", 0, -10)
            bottomFS:SetPoint("LEFT", c, "LEFT", 16, 0)
            bottomFS:SetPoint("RIGHT", c, "RIGHT", -16, 0)
            bottomFS:SetText(messageBottom)
            bottomFS:SetShown(messageBottom ~= "")
        end,
    })
end


