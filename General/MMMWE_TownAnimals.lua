--[[
	MMMWE_TownAnimals.lua - domestic animals in the towns of all three continents (26.11.26)

	MM7 has cats, chickens, dogs and rats that were never placed (monsters 463-474, A/B/C
	each); Waffel Edition put some in Harmondale, Erathia and the Tularean Forest by hand.
	This script brings them to the other outdoor towns, chosen by each town's people and
	ways (warlocks, necromancers and elves keep cats, farmers chickens, hunters dogs, ports
	rats), with a few animal-like creatures where they fit (young couatls with the lizardmen,
	bats in the dark towns, dragonflies in the swamps).

	On every refill of a listed map with at least MIN_PEASANTS townsfolk (peasant monsters),
	COUNT animals are placed next to random townsfolk, peaceful like them (their group and
	ally). The variant (A/B/C: three colourings, palettes 545 / 2101 / 2102) is random.
	(27.11.26) A map whose own monster list already has domestic animals (Harmondale, Erathia,
	the Tularean Forest) keeps them, each given a random colouring of its own kind, and gets
	only EXTRA more, of the kinds that suit the town.
	TOWNS[map] = {{kind, weight}, ...}; kind = the A line's monster id, Variants = false for
	a creature with one line only.
	mapvars.MMMWE_TownAnimals is set once the map has been handled.
	(27.11.26) Every animal takes the side of the townsfolk: its Ally is set to the Hostile.txt
	class of a peasant of the town, so the engine judges it by the peasants' relations instead
	of its own class (a wild dragonfly or couatl class is hostile to the party and the
	peasants). Saves made before this get it on their next visit (mapvars.MMMWE_TownAnimalsSide).
--]]

local MF = Merge.Functions
local random, floor, min, max = math.random, math.floor, math.min, math.max

local CAT, CHICKEN, DOG, RAT = 463, 466, 469, 472
local COUATL, BAT, DRAGONFLY = 7, 205, 226
local DOMESTIC = {}                         -- 463..474
for i = 463, 474 do DOMESTIC[i] = true end

local MIN_PEASANTS = 3
local COUNT = {4, 12}                       -- at least, at most; else townsfolk / 2
local SPREAD = {120, 420}                   -- distance from the townsfolk
local EXTRA = {2, 5}                        -- added where the map has animals of its own

local TOWNS = {
	-- Antagarich
	["7out02.odm"] = {{CHICKEN, 2}, {CAT, 1}, {RAT, 1}},                        -- Harmondale (has its own)
	["7out03.odm"] = {{DOG, 2}, {CAT, 1}, {RAT, 1}},                            -- Erathia (has its own)
	["7out04.odm"] = {{CAT, 3}, {CHICKEN, 1}},                                  -- Tularean Forest (has its own)
	["7out01.odm"] = {{CHICKEN, 3}, {DOG, 2}, {CAT, 1}},                        -- Emerald Island
	["7out05.odm"] = {{CAT, 3}, {RAT, 3}, {BAT, 1}},                            -- Deyja
	["7out06.odm"] = {{CAT, 3}, {DOG, 1}, {CHICKEN, 1}},                        -- Bracada Desert
	["7out13.odm"] = {{DOG, 2}, {CHICKEN, 2}, {RAT, 2}, {DRAGONFLY, 1}},        -- Tatalia
	["out09.odm"]  = {{CHICKEN, 2}, {CAT, 2}, {DOG, 1}},                        -- Evenmorn Island
	["out10.odm"]  = {{CAT, 4}, {RAT, 2}},                                      -- Mount Nighon
	["out11.odm"]  = {{DOG, 2}, {CHICKEN, 2}},                                  -- The Barrow Downs
	["out14.odm"]  = {{CAT, 3}, {CHICKEN, 2}, {DOG, 1}},                        -- AvLee
	-- Jadame
	["out01.odm"]  = {{CHICKEN, 3}, {COUATL, 2}},                               -- Dagger Wound Island
	["out02.odm"]  = {{DOG, 3}, {CAT, 2}, {CHICKEN, 2}, {RAT, 1}},              -- Ravenshore
	["out03.odm"]  = {{DOG, 2}, {CHICKEN, 2}, {CAT, 1}},                        -- Alvar
	["out04.odm"]  = {{DOG, 2}, {RAT, 2}},                                      -- Ironsand Desert
	["out05.odm"]  = {{DOG, 3}, {CHICKEN, 1}},                                  -- Garrote Gorge
	["out06.odm"]  = {{CAT, 3}, {RAT, 3}, {BAT, 1}},                            -- Shadowspire
	["out13.odm"]  = {{RAT, 3}, {CAT, 2}, {DOG, 1}},                            -- Regna
	-- Enroth
	["oute3.odm"]  = {{CHICKEN, 3}, {DOG, 2}, {CAT, 2}},                        -- New Sorpigal
	["outc2.odm"]  = {{CAT, 3}, {DOG, 2}, {RAT, 2}, {CHICKEN, 1}},              -- Free Haven
	["outd1.odm"]  = {{CAT, 3}, {DOG, 2}, {CHICKEN, 1}},                        -- Silver Cove
	["outd2.odm"]  = {{DOG, 2}, {CHICKEN, 2}, {RAT, 2}},                        -- Bootleg Bay
	["outd3.odm"]  = {{DOG, 3}, {CAT, 2}, {CHICKEN, 2}},                        -- Castle Ironfist
	["outb2.odm"]  = {{DOG, 3}, {CHICKEN, 2}, {CAT, 1}},                        -- Blackshire
	["outb1.odm"]  = {{CAT, 3}, {RAT, 3}},                                      -- Kriegspire
	["oute2.odm"]  = {{CAT, 2}, {CHICKEN, 2}, {DOG, 1}},                        -- Misty Islands
	["outa1.odm"]  = {{CHICKEN, 2}, {DOG, 2}},                                  -- Sweet Water
	["outa2.odm"]  = {{CHICKEN, 2}, {DOG, 1}},                                  -- Paradise Valley
	["outc1.odm"]  = {{DOG, 3}, {CHICKEN, 1}},                                  -- Frozen Highlands
	["outc3.odm"]  = {{RAT, 3}, {CAT, 2}, {DRAGONFLY, 1}},                      -- Mire of the Damned
}
MF.TownAnimals = TOWNS

