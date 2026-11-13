--[[
	MMMWE_SiegeOfHarmondale.lua — the war of the alliance against the Forge (13.11.26)

	The Dark path's war, after Armageddon's Blade as it was first planned: AvLee and Erathia,
	with the wizards of Bracada and the angels of Celeste, march on Kastore's Lords of
	Harmondale.

	  Start      one to two months after the Forge reads Padish's Signet (QBit 876): a messenger
	             from Castle Gloaming warns the party; the first wave comes a few days later.
	  Waves      every three weeks for a year (Settings.Waves), each larger and with stronger
	             troops; the last is the final siege. An army arrives at Castle Harmondale (the
	             Harmondale map) and the party has a week (Settings.TimeLimit) to destroy it.
	             Troops of the Dark side come to defend the castle alongside the party.
	  Score      a wave destroyed in time: a point for the Dark side, three for the final
	             siege; a wave not destroyed in time: the same for the alliance (it withdraws).
	  The end    the Dark side loses if the final siege isn't destroyed in time, or if the
	             alliance has more points at the end; otherwise it wins.
	  Patrols    while the war goes on, small alliance war parties may meet the party on the
	             other lands of Antagarich, and on the Dark side's lands Dark patrols fight them.
	Only MM7 monsters take part (MONSTERS.txt lines A/B/C: base id, +1, +2).

	Kastore's topic "The War" (Global/MMMWE_ForgeQuests.lua) and the quest log (quest bit
	879) show the score. State: vars.MMMWE_Siege.
--]]

local MF = Merge.Functions
local Tx = MF.Text
local floor, min, max, random = math.floor, math.min, math.max, math.random

local S = {
	StartMin = 30, StartMax = 60,        -- days after the Signet
	FirstWaveAfter = 3,                  -- days from the messenger to the first wave
	Waves = 16,                          -- the last one is the final siege
	Interval = 21,                       -- days between waves
	TimeLimit = 7,                       -- days to destroy a wave
	Points = 1, FinalPoints = 3,
	CountBase = 8, CountPerWave = 2, CountMax = 30, FinalCount = 45,
	Kinds = 6,                           -- alliance kinds per wave
	DarkKinds = 3, DarkShare = 0.5,      -- defenders: kinds, and their number against the wave
	LateKindsFrom = 0.5,                 -- share of the war after which golems, genies, angels come
	Radius = {1500, 6000},               -- where the troops gather, from the castle
	PatrolChance = 25, PatrolEvery = 7,  -- % on entering a land, at most once in so many days
	PatrolCount = {3, 6},
	VictoryExp = 100000, VictoryGold = 50000,
}
MF.SiegeSettings = S

local SIGNET_DONE = 876
local WAR_QUEST   = 879                  -- quest log line of the war
local DARK_PATH   = 612
local HARMONDALE  = "7out02.odm"
local ALLIANCE_GROUP, DARK_GROUP, PATROL_GROUP = 200, 201, 202

-- MM7 monsters: the A line of each (B = +1, C = +2)
local ALLIANCE = {
	250,   -- Elven Warrior, Defender, Lancer
	253,   -- Conscript, Soldier, Fighter
	256,   -- Robber, Raider, Bandit
	202,   -- Archer, Bowman, Elite Archer
	247,   -- Elven Archer, Scout, Ranger
	403,   -- Swordsman, Guard, Adventurer
	259,   -- Initiate, Champion, Master of the Sword
	304,   -- Monk, Initiate, Master
	217,   -- Acolyte, Cleric, Priest of the Sun
	280,   -- Griffins
	229,   -- Dwarven Soldier, Lieutenant, Commander
	451,   -- Treants
	292,   -- Sorcerer, Wizard, Archmage
}
local ALLIANCE_LATE = {
	277,   -- Golems
	265,   -- Djinni, Genie (the C line is the Efreet: not used)
	199,   -- Angel, Angel Lord, Archangel
}
local NO_C = {[265] = true}
local DARK = {
	271,   -- Goblins
	397,   -- Skeletons
	427,   -- Zombies
	268,   -- Ghosts
	415,   -- Vampires
	307,   -- Necromancers
	289,   -- Liches
	301,   -- Minotaurs
	208,   -- Behemoths
	238,   -- Fire Elementals
	388,   -- Droids
	459,   -- Blaster Guy (one line only: A and B are named NPCs)
}
local SINGLE = {[459] = true}

