local LogId = "PromotionTopics"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MS, MT = Merge.ModSettings, Merge.Settings, Merge.Tables
local Log = Log
local CPA = const.PromoAwards
local max, min = math.max, math.min
local strformat, strlower = string.format, string.lower
local u2 = mem.u2

local TXT = {
	promotion = Game.NPCText[2782],	-- "%s promotion"
	promote_to = Game.NPCText[2783],	-- "Promote to %s"
	promote_to_honorary = Game.NPCText[2784],	-- "Promote to Honorary %s"
	promote_to_honorary_sell = Game.NPCText[2785],	-- "Promote to Honorary %s (sell %s for %d gold)"
	cannot_be_promoted = Game.NPCText[2786],	-- "%s cannot be promoted to %s."
	already_promoted = Game.NPCText[2787],	-- "You have been promoted already to the rank of %s."
	congratulations = Game.NPCText[1678],	-- "Congratulations, %s!"
	convert_to = Game.NPCText[2788],	-- "Convert to %s"
	cannot_be_converted_to_undead = Game.NPCText[2789],	-- "Race %s cannot be converted to Undead."
	master_druids = Game.NPCText[2790],	-- "Master Druids"
	battle_mages = Game.NPCText[2791],	-- "Battle Mages"
	justiciars = Game.NPCText[2792],	-- "Justiciars"
	promote_first = Game.NPCText[2845]	-- "You have to be promoted to %s first."
}

local CC = const.Class

--------------------------------------------
---- Learn basic blaster (Tolberti, Robert the Wise)

Game.GlobalEvtLines:RemoveEvent(950)
Game.NPCTopic[950] = Game.GlobalTxt[278] -- Blaster
evt.Global[950] = function()
	local Noone = true
	for i, v in Party do
		if v.Skills[7] == 0 and Game.Classes.Skills[v.Class][7] > 0 then
			evt.ForPlayer(i).Set{"BlasterSkill", 1}
			Noone = false
		end
	end
end

--------------------------------------------
---- Base functions
local function can_convert_to_undead(player)
	local family = Game.Races[player.Attrs.Race].Family
	local kind = Game.Races[player.Attrs.Race].Kind
	local baserace = Game.Races[player.Attrs.Race].BaseRace
	if family == const.RaceFamily.Undead then
		return 0
	end
	if family == const.RaceFamily.Ghost then
		return -3
	end
	if MM.ConversionToUndeadRestriction == 1 and kind == const.RaceKind.Undead then
		return -2
	end
	if MM.ConversionToUndeadRestriction == 2 then
		return -1
	end
	local race = table.filter(Game.Races, 0,
		"BaseRace", "=", baserace,
		"Family", "=", const.RaceFamily.Undead
		)[1].Id
	if race and race > 0 then
		return race
	end
end
MF.CanConvertToUndead = can_convert_to_undead

local LichAppearance = {
[const.Race.Dwarf]		= {[0] = {Portrait = 65, Voice = 26}, [1] = {Portrait = 66, Voice = 27}},
[const.Race.Dragon]		= {[0] = {Portrait = 67, Voice = 28}, [1] = {Portrait = 67, Voice = 28}},
[const.Race.Minotaur]	= {[0] = {Portrait = 69, Voice = 67}, [1] = {Portrait = 69, Voice = 67}},
[const.Race.Troll]	= {[0] = {Portrait = 75, Voice = 72}, [1] = {Portrait = 75, Voice = 72}},
default					= {[0] = {Portrait = 26, Voice = 26}, [1] = {Portrait = 27, Voice = 27}}
}

local function SetLichAppearance(i, player, race)
	local race = race or GetCharRace(player)

	local CurPortrait = Game.CharacterPortraits[player.Face]
	local CurSex = CurPortrait.DefSex

	local NewFace = LichAppearance[Game.Races[race].BaseRace]
			or LichAppearance.default
	NewFace = NewFace[CurSex]

	if MS.Conversions.PreservePicOnLichPromotion == 1 then
		Log(Merge.Log.Info, "Lich promotion: do not change char pic")
	else
		Log(Merge.Log.Info, "Lich promotion: convert face")
		player.Face = NewFace.Portrait
		SetCharFace(i, NewFace.Portrait)
	end
	if MS.Conversions.KeepVoiceOnRaceConversion == 1 then
		Log(Merge.Log.Info, "Lich Promotion: keep current voice")
	else
		player.Voice = NewFace.Voice
	end
end

local function Promote(From, To, PromRewards, NonPromRewards, Gold, QBits, Awards)

	local Check

	if type(From) == "table" then
		Check = table.find
	else
		Check = function(v1, v2) return v1 == v2 end
	end

	for i,v in Party do
		if Check(From, v.Class) then
			evt.ForPlayer(i).Set{"ClassIs", To}
			if PromRewards then
				for k,v in pairs(PromRewards) do
					evt.ForPlayer(i).Add{k, v}
				end
			end
		elseif NonPromRewards then
			for k,v in pairs(NonPromRewards) do
				evt.ForPlayer(i).Add{k, v}
			end
		end
	end

	if GlobalRewards then
		for k,v in pairs(GlobalRewards) do
			evt.Add{k, v}
		end
	end

	if Gold then
		evt.Add{"Gold", Gold}
	end

	if QBits then
		for k,v in pairs(QBits) do
			evt.Add{"QBits", v}
		end
	end

	if Awards then
		for k,v in pairs(Awards) do
			evt.ForPlayer("All").Add{"Awards", v}
		end
	end

end

--[=[
--[[
Promote2{
	From 	= ,
	To 		= ,
	PromRewards 	= {},
	NonPromRewards 	= {},
	Gold 	= ,
	QBits 	= {},
	Awards	= {},
	Reputation	 = ,
	TextIdFirst	 = ,
	TextIdSecond = ,
	TextIdRefuse = ,
	Condition	 = nil -- function() return true end
}
]]
local function Promote2(t)

	local Check

	if type(t.From) == "table" then
		Check = table.find
	else
		Check = function(v1, v2) return v1 == v2 end
	end

	local FirstTime = true
	for k,v in pairs(t.QBits) do
		if Party.QBits[v] then
			FirstTime = false
			break
		end
	end

	local CanPromote = not FirstTime or not t.Condition or t.Condition()

	if not CanPromote then
		Message(Game.NPCText[t.TextIdRefuse])
		return 0
	end

	if t.TextIdFirst then
		if FirstTime then
			Message(Game.NPCText[t.TextIdFirst])
		else
			Message(Game.NPCText[t.TextIdSecond or t.TextIdFirst])
		end
	end

	for i,v in Party do
		if Check(t.From, v.Class) then
			evt.ForPlayer(i).Set{"ClassIs", t.To}
			if t.PromRewards then
				for k,v in pairs(t.PromRewards) do
					evt.ForPlayer(i).Add{k, v}
				end
			end
		elseif FirstTime and t.NonPromRewards then
			for k,v in pairs(t.NonPromRewards) do
				evt.ForPlayer(i).Add{k, v}
			end
		end
	end

	if FirstTime then

		for k,v in pairs(t.QBits) do
			evt.Add{"QBits", v}
		end

		if t.Gold then
			evt.Add{"Gold", t.Gold}
		end

		if t.Reputation then
			evt.Add{"Reputation", t.Reputation}
		end

		if t.Awards then
			for k,v in pairs(t.Awards) do
				evt.ForPlayer("All").Add{"Awards", v}
			end
		end

	end

	return FirstTime and 1 or 2

end

local function CheckPromotionSide(ThisSideBit, OppSideBit, ThisText, OppText, ElseText)
	if Party.QBits[ThisSideBit] then
		Message(Game.NPCText[ThisText])
		return true
	elseif Party.QBits[OppSideBit] then
		Message(Game.NPCText[OppText])
	else
		Message(Game.NPCText[ElseText])
	end
	return false
end
]=]

local function future_promotion(class1, class2)
	if class1 == class2 then
		return false
	end
	if MT.ClassesExtra[class1].Kind ~= MT.ClassesExtra[class1].Kind then
		return false
	end
	if table.find(MT.ClassPromotionsInv[class2] or {}, class1) then
		return true
	end
	if MT.ClassPromotions[class1] then
		for k, v in pairs(MT.ClassPromotions[class1]) do
			if future_promotion(v, class2) then
				return true
			end
		end
	end
	return false
end
--MF.FuturePromotion = future_promotion

local function promote_class(t)
	local k = MF.GetCurrentPlayer() or 0
	local player = Party[k]
	local orig_class = player.Class
	if player.Class == t.Class and not t.SameClass then
		Message(strformat(TXT.already_promoted, Game.ClassNames[t.Class]))
		return false
	else
		if type(t.From) == "table" then
			if not table.find(t.From, player.Class) then
				Message(strformat(TXT.cannot_be_promoted,
					Game.ClassNames[player.Class], Game.ClassNames[t.Class]))
				return false
			end
		elseif not table.find(MT.ClassPromotionsInv[t.Class] or {}, player.Class)
				and (not t.SameClass or player.Class ~= t.Class) then
			local interm
			for _, v in pairs(MT.ClassPromotions[player.Class] or {}) do
				if future_promotion(v, t.Class) then
					interm = interm or {}
					table.insert(interm, Game.ClassNames[v])
				end
			end
			if not interm then
				Message(strformat(TXT.cannot_be_promoted,
					Game.ClassNames[player.Class], Game.ClassNames[t.Class]))
			else
				Message(strformat(TXT.promote_first,
					table.concat(interm, " " .. Game.GlobalTxt[634] .. " ")))	-- "or"
			end
			return false
		end
		if (player.Attrs.Race == t.Race or table.find(t.RaceFamily or {}, Game.Races[player.Attrs.Race].Family))
				and t.Maturity and (not player.Attrs.Maturity
				or player.Attrs.Maturity < t.Maturity) then
			MF.ConvertCharacter({Player = player, ToClass = t.Class, ToMaturity = t.Maturity})
		else
			MF.ConvertCharacter({Player = player, ToClass = t.Class})
		end
		if t.Exp and t.Exp ~= 0 and orig_class ~= t.Class then
			evt[k].Add("Experience", t.Exp)
		end
		if t.Award then
			player.Attrs.PromoAwards[t.Award] = true
		end
		Message(strformat(TXT.congratulations, Game.ClassNames[t.Class]))
		MF.ShowAwardAnimation()
		return true
	end
end

local function promote_honorary_class(t)
	local k = MF.GetCurrentPlayer() or 0
	local player = Party[k]
	local show_anim = false
	if (player.Attrs.Race == t.Race or table.find(t.RaceFamily or {}, Game.Races[player.Attrs.Race].Family))
			and t.Maturity and (not player.Attrs.Maturity
			or player.Attrs.Maturity < t.Maturity) then
		MF.ConvertCharacter({Player = player, ToMaturity = t.Maturity})
		show_anim = true
	end
	if not player.Attrs.PromoAwards[t.Award] and not (player.Class == t.Class) then
		player.Attrs.PromoAwards[t.Award] = true
		show_anim = true
	end
	if show_anim then
		MF.ShowAwardAnimation()
	end
end

local function convert_class_race(t)
	local k = MF.GetCurrentPlayer() or 0
	local player = Party[k]
	local orig_class = player.Class
	if player.Class == t.Class and not t.SameClass then
		Message(strformat(TXT.already_promoted, Game.ClassNames[t.Class]))
		return false
	else
		if type(t.From) == "table" then
			if not table.find(t.From, player.Class) then
				Message(strformat(TXT.cannot_be_promoted,
					Game.ClassNames[player.Class], Game.ClassNames[t.Class]))
				return false
			end
		elseif not table.find(MT.ClassPromotionsInv[t.Class] or {}, player.Class)
				and (not t.SameClass or player.Class ~= t.Class) then
			Message(strformat(TXT.cannot_be_promoted,
				Game.ClassNames[player.Class], Game.ClassNames[t.Class]))
			return false
		end
		MF.ConvertCharacter({Player = player, ToClass = t.Class, ToRace = t.ToRace, ToMaturity = t.Maturity})
		if t.Exp and t.Exp ~= 0 and orig_class ~= t.Class then
			evt[k].Add("Experience", t.Exp)
		end
		if t.Award then
			player.Attrs.PromoAwards[t.Award] = true
		end
		Message(strformat(TXT.congratulations, Game.ClassNames[t.Class]))
		MF.ShowAwardAnimation()
		return true
	end
end

local promo_award_cont = {
	[6] = "Enroth",
	[7] = "Antagarich",
	[8] = "Jadame"
}

local function mm6_generate_promo_quests(t)
	QuestNPC = t.QuestNPC
	local class = CC[t.Name]
	local branch = strlower(t.Name)
	local class_name = Game.ClassNames[class]
	Quest{
		Name = "MM6_Promo_" .. t.Name .. "_1",
		Branch = "",
		Slot = t.Slot,
		CanShow = function() return Party.QBits[t.QBit] end,
		Ungive = function()
			QuestBranchScreen(branch)
		end,
		Texts = {
			Topic = strformat(TXT.promotion, class_name),
			Greet = t.Greet and Game.NPCText[t.Greet]
		}
	}
	Quest{
		Name = "MM6_Promo_" .. t.Name .. "_2",
		Branch = branch,
		Slot = 0,
		Ungive = function()
			promote_class({Class = class, Award = CPA["Enroth" .. t.Name],
				Race = const.Race.Human, Maturity = t.Maturity, Exp = t.Exp})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, class_name)
		}
	}
	Quest{
		Name = "MM6_Promo_" .. t.Name .. "_3",
		Branch = branch,
		Slot = 1,
		Ungive = function()
			promote_honorary_class({Class = class,
				Award = CPA["EnrothHonorary" .. t.Name],
				Race = const.Race.Human, Maturity = t.Maturity})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to_honorary, class_name)
		}
	}
end

local function mm7_generate_promo_quests(t)
	QuestNPC = t.QuestNPC
	local class = CC[t.Name]
	local branch = strlower(t.Name)
	local class_name = Game.ClassNames[class]
	local slot2 = t.Slot2 or 0
	Quest{
		Name = "MM7_Promo_" .. t.Name .. "_" .. t.Seq .. "_1",
		Branch = "",
		Slot = t.Slot,
		CanShow = function() return Party.QBits[t.QBit] end,
		Ungive = function()
			QuestBranchScreen(branch)
		end,
		Texts = {
			Topic = strformat(TXT.promotion, class_name),
			Greet = t.Greet and Game.NPCGreet[t.Greet][1],
			Ungive = t.Ungive and Game.NPCText[t.Ungive]
		}
	}
	Quest{
		Name = "MM7_Promo_" .. t.Name .. "_" .. t.Seq .. "_2",
		Branch = branch,
		Slot = slot2,
		Ungive = function()
			promote_class({Class = class, Award = CPA["Antagarich" .. t.Name],
				From = t.From, Race = t.Race, RaceFamily = t.RaceFamily,
				Maturity = t.Maturity, Exp = t.Exp})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, class_name)
		}
	}
	Quest{
		Name = "MM7_Promo_" .. t.Name .. "_" .. t.Seq .. "_3",
		Branch = branch,
		Slot = slot2 + 1,
		Ungive = function()
			promote_honorary_class({Class = class,
				Award = CPA["AntagarichHonorary" .. t.Name],
				Race = t.Race, RaceFamily = t.RaceFamily,
				Maturity = t.Maturity})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to_honorary, class_name)
		}
	}
end

local function mm8_generate_promo_quests(t)
	QuestNPC = t.QuestNPC
	local class = CC[t.Name]
	local branch = strlower(t.Name)
	local class_name = Game.ClassNames[class]
	local slot2 = t.Slot2 or 0
	Quest{
		Name = "MM8_Promo_" .. t.Name .. "_" .. t.Seq .. "_1",
		Branch = "",
		Slot = t.Slot,
		CanShow = function() return Party.QBits[t.QBit] end,
		Ungive = function()
			QuestBranchScreen(branch)
		end,
		Texts = {
			Topic = strformat(TXT.promotion, class_name),
			Greet = t.Greet and Game.NPCText[t.Greet],
			Ungive = t.Ungive and Game.NPCText[t.Ungive]
		}
	}
	Quest{
		Name = "MM8_Promo_" .. t.Name .. "_" .. t.Seq .. "_2",
		Branch = branch,
		Slot = slot2,
		Ungive = function()
			promote_class({Class = class, Award = CPA["Jadame" .. t.Name],
				From = t.From, Race = t.Race, RaceFamily = t.RaceFamily,
				Maturity = t.Maturity, Exp = t.Exp})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, class_name)
		}
	}
	Quest{
		Name = "MM8_Promo_" .. t.Name .. "_" .. t.Seq .. "_3",
		Branch = branch,
		Slot = slot2 + 1,
		Ungive = function()
			promote_honorary_class({Class = class,
				Award = CPA["JadameHonorary" .. t.Name],
				Race = t.Race, RaceFamily = t.RaceFamily,
				Maturity = t.Maturity})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to_honorary, class_name)
		}
	}
