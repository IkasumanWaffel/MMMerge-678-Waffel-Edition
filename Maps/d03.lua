
-- Enter Throne Room

Game.MapEvtLines:RemoveEvent(5)
evt.Hint[5] = evt.str[20]
evt.Map[5] = function()
	if Party.QBits[611] or not Party.QBits[612]
		or Party.EnemyDetectorYellow
		or Party.EnemyDetectorRed then

		Game.ShowStatusText(evt.str[21])
	elseif Party.QBits[710] then
		evt.EnterHouse{221}
	else
		evt.EnterHouse{219}
	end
end

function events.LoadMap()
	if vars.Quest_CrossContinents and Party.QBits[633] then
		vars.Quest_CrossContinents.ContinentFinished[2] = true
	end
end

function events.AfterLoadMap()
	if Party.QBits[630] then
		Game.PlayTrack(math.random(22,124,125))
	end
	if Party.QBits[633] then
		LocalHostileTxt()
		Game.HostileTxt[153][0] = 0
		Game.HostileTxt[130] = Game.HostileTxt[153]
		for i,v in Map.Monsters do
			if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
				if v.Id == 307 then
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
				elseif  v.Id == 289 then
					v:ChangeLook(389)
					v:SetId(389)
					v.Attack1.Type = 12
					v.Attack1.Missile = 13
					v.Attack2.Type = 12
					v.Attack2.Missile = 13
					v.FullHP = 1280
					v.HP = v.FullHP
					v.Level = 100
					v.Bonus = 16
				elseif  v.Id == 290 then
					v:ChangeLook(390)
					v:SetId(390)
					v.Attack1.Type = 12
					v.Attack1.Missile = 13
					v.Attack2.Type = 12
					v.Attack2.Missile = 13
					v.FullHP = 1600
					v.HP = v.FullHP
					v.Level = 100
					v.Bonus = 16
				end
			end
		end
	end	
end
