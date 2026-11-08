--[[
	MMMWE_OverlaySettings.lua — "Overlay fonts" page of the Extra Settings menu (07.11.26)

	The font sizes of the overlays drawn over the game window:
	  HP/SP display  the HP/SP text, and the small text of conditions and buffs
	                 (Global\MMMWE_HPSPDisplay.lua)
	  Combat log     its lines; the line spacing and width follow (Global\MMMWE_CombatLog.lua)
	Sizes are at the 1920x1200 base and scale with the window, as the overlays do.
	They are a setting of the installation, not of a save game: kept in MMMWE_Overlays.txt in
	the game folder.
--]]

local MF = Merge.Functions
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey

local FILE = AppPath .. "MMMWE_Overlays.txt"

local O = {
	HPSPFont  = nil,   -- nil: the overlay's own default
	HPSPSmall = nil,
	CombatLog = nil,
}
local RANGE = {
	HPSPFont  = {14, 40},
	HPSPSmall = {12, 34},
	CombatLog = {10, 32},
}

local function load()
	local f = io.open(FILE, "r")
	if not f then return end
	for line in f:lines() do
		local k, v = line:match("^%s*(%w+)%s*=%s*(%d+)")
		if k and RANGE[k] then O[k] = tonumber(v) end
	end
	f:close()
end

local function save()
	local f = io.open(FILE, "w")
	if not f then return end
	f:write(Tx"-- Waffel Edition overlay font sizes (the Extra Settings menu writes this file)\n")
	for _, k in ipairs{"HPSPFont", "HPSPSmall", "CombatLog"} do
		if O[k] then f:write(string.format("%s = %d\n", k, O[k])) end
	end
	f:close()
end

local function default(k)
	if k == "HPSPFont" then return MF.HPSPDisplayDefaults and MF.HPSPDisplayDefaults.Font or 24 end
	if k == "HPSPSmall" then return MF.HPSPDisplayDefaults and MF.HPSPDisplayDefaults.Small or 22 end
	return MF.CombatLogDefaults and MF.CombatLogDefaults.Font or 16
end
local function value(k) return O[k] or default(k) end

-- the overlays call this when they load (they are reloaded with the game), and the menu
-- after a change
function MF.ApplyOverlayFonts()
	if MF.SetHPSPFontSize and (O.HPSPFont or O.HPSPSmall) then
		MF.SetHPSPFontSize(O.HPSPFont, O.HPSPSmall)
	end
	if MF.SetCombatLogFontSize and O.CombatLog then
		MF.SetCombatLogFontSize(O.CombatLog)
	end
end
MF.OverlaySettings = O

load()

---------------------------------------------------------------------------
-- the menu page (as MMMWE_EnchantScaling.lua's)
---------------------------------------------------------------------------

local function MenuText(Screen, Text, X, Y, Action)
	return CustomUI.CreateText{
		Text = Text,
		Font = Game.Smallnum_fnt,
		X = X, Y = Y,
		ColorStd = 0xFFFF,
		ColorMouseOver = Action and 0xe664 or 0xFFFF,
		Layer = 1,
		Screen = Screen,
		AlignLeft = true,
		Action = Action,
	}
end

local function Yellow(text)
	return StrColor(255, 255, 150) .. text .. StrColor(255, 255, 255)
end

local COL_LABEL, COL_LEFT, COL_VALUE, COL_RIGHT = 80, 260, 280, 330

local function Selector(Screen, Y, Header, key)
	local o = {}
	o.Header = MenuText(Screen, Yellow(Header), COL_LABEL, Y)
	local function refresh()
		o.Value.Text = tostring(value(key)) .. (O[key] and "" or " (default)")
		o.Value:UpdateSize()
	end
	local function step(side)
		local r = RANGE[key]
		O[key] = math.max(r[1], math.min(r[2], value(key) + side))
		save()
		MF.ApplyOverlayFonts()
		refresh()
	end
	o.Left = MenuText(Screen, "<", COL_LEFT, Y, function() Game.PlaySound(24) step(-1) end)
	o.Value = MenuText(Screen, "", COL_VALUE, Y)
	o.Right = MenuText(Screen, ">", COL_RIGHT + 60, Y, function() Game.PlaySound(23) step(1) end)
	o.Update = refresh
	return o
end

function events.GameInitialized2()
	if not (CustomUI and CustomUI.NewSettingsPage) then
		return
	end
	local Screen = CustomUI.NewSettingsPage("MMMWEOverlayFonts", "Overlay fonts", "ExSetScr2")
	local items = {
		Selector(Screen, 190, Tx"HP/SP display text", "HPSPFont"),
		Selector(Screen, 220, Tx"HP/SP small text", "HPSPSmall"),
		Selector(Screen, 250, Tx"Combat log text", "CombatLog"),
	}
	MenuText(Screen, Tx"Font sizes at 1920x1200; they scale with the window.", COL_LABEL, 290)
	MenuText(Screen, Tx"Reset to the defaults", COL_LABEL, 320, function()
		Game.PlaySound(23)
		O.HPSPFont, O.HPSPSmall, O.CombatLog = nil, nil, nil
		save()
		if MF.SetHPSPFontSize then MF.SetHPSPFontSize(default("HPSPFont"), default("HPSPSmall")) end
		if MF.SetCombatLogFontSize then MF.SetCombatLogFontSize(default("CombatLog")) end
		for _, o in ipairs(items) do o.Update() end
	end)

	function events.OpenExtraSettingsMenu()
		for _, o in ipairs(items) do
			o.Update()
		end
	end
end
