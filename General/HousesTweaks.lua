local LogId = "HousesTweaks"
local MF, MO, MT, MV = Merge.Functions, Merge.Offsets, Merge.Tables, Merge.Vars
MF.LogInit1(LogId)

local u4 = mem.u4
local CLT = const.LearnTopics

local TextSet = false

local guild_member_qbit_house = {
	[191] = 1661,	-- Buccaneer's Lair, New Sorpigal
	[192] = 1661,	-- Buccaneer's Lair, Misty Islands
	[193] = 1662,	-- Protection Services, Frozen Highlands
	[194] = 1662,	-- Protection Services, Silver Cove
	[195] = 1663,	-- Smugglers, Free Haven
	[196] = 1663,	-- Smugglers, Blackshire
	[197] = 1664,	-- Blade's End, New Sorpigal
	[198] = 1665,	-- Duelists' Edge, Misty Islands
	[199] = 1666,	-- Berserker's Fury, Silver Cove
	[200] = 1665,	-- Duelists' Edge, Free Haven
	[201] = 1664,	-- Blade's End, Frozen Highlands
	[202] = 1666,	-- Berserker's Fury, Castle Ironfist
}

local guild_member_qbit_housetype = {
	[2] = {
		[5] = 1600,	-- Fire
		[6] = 1598,	-- Air
		[7] = 1601,	-- Water
		[8] = 1599,	-- Earth
		[9] = 1604,	-- Spirit
		[10] = 1603,	-- Mind
		[11] = 1602,	-- Body
		--[12] = 1605,	-- Light
		--[13] = 1606,	-- Dark
		[14] = 1596,	-- Elemental
		[15] = 1597,	-- Self
	},
	[3] = {
		[5] = 1669,
		[6] = 1667,
		[7] = 1670,
		[8] = 1668,
		[9] = 1673,
		[10] = 1672,
		[11] = 1671,
		[12] = 1674,
		[13] = 1675,
		[14] = 1659,
		[15] = 1660,
		[33] = 1659,
		[34] = 1660,
	},
}

local guild_npc_award = {
	--[65] = 248	-- test only
}
MT.GuildNPCAward = guild_npc_award

local guild_npc_mastery = {
	--[65] = 1	-- test only
}
MT.GuildNPCMastery = guild_npc_mastery

