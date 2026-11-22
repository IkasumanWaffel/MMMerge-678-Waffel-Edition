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
	stay) and Q (has its own stats, Bolster-SpcMonsters.txt).
	Weaknesses (WEAK), shown on the monster card as an ability:
	  Wromthrax - Old Wound: the menace of the centuries, but a hero of old nearly killed him
	  and the wound never closed. Critical hits deal CritMul times their extra damage, Air
	  (lightning through a water dragon's hide) gets through his resistance, and the wound
	  makes him flinch: no Juggernaut, so hits stagger him. A boss for a low-level party that
	  fights him with lightning and well-aimed blows (the first Paladin promotion).
	A carried item (Monster.Item: the Sandals, the named drops) is never touched.

	The bolster sets a monster's stats again on every map load; the boost is put back on
	after it (the boosted Hit Points are kept to tell a boosted monster from a reset one).
	MF.IsBoss(monster) -> true for a boss.
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local floor, max, min = math.floor, math.max, math.min
local VERSION = 2      -- records of an older version are boosted again

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
	[163] = true, [164] = true, [166] = true,   -- Placeholder
}
-- bosses by name and loot only
local KEEP_STATS = {
	[118] = true,                     -- Mega-Dragon
	[123] = true, [133] = true,       -- Q
}

-- (22.11.26) the necromancer the map puts atop Castle Harmondale (a Speaker for the Dead,
-- MONSTERS.txt 308) is named and so a boss: the Butler's quest (Global\MMMWE_BossQuests.lua).
-- She has her own Placemon.txt line, 165 (the placeholders 163, 164 and 166 kept as they
-- are); the highest one of the map's Speakers at the first visit (later ones, such as the
-- siege's, stay ordinary).
local SPEAKER = {
	NameId = 165,
	OldNameId = 163,   -- given to her for a while on 22.11.26
	Name   = Tx"Veyla the Speaker",
	MonId  = 308,
	Maps   = {["7out02.odm"] = true, ["7d29.blv"] = true},
}
MF.BossSpeaker = SPEAKER

local function tagSpeaker()
	if not SPEAKER.Maps[Map.Name:lower()] then return end
	if Game.PlaceMonTxt.count <= SPEAKER.NameId then return end   -- an older revamp.T.lod
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.Id == SPEAKER.MonId and m.NameId == SPEAKER.OldNameId then m.NameId = SPEAKER.NameId end
	end
	if mapvars.MMMWE_SpeakerTagged then return end
	mapvars.MMMWE_SpeakerTagged = true
	local best
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.Id == SPEAKER.MonId and (m.NameId or 0) == 0 and m.HP > 0
				and m.AIState ~= const.AIState.Removed and (not best or m.Z > best.Z) then
			best = m
		end
	end
	if best then best.NameId = SPEAKER.NameId end
end

-- (23.11.26) monsters that become a named boss on a map's first visit: the strongest of the
-- listed kinds, unless the map already has a monster of that name. The Devil of Baa is a
-- Kreegan among the cultists in the Temple of Baa (AvLee).
local TAGS = {
	{Map = "d04.blv", NameId = 138, MonIds = {[220] = true, [221] = true, [222] = true}, Key = "DevilOfBaa"},
}

local function tagStrongest()
	local name = Map.Name:lower()
	for _, t in ipairs(TAGS) do
		local key = "MMMWE_BossTag_" .. t.Key
		if t.Map == name and not mapvars[key] and Game.PlaceMonTxt.count > t.NameId then
			mapvars[key] = true
			local best, have = nil, false
			for i = 0, Map.Monsters.count - 1 do
				local m = Map.Monsters[i]
				if m.NameId == t.NameId then have = true end
				if t.MonIds[m.Id] and (m.NameId or 0) == 0 and m.HP > 0 and m.AIState ~= const.AIState.Removed
						and (not best or m.Level > best.Level or (m.Level == best.Level and m.FullHP > best.FullHP)) then
					best = m
				end
			end
			if best and not have then best.NameId = t.NameId end
		end
	end
end

