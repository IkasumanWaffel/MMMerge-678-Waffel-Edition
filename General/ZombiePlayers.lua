local LogId = "ZombiePlayers"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MO, MS, MV = Merge.ModSettings, Merge.Offsets, Merge.Settings, Merge.Vars

local floor, max, min, random = math.floor, math.max, math.min, math.random

function events.GameInitialized2()

	---- Reorganize priority of main conditions.
	local MainCondOrder = {
		const.Condition.Eradicated,
		const.Condition.Dead,
		const.Condition.Stoned,
		const.Condition.Unconscious,
		const.Condition.Paralyzed,
		const.Condition.Asleep,

		const.Condition.Disease3,
		const.Condition.Poison3,
		const.Condition.Disease2,
		const.Condition.Poison2,
		const.Condition.Disease1,
		const.Condition.Poison1,

		const.Condition.Zombie,
		const.Condition.Insane,
		const.Condition.Drunk,
		const.Condition.Afraid,
		19, -- Unarmed
		18, -- Feebleminded
		const.Condition.Weak,
		const.Condition.Cursed
	}

	for i,v in ipairs(MainCondOrder) do
		mem.u4[0x4fdfa4 + i*4] = v
	end

	---- Make Zombies immune to some diseases and mental conditions.
	local ZombieImmunities = {
		const.Condition.Asleep,
		const.Condition.Disease3,
		const.Condition.Disease2,
		const.Condition.Disease1,
		const.Condition.Insane,
		const.Condition.Drunk,
		const.Condition.Afraid,
		const.Condition.Weak
	}
	
	local InfectionTimers = {}
	function events.DoBadThingToPlayer(t)
		local ZombieNPC = {154, 155, 156, 427, 428, 429}
		local Infections = {9, 10, 11}
		local Thing = t.Thing
		local Monster = t.Monster.Id
		local Time = Game.Time + const.Minute*20
		local Player = t.Player
		local TKey = Time .. Player.Name
		if Player.Conditions[17] > 0 and table.find(ZombieImmunities, Thing) then
			t.Allow = false
		end
		InfectionTimers[TKey] = function()
			if Game.Time > Time then
				Player.Conditions[17] = Game.Time
				if Player.Conditions[14] <= Game.Time then 
					Player.HP = 1
					Player.Conditions[14] = 0
				end
				Player:ShowFaceAnimation(28)
				RemoveTimer(InfectionTimers[TKey])
				InfectionTimers[TKey] = nil
			else
				Game.PlayersExtra[Player:GetIndex()].Debuffs[17].ExpireTime = Time
				local MainCond = Player:GetMainCondition()
				if MainCond == 20 or (Player.Conditions[7] == 0 and Player.Conditions[9] == 0 and Player.Conditions[11] == 0) then
					Game.PlayersExtra[Player:GetIndex()].Debuffs[17].ExpireTime = 0
					RemoveTimer(InfectionTimers[TKey])
					InfectionTimers[TKey] = nil
				end
			end
		end
		--Merge.Vars.Txtmessage = string.format("Thing: %d, Monster: %d", Thing, Monster)
		if table.find(Infections, Thing) and t.Allow == true and table.find(ZombieNPC, Monster) then
			Timer(InfectionTimers[TKey], const.Minute, true)
		end
	end

	---- Portrait switches.

	-- Keep drawing face animations if character is in zombie condition
	-- and switch portrait according to condition.
	NewCode = mem.asmpatch(0x48fb90, [[
	mov ecx, eax

	; Get face
	movzx eax, byte [ds:esi+0x353]

	; Get race
	imul eax, eax, ]] .. Game.CharacterPortraits[0]["?size"] ..[[;
	add eax, ]] .. Game.CharacterPortraits["?ptr"] .. [[;
	add eax, 0x3f; race value offset
	movzx eax, byte [ds:eax]

	; cmp eax, const.Race.Zombie ;
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	mov eax, dword [ds:esi+0x88]
	jne @Zom

	test eax, eax
	jnz @SetFace
	jmp @std

	@Zom:
	test eax, eax
	jnz @std

	@SetFace:
	nop
	nop
	nop
	nop
	nop

	@std:
	mov eax, ecx
	mov ecx, esi
	cmp eax, 0x14 ; Good condition
	je absolute 0x48fcb4
	cmp eax, 0x11
	je absolute 0x48fcb4]])

	local function GetZombieFace(Race, Sex)
		MF.LogVerbose("%s: GetZombieFace: %d, %d", LogId, Race, Sex)
		local ZombieFaces = {
			[const.Race.Human]	= {[0] = 59, [1] = 60},
			[const.Race.DarkElf]	= {[0] = 59, [1] = 60},
			[const.Race.Minotaur]	= {[0] = 70, [1] = 70},
			[const.Race.Troll]	= {[0] = 76, [1] = 76},
			[const.Race.Dragon]	= {[0] = 68, [1] = 68},
			[const.Race.Elf]	= {[0] = 59, [1] = 60},
			[const.Race.Goblin]	= {[0] = 59, [1] = 60},
			[const.Race.Dwarf]	= {[0] = 72, [1] = 73},
		}
		if Game.Races[Race].Family == const.RaceFamily.Undead
				or Game.Races[Race].Family == const.RaceFamily.Ghost then
			return nil
		end
		--if Game.Races[Race].Family == const.RaceFamily.Vampire
		--		or Game.Races[Race].Family == const.RaceFamily.Zombie then
		--	return ZombieFaces[Game.Races[Race].BaseRace][Sex]
		--end
		return ZombieFaces[Game.Races[Race].BaseRace][Sex]
	end


	local function SetFace(PlayerId)
		MF.LogVerbose("%s: SetFace: %d", LogId, PlayerId)
		local Player = Party.PlayersArray[PlayerId]
		local CurrentPlayer = 0

		for k,v in Party.PlayersIndexes do
			if v == PlayerId then
				CurrentPlayer = k
			end
		end

		vars.PlayerFaces = vars.PlayerFaces or {}

		if Player.Conditions[const.Condition.Zombie] > 0 then
			local Portrait = Game.CharacterPortraits[Player.Face]

			if Game.Races[Portrait.Race].Family ~= const.RaceFamily.Zombie then
				vars.PlayerFaces[PlayerId] = vars.PlayerFaces[PlayerId] or {}
				if not vars.PlayerFaces[PlayerId].Face then
					vars.PlayerFaces[PlayerId].Face = Player.Face
				end
				if not vars.PlayerFaces[PlayerId].Voice then
					vars.PlayerFaces[PlayerId].Voice = Player.Voice
				end
			end

			local OrigPortrait = vars.PlayerFaces[PlayerId]
				and Game.CharacterPortraits[vars.PlayerFaces[PlayerId].Face] or nil
			if OrigPortrait then
				local NewFace = GetZombieFace(OrigPortrait.Race, OrigPortrait.DefSex)
				MF.LogVerbose("%s, NewFace: %s", LogId, NewFace or "nil")

				if NewFace then
					Player.Face = NewFace
					SetCharFace(CurrentPlayer, NewFace)
					if Merge.Settings.Conversions.KeepVoiceOnZombification ~= 1 then
						Player.Voice = Game.CharacterPortraits[NewFace].DefVoice
					end
				else
					Player.Conditions[const.Condition.Zombie] = 0
					Player.Conditions[const.Condition.Dead] = Game.Time
				end
			end
		else
			local NewFace = vars.PlayerFaces[PlayerId]
			if NewFace then
				Player.Face = NewFace.Face
				SetCharFace(CurrentPlayer, NewFace.Face)
				Player.Voice = NewFace.Voice
			end
			--if Game.Races[Game.CharacterPortraits[Player.Face].Race].Family == const.RaceFamily.Zombie then
			--	Player.Conditions[const.Condition.Zombie] = Game.Time
			--end
		end
	end

	mem.hook(NewCode + 0x17, function(d)
		d.eax = Game.Races[d.eax] and (Game.Races[d.eax].Family == const.RaceFamily.Zombie)
	end)

	mem.hook(NewCode + 0x30, function(d)
		local PlayerId	= (d.esi - Party.PlayersArray["?ptr"])/Party.PlayersArray[0]["?size"]
		SetFace(PlayerId)
	end)

	-- Make direct heals harm zombified characters.
	mem.asmpatch(0x48d048, [[
	cmp dword [ds:esi+0x88], 0x0
	je @std
	sub dword [ds:esi+0x1bf8], ecx
	jmp @end

	@std:
	add dword [ds:esi+0x1bf8], ecx
	@end:
	]])

	-- Make Divine Intervention cure zombie condition as well.
	mem.asmpatch(0x42be4a, [[
	push 0x20
	pop ecx
	mov esi, eax
	mov dword [ds:eax+0x88], 0
	]])
	

	-- Make cure of zombie condition same expensive as eradication.
	-- NOTE: MMMWE_Economy.lua replaces temple_heal_price entirely and applies
	-- this rule itself (Economy.Settings.Heal.ZombieMul). The patch below only
	-- takes effect when Economy.Settings.Enabled = false or via t.CallOriginal().
	local IsDarkTemplePtr = mem.StaticAlloc(1)
	local HasLowRankCondZPtr = mem.StaticAlloc(1)
	mem.asmpatch(0x4b661b, [[
	; don't increase cost in dark temples
	cmp byte [ds:]] .. IsDarkTemplePtr .. [[], 1
	je @std
	
	cmp byte [ds:]] .. HasLowRankCondZPtr .. [[], 1
	je absolute 0x4b662a

	cmp eax, 0x11
	je absolute 0x4b662a

	@std:
	cmp eax, 0xe
	jl absolute 0x4b6648]])
	
	-- Dark temples will reanimate players instead of reviving.
	local IsDarkTemple = false
	function events.EnterHouse(i)
		local House = Game.Houses[i]
		IsDarkTemple = House.Type == const.HouseType.Temple and (House.C == 2 or House.C == 3)
		mem.u1[IsDarkTemplePtr] = IsDarkTemple and 1 or 0
		if Economy then
			Economy.IsDarkTemple = IsDarkTemple
			Economy.CurrentHouse = i
		end
	end
	
	-- Zombie condition is prioritized in temple heal cost
	local HasLowRankCondZ = 0
	function events.CanShowHealTopic(t)
		if t.CanShow then
			local Player = Party:GetCurrentPlayer()
			HasLowRankCondZ = Player.Conditions[const.Condition.Zombie] > 0 and Player:GetMainCondition() < const.Condition.Eradicated and 1 or 0
			mem.u1[HasLowRankCondZPtr] = HasLowRankCondZ == 1 and 1 or 0
		end
	end

	local function NeedHealDark(Player)
		local Conditions = Player.Conditions
		local Race = GetCharRace(Player)

		if (Conditions[const.Condition.Dead] > 0 or Conditions[const.Condition.Eradicated] > 0)
				and Game.Races[Race].Family ~= const.RaceFamily.Undead
				and Game.Races[Race].Family ~= const.RaceFamily.Ghost
				and not GetZombieFace(Race, Player:GetSex()) then
			return false
		end

		local NeedHeal = false
		for i = 0, 16 do
			if Conditions[i] > 0 then
				NeedHeal = true
				break
			end
		end

		local NeedHeal = NeedHeal or (Player.HP < Player:GetFullHP()) or (Player.SP < Player:GetFullSP())
		return NeedHeal
	end

	-- Base reanimation price charged by dark temples (nil = normal temple heal).
	-- Shared with MMMWE_Economy.lua so the heal topic shows the same price.
	local function DarkHealBaseCost(Player, HouseId)
		local Conditions = Player.Conditions
		local Val = Game.Houses[HouseId].Val
		if Conditions[const.Condition.Dead] > 0 then
			return Val*5
		elseif Conditions[const.Condition.Eradicated] > 0 then
			return Val*10
		elseif Conditions[const.Condition.Zombie] > 0 then
			return Val
		end
	end
	if Economy then
		Economy.DarkHealBaseCost = DarkHealBaseCost
	end

	function events.ClickShopTopic(t)

		if IsDarkTemple and t.Topic == const.ShopTopics.Heal then

			local PlayerId = max(Game.CurrentPlayer, 0)
			local cPlayer  = Party[PlayerId]

			if not NeedHealDark(cPlayer) then
				t.Handled = true
				return
			end

			local Conditions = cPlayer.Conditions
			local Cost = DarkHealBaseCost(cPlayer, t.HouseId)

			if Cost and Economy and Economy.Price then
				Cost = Economy.Price("DarkHeal", {
					BaseCost = Cost, Mult = Game.Houses[t.HouseId].Val,
					HouseId = t.HouseId, Player = cPlayer,
					PlayerIndex = Party.PlayersIndexes[PlayerId],
				})
			end

			if Cost and evt.Subtract{"Gold", Cost} then
				t.Handled = true
				cPlayer.HP = cPlayer:GetFullHP()
				cPlayer.SP = cPlayer:GetFullSP()
				evt.ForPlayer(PlayerId).Set{"MainCondition", 1}
				if Game.Races[GetCharRace(cPlayer)].Family ~= const.RaceFamily.Undead
						and Game.Races[GetCharRace(cPlayer)].Family ~= const.RaceFamily.Ghost then
					Conditions[const.Condition.Zombie] = Game.Time
					SetFace(Party.PlayersIndexes[PlayerId])
				end
			end
		end
	end

	function events.CanShowHealTopic(t)
		if not IsDarkTemple then
			return
		end

		t.CanShow = NeedHealDark(Party[max(Game.CurrentPlayer, 0)])
	end

	local function TransformToZombie(Target, Skill, Mastery, Force)
		--local Race = Game.CharacterPortraits[Target.Face].Race
		local Race = GetCharRace(Target)
		local valid = Force or Target.Conditions[const.Condition.Dead] > 0
			and Target.Conditions[const.Condition.Eradicated] == 0
			--and (Race == const.Race.Undead or ZombieFaces[Race][Target:GetSex()])
			and (Game.Races[Race].Family == const.RaceFamily.Undead
				or Game.Races[Race].Family == const.RaceFamily.Ghost
				or GetZombieFace(Race, Target:GetSex()))

		if valid then

			local resultHP = Skill*(10+10*Mastery)

			if Force or resultHP + Target.HP > 0 and resultHP > Target:GetFullHP()/2 then -- Success

				Game.PlaySound(18000)
				Target.HP = min(Target:GetFullHP(), resultHP + Target.HP)
				Target.HP = max(Target.HP, 1)

				for k,v in pairs(ZombieImmunities) do
					Target.Conditions[v] = 0
				end

				Target.Conditions[const.Condition.Unconscious] = 0
				Target.Conditions[const.Condition.Paralyzed] = 0
				Target.Conditions[const.Condition.Dead] = 0

				if Race ~= const.Race.Undead then
					Target.Conditions[const.Condition.Zombie] = Game.Time
					SetFace(Target:GetIndex())
				end

				return 1

			else -- Not enough skill
				Game.PlaySound(136)
				return 2

			end

		else -- Not enough SP or wrong target

			return 0
		end

	end
	Game.TransformToZombie = TransformToZombie

	-- "Reanimate" spell will raise dead players as zombies
	local u2 = mem.u2
	function events.Action(t)
		if Game.CurrentScreen == 20 and t.Action == 110 then
			local Spell = u2[0x51d820]
			if Spell == 0x59 then -- reanimate
				local Target = Party[t.Param-1]
				local Caster = Party.PlayersArray[u2[0x51d822]]
				local Skill, Mas = SplitSkill(Caster:GetSkill(const.Skills.Dark))

				local Result = Caster.SP >= 10 and TransformToZombie(Target, Skill, Mas) or 0
				if Result == 1 then
					Caster:ShowFaceAnimation(const.FaceAnimation.CastSpell)
				elseif Result == 2 then
					Caster:ShowFaceAnimation(const.FaceAnimation.SpellFailed)
					Game.ShowStatusText(Game.GlobalTxt[51])
				else
					Game.ShowStatusText(Game.GlobalTxt[586])
					Caster:ShowFaceAnimation(const.FaceAnimation.SpellFailed)
					Game.NeedRedraw = true
				end

				u2[0x51d820] = 0
				ExitCurrentScreen(nil, nil, true)
			end
		end
	end

	local chance = MS and MS.Conversions
		and MS.Conversions.ZombieZombificationChance or 0
	local StatEffect = Game.GetStatisticEffect
	local MindRes, DarkRes = const.Stats.MindResistance, const.Stats.DarkResistance
	function events.RegenTick(player)
		if Game.Races[player.Attrs.Race]
				and Game.Races[player.Attrs.Race].Family == const.RaceFamily.Zombie
				and player.Conditions[const.Condition.Zombie] == 0 then
			if chance == 0 then
				return
			end
			local base = StatEffect(player:GetResistance(MindRes) + 13)
				+ StatEffect(player:GetResistance(DarkRes) + 13)
			base = 10 * (base + StatEffect(player:GetLuck())) + 1000
			local rnd = random(base)
			--MF.LogVerbose("Zombie zombification: %d, %d, %d", rnd, chance, base)
			if rnd <= chance then
				player.Conditions[const.Condition.Zombie] = Game.Time
			end
		end
	end
end

	-- Zombies slowly rot away with time
	MV.ZombieHPDegen = MV.ZombieHPDegen or {}
	MV.ZombieSPDegen = MV.ZombieHPDegen or {}
	function events.RegenTick(Player)
		if Player.Conditions[const.Condition.Zombie] > 0 then
			local FHP, FSP = Player:GetFullHP(), Player:GetFullSP()
			MV.ZombieHPDegen[Player.Name] = (Player.HP > math.ceil(FHP/2)) and math.max(1, FHP*0.02) or 0
			MV.ZombieSPDegen[Player.Name] = math.max(1, FSP*0.02)
			Player.HP = (Player.HP > math.ceil(FHP/2)) and Player.HP - MV.ZombieHPDegen[Player.Name] or Player.HP
			Player.SP = math.max(0, Player.SP - MV.ZombieSPDegen[Player.Name])
		else
			MV.ZombieHPDegen[Player.Name] = 0
			MV.ZombieSPDegen[Player.Name] = 0
		end
	end
MF.LogInit2(LogId)