end

local function mm_generate_promo_quests_undead(t)
	QuestNPC = t.QuestNPC
	local class = CC[t.Name]
	local branch = strlower(t.Name)
	local class_name = Game.ClassNames[class]
	local class_name_spc = GetClassName({ClassId = class,
		RaceId = const.Race.UndeadHuman})
	local slot2 = t.Slot2 or 0
	-- t.Exp2 (promo with conversion to undead), t.Exp3 (already undead promo)
	local exp2, exp3 = t.Exp2 or t.Exp, t.Exp3 or t.Exp
	Quest{
		Name = "MM" .. t.Ver .. "_Promo_" .. t.Name .. "_" .. t.Seq .. "_1",
		Branch = "",
		Slot = t.Slot,
		CanShow = function() return Party.QBits[t.QBit] end,
		Ungive = function()
			QuestBranchScreen(branch)
		end,
		Texts = {
			Topic = strformat(TXT.promotion, class_name),
			Greet = t.Greet and Game.NPCGreet[t.Greet][1],
			Ungive = t.Ungive and Game.NPCText[t.Ungive]
		}
	}
	Quest{
		Name = "MM" .. t.Ver .. "_Promo_" .. t.Name .. "_" .. t.Seq .. "_2",
		Branch = branch,
		Slot = slot2,
		Ungive = function()
			local k = MF.GetCurrentPlayer() or 0
			local player = Party[k]
			evt.ForPlayer(k)
			local new_race = can_convert_to_undead(player)
			if new_race == 0 then
				promote_class({Class = class,
					Award = CPA[promo_award_cont[t.Ver] .. t.Name2],
					Race = player.Attrs.Race, Maturity = t.Maturity, Exp = exp3})
				return
			end
			if new_race > 0 then
				local orig_race = player.Attrs.Race
				if not table.find(MT.ClassPromotionsInv[class] or {}, player.Class)
						and not player.Class == class then
					Message(strformat(TXT.cannot_be_promoted,
						class_name, class_name_spc))
					return
				end
				if not evt.Cmp("Inventory", t.Item) then
					Message(Game.NPCText[t.FailTxt])
					return
				end
				if not convert_class_race({Class = class,
						Award = CPA[promo_award_cont[t.Ver] .. t.Name2],
						ToRace = new_race, Maturity = t.Maturity, Exp = exp2,
						SameClass = true}) then
					return
				end
				Message(Game.NPCText[t.SuccessTxt])
				evt.Subtract("Inventory", t.Item)
				SetLichAppearance(k, player, orig_race)
				-- Consider not to increase overbuffed lich resistances
				for j = 0, 3 do
					-- Resistances with immunity (65000) become negative in MMExtension
					local res_base = u2[player["?ptr"] + 0x1A08 + j * 2]
					if res_base < 20 then
						u2[player["?ptr"] + 0x1A08 + j * 2] = 20
					end
					--player.Resistances[j].Base = max(player.Resistances[j].Base, 20)
				end
			else
				Message(strformat(TXT.cannot_be_converted_to_undead,
					Game.Races[player.Attrs.Race].Name))
			end
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, class_name_spc)
		}
	}

	Quest{
		Name = "MM" .. t.Ver .. "_Promo_" .. t.Name .. "_" .. t.Seq .. "_3",
		Branch = branch,
		Slot = slot2 + 1,
		Ungive = function()
			promote_class({Class = class, Award = CPA[promo_award_cont[t.Ver] .. t.Name],
				From = t.From, Race = t.Race, RaceFamily = t.RaceFamily,
				Maturity = t.Maturity, Exp = t.Exp})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, class_name)
		}
	}
	Quest{
		Name = "MM" .. t.Ver .. "_Promo_" .. t.Name .. "_" .. t.Seq .. "_4",
		Branch = branch,
		Slot = slot2 + 2,
		Ungive = function()
			if t.Sell then
				promote_honorary_class({Class = class,
					Award = CPA[promo_award_cont[t.Ver] .. "Honorary" .. t.Name2],
					Race = t.Race, RaceFamily = t.RaceFamily,
					Maturity = t.Maturity})
				evt.ForPlayer("Current")
				if evt.Cmp("Inventory", t.Item) then
					evt.Subtract("Inventory", t.Item)
					evt.Add("Gold", t.Sell)
					if t.SellTxt then
						Message(Game.NPCText[t.SellTxt])
					end
				end
			else
				promote_honorary_class({Class = class,
					Award = CPA[promo_award_cont[t.Ver] .. "Honorary" .. t.Name],
					Race = t.Race, RaceFamily = t.RaceFamily,
					Maturity = t.Maturity})
			end
		end,
		Texts = {
			Topic = t.Sell
				and strformat(TXT.promote_to_honorary_sell, class_name_spc,
					Game.ItemsTxt[t.Item].Name, t.Sell)
				or strformat(TXT.promote_to_honorary, class_name)
		}
	}
end

--------------------------------------------
---- 		ENROTH PROMOTIONS			----
--------------------------------------------

--------------------------------------------
---- Enroth Knight promotion
QuestNPC = 791	-- Osric Temper
-- First
-- "Nomination"
evt.global[1379] = function()
	Party.QBits[1283] = true
end

Quest{
	Name = "MM6_Promo_Cavalier",
	Branch = "",
	Slot = 1,
	Quest = 1138,
	Exp = 15000,
	Give = function()
		if MF.CheckClassInParty(CC.Knight) then
			Message(Game.NPCText[1771])
		else
			Message(Game.NPCText[1772])
		end
		Game.NPC[792].EventA = 1379
	end,
	CheckDone = function() return Party.QBits[1283] end,
	Done = function()
		evt[0].Add("Reputation", -50)
		Party.QBits[1273] = true
		evt.All.Add("Awards", 186)	-- "Got Knight's nomination"
		Game.NPC[792].EventA = 1380
	end,
	Texts = {
		Topic = Game.NPCTopic[1378],
		Undone = Game.NPCText[1775],
		Done = Game.NPCText[1776]
	}
}
mm6_generate_promo_quests({QuestNPC = 791, Name = "Cavalier", Slot = 1,
	QBit = 1273, Maturity = 1, Exp = MM.MM6Promo1ExpReward})

-- Second
Quest{
	Name = "MM6_Promo_Champion",
	Branch = "",
	Slot = 2,
	Quest = 1139,
	QuestItem = 2128,
	Exp = 40000,
	CanShow = function() return Party.QBits[1273] end,
	Done = function()
		evt[0].Add("Reputation", -100)
		Party.QBits[1211] = false
		Party.QBits[1274] = true
		evt.All.Add("Awards", 187)	-- "Defeated the Warlord"
	end,
	Texts = {
		Topic = Game.NPCTopic[1383],
		Give = Game.NPCText[1777],
		Undone = Game.NPCText[1778],
		Done = Game.NPCText[1779]
	}
}
mm6_generate_promo_quests({QuestNPC = 791, Name = "Champion", Slot = 2,
	QBit = 1274, Greet = 1812, Maturity = 2, Exp = MM.MM6Promo2ExpReward})

--------------------------------------------
---- Enroth Sorcerer promotion
QuestNPC = 790	-- Albert Newton
-- First
Quest{
	Name = "MM6_Promo_Wizard",
	Branch = "",
	Slot = 1,
	Quest = 1135,	-- "Drink from the Fountain of Magic and return to Lord Albert Newton in Mist."
	Exp = 15000,
	Give = function()
		if MF.CheckClassInParty(CC.Sorcerer) then
			Message(Game.NPCText[1759])
		else
			Message(Game.NPCText[1760])
		end
	end,
	CheckDone = function() return Party.QBits[1260] end,
	Done = function()
		evt[0].Add("Reputation", -50)
		Party.QBits[1271] = true
		evt.All.Add("Awards", 184)	-- "Drank from the Fountain of Magic"
	end,
	Texts = {
		Topic = Game.NPCTopic[1368],
		Undone = Game.NPCText[1761],
		Done = Game.NPCText[1762]	--[[
			"You have done well in finding the Fountain.  It’s location and
			powers are a secret, do not spread its location around.  Now,
			let me show you the secrets of the wizard."
			]]
	}
}
mm6_generate_promo_quests({QuestNPC = 790, Name = "Wizard", Slot = 1,
	QBit = 1271, Maturity = 1, Exp = MM.MM6Promo1ExpReward})

if MF.GtSettingNum(MM.MM6MagePromo, 0) then
	Quest{
		Name = "MM6_Promo_Wizard_4",
		Branch = "wizard",
		Slot = 2,
		Ungive = function()
			promote_class({Class = const.Class.Mage, Award = CPA.EnrothMage})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.Mage])
		}
	}
end
if MF.GtSettingNum(MM.MM6NecromancerPromo, 0) then
	Quest{
		Name = "MM6_Promo_Wizard_5",
		Branch = "wizard",
		Slot = 3,
		Ungive = function()
			promote_class({Class = const.Class.Necromancer, Award = CPA.EnrothNecromancer})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.Necromancer])
		}
	}
end
-- Second
Quest{
	Name = "MM6_Promo_MasterWizard",
	Branch = "",
	Slot = 2,
	Quest = 1136,
	QuestItem = 2077,
	Exp = 30000,
	CanShow = function() return Party.QBits[1271] end,
	Done = function()
		evt[0].Add("Reputation", -100)
		Party.QBits[1210] = false
		Party.QBits[1272] = true
		evt.All.Add("Awards", 185)	-- "Retrieved the Crystal of Terrax"
	end,
	Texts = {
		Topic = Game.NPCTopic[1372],
		Give = Game.NPCText[1763],
		Undone = Game.NPCText[1764],
		Done = Game.NPCText[1765]
	}
}
mm6_generate_promo_quests({QuestNPC = 790, Name = "MasterWizard", Slot = 2,
	QBit = 1272, Greet = 1813, Maturity = 2, Exp = MM.MM6Promo2ExpReward})

--------------------------------------------
---- Enroth Archer promotion
QuestNPC = 800	-- Erik Von Stromgard
-- First
Quest{
	Name = "MM6_Promo_WarriorMage",
	Branch = "",
	Slot = 1,
	Quest = 1145,
	QuestItem = 2106,
	KeepQuestItem = true,
	Exp = 15000,
	Done = function()
		evt[0].Add("Reputation", -50)
		Party.QBits[1279] = true
		evt.All.Add("Awards", 192)	-- "Retrieved the key to the Dragon Towers"
	end,
	Texts = {
		Topic = Game.NPCTopic[1404],
		Give = Game.NPCText[1801],
		Undone = Game.NPCText[1802],
		Done = Game.NPCText[1803]
	}
}
mm6_generate_promo_quests({QuestNPC = 800, Name = "WarriorMage", Slot = 1,
	QBit = 1279, Maturity = 1, Exp = MM.MM6Promo1ExpReward})

-- Second
local TowerHints = {
	[1180] = Game.MapStats[151].Name,
	[1181] = Game.MapStats[150].Name,
	[1182] = Game.MapStats[146].Name,
	[1183] = Game.MapStats[144].Name,
	[1184] = Game.MapStats[141].Name,
	[1185] = Game.MapStats[143].Name
}

Quest{
	Name = "MM6_Promo_BattleMage",
	Branch = "",
	Slot = 2,
	Quest = 1146,
	Exp = 40000,
	CanShow = function() return Party.QBits[1279] end,
	CheckDone = function()
		return Party.QBits[1180] and Party.QBits[1181] and Party.QBits[1182]
			 and Party.QBits[1183] and Party.QBits[1184] and Party.QBits[1185]
	end,
	Undone = function()
		local HintLine, Hints = "", {}
		for Qbit, Line in pairs(TowerHints) do
			if not Party.QBits[Qbit] then
				table.insert(Hints, Line)
			end
			HintLine = Game.NPCText[2705] .. table.concat(Hints, Game.NPCText[2704]) .. Game.NPCText[2706] -- "(" .. ", " .. ")"
		end
		Message(Game.NPCText[1805] .. HintLine)
	end,
	Done = function()
		evt[0].Add("Reputation", -100)
		Party.QBits[1213] = false
		evt.ForPlayer("All").Subtract("Inventory", 2106)
		Party.QBits[1280] = true
		evt.All.Add("Awards", 193)	-- "Reseted all of the Dragon Towers"
	end,
	Texts = {
		Topic = TXT.battle_mages,
		Give = Game.NPCText[1804],
		--Undone = Game.NPCText[1805],
		Done = Game.NPCText[1807]
	}
}
mm6_generate_promo_quests({QuestNPC = 800, Name = "BattleMage", Slot = 2,
	QBit = 1280, Greet = 1808, Maturity = 2, Exp = MM.MM6Promo2ExpReward})

--------------------------------------------
-- "Ankh"
Game.GlobalEvtLines:RemoveEvent(1613)
evt.Global[1613] = function()
	evt.SetMessage{Str = 2003}	--[[
		"Gerrard has an ankh inscribed with his name given to him
		by the priests of Baa.  I’m not sure exactly what the ankh
		is used for, but he may use it to identify himself as a
		friend of Baa."
		]]
	--evt.SetNPCTopic{NPC = 799, Index = 2, Event = 1675}	-- "Loretta Fleise" : "Ankh"
	--evt.SetNPCTopic{NPC = 801, Index = 2, Event = 1676}	-- "Anthony Stone" : "Ankh"
	Party.QBits[1281] = true
end

--------------------------------------------
---- Enroth Cleric promotion
QuestNPC = 801	-- Anthony Stone
-- Ankh
Quest{
	Name = "MM6_Ankh_2",
	Branch = "",
	Slot = 3,
	QuestItem = 2068,
	Exp = 10000,
	Gold = 5000,
	NeverGiven = true,
	CanShow = function() return Party.QBits[1281] end,
	Done = function() Party.QBits[1281] = false end,
	Texts = {
		Topic = Game.NPCTopic[1676],
		Undone = Game.NPCText[2095],
		Done = Game.NPCText[2082]
	}
}
Quest{
	Name = "MM6_Ankh_3",
	Branch = "",
	Slot = 3,
	Gold = 5000,
	NeverGiven = true,
	CanShow = function() return Party.QBits[1282] end,
	Done = function()
		Party.QBits[1282] = false
		MF.ShowAwardAnimation()
	end,
	Texts = {
		Topic = Game.NPCTopic[1677],
		Done = Game.NPCText[2083]
	}
}

-- First
Quest{
	Name = "MM6_Promo_Priest",
	Branch = "",
	Slot = 1,
	Quest = 1129,	--[[
		"Hire a Stonecutter and a Carpenter, bring them to Temple
		Stone in Free Haven to repair the Temple, and then return
		to Lord Anthony Stone at Castle Stone."
		]]
	Exp = 15000,
	CheckDone = function() return Party.QBits[1130] end,
	Done = function()
		evt[0].Add("Reputation", -50)
		Party.QBits[1275] = true
		evt.All.Add("Awards", 188)	-- "Repaired Temple Stone in Free Haven"
	end,
	Texts = {
		Topic = Game.NPCTopic[1348],
		Give = Game.NPCText[1738],
		Undone = Game.NPCText[1739],
		Done = Game.NPCText[1740]	--[[
			"Excellent work!  The temple has been rebuilt and
			the affront to the gods eased.  For this service,
			I am happy to promote all clerics to priests, and
			I grant honorary priest status to all non-clerics.
			Congratulations! "
			]]
	}
}
mm6_generate_promo_quests({QuestNPC = 801, Name = "Priest", Slot = 1,
	QBit = 1275, Maturity = 1, Exp = MM.MM6Promo1ExpReward})

if MF.GtSettingNum(MM.MM6ClericLightPromo, 0) then
	Quest{
		Name = "MM6_Promo_Priest_4",
		Branch = "priest",
		Slot = 2,
		Ungive = function()
			promote_class({Class = const.Class.ClericLight, Award = CPA.EnrothClericLight})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.ClericLight])
		}
	}