-- (23.11.26) bonus encounters without a quest: richer loot (treasure classes more, gold x)
local EXTRA_LOOT = {
	[135] = true,   -- Lurch
	[26]  = true,   -- Guthwulf
	[128] = true,   -- Lesser Genie
	[125] = true,   -- Fallen Defender
}
B.ExtraTreasureUp, B.ExtraGoldMul = 1, 2

-- weaknesses by Placemon.txt line
local WEAK = {
	[117] = {                         -- Wromthrax: Old Wound
		Ability = "OldWound",
		CritMul = 2,                  -- a critical hit's extra damage x this (x1.5 -> x2)
		Resist = {AirResistance = 0},
		NoJuggernaut = true,
		Text = Tx"The old wound tears open!",
	},
}
MF.BossWeaknesses = WEAK

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
	local same = rec and rec.Id == m.Id and rec.NameId == m.NameId and rec.V == VERSION
	-- already boosted, and the bolster hasn't reset it since
	if same and rec.FullHP == m.FullHP then return end
	-- the gold dice aren't set again by the bolster: kept from the first time
	local dice = same and rec.Dice or {m.TreasureDiceCount, m.TreasureDiceSides}
	rec = {Id = m.Id, NameId = m.NameId, Dice = dice, V = VERSION}
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
	local w = WEAK[m.NameId]
	if w and w.Resist then
		for k, v in pairs(w.Resist) do m[k] = v end
	end
	-- loot: a sure item a class better, more gold (the treasure isn't rolled yet)
	if not m.TreasureGenerated then
		m.TreasureItemPercent = 100
		local extra = EXTRA_LOOT[m.NameId]
		m.TreasureItemLevel = min(6, max(1, m.TreasureItemLevel + B.TreasureUp + (extra and B.ExtraTreasureUp or 0)))
		m.TreasureDiceCount = min(255, max(1, dice[1]) * B.GoldMul * (extra and B.ExtraGoldMul or 1))
		m.TreasureDiceSides = max(dice[2], 10)
	end
	rec.FullHP = m.FullHP
	store()[i] = rec
end

local function scan()
	tagSpeaker()
	tagStrongest()
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if isBoss(m) and alive(m) then
			boost(i, m)
			if not KEEP_STATS[m.NameId] and MF.SetBossAbilities and not MF.IsBossAbilityRecord(i, m) then
				local w = WEAK[m.NameId]
				MF.SetBossAbilities(i, m, B.Abilities,
					w and {NoJuggernaut = w.NoJuggernaut, Extra = {w.Ability}})
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
-- critical hits on a weak boss (CalcCrits, MMMWE_Main.lua: 1 or the crit multiplier)
---------------------------------------------------------------------------

local function wrapCrits()
	if not CalcCrits or MF.BossCritsWrapped then return end
	MF.BossCritsWrapped = true
	local calc = CalcCrits
	CalcCrits = function(pl, melee, mon, ...)
		local r = calc(pl, melee, mon, ...)
		local w = mon and r > 1 and WEAK[mon.NameId or 0]
		if w and w.CritMul and isBoss(mon) then
			r = 1 + (r - 1) * w.CritMul
			if w.Text then Game.ShowStatusText(w.Text, 2) end
		end
		return r
	end
end

---------------------------------------------------------------------------
-- the names in gold
---------------------------------------------------------------------------

-- (again on every map load, in case the texts were read again: names already coloured are skipped)
local function colorNames()
	if not Game.PlaceMonTxt then return end
	local cur = Game.PlaceMonTxt.count > SPEAKER.NameId and Game.PlaceMonTxt[SPEAKER.NameId]
	if cur and not cur:find(SPEAKER.Name, 1, true) then Game.PlaceMonTxt[SPEAKER.NameId] = SPEAKER.Name end
	local c = B.Color
	for n = 1, Game.PlaceMonTxt.count - 1 do
		local s = Game.PlaceMonTxt[n]
		if s and s ~= "" and not NOT_BOSS[n] and not s:find("\f", 1, true) then
			Game.PlaceMonTxt[n] = StrColor(c[1], c[2], c[3], s)
		end
	end
end

function events.GameInitialized2() colorNames(); wrapCrits() end
function events.LoadMap() colorNames() end
