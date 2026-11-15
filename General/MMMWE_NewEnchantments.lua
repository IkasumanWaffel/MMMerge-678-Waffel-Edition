--[[
	MMMWE_NewEnchantments.lua — the special enchantments of 15.11.26 (SPCITEMS.TXT 146..153)

	146 Construct Slaying   weapons   double damage against constructs (ItemsModifiers.lua and
	                                  MMMWE_Slaying.lua, like the other slaying enchantments)
	147 of Pack Hunting     weapons   double damage against creatures (beasts, spiders, rats...)
	148 of the Exorcist     armor, shields, helms, cloaks, rings, amulets
	                                  half damage from the undead and demons
	149 of Banishing        weapons   BANISH_CHANCE % of hits slay a summoned monster outright
	150 Hunter's            belts, cloaks, boots, rings, amulets
	                                  Perception +HUNTER_PERCEPTION, HUNTER_GOLD x the gold found
	                                  (once, while a conscious wearer is in the party)
	151 of Sundering        weapons (mostly two-handed)
	                                  each physical hit opens the target: +SUNDER_STEP physical
	                                  damage taken from the party, SUNDER_MAX stacks, SUNDER_TIME s
	152 Arcane              two-handed weapons (staves), rings, amulets
	                                  wands cast at +ARCANE_WAND skill (MMMWE_ExtraSkillsEnchanting);
	                                  ARCANE_SP of the weapon damage dealt comes back as spell points
	153 of Retribution      armor, shields
	                                  RETRIBUTION of the melee damage taken goes back to the attacker
	Blasters slay constructs from Disruptor tier 2 (MF.BlasterSlays, MMMWE_Blasters.lua).
	Several pieces with the same enchantment don't add up (except the wands' skill).
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local floor, max, min, random = math.floor, math.max, math.min, math.random
local MK = const.MonsterKind

local B = {
	PackHunting = 147, Exorcist = 148, Banishing = 149, Hunter = 150, Sundering = 151,
	Arcane = 152, Retribution = 153,
}
MF.NewEnchantments = B

local BANISH_CHANCE     = 5
local HUNTER_PERCEPTION = 5
local HUNTER_GOLD       = 1.10
local SUNDER_STEP       = 0.05
local SUNDER_MAX        = 3
local SUNDER_TIME       = 10
local ARCANE_WAND       = 2
local ARCANE_SP         = 0.05
local RETRIBUTION       = 0.10
local DEMON, CREATURE   = 9, 19

local function has(pl, b)
	return pl and pl:HasItemBonus(b) > 0
end

local function status(s)
	if Game.ShowStatusText then Game.ShowStatusText(s) end
end

-- the monster that hit a character (as MMMWE_MonsterAbilities.lua finds it); melee: no missile
local function attacker()
	if not WhoHitPlayer then return end
	local who = WhoHitPlayer()
	if type(who) ~= "table" then return end
	if who.Monster then return who.Monster, who.MonsterIndex, who.Object == nil end
	local o = who.Object
	if o and o.Owner and o.Owner % 8 == 3 then
		local i = floor(o.Owner / 8)
		if i < Map.Monsters.count then return Map.Monsters[i], i, false end
	end
end

---------------------------------------------------------------------------
-- damage taken: of the Exorcist, of Retribution
---------------------------------------------------------------------------

function events.CalcDamageToPlayer(t)
	local pl = t.Player
	if not pl or (t.Result or 0) <= 0 then return end
	local exo, ret = has(pl, B.Exorcist), has(pl, B.Retribution)
	if not exo and not ret then return end
	local m, mi, melee = attacker()
	if not m then return end
	if exo and (Game.IsMonsterOfKind(m.Id, MK.Undead) ~= 0 or Game.IsMonsterOfKind(m.Id, DEMON) ~= 0) then
		t.Result = floor(t.Result / 2)
	end
	if ret and melee and MF.QueueForcedHit and m.HP > 0 then
		local back = floor(t.Result * RETRIBUTION)
		if back > 0 then MF.QueueForcedHit(t.PlayerIndex, mi, back, const.Damage.Phys) end
	end
end

---------------------------------------------------------------------------
-- damage dealt: of Banishing, of Sundering, Arcane
---------------------------------------------------------------------------

local Sunder = {}       -- [monster index] = {Stacks, Until, Id}

function events.LeaveMap() Sunder = {} end

local function summoned(m)
	return m.Summoner and m.Summoner ~= 0 and m.Summoner % 8 == 3
end

function events.CalcDamageToMonster(t)
	local pl, m = t.Player, t.Monster
	if not t.ByPlayer or not pl or not m or (t.Result or 0) <= 0 or t.IsSecondary then return end
	local phys = t.DamageKind == const.Damage.Phys
	-- the open wounds of Sundering, whoever strikes
	local s = Sunder[t.MonsterIndex]
	if s and (s.Id ~= m.Id or os.clock() > s.Until) then Sunder[t.MonsterIndex] = nil; s = nil end
	if s and phys then t.Result = floor(t.Result * (1 + SUNDER_STEP * s.Stacks)) end
	if not phys then return end
	if has(pl, B.Sundering) then
		s = s or {Stacks = 0, Id = m.Id}
		s.Stacks = min(SUNDER_MAX, s.Stacks + 1)
		s.Until = os.clock() + SUNDER_TIME
		Sunder[t.MonsterIndex] = s
	end
	if has(pl, B.Banishing) and summoned(m) and random(100) <= BANISH_CHANCE then
		t.Result = max(t.Result, m.HP)
		status(string.format(Tx"%s banishes %s", pl.Name, Game.MonstersTxt[m.Id].Name))
	end
	if has(pl, B.Arcane) then
		local full = pl:GetFullSP()
		if pl.SpellPoints < full then
			pl.SpellPoints = min(full, pl.SpellPoints + max(1, floor(t.Result * ARCANE_SP)))
		end
	end
end

-- the wands' skill (MMMWE_ExtraSkillsEnchanting.lua)
function MF.ArcaneWandBonus(pl)
	return has(pl, B.Arcane) and ARCANE_WAND or 0
end

---------------------------------------------------------------------------
-- Hunter's
---------------------------------------------------------------------------

function events.GetSkill(t)
	if t.Skill == const.Skills.Perception and has(t.Player, B.Hunter) then
		local s, m = SplitSkill(t.Result)
		if m > 0 then t.Result = JoinSkill(s + HUNTER_PERCEPTION, m) end
	end
end

function events.BeforeGotGold(t)
	for _, pl in Party do
		if pl:IsConscious() and has(pl, B.Hunter) then
			t.Amount = floor(t.Amount * HUNTER_GOLD)
			return
		end
	end
end
