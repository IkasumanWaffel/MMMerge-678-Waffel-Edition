
	local MF = Merge.Functions
	local MM, MO, MS, MV = Merge.ModSettings, Merge.Offsets, Merge.Settings, Merge.Vars
	local asmpatch, asmproc = mem.asmpatch, mem.asmproc
	--0x4608c0
	local NewCode

	-- Change main menu soundtrack.
	mem.IgnoreProtection(true)
	mem.u1[0x46103c] = 16
	mem.u1[0x4bd38d] = 16
	mem.IgnoreProtection(false)

	-- Override water settings from mm8.ini
	Game.PatchOptions.HDWTRCount = 14
	Game.PatchOptions.HDWTRDelay = 15

	-- 0x4b067b - increase amount of house sound sets
	mem.asmpatch(0x4b067d, "add eax, 0xbb8")
	mem.asmpatch(0x4b0683, "imul eax, eax, 0xa")

	-- Other kinds of sounds:
	mem.asmpatch(0x4a9b23, "movzx eax, word [ds:edi+0x4c]")

	-- Disable standard lich-transformation by evt.Set{"ClassIs", X}
	-- Use Party[Y].Face = Z, and SetCharFace(Y, Z) instead.
	-- Y - char id in party, Z - portrait id form "Character portraits.txt".
	--
	-- Disable mind and soul immunity setting after lich-transformation, use
	--		Party[X].Resistances[7].Base = 65000
	--		Party[X].Resistances[8].Base = 65000

	mem.asmpatch(0x447d43, "jmp absolute 0x4482eb")

	-- Fix crown of final dominion (Remove unstackable "Of Dark" bonus)
	mem.asmpatch(0x48e7b7, "jmp absolute 0x48ec2d")
	-- Eclipse
	mem.asmpatch(0x48e73f, "jmp absolute 0x48ec2d")
	-- Staff of elements
	mem.asmpatch(0x48e86c, "jmp absolute 0x48e890")
	-- Ring of fusion
	mem.asmpatch(0x48e8f3, "jmp absolute 0x48e8fc")

	-- Remove some duplicated GetFullHP/GetFullSP calls
	mem.nop(0x492010, 7)
	mem.nop(0x492082, 7)
	mem.nop(0x492116, 7)
	mem.nop(0x49215B, 7)
	-- Remove duplicated GetSkill call
	mem.nop(0x4920BF, 9)

	-- Workaround for crash caused by exceed amount of loaded icons (>1000)
	-- Draw pending icon for items, which's icons could not be loaded.
	-- Need to find proper solution for this case.
	mem.asmpatch(0x410e06, "jmp absolute 0x410ec8")
	mem.asmpatch(0x410d76, [[
	xor eax, eax
	cmp dword [ds:ecx+0x11B7C], 0x3e7
	jge absolute 0x410ed1
	xor edi, edi
	cmp dword [ss:ebp+8], edi]])

	-- Reduce traveling cost from arena to four days and zero food.
	mem.asmpatch(0x446ee6, "push 0x0")
	mem.asmpatch(0x446f3c, "push 0x0")
	mem.nop(0x446f07, 3)

	-- Fix jumping on nonflat structures in outdoor maps.
	mem.asmpatch(0x47312d, [[
	cmp dword [ss:ebp-0x5c], ecx
	je @end

	mov eax, dword [ds:0xb7ca88]
	bt eax, 3
	jc @bad

	cmp dword [0xB21588], 100  ; max upward speed
	jg @bad
	cmp dword [0xB21588], -100  ; max downward speed
	jnl @end

	@bad:
	jmp absolute 0x47316c

	@end:
	]])

	-- fix flickering during crossing portals in indoor maps
	-- Use party Z instead of camera Z, when checking portals:
	mem.asmpatch(0x4af29c, "mov edx, dword [ds:0xB2155C]")
	-- Increase offset for MinX, MaxX, MinY, MaxY, MinZ
	mem.asmpatch(0x4af257, "push 0x7f")
	-- Increase offset for MaxZ
	mem.asmpatch(0x4af2ae, "add edi, 0x7f")

	-- Fix monsters flickering in indoor maps.
	function events.LoadMap()

		if not Map.IsIndoor() then
			return
		end

		local function fix(strData, strRoomData)
			local tData = mapvars[strData]

			local function ProcessCash()
				for RoomId,Room in pairs(tData) do
					local RoomData = Map.Rooms[RoomId][strRoomData]
					for i,v in RoomData do
						RoomData[i] = -1
					end
					local count = 0
					for i,DataId in pairs(Room) do
						RoomData[i] = DataId
						count = count + 1
					end
					RoomData.count = count
				end
			end

			local function GenerateFix()
				local cRoomId
				mapvars[strData] = {}
				for RoomId,Room in Map.Rooms do
					for i,DataId in Room[strRoomData] do
						cRoomId = Map.RoomFromPoint(Map[strRoomData][DataId])
						if cRoomId ~= RoomId and cRoomId ~= 0 then
							Room[strRoomData][i] = -1
						end
					end

					mapvars[strData][RoomId] = {}
					local RoomFix = mapvars[strData][RoomId]
					local pos = 0
					for i,v in Room[strRoomData] do
						if v >= 0 then
							RoomFix[pos] = v
							Room[strRoomData][pos] = v
							pos = pos + 1
						end
					end
					Room[strRoomData].count = pos
				end
			end

			if tData and type(tData) == "table" then
				if pcall(ProcessCash) then
					return
				end
			end
			GenerateFix()
		end

		fix("RoomSpritesFix", "Sprites")
		fix("RoomLightsFix", "Lights")

		-- fix portals Z bounds
		local F
		for RoomId, Room in Map.Rooms do
			for _, FId in Room.Portals do
				F = Map.Facets[FId]
				F.MinZ = Room.MinZ
				F.MaxZ = Room.MaxZ
			end
		end

	end

	-- Fix evt.Question (was not supposed to be called outside houses in mm8, now it should)
	mem.asmpatch(0x4d9e95, [[
	test ecx, ecx
	je absolute 0x4d9f08
	test ecx, 3]])

	mem.asmpatch(0x44203a, [[
	mov dword [ds:ebp-0x8], eax
	cmp dword [ds:0x4f37d8], 0xd
	je absolute 0x44210a
	jmp absolute 0x44204a]])

	-- Don't show final cutscene, don't change map, just print image (cutscene can be shown by evt.ShowMovie)
	mem.asmpatch(0x4bd454, "push 4")
	mem.asmpatch(0x4bd88b, "jmp 0x4bd8c4 - 0x4bd88b")
	Game.PrintEndCard = function(Text, BackImg)
		Game.EscMessage() -- to prevent custom UI being drawn on top.
		if Text then
			Game.GlobalTxt[676] = Text
		end
		if BackImg then
			mem.copy(0x5014e0, BackImg, 11)
		end
		mem.call(0x4bd3e1)
	end

	-- Fix Day of the Gods, Deadly Swarm and Flying Fist spell selection for monsters.
	-- Note: if string variables are declared as local, only the last one will contain
	--   proper characters.
	local day_of_gods, deadly_swarm = MF.cstring("Day-o-Gods"), MF.cstring("Deadly")
	local flying_fist, finger_of_death = MF.cstring("Flying"), MF.cstring("Finger")
	mem.asmpatch(0x4524B3, [[
	jnz short @daygods
	push 0x44
	jmp absolute 0x4520EB
	@daygods:
	push ]] .. day_of_gods .. [[;
	push dword ptr [edi+4]
	call absolute 0x4DA920
	test eax, eax
	pop ecx
	pop ecx
	jnz @swarm
	push 0x53
	jmp absolute 0x4520EB
	@swarm:
	push ]] .. deadly_swarm .. [[;
	push dword ptr [edi+4]
	call absolute 0x4DA920
	test eax, eax
	pop ecx
	pop ecx
	jnz @fist
	push 0x25
	jmp absolute 0x452485
	@fist:
	push ]] .. flying_fist .. [[;
	push dword ptr [edi+4]
	call absolute 0x4DA920
	test eax, eax
	pop ecx
	pop ecx
	jnz @finger
	push 0x4C
	jmp absolute 0x452485
	@finger:
	push ]] .. finger_of_death .. [[;
	push dword ptr [edi+4]
	call absolute 0x4DA920
	test eax, eax
	pop ecx
	pop ecx
	jnz absolute 0x4524BC
	push 0x75
	jmp absolute 0x4520B6
	]])

	-- Show correct transition texts for mm6/7 maps.
	local TransTexts = {
	["7d18.blv"] = 9,
	["7d14.blv"] = 398,
	["d01.blv"] = 392,
	["7d16.blv"] = 412,
	["zddb01.blv"] = 22,
	["oracle.blv"] = 166,
	["sci-fi.blv"] = 451,
	["7d15.blv"] = 397,
	["d43.blv"] = 806,
	["d44.blv"] = 815,
	["d45.blv"] = 825,
	["d46.blv"] = 835,
	["d48.blv"] = 845,
	["d49.blv"] = 854,
	["mdt09.blv"] = 8,
	["mdt10.blv"] = 15,
	["zddb04.blv"] = 19,	-- Warehouse

	-- The Bandit Caves
	["mdt14.blv"] = 10,

	-- Thunderfist mountain
	["7d07.blv"] = 406,

	-- Nighon tunnels
	["7d35.blv"] = 845, -- no proper transition text, using this one instead "Placeholder"

	-- Tunnels to Eofol
	["7d36.blv"] = 1317, -- no proper transition text, using this one instead "Placeholder"

	-- The Haunted Mansion
	["7d37.blv"] = 11,

	-- barrows
	["mdk01.blv"] = 12,
	["mdk02.blv"] = 12,
	["mdk03.blv"] = 12,
	["mdk04.blv"] = 12,
	["mdk05.blv"] = 12,
	["mdt01.blv"] = 12,
	["mdt02.blv"] = 12,
	["mdt03.blv"] = 12,
	["mdt04.blv"] = 12,
	["mdt05.blv"] = 12,
	["mdr01.blv"] = 12,
	["mdr02.blv"] = 12,
	["mdr03.blv"] = 12,
	["mdr04.blv"] = 12,
	["mdr05.blv"] = 12,

	}

	function events.GetTransitionText(t)
		local TextId = TransTexts[t.EnterMap]
		if TextId then
			t.TransId = TextId
		end
	end

	-- Roster.txt processing
	mem.nop(0x494a67, 3)
	mem.hook(0x494a6a, function(d)

		local ClassConns = {

			necromancer0  = const.Class.DarkAdept,
			necromancer  = const.Class.Necromancer,
			necromancer2 = const.Class.MasterNecromancer,
			cleric0 = const.Class.AcolyteLight,
			cleric 		 = const.Class.ClericLight,
			cleric2		 = const.Class.PriestLight,
			knight 		 = const.Class.Knight,
			knight1		 = const.Class.Cavalier,
			knight2		 = const.Class.Champion,
			troll 		 = const.Class.Barbarian,
			troll1 		 = const.Class.Berserker,
			troll2 		 = const.Class.Warmonger,
			minotaur 	 = const.Class.Minotaur,
			minotaur1	 = const.Class.MinotaurHeadsman,
			minotaur2 	 = const.Class.MinotaurLord,
			darkelf 	 = const.Class.Deerslayer,
			darkelf1 	 = const.Class.Pioneer,
			darkelf2 	 = const.Class.Pathfinder,
			vampire 	 = const.Class.Vampire,
			vampire1 	 = const.Class.ElderVampire,
			vampire2 	 = const.Class.Nosferatu,
			dragon 		 = const.Class.Dragon,
			dragon1		 = const.Class.FlightLeader,
			dragon2		 = const.Class.GreatWyrm
		} -- Use class indexes for rest.

		d.ecx = mem.u4[d.eax+8]
		local CurClassName = mem.string(d.ecx)
		d.eax = tonumber(CurClassName) or ClassConns[CurClassName]
			or const.Class[CurClassName] or const.Class.Knight

	end)

	-- Use Game.NPCNames during player selection to avoid screwing with names by gender.
	mem.hook(0x48e0f0, function(d)
		local NamesTable = Game.NPCNames[Game.CharacterPortraits[Party[0].Face].DefSex == 0 and "M" or "F"]
		Party[0].Name = NamesTable[math.random(1, #NamesTable)]
	end)

	-- negative value of FacetId leads to use facet itself instead of facet group.
	-- evt.SetFacetBit correction.
	mem.autohook(0x445d05, function(d)
		if Map.IsOutdoor() or d.ecx >= 0 or -d.ecx > Map.Facets.count -1 then return end
		d.ecx = math.abs(d.ecx)
		for k, v in pairs(const.FacetBits) do
			if v == d.edx then
				Map.Facets[d.ecx][k] = mem.u4[d.esp+4] == 1
				d.ecx = 0
			end
		end
	end)

	-- evt.SetTexture correction.
	mem.autohook(0x44597e, function(d)
		if d.ecx >= 0 then return end
		d.ecx = math.abs(d.ecx)
		local CurBitmap = mem.string(d.edx)
		local Facet = Map.Facets[d.ecx]
		if Facet.AnimatedTFT then
			for i,v in Game.TFTBin do
				if v.Name == CurBitmap then
					for a = i, i+255 do
						local TFT = Game.TFTBin[a]
						CurBitmap = TFT.Name
						CurBitmap = Game.BitmapsLod:LoadBitmap(CurBitmap)
						Game.BitmapsLod.Bitmaps[CurBitmap]:LoadBitmapPalette()
						TFT.Index = CurBitmap
						if not TFT.NotGroupEnd then
							break
						end
					end
					Facet.BitmapId = i
					break
				end
			end
		else
			CurBitmap = Game.BitmapsLod:LoadBitmap(CurBitmap)
			Game.BitmapsLod.Bitmaps[CurBitmap]:LoadBitmapPalette()
			Facet.BitmapId = CurBitmap
		end
		d.ecx = 0
	end)

	-- evt.SetSprite correction.
	mem.autohook(0x445bd2, function(d) --0x445bd2, 0x445bee
		if d.ecx >= 0 then
			return
		end

		d.ecx = math.abs(d.ecx)
		if d.ecx >= Map.Sprites.count then
			return
		end

		local DecName = mem.string(mem.u4[d.esp+4])
		Map.Sprites[d.ecx].Invisible = d.edx == 0
		if DecName ~= "0" then
			Map.Sprites[d.ecx].DecName = DecName
		end
	end)

	-- evt.SetLight correction.
	mem.autohook(0x445c9a, function(d)
		if d.ecx >= 0 then
			return
		end
		d.ecx = math.abs(d.ecx)
		Map.Lights[d.ecx].Off = d.edx == 0
		d.ecx = -1
	end)

	-- fixed in MMPatch 2.5
	-- Trigger "LeaveMap" event during traveling by boats/stables.
	--mem.autohook2(0x4b516b, function(d) -- 0x4bab72
	--	if Party.Gold >= d.ecx then
	--		internal.OnLeaveMap()
	--	end
	--end)

	-- Need to inspect this, sometimes gives crahes at spacebar action:
	mem.asmpatch(0x4685d9, [[
	movsx ecx, word [ds:ecx+0x6b1458]
	cmp ecx, 0x7fff
	jnz @end
	xor ecx, ecx
	@end:
	]])

	-- Need to inspect this, fix for ghost items in Party[*].Inventory array.
	mem.asmpatch(0x43c0f7, [[
	je absolute 0x43c105
	cmp eax, 138; limit of items in player's inventory
	jle @end
	mov dword [ds:esi], 0; erase wrong index
	jmp absolute 0x43c105
	@end:
	lea eax, [eax*8+eax];]])

	-- Need to inspect this: division by zero
	mem.asmpatch(0x4ad557, [[
	jg absolute 0x4ad5f0
	test ecx, ecx
	je absolute 0x4ad5f0;]])

	-- Need to inspect this, crashes in mm6 dungeons
	-- (something with facet lighting by objects)
	mem.asmpatch(0x408987, [[
	test esi, esi
	jl absolute 0x408b1a
	add esi, dword [ds:0x6F3C84];]])
	mem.asmpatch(0x408ca8, [[
	test esi, esi
	jl absolute 0x408e3b
	add esi, dword [ds:0x6F3C84];]])

	--mem.asmpatch(0x41a38a, [[
	--je absolute 0x41a4f1
	--cmp eax, dword [ds:0x454085];
	--jg absolute 0x41a4f1]])

	-- Reduce party move speed in TB mode, and reduce time for move taken to compensate
	do
		local mul = 5
		local old = 0x1a
		local factor = mul / old
		local BakSpeedModifiers = {}

		local function ToggleTBSpeed(state)
			if state then
				for i = 0, 1 do
					BakSpeedModifiers[i] = BakSpeedModifiers[i] or Game.SpeedModifiers[i]
					Game.SpeedModifiers[i] = factor
				end
			else
				for i, v in pairs(BakSpeedModifiers) do
					Game.SpeedModifiers[i] = v
				end
				table.clear(BakSpeedModifiers)
			end
		end

		local patch = "sub dword [ds:0x509cac], " .. mul
		for _, p in pairs{0x42E675, 0x42E6CB, 0x42EBD6, 0x42EC07} do
			mem.asmpatch(p, patch)
		end

		function events.TurnBasedStarted()
			ToggleTBSpeed(true)
		end

		function events.TurnBasedStopped()
			ToggleTBSpeed(false)
		end

		function events.LoadMapScripts()
			if not Game.TurnBased then
				for i = 0, 1 do
					Game.SpeedModifiers[i] = 1
				end
			end
		end
	end

	-- Remove artifacts found limit
	function events.LoadMap(WasInGame)
		if not WasInGame then
			for i,v in Party.ArtifactsFound do
				Party.ArtifactsFound[i] = false
			end
		end
	end
	mem.nop(0x44dd82, 7)
	mem.nop(0x4541b4, 7)
	
	-- Fix GM staff usage with Unarmed skill (Damage bonus).
	local UNARMED = const.Skills.Unarmed
	function events.CalcStatBonusBySkills(t)
		if (t.Stat ~= const.Stats.MeleeDamageBase
			and t.Stat ~= const.Stats.MeleeDamageMin
			and t.Stat ~= const.Stats.MeleeDamageMax
			or t.Player.ItemMainHand == 0
			or t.Player.Skills[UNARMED] == 0)
		then
			return
		end

		local Item = t.Player.Items[t.Player.ItemMainHand]
		local ItemSkill = Game.ItemsTxt[Item.Number].Skill
		if Item.Broken or ItemSkill ~= 0 then return end

		local US, UM = SplitSkill(t.Player:GetSkill(UNARMED))
		local SS, SM = SplitSkill(t.Player:GetSkill(const.Skills.Staff))
		if UM < 2 or SM < 3 then return end

		local u_bonus = US
		if UM > 2 then
			u_bonus = US * 2
		end
		if u_bonus > SS then
			t.Result = t.Result + u_bonus - SS
		end
	end

	-- Repair unarmed skill dodge chance
	function events.GetArmorClass(t)
		local Skill, Mas = SplitSkill(t.Player:GetSkill(UNARMED))
		if Mas == 4 and math.random(1,100) < Skill then
			t.AC = 10000
		end
	end

	-- Fix Dragon's AC and Dmg bonuses by skill
	local function CheckDragonRace(d)
		local player = MF.GetPlayerFromPtr(d.ecx)
		local race = player.Attrs and player.Attrs.Race
		if race and (Game.Races[race]
				and Game.Races[race].BaseRace == const.Race.Dragon) then
			d.eax = 1
		else
			d.eax = 0
		end
	end
	
	-- GetMeleeDamageRangeText
	NewCode = mem.asmpatch(0x48CC07, [[
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jnz absolute 0x48CC1D
	]])
	mem.hook(NewCode, CheckDragonRace)

	-- GetRangedDamageRangeText
	NewCode = mem.asmpatch(0x48CCA4, [[
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jnz absolute 0x48CC1D
	]])
	mem.hook(NewCode, CheckDragonRace)

	-- CalcStatBonusByItems
	NewCode = mem.asmpatch(0x48E2E5, [[
	mov ecx, edi
	nop
	nop
	nop
	nop
	nop
	cmp eax, 1
	]])
	mem.hook(NewCode + 2, CheckDragonRace)

	function events.CalcStatBonusBySkills(t)
		if t.Stat == const.Stats.MeleeAttack
			or t.Stat == const.Stats.MeleeDamageBase then

			local mas, skill = SplitSkill(t.Player:GetSkill(const.Skills.DragonAbility))
			t.Result = t.Result + skill*mas
		end
	end

	-- Make Dragon Attack to be of Fire damage type
	--   Undead/Ghost dragons produce Dark damage type
	mem.asmpatch(0x43710C, [[
	mov ax, word ptr [edi]
	cmp ax, 0x1F40
	mov dword ptr [ebp-0xC], 0
	jne @std
	mov dword ptr [ebp-0xC], 0xA
	@std:
	]])

	-- Make zombie/lich dragon breath white projectile
	function events.DragonBreathProjectile(t)
		local race = Party.PlayersArray[t.PlayerIndex].Attrs.Race
		if Game.Races[race].BaseRace == const.Race.Dragon
				and (Game.Races[race].Kind == const.RaceKind.Undead
				or Game.Races[race].Kind == const.RaceKind.Ghost) then
			t.ObjId = 8000
		end
	end

	local function PartyCanLearn(skill)
		for _,pl in Party do
			if pl.Skills[skill] == 0 and GetMaxAvailableSkill(pl, skill) > 0 then
				return true
			end
		end
		return false
	end

	local function PlayerCanLearn(skill)
		local pl = Party[math.max(Game.CurrentPlayer,0)]
		return pl.Skills[skill] == 0 and GetMaxAvailableSkill(pl, skill) > 0
	end

	-- For characters without SP factor, but with Meditation skill - add linear amount of SP
	local gameSPStats = Game.Classes.SPStats
	local statSP = const.Stats.SP
	function events.CalcStatBonusBySkills(t)
		if t.Stat == statSP and gameSPStats[t.Player.Class] == 0 then
			local Skill, Mas = SplitSkill(t.Player:GetSkill(const.Skills.Meditation))
			t.Result = Skill * Mas
		end
	end
	--   Add SP bonus from items if character without SP factor has Meditation
	NewCode = asmproc([[
	mov ecx, edi
	mov edx, 28
	call absolute ]] .. MO.GetPlayerSkillMastery .. [[;
	test eax, eax
	jz absolute 0x48DA98
	push 0
	push 8
	mov ecx, edi
	jmp absolute 0x48DA80
	]])

	mem.IgnoreProtection(true)
	mem.u4[0x48da9d] = NewCode
	mem.IgnoreProtection(false)

	--[[
	-- Correct learn skills in temples
	function events.DrawLearnTopics(t)
		if t.HouseType == const.HouseType.Temple then
			t.Handled = true
			t.NewTopics[1] = const.LearnTopics.Unarmed
			t.NewTopics[2] = const.LearnTopics.Dodging
			t.NewTopics[3] = const.LearnTopics.Regeneration
			t.NewTopics[4] = const.LearnTopics.Merchant
		end
	end
	]]

	-- Clean out map of removed corpses and summons by shrinking Map.Monsters table.
	--function events.LoadMap(WasInGame)
	--	local lim = Map.Monsters.limit
	--	if WasInGame and Map.Monsters.count >= lim then
	--		local MonsToKeep = {}
	--		local size = Map.Monsters[0]["?size"]
	--
	--		for i,v in Map.Monsters do
	--			if v.AIState ~= const.AIState.Removed and not (v.Summoner ~= 0 and v.HP <= 0) then
	--				table.insert(MonsToKeep, i)
	--			end
	--		end
	--
	--		for i,v in ipairs(MonsToKeep) do
	--			if i ~= v + 1 then
	--				mem.copy(Map.Monsters[i-1]["?ptr"], Map.Monsters[v]["?ptr"], size)
	--			end
	--		end
	--
	--		Map.Monsters.count = math.min(#MonsToKeep, lim)
	--	end
	--end

	-- Make mixing catalyst potions add up result catalyst power
	mem.autohook(0x415b25, function(d)
		local Target = structs.Item:new(d.ecx)
		Target.Bonus = Target.Bonus + Mouse.Item.Bonus
	end)

	-- Allow to switch between Party members in NPC screen
	mem.asmpatch(0x420D01, [[
	jz absolute 0x420E40
	cmp ecx, 4
	jnz absolute 0x420D07
	cmp dword ptr [0x519350], esi
	jz absolute 0x420F27
	xor ebx, ebx
	inc ebx
	mov dword ptr [0x587ADC], ebx
	jmp absolute 0x420F21
	]])

	-- Restrict Fly vertical movement in turn-base mode
	local tb_fly_abuse = Merge and Merge.Settings and Merge.Settings.Abuse
		and Merge.Settings.Abuse.TurnBasedFly or false
	if not tb_fly_abuse then
		--   Fly: Up
		mem.asmpatch(0x42EB89, [[
		jnz absolute 0x42EC44
		cmp dword ptr [0xB21728], edi
		jnz @end
		cmp dword ptr [0x509C9C], 3
		jnz absolute 0x42EC44
		cmp dword ptr [0x509CAC], ebx
		jle absolute 0x42EC44
		sub dword ptr [0x509CAC], 0x1A
		@end:
		]])

		--   Fly: Land
		mem.asmpatch(0x42EC1A, [[
		cmp dword ptr [0x51D33C], ebx
		jnz absolute 0x42EC44
		cmp dword ptr [0xB21728], edi
		jnz @end
		cmp dword ptr [0x509C9C], 3
		jnz absolute 0x42EC44
		cmp dword ptr [0x509CAC], 0x82
		jl absolute 0x42EC44
		sub dword ptr [0x509CAC], 0x82
		@end:
		]])
		mem.nop(0x42EC20, 2)

		--   Fly: Down
		mem.asmpatch(0x42EC2E, [[
		cmp dword ptr [0x51D33C], ebx
		jnz absolute 0x42EC44
		cmp dword ptr [0xB21728], edi
		jnz @end
		cmp dword ptr [0x509C9C], 3
		jnz absolute 0x42EC44
		cmp dword ptr [0x509CAC], ebx
		jle absolute 0x42EC44
		sub dword ptr [0x509CAC], 0x1A
		@end:
		]])
		mem.nop(0x42EC34, 2)
	end

	-- Add experience to party if monster was killed by reanimated monster
	function events.MonsterKilled(mon, monIndex, defaultHandler, killer)
		if not Merge.ModSettings.ExpFromKillByReanimated
				or Merge.ModSettings.ExpFromKillByReanimated == 0 then
			return
		end
		if killer.Type == 3 and killer.Monster.Ally == 9999 and mon.Ally ~= 9999 then
			mem.call(0x424D5B, 1, mon.Experience)
		end
	end

	-- Shrink skills table in Player Skills Panel
	local interskill = 5
	--   skills
	asmpatch(0x418DA4, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x418EAC, [[
	sub eax, ]] .. interskill)
	asmpatch(0x419006, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x419091, [[
	sub eax, ]] .. interskill)
	asmpatch(0x419102, [[
	lea ecx, [ecx + edx + 1]
	]])
	asmpatch(0x419151, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x419259, [[
	sub eax, ]] .. interskill)
	asmpatch(0x41931E, [[
	sub eax, ]] .. interskill)
	asmpatch(0x4193B3, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x41943E, [[
	sub eax, ]] .. interskill)
	asmpatch(0x4194F1, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x4195F9, [[
	sub eax, ]] .. interskill)
	asmpatch(0x4196BE, [[
	sub eax, ]] .. interskill)
	asmpatch(0x419753, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x4197DE, [[
	sub eax, ]] .. interskill)
	asmpatch(0x41984F, [[
	lea ecx, [ecx + edx + 1]
	]])
	asmpatch(0x419894, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x41999C, [[
	sub eax, ]] .. interskill)
	asmpatch(0x419A61, [[
	sub eax, ]] .. interskill)
	asmpatch(0x419AF6, [[
	lea eax, [ecx + eax - ]] .. interskill .. "]")
	asmpatch(0x419B81, [[
	sub eax, ]] .. interskill)
	--   headers
	asmpatch(0x419E6B, [[
	lea ebx, [ebx + ecx - ]] .. interskill .. "]")
	asmpatch(0x419E88, [[
	lea ebx, [ebx + ecx - ]] .. interskill .. "]")
	asmpatch(0x419E9C, [[
	lea ebx, [ebx + eax - 1]
	]])
	asmpatch(0x419F37, [[
	lea ebx, [ebx + ecx - ]] .. interskill .. "]")
	asmpatch(0x419F54, [[
	lea ebx, [ebx + ecx - ]] .. interskill .. "]")
	asmpatch(0x419F68, [[
	lea ebx, [ebx + eax - 1]
	]])

	-- Current Fines Due (Awards 42)
	asmpatch(0x41A140, [[
	jz absolute 0x41A158
	sub eax, 5
	jnz @end
	mov eax, dword ptr [0xBB2EF4]
	jmp absolute 0x41A1A1
	@end:
	dec eax]])

	-- Accept 'Y' and '1' as well as 'y' in NPCData.txt 'Join' field
	asmpatch(0x475CFF, [[
	jz @join
	cmp byte ptr [eax], 0x59
	jz @join
	cmp byte ptr [eax], 0x31
	jnz @end
	@join:
	inc ecx
	@end:
	mov dword ptr [edi+0xC], ecx
	]])

	-- Load A (BTB State), B (Fame) and C (Rep) fields of NPCData.txt
	local npcdatatxt_btb_fame_rep = asmproc([[
	push eax
	call absolute 0x4DAAD3
	mov dword ptr [edi - 0xC], eax
	jmp @end
	push eax
	call absolute 0x4DAAD3
	mov dword ptr [edi - 0x8], eax
	jmp @end
	push eax
	call absolute 0x4DAAD3
	mov dword ptr [edi - 0x4], eax
	@end:
	jmp absolute 0x475D47
	]])

	mem.prot(true)
	mem.u4[0x475F5A + 0x8] = npcdatatxt_btb_fame_rep
	mem.u4[0x475F5A + 0xC] = npcdatatxt_btb_fame_rep + 0xB
	mem.u4[0x475F5A + 0x10] = npcdatatxt_btb_fame_rep + 0x16
	mem.prot(false)

	-- 24-hour time format
	if MF.SettingGtNum(MS.Time24hFormat, 0) then
		-- tooltip
		mem.asmpatch(0x432699, [[
		mov esi, eax
		mov ecx, 0x517B40 ; MO.EmptyString
		jmp absolute 0x4326BB
		]])
		mem.asmpatch(0x4326ED, "push ecx")
		-- rest screen
		mem.nop2(0x41F00D, 0x41F015)
		mem.asmpatch(0x41F186, "push 0x517B40")
		-- shop
		MO.StrC00 = MF.cstring(":00")
		mem.nop2(0x44314A, 0x44315A)
		mem.asmpatch(0x44315A, "push " .. MO.StrC00)
		mem.asmpatch(0x443162, "push " .. MO.StrC00)
		-- savegame
		mem.nop2(0x45DF10, 0x45DF15)
		mem.asmpatch(0x45DF3B, "push 0x517B40")
	end

	-- 64bit Experience
	-- Note: uncomment 'push edx' and 'add esp' lines when GlobalTxt[538] is changed
	--   Player exp popup
	mem.asmpatch(0x4179EE, [[
	mov ecx, dword ptr [edi + 0xA4]
	cmp ecx, edx
	]], 0x4179F8 - 0x4179EE)
	mem.asmpatch(0x417A48, [[
	sub eax, dword ptr [edi + 0xA0]
	sbb edx, dword ptr [edi + 0xA4]
	;push edx
	]])
	--mem.asmpatch(0x417A91, "add esp, 0x34")
	--   Player stat exp
	MO.ExpLine = MF.cstring("%s\r190\f%05d%I64d\f00000\n\n")
	mem.asmpatch(0x41835C, [[
	push dword ptr [eax + 4]
	push dword ptr [eax]
	mov dword ptr [esp + 0x20], ecx
	]])
	mem.asmpatch(0x41836E, "push " .. MO.ExpLine)
	mem.asmpatch(0x418385, "add esp, 0x18")
	--   Evt.Cmp
	mem.asmpatch(0x447483, [[
	mov edi, dword ptr [esi + 0xA4]
	test edi, edi
	jle @std
	@success:
	xor eax, eax
	inc eax
	jmp absolute 0x447ACF
	@std:
	mov edi, dword ptr [esi + 0xA0]
	test edi, edi
	js @success
	]])
	--   CanTrain
	mem.asmpatch(0x48CD55, [[
	mov esi, ecx
	mov ecx, edx
	call absolute 0x4B30EF
	mov ecx, esi
	mov esi, dword ptr [ecx + 0xA4]
	]], 0x48CD73 - 0x48CD55)
	--   Exp required for level
	mem.asmpatch(0x4B3100, [[
	mov edx, 0x3E8
	imul edx
	]])
	--
	mem.nop(0x4B312E)
	--   Training
	mem.asmpatch(0x4B31A6, "sub esp, 0x78")
	mem.asmpatch(0x4B3229, [[
	call absolute 0x4B30EF
	mov dword ptr [ebp - 0x78], edx
	]])
	mem.asmpatch(0x4B3569, [[
	mov eax, ecx
	mov edx, dword ptr [ebp - 0x78]
	cmp edi, edx
	]])
	mem.asmpatch(0x4B3576, [[
	mov edi, dword ptr [esi + 0xA0]
	cmp edi, eax
	]], 0x4B357E - 0x4B3576)
	mem.asmpatch(0x4B3691, [[
	sub ecx, dword ptr [esi + 0xA0]
	sbb edx, dword ptr [esi + 0xA4]
	inc eax
	push eax
	;push edx
	]], 0x4B3699 - 0x4B3691)
	--mem.asmpatch(0x4B36B1, "add esp, 0x14")
	mem.asmpatch(0x4B37BB, [[
	mov eax, dword ptr [esi + 0xA4]
	mov edx, dword ptr [ebp - 0x78]
	]])
	mem.asmpatch(0x4B37ED, [[
	push ecx
	mov edx, dword ptr [ebp - 0x78]
	sub eax, dword [esi + 0xA0]
	sbb edx, dword [esi + 0xA4]
	;push edx
	]], 0x4B37F4 - 0x4B37ED)
	--mem.asmpatch(0x4B3807, "add esp, 0x14")
	--
	mem.nop(0x4BAB11)

	-- Exp limit
	MO.ExpLimit = mem.StaticAlloc(8)
	mem.i8[MO.ExpLimit] = MM.ExperienceLimit or 4000000000
	--   AddKillExp
	mem.asmpatch(0x424E07, [[
	mov edx, dword ptr []] .. (MO.ExpLimit + 4) .. [[]
	mov eax, dword ptr []] .. MO.ExpLimit .. [[]
	cmp dword ptr [esi + 0xA4], edx
	]])
	mem.asmpatch(0x424E12, "cmp dword ptr [esi + 0xA0], eax")
	mem.asmpatch(0x424E1E, "mov dword ptr [esi + 0xA4], edx")
	mem.asmpatch(0x424E25, "mov dword ptr [esi + 0xA0], eax")
	--   Evt.Add
	mem.asmpatch(0x4487FE, [[
	mov edx, dword ptr []] .. (MO.ExpLimit + 4) .. [[]
	cmp dword ptr [esi + 0xA4], edx
	]])
	mem.asmpatch(0x44880B, "mov eax, dword ptr [" .. MO.ExpLimit .. "]")
	mem.asmpatch(0x44881E, "mov dword ptr [esi + 0xA4], edx")

	-- fix UI break on outdoor NPC question screen, when pressing spacebar
	function events.Action(t)
		if t.Action == 113 and Game.CurrentScreen == 4 and mem.u4[0x5CCCE4] == 1 and mem.u4[0x6C8DDC] == 1 then
			t.Handled = true
		end
	end

	-- divison by zero, when using evt.SetDoorState with invalid door
	mem.asmpatch(0x447263, [[
		test esi, esi
		jne @std
		inc esi
		@std:
		cdq
		idiv esi
		mov edi, eax
	]])

	
