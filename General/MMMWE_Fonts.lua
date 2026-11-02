--[[
	MMMWE_Fonts.lua — fonts shipped with Waffel Edition (03.11.26)

	The .ttf files in Data\Fonts are loaded for this game only (AddFontResourceExA with
	FR_PRIVATE): nothing is installed in Windows, and the fonts are gone when the game closes.
	General scripts load before Global ones, so the overlays (MMMWE_HPSPDisplay.lua,
	MMMWE_CombatLog.lua) find them when they create their fonts.

	MF.FontFace(name, fallback): name if that font was loaded from Data\Fonts, else fallback.
--]]

local MF = Merge.Functions

-- family name (as the font file calls itself) = file in Data\Fonts
local FONTS = {
	Sovngarde = "SovngardeLight.ttf",
}

local FR_PRIVATE = 0x10
local Loaded = {}
MF.LoadedFonts = Loaded

for family, file in pairs(FONTS) do
	local path = (AppPath or "") .. "Data\\Fonts\\" .. file
	local f = io.open(path, "rb")
	if f then
		f:close()
		local ok, n = pcall(mem.dll.gdi32.AddFontResourceExA, path, FR_PRIVATE, 0)
		if ok and n and n > 0 then
			Loaded[family] = true
			MF.LogInfo("Fonts: %s loaded from %s", family, path)
		else
			MF.LogWarning("Fonts: %s could not be loaded from %s", family, path)
		end
	else
		MF.LogWarning("Fonts: %s is missing", path)
	end
end

function MF.FontFace(name, fallback)
	if Loaded[name] then return name end
	return fallback or name
end
