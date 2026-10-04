-- The Pit

function events.AfterLoadMap()
	Party.QBits[723] = true	-- TP Buff The Pit
	
	if Party.QBits[633] then
		Game.PlayTrack(math.random(22,72,117,121,134,124,125))
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
