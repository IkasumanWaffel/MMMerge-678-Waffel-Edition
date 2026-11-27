--[[
	MMMWE_MonsterAttacks.lua - second attacks by combat style (27.11.26)

	Data/Tables/Monster attacks.txt lists the monsters whose second attack (Attack2 of
	MONSTERS.txt) is set or replaced: Id, Name, Action (new / replace / remove), Type, the damage
	dice (count, sides, add), Missile ("melee" for none) and Chance (%). The list was drawn up by
	combat style (Data/Tables/Bolster - monsters.txt) and reviewed by hand; monsters not in it keep
	their second attack. Tools/monster_attacks_proposal.py made the first draft.

	The damage types and missiles are named as in MONSTERS.txt. Their numbers are read from the
	monsters that already use them (TYPE_REF, MISSILE_REF: {id, attack}), so the table needs no
	codes of its own.

	Action "attack1" sets the first attack instead (Chance unused): the dark dwarves shoot their
	crossbows first and fight in melee second (27.11.26).

	Flaming arrows (ArrowF) deal Fire damage: every attack that shoots one is made Fire.

	Game.MonstersTxt is changed once the game data is loaded. The bolster copies the second attack
	to the map's monsters on each map load (AdaptiveMonstersStats.lua, PrepareMapMon). With the
	bolster off, a map's monsters get it once (mapvars.MMMWE_MonsterAttacks).
--]]

local MF = Merge.Functions
local LogId = "MonsterAttacks"

local TYPE_REF = {
	["Air"] = {{16,1}, {72,1}, {82,1}, {83,1}, {84,1}},
	["Body"] = {{53,2}, {295,1}, {296,1}, {297,1}, {305,2}},
	["Dark"] = {{55,1}, {56,1}, {57,1}, {163,1}, {164,1}},
	["Earth"] = {{16,2}, {17,2}, {18,2}, {79,1}, {80,1}},
	["Ener"] = {{112,1}, {112,2}, {113,1}, {113,2}, {114,1}},
	["Fire"] = {{7,2}, {18,1}, {46,1}, {47,1}, {70,1}},
	["Light"] = {{48,1}, {97,1}, {98,1}, {99,1}, {199,1}},
	["Mind"] = {{52,2}, {211,2}, {212,2}, {213,2}, {306,2}},
	["Phys"] = {{1,1}, {2,1}, {3,1}, {4,1}, {4,2}},
	["Spirit"] = {{54,2}, {268,2}, {269,2}, {270,2}, {283,2}},
	["Water"] = {{8,2}, {17,1}, {71,1}, {76,1}, {77,1}},
}
local MISSILE_REF = {
	["Air"] = {{16,1}, {108,2}, {111,1}, {148,2}, {149,2}},
	["Arrow"] = {{4,2}, {5,2}, {6,2}, {172,1}, {173,1}},
	["ArrowF"] = {{13,2}, {14,2}, {15,2}, {100,1}, {101,1}},
	["Body"] = {{295,1}, {296,1}, {297,1}, {490,2}, {491,2}},
	["Dark"] = {{55,1}, {56,1}, {57,1}, {163,1}, {164,1}},
	["Earth"] = {{16,2}, {17,2}, {18,2}, {235,1}, {236,1}},
	["Ener"] = {{112,1}, {112,2}, {113,1}, {113,2}, {114,1}},
	["Fire"] = {{7,2}, {18,1}, {46,1}, {47,1}, {70,1}},
	["FireAr"] = {{172,2}, {173,2}, {174,2}, {202,2}, {203,2}},
	["Light"] = {{48,1}, {97,1}, {98,1}, {99,1}, {199,1}},
	["Mind"] = {{211,2}, {212,2}, {213,2}, {584,2}},
	["Rock"] = {{142,2}, {143,2}, {144,2}, {412,2}, {413,2}},
	["Spirit"] = {{283,2}, {284,2}, {285,2}, {556,2}, {557,2}},
	["Water"] = {{8,2}, {17,1}, {107,2}, {109,1}, {155,2}},
}

local function warn(fmt, ...)
	if MF.LogWarning then MF.LogWarning("monster attacks: " .. fmt, ...) end
end

local function attack(mon, slot)
	return slot == 1 and mon.Attack1 or mon.Attack2
end

-- the number the game uses for each name: what most of its reference monsters hold
local function codes(refs, field)
	local out = {}
	for name, list in pairs(refs) do
		local votes, best, bestN = {}, nil, 0
		for _, r in ipairs(list) do
			local m = Game.MonstersTxt[r[1]]
			if m then
				local v = attack(m, r[2])[field]
				votes[v] = (votes[v] or 0) + 1
				if votes[v] > bestN then best, bestN = v, votes[v] end
			end
		end
		out[name] = best
	end
	return out
end

local Changed = {}          -- MONSTERS.txt id -> true, for the maps' monsters
local First = {}            -- MONSTERS.txt id -> true: Attack1 changed (type and missile, which the bolster leaves)
local ArrowF, FireType

