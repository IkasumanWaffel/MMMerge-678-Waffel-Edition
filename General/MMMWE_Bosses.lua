--[[
	MMMWE_Bosses.lua (22.11.26): the named monsters (Placemon.txt) are bosses.

	A monster placed with a name (its NameId, a line of Placemon.txt) - the story figures
	(Yaardrake, Ilsingore, Snergle, Agar, Xenofex, the Lich King, the Queen Spider...) and the
	New World Computing staff cameos - gets on top of the bolster:
	  Hit Points x HPMul, damage x DamageMul, Armor Class x ACMul, Level + LevelAdd,
	  Experience x ExpMul;
	  abilities (MMMWE_MonsterAbilities.lua): Juggernaut and Abilities more, whatever the
	  party's level or the bolster setting;
	  a sure treasure item one class better (TreasureUp, up to 6) and Gold x GoldMul;
	  its name in gold (the hover text, the monster card, the status line).
	Not bosses: the filler names (guards, lookouts, a pet, placeholders).
	Kept as they are (name and loot only): Mega-Dragon (deadly as it is; its Hermes' Sandals
	stay), Wromthrax (the first Paladin promotion's quest; already a hard fight) and Q (has its
	own stats, Bolster-SpcMonsters.txt).
	A carried item (Monster.Item: the Sandals, the named drops) is never touched.

	The bolster sets a monster's stats again on every map load; the boost is put back on
	after it (the boosted Hit Points are kept to tell a boosted monster from a reset one).
	MF.IsBoss(monster) -> true for a boss.
--]]

local MF = Merge.Functions
local floor, max, min = math.floor, math.max, math.min

local B = {
	HPMul     = 3,
	DamageMul = 1.5,
	ACMul     = 1.25,
	LevelAdd  = 5,
	ExpMul    = 3,
	Abilities = 2,      -- besides Juggernaut
	TreasureUp = 1,
	GoldMul   = 3,
	Color     = {255, 200, 60},
}
MF.BossSettings = B

-- Placemon.txt lines that are not bosses
local NOT_BOSS = {
	[3] = true,                       -- Dragon Hunter Pet
	[8] = true, [9] = true,           -- Lizardman Lookout
	[10] = true, [110] = true,        -- Guard, guard
	[163] = true, [164] = true,       -- Placeholder
}
-- bosses by name and loot only
local KEEP_STATS = {
	[117] = true,                     -- Wromthrax
	[118] = true,                     -- Mega-Dragon
	[123] = true, [133] = true,       -- Q
}

local function isBoss(m)
	local n = m.NameId or 0
	return n > 0 and not NOT_BOSS[n] and Game.PlaceMonTxt[n] ~= nil and Game.PlaceMonTxt[n] ~= ""
end
MF.IsBoss = isBoss

local function store()
	mapvars.MMMWE_Bosses = mapvars.MMMWE_Bosses or {}
	return mapvars.MMMWE_Bosses
end

local function alive(m)
	return m.AIState ~= const.AIState.Removed and m.AIState ~= const.AIState.Dead
		and m.AIState ~= const.AIState.Dying and m.HP > 0
end

local function mulAttack(a, mul)
	a.DamageDiceCount = min(255, max(1, floor(a.DamageDiceCount * mul + 0.5)))
	a.DamageAdd = min(255, floor(a.DamageAdd * mul + 0.5))
end

local function boost(i, m)
	local rec = store()[i]
	local same = rec and rec.Id == m.Id and rec.NameId == m.NameId
	-- already boosted, and the bolster hasn't reset it since
	if same and rec.FullHP == m.FullHP then return end
	-- the gold dice aren't set again by the bolster: kept from the first time
	local dice = same and rec.Dice or {m.TreasureDiceCount, m.TreasureDiceSides}
	rec = {Id = m.Id, NameId = m.NameId, Dice = dice}
	if not KEEP_STATS[m.NameId] then
		local full = min(32000, floor(m.FullHP * B.HPMul))
		if m.HP > 0 then m.HP = max(1, min(full, floor(m.HP * full / max(m.FullHP, 1)))) end
		m.FullHP = full
		mulAttack(m.Attack1, B.DamageMul)
		mulAttack(m.Attack2, B.DamageMul)
		m.ArmorClass = min(255, floor(m.ArmorClass * B.ACMul + 0.5))
		m.Level = min(255, m.Level + B.LevelAdd)
		m.Experience = floor(m.Experience * B.ExpMul)
	end
	-- loot: a sure item a class better, more gold (the treasure isn't rolled yet)
	if not m.TreasureGenerated then
		m.TreasureItemPercent = 100
		m.TreasureItemLevel = min(6, max(1, m.TreasureItemLevel + B.TreasureUp))
		m.TreasureDiceCount = min(255, max(1, dice[1]) * B.GoldMul)
		m.TreasureDiceSides = max(dice[2], 10)
	end
	rec.FullHP = m.FullHP
	store()[i] = rec
end

local function scan()
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if isBoss(m) and alive(m) then
			boost(i, m)
			if not KEEP_STATS[m.NameId] and MF.SetBossAbilities and not MF.IsBossAbilityRecord(i, m) then
				MF.SetBossAbilities(i, m, B.Abilities)
			end
		end
	end
end

local function safeScan()
	local ok, err = pcall(scan)
	if not ok and MF.LogWarning then MF.LogWarning("Bosses: %s", tostring(err)) end
end

-- after the bolster: on loading a map and when the bolster settings change
function events.AfterMapBolster() safeScan() end
function events.AfterLoadMap() safeScan() end

---------------------------------------------------------------------------
-- the names in gold
---------------------------------------------------------------------------

-- (again on every map load, in case the texts were read again: names already coloured are skipped)
local function colorNames()
	if not Game.PlaceMonTxt then return end
	local c = B.Color
	for n = 1, Game.PlaceMonTxt.count - 1 do
		local s = Game.PlaceMonTxt[n]
		if s and s ~= "" and not NOT_BOSS[n] and not s:find("\f", 1, true) then
			Game.PlaceMonTxt[n] = StrColor(c[1], c[2], c[3], s)
		end
	end
end

function events.GameInitialized2() colorNames() end
function events.LoadMap() colorNames() end
