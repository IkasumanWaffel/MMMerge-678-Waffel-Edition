-- White Cliff Cave
-- (MMMWE 25.11.26) small trolls (MM7's unused 7m452 sprites; monsters 655-657: Troll Runt,
-- Troll Brawler, Troll Bruiser) live here alongside the oozes: on every refill a few bands are
-- put at the cave's monster spawn points, mostly runts, some brawlers, a rare bruiser.

local TROLLS = {655, 656, 657}
local BANDS = {3, 5}         -- bands per refill (at most the number of spawn points)
local BAND_SIZE = {2, 4}
local SPREAD = 150

local function pickTroll()
	local r = math.random()
	if r < 0.15 then return TROLLS[3] end
	if r < 0.45 then return TROLLS[2] end
	return TROLLS[1]
end

local function spawnTrolls()
	if mapvars.MMMWE_SmallTrolls then return end
	mapvars.MMMWE_SmallTrolls = true
	if Game.MonstersTxt.count <= TROLLS[3] then return end   -- MONSTERS.txt without the rows
	local points = {}
	for i = 0, Map.Spawns.count - 1 do
		local s = Map.Spawns[i]
		if s.Kind == const.ObjectRefKind.Monster then points[#points + 1] = s end
	end
	for _ = 1, math.min(math.random(BANDS[1], BANDS[2]), #points) do
		local s = table.remove(points, math.random(#points))
		for _ = 1, math.random(BAND_SIZE[1], BAND_SIZE[2]) do
			local ok, m = pcall(SummonMonster, pickTroll(),
				s.X + math.random(-SPREAD, SPREAD), s.Y + math.random(-SPREAD, SPREAD), s.Z, true)
			if ok and m then
				pcall(m.LoadFramesAndSounds, m)
				m.Hostile = true
				pcall(function() m.ShowAsHostile = true end)
			end
		end
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(spawnTrolls)
	if not ok and Merge.Functions.LogWarning then
		Merge.Functions.LogWarning("7d21 small trolls: " .. tostring(err))
	end
end
