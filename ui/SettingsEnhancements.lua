local addonName, addon = ...

-- Attach a small live swatch at the right side of a dropdown row for bar textures.
function addon.InitBarTextureDropdown(controlFrame, setting)
	-- No extra swatch; rely on the selected option string (with |T preview) to render inside the dropdown control.
	if not controlFrame or not setting then return end
	local dropdown = controlFrame.Dropdown
	if not dropdown then return end
end


