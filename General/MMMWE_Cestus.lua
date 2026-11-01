--[[
	MMMWE_Cestus.lua — cestuses: gauntlet-slot weapons of the Unarmed skill (01.11.26)

	A cestus is worn in the gauntlet slot (ITEMS.txt, Skill Group Unarmed: the Unarmed skill is
	needed to wear one), so the monk stays bare-handed for every Unarmed and Monk rule
	(MF.IsBareHanded looks at the hands only). With bare hands each melee blow also deals:
	  * the cestus's own element, if it has one (CESTUS below: dice and kind; "least" = the one
	    of Fire, Air, Water and Earth the target resists least)
	  * the damage of an elemental enchantment on it ("of Fire", "of Frost", "of Mind Bite"...)
	both scaled like weapon enchantments (MMMWE_EnchantScaling.lua; a cestus scales with the
	Unarmed skill), then reduced by the monster's resistance to that element. The physical blow
	stays the main source of damage. The elemental parts are dealt as separate hits of their
	kind right after the blow (MF.QueueForcedHit, MMMWE_Blasters.lua), so monsters immune to
	physical damage still take them.

	Found cestuses can carry an elemental enchantment like weapons do: Special % by the
	treasure level (10 / 20 / 30 / 50% at levels 3-6), its rank by the level.

	Artifacts and relics (bonuses in ExtraArtifacts.lua): Fists of the Four Winds, Palms of
	Serenity, Shadowgrip (artifacts), Mountain's Heart (relic).

	MF.QueueElementalHit(pi, mi, dmg, kind) is also used by the Master Monk's Ki strikes
	(MMMWE_MonkBranches.lua).
--]]

local MF = Merge.Functions
local D = const.Damage
local floor, max, min, random = math.floor, math.max, math.min, math.random

local C = {
	SpecialChance = {[3] = 10, [4] = 20, [5] = 30, [6] = 50},   -- % for an elemental enchantment
	-- enchantment ranks (SPCITEMS.TXT Lvl A..D = 1..4) by treasure level
	RankByStrength = {[3] = {1, 1}, [4] = {1, 2}, [5] = {2, 3}, [6] = {3, 4}},
}
MF.CestusSettings = C

-- item id = {Kind = damage kind or "least", Dice = {count, sides}} (nil: no element of its own)
local CESTUS = {
	[2201] = {},                                          -- Leather Cestus
	[2202] = {},                                          -- Studded Cestus
	[2203] = {Kind = D.Fire,  Dice = {1, 6}},             -- Ember Cestus
	[2204] = {Kind = D.Air,   Dice = {1, 6}},             -- Storm Cestus
	[2205] = {Kind = D.Water, Dice = {1, 6}},             -- Frost Cestus
	[2206] = {Kind = D.Earth, Dice = {1, 6}},             -- Stone Cestus
	[2207] = {},                                          -- Mithril Cestus
	[2208] = {Kind = D.Fire,  Dice = {2, 6}},             -- Dragonbone Cestus
	[2209] = {Kind = "least", Dice = {2, 6}},             -- Fists of the Four Winds (artifact)
	[2210] = {Kind = D.Mind,  Dice = {2, 6}},             -- Palms of Serenity (artifact)
	[2211] = {Kind = D.Dark,  Dice = {2, 6}},             -- Shadowgrip (artifact)
	[2212] = {Kind = D.Earth, Dice = {3, 6}},             -- Mountain's Heart (relic)
	[2215] = {Kind = D.Energy, Dice = {2, 8}},            -- Servo Gauntlets (MMMWE_AncientArtifacts.lua)
}
MF.Cestuses = CESTUS
local ARTIFACTS = {[2209] = true, [2210] = true, [2211] = true, [2212] = true, [2215] = true}

local FOUR = {D.Fire, D.Air, D.Water, D.Earth}

---------------------------------------------------------------------------
-- resistances
---------------------------------------------------------------------------

local RES_FIELD = {
	[D.Fire] = "FireResistance", [D.Air] = "AirResistance", [D.Water] = "WaterResistance",
	[D.Earth] = "EarthResistance", [D.Spirit] = "SpiritResistance", [D.Mind] = "MindResistance",
	[D.Body] = "BodyResistance", [D.Light] = "LightResistance", [D.Dark] = "DarkResistance",
}

-- share of the damage a resistance takes away (the expected value of the game's rolls,
-- the curve of MMMWE_Main.lua)
local function reduction(res)
	if not res or res <= 0 then return 0 end
	if res >= 65000 then return 1 end
	local p = 1 - 30 / (res + 30)
	return 0.5 * p + 0.25 * p^2 + 0.125 * p^3 + 0.0625 * p^4
end

local function monRes(mon, kind)
	local f = RES_FIELD[kind]
	if not f then return 0 end
	local ok, v = pcall(function() return mon[f] end)
	return ok and v or 0
end

