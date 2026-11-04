-- Deyja

function events.LoadMap()
	
end
function events.AfterLoadMap()
	Party.QBits[820] = true	-- DDMapBuff
	
	LocalHostileTxt()
	Game.HostileTxt[91][0] = 0
	if Party.QBits[633] then
		function events.SetOutdoorLight(t)
			t.Hour, t.Minute = 5, 0
		end
		SetSkyTexture("sky007")
		Game.Weather.SetFog(100,1024)
		Map.OutdoorExtra.AlwaysFoggy = true
		-- music after this quest: MMMWE_Music.lua (Music.QuestMusic)
		Game.HostileTxt[153][0] = 0
		Game.HostileTxt[130] = Game.HostileTxt[153]
		for i,v in Map.Monsters do
			if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
				if v.Id == 272 then
					v:ChangeLook(459)
					v:SetId(459)
					v.Attack1.Type = 12
					v.Attack1.Missile = 13
					v.Attack2.Type = 12
					v.Attack2.Missile = 13
					v.FullHP = 880
					v.HP = v.FullHP
					v.Level = 100
					v.Bonus = 16
				end
			end
		end
	end
	evt.SetMonGroupBit {56,  const.MonsterBits.Hostile,  true}
	evt.SetMonGroupBit {55,  const.MonsterBits.Hostile,  Party.QBits[611]}
end

function events.ExitNPC(i)
	if i == 461 and not Party.QBits[761] then
		evt.SummonMonsters{3, 3, 5, Party.X, Party.Y, Party.Z + 400, 59}
		evt.SetMonGroupBit{59, const.MonsterBits.Hostile, true}
	end
end

evt.HouseDoor(17, 494)  -- "Ship"
evt.house[18] = 494  -- "Ship"

evt.hint[457] = evt.str[100]  -- ""
evt.map[457] = function()
	if not evt.Cmp{"MapVar29", Value = 5} then
		if evt.Cmp{"QBits", Value = 761} then         -- Don't get ambushed
			evt.Set{"MapVar29", Value = 5}
		else
			evt.Add{"QBits", Value = 761}         -- Don't get ambushed
			evt.SummonMonsters{TypeIndexInMapStats = 3, Level = 1, Count = 10, X = 1310, Y = 4720, Z = 3853, NPCGroup = 66, unk = 0}         -- ""
			evt.SummonMonsters{TypeIndexInMapStats = 3, Level = 1, Count = 10, X = 1310, Y = -7800, Z = 3853, NPCGroup = 66, unk = 0}         -- ""
			evt.SetMonGroupBit{NPCGroup = 66, Bit = const.MonsterBits.Hostile, On = true}         -- ""
			evt.Set{"MapVar29", Value = 5}
		end
	end
	evt.SetNPCTopic{NPC = 461, Index = 0, Event = 513}         -- "Lunius Shador" : "Pay 1000 Gold"
	evt.SetNPCTopic{NPC = 461, Index = 1, Event = 514}         -- "Lunius Shador" : "Don't Pay"
end

evt.hint[458] = evt.str[100]  -- ""
evt.map[458] = function()
	if not evt.Cmp{"MapVar29", Value = 5} then
		if evt.Cmp{"QBits", Value = 761} then         -- Don't get ambushed
			evt.Set{"MapVar29", Value = 5}
		else
			evt.Add{"QBits", Value = 761}         -- Don't get ambushed
			evt.SummonMonsters{TypeIndexInMapStats = 3, Level = 1, Count = 10, X = 12435, Y = 2180, Z = 3680, NPCGroup = 66, unk = 0}         -- ""
			evt.SummonMonsters{TypeIndexInMapStats = 3, Level = 1, Count = 10, X = 12435, Y = -5030, Z = 3680, NPCGroup = 66, unk = 0}         -- ""
			evt.SetMonGroupBit{NPCGroup = 66, Bit = const.MonsterBits.Hostile, On = true}         -- ""
			evt.Set{"MapVar29", Value = 5}
		end
	end
	evt.SetNPCTopic{NPC = 461, Index = 0, Event = 513}         -- "Lunius Shador" : "Pay 1000 Gold"
	evt.SetNPCTopic{NPC = 461, Index = 1, Event = 514}         -- "Lunius Shador" : "Don't Pay"
end


