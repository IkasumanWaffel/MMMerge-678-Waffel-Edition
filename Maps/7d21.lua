-- White Cliff Cave
-- (MMMWE 25.11.26) small trolls (MM7's small troll sprites m461, which the Swamp Troll only shows enlarged; monsters 655-657: Troll Runt,
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

local function warn(fmt, ...)
	local MF = Merge.Functions
	if MF.LogWarning then MF.LogWarning("7d21 small trolls: " .. fmt, ...) end
end

local function spawnTrolls()
	if mapvars.MMMWE_SmallTrolls then return end
	local txt = Game.MonstersTxt
	if txt.count <= TROLLS[3] then
		-- MONSTERS.txt in revamp.T.lod doesn't have the rows yet: try again on the next load
		warn("monster %d is missing from MONSTERS.txt (count %d)", TROLLS[1], txt.count)
		return
	end
	local points = {}
	for i = 0, Map.Spawns.count - 1 do
		local s = Map.Spawns[i]
		if s.Kind == const.ObjectRefKind.Monster then points[#points + 1] = s end
	end
	if #points == 0 then
		-- no monster spawn points: around the monsters of the map instead
		for i = 0, Map.Monsters.count - 1 do
			local m = Map.Monsters[i]
			if m.HP > 0 and m.AIState ~= const.AIState.Removed then points[#points + 1] = m end
		end
	end
	local sent = 0
	for _ = 1, math.min(math.random(BANDS[1], BANDS[2]), #points) do
		local s = table.remove(points, math.random(#points))
		local x, y, z = s.X, s.Y, s.Z
		for _ = 1, math.random(BAND_SIZE[1], BAND_SIZE[2]) do
			local ok, m = pcall(SummonMonster, pickTroll(),
				x + math.random(-SPREAD, SPREAD), y + math.random(-SPREAD, SPREAD), z, true)
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
		warn("none placed (%d spawn points)", #points)
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(spawnTrolls)
	if not ok and Merge.Functions.LogWarning then
		Merge.Functions.LogWarning("7d21 small trolls: " .. tostring(err))
	end
end
