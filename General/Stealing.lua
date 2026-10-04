-- Stealing from map monsters and shops
local LogId = "Stealing"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MO, MS = Merge.ModSettings, Merge.Offsets, Merge.Settings

local nop, u2, u4 = mem.nop, mem.u2, mem.u4
local strformat = string.format
local ceil, max, min, random = math.ceil, math.max, math.min, math.random

local base_recovery = { 120, 115, 110, 105 }
local thief_recovery_bonus = 15
local ban_days = MS and MS.Stealing and MS.Stealing.ShopBanDuration or 336
local base_fine = MS and MS.Stealing and MS.Stealing.BaseFine or 50

local stolen_this_session
local MonstersSource

function GetStealingTotalSkill(player)
	local result, mastery = SplitSkill(player:GetSkill(const.Skills.Stealing))
	if result > 0 then
		local level = SplitSkill(player.Skills[const.Skills.Stealing])
		result = result + level * select(mastery, 0, 1, 2, 4)
		if player:HasItemBonus(35) > 0 then
			-- Has 'of Thievery' bonus
			result = result * 2
		end
		result = result + select(mastery, 25, 30, 35, 40)
	end
	return result 
end

local function SetStealingHooks()
	local function GetPlayerFromPtr(ptr)
		local PlayerId = (ptr - Party.PlayersArray["?ptr"])/Party.PlayersArray[0]["?size"]
		return Party.PlayersArray[PlayerId], PlayerId
	end

	-- Show Stealing in character skills screen
	mem.asmpatch(0x419AE2, [[
	cmp dword ptr [0x4F3964], 0x24
	je @end
	mov dword ptr [0x4F3964], 0x24
	sub dword ptr [ebp-0x28], 4
	jmp absolute 0x419867
	@end:
	mov dword ptr [0x4F3964], 0x1A
	cmp dword ptr [ebp-0x2C], 0
	jnz absolute 0x419BDA
	]])

	-- Click in the shop/guild
	mem.autohook2(0x4b45a0, function(d)			-- magic shop
		if Keys.IsPressed(const.Keys.CTRL) then
			local item_ptr = d.esi
			local item_txt = Game.ItemsTxt[u4[item_ptr]]
			local value = item_txt.Value
			local player = Party:GetCurrentPlayer()
			local stealing = GetStealingTotalSkill(player)
			local bound = item_txt.IdRepSt > 0 and item_txt.IdRepSt
			or value > 0 and min(ceil(value / 100), 50) or 0
			d.ecx = mem_cstring(string.format("Chance to steal this item is %d percent.", math.max(stealing - bound, 0)))		
		end
	end)
	mem.autohook2(0x4b4a56, function(d)			-- magic guild
		if Keys.IsPressed(const.Keys.CTRL) then
			local item_ptr = d.esi
			local item_txt = Game.ItemsTxt[u4[item_ptr]]
			local value = item_txt.Value
			local player = Party:GetCurrentPlayer()
			local stealing = GetStealingTotalSkill(player)
			local bound = item_txt.IdRepSt > 0 and item_txt.IdRepSt
			or value > 0 and min(ceil(value / 100), 50) or 0
			d.ecx = mem_cstring(string.format("Chance to steal this item is %d percent.", math.max(stealing - bound, 0)))	
		end
	end)
	mem.autohook2(0x4b804b, function(d)			-- weapon shop
		if Keys.IsPressed(const.Keys.CTRL) then
			local item_ptr = d.esi
			local item_txt = Game.ItemsTxt[u4[item_ptr]]
			local value = item_txt.Value
			local player = Party:GetCurrentPlayer()
			local stealing = GetStealingTotalSkill(player)
			local bound = item_txt.IdRepSt > 0 and item_txt.IdRepSt
			or value > 0 and min(ceil(value / 100), 50) or 0
			d.ecx = mem_cstring(string.format("Chance to steal this item is %d percent.", math.max(stealing - bound, 0)))	
		end
	end)
	mem.autohook2(0x4b8c78, function(d)			-- alchemy shop
		if Keys.IsPressed(const.Keys.CTRL) then
			local item_ptr = d.esi
			local item_txt = Game.ItemsTxt[u4[item_ptr]]
			local value = item_txt.Value
			local player = Party:GetCurrentPlayer()
			local stealing = GetStealingTotalSkill(player)
			local bound = item_txt.IdRepSt > 0 and item_txt.IdRepSt
			or value > 0 and min(ceil(value / 100), 50) or 0
			d.ecx = mem_cstring(string.format("Chance to steal this item is %d percent.", math.max(stealing - bound, 0)))	
		end
	end)
	mem.autohook2(0x4b9857, function(d)			-- armor shop
		if Keys.IsPressed(const.Keys.CTRL) then
			local item_ptr = d.esi
			local item_txt = Game.ItemsTxt[u4[item_ptr]]
			local value = item_txt.Value
			local player = Party:GetCurrentPlayer()
			local stealing = GetStealingTotalSkill(player)
			local bound = item_txt.IdRepSt > 0 and item_txt.IdRepSt
			or value > 0 and min(ceil(value / 100), 50) or 0
			d.ecx = mem_cstring(string.format("Chance to steal this item is %d percent.", math.max(stealing - bound, 0)))	
		end
	end)
	
	local function StealItemFromShopGuild(d, value)
		if not Keys.IsPressed(const.Keys.CTRL) then
			return 0
		end
		local player = GetPlayerFromPtr(d.edi)
		local skill = player.Skills[const.Skills.Stealing]
		if skill == 0 then
			-- No stealing skill, do nothing
			return 1
		end
		local result
		local item_ptr = d.esi
		local item_txt = Game.ItemsTxt[u4[item_ptr]]
		local stealing = GetStealingTotalSkill(player)
		local bound = item_txt.IdRepSt > 0 and item_txt.IdRepSt
			or value > 0 and min(ceil(value / 100), 50) or 0
		if stealing - bound > 0 then
			-- Try to steal
			local rnd = random(100)--random(stealing + 1) - 1
			
			MF.LogInfo("Stealing: shop item check %d vs %d", rnd, stealing - bound)
			if rnd <= stealing - bound then
				-- Put item into player's inventory
				item = mem.call(0x4910BA, 1, d.edi, -1, u4[item_ptr])
				if item > 0 then
					-- Stealing succeed
					mem.copy(d.edi + 0x484 + item * 36, item_ptr, 36)
					player.Items[item].Identified = 1
					player.Items[item].Stolen = 1
					-- FIXME
					stolen_this_session = (stolen_this_session or 0) + value
					-- Clear shop item
					Game.NeedRedraw = 1
					mem.call(0x403135, 1, item_ptr)
					mem.call(0x49E900, 1, 0xEC1980, 0, 0x1DF)
					-- Face Animation: 0x4BBD25
					player:ShowFaceAnimation(8, 0)
					-- Successful stealing
					evt[0].Add{"Reputation", 1}
					result = 2
				else
					-- Unsuccessful stealing: no room in inventory
					-- Corresponding face animation can be added
					result = 3
				end
			else
				-- Unsuccessful stealing
				result = 4
			end
		else
			-- Unsuccessful stealing
			result = 4
		end
		if result > 2 then
			-- Stealing failed
			-- Check for being caught
			local Stealth = random(max(MF.GetPlayerStatEffect(player, const.Stats.Luck)
				+ stealing
				+ (Party.SpellBuffs[11].ExpireTime > Game.Time
					and Party.SpellBuffs[11].Skill or 0), 1) + 1)
			bound = (bound == 0) and 3 or bound + 1
			local rnd = random(1,100)
			MF.LogInfo("Stealing: CaughtCheck %d vs %d", rnd, Stealth - bound)
			if rnd > Stealth - bound then
				-- Break invisibility
				Party.SpellBuffs[11].Bits=0
				Party.SpellBuffs[11].Caster=0
				Party.SpellBuffs[11].ExpireTime=0
				Party.SpellBuffs[11].OverlayId=0
				Party.SpellBuffs[11].Power=0
				Party.SpellBuffs[11].Skill=0
				evt[0].Add{"Reputation", 2}
				-- FIXME: StatusText isn't shown in shops
				--Message(strformat(Game.GlobalTxt[376], player.Name))
				result = result + 2
				player:ShowFaceAnimation(9, 0)
				Game.ShowStatusText(strformat(Game.GlobalTxt[376], player.Name))
				local write_pos = GetHouseWritePos(GetCurrentHouse())
				Game.ShopTheftExpireTime[write_pos] = Game.Time + ban_days * const.Day
				Party.Fine = Party.Fine + (stolen_this_session or 0) + base_fine
			else
				evt[0].Add{"Reputation", 1}
				-- FIXME: StatusText isn't shown in shops
				Message(strformat(Game.GlobalTxt[377], player.Name))
				player:ShowFaceAnimation(9, 0)
			end
		end
		local level, mastery = SplitSkill(skill)
		local recovery = base_recovery[mastery]
			- MF.GetPlayerStatEffect(player, const.Stats.Speed)
			- (Game.ClassesExtra[player.Class].Kind == const.ClassKind.Thief
				and thief_recovery_bonus or 0)
		player:SetRecoveryDelay(recovery)
		return result
	end

	-- Buy spellbooks
	nop(0x4BBB27, 2)

	local NewCode = mem.asmpatch(0x4BBB2C, [[
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jnz absolute 0x4BBD61
	]])

	mem.hook(NewCode, function(d)
		d.eax = StealItemFromShopGuild(d, d.ebx)
	end)

	-- Buy standard and special items
	NewCode = mem.asmpatch(0x4BBC57, [[
	nop
	nop
	nop
	nop
	nop
	test ecx, ecx
	jnz absolute 0x4BBD61
	cmp dword [ds:0xB215D4], eax
	]])

	mem.hook(NewCode, function(d)
		d.ecx = StealItemFromShopGuild(d, d.eax)
	end)
