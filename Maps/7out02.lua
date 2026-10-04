-- Harmondale
local MF = Merge.Functions

function events.AfterLoadMap()
	Party.QBits[817] = true	-- DDMapBuff
end

-- Choose Judge quest

evt.Map[37] = function()
	NPCFollowers.Remove(416)
	NPCFollowers.Remove(417)
	MF.UISendAlignment()
end

-- Enter castle Harmondale

Game.MapEvtLines:RemoveEvent(301)
evt.Hint = evt.str[30]
evt.Map[301] = function()
	if Party.QBits[519] then
		if Party.QBits[610] or Party.QBits[644] then
			if Party.QBits[610] then
				evt.MoveToMap{-5073, -2842, 1, 512, 0, 0, 382, 9, "7d29.blv"}
			else
				evt.MoveToMap{-5073, -2842, 1, 512, 0, 0, 390, 9, "7d29.blv"}
			end
		else
			Party.QBits[644] = true
			Party.QBits[587] = true

			evt.Add{"History3", 0}
			evt.MoveNPC {397, 240}
			evt.SpeakNPC{397}
		end
	else
		evt.FaceAnimation{Game.CurrentPlayer, const.FaceAnimation.DoorLocked}
	end
end

-- Mercenary guild - invasion

Party.QBits[608] = Party.QBits[611] or Party.QBits[612]

evt.Map[50] = function()
	if (Party.QBits[693] or Party.QBits[694]) and not (Party.QBits[702] or Party.QBits[695]) then
		mapvars.InvasionTime = mapvars.InvasionTime or Game.Time + const.Week*2
		if mapvars.InvasionTime < Game.Time then
			Party.QBits[695] = true
			evt.SetMonGroupBit {60,  const.MonsterBits.Hostile,  true}
			evt.SetMonGroupBit {60,  const.MonsterBits.Invisible, false}
			evt.Set{"BankGold", 0}
			evt.SpeakNPC{437}
		end
	end
end

-- Give "Scavenger hunt" advertisment

local CCTimers = {}

function events.AfterLoadMap()
	if not (mapvars.GotAdvertisment or Party.QBits[519] or evt.All.Cmp{"Inventory", 774}) then

		CCTimers.Catch = function()
			if not (Party.Flying or Party.EnemyDetectorRed or Party.EnemyDetectorYellow)
				and 4000 > math.sqrt((-13115-Party.X)^2 + (12497-Party.Y)^2) then

				mapvars.GotAdvertisment = true
				RemoveTimer(CCTimers.Catch)
				evt.ForPlayer(0).Add{"Inventory", 774}
				evt.SetNPCGreeting(649, 332)
				evt.SpeakNPC{649}

			end
		end
		Timer(CCTimers.Catch, false, const.Minute*3)

	end
end

-- Let judge Grey die unconditionally within 6 months
Game.MapEvtLines:RemoveEvent(211)
function events.LoadMap()
	if Party.QBits[610] then -- have not rebuilt castle yet
		vars.HarmondaleRebuiltDate = vars.HarmondaleRebuiltDate or Game.Time
	else
		return
	end

	if Party.QBits[646] then -- Arbiter Messenger only happens once
		return
	end

	-- if artifact given to anyone, or 6 months passed - kill judge
	if Party.QBits[659] or Party.QBits[596] or Party.QBits[597] or (Game.Time > vars.HarmondaleRebuiltDate + const.Month * 6) then
		evt.SpeakNPC(430)         -- "Messenger"
		evt.Add("QBits", 665)         -- "Choose a judge to succeed Judge Grey as Arbiter in Harmondale."
		evt.Add("History6", 0)
		evt.MoveNPC{NPC = 406, HouseId = 0}         -- "Ellen Rockway"
		evt.MoveNPC{NPC = 407, HouseId = 0}         -- "Alain Hani"
		evt.MoveNPC{NPC = 414, HouseId = 1169}         -- "Ambassador Wright" -> "Throne Room"
		evt.MoveNPC{NPC = 415, HouseId = 1169}         -- "Ambassador Scale" -> "Throne Room"
		evt.MoveNPC{NPC = 416, HouseId = 244}         -- "Judge Fairweather" -> "Familiar Place"
		evt.MoveNPC{NPC = 417, HouseId = 243}         -- "Judge Sleen" -> "The Snobbish Goblin"

		Party.QBits[646] = true
	end
end

function events.AfterLoadMap()
	if evt.CheckSeason{Season = 3} then
		Map.Tilesets[0].Group = 1
		Map.LoadTileset(1)
	else
		Map.Tilesets[0].Group = 0
		Map.LoadTileset(0)
	end
end