end
if MF.GtSettingNum(MM.MM6ClericDarkPromo, 0) then
	Quest{
		Name = "MM6_Promo_Priest_5",
		Branch = "priest",
		Slot = 3,
		Ungive = function()
			promote_class({Class = const.Class.ClericDark, Award = CPA.EnrothClericDark})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.ClericDark])
		}
	}
end

-- Second
Quest{
	Name = "MM6_Promo_HighPriest",
	Branch = "",
	Slot = 2,
	Quest = 1131,
	Exp = 30000,
	CanShow = function() return Party.QBits[1275] end,
	CheckDone = function() return Party.QBits[1132] end,
	Undone = function()
		if evt.All.Cmp("Inventory", 2054) then
			Message(Game.NPCText[1743])
		else
			Message(Game.NPCText[1742])
		end
	end,
	Done = function()
		evt[0].Add("Reputation", -100)
		Party.QBits[1276] = true
		evt.All.Add("Awards", 189)	-- "Brought Sacred Chalice to Temple Stone"
	end,
	Texts = {
		Topic = Game.NPCTopic[1350],
		Give = Game.NPCText[1741],
		Done = Game.NPCText[1744]
	}
}
mm6_generate_promo_quests({QuestNPC = 801, Name = "HighPriest", Slot = 2,
	QBit = 1276, Greet = 1745, Maturity = 2, Exp = MM.MM6Promo2ExpReward})

--------------------------------------------
---- Enroth Druid promotion
QuestNPC = 799	-- Loretta Fleise
-- Ankh
Quest{
	Name = "MM6_Ankh_1",
	Branch = "",
	Slot = 3,
	QuestItem = 2068,
	Exp = 10000,
	NeverGiven = true,
	CanShow = function() return Party.QBits[1281] end,
	Done = function()
		Party.QBits[1281] = false
		Party.QBits[1282] = true
	end,
	Texts = {
		Topic = Game.NPCTopic[1675],
		Undone = Game.NPCText[2094],
		Done = Game.NPCText[2081]
	}
}

function events.NewMonth(t)
	Party.QBits[1197] = false
	Party.QBits[1198] = false
end

-- First
Quest{
	Name = "MM6_Promo_GreatDruid",
	Branch = "",
	Slot = 1,
	CheckDone = false,
	Quest = 1142,
	Texts = {
		Topic = Game.NPCTopic[1395],
		Give = Game.NPCText[1790],
		Undone = Game.NPCText[1791],
		After = Game.NPCText[1791]
	}
}

QuestNPC = 1090	-- Loretta Fleise

Quest{
	Name = "MM6_Promo_GreatDruid_0",
	BaseName = "MM6_Promo_GreatDruid",
	Branch = "",
	Slot = 0,
	Quest = 1142,
	Done = function()
		Party.QBits[1277] = true
		Party.QBits[1197] = true
		evt[0].Add("Reputation", -50)
		evt.All.Add("Awards", 190)	-- "Visited the Altar of the Sun"
		--MF.ShowAwardAnimation()
	end,
	Texts = {
		Topic = Game.NPCTopic[1678],
		Done = Game.NPCText[1792]
	}
}
mm6_generate_promo_quests({QuestNPC = 1090, Name = "GreatDruid", Slot = 0,
	QBit = 1277, Greet = 1792, Maturity = 1, Exp = MM.MM6Promo1ExpReward})

Quest{
	Name = "MM6_Promo_GreatDruid_4",
	Branch = "",
	Slot = 1,
	Texts = {
		Topic = " "
	}
}

-- Second
QuestNPC = 799	-- Loretta Fleise
Quest{
	Name = "MM6_Promo_MasterDruid",
	Branch = "",
	Slot = 2,
	CheckDone = false,
	Quest = 1143,
	CanShow = function() return Party.QBits[1277] end,
	Texts = {
		Topic = TXT.master_druids,
		Give = Game.NPCText[1793],
		Undone = Game.NPCText[1795]
	}
}
Quest{
	Name = "MM6_Promo_MasterDruid_5",
	Branch = "",
	Slot = 2,
	CanShow = function() return Party.QBits[1278] end,
	Texts = {
		Topic = TXT.master_druids,
		Ungive = Game.NPCText[1795],
		Greet = Game.NPCText[1796]
	}
}

QuestNPC = 1091	-- Loretta Fleise

Quest{
	Name = "MM6_Promo_MasterDruid_0",
	BaseName = "MM6_Promo_MasterDruid",
	Branch = "",
	Slot = 0,
	Quest = 1143,
	Exp = 40000,
	Done = function()
		Party.QBits[1278] = true
		Party.QBits[1198] = true
		evt[0].Add("Reputation", -100)
		evt.All.Add("Awards", 191)	-- "Visited the Altar of the Moon"
		--MF.ShowAwardAnimation()
	end,
	Texts = {
		Topic = Game.NPCTopic[1679],
		Done = Game.NPCText[1794]
	}
}
mm6_generate_promo_quests({QuestNPC = 1091, Name = "MasterDruid", Slot = 0,
	QBit = 1278, Greet = 1794, Maturity = 2, Exp = MM.MM6Promo2ExpReward})

Quest{
	Name = "MM6_Promo_MasterDruid_4",
	Branch = "",
	Slot = 1,
	Texts = {
		Topic = " "
	}
}

--------------------------------------------
---- Enroth Paladin promotion
QuestNPC = 789	-- Wilbur Humphrey
-- First
Quest{
	Name = "MM6_Promo_Crusader",
	Branch = "",
	Slot = 1,
	Quest = 1112,
	Exp = 15000,
	CheckDone = function()
		return NPCFollowers.NPCInGroup(796)
	end,
	Done = function()
		evt[0].Add("Reputation", -50)
		Party.QBits[1269] = true
		NPCFollowers.Remove(796)
		evt.All.Add("Awards", 182)	-- "Rescued a Damsel in Distress"
	end,
	Texts = {
		Topic = Game.NPCTopic[1326],
		Give = Game.NPCText[1711],
		Undone = Game.NPCText[1712],
		Done = Game.NPCText[1713]
	}
}
mm6_generate_promo_quests({QuestNPC = 789, Name = "Crusader", Slot = 1,
	QBit = 1269, Maturity = 1, Exp = MM.MM6Promo1ExpReward})

-- Second
Quest{
	Name = "MM6_Promo_Justiciar",
	Branch = "",
	Slot = 2,
	Quest = 1113,
	Exp = 30000,
	QuestItem = 2075,
	CanShow = function() return Party.QBits[1269] end,
	Done = function()
		evt[0].Add("Reputation", -100)
		Party.QBits[1270] = true
		evt.All.Add("Awards", 183)	-- "Slayed Longfang Witherhide"
	end,
	Texts = {
		Topic = TXT.justiciars,
		Give = Game.NPCText[1714],
		Undone = Game.NPCText[1715],
		Done = Game.NPCText[1716]
	}
}
mm6_generate_promo_quests({QuestNPC = 789, Name = "Justiciar", Slot = 2,
	QBit = 1270, Greet = 1717, Maturity = 2, Exp = MM.MM6Promo2ExpReward})

-- Pearl of Purity
Game.GlobalEvtLines:RemoveEvent(1652)
evt.global[1652] = function()
	evt.SetMessage{Str = 2055}         --[[
		"In my flight, I managed to hide the Pearl of Purity in these caverns.
		The pearl will both protect you from the curse of the werewolves, and will
		also destroy the Altar of the Wolf if the pearl touches it.  That should
		free everyone afflicted by the curse these werewolves have caused.  The
		pearl is at the end of the cavern across from this one.  Please do me one
		favor, return the Pearl to Wilbur Humphrey.  He is the lord in charge of
		paladins and the pearl belongs with him."
		]]
	evt.Add{"QBits", Value = 1166}         -- NPC
end

Quest{
	Name = "MM6_PearlOfPurity",
	Branch = "",
	Slot = 3,
	Quest = 1166,
	QuestItem = 2079,
	Exp = 10000,
	NeverGiven = true,
	CanShow = function() return Party.QBits[1166] end,
	Texts = {
		Topic = Game.NPCTopic[1655],
		Undone = Game.NPCText[2092],
		Done = Game.NPCText[2059]
	}
}

--------------------------------------------
---- 		ANTAGARICH PROMOTIONS		----
--------------------------------------------

--------------------------------------------
---- Antagarich Archer promotion
-- First
QuestNPC = 380	-- Steagal Snick

Quest{
	Name = "MM7_Promo_WarriorMage_1",
	Branch = "",
	Slot = 0,
	Quest = 543,
	GivenItem = 1451,	-- Worn Belt
	Exp = 15000,
	Gold = 7500,
	Give = function()
		Party.QBits[728] = true
	end,
	CheckDone = function() return Party.QBits[570] end,
	Done = function()
		Party.QBits[794] = true
		Party.QBits[728] = false
		evt[0].Subtract("Reputation", 5)
		evt.All.Add("Awards", 133)	-- "Sabotaged the lift in the Red Dwarf Mines"
	end,
	Texts = {
		Topic = Game.NPCTopic[817],	-- "Warrior Mage"
		Give = Game.NPCText[1087],
		Undone = Game.NPCText[1089],
		Done = Game.NPCText[1088]
	}
}
mm7_generate_promo_quests({QuestNPC = 380, Name = "WarriorMage", Seq = 1, Slot = 0,
	QBit = 794, Exp = 15000})

-- Second good
QuestNPC = 379	-- Lawrence Mark

Quest{
	Name = "MM7_Promo_MasterArcher_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1083])
		elseif not Party.QBits[794] then
			Message(Game.NPCText[1084])
		else
			Message(Game.NPCText[1082])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[815]	-- "Master Archer"
	}
}
Quest{
	Name = "MM7_Promo_MasterArcher_1",
	Branch = "",
	Slot = 0,
	Quest = 542,
	QuestItem = 1344,	-- The Perfect Bow
	RewardItem = 1345,	-- The Perfect Bow
	Exp = 40000,
	CanShow = function() return Party.QBits[794] and Party.QBits[611] end,
	Done = function()
		Party.QBits[795] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 134)	-- "Retrieved the Perfect Bow and returned it to Lawrence Mark"
	end,
	Texts = {
		Topic = Game.NPCTopic[815],	-- "Master Archer"
		Give = Game.NPCText[1081],
		Undone = Game.NPCText[1086],
		Done = Game.NPCText[1085]
	}
}
mm7_generate_promo_quests({QuestNPC = 379, Name = "MasterArcher", Seq = 1, Slot = 0,
	QBit = 795, Greet = 172, Exp = 40000})

-- Second evil
QuestNPC = 380	-- Steagal Snick

Quest{
	Name = "MM7_Promo_Sniper_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[794] end,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1092])
		else
			Message(Game.NPCText[1091])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[819]	-- "Sniper"
	}
}
Quest{
	Name = "MM7_Promo_Sniper_1",
	Branch = "",
	Slot = 1,
	Quest = 544,
	QuestItem = 1344,	-- The Perfect Bow
	RewardItem = 1345,	-- The Perfect Bow
	Exp = 40000,
	CanShow = function() return Party.QBits[794] and Party.QBits[612] end,
	Done = function()
		Party.QBits[796] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 135)	-- "Retrieved the Perfect Bow and returned it to Steagal Snick"
	end,
	Texts = {
		Topic = Game.NPCTopic[819],	-- "Sniper"
		Give = Game.NPCText[1090],
		Undone = Game.NPCText[1094],
		Done = Game.NPCText[1093]
	}
}
mm7_generate_promo_quests({QuestNPC = 380, Name = "Sniper", Seq = 1, Slot = 1,
	QBit = 796, Exp = 40000})

--------------------------------------------
---- Antagarich Cleric promotion
-- First
QuestNPC = 386	-- Daedalus Falk

Quest{
	Name = "MM7_Promo_Priest_1",
	Branch = "",
	Slot = 0,
	Quest = 555,
	QuestItem = 1485,	-- Map to Evenmorn Island
	Exp = 15000,
	Gold = 5000,
	Done = function()
		Party.QBits[1004] = true
		Party.QBits[576] = true
		Party.QBits[730] = false
		evt[0].Subtract("Reputation", 5)
		evt.All.Add("Awards", 139)	-- "Found the lost pirate map in the Tidewater Caverns"
	end,
	Texts = {
		Topic = Game.NPCTopic[838],	-- "Priest"
		Give = Game.NPCText[1133],
		Undone = Game.NPCText[1135],
		Done = Game.NPCText[1134]
	}
}
mm7_generate_promo_quests({QuestNPC = 386, Name = "Priest", Seq = 1, Slot = 0,
	QBit = 1004, Exp = 15000})

if MF.GtSettingNum(MM.MM7ClericLightPromo, 0) then
	Quest{
		Name = "MM7_Promo_Priest_4",
		Branch = "priest",
		Slot = 2,
		Ungive = function()
			promote_class({Class = const.Class.ClericLight, Award = CPA.AntagarichClericLight})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.ClericLight])
		}
	}
end
if MF.GtSettingNum(MM.MM7ClericDarkPromo, 0) then
	Quest{
		Name = "MM7_Promo_Priest_5",
		Branch = "priest",
		Slot = 3,
		Ungive = function()
			promote_class({Class = const.Class.ClericDark, Award = CPA.AntagarichClericDark})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.ClericDark])
		}
	}
end

-- Second good
QuestNPC = 385	-- Rebecca Devine

Quest{
	Name = "MM7_Promo_PriestLight_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1130])
		elseif not Party.QBits[1004] then
			Message(Game.NPCText[1129])
		else
			Message(Game.NPCText[1128])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[836]	-- "Priest of Light"
	}
}
Quest{
	Name = "MM7_Promo_PriestLight_1",
	Branch = "",
	Slot = 0,
	Quest = 554,
	Exp = 40000,
	Gold = 10000,
	CanShow = function() return Party.QBits[1004] and Party.QBits[611] end,
	CheckDone = function() return Party.QBits[574] end,
	Done = function()
		Party.QBits[1005] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 140)	-- "Purified the Altar of Evil in the Temple of the Moon"
	end,
	Texts = {
		Topic = Game.NPCTopic[836],	-- "Priest of Light"
		Give = Game.NPCText[1127],
		Undone = Game.NPCText[1132],
		Done = Game.NPCText[1131]
	}
}
mm7_generate_promo_quests({QuestNPC = 385, Name = "PriestLight", Seq = 1, Slot = 0,
	QBit = 1005, Greet = 188, Exp = 40000})

-- Second evil
QuestNPC = 386	-- Daedalus Falk

Quest{
	Name = "MM7_Promo_PriestDark_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[1004] end,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[200])
		else
			Message(Game.NPCText[1137])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[840]	-- "Priest of Dark"
	}
}
Quest{
	Name = "MM7_Promo_PriestDark_1",
	Branch = "",
	Slot = 1,
	Quest = 556,
	Exp = 40000,
	Gold = 10000,
	CanShow = function() return Party.QBits[1004] and Party.QBits[612] end,
	CheckDone = function() return Party.QBits[575] end,
	Done = function()
		Party.QBits[1006] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 141)	-- "Defaced the Altar of Good in the Temple of the Sun"
	end,
	Texts = {
		Topic = Game.NPCTopic[840],	-- "Priest of Dark"
		Give = Game.NPCText[1136],
		Undone = Game.NPCText[1138],
		Done = Game.NPCText[201]
	}
}
mm7_generate_promo_quests({QuestNPC = 386, Name = "PriestDark", Seq = 1, Slot = 1,
	QBit = 1006, Greet = 190, Exp = 40000})

--------------------------------------------
---- Antagarich Druid promotion
-- First
QuestNPC = 389	-- Anthony Green

Quest{
	Name = "MM7_Promo_GreatDruid_1",
	Branch = "",
	Slot = 0,
	Quest = 561,
	Exp = 15000,
	CheckDone = function() return Party.QBits[562] end,
	Undone = function()
		if not (Party.QBits[563] or Party.QBits[564] or Party.QBits[565]) then
			Message(Game.NPCText[1153])
		else
			Message(Game.NPCText[1154])
		end
	end,
	Done = function()
		Party.QBits[1010] = true
		evt[0].Subtract("Reputation", 5)
		evt.All.Add("Awards", 142)	-- "Visited the stonehenge monoliths in Tatalia, the Evenmorn Islands, and Avlee"
	end,
	Texts = {
		Topic = Game.NPCTopic[848],	-- "Great Druid"
		Give = Game.NPCText[1152],
		Done = Game.NPCText[1155]
	}
}
mm7_generate_promo_quests({QuestNPC = 389, Name = "GreatDruid", Seq = 1, Slot = 0,
	QBit = 1010, Exp = 15000})

