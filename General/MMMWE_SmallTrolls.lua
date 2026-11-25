--[[
	MMMWE_SmallTrolls.lua - small trolls in caves (25.11.26)

	MM7's small troll sprites (m461, which the Swamp Troll only shows enlarged) are monsters
	655-657 in MONSTERS.txt: Troll Runt, Troll Brawler, Troll Bruiser (levels 5 / 9 / 14).
	TCRF's note on the cut small troll puts it in the dwarven barrows.

	On every refill of a listed map, a few bands are put at the map's monster spawn points
	(or, if it has none, next to its monsters). The map's own monsters stay.
	MAPS[map] = {Bands = {min, max}, Size = {min, max}, Mix = {runt, brawler, bruiser}}
	(Mix: shares, need not add up to 1).
	mapvars.MMMWE_SmallTrolls is set once a band is in, so a load without the monster rows
	(MONSTERS.txt not yet in revamp.T.lod) tries again next time.
--]]

local MF = Merge.Functions
local random, min = math.random, math.min

local TROLLS = {655, 656, 657}
local SPREAD = 150

local MAPS = {
	-- Antagarich
	["7d21.blv"] = {Bands = {3, 5}, Size = {2, 4}, Mix = {55, 30, 15}},   -- White Cliff Cave
	["7d24.blv"] = {Bands = {3, 4}, Size = {2, 4}, Mix = {40, 40, 20}},   -- Stone City
	["7d08.blv"] = {Bands = {2, 4}, Size = {2, 3}, Mix = {50, 35, 15}},   -- The Tularean Caves
	-- five of the fifteen barrows of the Barrow Downs
	["mdk01.blv"] = {Bands = {1, 2}, Size = {2, 3}, Mix = {70, 25, 5}},   -- Barrow VII
	["mdt02.blv"] = {Bands = {1, 2}, Size = {2, 3}, Mix = {70, 25, 5}},   -- Barrow VI
	["mdr03.blv"] = {Bands = {1, 2}, Size = {2, 3}, Mix = {70, 25, 5}},   -- Barrow V
	["mdk04.blv"] = {Bands = {1, 2}, Size = {2, 3}, Mix = {70, 25, 5}},   -- Barrow XIV
	["mdt05.blv"] = {Bands = {1, 2}, Size = {2, 3}, Mix = {70, 25, 5}},   -- Barrow XIII
	-- Jadame
	["d08.blv"] = {Bands = {2, 3}, Size = {2, 3}, Mix = {60, 30, 10}},    -- Dire Wolf Den
}
MF.SmallTrollMaps = MAPS

local function warn(fmt, ...)
	if MF.LogWarning then MF.LogWarning("small trolls: " .. fmt, ...) end
end

local function pickTroll(mix)
	local sum = mix[1] + mix[2] + mix[3]
	local r = random() * sum
	if r < mix[1] then return TROLLS[1] end
	if r < mix[1] + mix[2] then return TROLLS[2] end
	return TROLLS[3]
end

local function spawnTrolls()
	local cfg = MAPS[(Map.Name or ""):lower()]
	if not cfg or mapvars.MMMWE_SmallTrolls then return end
	local txt = Game.MonstersTxt
	if txt.count <= TROLLS[3] then
		warn("monster %d is missing from MONSTERS.txt (count %d)", TROLLS[3], txt.count)
		return
	end
	local points = {}
	for i = 0, Map.Spawns.count - 1 do
		local s = Map.Spawns[i]
		if s.Kind == const.ObjectRefKind.Monster then points[#points + 1] = {s.X, s.Y, s.Z} end
	end
	if #points == 0 then
		for i = 0, Map.Monsters.count - 1 do
			local m = Map.Monsters[i]
			if m.HP > 0 and m.AIState ~= const.AIState.Removed then points[#points + 1] = {m.X, m.Y, m.Z} end
		end
	end
	local sent = 0
	for _ = 1, min(random(cfg.Bands[1], cfg.Bands[2]), #points) do
		local p = table.remove(points, random(#points))
		for _ = 1, random(cfg.Size[1], cfg.Size[2]) do
			local ok, m = pcall(SummonMonster, pickTroll(cfg.Mix),
				p[1] + random(-SPREAD, SPREAD), p[2] + random(-SPREAD, SPREAD), p[3], true)
			if ok and m then
				pcall(m.LoadFramesAndSounds, m)
				m.Hostile = true
				pcall(function() m.ShowAsHostile = true end)
				sent = sent + 1
			elseif not ok then
				warn("SummonMonster: %s", tostring(m))
			end
		end
	end
	if sent > 0 then
		mapvars.MMMWE_SmallTrolls = true
	else
		warn("none placed on %s (%d spawn points)", Map.Name, #points)
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(spawnTrolls)
	if not ok then warn("%s", tostring(err)) end
end
