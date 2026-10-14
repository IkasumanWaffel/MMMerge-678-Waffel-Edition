--[[
	MMMWE_StatsTooltips.lua — right-click tooltips of the Stats page, matched to its layout

	The game's stats_screen_rmb (0x41771F) looks up the mouse in a table of 27 rectangles
	(x, y, w, h as shorts, at the operand of "mov ecx, offset stats_screen_hints" 0x417754
	minus 2) and shows a title (GLOBAL.TXT) with a description from stats.txt. The Waffel
	Edition Stats page has a different layout (regeneration, HR Class / Phys, Light / Dark,
	Eva / Par / Blk, Sla / Pie / Blu, crits, Spirit), so:
	  - the function is hooked: the rectangles below are checked first and the tooltip is
	    drawn with the game's own routine (sub_417035: ecx = title, edx = text);
	  - the game's rectangles 0..25 are moved off screen, so a click outside the regions
	    below never shows a stale tooltip; rectangle 26 (the name: race description) is kept
	    and still handled by the game.

	Descriptions come from stats.txt by row (header excluded): rows 0..6 are kept by the
	game at 0x5E4990, rows 7..25 at 0x5E4D50. stats.txt must have exactly these 26 rows in
	this order (see ROW below); the titles are set here.

	Coordinates are 640x480. Console: Merge.Functions.StatsTooltipAt(x, y) -> title, row
--]]

local MF = Merge.Functions

-- stats.txt rows (0-based, header excluded)
local ROW = {
	Might = 0, Intellect = 1, Personality = 2, Endurance = 3, Accuracy = 4, Speed = 5, Luck = 6,
	HP = 7, SP = 8, AC = 9, Defense = 10, Kinds = 11, Age = 12, Level = 13, Exp = 14,
	AttackBonus = 15, AttackDamage = 16, ShootBonus = 17, ShootDamage = 18, Crit = 19,
	FireAir = 20, WaterBody = 21, Earth = 22, MindSpirit = 23, LightDark = 24, SkillPoints = 25,
}

-- {x, y, w, h, title, row}
local L, LW = 13, 236      -- left column
local R, RW = 261, 192     -- right column
local REGIONS = {
	-- seven stats
	{L,  69, LW, 17, "Might",        ROW.Might},
	{L,  86, LW, 17, "Intellect",    ROW.Intellect},
	{L, 103, LW, 17, "Personality",  ROW.Personality},
	{L, 120, LW, 17, "Endurance",    ROW.Endurance},
	{L, 137, LW, 17, "Accuracy",     ROW.Accuracy},
	{L, 154, LW, 17, "Speed",        ROW.Speed},
	{L, 171, LW, 17, "Luck",         ROW.Luck},
	-- HP / SP / Armor Class (+ HR Class and Phys line)
	{L, 200, LW, 15, "Hit Points",   ROW.HP},
	{L, 215, LW, 15, "Spell Points", ROW.SP},
	{L, 230, LW, 28, "Armor Class",  ROW.AC},
	-- Light / Dark, Eva / Par / Blk, Sla / Pie / Blu
	{L, 268, LW, 29, "Light and Dark Resistances", ROW.LightDark},
	{L, 297, LW, 14, "Evasion, Parry and Block",   ROW.Defense},
	{L, 311, LW, 16, "Physical Damage Kinds",      ROW.Kinds},
	-- name line: skill points on the right (the name itself is left to the game)
	{300, 34, 153, 18, "Skill Points", ROW.SkillPoints},
	-- Age / Level / Experience
	{R,  66, RW, 17, "Age",        ROW.Age},
	{R,  83, RW, 17, "Level",      ROW.Level},
	{R, 100, RW, 17, "Experience", ROW.Exp},
	-- attack box
	{R, 135, RW, 13, "Attack Bonus",     ROW.AttackBonus},
	{R, 148, RW, 13, "Critical Strikes", ROW.Crit},
	{R, 161, RW, 14, "Attack Damage",    ROW.AttackDamage},
	{R, 175, RW, 13, "Shoot Bonus",      ROW.ShootBonus},
	{R, 188, RW, 14, "Critical Strikes", ROW.Crit},
	{R, 202, RW, 14, "Shoot Damage",     ROW.ShootDamage},
	-- resistances
	{R, 229, RW, 13, "Fire Resistance",   ROW.FireAir},
	{R, 242, RW, 14, "Air Resistance",    ROW.FireAir},
	{R, 256, RW, 13, "Water Resistance",  ROW.WaterBody},
	{R, 269, RW, 13, "Earth Resistance",  ROW.Earth},
	{R, 282, RW, 13, "Mind Resistance",   ROW.MindSpirit},
	{R, 295, RW, 14, "Body Resistance",   ROW.WaterBody},
	{R, 309, RW, 14, "Spirit Resistance", ROW.MindSpirit},
}

local KEEP_GAME_ENTRY = 26   -- the name / race tooltip

---------------------------------------------------------------------------

local function textOfRow(row)
	if row <= 6 then return mem.u4[0x5E4990 + row * 4] end
	return mem.u4[0x5E4D50 + (row - 7) * 4]
end

-- titles as C strings
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
for _, r in ipairs(REGIONS) do titlePtr(r[5]) end

local function regionAt(x, y)
	for _, r in ipairs(REGIONS) do
		if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then
			return r
		end
	end
end

function MF.StatsTooltipAt(x, y)
	local r = regionAt(x, y)
	if r then return r[5], r[6] end
end

-- move the game's rectangles 0..25 off screen
do
	local base = mem.u4[0x417755] - 2
	mem.IgnoreProtection(true)   -- the table may be in a read-only section
	for i = 0, 26 do
		if i ~= KEEP_GAME_ENTRY then
			local e = base + i * 8
			mem.i2[e], mem.i2[e + 2], mem.i2[e + 4], mem.i2[e + 6] = -2000, -2000, 0, 0
		end
	end
	mem.IgnoreProtection(false)
end

mem.hookfunction(0x41771F, 1, 0, function(d, def, this)
	local r = regionAt(Mouse.X, Mouse.Y)
	if r then
		local text = textOfRow(r[6])
		if text ~= 0 then
			mem.call(0x417035, 2, titlePtr(r[5]), text)
			return
		end
	end
	return def(this)
end)