-- Second good
QuestNPC = 389	-- Anthony Green

Quest{
	Name = "MM7_Promo_ArchDruid_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[1010] end,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1158])
		else
			Message(Game.NPCText[1157])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[850]	-- "Arch Druid"
	}
}
Quest{
	Name = "MM7_Promo_ArchDruid_1",
	Branch = "",
	Slot = 1,
	Quest = 566,
	Exp = 40000,
	CanShow = function()
		return Party.QBits[1010] and (Party.QBits[611]
			or Party.QBits[612] and MF.GtSettingNum(MM.MM7ArchDruidPromoBothSides, 0))
	end,
	CheckDone = function() return Party.QBits[577] end,
	Done = function()
		Party.QBits[1011] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 143)	-- "Returned the bones of the Dwarf King"
	end,
	Texts = {
		Topic = Game.NPCTopic[850],	-- "Arch Druid"
		Give = Game.NPCText[1156],
		Undone = Game.NPCText[1160],
		Done = Game.NPCText[1159]
	}
}
mm7_generate_promo_quests({QuestNPC = 389, Name = "ArchDruid", Seq = 1, Slot = 1,
	QBit = 1011, Greet = 196, Exp = 40000})

-- Second evil
QuestNPC = 390	-- Tor Anwyn

Quest{
	Name = "MM7_Promo_Warlock_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1164])
		elseif not Party.QBits[1010] then
			Message(Game.NPCText[1162])
		else
			Message(Game.NPCText[1163])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[852]	-- "Warlock"
	}
}
Quest{
	Name = "MM7_Promo_Warlock_1",
	Branch = "",
	Slot = 0,
	Quest = 567,
	QuestItem = 1449,	-- Dragon Egg
	Exp = 40000,
	CanShow = function()
		return Party.QBits[1010] and (Party.QBits[612]
			or Party.QBits[611] and MF.GtSettingNum(MM.MM7WarlockPromoBothSides, 0))
	end,
	Done = function()
		Party.QBits[1012] = true
		Party.QBits[739] = false
		evt[0].Subtract("Reputation", 10)
		MF.NPCFollowerAdd(396)
		evt.All.Add("Awards", 144)	-- "Retrieved the dragon egg for Tor Anwyn"
	end,
	Texts = {
		Topic = Game.NPCTopic[852],	-- "Warlock"
		Give = Game.NPCText[1161],
		Undone = Game.NPCText[1166],
		Done = Game.NPCText[1165]
	}
}
mm7_generate_promo_quests({QuestNPC = 390, Name = "Warlock", Seq = 1, Slot = 0,
	QBit = 1012, Greet = 198, Exp = 40000})

--------------------------------------------
---- Antagarich Paladin promotion
-- First
QuestNPC = 356	-- Sir Charles Quixote

Quest{
	Name = "MM7_Promo_Crusader_1",
	Branch = "",
	Slot = 0,
	Quest = 534,
	Exp = 15000,
	Gold = 5000,
	CheckDone = function() return Party.QBits[535] end,
	Give = function()
		MF.NPCFollowerAdd(356)
		evt.MoveNPC(356, 0)
	end,
	Done = function()
		Party.QBits[788] = true
		evt[0].Subtract("Reputation", 5)
		MF.NPCFollowerRemove(356)
		evt.MoveNPC(356, 941)
		evt.All.Add("Awards", 136)	-- "Killed Wromthrax the Heartless"
	end,
	Texts = {
		Topic = Game.NPCTopic[801],	-- "Crusader"
		Give = Game.NPCText[1012],
		Undone = Game.NPCText[1014],
		Done = Game.NPCText[1013]
	}
}
mm7_generate_promo_quests({QuestNPC = 356, Name = "Crusader", Seq = 1, Slot = 0,
	QBit = 788, Greet = 158, Exp = 15000})

-- Second good
Quest{
	Name = "MM7_Promo_Hero_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[788] end,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1016])
		else
			Message(Game.NPCText[1017])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[803]	-- "Hero"
	}
}
Quest{
	Name = "MM7_Promo_Hero_1",
	Branch = "",
	Slot = 1,
	Quest = 536,
	Exp = 40000,
	CanShow = function() return Party.QBits[788] and Party.QBits[611] end,
	CheckDone = function() return MF.NPCInGroup(393) end,
	Give = function()
		evt.MoveNPC(393, 1158)
	end,
	Done = function()
		Party.QBits[789] = true
		evt[0].Subtract("Reputation", 10)
		MF.NPCFollowerRemove(393)
		evt.MoveNPC(393, 941)
		evt.All.Add("Awards", 137)	-- "Rescued Alice Hargreaves from William's Tower"
	end,
	Texts = {
		Topic = Game.NPCTopic[803],	-- "Hero"
		Give = Game.NPCText[1015],
		Undone = Game.NPCText[1019],
		Done = Game.NPCText[1018]
	}
}
mm7_generate_promo_quests({QuestNPC = 356, Name = "Hero", Seq = 1, Slot = 1,
	QBit = 789, Greet = 161, Exp = 40000})

-- Second evil
QuestNPC = 357	-- William Setag

Quest{
	Name = "MM7_Promo_Villain_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1027])
		elseif not Party.QBits[788] then
			Message(Game.NPCText[1037])
		else
			Message(Game.NPCText[1028])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[806]	-- "Villain"
	}
}
Quest{
	Name = "MM7_Promo_Villain_1",
	Branch = "",
	Slot = 0,
	Quest = 538,
	Exp = 40000,
	Gold = 10000,
	CanShow = function() return Party.QBits[788] and Party.QBits[612] end,
	CheckDone = function() return MF.NPCInGroup(393) end,
	Give = function()
		evt.MoveNPC(393, 1158)
	end,
	Done = function()
		Party.QBits[790] = true
		evt[0].Add("Reputation", 10)
		MF.NPCFollowerRemove(393)
		evt.All.Add("Awards", 138)	-- "Captured Alice Hargreaves from Castle Gryphonheart"
	end,
	Texts = {
		Topic = Game.NPCTopic[806],	-- "Villain"
		Give = Game.NPCText[1026],
		Undone = Game.NPCText[1030],
		Done = Game.NPCText[1029]
	}
}
Quest{
	Name = "MM7_Promo_Villain_1_4",
	Branch = "",
	Slot = 1,
	Texts = {
		Topic = " "
	}
}
mm7_generate_promo_quests({QuestNPC = 357, Name = "Villain", Seq = 1, Slot = 0,
	QBit = 790, Greet = 165, Exp = 40000})

--------------------------------------------
---- Antagarich Monk promotion
-- First
QuestNPC = 377	-- Bartholomew Hume

Quest{
	Name = "MM7_Promo_InitiateMonk_1",
	Branch = "",
	Slot = 0,
	CheckDone = false,
	Quest = 539,
	Texts = {
		Topic = Game.NPCTopic[808],	-- "Initiate Monk"
		Give = Game.NPCText[1031],
		Undone = Game.NPCText[1033]
	}
}
mm7_generate_promo_quests({QuestNPC = 377, Name = "InitiateMonk", Seq = 1, Slot = 0,
	QBit = 791, Exp = 15000})

QuestNPC = 394	-- Bartholomew Hume

Quest{
	Name = "MM7_Promo_InitiateMonk_2",
	BaseName = "MM7_Promo_InitiateMonk_1",
	Branch = "",
	Slot = 0,
	Quest = 539,
	Exp = 15000,
	Done = function()
		Party.QBits[791] = true
		evt.All.Add("Awards", 127)	-- "Found the lost meditation spot in the Dwarven Barrows"
	end,
	Texts = {
		Topic = Game.NPCTopic[808],	-- "Initiate Monk"
		Done = Game.NPCText[1032]
	}
}
Quest{
	Name = "MM7_Promo_InitiateMonk_2_0",
	Branch = "",
	Slot = 1,
	Texts = {
		Topic = " "
	}
}
mm7_generate_promo_quests({QuestNPC = 394, Name = "InitiateMonk", Seq = 2, Slot = 0,
	QBit = 791, Exp = 15000})

-- Second good
QuestNPC = 377	-- Bartholomew Hume

Quest{
	Name = "MM7_Promo_MasterMonk_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[791] end,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1035])
		else
			Message(Game.NPCText[1036])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[811]	-- "Master Monk"
	}
}
Quest{
	Name = "MM7_Promo_MasterMonk_1",
	Branch = "",
	Slot = 1,
	Quest = 540,
	Exp = 40000,
	CanShow = function() return Party.QBits[791] and Party.QBits[611] end,
	CheckDone = function() return Party.QBits[755] end,
	Done = function()
		Party.QBits[792] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 128)	-- "Defeated the High Priest of Baa"
	end,
	Texts = {
		Topic = Game.NPCTopic[811],	-- "Master Monk"
		Give = Game.NPCText[1034],
		Undone = Game.NPCText[1073],
		Done = Game.NPCText[1072]
	}
}
mm7_generate_promo_quests({QuestNPC = 377, Name = "MasterMonk", Seq = 1, Slot = 1,
	QBit = 792, Greet = 167, Exp = 40000})

-- Second evil
QuestNPC = 378	-- Stephan Sand

Quest{
	Name = "MM7_Promo_Ninja_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1076])
		elseif not Party.QBits[791] then
			Message(Game.NPCText[1075])
		else
			Message(Game.NPCText[1077])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[813]	-- "Ninja"
	}
}
Quest{
	Name = "MM7_Promo_Ninja_1",
	Branch = "",
	Slot = 0,
	Quest = 541,
	GivenItem = 1503,
	Exp = 40000,
	CanShow = function() return Party.QBits[791] and Party.QBits[612] end,
	CheckDone = function() return Party.QBits[754] end,
	Give = function()
		Party.QBits[727] = true
	end,
	Undone = function()
		if Party.QBits[569] then
			Message(Game.NPCText[1078])
		else
			Message(Game.NPCText[1079])
		end
	end,
	Done = function()
		Party.QBits[793] = true
		Party.QBits[727] = false
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 129)	-- "Deciphered the code in the School of Sorcery"
	end,
	Texts = {
		Topic = Game.NPCTopic[813],	-- "Ninja"
		Give = Game.NPCText[1074],
		Done = Game.NPCText[1080]
	}
}
mm7_generate_promo_quests({QuestNPC = 378, Name = "Ninja", Seq = 1, Slot = 0,
	QBit = 793, Greet = 170, Exp = 40000})

--------------------------------------------
---- Antagarich Knight promotion
-- First
QuestNPC = 382	-- Frederick Org

Quest{
	Name = "MM7_Promo_Cavalier_1",
	Branch = "",
	Slot = 0,
	Quest = 546,
	Exp = 15000,
	CheckDone = function() return Party.QBits[652] end,
	Done = function()
		Party.QBits[797] = true
		evt[0].Subtract("Reputation", 5)
		evt.All.Add("Awards", 124)	-- "Destroyed all the undead in the Haunted House"
	end,
	Texts = {
		Topic = Game.NPCTopic[823],	-- "Cavalier"
		Give = Game.NPCText[1101],
		Undone = Game.NPCText[1103],
		Done = Game.NPCText[1102]
	}
}
mm7_generate_promo_quests({QuestNPC = 382, Name = "Cavalier", Seq = 1, Slot = 0,
	QBit = 797, Exp = 15000})

-- Second evil
QuestNPC = 382	-- Frederick Org

Quest{
	Name = "MM7_Promo_BlackKnight_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[797] end,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1106])
		else
			Message(Game.NPCText[1105])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[825]	-- "Black Knight"
	}
}
Quest{
	Name = "MM7_Promo_BlackKnight_1",
	Branch = "",
	Slot = 1,
	Quest = 547,
	Exp = 40000,
	CanShow = function() return Party.QBits[797] and Party.QBits[612] end,
	CheckDone = function() return Party.QBits[572] end,
	Done = function()
		Party.QBits[799] = true
		evt[0].Add("Reputation", 10)
		evt.All.Add("Awards", 126)	-- "Robbed the Elven Treasury at Castle Navan"
	end,
	Texts = {
		Topic = Game.NPCTopic[825],	-- "Black Knight"
		Give = Game.NPCText[1104],
		Undone = Game.NPCText[1108],
		Done = Game.NPCText[1107]
	}
}
mm7_generate_promo_quests({QuestNPC = 382, Name = "BlackKnight", Seq = 1, Slot = 1,
	QBit = 799, Greet = 178, Exp = 40000})

-- Second good
QuestNPC = 381	-- Leda Rowan

Quest{
	Name = "MM7_Promo_Templar_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[2727])
		elseif not Party.QBits[797] then
			Message(Game.NPCText[2728])
		else
			Message(Game.NPCText[2726])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[1795]	-- "Templar"
	}
}
Quest{
	Name = "MM7_Promo_Templar_1",
	Branch = "",
	Slot = 0,
	Quest = 545,
	Exp = 40000,
	CanShow = function() return Party.QBits[797] and Party.QBits[611] end,
	CheckDone = function() return Party.ArenaWinsKnight >= 5 end,
	Done = function()
		Party.QBits[798] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 125)	-- "Won five arena challenges for Leda Rowan"
	end,
	Texts = {
		Topic = Game.NPCTopic[1795],	-- "Templar"
		Give = Game.NPCText[2725],
		Undone = Game.NPCText[2730],
		Done = Game.NPCText[2729]
	}
}
mm7_generate_promo_quests({QuestNPC = 381, Name = "Templar", Seq = 1, Slot = 0,
	QBit = 798, Greet = 333, Exp = 40000})

--------------------------------------------
---- Antagarich Ranger promotion
-- First
QuestNPC = 384	-- Ebednezer Sower

Quest{
	Name = "MM7_Promo_Hunter_1",
	Branch = "",
	Slot = 0,
	CheckDone = false,
	Quest = 549,
	Texts = {
		Topic = Game.NPCTopic[829],	-- "Hunter"
		Give = Game.NPCText[1116],
		Undone = Game.NPCText[1117]
	}
}
mm7_generate_promo_quests({QuestNPC = 384, Name = "Hunter", Seq = 1, Slot = 0,
	QBit = 1001, Exp = 15000})

QuestNPC = 391	-- Faerie King

Quest{
	Name = "MM7_Promo_Hunter_2",
	BaseName = "MM7_Promo_Hunter_1",
	Branch = "",
	Slot = 0,
	Quest = 549,
	Exp = 15000,
	CanShow = function() return Party.QBits[549] or Party.QBits[1001] end,
	Done = function()
		Party.QBits[1001] = true
		evt.All.Add("Awards", 130)	-- "Solved the secret to the entrance of the Faerie Mound"
	end,
	Texts = {
		Topic = Game.NPCTopic[833],	-- "Hunter?"
		Done = Game.NPCText[1123]
	}
}
Quest{
	Name = "MM7_Promo_Hunter_2_0",
	Branch = "",
	Slot = 1,
	-- don't hide "Pipes" topic when it should be shown
	CanShow = function() return not evt.All.Cmp("Inventory", 1409) end,
	Texts = {
		Topic = " "
	}
}
mm7_generate_promo_quests({QuestNPC = 391, Name = "Hunter", Seq = 2, Slot = 0,
	QBit = 1001, Exp = 15000})

-- Second evil
QuestNPC = 384	-- Ebednezer Sower

Quest{
	Name = "MM7_Promo_BountyHunter_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[1001] end,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1120])
		else
			Message(Game.NPCText[1119])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[831]	-- "Bounty Hunter"
	}
}
Quest{
	Name = "MM7_Promo_BountyHunter_1",
	Branch = "",
	Slot = 1,
	Quest = 550,
	Exp = 40000,
	CanShow = function() return Party.QBits[1001] and Party.QBits[612] end,
	CheckDone = function() return evt.Cmp("MontersHunted", 50000) end,
	Done = function()
		Party.QBits[1003] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 132)	-- "Collected 10,000 gold worth of bounties from the Bounty Hunts for Ebednezer Sower"
	end,
	Texts = {
		Topic = Game.NPCTopic[831],	-- "Bounty Hunter"
		Give = Game.NPCText[1118],
		Undone = Game.NPCText[1122],
		Done = Game.NPCText[1121]
	}
}
mm7_generate_promo_quests({QuestNPC = 384, Name = "BountyHunter", Seq = 1, Slot = 1,
	QBit = 1003, Greet = 182, Exp = 40000})

-- Second good
QuestNPC = 383	-- Lysander Sweet

