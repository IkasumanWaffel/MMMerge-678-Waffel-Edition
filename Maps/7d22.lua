Game.MapEvtLines:RemoveEvent(197)
evt.hint[197] = evt.str[12]
evt.map[197] = function()
	local Player = Party:GetCurrentPlayer()
	local cnt = Party.Count
	local Rand = math.random(1,4)
	if Map.Vars[1] < cnt then
	
		if Rand == 1 then
			if Player.AgeBonus > 0 then
				Player.SkillPoints = Player.SkillPoints + Player.AgeBonus
				Player.AgeBonus = 0
				Map.Vars[1] = Map.Vars[1] + 1
				evt[Player:GetSlot()].Add{"Exp",0}
				Player:ShowFaceAnimation(92)
				Game.ShowStatusText("You feel rejuvenated!")
			else
				Map.Vars[1] = Map.Vars[1] + 1
				Player:ShowFaceAnimation(52)
				Game.ShowStatusText("You feel nothing unusual.")
			end
		elseif Rand == 2 then
			local PlayerStats = {
			[1] = Player.MightBase,
			[2] = Player.IntellectBase,
			[3] = Player.PersonalityBase,
			[4] = Player.EnduranceBase,
			[5] = Player.AccuracyBase,
			[6] = Player.SpeedBase,
			[7] = Player.LuckBase
			}
			local StatSum = 0
			for i = 1, 7 do
				StatSum = StatSum + PlayerStats[i]
			end
			Player.MightBase = math.ceil(StatSum/7)
			Player.IntellectBase = math.ceil(StatSum/7)
			Player.PersonalityBase = math.ceil(StatSum/7)
			Player.EnduranceBase = math.ceil(StatSum/7)
			Player.AccuracyBase = math.ceil(StatSum/7)
			Player.SpeedBase = math.ceil(StatSum/7)
			Player.LuckBase = math.ceil(StatSum/7)
			Map.Vars[1] = Map.Vars[1] + 1
			evt[Player:GetSlot()].Add{"Exp",0}
			Player:ShowFaceAnimation(92)
			Game.ShowStatusText("Perfection through balance!")
			
		elseif Rand == 3 then
			local ArtId = {545, 550}
			for _, r in ipairs({
				{1355, 1356},
				{2020, 2049},
				{1302, 1338},
				{500, 537},
			}) do
				for i = r[1], r[2] do
					ArtId[#ArtId + 1] = i
				end
			end
			evt.Add{"Inventory", ArtId[math.random(1, #ArtId)]}
			evt[Player:GetSlot()].Add{"Exp",0}
			Player:ShowFaceAnimation(35)
			Player.Conditions[const.Condition.Eradicated] = Game.Time
			Player.HP = 0
			Player.SP = 0
			Player.MightBase 		= Player.MightBase 			- 6
			Player.IntellectBase 	= Player.IntellectBase 		- 6
			Player.PersonalityBase 	= Player.PersonalityBase 	- 6
			Player.EnduranceBase 	= Player.EnduranceBase 	    - 6
			Player.AccuracyBase 	= Player.AccuracyBase 	    - 6
			Player.SpeedBase 		= Player.SpeedBase 		    - 6
			Player.LuckBase 		= Player.LuckBase 		    - 6
			Map.Vars[1] = Map.Vars[1] + 1
			Game.ShowStatusText("Searing dream!")
			
		elseif Rand == 4 then
			local function applyResistancePump(player, maxShift)
				local pumpMap = {
					[1] = { "WaterResistanceBase", "FireResistanceBase" },  -- Water → Fire
					[2] = { "EarthResistanceBase",  "AirResistanceBase"  }, -- Earth → Air
					[3] = { "FireResistanceBase",   "WaterResistanceBase"  }, -- Fire → Water
					[4] = { "AirResistanceBase",    "EarthResistanceBase"  }, -- Air → Earth
					[5] = { "BodyResistanceBase",   "MindResistanceBase"   }, -- Body → Mind
					[6] = { "MindResistanceBase",   "BodyResistanceBase"   }  -- Mind → Body
				}
				local elem = math.random(1, 6)
				local src, dst = pumpMap[elem][1], pumpMap[elem][2]
				if not src then return end
				local shift = math.min(maxShift, player[src])
				player[src] = player[src] - shift
				player[dst] = player[dst] + shift
			end
			applyResistancePump(Player, 20)
			Map.Vars[1] = Map.Vars[1] + 1
			evt[Player:GetSlot()].Add{"Exp",0}
			Player:ShowFaceAnimation(92)
			Game.ShowStatusText("As above, so below!")
		end
	else
		Game.ShowStatusText("Refreshing!")
	end
end