end

local function GetSqDistance(Obj1, Obj2)
	local x1, y1, z1 = XYZ(Obj1)
	local x2, y2, z2 = XYZ(Obj2)
	return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 + (z1 - z2) ^ 2
end

-- Decrease reputation if player stole from guards (group 38 or 55) or peasants
local function MonsterStealingDropReputation(mon, amount, fine)
	if mon.Group == 38 or mon.Group == 55
			or MonstersSource[mon.Id].Creed == const.Bolster.Creed.Peasant then
		evt[0].Add("Reputation", amount)
		if fine then
			Party.Fine = Party.Fine + fine
		end
	end
end

-- Steal from map monster (including NPC)
function events.WindowMessage(t)
	if not (t.Msg == 0x201 and Keys.IsPressed(const.Keys.CTRL)) then	-- WM_LBUTTONDOWN
		return
	end
	-- If in game and no spell is being casted
	if not (Game.CurrentScreen == const.Screens.Game and u2[0x51D820] == 0) then
		return
	end
	local player = Party[max(Game.CurrentPlayer, 0)]
	local target = Mouse.MouseStruct.Target
	local skill = player:GetSkill(const.Skills.Stealing)
	MF.LogInfo("Stealing: target: %d, %d", target.Index, target.Kind)
	-- Check if target is map monster and player has Stealing
	if target.Kind == 3 and skill > 0 then
		local mon = Map.Monsters[target.Index]
		if not mon then
			return
		end
		t.Handled = true
		-- Check distance to monster
		local level, mastery = SplitSkill(skill)
		--local distance = GetSqDistance(Party, mon)
		local distance = mem.call(MO.GetDistanceToMonster, 1, mon["?ptr"])
		MF.LogInfo("Stealing: monster type %d, lvl %d, distance %d",
				mon.Id, mon.Level, distance)
		--if distance > 20000 * mastery ^ 2 then
		if distance > 20 * (18 + mastery * 2) then
			return
		end
		-- Check stealing ability against monster level
		local stealing = GetStealingTotalSkill(player)
		local mbound = mon.Level
		if stealing >= mbound then
			-- Generate monster treasure if not generated yet
			if not mon.TreasureGenerated then
				-- Generate Treasure
				-- Can be overridden by events.CastTelepathy
				mem.call(0x408E89, 1, mon["?ptr"])
				MF.LogInfo("TreasureGenerated: Item0 %d, Item1 %d, Item2 %d, Item3 %d (%d)",
					mon.Items[0].Number, mon.Items[1].Number,
					mon.Items[2].Number, mon.Items[3].Number,
					mon.Items[3].Bonus2)
			end
			-- Try to steal
			local rnd = random(100)
			MF.LogInfo("Stealing: monster check %d vs %d", rnd, stealing - mbound)
			if rnd <= stealing - mbound then
				if mon.Items[3].Bonus2 > 0 then
					-- Successful stealing
					Party.AddGold(mon.Items[3].Bonus2, 0)
					Game.ShowStatusText(strformat(Game.GlobalTxt[302],
						player.Name, mon.Items[3].Bonus2))
					mon.Items[3].Bonus2 = 0
					mon.Items[3].Number = 0
					MonsterStealingDropReputation(mon, 1)
					result = 2
				else
					local item_ptr
					if mon.Items[0].Number > 0 then
						item_ptr = mon.Items[0]["?ptr"]
					elseif	mon.Items[1].Number > 0 then
						item_ptr = mon.Items[1]["?ptr"]
					elseif	mon.Items[2].Number > 0 then
						item_ptr = mon.Items[2]["?ptr"]
					end
					if item_ptr then
						-- Successful stealing
						-- Add item to Mouse
						mem.call(0x491A27, 1, 0xB20E90, item_ptr)
						-- Clear monster item
						mem.call(0x403135, 1, item_ptr)
						Mouse.Item.Stolen = 1
						MonsterStealingDropReputation(mon, 1)
						result = 2
					else
						-- Unsuccessful stealing: nothing to steal
						MonsterStealingDropReputation(mon, 1)
						Game.ShowStatusText(strformat(Game.GlobalTxt[377], player.Name))
						result = 3
					end
				end
			else
				-- Unsuccessful stealing
				result = 4
			end
		else
			-- Unsuccessful stealing
			result = 5
		end
		if result > 3 then
			-- Stealing failed
			-- Check for being caught
			local Stealth = random(max(MF.GetPlayerStatEffect(player, const.Stats.Luck)
				+ stealing
				+ (Party.SpellBuffs[11].ExpireTime > Game.Time
					and Party.SpellBuffs[11].Skill or 0), 1) + 1)
			local rnd = random(100)
			mbound = mbound + 1
			
			MF.LogInfo("Stealing: CaughtCheck %d vs %d", rnd, Stealth - mbound)
			if rnd > Stealth - mbound then
				-- Break invisibility
				Party.SpellBuffs[11].Bits=0
				Party.SpellBuffs[11].Caster=0
				Party.SpellBuffs[11].ExpireTime=0
				Party.SpellBuffs[11].OverlayId=0
				Party.SpellBuffs[11].Power=0
				Party.SpellBuffs[11].Skill=0
				MonsterStealingDropReputation(mon, 2, base_fine)
				result = result + 2
				Game.ShowStatusText(strformat(Game.GlobalTxt[376], player.Name))
				-- TODO: proper face animation
				player:ShowFaceAnimation(9, 0)
			else
				MonsterStealingDropReputation(mon, 1)
				Game.ShowStatusText(strformat(Game.GlobalTxt[377], player.Name))
				-- TODO: proper face animation
				player:ShowFaceAnimation(9, 0)
			end
		end
		local recovery = base_recovery[mastery]
			- MF.GetPlayerStatEffect(player, const.Stats.Speed)
			- (Game.ClassesExtra[player.Class].Kind == const.ClassKind.Thief
				and thief_recovery_bonus or 0)
		player:SetRecoveryDelay(recovery)
	end
end

-- FIXME: doesn't work for Magic Guilds
function events.OnEnterShop(t)
	MF.LogInfo("%s: OnEnterShop", LogId)
	stolen_this_session = 0
end

function events.GameInitialized2()
	SetStealingHooks()
	MonstersSource = Game.Bolster.MonstersSource
end

MF.LogInit2(LogId)