Quest{
	Name = "MM7_Promo_RangerLord_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1112])
		elseif not Party.QBits[1001] then
			Message(Game.NPCText[1111])
		else
			Message(Game.NPCText[1110])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[827]	-- "Ranger Lord"
	}
}
Quest{
	Name = "MM7_Promo_RangerLord_1",
	Branch = "",
	Slot = 0,
	Quest = 548,
	Exp = 40000,
	CanShow = function() return Party.QBits[1001] and Party.QBits[611] end,
	CheckDone = function() return Party.QBits[553] end,
	Undone = function()
		if Party.QBits[552] then
			Message(Game.NPCText[1114])
		else
			Message(Game.NPCText[1113])
		end
	end,
	Done = function()
		Party.QBits[1002] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 131)	-- "Calmed the trees in the Tularean Forest"
	end,
	Texts = {
		Topic = Game.NPCTopic[827],	-- "Ranger Lord"
		Give = Game.NPCText[1109],
		Done = Game.NPCText[1115]
	}
}
mm7_generate_promo_quests({QuestNPC = 383, Name = "RangerLord", Seq = 1, Slot = 0,
	QBit = 1002, Greet = 180, Exp = 40000})

--------------------------------------------
---- Antagarich Thief promotion
-- First
QuestNPC = 354	-- William Lasker

Quest{
	Name = "MM7_Promo_Rogue_1",
	Branch = "",
	Slot = 0,
	Quest = 530,
	QuestItem = 1426,	-- Vase
	Exp = 15000,
	Gold = 5000,
	Done = function()
		Party.QBits[785] = true
		evt.All.Add("Awards", 121)	-- "Stole the vase from Lord Markham's estate"
	end,
	Texts = {
		Topic = Game.NPCTopic[794],	-- "Rogue "
		Give = Game.NPCText[993],
		Undone = Game.NPCText[994],
		Done = Game.NPCText[995]
	}
}
Quest{
	Name = "MM7_Promo_Rogue_1_4",
	Branch = "",
	Slot = 2,
	StdTopic = 393
}
Quest{
	Name = "MM7_Promo_Rogue_1_5",
	Branch = "",
	Slot = 3,
	StdTopic = 308
}
mm7_generate_promo_quests({QuestNPC = 354, Name = "Rogue", Seq = 1, Slot = 0,
	QBit = 785, Exp = 15000})

-- Second good
Quest{
	Name = "MM7_Promo_Spy_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[785] end,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[996])
		else
			Message(Game.NPCText[997])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[796]	-- "Spy"
	}
}
Quest{
	Name = "MM7_Promo_Spy_1",
	Branch = "",
	Slot = 1,
	Quest = 531,
	Exp = 40000,
	Gold = 15000,
	CanShow = function() return Party.QBits[785] and Party.QBits[611] end,
	CheckDone = function() return Party.QBits[532] end,
	Undone = function()
		-- FIXME: MM7 had item 999 here
		--if evt.ForPlayer("All").Cmp("Inventory", ..) then Message(Game.NPCText[999]) else
		if Party.QBits[568] then
			Message(Game.NPCText[1000])
		else
			Message(Game.NPCText[1001])
		end
		--end
	end,
	Done = function()
		Party.QBits[786] = true
		evt.All.Add("Awards", 122)	-- "Misplaced weights in Watchtower 6"
	end,
	Texts = {
		Topic = Game.NPCTopic[796],	-- "Spy"
		Give = Game.NPCText[998],
		Done = Game.NPCText[1002]
	}
}
mm7_generate_promo_quests({QuestNPC = 354, Name = "Spy", Seq = 1, Slot = 1,
	QBit = 786, Greet = 154, Exp = 40000})

-- Second evil
QuestNPC = 355	-- Seknit Undershadow

Quest{
	Name = "MM7_Promo_Assassin_1_0",
	Branch = "",
	Slot = 1,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[1006])
		elseif not Party.QBits[785] then
			Message(Game.NPCText[1008])
		else
			Message(Game.NPCText[1007])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[799]	-- "Assassin"
	}
}
Quest{
	Name = "MM7_Promo_Assassin_1",
	Branch = "",
	Slot = 1,
	Quest = 533,
	QuestItem = 1342,	-- Lady Carmine's Dagger
	KeepQuestItem = true,
	Exp = 40000,
	Gold = 15000,
	CanShow = function() return Party.QBits[785] and Party.QBits[612] end,
	Done = function()
		Party.QBits[787] = true
		Party.QBits[725] = false
		evt[0].Add("Reputation", 10)
		evt.All.Add("Awards", 123)	-- "Killed Lady Eleanor Carmine"
	end,
	Texts = {
		Topic = Game.NPCTopic[799],	-- "Assassin"
		Give = Game.NPCText[1005],
		Undone = Game.NPCText[1009],
		Done = Game.NPCText[1010]
	}
}
mm7_generate_promo_quests({QuestNPC = 355, Name = "Assassin", Seq = 1, Slot = 1,
	QBit = 787, Greet = 157, Exp = 40000})

--------------------------------------------
---- Antagarich Wizard promotion
-- First
QuestNPC = 387	-- Thomas Grey

Quest{
	Name = "MM7_Promo_Wizard_1",
	Branch = "",
	Slot = 0,
	Quest = 557,
	Exp = 15000,
	CheckDone = function() return Party.QBits[585] or Party.QBits[586] end,
	Give = function()
		MF.NPCFollowerAdd(395)
		evt.SetNPCGreeting(395, 0)
	end,
	Done = function()
		Party.QBits[1007] = true
		Party.QBits[558] = true
		Party.QBits[731] = false
		Party.QBits[732] = false
		evt.SetNPCGreeting(395, 199)
		--evt[0].Subtract("Reputation", 5)
		evt.All.Add("Awards", 145)	-- "Constructed a Golem"
	end,
	Texts = {
		Topic = Game.NPCTopic[842],	-- "Wizard"
		Give = Game.NPCText[1139],
		Undone = Game.NPCText[205],
		Done = Game.NPCText[1140]
	}
}
mm7_generate_promo_quests({QuestNPC = 387, Name = "Wizard", Seq = 1, Slot = 0,
	QBit = 1007, Exp = 15000})

if MF.GtSettingNum(MM.MM7MagePromo, 0) then
	Quest{
		Name = "MM7_Promo_Wizard_4",
		Branch = "wizard",
		Slot = 2,
		Ungive = function()
			promote_class({Class = const.Class.Mage, Award = CPA.AntagarichMage})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.Mage])
		}
	}
end
if MF.GtSettingNum(MM.MM7NecromancerPromo, 0) then
	Quest{
		Name = "MM7_Promo_Wizard_5",
		Branch = "wizard",
		Slot = 3,
		Ungive = function()
			promote_class({Class = const.Class.Necromancer, Award = CPA.AntagarichNecromancer})
		end,
		Texts = {
			Topic = strformat(TXT.promote_to, Game.ClassNames[const.Class.Necromancer])
		}
	}
end

-- Second good
QuestNPC = 387	-- Thomas Grey

Quest{
	Name = "MM7_Promo_ArchMage_1_0",
	Branch = "",
	Slot = 1,
	CanShow = function() return Party.QBits[1007] end,
	Ungive = function()
		if Party.QBits[612] then
			Message(Game.NPCText[1143])
		else
			Message(Game.NPCText[1142])
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[844]	-- "Archmage"
	}
}
Quest{
	Name = "MM7_Promo_ArchMage_1",
	Branch = "",
	Slot = 1,
	Quest = 559,
	QuestItem = 1289,	-- Divine Intervention
	KeepQuestItem = true,
	Exp = 40000,
	Gold = 10000,
	CanShow = function() return Party.QBits[1007] and Party.QBits[611] end,
	Done = function()
		Party.QBits[1008] = true
		Party.QBits[738] = false
		evt.All.Add("Awards", 146)	-- "Found the Book of Divine Intervention in the Breeding Zone"
	end,
	Texts = {
		Topic = Game.NPCTopic[844],	-- "Archmage"
		Give = Game.NPCText[1141],
		Undone = Game.NPCText[1145],
		Done = Game.NPCText[1144]
	}
}
mm7_generate_promo_quests({QuestNPC = 387, Name = "ArchMage", Seq = 1, Slot = 1,
	QBit = 1008, Greet = 192, Exp = 40000})

-- Second evil
QuestNPC = 388	-- Halfgild Wynac

Quest{
	Name = "MM7_Promo_MasterNecromancer_1_0",
	Branch = "",
	Slot = 0,
	Ungive = function()
		if Party.QBits[611] then
			Message(Game.NPCText[2741])
		elseif not Party.QBits[1007] then
			Message(Game.NPCText[2739])
		else
			Message(Game.NPCText[2740])
		end
	end,
	Texts = {
		Topic = Game.NPCText[2731]	-- "Power Lich"
	}
}
Quest{
	Name = "MM7_Promo_MasterNecromancer_1",
	Branch = "",
	Slot = 0,
	Quest = 560,
	Exp = 40000,
	CanShow = function() return Party.QBits[1007] and Party.QBits[612] end,
	CheckDone = function()
		return evt.All.Cmp("Inventory", 1417)	-- Lich Jar
	end,
	Done = function()
		Party.QBits[1009] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 147)	-- "Retrieved the lich jars from the Proving Grounds"
	end,
	Texts = {
		Topic = Game.NPCText[2731],	-- "Power Lich"
		Give = Game.NPCText[2738],
		Undone = Game.NPCText[2743],
		Done = Game.NPCText[2742]
	}
}
mm_generate_promo_quests_undead({QuestNPC = 388, Name = "MasterNecromancer",
	Name2 = "PowerLich", Ver = 7, Seq = 1, Slot = 0, Slot2 = 0, QBit = 1009,
	RaceFamily = {const.RaceFamily.Undead, const.RaceFamily.Ghost}, Maturity = 2, Greet = 194,
	Exp = 40000, Item = 1417, Sell = Game.ItemsTxt[1417].Value,
	SuccessTxt = 2744, FailTxt = 2743, SellTxt = 2698})

--------------------------------------------
---- Antagarich Technician promotion
-- First
QuestNPC = 782	-- Tallia Ravenswood
local Q = vars.Quests
Quest{
	Name = "MM7_Promo_Engineer_1",
	Branch = "",
	Slot = 0,
	Quest = 866,
	Exp = 15000,
	QuestItem = 966,
	KeepQuestItem = true,
	Done = function()
		Party.QBits[868] = true
		evt[0].Subtract("Reputation", 5)
		evt.All.Add("Awards", 260)	-- "Retrieved Jetpack from Clanker's Lab"
	end,
	Texts = {
		FirstGreet = "Good day, travellers! I am Tallia Ravenwood, a researcher of the Ancients. How can I assist you?",
		GreetGiven = "Welcome, my dear assistants! How is your progress today?",
		GreetDone = "Nice to meet you, Engineers!",
		Topic = "Engineer",	
		Give = "There are many mysteries around the civilization of the Ancients that has populated these lands long before the Silence but the evidence of it is so scarce that many people think the Ancients is just a myth of old. Nonetheless, the archives of the Bracadan Wizards hold the information about the technical wonders from millenias back. Even more so, I've seen and held in my very hands some of the artifacts of the Ancients myself, though most of it was defunct and beyond any repair. So, I'm in search for the pieces of tech that may have survived the ages and misuse to study it and make an attempt to reverse-engineer it. If you are as eager to uncover the veil of mystery of the Ancients as I am, then I'd like to ask you for help. It is rumored that the part of scientifical prowess of the ominous alchemist Clanker is on Ancient's tech behalf. Investigate his abandoned laboratory on the island east of Pierpont and try to find out if the rumors are true. I'll share any knowledge of the Ancients I have if you succeed.",
		Undone = "Hello! Have you found anything there yet? Please, the results of your expedition are crucial for my research.",
		Done = "Ah, you have returned! Let's see what you have here... Looks like this is some sort of device designed for travel by air! And it's almost in mint condition! I could only dream of something like that! Please let me make the blueprints of it and then you can keep it as a reward for your help. And as I've promised, I'll share my knowledge with you and disclose some of the more intricate details to those of you who is an adept of science like myself."
	},
}
Quest{
	Slot = 1,
}
mm7_generate_promo_quests({QuestNPC = 782, Name = "Engineer", Seq = 1, Slot = 0,
	QBit = 868, Exp = 15000})

Quest{
	Slot = 2,
	}
Quest{
	Slot = 2,
	CanShow = || Q.MM7_Promo_Engineer_1 == "Given",  
	Texts = {
		Topic = "Ancient Tech",
		Ungive = "After you finish your task, I'll gladly take from you any sample of the Ancient tech you may find along your journey for an ample reward of 10000 gold per item and a bit of wisdom in my art of the trade. I need more samples to do my research.",
		},
	}
Quest{
	Slot = 2,
	CanShow = || Q.MM7_Promo_Engineer_1 == "Done",
	NeverGiven = true,
	NeverDone = true,
	Gold = 10000,
	Done = function(t)
		evt.Add("Experience", 0)
		evt.Add("SkillPoints",5)
	end,
	QuestItem = {{866, 867, 966, 967, 1666, 1667, 2076, Count = 1},},
	Texts = {
		Topic = "Donate Ancient Tech Samples",
		Done = "Your contribution into my research of the Ancients is invaluable! Please, take this for your help.",
		Undone = "Please, if you find more samples of Ancient tech along your journeys, bring them to me."},
	}


Quest{
	Slot = 4,
	CanShow = || Party:GetCurrentPlayer().Class == 120 or Party:GetCurrentPlayer().Class == 122 or Party:GetCurrentPlayer().Class == 124 or Party:GetCurrentPlayer().Class == 126,
	Texts = {
		Topic = "Tech Repair",
		Ungive = "I can try to repair your Ancient weapons but it would cost you a mere sum of 5000 gold. So, what do you say?",
		},
		NeverGiven = true,
		NeverDone = true,
		Done = function(t)
			local Player = Party:GetCurrentPlayer()
			local WeapSlot = Player.ItemMainHand
			local Weap = Player.Items[WeapSlot]
			if (Weap.Number == 866 or Weap.Number == 867 or Weap.Number == 1666 or Weap.Number == 1667) and Party.Gold >= 5000 and Weap.Broken == true then
				Weap.Broken = false
				evt.Subtract("Gold", 5000)
			end
		end,
	}
Quest{
	Slot = 5,
	Texts = {
		Topic = "Blaster Modifications",
		Ungive = "Did you know that these powerful weapons can be made even more powerful? No? Then I tell you it's absolutely possible. The ores and rare gems found across the land can be used to make modifications to your blasters. A scope for better aim, a focusing lens for more concentrated plasma bursts or a cooling system and barrel hardening to allow more powerful shots with less risk of overheating or breaking the gun.\nThe most valuable and rare ores provide the best results. With enough skill in craftsmanship and repair you will be able to mod your weapon - just apply a piece of ore while holding the blaster in your hand.",
		},
	}
Quest{
	Slot = 5,
	CanShow = || Q.MM7_Promo_Engineer_1 == "Done",
	Texts = {
		Topic = "Jetpacks",
		Ungive = "The device you have recovered in Clanker's lab is called a jetpack. A few old books from Bracadan Wizards' library describe some of these. The power engine of a jetpack usually requires special batteries lasting for a very extended periods of time but the experiments show that the usual Recharge Item potion allows to refill the installed battery to some extent. And I have a theory that the other devices of the Ancients can be recharged in the same fashion. \n\nAnd one more thing about jetpacks - they are calibrated to assist the user in taking a high position with one huge leap but with enough training you might use them to fly. Just watch the charge meter and take care as you may fall hard if the battery runs out midair.",
		},
	}

-- Second good
QuestNPC = 419	-- Resurectra