local guild_learn_topics = {
	[191] = {CLT.Dagger, CLT.Merchant, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Buccaneer's Lair, New Sorpigal
	[192] = {CLT.Leather, CLT.Alchemy, CLT.IdentifyMonster, CLT.Stealing, CLT.DisarmTraps},	-- Buccaneer's Lair, Misty Islands
	[193] = {CLT.Dagger, CLT.Merchant, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Protection Services, Frozen Highlands
	[194] = {CLT.Leather, CLT.Alchemy, CLT.IdentifyMonster, CLT.Stealing, CLT.DisarmTraps},	-- Protection Services, Silver Cove
	[195] = {CLT.Dagger, CLT.Merchant, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Smugglers, Free Haven
	[196] = {CLT.Leather, CLT.Alchemy, CLT.IdentifyMonster, CLT.Stealing, CLT.DisarmTraps},	-- Smugglers, Blackshire
	[197] = {CLT.Sword, CLT.Axe, CLT.Spear, CLT.Staff, CLT.Leather},	-- Blade's End, New Sorpigal
	[198] = {CLT.Bow, CLT.Mace, CLT.Chain, CLT.Shield, CLT.Bodybuilding},	-- Duelists' Edge, Misty Islands
	[199] = {CLT.Bow, CLT.Plate, CLT.Unarmed, CLT.Shield, CLT.Repair},	-- Berserker's Fury, Silver Cove
	[200] = {CLT.Bow, CLT.Mace, CLT.Dodging, CLT.Shield, CLT.Bodybuilding},	-- Duelists' Edge, Free Haven
	[201] = {CLT.Sword, CLT.Axe, CLT.Spear, CLT.Armsmaster, CLT.Repair},	-- Blade's End, Frozen Highlands
	[202] = {CLT.Bow, CLT.Plate, CLT.Chain, CLT.Shield, CLT.Repair},	-- Berserker's Fury, Castle Ironfist
}
--[[
-- MM6 semi-default
local guild_learn_topics = {
	[191] = {CLT.Dagger, CLT.Merchant, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Buccaneer's Lair, New Sorpigal
	[192] = {CLT.Leather, CLT.Alchemy, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Buccaneer's Lair, Misty Islands
	[193] = {CLT.Dagger, CLT.Merchant, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Protection Services, Frozen Highlands
	[194] = {CLT.Leather, CLT.Alchemy, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Protection Services, Silver Cove
	[195] = {CLT.Dagger, CLT.Merchant, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Smugglers, Free Haven
	[196] = {CLT.Leather, CLT.Alchemy, CLT.IdentifyItem, CLT.Perception, CLT.DisarmTraps},	-- Smugglers, Blackshire
	[197] = {CLT.Sword, CLT.Axe, CLT.Spear, CLT.Staff, CLT.Leather},	-- Blade's End, New Sorpigal
	[198] = {CLT.Bow, CLT.Mace, CLT.Chain, CLT.Shield, CLT.Bodybuilding},	-- Duelists' Edge, Misty Islands
	[199] = {CLT.Bow, CLT.Plate, CLT.Chain, CLT.Shield, CLT.Repair},	-- Berserker's Fury, Silver Cove
	[200] = {CLT.Bow, CLT.Mace, CLT.Chain, CLT.Shield, CLT.Bodybuilding},	-- Duelists' Edge, Free Haven
	[201] = {CLT.Sword, CLT.Axe, CLT.Spear, CLT.Staff, CLT.Repair},	-- Blade's End, Frozen Highlands
	[202] = {CLT.Bow, CLT.Plate, CLT.Chain, CLT.Shield, CLT.Repair},	-- Berserker's Fury, Castle Ironfist
}
]]

function events.GameInitialized2()
	MF.LogVerbose("%s: GameInitialized2", LogId)
	--MO.EmptyString = MF.cstring("")
	MO.GlobalTxtPtr528 = u4[Game.GlobalTxt["?ptr"] + 528 * 4]
	MO.GlobalTxtPtr544 = u4[Game.GlobalTxt["?ptr"] + 544 * 4]
	MO.NPCTextPtr122 = u4[Game.NPCText["?ptr"] + (122 - 1) * 8]
end

local function get_guild_member_qbit(house_id, house_type, continent)
	continent = continent or MV.Continent
	local res = guild_member_qbit_house[house_id]
	if res then
		return (res > 0) and res or nil
	end
	if not continent then return end
	res = guild_member_qbit_housetype[continent]
		and guild_member_qbit_housetype[continent][house_type]
	if res then
		return (res > 0) and res or nil
	end
end

function events.DrawShopTopics(t)
	MF.LogVerbose("%s: DrawShopTopics", LogId)
	local member_qbit = get_guild_member_qbit(t.HouseId, t.HouseType)
	if member_qbit and not Party.QBits[member_qbit] then
		u4[Game.GlobalTxt["?ptr"] + 544 * 4] = MO.NPCTextPtr122	-- "You must be a member of this guild to study here."
		u4[Game.GlobalTxt["?ptr"] + 528 * 4] = MO.EmptyString
		TextSet = true
		t.Handled = true
	else
		if t.HouseType == 18 then
			t.NewTopics[1] = const.ShopTopics.Learn
			t.Handled = true
		end
		if TextSet then
			u4[Game.GlobalTxt["?ptr"] + 544 * 4] = MO.GlobalTxtPtr544	-- "Seek knowledge elsewhere %s the %s"
			u4[Game.GlobalTxt["?ptr"] + 528 * 4] = MO.GlobalTxtPtr528	-- "I can offer you nothing further."
			TextSet = false
		end
	end
end

function events.DrawLearnTopics(t)
	MF.LogVerbose("%s: DrawLearnTopics", LogId)
	local member_qbit = get_guild_member_qbit(t.HouseId, t.HouseType)
	if member_qbit and not Party.QBits[member_qbit] then
		t.Handled = true
	else
		if guild_learn_topics[t.HouseId] then
			for i = 1, #guild_learn_topics[t.HouseId] do
				t.NewTopics[i] = guild_learn_topics[t.HouseId][i]
			end
			t.Handled = true
		elseif t.HouseType == 18 then
			-- Correct learn skills in merc guilds
			t.NewTopics[1] = CLT.Unarmed
			t.NewTopics[2] = CLT.Dodging
			t.NewTopics[3] = CLT.Armsmaster
			t.NewTopics[4] = CLT.DisarmTraps
			t.Handled = true
		elseif (t.HouseType >= 5 and t.HouseType <= 8) then
			-- Correct learn skills in single-school guilds.
			t.NewTopics[1] = 0x2B + t.HouseType
			t.NewTopics[2] = CLT.Learning
			t.Handled = true
		elseif (t.HouseType >= 9 and t.HouseType <= 11) then
			-- Correct learn skills in single-school guilds.
			t.NewTopics[1] = 0x2B + t.HouseType
			t.NewTopics[2] = CLT.Meditation
			t.Handled = true
		elseif t.HouseType == const.HouseType.Temple then
			-- Correct learn skills in temples
			t.NewTopics[1] = CLT.Unarmed
			t.NewTopics[2] = CLT.Dodging
			t.NewTopics[3] = CLT.Regeneration
			t.NewTopics[4] = CLT.Merchant
			t.Handled = true
		elseif t.HouseType == const.HouseType.Tavern then
			-- Correct learn skills in taverns
			t.NewTopics[1] = CLT.DisarmTraps
			t.NewTopics[2] = CLT.Perception
			t.NewTopics[3] = CLT.Stealing
			t.Handled = true
		end
	end
end

----------------------------------------
-- Switch NPC topics visibility for NPC guild
--
function events.Action(t)
	if t.Action ~= 110 then
		return
	end
	if Game.CurrentScreen ~= 13 and Game.CurrentScreen ~= 4 then return end
	local npc = GetCurrentNPC()
	if not npc or not guild_npc_award[npc] then return end
	local slot0 = MF.GetCurrentPlayer()
	if not slot0 or slot0 < 0 or slot0 == t.Param - 1 then return end
	local award = guild_npc_award[npc]
	local branch = QuestBranch()
	local slot1 = t.Param - 1
	--MF.LogVerbose("Switch player %d to %d (npc %d, branch %s), award %d(%s)",
	--	slot0, slot1, npc, branch, award, Party[slot1].Awards[award] and "y" or "n")
	Game.CurrentPlayer = slot1
	if branch ~= "" then
		if award > 0 and not Party[slot1].Awards[award] then
			ExitQuestBranch(true)
		else
			-- Reenter branch to update possible message
			ExitQuestBranch()
			QuestBranchScreen(branch)
		end
	end
	UpdateNPCQuests()
end

----------------------------------------
-- Extended Arcomage wins
--
local function get_tavern_abit(id)
	if id < 1 then
		return
	elseif id <= 11 then
		return 645 + id
	elseif id <= 25 then
		return 649 + id
	elseif id >= 33 and id <= 53 then
		return 664 + id
	end
end

local function get_tavern_award(id)
	if id < 1 then
		return
	elseif id <= 11 then
		return id
	elseif id <= 25 then
		return id - 11
	elseif id >= 33 and id <= 53 then
		return id - 32
	end
end

function events.ArcomageMatchEnd(t)

	local function CheckWin(Start, End, QBit)

		local ContWin = true
		for i = Start, End do
			if not vars.PartyStats.ArcomageWins or not vars.PartyStats.ArcomageWins[i] 
					or vars.PartyStats.ArcomageWins[i] == 0 then
				ContWin = false
				break
			end
		end
		if ContWin then
			evt.Add{"QBits", QBit}
		end

	end

	if t.result == 1 then
		vars.PartyStats = vars.PartyStats or {}
		vars.PartyStats.ArcomageWins = vars.PartyStats.ArcomageWins or {}
		--vars.ArcomageWinsExtra = vars.ArcomageWinsExtra or {}
		local IndexByType = Game.HousesExtra[t.House].IndexByType
		local abit, award = get_tavern_abit(IndexByType), get_tavern_award(IndexByType)
		local wins = vars.PartyStats.ArcomageWins[IndexByType] or 0
		if wins == 0 then
			evt.ForPlayer(0)
			evt.Add("Gold", Game.Houses[t.House].Val * 100)
			vars.PartyStats.ArcomageWins[IndexByType] = wins + 1
			if abit then
				evt.Set("AutonotesBits", abit)
			end
		end
		if award then
			evt.All.Add("Awards", award)
		end
		for k, pl in Party do
			pl.Attrs.ArcomageWins = pl.Attrs.ArcomageWins or {}
			pl.Attrs.ArcomageWins[IndexByType] =
				(pl.Attrs.ArcomageWins[IndexByType] or 0) + 1
		end
		t.Handled = true

		CheckWin(1, 11, 174)
		CheckWin(13, 25, 750)

	end
end

function events.ContinentChange1()
	-- Clear Awards text
	for i = 1, 35 do
		u4[Game.AwardsTxt["?ptr"] + 8 * i] = 0
		Game.AwardsSort[i] = 0
	end
	for p = 0, 49 do
		local pl = Party.PlayersArray[p]
		for i = 1, 35 do
			pl.Awards[i] = false
		end
	end
	if MV.Continent < 1 or MV.Continent > 3 then return end
	-- Set Awards text from Autonotes
	if MV.Continent == 1 then
		for i = 1, 11 do
			u4[Game.AwardsTxt["?ptr"] + 8 * i] = u4[Game.AutonoteTxt["?ptr"] + 8 * (i + 645)]
			Game.AwardsSort[i] = 1
		end
		for p = 0, 49 do
			local pl = Party.PlayersArray[p]
			for i = 1, 11 do
				pl.Awards[i] = pl.Attrs and pl.Attrs.ArcomageWins
					and pl.Attrs.ArcomageWins[i] and pl.Attrs.ArcomageWins[i] > 0
			end
		end
	elseif MV.Continent == 2 then
		for i = 1, 14 do
			u4[Game.AwardsTxt["?ptr"] + 8 * i] = u4[Game.AutonoteTxt["?ptr"] + 8 * (i + 660)]
			Game.AwardsSort[i] = 1
		end
		for p = 0, 49 do
			local pl = Party.PlayersArray[p]
			for i = 1, 14 do
				pl.Awards[i] = pl.Attrs and pl.Attrs.ArcomageWins
					and pl.Attrs.ArcomageWins[i + 11] and pl.Attrs.ArcomageWins[i + 11] > 0
			end
		end
	elseif MV.Continent == 3 then
		for i = 1, 21 do
			u4[Game.AwardsTxt["?ptr"] + 8 * i] = u4[Game.AutonoteTxt["?ptr"] + 8 * (i + 696)]
			Game.AwardsSort[i] = 1
		end
		for p = 0, 49 do
			local pl = Party.PlayersArray[p]
			for i = 1, 21 do
				pl.Awards[i] = pl.Attrs and pl.Attrs.ArcomageWins
					and pl.Attrs.ArcomageWins[i + 32] and pl.Attrs.ArcomageWins[i + 32] > 0
			end
		end
	end
end

----------------------------------------
-- Arcomage restriction at Antagarich
--
function events.ClickShopTopic(t)
	if t.Topic == const.ShopTopics.PlayArcomage and MV.Continent == 2
			and not evt.All.Cmp("Inventory", 1453) then
		t.Handled = true
		Game.EscMessage(Game.NPCText[1690])	-- "You must have your own card deck to play here."
	end
end

MF.LogInit2(LogId)

