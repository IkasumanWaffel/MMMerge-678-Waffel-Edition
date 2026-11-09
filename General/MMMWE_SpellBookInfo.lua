--[[
	MMMWE_SpellBookInfo.lua — who can learn the spell of a spellbook (09.11.26)

	The description of a spellbook (in the inventory, in a guild's shop, anywhere the game
	shows an item's description) gets a line for every party member:
	  green  can learn it now
	  grey   knows it already
	  red    can't: the requirement it misses (the skill and mastery of the spell's school,
	         or the level), or "not for <class>" when the class can't learn that spell at all
	The check is the game's own (the CanPlayerLearnSpell event: SpellsLearning.txt, custom
	classes' picked spells). MMMWE_Main.lua's item description hook calls MF.SpellBookNotes.
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local floor = math.floor

local GREEN, GREY, RED = {120, 230, 120}, {170, 170, 170}, {240, 100, 90}
local MASTERY = {Tx"Novice", Tx"Expert", Tx"Master", Tx"Grand Master"}

local OrigNotes = {}       -- [item] = the description without the line

local function color(c, s)
	return StrColor(c[1], c[2], c[3], s)
end

local function status(pl, i, spell, book)
	if pl.Spells[spell] then return color(GREY, string.format(Tx"%s: knows it", pl.Name)) end
	local t = {ReqLevel = (spell - 1) % 11 + 1, Level = 0, Player = pl, PlayerIndex = i,
		BookIndex = book, SpellId = spell}
	events.call("CanPlayerLearnSpell", t)
	if t.Level >= 0x40 or t.Level >= t.ReqLevel then
		return color(GREEN, string.format(Tx"%s: can learn", pl.Name))
	end
	local req = t.Reqs and t.Reqs[1]
	if not req then
		return color(RED, string.format(Tx"%s: not for a %s", pl.Name, Game.ClassNames[pl.Class]))
	end
	local school = floor((spell - 1) / 11) + 12
	local need = string.format(Tx"%s %s %d", Game.SkillNames[school],
		MASTERY[req.SkillMastery] or "", req.SkillLevel or 1)
	if req.PlayerLevel and req.PlayerLevel > 1 then
		need = need .. string.format(Tx", level %d", req.PlayerLevel)
	end
	return color(RED, string.format(Tx"%s: needs %s", pl.Name, need))
end

-- sets the description of a spellbook item to its text and the learning line
function MF.SpellBookNotes(num)
	local it = Game.ItemsTxt[num]
	if not it or it.EquipStat ~= 16 then return end
	local spell = it.Mod1DiceSides
	if not spell or spell < 1 or spell > 132 then return end
	if not OrigNotes[num] then OrigNotes[num] = it.Notes end
	local ok, line = pcall(function()
		local parts = {}
		for i = 0, Party.count - 1 do
			parts[#parts + 1] = status(Party[i], i, spell, num)
		end
		return table.concat(parts, "\n")
	end)
	local text = OrigNotes[num]
	if ok and line ~= "" then text = text .. "\n\n" .. line end
	if it.Notes ~= text then it.Notes = text end
end
