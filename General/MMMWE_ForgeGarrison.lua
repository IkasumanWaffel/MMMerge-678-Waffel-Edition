--[[
	MMMWE_ForgeGarrison.lua — Kastore's Forge troops after the Dark ending of MM7 (11.11.26)

	Once the Heavenly Forge is running ("Got the sci-fi part", QBit 633, on the path of Dark, 612), Castle Gloaming,
	The Pit and Deyja get a garrison of the Forge's own make: real Blaster Guys and Droids
	added next to the monsters that live there. The monsters of the map stay as they are, and
	the garrison is scaled by AdaptiveMonstersStats.lua like any summoned monster
	(SummonMonster is wrapped there).

	Sides: the garrison fights for the party (Ally 9999, the side of reanimated and summoned
	monsters) and never turns on it or on the map's own people: for as long as the party is on
	the map, Hostile.txt is changed locally (LocalHostileTxt) so the Blaster Guy and Robot
	classes are peaceful to the party and to the classes they are placed next to (Necromancers
	and Liches, Deyja's goblin guards), both ways. Anything hostile to the party stays their
	enemy.

	The garrison is placed once per map fill (mapvars are cleared on a refill); a map that
	still holds Blaster Guys or Droids, alive or dead, is not given another one (these maps
	have none of their own).
	The map scripts keep only their own effects (Deyja's sky, fog and twilight: 7out05.lua);
	the music is in MMMWE_Music.lua.
--]]

local MF = Merge.Functions

local FORGE_DONE = 633            -- QBit "Got the sci-fi part" (the end of either path)
local DARK_PATH  = 612            -- QBit "Chose the path of Dark"

-- Monster ids
local BLASTER_GUY = 459           -- Blaster Guy C
local SENTINEL    = 389           -- Sentinel Droid (Robot B)
local ASSASSIN    = 390           -- Assassin Droid (Robot C)
local FORGE_IDS = {[457] = true, [458] = true, [459] = true, [388] = true, [389] = true, [390] = true}

-- Per map: which troop is placed next to which denizen, at most Max troops, and the denizen
-- classes (monster ids) the garrison must stay at peace with
local GARRISONS = {
	["d03.blv"] = {                                -- Castle Gloaming
		Max = 12,
		Next = {[307] = BLASTER_GUY, [289] = SENTINEL, [290] = ASSASSIN},
	},
	["7d26.blv"] = {                               -- The Pit
		Max = 16,
		Next = {[307] = BLASTER_GUY, [289] = SENTINEL, [290] = ASSASSIN},
	},
	["7out05.odm"] = {                             -- Deyja: next to the goblin guards
		Max = 10,
		Next = {[271] = BLASTER_GUY, [272] = BLASTER_GUY, [273] = SENTINEL},
	},
}
MF.ForgeGarrisons = GARRISONS

local OFFSET = 48                 -- a troop stands this far from its denizen

-- Hostile.txt row/column of a monster id
local function class(id) return math.floor((id + 2) / 3) end

local function alive(m)
	return m.HP > 0 and m.AIState ~= const.AIState.Removed and m.AIState ~= const.AIState.Dead
		and m.AIState ~= const.AIState.Dying
end

-- peace between the Forge classes and the party / the map's own classes, for this visit only
local function makePeace(g)
	LocalHostileTxt()
	local H = Game.HostileTxt
	local forge = {}
	for id in pairs(FORGE_IDS) do forge[class(id)] = true end
	-- the people the garrison stands with: the classes it is placed next to
	local own = {}
	for id in pairs(g.Next) do own[class(id)] = true end
	for fc in pairs(forge) do
		H[fc][0] = 0                                   -- the party
		for oc in pairs(own) do
			if not forge[oc] then
				H[fc][oc] = 0
				H[oc][fc] = 0
			end
		end
	end
end

local function hasGarrison()
	for i, m in Map.Monsters do
		if FORGE_IDS[m.Id] and m.AIState ~= const.AIState.Removed then
			return true
		end
	end
	return false
end

local function enlist(m)
	m.Ally = 9999                                      -- the party's side
	m.Group = 0
	m.Summoner = 0                                     -- not a Technician's droid (MMMWE_Resources.lua)
	m.Hostile = false
	pcall(function() m.ShowAsHostile = false end)
end

local function placeGarrison(g)
	-- the denizens the troops go next to, spread over the map when there are more than Max
	local anchors = {}
	for i, m in Map.Monsters do
		if g.Next[m.Id] and m.Ally ~= 9999 and alive(m) then
			anchors[#anchors + 1] = {Id = m.Id, X = m.X, Y = m.Y, Z = m.Z}
		end
	end
	local n = #anchors
	if n == 0 then return 0 end
	local step = math.max(1, n / g.Max)
	local placed = 0
	local k = 1
	while k <= n and placed < g.Max do
		local a = anchors[math.floor(k)]
		local side = placed % 2 == 0 and OFFSET or -OFFSET
		local ok, m = pcall(SummonMonster, g.Next[a.Id], a.X + side, a.Y, a.Z, false)
		if ok and m then
			pcall(m.LoadFramesAndSounds, m)
			enlist(m)
			m.GuardX, m.GuardY, m.GuardZ = m.X, m.Y, m.Z
			placed = placed + 1
		end
		k = k + step
	end
	return placed
end

function events.AfterLoadMap()
	if not (Party.QBits[FORGE_DONE] and Party.QBits[DARK_PATH]) then return end
	local g = GARRISONS[(Map.Name or ""):lower()]
	if not g then return end
	makePeace(g)
	if not mapvars.MMMWE_ForgeGarrison and not hasGarrison() then
		placeGarrison(g)
	end
	mapvars.MMMWE_ForgeGarrison = true
	-- every troop on the map is on the party's side, those of an older save too (the old map
	-- scripts turned some denizens into Blaster Guys and Droids: they count as the garrison)
	for i, m in Map.Monsters do
		if FORGE_IDS[m.Id] then enlist(m) end
	end
end
