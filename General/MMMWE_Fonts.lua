--[[
	MMMWE_Fonts.lua — fonts shipped with Waffel Edition (03.11.26)

	The .ttf files in Data\Fonts are loaded for this game only (AddFontResourceExA with
	FR_PRIVATE): nothing is installed in Windows, and the fonts are gone when the game closes.
	General scripts load before Global ones, so the overlays (MMMWE_HPSPDisplay.lua,
	MMMWE_CombatLog.lua) find them when they create their fonts.

	MF.FontFace(name, fallback): name if that font was loaded from Data\Fonts, else fallback.

	The game's own bitmap fonts (*.fnt of EnglishT.lod) have no Cyrillic letters. With a
	language chosen in MMMWE_Language.txt (Structs/26_MMMWE_Texts.lua), the fonts found in
	Data\Text localization\<Language>\Fonts replace them as the game loads them (LoadFont,
	0x449BA1) - made from Sovngarde by Tools/make_fonts.py for Russian. A new font goes into
	the buffer of the old one when it fits, else into memory of the game's malloc.
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

-- the character set the overlays create their fonts with: the language's code page
-- (DEFAULT_CHARSET follows the Windows locale instead)
local CHARSETS = {Russian = 204, Ukrainian = 204, Belarusian = 204, Bulgarian = 204, Serbian = 204,
	Polish = 238, Czech = 238, Hungarian = 238, Greek = 161, Turkish = 162}
function MF.FontCharset()
	return CHARSETS[MF.TextLanguage or ""] or 1
end

function MF.FontFace(name, fallback)
	if Loaded[name] then return name end
	return fallback or name
end

-- the language's own bitmap fonts
local lang = MF.TextLanguage
if lang and lang ~= "English" then
	local dir = (AppPath or "") .. "Data\\Text localization\\" .. lang .. "\\Fonts\\"
	local u1, u4, i4 = mem.u1, mem.u4, mem.i4
	local Replaced = {}

	-- the bytes a loaded font takes: header, 256 ABC widths, 256 offsets, the glyphs
	local function fontSize(p)
		local h, size = u1[p + 5], 0
		for c = 0, 255 do
			local w = i4[p + 0x20 + c * 12 + 4]
			if w > 0 then
				size = math.max(size, u4[p + 0x20 + 3072 + c * 4] + w * h)
			end
		end
		return 0x20 + 3072 + 1024 + size
	end

	local function readFont(name)
		local f = io.open(dir .. name, "rb")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		if #s < 0x20 + 4096 or s:byte(6) == 0 then
			MF.LogWarning("Fonts: %s%s is not a font", dir, name)
			return nil
		end
		return s
	end

	-- the font file just read by LoadFont (eax), before its palettes are set
	mem.autohook(0x449BB7, function(d)
		local p = d.eax
		if p == 0 then return end
		local name = mem.string(u4[d.ebp + 8])
		local s = readFont(name)
		if not s then return end
		local np = #s <= fontSize(p) and p or mem.malloc(#s)
		mem.copy(np, s, #s)
		d.eax = np
		Replaced[np] = true
		MF.LogInfo("Fonts: %s from %s", name, dir)
	end)

	-- fonts the game loaded before this script: swapped in place, their palettes kept
	local LOADED = {[0x5DB918] = "arrus.fnt", [0x5DB91C] = "lucida.fnt", [0x5DB938] = "smallnum.fnt",
		[0x5DB92C] = "create.fnt", [0x5DB934] = "comic.fnt", [0x5DB924] = "book.fnt",
		[0x5DB920] = "book2.fnt", [0x5DB910] = "autonote.fnt", [0x5DB914] = "spell.fnt"}
	function events.GameInitialized1()
		for at, name in pairs(LOADED) do
			local p = u4[at]
			if p ~= 0 and not Replaced[p] then
				local s = readFont(name)
				if s then
					local np = #s <= fontSize(p) and p or mem.malloc(#s)
					local pal = mem.string(p + 8, 0x18, true)
					mem.copy(np, s, #s)
					mem.copy(np + 8, pal, 0x18)
					u4[at] = np
					Replaced[np] = true
					MF.LogInfo("Fonts: %s from %s (after loading)", name, dir)
				end
			end
		end
	end
end