local function readTable()
	local f = io.open("Data/Tables/Monster attacks.txt", "r")
	if not f then
		warn("Data/Tables/Monster attacks.txt not found")
		return {}
	end
	local rows = {}
	local first = true
	for line in f:lines() do
		if first then
			first = false
		elseif line:match("%S") then
			local c = line:split("\t")
			rows[#rows + 1] = {
				Id = tonumber(c[1]), Name = c[2], Action = c[3], Type = c[4],
				Count = tonumber(c[5]) or 0, Sides = tonumber(c[6]) or 0, Add = tonumber(c[7]) or 0,
				Missile = c[8], Chance = tonumber(c[9]) or 0,
			}
		end
	end
	f:close()
	return rows
end

local function apply()
	local Types = codes(TYPE_REF, "Type")
	local Missiles = codes(MISSILE_REF, "Missile")
	Missiles.melee = 0
	ArrowF, FireType = Missiles.ArrowF, Types.Fire

	local count, last = 0, Game.MonstersTxt.count - 1
	for _, r in ipairs(readTable()) do
		local m = r.Id and r.Id <= last and Game.MonstersTxt[r.Id]
		local ty, mi = Types[r.Type], Missiles[r.Missile]
		if not m then
			warn("no monster %s (%s)", tostring(r.Id), tostring(r.Name))
		elseif r.Action == "remove" then
			m.Attack2Chance = 0
			Changed[r.Id] = true
			count = count + 1
		elseif r.Action == "attack1" then
			if not ty or not mi then
				warn("%d %s: unknown type %s or missile %s", r.Id, r.Name, tostring(r.Type), tostring(r.Missile))
			else
				local a = m.Attack1
				a.Type = ty
				a.Missile = mi
				a.DamageDiceCount = math.min(r.Count, 255)
				a.DamageDiceSides = math.min(r.Sides, 255)
				a.DamageAdd = math.min(r.Add, 255)
				First[r.Id] = true
			end
		elseif r.Action == "new" or r.Action == "replace" then
			if not ty or not mi then
				warn("%d %s: unknown type %s or missile %s", r.Id, r.Name, tostring(r.Type), tostring(r.Missile))
			else
				local a = m.Attack2
				a.Type = ty
				a.Missile = mi
				a.DamageDiceCount = math.min(r.Count, 255)
				a.DamageDiceSides = math.min(r.Sides, 255)
				a.DamageAdd = math.min(r.Add, 255)
				m.Attack2Chance = math.min(r.Chance, 100)
				Changed[r.Id] = true
				count = count + 1
			end
		end
	end
	for id in pairs(First) do Changed[id] = true end

	-- flaming arrows burn
	local burning = 0
	if ArrowF and FireType then
		for i = 1, last do
			local m = Game.MonstersTxt[i]
			for slot = 1, 2 do
				local a = attack(m, slot)
				if a.Missile == ArrowF and a.Type ~= FireType then
					a.Type = FireType
					burning = burning + 1
				end
			end
		end
	end
	if MF.LogInfo then MF.LogInfo("monster attacks: %d second attacks set, %d flaming-arrow attacks made Fire", count, burning) end
end

function events.GameInitialized2()
	local ok, err = pcall(apply)
	if not ok then warn("%s", tostring(err)) end
end

-- the monsters already on a map
local function onMap()
	if ArrowF and FireType then
		for i, mon in Map.Monsters do
			for slot = 1, 2 do
				local a = attack(mon, slot)
				if a.Missile == ArrowF then a.Type = FireType end
			end
		end
	end
	for i, mon in Map.Monsters do
		if First[mon.Id] then
			local a = Game.MonstersTxt[mon.Id].Attack1
			mon.Attack1.Type = a.Type
			mon.Attack1.Missile = a.Missile
		end
	end
	if Game.UseMonsterBolster or mapvars.MMMWE_MonsterAttacks then return end
	mapvars.MMMWE_MonsterAttacks = true
	for i, mon in Map.Monsters do
		if Changed[mon.Id] then
			local src = Game.MonstersTxt[mon.Id]
			if First[mon.Id] then
				mon.Attack1.DamageDiceCount = src.Attack1.DamageDiceCount
				mon.Attack1.DamageDiceSides = src.Attack1.DamageDiceSides
				mon.Attack1.DamageAdd = src.Attack1.DamageAdd
			end
			mon.Attack2Chance = src.Attack2Chance
			mon.Attack2.Type = src.Attack2.Type
			mon.Attack2.Missile = src.Attack2.Missile
			mon.Attack2.DamageDiceCount = src.Attack2.DamageDiceCount
			mon.Attack2.DamageDiceSides = src.Attack2.DamageDiceSides
			mon.Attack2.DamageAdd = src.Attack2.DamageAdd
		end
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(onMap)
	if not ok then warn("%s", tostring(err)) end
end

MF.MonsterAttacksChanged = Changed
