--[[
	MMMWE_WarlockPeace.lua — peace talks with the Warlocks of Thunderfist Mountain (25.11.26)

	MM7's unused history entry 19 ("my lords were able to make a deal with the Warlocks to
	obtain the soul jars without a fight") had no quest behind it. Now:

	  Maximus (the Pit, quest "Soul Jars", QBit 636) gives a sealed offer (the unused Sealed
	    Letter 2, item 1410) to carry to Thunderfist Mountain.
	  A warlock envoy meets the party at the two cave entrances nearest the town in Mount
	    Nighon (out10 events 501 and 505, Maps/out10.lua).
	  The warlocks deal only with those who did them some good:
	    Haldar's remains brought home (Award 151),
	    a Warlock promotion, true or honorary (QBit 1012, Awards 1617/1618),
	    Morcarack slain (MMMWE_BossQuests.lua).
	  Otherwise they refuse, and the jars have to be taken by force, as before.
	  The price: gold, or a favour (clearing the Eyes - Beholders - out of Thunderfist).
	  The deal gives the Case of Soul Jars (1404), takes it out of the chest in Thunderfist,
	    and makes the warlocks there peaceful. Attacking one breaks the peace.
	  Brought to Maximus, the jars then go down in the history as entry 19 instead of 18.

	vars.MMMWE_WarlockPeace.State: nil, "Offered", "Refused", "Terms", "Favour", "Peace", "Broken"
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text

local WP = {
	Maximus = 424,
	Envoy = 717,         -- "Contest Winner 7", an empty NPC row
	EnvoyPic = 472,
	Offer = 1410,        -- Sealed Letter 2, unused
	Jars = 1404,         -- Case of Soul Jars
	QuestBit = 636,      -- Maximus: retrieve the soul jars
	GotJarsBit = 661,    -- "Got Lich Jar from Thunderfist Mountain"
	LostJarsBit = 743,   -- "Lich Jar Case - I lost it"
	Price = 10000,
	Map = "7d07.blv",
	Warlocks = {[418] = true, [419] = true, [420] = true},
	Eyes = {[211] = true, [212] = true, [213] = true},
	HistoryForce = 18, HistoryDeal = 19,
}
MF.WarlockPeace = WP

local function st()
	vars.MMMWE_WarlockPeace = vars.MMMWE_WarlockPeace or {}
	return vars.MMMWE_WarlockPeace
end

local function state() return st().State end
local function setState(s) st().State = s end

local function inThunderfist() return (Map.Name or ""):lower() == WP.Map end

local function hasItem(n) return TakeItemFromParty(n, true) end

local function anyAward(...)
	for _, pl in Party.PlayersArray do
		for _, a in ipairs{...} do
			if pl.Awards[a] then return true end
		end
	end
	return false
end

-- what the party did for the warlocks
local function goodDeeds()
	local list = {}
	if anyAward(151) then
		list[#list + 1] = Tx"You brought Haldar home from the Maze to his brother."
	end
	if Party.QBits[1012] or anyAward(1617, 1618) then
		list[#list + 1] = Tx"One of you wears the robes of a Warlock."
	end
	if vars.Quests and vars.Quests["MMMWE_Boss_Morcarack"] == "Done" then
		list[#list + 1] = Tx"You slew Morcarack, who burned our ship to the waterline."
	end
	return list
end

local function questOpen()
	return Party.QBits[WP.QuestBit] and not Party.QBits[WP.GotJarsBit] and not hasItem(WP.Jars)
end

---------------------------------------------------------------------------
-- the sealed offer
---------------------------------------------------------------------------

-- set again on each map load, after any table localization
local function nameOffer()
	local it = Game.ItemsTxt[WP.Offer]
	local name, notes = Tx"Sealed Offer of the Pit", Tx"A letter under Maximus's seal, offering the Warlocks of Thunderfist Mountain a deal for their soul jars."
	if it.Name ~= name then it.Name = name end
	if it.Notes ~= notes then it.Notes = notes end
end
events.GameInitialized2 = nameOffer
events.LoadMap = nameOffer

local function giveOffer()
	evt.Add("Inventory", WP.Offer)
end

Quest{
	Name = "MMMWE_WarlockPeace_Offer",
	NPC = WP.Maximus,
	Slot = 1,
	Quest = false,
	CanShow = function()
		local s = state()
		return questOpen() and (s == nil or s == "Offered" or s == "Terms" or s == "Favour")
	end,
	Execute = function(t)
		local s = state()
		if s == nil then
			setState("Offered")
			giveOffer()
			Message(Tx"Archibald would rather we didn't start a war with Nighon over a few jars, and for once I agree with him: dead warlocks make no jars. Take this letter to Thunderfist Mountain. It carries my seal and my terms. The warlocks watch their caves; show it at the entrances near their town and someone will come out to talk.\n\nThey won't deal with just anyone, mind. If they turn you away, you know what to do.")
		elseif s == "Offered" and not hasItem(WP.Offer) then
			giveOffer()
			Message(Tx"You lost my letter? Here's another. Try to keep this one until it reaches the warlocks.")
		elseif s == "Offered" then
			Message(Tx"You still have my letter. Thunderfist Mountain, the caves near the warlocks' town. Go.")
		else
			Message(Tx"The warlocks have named their price? Then pay it, one way or another. I want those jars, not a report on the haggling.")
		end
	end,
	Texts = {Topic = Tx"Peace with the Warlocks"},
}

---------------------------------------------------------------------------
-- the envoy
---------------------------------------------------------------------------

local function eyesCleared() return st().EyesLeft == 0 end

local function envoyWaits()
	local s = state()
	if not questOpen() then return false end
	if s == "Offered" then return hasItem(WP.Offer) end
	return s == "Terms" or s == "Favour" and eyesCleared()
end

local function makeDeal(text)
	setState("Peace")
	st().Deal = true
	TakeItemFromParty(WP.Offer)
	evt.Add("Inventory", WP.Jars)
	Party.QBits[WP.GotJarsBit] = true
	Party.QBits[WP.LostJarsBit] = true
	Message(text .. "\n\n" .. Tx"[The envoy hands you a heavy case] The jars, as agreed. Tell Maximus the price will not be this low again. And tell him the warlocks keep their word as long as others keep theirs. You may walk in Thunderfist Mountain in peace.")
end

Greeting{
	Name = "MMMWE_WarlockPeace_EnvoyGreet",
	NPC = WP.Envoy,
	GetGreeting = function()
		local s = state()
		if s == "Offered" then
			return Tx"A figure in dark robes steps out of the cave mouth, eyes glowing red under the hood. \"You carry the seal of the Pit. Speak your business, and be quick.\""
		elseif s == "Terms" then
			return Tx"\"Back again. Have you brought the price?\""
		elseif s == "Favour" then
			return Tx"\"The Eyes no longer stir in the deep halls. We felt it. The masters are pleased.\""
		end
		return Tx"\"The masters have nothing more to say to you.\""
	end,
}

Quest{
	Name = "MMMWE_WarlockPeace_Letter",
	NPC = WP.Envoy,
	Slot = 0,
	Quest = false,
	CanShow = function() return state() == "Offered" end,
	Execute = function(t)
		local deeds = goodDeeds()
		if #deeds == 0 then
			setState("Refused")
			TakeItemFromParty(WP.Offer)
			Message(Tx"[The envoy reads the letter and tears it in two] The Pit sends strangers to beg for our jars, and offers nothing but gold. The masters don't know you, and you have done nothing for them. There will be no deal. Go home, or come and take the jars, if you dare.")
			return
		end
		setState("Terms")
		Message(string.format(Tx"[The envoy breaks the seal and reads in silence] Maximus. Last year he called us thieves, and now he wants our jars again. Still, the masters know your names. %s\n\nFor that alone they are willing to deal. A case of soul jars for %d gold. Or for a favour: the Eyes have crept into the deep halls of Thunderfist and spoil our work there. Clear them out, and the jars are yours. While you do it, no warlock will raise a hand against you.",
			table.concat(deeds, " "), WP.Price))
	end,
	Texts = {Topic = Tx"The sealed offer"},
}

Quest{
	Name = "MMMWE_WarlockPeace_Gold",
	NPC = WP.Envoy,
	Slot = 0,
	Quest = false,
	CanShow = function() return state() == "Terms" end,
	GetTopic = function() return string.format(Tx"Pay %d gold", WP.Price) end,
	Execute = function(t)
		if Party.Gold < WP.Price then
			Message(string.format(Tx"\"That is not %d gold. Come back when you have it.\"", WP.Price))
			return
		end
		Party.Gold = Party.Gold - WP.Price
		makeDeal(Tx"[The envoy counts the gold slowly, coin by coin] It is all here.")
	end,
}

Quest{
	Name = "MMMWE_WarlockPeace_Favour",
	NPC = WP.Envoy,
	Slot = 1,
	Quest = false,
	CanShow = function() local s = state(); return s == "Terms" or s == "Favour" end,
	Execute = function(t)
		if state() == "Terms" then
			setState("Favour")
			Message(Tx"\"Good. The Eyes nest in the deep halls under the mountain. Kill every one you find in Thunderfist and come back to me. Until then the masters' word protects you, as long as you don't raise a hand against us.\"")
		elseif eyesCleared() then
			makeDeal(Tx"\"Not one Eye left. The masters did not think you could do it.\"")
		else
			Message(Tx"\"The Eyes still float in the deep halls. Kill them all, then come back.\"")
		end
	end,
	Texts = {Topic = Tx"A favour"},
}

-- called by Maps/out10.lua from the two cave entrances: true if the envoy came out
local metThisVisit
function events.LoadMap() metThisVisit = nil end

function MF.WarlockEnvoy()
	if metThisVisit or not envoyWaits() then return false end
	metThisVisit = true
	local npc = Game.NPC[WP.Envoy]
	npc.Name = Tx"Warlock Envoy"
	npc.Pic = WP.EnvoyPic
	for i = 0, 5 do npc.Events[i] = 0 end
	evt.SpeakNPC{WP.Envoy}
	return true
end

---------------------------------------------------------------------------
-- Thunderfist Mountain: the truce and the peace
---------------------------------------------------------------------------

local function alive(m)
	return m.HP > 0 and m.AIState ~= const.AIState.Removed and m.AIState ~= const.AIState.Dead
		and m.AIState ~= const.AIState.Dying
end

local function peaceful() local s = state(); return s == "Favour" or s == "Peace" end

local function setWarlocks(hostile)
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if WP.Warlocks[m.Id] and alive(m) then
			m.Hostile = hostile
			pcall(function() m.ShowAsHostile = hostile end)
		end
	end
end

local function countEyes(except)
	if state() ~= "Favour" then return end
	local n = 0
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if WP.Eyes[m.Id] and alive(m) and m["?ptr"] ~= except then n = n + 1 end
	end
	local was = st().EyesLeft
	st().EyesLeft = n
	if n == 0 and was ~= 0 then
		Game.ShowStatusText(Tx"The deep halls are clear of the Eyes. Return to the warlock envoy.", 6)
	end
end

local function removeJarsFromChests()
	for i = 0, Map.Chests.count - 1 do
		local items = Map.Chests[i].Items
		for k = 1, 140 do
			if items[k].Number == WP.Jars then items[k]:Clear() end
		end
	end
end

function events.AfterLoadMap()
	if not inThunderfist() then return end
	if st().Deal then removeJarsFromChests() end
	if peaceful() then setWarlocks(false) end
	countEyes()
end

local function breakPeace()
	setState("Broken")
	setWarlocks(true)
	Game.ShowStatusText(Tx"You attacked the warlocks: the peace with Thunderfist Mountain is broken!", 6)
end

function events.CalcDamageToMonster(t)
	if not t.ByPlayer or not peaceful() or not inThunderfist() then return end
	local m = t.Monster
	if m and WP.Warlocks[m.Id] then breakPeace() end
end

function events.MonsterKilled(mon)
	if not inThunderfist() then return end
	if WP.Eyes[mon.Id] then
		countEyes(mon["?ptr"])   -- the dying one may still count as alive here
	end
end

-- the game may turn a struck warlock hostile on its own (an area spell, a group alert)
local tickAcc = 0
function events.Tick()
	tickAcc = tickAcc + 1
	if tickAcc < 64 then return end
	tickAcc = 0
	if not peaceful() or not inThunderfist() then return end
	if st().EyesLeft ~= 0 then countEyes() end
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if WP.Warlocks[m.Id] and alive(m) and m.Hostile then
			breakPeace()
			return
		end
	end
end

---------------------------------------------------------------------------
-- history: the deal instead of the raid
---------------------------------------------------------------------------

local function fixHistory()
	if not st().Deal then return end
	local h = Party.History
	if h[WP.HistoryForce] ~= 0 and h[WP.HistoryDeal] == 0 then
		h[WP.HistoryDeal] = h[WP.HistoryForce]
		h[WP.HistoryForce] = 0
	end
end

events.ExitAnyNPC = fixHistory
function events.AfterLoadMap() fixHistory() end