-- lands of the war (MapStats names), and which of them are the Dark side's
local LANDS = {["erathia"] = "light", ["the tularean forest"] = "light", ["the bracada desert"] = "light",
	["avlee"] = "light", ["deyja"] = "dark", ["mount nighon"] = "dark", ["tatalia"] = "light",
	["the barrow downs"] = "light"}

local TEXT = {
	Messenger = Tx"A rider in the black of Castle Gloaming reins in beside you, his horse lathered.\n\n\"Word from Kastore, my lords! The elves of AvLee and the knights of Erathia have made common cause. Bracada's wizards ride with them, and there are angels from Celeste in the sky over their camps. Their army is marching on Harmondale!\n\nThe Forge is sending what it can, but the castle is yours to hold. Every army they send must be broken - and quickly, before the next one comes.\"",
	Arrived = Tx"The alliance's army has reached Castle Harmondale! (wave %d of %d, %d days to destroy it)",
	FinalArrived = Tx"The final siege: the whole alliance stands before Castle Harmondale! (%d days to destroy it)",
	Cleared = Tx"The alliance's army at Harmondale is destroyed! Score: Dark side %d, alliance %d",
	Lost = Tx"Too late: the alliance's army withdrew from Harmondale on its own terms. Score: Dark side %d, alliance %d",
	Victory = Tx"The alliance is broken!\n\nTheir last army lies in ruins before Castle Harmondale, and the survivors flee back to Erathia and AvLee. Kastore's laughter rings through the halls of Castle Gloaming: the Forge, and Harmondale, are safe - and the Dark side holds Antagarich's heart.\n\nFinal score: Dark side %d, alliance %d.",
	Defeat = Tx"Harmondale has fallen.\n\nThe alliance's banners fly over the castle, and Erathia and AvLee celebrate a victory that will be sung of for years. The war is lost.\n\nFinal score: Dark side %d, alliance %d.",
	Journal = Tx"The war for Harmondale: Dark side %d, alliance %d. Wave %d of %d.%s",
	JournalNext = Tx" The next army is expected in %d days.",
	JournalNow = Tx" An army stands at Castle Harmondale: %d days left to destroy it.",
	Patrol = Tx"A war party of the alliance!",
	Topic = Tx"The War",
	TopicWar = Tx"Every army they send is weaker than the last one they lost - or so I tell my officers. Keep Harmondale, and keep it fast: an army left standing for a week is a victory they will boast of.\n\n%s",
	TopicWon = Tx"We won. The alliance will lick its wounds for a generation. Final score: Dark side %d, alliance %d.",
	TopicLost = Tx"Harmondale is lost, and the Forge with it soon enough, if they press on. Final score: Dark side %d, alliance %d.",
}

-- Kastore's topic (Global/MMMWE_ForgeQuests.lua)
function MF.SiegeTopicText()
	local s = vars and vars.MMMWE_Siege
	if not (s and s.Announced) then return end
	if s.Over == "victory" then return string.format(TEXT.TopicWon, s.Score.Dark, s.Score.Alliance) end
	if s.Over == "defeat" then return string.format(TEXT.TopicLost, s.Score.Dark, s.Score.Alliance) end
	return string.format(TEXT.TopicWar, MF.SiegeStatus() or "")
end
MF.SiegeTexts = TEXT

local function state()
	vars.MMMWE_Siege = vars.MMMWE_Siege or {Score = {Dark = 0, Alliance = 0}, Wave = 0}
	return vars.MMMWE_Siege
end
local function days(n) return floor(n * const.Day) end
local function daysLeft(t) return max(0, math.ceil((t - Game.Time) / const.Day)) end