Quest{
	Name = "MM7_Promo_AncientResearcher_1_0",
	Branch = "",
	Slot = 4,
	CanShow = || Party.QBits[631] and Party.QBits[868],
	Ungive = function()
		if Party.QBits[612] then
			Message("You have made sides with our former allies! Go back to your masters and plead them to teach you. I'm done talking with you.")
		elseif not Party.QBits[868] then
			Message("I see you have a solid will to join us in our search for the Ancients and their knowledge but you are not prepared yet. Please, come back later when you have the proper degree in technical sciences.")
		else
			Message("It is hard to believe that someone from this world would be as educated as yourselves in the art of Ancient engineering, since there's almost nothing left of their tech after the Silence. And you are eager to know more. That's very admirable! And so, I have a task for you that will help you to improve your skills as researchers and to prepare for the dangers the outer worlds may hold.")
		end
	end,
	Texts = {
		Topic = "Ancient Researcher",
	}
}
Quest{
	Name = "MM7_Promo_AncientResearcher_1",
	Branch = "",
	Slot = 4,
	CanShow = || Party.QBits[631] and Party.QBits[868],
	Quest = 869,
	QuestItem = {{964, Count = 1},
				 {965, Count = 1},},	-- Dimensional Scanner, Pathfinder Beacon
	KeepQuestItem = true,	
	RewardItem = 867,
	Exp = 40000,
	Done = function()
		Party.QBits[870] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 261)	-- "Retrieved the Dimensional Scanner and Pathfinder Beacon and returned them to Resurectra"
	end,
	Texts = {
		Topic = "Ancient Researcher",	
		Give = "It is hard to believe that someone from this world would be as educated as yourselves in the art of Ancient engineering, since there's almost nothing left of their tech after the Silence. And you are eager to know more. That's very admirable! And so, I have a task for you that will help you to improve your skills as researchers and to prepare for the dangers the outer worlds may hold. \n\nWe have detected faint signals coming from the two entities located in Erathia and in the Land of the Giants. These entities could be the old teleportational devices of the Ancients. Find them and come back to me. Then I will share my knowledge with you. Good luck!",
		Undone = "I perfectly understand that this task is not an easy one but we need those devices to have an upper hand in our mission. Take your time and prepare well for your expedition. Be wary of dragons and titans in The Land of Giants and take care!",
		Done = "Brilliant! You have succeeded on your quest and we are in your debt. My colleagues are already working on blueprints to make copies of these devices in the future. I'll share my knowledge of the operantional principles for this technology with those of you who are skilled in engineering and show some useful tricks to the others. And please, take this blaster rifle. It should come in handy very soon."
	}
}
mm7_generate_promo_quests({QuestNPC = 419, Name = "AncientResearcher", Seq = 1, Slot = 4,
	QBit = 871, Exp = 40000})

-- Second evil
QuestNPC = 423	-- Kastore

Quest{
	Name = "MM7_Promo_Scientist_1_0",
	Branch = "",
	Slot = 4,
	CanShow = || Party.QBits[630] and Party.QBits[868],
	Ungive = function()
		if Party.QBits[611] then
			Message("Ah, so you've chosen to join with those dreamers we'd used to call our teammates. Get out of my sight and tell you friendies to give up on their futile dreams of the Ancients!")
		else
			Message("Well, well, well... You wish to harness the power of technology as we do and to sharpen your mind so it could cut through the thickest walls? That is certainly possible but it will take some dedication to reach our... common goal. Are you ready to know what's going next?")
		end
	end,
	Texts = {
		Topic = "Scientist"	
	}
}
Quest{
	Name = "MM7_Promo_Scientist_1",
	Branch = "",
	Slot = 4,
	Quest = 872,
	QuestItem = {{964, Count = 1},
				 {965, Count = 1},},	-- The Perfect Bow
	KeepQuestItem = true,
	RewardItem = 867,
	Exp = 40000,
	CanShow = || Party.QBits[630] and Party.QBits[868],
	Done = function()
		Party.QBits[874] = true
		evt[0].Subtract("Reputation", 10)
		evt.All.Add("Awards", 262)	-- "Retrieved the Dimensional Scanner and Pathfinder Beacon and returned them to Kastore"
	end,
	Texts = {
		Topic = "Scientist",
		Give = "Well, well, well... You wish to harness the power of technology as we do and to sharpen your mind so it could cut through the thickest walls? That is certainly possible but it will take some dedication to reach our... common goal. Are you prepared for what's coming next? \n\nThere are certain devices found in this world that will vastly accelerate our progress in completing our plans. These are the teleportational devices of the Ancients. They didn't help their creators as much, as we can see now, but it won't be the case with us. I'll kindly ask you to locate these devices for me in the regions of Erathia and the Land of the Giants, acquire them and bring them back to me. Simplicity itself. And I'll make sure you won't regret the reward when you return.",
		Undone = "What's taking you so long? Just use your firearms to annihilate everything on your way and your brain to seek better. If you have got one, that is.",
		Done = "You have outperformed yourselves! Great job! I've sent the... most talented of our sorcerers and necromancers to make the blueprints of the devices under the watchful eye of my comrades. Talk to them later when they are ready to explain you the working principles of this tech. And oh... I almost forgot! Here's a little extra for your work. Try it and have fun!"
	}
}
mm7_generate_promo_quests({QuestNPC = 423, Name = "Scientist", Seq = 1, Slot = 4,
	QBit = 874, Exp = 40000})

--------------------------------------------
---- 		JADAME PROMOTIONS			----
--------------------------------------------

--------------------------------------------
---- Jadame Sorcerer promotion
Quest{
	NPC = 62, -- Lathean
	Branch = "",
	Slot = 3,
	CanShow 	= function() return evt.ForPlayer("All").Cmp{"ClassIs", CC.Sorcerer}
					or evt.ForPlayer("All").Cmp{"ClassIs", CC.Wizard}
					or evt.ForPlayer("All").Cmp{"ClassIs", CC.Peasant}
			end,
	CheckDone 	= function(t)	Message(t.Texts.Undone)
								return evt.Subtract{"Gold", 10000}	end,
	Done		= function() 
			Promote({CC.Sorcerer, CC.Wizard, CC.Peasant},
					CC.Necromancer,
					{Experience = 15000}, {Experience = 5000})
		end,
	After		= function()
			Promote({CC.Sorcerer, CC.Wizard, CC.Peasant},
					CC.Necromancer, {Experience = 15000})
		end,
	Texts = {	Topic 	= Game.NPCText[2699], -- "Join guild"
				Give 	= Game.NPCText[2700], -- "Well, sorcerers among you seeking for power of dark arts? Pay 10000 bill and step into our chambers."
				Undone	= Game.NPCText[2701], -- "We will not allow any rambler to sneak here. Pay and study or scram!"
				Done	= Game.NPCText[2702], -- "Perfect! Now i call all sorcerers among you necromancers, don't pretend to be good anymore."
				After	= Game.NPCText[2703]} -- "Welcome, necromancers."
	}

--------------------------------------------
---- Jadame Necromancer promotion
QuestNPC = 61	-- Vetrinus Taleshire

Quest{
	Name = "MM8_Promo_MasterNecromancer_1",
	Branch = "",
	Slot = 1,
	Quest = 82,
	QuestItem = 611,
	Exp = 25000,
	Done = function()
		Party.QBits[83] = true
		evt.All.Add("Awards", 85)	-- "Found the Lost Book of Khel"
		if MF.GtSettingNum(MM.MM8ClearLostItBits, 0) then
			Party.QBits[210] = false	-- Lost Book of Kehl - I lost it
		end
		evt.SetNPCTopic(61, 0, 742)	-- "Vetrinus Taleshire" : "Travel with you!"
	end,
	Texts = {
		--Topic = Game.NPCTopic[86],
		Topic = Game.NPCText[2731],	-- "Power Lich"
		Give = Game.NPCText[2732],
		Undone = Game.NPCText[2734],
		Done = Game.NPCText[2735]
	}
}
--[=[
mm8_generate_promo_quests({QuestNPC = 61, Name = "MasterNecromancer", Seq = 1, Slot = 1,
	Slot2 = 1, QBit = 83, RaceFamily = {const.RaceFamily.Undead, const.RaceFamily.Ghost}, Maturity = 2,
	Exp = 10000})
Quest{
	Name = "MM8_Promo_MasterNecromancer_1_4",
	Branch = "masternecromancer",
	Slot = 0,
	Ungive = function()
		local k = MF.GetCurrentPlayer() or 0
		local player = Party[k]
		evt.ForPlayer(k)
		local new_race = can_convert_to_undead(player)
		if new_race == 0 then
			promote_class({Class = CC.MasterNecromancer,
				Award = CPA["JadamePowerLich"],
				Race = player.Attrs.Race, Maturity = 2, Exp = 10000})
			return
		end
		if new_race > 0 then
			if not table.find(MT.ClassPromotionsInv[CC.MasterNecromancer] or {}, player.Class)
					and not player.Class == CC.MasterNecromancer then
				Message(strformat(TXT.cannot_be_promoted,
					Game.ClassNames[player.Class],
					GetClassName({ClassId = CC.MasterNecromancer,
						RaceId = const.Race.UndeadHuman})))
				return
			end
			if not evt.Cmp("Inventory", 628) then	-- "Lich Jar"
				Message(Game.NPCText[2733])
				return
			end
			if not convert_class_race({Class = CC.MasterNecromancer,
					Award = CPA["JadamePowerLich"],
					ToRace = new_race, Maturity = 2, Exp = 10000,
					SameClass = true}) then
				return
			end
			Message(Game.NPCText[2736])
			evt.Subtract("Inventory", 628)	-- "Lich Jar"
			SetLichAppearance(k, player)
		else
			Message(strformat(TXT.cannot_be_converted_to_undead,
				Game.Races[player.Attrs.Race].Name))
		end
	end,
	Texts = {
		Topic = strformat(TXT.promote_to,
			GetClassName({ClassId = CC.MasterNecromancer,
				RaceId = const.Race.UndeadHuman}))
	}
}
]=]
mm_generate_promo_quests_undead({QuestNPC = 61, Name = "MasterNecromancer",
	Name2 = "PowerLich", Ver = 8, Seq = 1, Slot = 1, Slot2 = 0, QBit = 83,
	RaceFamily = {const.RaceFamily.Undead, const.RaceFamily.Ghost}, Maturity = 2,
	Exp = 10000, Item = 628,
	SuccessTxt = 2736, FailTxt = 2733})

QuestNPC = 62	-- Lathean

Quest{
	Name = "MM8_Promo_MasterNecromancer_2",
	Branch = "",
	Slot = 2,
	Texts = {
		Topic = Game.NPCTopic[738],
		Ungive = Game.NPCText[924]	--[[
			"You have not recovered the Lost Book of Kehl!  There will be no promotions
			until you return with the book!  Speak with Vetrinus Taleshire."
			]]
	}
}
--[=[
mm8_generate_promo_quests({QuestNPC = 62, Name = "MasterNecromancer", Seq = 2, Slot = 2,
	Slot2 = 1, QBit = 83, Ungive = 2737,
	RaceFamily = {const.RaceFamily.Undead, const.RaceFamily.Ghost}, Maturity = 2, Exp = 10000})
Quest{
	Name = "MM8_Promo_MasterNecromancer_2_4",
	Branch = "masternecromancer",
	Slot = 0,
	Ungive = function()
		local k = MF.GetCurrentPlayer() or 0
		local player = Party[k]
		evt.ForPlayer(k)
		local new_race = can_convert_to_undead(player)
		if new_race == 0 then
			promote_class({Class = CC.MasterNecromancer,
				Award = CPA["JadamePowerLich"],
				Race = player.Attrs.Race, Maturity = 2, Exp = 10000})
			return
		end
		if new_race > 0 then
			if not table.find(MT.ClassPromotionsInv[CC.MasterNecromancer] or {}, player.Class)
					and not player.Class == CC.MasterNecromancer then
				Message(strformat(TXT.cannot_be_promoted,
					Game.ClassNames[player.Class],
					GetClassName({ClassId = CC.MasterNecromancer,
						RaceId = const.Race.UndeadHuman})))
				return
			end
			if not evt.Cmp("Inventory", 628) then	-- "Lich Jar"
				Message(Game.NPCText[2733])
				return
			end
			if not promote_class({Class = CC.MasterNecromancer,
					Award = CPA["JadamePowerLich"],
					Race = new_race, Maturity = 2, Exp = 10000,
					SameClass = true}) then
				return
			end
			Message(Game.NPCText[2736])
			evt.Subtract("Inventory", 628)	-- "Lich Jar"
			SetLichAppearance(k, player)
		else
			Message(strformat(TXT.cannot_be_converted_to_undead,
				Game.Races[player.Attrs.Race].Name))
		end
	end,
	Texts = {
		Topic = strformat(TXT.promote_to,
			GetClassName({ClassId = CC.MasterNecromancer,
				RaceId = const.Race.UndeadHuman}))
	}
}
]=]
mm_generate_promo_quests_undead({QuestNPC = 62, Name = "MasterNecromancer",
	Name2 = "PowerLich", Ver = 8, Seq = 2, Slot = 2, Slot2 = 0, QBit = 83,
	RaceFamily = {const.RaceFamily.Undead, const.RaceFamily.Ghost}, Maturity = 2,
	Exp = 10000, Item = 628, Ungive = 2737,
	SuccessTxt = 2736, FailTxt = 2733})

if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	Quest{
		Name = "MM8_Promo_Necromancer_1",
		NPC = 56,	-- Avershara
		Branch = "",
		Slot = 0,
		Quest = 296,
		Exp = 25000,
		CheckDone = function()
			return MF.NPCInGroup(53)
		end,
		Done = function()
			Party.QBits[298] = true
			MF.NPCFollowerRemove(53)
			evt.MoveNPC(53, 589)
			evt.All.Add("Awards", 84)	-- "Led Dead Prophetess to Avershara"
		end,
		Texts = {
			Topic = Game.NPCText[2760],
			Give = Game.NPCText[2761],
			Undone = Game.NPCText[2762],
			Done = Game.NPCText[2763]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 56, Name = "Necromancer", Seq = 1, Slot = 0,
		QBit = 298, Exp = 10000})
	Quest{
		Name = "DeadProphetessFollow",
		NPC = 53,	-- Dead Prophetess
		Slot = 0,
		Branch = "",
		CanShow = function()
			return Party.QBits[296] and not MF.NPCInGroup(53)
		end,
		Ungive = function()
			local id = 0
			for k, v in Map.Monsters do
				if v.NPC_ID == 53 then
					id = k
					break
				end
			end
			if id > 0 then
				Map.Monsters[id].AIState = 19
			end
			MF.NPCFollowerAdd(53)
			ExitCurrentScreen(true)
		end,
		Texts = {
			Topic = Game.NPCText[2793]	-- "Follow"
		}
	}
end

--------------------------------------------
---- Jadame Cleric/Priest promotion
QuestNPC = 59	-- Stephen

Quest{
	Name = "MM8_Promo_PriestLight_1",
	Branch = "",
	Slot = 1,
	Quest = 78,
	QuestItem = 626,	-- Prophecies of the Sun
	Exp = 25000,
	Done = function()
		Party.QBits[79] = true
		evt.All.Add("Awards", 81)	-- "Found the lost Prophecies of the Sun and returned them to the Temple of the Sun"
		if MF.GtSettingNum(MM.MM8ClearLostItBits, 0) then
			Party.QBits[218] = false	-- Prophesies of the Sun - I lost it
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[78],
		Give = Game.NPCText[105],
		Undone = Game.NPCText[106],	--[[
		"Have you found this Lair of the Feathered Serpent and the
		Prophecies of the Sun?  Do not waste my time!  The world is
		ending and you waste time with useless conversation!  Return
		to me when you have found the Prophecies and have taken them
		to the Temple of the Sun."
		]]
		Done = Game.NPCText[107]	--[[
		"You have found the lost Prophecies of the Sun?  May the Light
		forever shine upon you and may the Prophet guide your steps.
		With these we may be able to find the answer to what has befallen
		Jadame! "
		]]
	}
}
Quest{
	Name = "MM8_Promo_PriestLight_1_4",
	Branch = "",
	Slot = 0,
	CanShow = function() return Party.QBits[78] end,
	Texts = {
		Topic = Game.NPCTopic[76],
		Ungive = Game.NPCText[119]
	}
}
Quest{
	Name = "MM8_Promo_PriestLight_1_5",
	Branch = "",
	Slot = 2,
	CanShow = function() return Party.QBits[78] end,
	Texts = {
		Topic = Game.NPCTopic[77],
		Ungive = Game.NPCText[104]
	}
}
Quest{
	Name = "MM8_Promo_PriestLight_1_6",
	Branch = "",
	Slot = 3,
	CanShow = function() return Party.QBits[78] end,
	Texts = {
		Topic = Game.NPCTopic[79],
		Ungive = Game.NPCText[118]
	}
}
if not MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	mm8_generate_promo_quests({QuestNPC = 59, Name = "PriestLight", Seq = 1,
		Slot = 1, QBit = 79, From = {CC.Cleric, CC.Priest, CC.ClericLight},
		Ungive = 923, Race = const.Race.Human, Maturity = 2, Exp = 10000})