-- of Fire, Air, Water and Earth: the kind the monster resists least (ties: a random one)
function MF.LeastResistedElement(mon)
	local best, bestR = {}, nil
	for _, k in ipairs(FOUR) do
		local r = reduction(monRes(mon, k))
		if not bestR or r < bestR - 1e-9 then
			best, bestR = {k}, r
		elseif math.abs(r - bestR) <= 1e-9 then
			best[#best + 1] = k
		end
	end
	return best[random(#best)]
end

-- an extra hit of an element by character pi (PlayersArray index) on monster mi: the
-- resistance is applied here, the hit is dealt on the next tick
function MF.QueueElementalHit(pi, mi, dmg, kind)
	if not MF.QueueForcedHit or not dmg or dmg <= 0 then return 0 end
	local mon = Map.Monsters[mi]
	if not mon then return 0 end
	local final = floor(dmg * (1 - reduction(monRes(mon, kind))) + 0.5)
	if final > 0 then MF.QueueForcedHit(pi, mi, final, kind) end
	return final
end

---------------------------------------------------------------------------
-- elemental enchantments (SPCITEMS.TXT "Adds X-Y points of <element> damage.")
---------------------------------------------------------------------------

local WORD_KIND = {
	Fire = D.Fire, Cold = D.Water, Water = D.Water, Electrical = D.Air, Air = D.Air,
	Earth = D.Earth, Spirit = D.Spirit, Mind = D.Mind, Body = D.Body, Light = D.Light, Dark = D.Dark,
}
local Elemental = {}    -- [Bonus2] = {Min, Max, Kind, Rank}
local ByRank = {}       -- [rank] = {Bonus2, ...}

local function parseEnchantments()
	Elemental, ByRank = {}, {}
	for idx, v in Game.SpcItemsTxt do
		local s = v.BonusStat or ""
		local a, b, word = s:match("^%s*Adds (%d+)%-(%d+) points of (%a+) damage%.%s*$")
		if not a then
			a, word = s:match("^%s*Adds (%d+) points of (%a+) damage%.%s*$")
			b = a
		end
		local kind = word and WORD_KIND[word]
		if kind then
			local rank = v.Lvl or 1
			if rank >= 65 then rank = rank - 64 end      -- stored as a letter
			rank = max(1, min(4, rank))
			local b2 = idx + 1
			Elemental[b2] = {Min = tonumber(a), Max = tonumber(b), Kind = kind, Rank = rank}
			ByRank[rank] = ByRank[rank] or {}
			table.insert(ByRank[rank], b2)
		end
	end
end

---------------------------------------------------------------------------
-- items
---------------------------------------------------------------------------

function MF.IsCestus(num)
	return CESTUS[num] ~= nil
end

-- the cestus worn by a player (nil if none, broken, or the hands aren't bare)
local function wornCestus(pl)
	local slot = pl.ItemGauntlets
	if not slot or slot == 0 then return end
	local it = pl.Items[slot]
	if not it or not CESTUS[it.Number] or it.Broken then return end
	return it
end
MF.WornCestus = wornCestus

function events.GameInitialized2()
	-- (the rows are in ITEMS.txt of revamp.T.lod; without them the ids don't exist yet)
	for id in pairs(CESTUS) do
		if id < Game.ItemsTxt.count then Game.ItemsTxt[id].Skill = const.Skills.Unarmed end
	end
	parseEnchantments()
end

-- found cestuses: an elemental enchantment like weapons get one
-- (registered at load, before MMMWE_Main.lua hides the bonuses of unidentified items)
function events.ItemGenerated(t)
	local it = t.Item
	if not it or not CESTUS[it.Number] or ARTIFACTS[it.Number] or it.Bonus2 ~= 0 then return end
	local s = t.Strength or 0
	local chance = C.SpecialChance[s]
	if not chance or random(100) > chance then return end
	local ranks = C.RankByStrength[s]
	local pool = {}
	for r = ranks[1], ranks[2] do
		for _, b2 in ipairs(ByRank[r] or {}) do pool[#pool + 1] = b2 end
	end
	if #pool > 0 then it.Bonus2 = pool[random(#pool)] end
end

---------------------------------------------------------------------------
-- the blows
---------------------------------------------------------------------------

local function roll(n, s)
	local r = 0
	for _ = 1, n do r = r + random(s) end
	return r
end

local function scale(pl, it, dmg, kind)
	return MF.ScaleEnchantDamage and MF.ScaleEnchantDamage(pl, it, dmg, kind) or dmg
end

-- the elemental parts of one blow: {kind = damage before resistance}
function MF.CestusDamage(pl, mon)
	local it = wornCestus(pl)
	if not it then return nil end
	local parts = {}
	local c = CESTUS[it.Number]
	if c.Dice then
		local kind = c.Kind == "least" and MF.LeastResistedElement(mon) or c.Kind
		parts[kind] = (parts[kind] or 0) + scale(pl, it, roll(c.Dice[1], c.Dice[2]), kind)
	end
	local e = it.Bonus2 ~= 0 and Elemental[it.Bonus2]
	if e then
		parts[e.Kind] = (parts[e.Kind] or 0) + scale(pl, it, random(e.Min, e.Max), e.Kind)
	end
	return parts
end

function events.CalcDamageToMonster(t)
	if not t.ByPlayer or t.IsSecondary or not t.Melee then return end
	if t.DamageKind ~= const.Damage.Phys then return end
	if MF.BlasterSpecs and MF.BlasterSpecs.Forced then return end
	local pl, mon = t.Player, t.Monster
	if not pl or not mon or not t.PlayerIndex or not t.MonsterIndex then return end
	if not (MF.IsBareHanded and MF.IsBareHanded(pl)) then return end
	local parts = MF.CestusDamage(pl, mon)
	if not parts then return end
	for kind, dmg in pairs(parts) do
		MF.QueueElementalHit(t.PlayerIndex, t.MonsterIndex, dmg, kind)
	end
end