-- creatures with one line only (no A/B/C colourings of their own)
local SINGLE = {[COUATL] = true, [BAT] = true, [DRAGONFLY] = true}

local function warn(fmt, ...)
	if MF.LogWarning then MF.LogWarning("town animals: " .. fmt, ...) end
end

local function isPeasant(id)
	local k = const.MonsterKind and const.MonsterKind.Peasant
	local r = k and Game.IsMonsterOfKind(id, k)
	return r ~= nil and r ~= 0 and r ~= false
end

-- the Hostile.txt class whose relations a townsman (and his animals) follow
local function side(f)
	if f.Ally ~= 0 then return f.Ally end
	return floor((f.Id + 2) / 3)
end

local function befriend(m, f)
	m.Group = f.Group
	m.Ally = side(f)
	m.Hostile = false
	pcall(function() m.ShowAsHostile = false end)
	pcall(function() m.HostileType = 0 end)
end

local function pick(pool)
	local sum = 0
	for _, e in ipairs(pool) do sum = sum + e[2] end
	local r = random() * sum
	for _, e in ipairs(pool) do
		r = r - e[2]
		if r < 0 then return e[1] end
	end
	return pool[1][1]
end

local function place()
	local name = (Map.Name or ""):lower()
	local pool = TOWNS[name]
	if not pool or mapvars.MMMWE_TownAnimals then return end
	if Game.MonstersTxt.count <= RAT + 2 then return end

	local folk, pets, own = {}, {}, 0
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.AIState ~= const.AIState.Removed then
			if DOMESTIC[m.Id] then
				-- the map's own animal: same kind, a random colouring
				local base = m.Id - (m.Id - CAT) % 3
				local id = base + random(0, 2)
				if id ~= m.Id then
					m.Id = id
					pcall(m.LoadFramesAndSounds, m)
				end
				pets[#pets + 1] = m
				own = own + 1
			elseif isPeasant(m.Id) then
				folk[#folk + 1] = m
			end
		end
	end
	mapvars.MMMWE_TownAnimals = true
	mapvars.MMMWE_TownAnimalsSide = true
	if #folk > 0 then
		for _, m in ipairs(pets) do befriend(m, folk[random(#folk)]) end
	end
	if #folk < MIN_PEASANTS then return end

	local n = own > 0 and random(EXTRA[1], EXTRA[2]) or min(COUNT[2], max(COUNT[1], floor(#folk / 2)))
	local placed = 0
	for _ = 1, n do
		local f = folk[random(#folk)]
		local kind = pick(pool)
		local id = SINGLE[kind] and kind or kind + random(0, 2)
		local a = random() * 2 * math.pi
		local d = random(SPREAD[1], SPREAD[2])
		local x, y = f.X + floor(math.cos(a) * d), f.Y + floor(math.sin(a) * d)
		local ok, m = pcall(SummonMonster, id, x, y, f.Z, true)
		if ok and m then
			pcall(m.LoadFramesAndSounds, m)
			befriend(m, f)
			placed = placed + 1
		elseif not ok then
			warn("SummonMonster: %s", tostring(m))
		end
	end
	if MF.LogInfo then MF.LogInfo("town animals: %d placed on %s (%d townsfolk, %d of its own recoloured)", placed, name, #folk, own) end
end

-- a map handled before the animals took the townsfolk's side: the domestic animals, and the
-- couatls, bats and dragonflies that share a group with the townsfolk (placed by this script)
local function migrate()
	local name = (Map.Name or ""):lower()
	if not TOWNS[name] or not mapvars.MMMWE_TownAnimals or mapvars.MMMWE_TownAnimalsSide then return end
	mapvars.MMMWE_TownAnimalsSide = true
	local folk, byGroup, list = {}, {}, {}
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.AIState ~= const.AIState.Removed then
			if isPeasant(m.Id) then
				folk[#folk + 1] = m
				byGroup[m.Group] = byGroup[m.Group] or m
			elseif DOMESTIC[m.Id] or SINGLE[m.Id] then
				list[#list + 1] = m
			end
		end
	end
	if #folk == 0 then return end
	local n = 0
	for _, m in ipairs(list) do
		local f = byGroup[m.Group]
		if f or DOMESTIC[m.Id] then
			befriend(m, f or folk[random(#folk)])
			n = n + 1
		end
	end
	if MF.LogInfo then MF.LogInfo("town animals: %d set to the townsfolk's side on %s", n, name) end
end

function events.AfterLoadMap()
	local ok, err = pcall(migrate)
	if not ok then warn("%s", tostring(err)) end
	ok, err = pcall(place)
	if not ok then warn("%s", tostring(err)) end
end