else
	mm8_generate_promo_quests({QuestNPC = 59, Name = "PriestLight", Seq = 1,
		Slot = 1, QBit = 79,
		Ungive = 923, Race = const.Race.Human, Maturity = 2, Exp = 10000})
	Quest{
		Name = "MM8_Promo_ClericLight_1",
		NPC = 54,	-- Alycon Brinn
		Branch = "",
		Slot = 0,
		Quest = 293,
		Exp = 25000,
		GivenItem = 668,
		CheckDone = function()
			return Party.QBits[294]
		end,
		Done = function()
			Party.QBits[295] = true
			evt.All.Subtract("Inventory", 668)
			evt.All.Add("Awards", 80)	-- "Placed a focusing beacon in Shadowspire"
		end,
		Texts = {
			Topic = Game.NPCText[2756],
			Give = Game.NPCText[2757],
			Undone = Game.NPCText[2758],
			Done = Game.NPCText[2759]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 54, Name = "ClericLight", Seq = 1, Slot = 0,
		QBit = 295, Race = const.Race.Human, Maturity = 1, Exp = 10000})
end

--------------------------------------------
---- Jadame Dark Elf promotion
QuestNPC = 42	-- Cauri Blackthorne

-- "Thank you!"
Game.GlobalEvtLines:RemoveEvent(24)
evt.Global[24] = function()
	evt.SetMessage{26}	--[[
		"Thank you for your assistance with the Basilisk Curse.  Usually I am
		prepared to handle the vile lizards, but this time there were just too
		many of them.The Temple of the Sun asked me to check on a few pilgrims
		that were looking for the Druid Circle of Stone in this area.  When I
		found the first statue, I realized what had happened to the pilgrims.
		I myself did not know of the increase in the number of Basilisks in this
		area.  They seem to be agitated by something.  I was going to investigate
		the Druid Circle of Stone when the Basilisks attacked me."
		]]
	-- See out07.lua, evt.Map[132]
	--[[
	evt.ForPlayer("All")
	evt.Add{"Experience", 25000}
	evt.Add("Awards", 70)	-- "Rescued Cauri Blackthorne."
	Party.QBits[39] = false	-- "Find Cauri Blackthorne then return to Dantillion in Murmurwoods with information of her location."
	Party.QBits[40] = true	-- Found and Rescued Cauri Blackthorne
	Party.QBits[430] = true	-- Roster Character In Party 31
	Game.NPC[42].EventB = 25	-- Cauri Blackthorne : Promotion to Patriarch
	Game.NPC[42].EventC = 1799	-- Cauri Blackthorne : Promotion to Honorary Patriarch
	Game.NPC[39].EventD = 1799	-- Relburn Jeebes : Promotion to Honorary Patriarch
	]]
	evt.SetNPCTopic{NPC = 42, Index = 0, Event = 38}	-- "Cauri Blackthorne" : "Thanks for your help!"
end

mm8_generate_promo_quests({QuestNPC = 42, Name = "Pathfinder", Seq = 1, Slot = 1,
	QBit = 40, Ungive = 27, Race = const.Race.DarkElf, Maturity = 2, Exp = 10000})

QuestNPC = 39	-- Relburn Jeebes

Quest{
	Name = "MM8_Promo_Pathfinder_2",
	Branch = "",
	Slot = 2,
	CanShow = function() return Party.QBits[39] end,
	Texts = {
		Topic = Game.NPCTopic[733],
		Ungive = Game.NPCText[914]
	}
}
mm8_generate_promo_quests({QuestNPC = 39, Name = "Pathfinder", Seq = 2, Slot = 2,
	QBit = 40, Ungive = 915, Race = const.Race.DarkElf, Maturity = 2, Exp = 10000})
-- Hide EventC
Quest{
	Name = "MM8_Promo_Pathfinder_2_4",
	Branch = "pathfinder",
	Slot = 2,
}

if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	QuestNPC = 52	-- Jallije Leafcatcher
	Quest{
		Name = "MM8_Promo_Pioneer_1",
		Branch = "",
		Slot = 0,
		Quest = 1723,
		QuestItem = 670,	-- Blue Wasp Jelly
		Exp = 25000,
		Done = function()
			Party.QBits[1725] = true
			evt.All.Add("Awards", 69)	-- "Delivered a jar of Blue Wasp Jelly"
		end,
		Texts = {
			Topic = Game.NPCText[2764],	-- ""
			Give = Game.NPCText[2765],
			Undone = Game.NPCText[2766],
			Done = Game.NPCText[2767]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 52, Name = "Pioneer", Seq = 1,
		Slot = 0, QBit = 1725, Race = const.Race.DarkElf,
		Maturity = 1, Exp = 10000})
end

--------------------------------------------
---- Jadame Dragon promotion
QuestNPC = 17	-- Deftclaw Redreaver

Quest{
	Name = "MM8_Promo_GreatWyrm_1",
	Branch = "",
	Slot = 1,
	Quest = 74,
	QuestItem = 540,	-- Sword of Whistlebone
	Exp = 25000,
	Give = function()
		if Party.QBits[21] then
			Message(Game.NPCText[76])
		else
			Message(Game.NPCText[75])
		end
	end,
	Undone = function()
		if Party.QBits[75] then
			Message(Game.NPCText[81])	--[[
			"You have killed the Dragon Slayers, but where is the Sword
			of Whistlebone?  Return to me when you have it!"
			]]
		elseif Party.QBits[22] then
			Message(Game.NPCText[77])
		elseif Party.QBits[21] then
			Message(Game.NPCText[78])
		else
			Message(Game.NPCText[86])
		end
	end,
	Done = function()
		Party.QBits[86] = true
		if Party.QBits[21] then
			Message(Game.NPCText[80])	--[[
			"You return to me with the sword of the Slayer, Whistlebone!
			Is there no end to the treachery that you will commit? Is there
			no one that you owe allegiance to?  I will promote those Dragons
			who travel with you to Great Wyrm, however they will never fly
			underneath me!  There rest of your traitorous group will be
			instructed in those skills which can be taught to them!  Go now!
			Never show your face here again, unless you want it eaten!"
			]]
		else
			Message(Game.NPCText[79])	--[[
			"You return to me with the sword of the Slayer, Whistlebone!
			You are indeed worthy of my notice!  The Dragons in your group are
			promoted to Great Wyrm!  I will teach the others of your group what
			skills I can as a reward for their assistance!"
			]]
		end
		if MF.GtSettingNum(MM.MM8ClearLostItBits, 2) then
			Party.QBits[200] = false	-- Sword of Whistlebone - I lost it
		end
		evt.All.Add("Awards", 77)	-- "Gave the Sword of Whistlebone the Slayer to the Deftclaw Redreaver"
	end,
	Texts = {
		Topic = Game.NPCTopic[60],
		TopicGiven = Game.NPCTopic[62]
	}
}
mm8_generate_promo_quests({QuestNPC = 17, Name = "GreatWyrm", Seq = 1, Slot = 1,
	QBit = 86, Ungive = 921, Race = const.Race.Dragon, Maturity = 2, Exp = 10000})

if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	QuestNPC = 255	-- Bazalath

	Quest{
		Name = "MM8_Promo_FlightLeader_1",
		Branch = "",
		Slot = 1,
		Quest = 1720,
		GivenItem = 667,	-- Bazalath's Egg
		Exp = 25000,
		CheckDone = function()
			return Party.QBits[1721] and evt.All.Cmp("Inventory", 667)
		end,
		Done = function()
			Party.QBits[1722] = true
			evt.All.Subtract("Inventory", 667)
			evt.All.Add("Awards", 76)	-- "Infused Bazalath's Egg with the flames' power"
		end,
		Texts = {
			Topic = Game.NPCText[2745],
			Give = Game.NPCText[2746],
			Undone = Game.NPCText[2747],
			Done = Game.NPCText[2748],
		}
	}
	mm8_generate_promo_quests({QuestNPC = 255, Name = "FlightLeader", Seq = 1, Slot = 1,
		QBit = 1722, Race = const.Race.Dragon, Maturity = 1, Exp = 10000})
end

--------------------------------------------
---- Jadame Knight promotions
QuestNPC = 15	-- Sir Charles Quixote

Quest{
	Name = "MM8_Promo_Champion_1",
	Branch = "",
	Slot = 1,
	Quest = 70,
	QuestItem = 539,	-- Ebonest
	Exp = 35000,
	NeverGiven = true,
	CanShow = function() return Party.QBits[73] end,
	Done = function()
		Party.QBits[71] = true
		if Party.QBits[22] then
			Message(Game.NPCText[71])
			--[[
			"What is this?  You ally with my mortal enemies and then seek
			to do me a favor?I wonder what the Dragons think of this. But so
			be it.  I am in your debt for returning Ebonest to me.  I will
			promote any Knights in your party to Champion, however they will
			never be accepted in my service.  The rest I will teach what I can.
			I do not wish to see you again!"
			]]
		else
			Message(Game.NPCText[70])
			--[[
			"You found Blazen Stormlance?  What about MY spear Ebonest?  You
			have that as well?FANTASTIC!I thank you for this and find myself
			in your debt!  I will promote all knights in your party to
			Champion and teach what skills I can to the rest of your party. "
			]]
		end
		if MF.GtSettingNum(MM.MM8ClearLostItBits, 2) then
			Party.QBits[199] = false	-- Ebonest - I lost it
		end
		evt.All.Add("Awards", 74)	-- "Returned Ebonest to Charles Quixote"
	end,
	Texts = {
		Topic = Game.NPCTopic[58],	-- "Promotion to Champion"
		Undone = Game.NPCText[85]
			--[[
			"You have found Blazen Stormlance? But where is Ebonest?
			Return to me when you have the spear and you will be promoted!"
			]]
	}
}
mm8_generate_promo_quests({QuestNPC = 15, Name = "Champion", Seq = 1, Slot = 1,
	QBit = 71, Ungive = 919, From = MF.GtSettingNum(MM.MM8EnableTier1Promo, 0)
		and 0 or {CC.Knight, CC.Cavalier},
	Race = const.Race.Human, Maturity = 2, Exp = 15000})
Quest{
	Name = "MM8_Promo_Champion_1_4",
	Branch = "",
	Slot = 2,
	CanShow = function() return not Party.QBits[71] end,
	Texts = {
		Topic = Game.NPCTopic[56],	-- "Stormlance"
		Ungive = Game.NPCText[66]
	}
}
Quest{
	Name = "MM8_Promo_Champion_1_5",
	Branch = "",
	Slot = 3,
	CanShow = function() return not Party.QBits[71] end,
	Texts = {
		Topic = Game.NPCTopic[57],	-- "Ebonest"
		Ungive = Game.NPCText[67]
	}
}

QuestNPC = 51	-- Garret Deverro

if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	Quest{
		Name = "MM8_Promo_Cavalier_1",
		Branch = "",
		Slot = 0,
		Quest = 290,
		QuestItem = 544,	-- Sword-out-of-the-Stone
		KeepQuestItem = true,
		Exp = 25000,
		Done = function()
			Party.QBits[292] = true
			evt.All.Add("Awards", 73)	-- "Pulled out a sword from a stone"
		end,
		Texts = {
			Topic = Game.NPCTopic[735],	-- "Promote Knights"
			Give = Game.NPCText[2722],
			--[[
			"So you're looking to become a Cavalier? I hear you, but you
			need to prove your worth to me first. There will come a time
			for combat and glory, but it would be unwise to rush your
			enemies without a proper blade. There is a rock somewhere in
			the Ravage Roaming, in which a sword is stuck - a nod to a
			tradition of old. Partake in the old custom and try to take
			the sword out. If you succeed, bring it back to me as proof
			and you shall be granted the title of a Cavalier."
			]]
			Undone = Game.NPCText[2723],
			--[[
			"Having trouble finding the rock in that pile of rocks to the
			south? Or was the rock stronger than you? Consider drinking
			some good brew. There are no rules. There's only victory.
			Or defeat, I suppose."
			]]
			Done = Game.NPCText[2724]
			--[[
			"Well, well, well! Look who strolls in wielding the beautiful
			blade! I can see from your bulging muscles you deserve both
			the blade, and the promotion. Be well, Cavalier, and may the
			blade serve you in the battles to come."
			]]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 51, Name = "Cavalier", Seq = 1, Slot = 0,
		QBit = 292, Race = const.Race.Human, Maturity = 1, Exp = 10000})
	Quest{
		Name = "MM8_Promo_Champion_2",
		Branch = "",
		Slot = 1,
		Texts = {
			Topic = Game.NPCTopic[58],	-- "Promotion to Champion"
			Ungive = Game.NPCText[918]
			--[[
			"You cannot be promoted to Champion until you have proven yourself worthy!"
			]]
		}
	}
end

mm8_generate_promo_quests({QuestNPC = 51, Name = "Champion", Seq = 2, Slot = 1,
	QBit = 71, Ungive = 919, From = MF.GtSettingNum(MM.MM8EnableTier1Promo, 0)
		and 0 or {CC.Knight, CC.Cavalier},
	Race = const.Race.Human, Maturity = 2, Exp = 15000})

--------------------------------------------
---- Jadame Minotaur promotion
QuestNPC = 58	-- Tessalar

Quest{
	Name = "MM8_Promo_MinotaurLord_1",
	Branch = "",
	Slot = 0,
	Quest = 76,
	QuestItem = {541, 732},	-- Axe of Balthazar, Certificate of Authentication
	Exp = 25000,
	Undone = function()
		if not evt.Cmp("Inventory", 541) then
			Message(Game.NPCText[98])	--[[
			"Where is Balthazar's Axe?  You waste my time!
			Find the axe, find Dadeross and return to me!"
			]]
		else
			Message(Game.NPCText[94])	--[[
			"You have found the Axe of Balthazar!  Have you presented it
			to Dadeross?  Without his authentication, we can not proceed
			with the Rite’s of Purity!  Find him and return to us once
			you have presented him with the axe!"
			]]
		end
	end,
	Done = function()
		Party.QBits[77] = true	-- Found the Axe of Balthazar.
		Message(Game.NPCText[95])	--[[
			"You have found the Axe of Balthazar!  Have you presented it to
			Dadeross? Ah, you have authentication from Dadeross!  The Rite’s
			of Purity will begin immediately! You proven yourselves worthy, and
			our now members of our herd!  The Minotaurs who travel with you are
			promoted to Minotaur Lord.  The others in your group will be taught
			what skills we have that maybe useful to them."
			]]
		evt.All.Add("Awards", 79)	-- "Recovered Axe of Balthazar"
		if MF.GtSettingNum(MM.MM8ClearLostItBits, 2) then
			Party.QBits[201] = false	-- Axe of Baltahzar - I lost it
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[69],
		TopicGiven = Game.NPCTopic[73],	-- Used by Dadeross
		Give = Game.NPCText[92],
	}
}
mm8_generate_promo_quests({QuestNPC = 58, Name = "MinotaurLord", Seq = 1, Slot = 0,
	QBit = 77, Ungive = 929, Race = const.Race.Minotaur, Maturity = 2, Exp = 10000})

if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	-- Note: QBit 1730 isn't used but preserved for possible variant
	--   where you have to return to Ferris to complete the quest
	Quest{
		Name = "MM8_Promo_MinotaurHeadsman_1",
		NPC = 322,	-- Ferris
		Branch = "",
		Slot = 1,
		Quest = 1729,
		CanShow = function() return not Party.QBits[1731] end,
		GivenItem = 669,	-- Letter to Ninegos
		CheckDone = false,
		Texts = {
			Topic = Game.NPCText[2772],	-- "Minotaur Headsman"
			Give = Game.NPCText[2773],
			Undone = Game.NPCText[2774]
		}
	}
	Quest{
		Name = "MM8_Promo_MinotaurHeadsman_2",
		BaseName = "MM8_Promo_MinotaurHeadsman_1",
		NPC = 55,	-- Ninegos
		CanShow = function() return Party.QBits[1729] end,
		QuestItem = 669,	-- Letter to Ninegos
		Exp = 25000,
		Done = function()
			Party.QBits[1729] = false
			Party.QBits[1731] = true
			Game.NPC[55].House = 625
			evt.All.Add("Awards", 78)	-- "Delivered letter to Ninegos"
		end,
		Texts = {
			Topic = Game.NPCText[2796],	-- "Letter from Ferris"
			Done = Game.NPCText[2775]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 55, Name = "MinotaurHeadsman", Seq = 1, Slot = 0,
		QBit = 1731, Race = const.Race.Minotaur, Maturity = 1, Exp = 10000})
end