local function warOn(s)
	return s.Announced and not s.Over
end

---------------------------------------------------------------------------
-- the score in the quest log and for Kastore's topic
---------------------------------------------------------------------------

function MF.SiegeStatus()
	local s = vars and vars.MMMWE_Siege
	if not (s and s.Announced) then return end
	local tail = ""
	if s.Active and s.Active.Arrived and not s.Active.Done then
		tail = string.format(TEXT.JournalNow, daysLeft(s.Active.Deadline))
	elseif s.Active and not s.Active.Arrived then
		tail = string.format(TEXT.JournalNext, daysLeft(s.Active.Arrive))
	end
	return string.format(TEXT.Journal, s.Score.Dark, s.Score.Alliance, max(1, s.Wave), S.Waves, tail), s
end

local function updateJournal()
	local text = MF.SiegeStatus()
	if text then
		Game.QuestsTxt[WAR_QUEST] = text
		Party.QBits[WAR_QUEST] = not state().Over
	end
end

---------------------------------------------------------------------------
-- placing troops
---------------------------------------------------------------------------

-- Castle Harmondale: the model whose face opens the castle (event 301 of 7out02)
local function castleCenter()
	for _, m in Map.Models do
		for _, f in m.Facets do
			if f.Event == 301 then
				return floor((m.MinX + m.MaxX) / 2), floor((m.MinY + m.MaxY) / 2)
			end
		end
	end
end

