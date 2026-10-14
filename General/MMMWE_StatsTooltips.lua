--[[
	MMMWE_StatsTooltips.lua — right-click tooltips of the Stats page, matched to its layout

	The game's stats_screen_rmb (0x41771F) looks up the mouse in a table of 27 rectangles
	(x, y, w, h as shorts, at the operand of "mov ecx, offset stats_screen_hints" 0x417754
	minus 2) and shows a title (GLOBAL.TXT) with a description from stats.txt:
	  0..6 stats, 7 HP, 8 SP, 9 AC, 10 condition, 11 quick spell, 12 age, 13 level,
	  14 experience, 15 attack bonus, 16 attack damage, 17 shoot bonus, 18 shoot damage,
	  19..24 fire, air, water, earth, mind, body, 25 skill points, 26 name (race).

	The Waffel Edition Stats page has a different layout, so:
	  - the entries the game still handles well get the rectangles of their new places
	    (GAME_RECTS below). The game's own code then adds what it always added: the
	    experience needed for the next level, and the patch's recovery time lines on
	    Attack Damage and Shoot Damage;
	  - entries with no line on the page any more (condition, quick spell) and the
	    resistances (merged descriptions now) are moved off screen;
	  - the lines the game knows nothing about (Eva/Par/Blk, Sla/Pie/Blu, Light/Dark,
	    crits, Spirit, and the resistances) are handled here (CUSTOM below): the tooltip is
	    drawn with the game's own routine (sub_417035: ecx = title, edx = text).

	stats.txt (26 rows, header excluded) is loaded into 0x5E4990 (rows 0..6) and
	0x5E4D50 (rows 7..25, one slot each) - except that row 8 goes to the Armor Class slot
	and row 9 to the Spell Points slot, so the file keeps Armor Class before Spell Points.
	Rows 10, 11 and 19..24 hold the Waffel descriptions used by CUSTOM.

	Coordinates are 640x480. Console: Merge.Functions.StatsTooltipAt(x, y)
--]]

local MF = Merge.Functions

local L, LW = 13, 236      -- left column
local R, RW = 261, 192     -- right column

-- the game's entries -> {x, y, w, h} of their line on the Waffel page
local GAME_RECTS = {
	[0]  = {L,  69, LW, 17},   -- Might
	[1]  = {L,  86, LW, 17},   -- Intellect
	[2]  = {L, 103, LW, 17},   -- Personality
	[3]  = {L, 120, LW, 17},   -- Endurance
	[4]  = {L, 137, LW, 17},   -- Accuracy
	[5]  = {L, 154, LW, 17},   -- Speed
	[6]  = {L, 171, LW, 17},   -- Luck
	[7]  = {L, 200, LW, 15},   -- Hit Points
	[8]  = {L, 215, LW, 15},   -- Spell Points
	[9]  = {L, 230, LW, 28},   -- Armor Class (+ HR Class / Phys line)
	[12] = {R,  66, RW, 17},   -- Age
	[13] = {R,  83, RW, 17},   -- Level
	[14] = {R, 100, RW, 17},   -- Experience
	[15] = {R, 135, RW, 13},   -- Attack bonus
	[16] = {R, 161, RW, 14},   -- Attack damage
	[17] = {R, 175, RW, 13},   -- Shoot bonus
	[18] = {R, 202, RW, 14},   -- Shoot damage
	[25] = {300, 34, 153, 18}, -- Skill points
	-- 26 (name / race) keeps the game's own rectangle
}
local KEEP_AS_IS = {[26] = true}

-- stats.txt rows used here
local ROW = {Defense = 10, Kinds = 11, Crit = 19, FireAir = 20, WaterBody = 21, Earth = 22,
	MindSpirit = 23, LightDark = 24}

-- {x, y, w, h, title, row}
local CUSTOM = {
	{L, 268, LW, 29, "Light and Dark Resistances", ROW.LightDark},
	{L, 297, LW, 14, "Evasion, Parry and Block",   ROW.Defense},
	{L, 311, LW, 16, "Physical Damage Kinds",      ROW.Kinds},
	{R, 148, RW, 13, "Critical Strikes",  ROW.Crit},
	{R, 188, RW, 14, "Critical Strikes",  ROW.Crit},
	{R, 229, RW, 13, "Fire Resistance",   ROW.FireAir},
	{R, 242, RW, 14, "Air Resistance",    ROW.FireAir},
	{R, 256, RW, 13, "Water Resistance",  ROW.WaterBody},
	{R, 269, RW, 13, "Earth Resistance",  ROW.Earth},
	{R, 282, RW, 13, "Mind Resistance",   ROW.MindSpirit},
	{R, 295, RW, 14, "Body Resistance",   ROW.WaterBody},
	{R, 309, RW, 14, "Spirit Resistance", ROW.MindSpirit},
}

---------------------------------------------------------------------------

local function textOfRow(row)
	if row <= 6 then return mem.u4[0x5E4990 + row * 4] end
	local slot = row - 7
	if row == 8 then slot = 2 elseif row == 9 then slot = 1 end   -- AC / SP
	return mem.u4[0x5E4D50 + slot * 4]
end

local TitlePtr = {}
local function titlePtr(title)
	local p = TitlePtr[title]
	if not p then
		p = mem.StaticAlloc(#title + 1)
		mem.copy(p, title .. "\0", #title + 1)
		TitlePtr[title] = p
	end
	return p
end
for _, r in ipairs(CUSTOM) do titlePtr(r[5]) end

local function inRect(x, y, r)
	return x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

local function customAt(x, y)
	for _, r in ipairs(CUSTOM) do
		if inRect(x, y, r) then return r end
	end
end

function MF.StatsTooltipAt(x, y)
	local r = customAt(x, y)
	if r then return r[5], "stats.txt row " .. r[6] end
	for i, g in pairs(GAME_RECTS) do
		if inRect(x, y, g) then return "game entry " .. i end
	end
end

-- the game's rectangle table
do
	local base = mem.u4[0x417755] - 2
	mem.IgnoreProtection(true)   -- the table may be in a read-only section
	for i = 0, 26 do
		if not KEEP_AS_IS[i] then
			local e = base + i * 8
			local g = GAME_RECTS[i] or {-2000, -2000, 0, 0}
			mem.i2[e], mem.i2[e + 2], mem.i2[e + 4], mem.i2[e + 6] = g[1], g[2], g[3], g[4]
		end
	end
	mem.IgnoreProtection(false)
end

mem.hookfunction(0x41771F, 1, 0, function(d, def, this)
	local r = customAt(Mouse.X, Mouse.Y)
	if r then
		local text = textOfRow(r[6])
		if text ~= 0 then
			mem.call(0x417035, 2, titlePtr(r[5]), text)
			return
		end
	end
	return def(this)
end)