--------------------------------------------
---- Jadame Barbarian/Troll promotions
QuestNPC = 43	-- Volog Sandwind

Quest{
	Name = "MM8_Promo_" .. (MF.GtSettingNum(MM.MM8EnableTier1Promo, 0)
			and "Berserker" or "Warmonger") .. "_1",
	Branch = "",
	Slot = 1,
	Quest = 68,
	Exp = 25000,
	CheckDone = function() return Party.QBits[69] end,
	Done = function()
		Party.QBits[87] = true
		evt.All.Add("Awards", 71)	-- "Found Troll Homeland"
		evt.SetNPCTopic(43, 0, 612)	-- "Volog Sandwind" : "Roster Join Event"
	end,
	Texts = {
		Topic = Game.NPCTopic[35],	-- Quest
		Give = MF.GtSettingNum(MM.MM8EnableTier1Promo, 0)
				and Game.NPCText[2715] or Game.NPCText[43],
			--[[
			"Perhaps if you could locate our previous homeland, and check
			to see if the Curse of the Stone still exists.
			If it does perhaps there is a way to remove it.
			Any Barbarian in your party who completes this task would be
			promoted to Berserker of our Clan. Many honors are bestowed
			with this title, and you would be forever known to us as a
			legendary hero.One of our warriors, Dartin Dunewalker, set
			out to find this place.
			He left thinking he would find clues among the stone fields
			of Ravage Roaming.
			Perhaps you can find him there and work together--or at the
			least, find clues that will lead you to our goal."
			]]
		Undone = Game.NPCText[49],
			--[[
			"Have you found the Ancient Home for our Clan?
			Without its location, my people will surely perish!"
			]]
		Done = MF.GtSettingNum(MM.MM8EnableTier1Promo, 0)
				and Game.NPCText[2716] or Game.NPCText[45]
			--[[
			"You have found our Ancient Home?  Its located in the western area
			of the Murmurwoods?  This is wonderful news.  Perhaps there is still
			time to move my people.  Unfortunately the Elemental threat must be
			dealt with first, or no people will be safe! All Barbarians among you
			have been promoted to Berserker, and their names will be forever
			remembered in our songs.  I will teach the rest of you what skills
			I can, perhaps it will be enough to help you save all of Jadame."
			]]
	}
}
Quest{
	Name = "MM8_Promo_" .. (MF.GtSettingNum(MM.MM8EnableTier1Promo, 0)
			and "Berserker" or "Warmonger") .. "_1_4",
	Branch = "",
	Slot = 2,
	CanShow = function() return Party.QBits[87] end,
	Texts = {
		Topic = Game.NPCTopic[39],	-- Thanks for your help!
		Ungive = Game.NPCText[48]
			--[[
			"Thanks for finding our Ancient Home, once the treat
			to Jadame has been handled we can begin to move there!"
			]]
	}
}
if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	mm8_generate_promo_quests({QuestNPC = 43, Name = "Berserker", Seq = 1,
		Slot = 1, QBit = 87, Race = const.Race.Troll, Maturity = 1,
		Exp = MM.MM8Promo1ExpReward})

	QuestNPC = 67	-- Hobb Sandwind

	mm8_generate_promo_quests({QuestNPC = 67, Name = "Berserker", Seq = 2,
		Slot = 0, QBit = 87, Ungive = 2717, Race = const.Race.Troll,
		Maturity = 1, Exp = MM.MM8Promo1ExpReward})
	Quest{
		Name = "MM8_Promo_Warmonger_1",
		Branch = "",
		Slot = 1,
		Quest = 287,
		Exp = 25000,
		CanShow = function() return Party.QBits[87] end,
		CheckDone = function() return Party.QBits[288] end,
		Done = function()
			Party.QBits[289] = true
			evt.All.Add("Awards", 72)	-- "Removed basilisks from the Ancient Troll Home"
		end,
		Texts = {
			Topic = Game.NPCText[2718],	-- "Warmonger"
			Give = Game.NPCText[2719],
				--[[
				"Can you please clear Ancient Troll Home from these
				nasty Basilisks? All Berserkers in your party will
				be promoted to Warmonger.",
				]]
			Undone = Game.NPCText[2720],
				--[[
				"If you ever want to be considered Warmonger candidate
				you should have no problem with ordinary Basilisks.
				Come back after you finish them.",
				]]
			Done = Game.NPCText[2721]
				--[[
				"So those Basilisks are no longer a threat? Great news!
				All Berserkers among you have been promoted to Warmonger."
				]]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 67, Name = "Warmonger", Seq = 1,
		Slot = 1, QBit = 289, Race = const.Race.Troll, Maturity = 2,
		Exp = 10000})
else
	mm8_generate_promo_quests({QuestNPC = 43, Name = "Warmonger", Seq = 1,
		Slot = 1, QBit = 87, Race = const.Race.Troll, Maturity = 2,
		Exp = 10000})
	mm8_generate_promo_quests({QuestNPC = 67, Name = "Warmonger", Seq = 2,
		Slot = 0, QBit = 87, Ungive = 917, Race = const.Race.Troll,
		Maturity = 2, Exp = 10000})
end

--------------------------------------------
---- Jadame Vampire promotion
QuestNPC = 62	-- Lathean

Quest{
	Name = "MM8_Promo_Nosferatu_1",
	Branch = "",
	Slot = 1,
	Quest = 80,
	QuestItem = {627, 612},
	Exp = 25000,
	Undone = function()
		if evt.All.Cmp("Inventory", 627) then
			Message(Game.NPCText[111])
		elseif evt.All.Cmp("Inventory", 612) then
			Message(Game.NPCText[112])
		else
			Message(Game.NPCText[151])
		end
	end,
	Done = function()
		Party.QBits[88] = true
		evt.All.Add("Awards", 83)	-- "Found the Sarcophagus and Remains of Korbu"
		if MF.GtSettingNum(MM.MM8ClearLostItBits, 0) then
			Party.QBits[211] = false	-- Sarcophagus of Korbu - I lost it
			Party.QBits[219] = false	-- Remains of Korbu - I lost it
		end
	end,
	Texts = {
		Topic = Game.NPCTopic[83],
		TopicGiven = Game.NPCTopic[90],	-- "Return of Korbu"
		Give = Game.NPCText[110],
		Done = Game.NPCText[117]
	}
}
mm8_generate_promo_quests({QuestNPC = 62, Name = "Nosferatu", Seq = 1, Slot = 1,
	QBit = 88, 
	RaceFamily = {const.RaceFamily.Vampire}, Maturity = 2,
	Exp = MM.MM8Promo1ExpReward})
-- Hide EventC
Quest{
	Name = "MM8_Promo_Nosferatu_1_4",
	Branch = "nosferatu",
	Slot = 2,
}

if MF.GtSettingNum(MM.MM8EnableTier1Promo, 0) then
	QuestNPC = 1226
	Quest{
		Name = "MM8_Promo_ElderVampire_1",
		Branch = "",
		Slot = 0,
		Quest = 1726,
		QuestItem = 671,	-- Vial of Hermit Troll Blood
		Exp = 25000,
		Done = function()
			Party.QBits[1728] = true
			evt.All.Add("Awards", 82)	-- "Brought a vial of the hermit troll blood"
		end,
		Texts = {
			Topic = Game.NPCText[2768],	-- "Elder Vampire"
			Give = Game.NPCText[2769],
			Undone = Game.NPCText[2770],
			Done = Game.NPCText[2771]
		}
	}
	mm8_generate_promo_quests({QuestNPC = 1226, Name = "ElderVampire", Seq = 1,
		Slot = 0, QBit = 1728, RaceFamily = {const.RaceFamily.Vampire},
		Maturity = 1, Exp = 10000})
end

--------------------------------------------
---- 		PEASANT PROMOTIONS			----
--------------------------------------------

-- SkillId = Class
-- Teachers will also promote peasants to class assigned to skill.
local TeacherPromoters = {

	[0] = CC.Monk,	-- Staff = Monk
	[1] = CC.Knight,	-- Sword = Knight
	[2] = CC.Thief,	-- Dagger = Thief
	--[3] = CC.Ranger	-- Axe = Ranger
	[4] = CC.Knight,	-- Spear = Knight
	[5] = CC.Archer,	-- Bow = Archer
	[6] = CC.Cleric,	-- Mace = Cleric
	[7] = CC.Technician,-- Blaster = Technician
	[8] = CC.Paladin,	-- Shield = Paladin
	[9] = CC.Thief,	-- Leather = Thief
	[10] = CC.Archer,	-- Chain = Archer
	[11] = CC.Paladin,	-- Plate = Paladin
	[12] = CC.Sorcerer, 	-- Fire = Sorcerer
	[13] = CC.Sorcerer,	-- Air = Sorcerer
	[14] = CC.Druid,	-- Water = Druid
	[15] = CC.Druid,	-- Earth = Druid
	[16] = CC.Paladin,	-- Spirit = Paladin
	[17] = CC.Druid,	-- Mind = Druid
	[18] = CC.Cleric,	-- Body = Cleric
	[19] = CC.Cleric,	-- Light = Cleric
	[20] = CC.Sorcerer,	-- Dark = Sorcerer
	[21] = CC.Deerslayer,	-- Dark elf
	[22] = CC.Vampire,	-- Vampire
	[23] = nil,
	[24] = CC.Thief,	-- ItemId = Thief
	[25] = CC.Thief,	-- Merchant = Thief
	[26] = CC.Knight,	-- Repair = Knight
	[27] = CC.Knight,	-- Bodybuilding = Knight
	[28] = CC.Druid,	-- Meditation = Druid
	[29] = CC.Archer,	-- Perception = Archer
	[30] = nil,
	[31] = CC.Thief,	-- Disarm = Thief
	[32] = CC.Monk,	-- Dodging = Monk
	[33] = CC.Monk, 	-- Unarmed = Monk
	[34] = CC.Ranger,	-- Mon Id = Ranger
	[35] = CC.Ranger,	-- Arms = Ranger
	[36] = CC.Thief,	-- Stealing = Thief
	[37] = CC.Druid,	-- Alchemy = Druid
	[38] = CC.Sorcerer	-- Learning = Sorcerer

}

local PeasantPromoteTopic = 1721
NPCFollowers.PeasantPromoteTopic = PeasantPromoteTopic

local function PromotePeasant(To)

	evt.ForPlayer("Current")
	if not evt.Cmp{"ClassIs", CC.Peasant} then
		return false
	end

	evt.Set{"ClassIs", To}
	evt.Add{"Experience", 5000}

	if To == CC.Vampire or To == CC.Nosferatu then
		local cChar = Party[Game.CurrentPlayer]
		local Gender = Game.CharacterPortraits[cChar.Face].DefSex
		local NewFace = 12 + math.random(0,1)*2 + Gender

		cChar.Face = NewFace
		SetCharFace(Game.CurrentPlayer, NewFace)
		cChar.Skills[const.Skills.VampireAbility] = 1
		cChar.Spells[111] = true

		local new_race = table.filter(Game.Races, 0,
			"BaseRace", "=", Game.Races[cChar.Attrs.Race].BaseRace,
			"Family", "=", const.RaceFamily.Vampire
			)[1].Id
		if new_race and new_race >= 0 then
			cChar.Attrs.Race = new_race
			cChar.Attrs.Maturity = 0
		end

	elseif To == CC.Deerslayer then
		local cChar = Party[Game.CurrentPlayer]
		cChar.Skills[const.Skills.DarkElfAbility] = 1
		cChar.Spells[100] = true

	end

	return true

end

local function CheckRace(To)

	local cChar = Party[Game.CurrentPlayer]
	local cRace = GetCharRace(cChar)
	local Races = const.Race

	if To == CC.Vampire and
		(cRace == Races.Human or cRace == Races.Elf or cRace == Races.DarkElf or cRace == Races.Goblin) then

		return true
	end

	local T = Game.CharSelection.ClassByRace[cRace]
	if T then
		return T[To]
	end

	return false

end

local CurPeasantPromClass
local RestrictedTeachers = {427, 418}
function events.EnterNPC(i)
	local cNPC = Game.NPC[i]
	for i = 0, 4 do
		if cNPC.Events[i] == PeasantPromoteTopic then
			cNPC.Events[i] = 0
		end
	end

	if table.find(RestrictedTeachers, i) then
		return
	end

	if MF.CheckClassInParty(CC.Peasant) then
		local ClassId
		local cEvent
		for Eid = 0, 5 do
			cEvent = cNPC.Events[Eid]
			local TTopic = Game.TeacherTopics[cEvent]
			if TTopic and TeacherPromoters[TTopic.SId] then
				ClassId = TeacherPromoters[TTopic.SId]
			end
		end

		if not ClassId then
			return
		end

		CurPeasantPromClass = ClassId

		for i = 0, 4 do
			if cNPC.Events[i] == 0 then
				cEvent = i
				break
			end
		end

		if not cEvent then
			return
		end

		cNPC.Events[cEvent] = PeasantPromoteTopic
		Game.NPCTopic[PeasantPromoteTopic] = string.format(Game.NPCText[1676], Game.ClassNames[ClassId])
	end

end

local PeasantLastClick = 0
evt.Global[PeasantPromoteTopic] = function()
	if Game.CurrentPlayer < 0 then
		return
	end

	local ClassId = CurPeasantPromClass

	if not CheckRace(ClassId) then
		Message(string.format(Game.NPCText[1679], Game.ClassNames[ClassId]))
		return
	end

	if PeasantLastClick + 2 > os.time() then
		PeasantLastClick = 0
		if PromotePeasant(ClassId) then
			Message(string.format(Game.NPCText[1678], Game.ClassNames[ClassId]))
		end
	else
		PeasantLastClick = os.time()
		Message(string.format(Game.NPCText[1677], Game.ClassNames[ClassId]))
	end
end

--------------------------------------------
---- 	ELF/VAMPIRE/DRAGON TEACHERS		----
--------------------------------------------

local LastLearnClick = 0
local LastTeacherSkill
local LearnSkillTopic = 1674
local SkillsToLearnFromTeachers = {21,22,23}

local function PartyCanLearn(skill)
	for _,pl in Party do
		if pl.Skills[skill] == 0 and GetMaxAvailableSkill(pl, skill) > 0 then
			return true
		end
	end
	return false
end

evt.Global[LearnSkillTopic] = function()
	if Game.CurrentPlayer < 0 then
		return
	end

	local Player = Party[Game.CurrentPlayer]
	local Skill = LastTeacherSkill
	local cNPC = Game.NPC[GetCurrentNPC()]

	if not Skill then
		return
	end

	if Player.Skills[Skill] > 0 then
		Message(string.format(Game.GlobalTxt[403], Game.SkillNames[Skill]))
	elseif GetMaxAvailableSkill(Player, Skill) == 0 then
		Message(string.format(Game.GlobalTxt[632],
				GetClassName({ClassId = Player.Class, RaceId = Player.Attrs.Race})))
	elseif Party.Gold < 500 then
		Message(Game.GlobalTxt[155])
	elseif GetMaxAvailableSkill(Player, Skill) > 0 and Player.Skills[Skill] == 0 then
		evt[Game.CurrentPlayer].Add{"Experience", 0} -- animation
		Player.Skills[Skill] = 1

		for i = 9, 11 do
			local CurS, CurM = SplitSkill(Player.Skills[i+12])
			for iL = 1 + i*11, CurM + i*11 do
				Player.Spells[iL] = true
			end
		end

		evt[Game.CurrentPlayer].Subtract{"Gold", 500}
		Message(Game.GlobalTxt[569])
	end
end

function events.EnterNPC(i)

	LastTeacherSkill = nil

	local TTopic
	local cNPC = Game.NPC[i]
	for Eid = 0, 5 do
		TTopic = Game.TeacherTopics[cNPC.Events[Eid]]
		if TTopic then
			LastTeacherSkill = TTopic.SId
			break
		end
	end

	if not table.find(SkillsToLearnFromTeachers, LastTeacherSkill) then
		return
	end

	if LastTeacherSkill and PartyCanLearn(LastTeacherSkill) then
		local str = Game.GlobalTxt[534]
		str = string.replace(str, "%lu", "500")
		str = string.format(str, Game.GlobalTxt[431], Game.SkillNames[LastTeacherSkill], "")

		Game.NPCTopic[LearnSkillTopic] = str
		cNPC.Events[NPCFollowers.FindFreeEvent(cNPC, LearnSkillTopic)] = LearnSkillTopic
	else
		NPCFollowers.ClearEvents(cNPC, {LearnSkillTopic})
	end

end

MF.LogInit2(LogId)

