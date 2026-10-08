--[[
	MMMWE_PercentHPSP.lua — HP / SP enchantments give a percentage instead of a flat bonus

	Converted enchantments (found by their "Name Add" from STDITEMS.TXT / SPCITEMS.TXT):
	  standard  "of Health"      +N Hit Points    ->  +N*StdPercentPerPoint % Hit Points
	  standard  "of Magic"       +N Spell Points  ->  +N*StdPercentPerPoint % Spell Points
	  special   "of Doom"        +1 HP, +1 SP     ->  +1% HP, +1% SP   (stats, AC, res unchanged)
	  special   "of Earth"       +10 HP           ->  +10% HP          (End, AC unchanged)
	  special   "of Life"        +10 HP           ->  +10% HP          (HP regen unchanged)
	  special   "of The Eclipse" +10 SP           ->  +10% SP          (SP regen unchanged)
	  special   "of The Sky"     +10 SP           ->  +10% SP          (Int, Speed unchanged)

	How it works:
	  1. events.CalcStatBonusByItems removes the flat HP / SP these enchantments give.
	  2. GetFullHP (0x48D9B4) / GetFullSP (0x48DA18) are hooked: the game computes the full
	     value as usual (now without those flat bonuses) and the summed percentage of all
	     equipped items is added on top of it.
	  3. The enchantment texts shown on items are rewritten in memory (no .lod changes).

	Everything is tunable in PercentHPSP below. Artifacts' own HP / SP bonuses aren't touched.
--]]

PercentHPSP = PercentHPSP or {}
local P = PercentHPSP

P.Enabled = (P.Enabled == nil) and true or P.Enabled

-- "of Health" / "of Magic": percent per point of the enchantment's strength
-- (strength rolls 1-25 depending on treasure level, see STDITEMS.TXT)
P.StdPercentPerPoint = P.StdPercentPerPoint or 1

-- Special enchantments by Name Add:
--   HP / SP         = percent given
--   FlatHP / FlatSP = flat bonus the game gives (removed); must match the game's values
P.Special = P.Special or {
	["of Doom"]        = {HP = 1,  SP = 1,  FlatHP = 1,  FlatSP = 1,
	                      Text = " +1 to Seven Stats, Resistances, Armor; +1% HP and SP."},
	["of Earth"]       = {HP = 10, FlatHP = 10,
	                      Text = " +10 to Endurance and Armor Class, +10% Hit points."},
	["of Life"]        = {HP = 10, FlatHP = 10,
	                      Text = " +10% Hit points and Regenerate Hit points over time."},
	["of The Eclipse"] = {SP = 10, FlatSP = 10,
	                      Text = " +10% Spell points and Regenerate Spell points over time."},
	["of The Sky"]     = {SP = 10, FlatSP = 10,
	                      Text = " +10 Speed and Intellect, +10% Spell points."},
}

-- Optional cap on the total percentage from all items (nil = no cap)
P.MaxPercentHP = P.MaxPercentHP
P.MaxPercentSP = P.MaxPercentSP

-- Names of the standard bonuses shown on items
P.StdLabels = P.StdLabels or {
	["of Health"] = "Hit Points (%)",
	["of Magic"]  = "Spell Points (%)",
}

---------------------------------------------------------------------------

local MF = Merge.Functions
local floor, min = math.floor, math.min

local STAT_HP = const.Stats.HitPoints or const.Stats.HP or 7
local STAT_SP = const.Stats.SpellPoints or const.Stats.SP or 8

local GET_FULL_HP = 0x48D9B4
local GET_FULL_SP = 0x48DA18

-- item.Bonus / item.Bonus2 numbers (1-based) of the converted enchantments
local StdHP, StdSP
local SpcByBonus2 = {}

local function findEnchantments()
	StdHP, StdSP = nil, nil
	for i, v in Game.StdItemsTxt do
		if v.NameAdd == "of Health" then StdHP = i + 1 end
		if v.NameAdd == "of Magic"  then StdSP = i + 1 end
	end
	SpcByBonus2 = {}
	for i, v in Game.SpcItemsTxt do
		local conf = P.Special[v.NameAdd]
		if conf then
			SpcByBonus2[i + 1] = conf
		end
	end
end

-- Enchantment texts shown on items
local function updateTexts()
	for i, v in Game.StdItemsTxt do
		local label = P.StdLabels[v.NameAdd]
		if label and v.BonusStat ~= label then
			v.BonusStat = label
		end
	end
	for i, v in Game.SpcItemsTxt do
		local conf = P.Special[v.NameAdd]
		if conf and conf.Text and v.BonusStat ~= conf.Text then
			v.BonusStat = conf.Text
		end
	end
end

-- Percent and removed flat amounts of all equipped items
local function sumItems(pl)
	local pctHP, pctSP, flatHP, flatSP = 0, 0, 0, 0
	for item in pl:EnumActiveItems() do
		if StdHP and item.Bonus == StdHP then
			pctHP = pctHP + item.BonusStrength * P.StdPercentPerPoint
			flatHP = flatHP + item.BonusStrength
		elseif StdSP and item.Bonus == StdSP then
			pctSP = pctSP + item.BonusStrength * P.StdPercentPerPoint
			flatSP = flatSP + item.BonusStrength
		end
		local conf = SpcByBonus2[item.Bonus2]
		if conf then
			pctHP = pctHP + (conf.HP or 0)
			pctSP = pctSP + (conf.SP or 0)
			flatHP = flatHP + (conf.FlatHP or 0)
			flatSP = flatSP + (conf.FlatSP or 0)
		end
	end
	if P.MaxPercentHP then pctHP = min(pctHP, P.MaxPercentHP) end
	if P.MaxPercentSP then pctSP = min(pctSP, P.MaxPercentSP) end
	return pctHP, pctSP, flatHP, flatSP
end
P.SumItems = sumItems

-- 1. remove the flat bonuses
function events.CalcStatBonusByItems(t)
	if not P.Enabled or (t.Stat ~= STAT_HP and t.Stat ~= STAT_SP) or not t.Player then
		return
	end
	local _, _, flatHP, flatSP = sumItems(t.Player)
	if t.Stat == STAT_HP then
		t.Result = t.Result - flatHP
	else
		t.Result = t.Result - flatSP
	end
end

-- 2. add the percentage to full HP / SP
local function percentHook(isHP)
	return function(d, def, this)
		local full = def(this)
		if not P.Enabled then
			return full
		end
		local pl = MF.GetPlayerFromPtr(this)
		if not pl or full <= 0 then
			return full
		end
		local pctHP, pctSP = sumItems(pl)
		local pct = isHP and pctHP or pctSP
		if pct ~= 0 then
			full = full + floor(full * pct / 100)
		end
		return full
	end
end
mem.hookfunction(GET_FULL_HP, 1, 0, percentHook(true))
mem.hookfunction(GET_FULL_SP, 1, 0, percentHook(false))

-- 3. find the enchantments and update their texts once the tables are loaded
function events.GameInitialized2()
	findEnchantments()
	updateTexts()
end

-- tables can be reloaded (e.g. on continent change): keep the texts in sync
function events.AfterLoadMap()
	findEnchantments()
	updateTexts()
end

-- Re-read the settings after changing PercentHPSP from another script / the console
P.Refresh = function()
	findEnchantments()
	updateTexts()
end