-- points on the ground between r1 and r2 from (cx, cy): the map's spawn points first
local function points(cx, cy, r1, r2)
	local list = {}
	for _, sp in Map.Spawns do
		local dx, dy = sp.X - cx, sp.Y - cy
		local d = math.sqrt(dx * dx + dy * dy)
		if d >= r1 and d <= r2 then list[#list + 1] = {sp.X, sp.Y, sp.Z} end
	end
	if #list < 4 then
		for i = 1, 12 do
			local a, r = random() * 2 * math.pi, r1 + random() * (r2 - r1)
			local x, y = floor(cx + r * math.cos(a)), floor(cy + r * math.sin(a))
			local ok, z = pcall(Map.GetGroundLevel, x, y)
			if ok and z then list[#list + 1] = {x, y, z} end
		end
	end
	return list
end

local function tierFor(progress, final)
	if final then return 2 end
	return max(0, min(2, floor(progress * 3 + random() - 0.5)))
end

local function idOf(base, tier)
	if SINGLE[base] then return base end
	if NO_C[base] and tier == 2 then tier = 1 end
	return base + tier
end

local function pickKinds(list, n)
	local pool, out = {}, {}
	for _, v in ipairs(list) do pool[#pool + 1] = v end
	for _ = 1, min(n, #pool) do
		out[#out + 1] = table.remove(pool, random(#pool))
	end
	return out
end

local function spawnOne(id, p, group, side)
	local ok, m = pcall(SummonMonster, id, p[1] + random(-150, 150), p[2] + random(-150, 150), p[3], false)
	if not ok or not m then return end
	pcall(m.LoadFramesAndSounds, m)
	m.Group = group
	if side == "dark" then
		m.Ally = 9999
		m.Hostile = false
		pcall(function() m.ShowAsHostile = false end)
	else
		m.Hostile = true
	end
	return m
end

-- n troops of the given kinds around the points, spread over them
local function spawnArmy(kinds, n, progress, final, pts, group, side)
	if #pts == 0 or #kinds == 0 then return 0 end
	local done = 0
	for i = 1, n do
		local base = kinds[(i - 1) % #kinds + 1]
		local p = pts[(i - 1) % #pts + 1]
		if spawnOne(idOf(base, tierFor(progress, final)), p, group, side) then done = done + 1 end
	end
	return done
end

local function countGroup(group, aliveOnly)
	local n = 0
	for _, m in Map.Monsters do
		if m.Group == group and m.AIState ~= const.AIState.Removed
				and (not aliveOnly or (m.HP > 0 and m.AIState ~= const.AIState.Dead and m.AIState ~= const.AIState.Dying)) then
			n = n + 1
		end
	end
	return n
end

local function removeGroup(group)
	for _, m in Map.Monsters do
		if m.Group == group and m.HP > 0 then m.AIState = const.AIState.Removed end
	end
end

---------------------------------------------------------------------------
-- the waves
---------------------------------------------------------------------------

local function newWave(s, arrive)
	s.Wave = s.Wave + 1
	local final = s.Wave >= S.Waves
	local progress = (s.Wave - 1) / max(1, S.Waves - 1)
	local count = final and S.FinalCount or min(S.CountMax, S.CountBase + S.CountPerWave * (s.Wave - 1))
	local list = {}
	for _, v in ipairs(ALLIANCE) do list[#list + 1] = v end
	if progress >= S.LateKindsFrom or final then
		for _, v in ipairs(ALLIANCE_LATE) do list[#list + 1] = v end
	end
	s.Active = {N = s.Wave, Final = final, Arrive = arrive, Count = count, Remaining = count,
		Progress = progress, Kinds = pickKinds(list, S.Kinds), Dark = pickKinds(DARK, S.DarkKinds)}
end

local function finish(s)
	local lostFinal = s.FinalLost
	if lostFinal or s.Score.Alliance > s.Score.Dark then
		s.Over = "defeat"
		Message(string.format(TEXT.Defeat, s.Score.Dark, s.Score.Alliance))
	else
		s.Over = "victory"
		Message(string.format(TEXT.Victory, s.Score.Dark, s.Score.Alliance))
		for _, pl in Party do pl.Exp = pl.Exp + S.VictoryExp end
		evt.Add("Gold", S.VictoryGold)
	end
	Party.QBits[WAR_QUEST] = false
	if MF.SiegeEnded then pcall(MF.SiegeEnded, s.Over) end
end

local function resolve(s, cleared)
	local a = s.Active
	local pts = a.Final and S.FinalPoints or S.Points
	a.Done = true
	if cleared then
		s.Score.Dark = s.Score.Dark + pts
		Game.ShowStatusText(string.format(TEXT.Cleared, s.Score.Dark, s.Score.Alliance), 6)
	else
		s.Score.Alliance = s.Score.Alliance + pts
		if a.Final then s.FinalLost = true end
		Game.ShowStatusText(string.format(TEXT.Lost, s.Score.Dark, s.Score.Alliance), 6)
		if (Map.Name or ""):lower() == HARMONDALE then removeGroup(ALLIANCE_GROUP) end
	end
	if a.Final then
		finish(s)
	else
		newWave(s, a.Arrive + days(S.Interval))
	end
	updateJournal()
end

-- the wave's army on the Harmondale map: placed once per wave and map fill (mapvars are
-- cleared by a refill, which also takes the troops away: the ones still alive come back)
local function placeWave(s)
	local a = s.Active
	if not (a and a.Arrived and not a.Done) then return end
	if (Map.Name or ""):lower() ~= HARMONDALE then return end
	if mapvars.MMMWE_SiegeWave == a.N then return end
	removeGroup(ALLIANCE_GROUP)                     -- what is left of an older wave
	local cx, cy = castleCenter()
	if not cx then cx, cy = Party.X, Party.Y end
	local pts = points(cx, cy, S.Radius[1], S.Radius[2])
	local n = spawnArmy(a.Kinds, a.Remaining, a.Progress, a.Final, pts, ALLIANCE_GROUP, "alliance")
	if countGroup(DARK_GROUP, true) == 0 then
		local d = max(1, floor(a.Remaining * S.DarkShare))
		spawnArmy(a.Dark, d, a.Progress, a.Final, points(cx, cy, 300, S.Radius[1]), DARK_GROUP, "dark")
	end
	mapvars.MMMWE_SiegeWave = a.N
	a.Remaining = n
	MF.LogInfo("[Siege] wave %d: %d alliance troops placed", a.N, n)
	if n == 0 then resolve(s, true) end
end

function events.MonsterKilled(mon)
	if mon.Group ~= ALLIANCE_GROUP or (Map.Name or ""):lower() ~= HARMONDALE then return end
	local s = vars.MMMWE_Siege
	local a = s and s.Active
	if not (a and a.Arrived and not a.Done) then return end
	-- the troops still standing, without the one just killed
	local n, ptr = 0, mon["?ptr"]
	for _, m in Map.Monsters do
		if m.Group == ALLIANCE_GROUP and m["?ptr"] ~= ptr and m.HP > 0 and m.AIState ~= const.AIState.Removed
				and m.AIState ~= const.AIState.Dead and m.AIState ~= const.AIState.Dying then
			n = n + 1
		end
	end
	a.Remaining = n
	if n == 0 then resolve(s, true) end
end

---------------------------------------------------------------------------
-- war parties on the other lands
---------------------------------------------------------------------------

local function patrol(s)
	local ms = Game.MapStats[Map.MapStatsIndex]
	local land = ms and LANDS[(ms.Name or ""):lower()]
	if not land then return end
	s.Patrols = s.Patrols or {}
	local last = s.Patrols[Map.Name]
	if last and Game.Time - last < days(S.PatrolEvery) then return end
	s.Patrols[Map.Name] = Game.Time
	if random(100) > S.PatrolChance then return end
	local pts = points(Party.X, Party.Y, 2000, 4500)
	if #pts == 0 then return end
	local progress = s.Active and s.Active.Progress or 0
	local n = random(S.PatrolCount[1], S.PatrolCount[2])
	local p = {pts[random(#pts)]}
	spawnArmy(pickKinds(ALLIANCE, 2), n, progress, false, p, PATROL_GROUP, "alliance")
	if land == "dark" then
		spawnArmy(pickKinds(DARK, 2), n, progress, false, p, PATROL_GROUP + 1, "dark")
	end
	Game.ShowStatusText(TEXT.Patrol, 4)
end

---------------------------------------------------------------------------
-- time
---------------------------------------------------------------------------

local lastCheck = 0
function events.Tick()
	if not vars or not Party.QBits[SIGNET_DONE] or not Party.QBits[DARK_PATH] then return end
	if Game.Time - lastCheck < const.Minute * 10 and Game.Time >= lastCheck then return end
	lastCheck = Game.Time
	local s = state()
	if s.Over then return end
	if not s.Start then
		s.Start = Game.Time + days(random(S.StartMin, S.StartMax))
		return
	end
	if not s.Announced then
		if Game.Time >= s.Start and Game.CurrentScreen == 0 and not Party.EnemyDetectorRed then
			s.Announced = true
			newWave(s, Game.Time + days(S.FirstWaveAfter))
			Message(TEXT.Messenger)
			updateJournal()
		end
		return
	end
	local a = s.Active
	if not a then return end
	if not a.Arrived and Game.Time >= a.Arrive then
		a.Arrived = true
		a.Deadline = a.Arrive + days(S.TimeLimit)
		if a.Final then
			Game.ShowStatusText(string.format(TEXT.FinalArrived, S.TimeLimit), 8)
		else
			Game.ShowStatusText(string.format(TEXT.Arrived, a.N, S.Waves, S.TimeLimit), 8)
		end
		placeWave(s)
		updateJournal()
	elseif a.Arrived and not a.Done and Game.Time > a.Deadline then
		resolve(s, false)
	end
end

function events.AfterLoadMap()
	if not (vars and vars.MMMWE_Siege) then return end
	local s = vars.MMMWE_Siege
	updateJournal()
	if not warOn(s) then
		-- after the war: what is left of the armies leaves Harmondale
		if s.Over and (Map.Name or ""):lower() == HARMONDALE then
			removeGroup(ALLIANCE_GROUP)
		end
		return
	end
	if (Map.Name or ""):lower() == HARMONDALE then
		local a = s.Active
		-- no army due now: the troops of a wave that withdrew are gone
		if not (a and a.Arrived and not a.Done) then removeGroup(ALLIANCE_GROUP) end
		placeWave(s)
	else
		patrol(s)
	end
end
