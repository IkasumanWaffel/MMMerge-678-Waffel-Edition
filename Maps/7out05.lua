-- Deyja

function events.LoadMap()
	if Party.QBits[633] then
		function events.SetOutdoorLight(t)
			t.Hour, t.Minute = 5, 0
		end
	end
end
function events.AfterLoadMap()
	Party.QBits[820] = true	-- DDMapBuff

	LocalHostileTxt()
	Game.HostileTxt[91][0] = 0
	if Party.QBits[633] then
		SetSkyTexture("sky007")
		Game.Weather.SetFog(100,8192)
		Game.PlayTrack(math.random(58,124,125))
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


