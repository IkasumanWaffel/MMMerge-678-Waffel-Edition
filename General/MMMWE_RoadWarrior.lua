--[[
	MMMWE_RoadWarrior.lua (17.11.26): the Leathers of the Road Warrior (2259), an easter egg.
	Their stats are in Global\ExtraArtifacts.lua. Here:
	  - physical damage taken by the wearer is cut by PHYS_CUT
	  - once a game, the first visit to the Tomb of VARN (pyramid.blv) puts them in one of its
	    chests, picked at random among those the game hasn't filled yet
]]

local LEATHERS, PHYS_CUT, MAP = 2259, 0.10, "pyramid.blv"
local MF = Merge.Functions

local function wears(pl)
	local idx = pl and pl.ItemArmor
	if not idx or idx <= 0 then return false end
	local it = pl.Items[idx]
	return it.Number == LEATHERS and not it.Broken
end
MF.WearsRoadWarrior = wears

-- registered on the first map load, after the other damage handlers (as MMMWE_Resources.lua does)
local registered = false
local function register()
	if registered then return end
	registered = true
	function events.CalcDamageToPlayer(t)
		if (t.Result or 0) > 0 and t.DamageKind == const.Damage.Phys and wears(t.Player) then
			t.Result = math.max(1, math.floor(t.Result * (1 - PHYS_CUT) + 0.5))
		end
	end
end

local function placeInTomb()
	if string.lower(Map.Name or "") ~= MAP then return end
	vars.MMMWE_RoadWarrior = vars.MMMWE_RoadWarrior or {}
	if vars.MMMWE_RoadWarrior.Placed then return end
	local free = {}
	for i = 0, Map.Chests.count - 1 do
		if bit.band(Map.Chests[i].Bits, const.ChestBits.ItemsPlaced) == 0 then free[#free + 1] = i end
	end
	if #free == 0 then return end           -- every chest already filled: try again on a new game
	local id = free[math.random(#free)]
	local chest = Map.Chests[id]
	for k = 1, 140 do
		local it = chest.Items[k]
		if it.Number == 0 then
			it:Clear()
			it.Number = LEATHERS
			it.Identified = false
			vars.MMMWE_RoadWarrior.Placed = true
			MF.LogInfo("[RoadWarrior] leathers put into chest %d of the Tomb of VARN", id)
			return
		end
	end
end

function events.AfterLoadMap()
	register()
	local ok, err = pcall(placeInTomb)
	if not ok then MF.LogWarning("[RoadWarrior] %s", tostring(err)) end
end
