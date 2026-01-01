local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Lightweight theming helpers --------------------------------------------------
do
    local fonts = addon and addon.Fonts or nil
    local brandR, brandG, brandB = 0.20, 0.90, 0.30 -- Scooter green

    -- Apply Roboto + green to a FontString (idempotent)
    function panel.ApplyGreenRoboto(fs, size, flags)
        if not fs or not fs.SetFont then return end
        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
        local _, currentSize, currentFlags = fs:GetFont()
        fs:SetFont(face, size or currentSize or 12, flags or currentFlags or "")
        if fs.SetTextColor then fs:SetTextColor(brandR, brandG, brandB, 1) end
    end

    -- Apply Roboto but preserve current color
    function panel.ApplyRoboto(fs, size, flags)
        if not fs or not fs.SetFont then return end
        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
        local r, g, b, a = 1, 1, 1, 1
        if fs.GetTextColor then r, g, b, a = fs:GetTextColor() end
        local _, currentSize, currentFlags = fs:GetFont()
        fs:SetFont(face, size or currentSize or 12, flags or currentFlags or "")
        if fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
    end

    -- Apply Roboto and force white
    function panel.ApplyRobotoWhite(fs, size, flags)
        if not fs then return end
        panel.ApplyRoboto(fs, size, flags)
        if fs.SetTextColor then fs:SetTextColor(1, 1, 1, 1) end
    end

    -- Desaturate/tint a button's textures to neutral gray while keeping volume
    local function tintTexture(tex, gray)
        if not tex or not tex.SetVertexColor then return end
        pcall(tex.SetDesaturated, tex, true)
        tex:SetVertexColor(gray, gray, gray)
    end

    function panel.ApplyButtonTheme(btn)
        if not btn then return end
        if btn.Text then
            local _, sz, fl = btn.Text:GetFont()
            panel.ApplyGreenRoboto(btn.Text, sz, fl)
        end
        tintTexture(btn.GetNormalTexture and btn:GetNormalTexture() or nil, 0.97)
        tintTexture(btn.GetPushedTexture and btn:GetPushedTexture() or nil, 0.93)
        do
            if btn.SetHighlightTexture then pcall(btn.SetHighlightTexture, btn, "Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD") end
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
            if hl then hl:SetDesaturated(false); hl:SetVertexColor(1, 1, 1); hl:SetAlpha(0.45) end
        end
        tintTexture(btn.GetDisabledTexture and btn:GetDisabledTexture() or nil, 0.90)
        local regions = { btn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                tintTexture(r, 0.97)
            end
        end
    end

    local function forEachDescendant(frame, fn, depth)
        if not frame or (depth and depth <= 0) then return end
        if frame.GetRegions then
            local regions = { frame:GetRegions() }
            for i = 1, #regions do fn(regions[i]) end
        end
        if frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, #children do fn(children[i]); forEachDescendant(children[i], fn, (depth and depth-1) or 2) end
        end
    end

    local function isFontString(obj)
        return obj and obj.IsObjectType and obj:IsObjectType("FontString")
    end

    function panel.ApplyControlTheme(root)
        if not root then return end
        forEachDescendant(root, function(obj)
            if isFontString(obj) then
                panel.ApplyRoboto(obj)
            elseif obj and obj.IsObjectType and obj:IsObjectType("Button") then
                local objType = obj.GetObjectType and obj:GetObjectType() or ""
                if objType == "CheckButton" then
                    -- Theme checkbox checkmarks to green
                    panel.ThemeCheckbox(obj)
                else
                    local function tint(tex)
                        if tex and tex.SetVertexColor then tex:SetDesaturated(true); tex:SetVertexColor(brandR, brandG, brandB) end
                    end
                    tint(obj.GetNormalTexture and obj:GetNormalTexture() or nil)
                    tint(obj.GetPushedTexture and obj:GetPushedTexture() or nil)
                    if obj.SetHighlightTexture then pcall(obj.SetHighlightTexture, obj, "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD") end
                    local hl = obj.GetHighlightTexture and obj:GetHighlightTexture() or nil
                    if hl then hl:SetDesaturated(false); hl:SetVertexColor(1,1,1); hl:SetAlpha(0.25) end
                end
            elseif obj and obj.SliderWithSteppers then
                -- Theme slider value text to green (for SettingsSliderControlTemplate frames)
                panel.ThemeSliderValue(obj)
            end
        end, 3)

        -- Also check the root frame itself for SliderWithSteppers
        if root and root.SliderWithSteppers then
            panel.ThemeSliderValue(root)
        end
        -- And check if root is a CheckButton
        if root and root.IsObjectType and root:IsObjectType("CheckButton") then
            panel.ThemeCheckbox(root)
        end
        -- Check for Checkbox child (common in SettingsCheckboxControlTemplate)
        if root and root.Checkbox and root.Checkbox.IsObjectType and root.Checkbox:IsObjectType("CheckButton") then
            panel.ThemeCheckbox(root.Checkbox)
        end
    end

    function panel.StyleDropdownLabel(dropdown, scale)
        if not dropdown or not dropdown.Text or not dropdown.Text.GetFont then return end
        local face, sz, flags = dropdown.Text:GetFont()
        if not dropdown.Text._ScooterBaseFont then
            dropdown.Text._ScooterBaseFont = { face, sz or 12, flags }
        end
        local baseSize = (dropdown.Text._ScooterBaseFont and dropdown.Text._ScooterBaseFont[2]) or (sz or 12)
        local newSize = math.floor(baseSize * (scale or 1.25) + 0.5)
        panel.ApplyRobotoWhite(dropdown.Text, newSize, flags)
    end

    if not panel._dropdownMenuHooked then
        panel._dropdownMenuHooked = true
        hooksecurefunc("ToggleDropDownMenu", function(level)
            local function styleLevel(lvl)
                local list = _G["DropDownList" .. tostring(lvl)]
                if not list or not list:IsShown() then return end
                local i = 1
                while true do
                    local btn = _G[list:GetName() .. "Button" .. i]
                    if not btn then break end
                    local fs = (btn.GetFontString and btn:GetFontString()) or btn.NormalText
                    if fs and fs.GetFont then
                        local face, sz, flags = fs:GetFont()
                        if not fs._ScooterBaseFont then
                            fs._ScooterBaseFont = { face, sz or 12, flags }
                        end
                        local baseSize = (fs._ScooterBaseFont and fs._ScooterBaseFont[2]) or (sz or 12)
                        panel.ApplyRobotoWhite(fs, math.floor(baseSize * 1.25 + 0.5), flags)
                    end
                    i = i + 1
                end
            end
            C_Timer.After(0, function() styleLevel(level or 1) end)
        end)
    end

    -- Apply class-colored background to a spec badge frame
    -- classFile is the uppercase class token (e.g., "DEATHKNIGHT", "MAGE")
    function panel.ApplySpecBadgeTheme(badge, classFile)
        if not badge then return end
        local colors = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) or {}
        local color = classFile and colors[classFile]
        local r, g, b = 0.3, 0.3, 0.3 -- fallback gray
        if color then
            r, g, b = color.r or 0.3, color.g or 0.3, color.b or 0.3
        end
        -- Semi-transparent class-colored background
        if badge.SetBackdropColor then
            badge:SetBackdropColor(r, g, b, 0.6)
        end
        -- Subtle darker border
        if badge.SetBackdropBorderColor then
            badge:SetBackdropBorderColor(r * 0.5, g * 0.5, b * 0.5, 0.8)
        end
    end

    -- Get class color as r,g,b values (0-1)
    function panel.GetClassColor(classFile)
        local colors = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) or {}
        local color = classFile and colors[classFile]
        if color then
            return color.r or 1, color.g or 1, color.b or 1
        end
        return 1, 1, 1
    end

    function panel.SkinCategoryList(categoryList)
        if not categoryList or not categoryList.ScrollBox or not categoryList.ScrollBox.ScrollTarget then return end
        local target = categoryList.ScrollBox.ScrollTarget
        -- Sidebar layout knobs (tweak as desired)
        panel.SidebarLayout = panel.SidebarLayout or { itemSpacing = 2, gapHeaderToList = 10, gapHeaderToHeader = 0 }
		-- Tighten global vertical spacing for the sidebar list without touching top/left/right padding
        do
            local view = categoryList.ScrollBox.GetView and categoryList.ScrollBox:GetView()
            local pad = view and view.GetPadding and view:GetPadding()
            local desiredSpacing = (panel.SidebarLayout and panel.SidebarLayout.itemSpacing) or 2
            if pad and pad.SetSpacing then pcall(pad.SetSpacing, pad, desiredSpacing) end
        end
		local children = { target:GetChildren() }
		for i = 1, #children do
			local f = children[i]
			local label = (f and (f.Text or f.Name or f.Label))
			if label then
				local _, size, flags = label:GetFont()
				local text = label.GetText and label:GetText() or ""
				local isHeader = (f and f.Toggle == nil and f.Background ~= nil) -- header has no Toggle but has a Background
				panel.ApplyGreenRoboto(label, size, flags)
				if not isHeader and label.SetTextColor then
					label:SetTextColor(1, 1, 1, 1)
				end

				-- Attach green '+' to header right edge to control our parent category (skip for Profiles)
				if isHeader and panel._sidebarParents and text and panel._sidebarParents[text] and text ~= "Profiles" then
					local parentCat = panel._sidebarParents[text]
					if not f.ScooterCollapse then
						local btn = CreateFrame("Button", nil, f)
						btn:SetSize(16, 16)
						btn:SetPoint("RIGHT", f, "RIGHT", -6, 0)
						-- Create a minimal button with no Blizzard textures
						-- Avoid calling SetNormalTexture(nil) which errors on some clients
						local glyph = btn:CreateFontString(nil, "OVERLAY")
						glyph:SetPoint("CENTER")
						panel.ApplyGreenRoboto(glyph, 16, "OUTLINE")
						btn._glyph = glyph
						btn:SetScript("OnClick", function()
							if not parentCat then return end
							-- Prefer native toggle path to minimize churn
							local elementData = categoryList.FindCategoryElementData and categoryList:FindCategoryElementData(parentCat)
							local sb = categoryList and categoryList.ScrollBox
							local button = elementData and sb and sb.FindFrame and sb:FindFrame(elementData) or nil
							if button and button.Toggle and button.Toggle.Click then
								button.Toggle:Click()
							else
								local newState = not (parentCat.IsExpanded and parentCat:IsExpanded())
								parentCat:SetExpanded(newState)
								if categoryList.CreateCategories then pcall(categoryList.CreateCategories, categoryList) end
							end
							panel._sidebarExpanded = panel._sidebarExpanded or {}
							panel._sidebarExpanded[text] = (parentCat and parentCat.IsExpanded and parentCat:IsExpanded()) and true or false
							-- Skin after recycle
							if panel and panel.SkinCategoryList then
								C_Timer.After(0, function() panel.SkinCategoryList(categoryList) end)
							end
						end)
						f.ScooterCollapse = btn
					end
					-- Update glyph per state: '+' collapsed, '−' expanded
					if f.ScooterCollapse and f.ScooterCollapse._glyph and parentCat then
						f.ScooterCollapse._glyph:SetText(parentCat:IsExpanded() and "−" or "+")
					end
				end

				-- Hide the duplicate parent row label & default chevron; set measured extent based on expanded/collapsed
				if f.GetElementData then
					local ok, init = pcall(f.GetElementData, f)
					local category = ok and init and init.data and init.data.category or nil
					local isOurParent = false
					local parentCat
					if category and panel._sidebarParents then
						local name = category.GetName and category:GetName() or nil
						parentCat = (name and panel._sidebarParents[name]) or nil
						isOurParent = parentCat ~= nil
					end
					if isOurParent then
								if f.Toggle then f.Toggle:Hide() end
								if f.Texture then f.Texture:Hide() end
							if f.NewFeature then f.NewFeature:Hide() end
                                if label and label.SetText then label:SetText(" ") end
                                -- Drive the visual gap by directly setting the row height so net gap matches target
                                do
                                    local gaps = panel.SidebarLayout or {}
								local expanded = (parentCat and parentCat.IsExpanded and parentCat:IsExpanded()) and true or false
                                    local desired = expanded and (gaps.gapHeaderToList or 4) or (gaps.gapHeaderToHeader or 10)
                                    local itemSpacing = (panel.SidebarLayout and panel.SidebarLayout.itemSpacing) or 0
                                    local netHeight = math.max(0, desired - (2 * itemSpacing))
                                    -- Apply height and keep it non-interactive
                                    if netHeight and f.SetHeight then f:SetHeight(netHeight) end
                                    if f.SetFrameLevel and target and target:GetFrameLevel() then
                                        pcall(f.SetFrameLevel, f, math.max(1, (target:GetFrameLevel() or 1) - 1))
                                    end
                                    if f.SetFrameStrata then pcall(f.SetFrameStrata, f, "BACKGROUND") end
                                    if f.EnableMouse then f:EnableMouse(false) end
                                    if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(false) end
                                    if f.SetHitRectInsets then
                                        local w = tonumber(f:GetWidth()) or 200
                                        pcall(f.SetHitRectInsets, f, 0, w, 0, 0) -- zero-width hit rect
                                    end
                                end
								-- Disable selection/clicks on the parent row
								f:EnableMouse(false)
					end
				end
			end
		end

		-- Light reflow to apply height changes without full rebuild (reduces flicker)
		if categoryList and categoryList.ScrollBox and categoryList.ScrollBox.Layout then
			if not panel._sidebarReflowQueued then
				panel._sidebarReflowQueued = true
				C_Timer.After(0, function()
					panel._sidebarReflowQueued = false
					pcall(categoryList.ScrollBox.Layout, categoryList.ScrollBox)
				end)
			end
		end
    end

    -- Helper: Apply Roboto font with green color to a FontString
    local function applyRobotoGreen(fs, size)
        if not fs or not fs.SetFont then return end
        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
        local _, currentSize, currentFlags = fs:GetFont()
        fs:SetFont(face, size or currentSize or 12, currentFlags or "")
        fs:SetTextColor(brandR, brandG, brandB, 1)
    end

    -- Helper: Style menu option buttons when a dropdown menu is opened
    local function styleMenuOptions(menu)
        if not menu then return end
        -- Delay slightly to ensure menu frames are populated
        C_Timer.After(0, function()
            -- The menu's scroll box contains the option buttons
            local scrollBox = menu.ScrollBox or (menu.GetScrollBox and menu:GetScrollBox())
            if scrollBox then
                local function styleButton(btn)
                    if not btn then return end
                    -- Find FontStrings in the button and style them
                    local regions = { btn:GetRegions() }
                    for _, region in ipairs(regions) do
                        if region and region.IsObjectType and region:IsObjectType("FontString") then
                            local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
                            local _, sz, fl = region:GetFont()
                            region:SetFont(face, sz or 12, fl or "")
                        end
                    end
                    -- Also check common child keys
                    if btn.fontString then
                        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
                        local _, sz, fl = btn.fontString:GetFont()
                        btn.fontString:SetFont(face, sz or 12, fl or "")
                    end
                    if btn.Text then
                        local face = (fonts and (fonts.ROBOTO_MED or fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
                        local _, sz, fl = btn.Text:GetFont()
                        btn.Text:SetFont(face, sz or 12, fl or "")
                    end
                end
                -- Iterate through visible frames in the scroll box
                scrollBox:ForEachFrame(styleButton)
            end
        end)
    end

    -- Theme a SettingsDropdownWithButtonsTemplate-based control
    -- Applies ScooterMod green to text, Roboto font, and green arrow icons.
    -- NOTE: Uses minimal hooks. Vertex colors on textures persist through atlas changes,
    -- so icons only need to be set once. Text color and font require hooks since
    -- Blizzard explicitly calls SetTextColor on state changes.
    function panel.ThemeDropdownWithSteppers(control)
        if not control then return end

        -- Use the control itself as the flag anchor to prevent any double-processing
        if control._scooterDropdownThemed then return end
        control._scooterDropdownThemed = true

        -- Theme the dropdown
        local dropdown = control.Dropdown
        if dropdown then
            -- Apply Roboto font with green color to button text
            if dropdown.Text then
                applyRobotoGreen(dropdown.Text)
            end
            -- Tint the small dropdown arrow indicator (shown on hover)
            if dropdown.Arrow then
                dropdown.Arrow:SetVertexColor(brandR, brandG, brandB, 1)
            end
            -- Single hook for text and arrow on state changes
            if dropdown.OnButtonStateChanged then
                hooksecurefunc(dropdown, "OnButtonStateChanged", function(self)
                    if self:IsEnabled() and self.Text then
                        applyRobotoGreen(self.Text)
                    end
                    -- Re-tint arrow in case it gets reset
                    if self.Arrow then
                        self.Arrow:SetVertexColor(brandR, brandG, brandB, 1)
                    end
                end)
            end
            -- Hook menu opening to style dropdown options with Roboto
            if dropdown.OnMenuOpened then
                hooksecurefunc(dropdown, "OnMenuOpened", styleMenuOptions)
            end
        end

        -- Theme the stepper buttons (no hooks needed - vertex colors persist)
        local function themeStepper(btn)
            if not btn then return end
            -- Apply icon tint - persists through atlas changes
            if btn.Icon then
                btn.Icon:SetVertexColor(brandR, brandG, brandB, 1)
            end
        end

        themeStepper(control.IncrementButton)
        themeStepper(control.DecrementButton)
    end

    -- Theme a slider control's value text to ScooterMod green
    -- The value text is displayed in SliderWithSteppers.RightText (and potentially LeftText, TopText, etc.)
    -- Blizzard's MinimalSliderWithSteppersMixin:SetEnabled() resets these to NORMAL_FONT_COLOR (yellow),
    -- so we need a hook to maintain our green color.
    function panel.ThemeSliderValue(control)
        if not control then return end

        -- Find the SliderWithSteppers child - it may be at control.SliderWithSteppers or control itself
        local sliderWithSteppers = control.SliderWithSteppers or control
        if not sliderWithSteppers then return end

        -- Apply green to all label text elements
        local function applyGreenToLabels(slider)
            if slider.RightText and slider.RightText.SetTextColor then
                slider.RightText:SetTextColor(brandR, brandG, brandB, 1)
            end
            if slider.LeftText and slider.LeftText.SetTextColor then
                slider.LeftText:SetTextColor(brandR, brandG, brandB, 1)
            end
            if slider.TopText and slider.TopText.SetTextColor then
                slider.TopText:SetTextColor(brandR, brandG, brandB, 1)
            end
            if slider.MinText and slider.MinText.SetTextColor then
                slider.MinText:SetTextColor(brandR, brandG, brandB, 1)
            end
            if slider.MaxText and slider.MaxText.SetTextColor then
                slider.MaxText:SetTextColor(brandR, brandG, brandB, 1)
            end
        end

        -- Apply immediately
        applyGreenToLabels(sliderWithSteppers)

        -- Mark that we've themed this slider so the global hook can re-apply
        sliderWithSteppers._scooterSliderThemed = true
    end

    -- Helper: Check if a frame belongs to the ScooterMod settings panel
    local function belongsToScooterPanel(frame)
        local p = frame
        local root = addon and addon.SettingsPanel and addon.SettingsPanel.frame
        while p do
            if p == root then return true end
            p = (p.GetParent and p:GetParent()) or nil
        end
        return false
    end

    -- Global hook on MinimalSliderWithSteppersMixin.SetEnabled to maintain green color
    -- This is necessary because Blizzard resets the color to NORMAL_FONT_COLOR when enabling
    if not panel._sliderSetEnabledHooked then
        panel._sliderSetEnabledHooked = true
        if type(MinimalSliderWithSteppersMixin) == "table" and type(MinimalSliderWithSteppersMixin.SetEnabled) == "function" then
            hooksecurefunc(MinimalSliderWithSteppersMixin, "SetEnabled", function(self, enabled)
                -- Only re-apply green for sliders that have been themed and are in our panel
                if self._scooterSliderThemed and enabled and belongsToScooterPanel(self) then
                    if self.RightText and self.RightText.SetTextColor then
                        self.RightText:SetTextColor(brandR, brandG, brandB, 1)
                    end
                    if self.LeftText and self.LeftText.SetTextColor then
                        self.LeftText:SetTextColor(brandR, brandG, brandB, 1)
                    end
                    if self.TopText and self.TopText.SetTextColor then
                        self.TopText:SetTextColor(brandR, brandG, brandB, 1)
                    end
                    if self.MinText and self.MinText.SetTextColor then
                        self.MinText:SetTextColor(brandR, brandG, brandB, 1)
                    end
                    if self.MaxText and self.MaxText.SetTextColor then
                        self.MaxText:SetTextColor(brandR, brandG, brandB, 1)
                    end
                end
            end)
        end
    end

    -- Theme a checkbox's checkmark to ScooterMod green
    -- The checkmark is a texture accessed via checkbox:GetCheckedTexture()
    -- SetVertexColor persists through state changes (no hook needed, same as dropdown icons)
    function panel.ThemeCheckbox(checkbox)
        if not checkbox then return end

        -- Prevent double-processing
        if checkbox._scooterCheckboxThemed then return end
        checkbox._scooterCheckboxThemed = true

        -- Apply green tint to the checked texture (the checkmark)
        local checkedTex = checkbox.GetCheckedTexture and checkbox:GetCheckedTexture()
        if checkedTex and checkedTex.SetVertexColor then
            checkedTex:SetVertexColor(brandR, brandG, brandB, 1)
        end

        -- Also tint the disabled checked texture so it remains green when disabled
        local disabledCheckedTex = checkbox.GetDisabledCheckedTexture and checkbox:GetDisabledCheckedTexture()
        if disabledCheckedTex and disabledCheckedTex.SetVertexColor then
            disabledCheckedTex:SetVertexColor(brandR, brandG, brandB, 1)
        end
    end

    -- Global hook on SettingsCheckboxControlMixin.Init to auto-theme all checkboxes in ScooterMod panel
    -- This ensures every checkbox is themed green without needing to add calls at each creation site
    if not panel._checkboxControlInitHooked then
        panel._checkboxControlInitHooked = true
        if type(SettingsCheckboxControlMixin) == "table" and type(SettingsCheckboxControlMixin.Init) == "function" then
            hooksecurefunc(SettingsCheckboxControlMixin, "Init", function(self)
                -- Only theme checkboxes inside ScooterMod's panel
                if not belongsToScooterPanel(self) then return end
                -- Find and theme the checkbox
                local cb = self.Checkbox or self.CheckBox or self.Control
                if cb and cb.IsObjectType and cb:IsObjectType("CheckButton") then
                    panel.ThemeCheckbox(cb)
                end
            end)
        end
    end
end


