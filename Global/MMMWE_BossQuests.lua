--[[
	MMMWE_BossQuests.lua — quests for bosses that had none (22.11.26)
	The bosses themselves: General/MMMWE_Bosses.lua.

	The Speaker for the Dead (the Butler, Harmondale): Veyla the Speaker, the necromancer
	atop Castle Harmondale, is calling up the castle's old lords. Given along with the
	Butler's own quest of cleaning out the castle.

	The Mega-Dragon (Lasiter the Slayer, Grand Master of Armsmaster): the beast in the Land
	of the Giants that the Slayer once failed to kill (a quest planned for him in MM7 and never
	made). Once it's dead, his topic "The Slayer's Way" makes any Grand Master of Armsmaster
	Legendary without the second promotion and the character level the other teachers ask
	for (MMMWE_LegendaryMastery.lua); the skill level and the one-skill rule still hold.

	(23.11.26) More, each for a boss's own story:
	  Morcarack (Tor Anwyn, Mount Nighon; the Dark path): the red dragon of Emerald Island
	    burns the warlocks' ship from Nighon - and keeps the pirates away from the islanders.
	  The renegade dragons Ilsingore, Yaardrake and Old Loeb: Deftclaw Redreaver wants them
	    dead as traitors to their race (allied with the dragons), Sir Charles Quixote as fair
	    game (allied with the hunters).
	  The Devil of Baa (Bartholomew Hume): a Kreegan among the cultists in the Temple of Baa
	    (MMMWE_Bosses.lua names the strongest one there).
	  The Sentinel of Varn (Kastore, the Dark ending; Resurectra, the Light ending): after the
	    Signet or the Cube.
	  The admirals of Regna (Dread Pirate Stanley): Admiral Nelson, Admiral Clausewitz and
	    Captain Zyrain, his rivals, on their ships off Dagger Wound Island.
	  The Wasp Queen (Schmecker, Alvar): the prize the dead adventurers' camp went for.
	  The Pack Master (Maddigan the Tracker, Ravenshore): in the Dire Wolf Den.
	  Grognard the Great (the Butler): once the Letter to Hairbaugh is found or a signal
	    fire is lit.
	  The Druid Circlet of Power (Anthony Green): from the hidden dungeon under the
	    Murmurwoods stonehenge (MM8's scrapped Druid quest).
	  The Dragon Riders (Erik von Stromgard): clear out the Caves of the Dragon Riders
	    (MM6's scrapped quest; their letter is in the keep they took).
	  The false Prince of Thieves (Lord Anthony Stone): the Rogue Leader in the rogues'
	    hideout, left to cover the real Prince in the Free Haven sewers.

	Kills: vars.MMMWE_BossKills[Placemon line] = true, for every named monster, whenever it
	dies (a boss killed before its quest was given counts).
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text

local BUTLER, LASITER = 397, 541
local SPEAKER_NAME = MF.BossSpeaker and MF.BossSpeaker.NameId or 165
local MEGA_NAME = 118
local MEGA_IDS = {[460] = true, [461] = true, [462] = true}

vars.MMMWE_BossKills = vars.MMMWE_BossKills or {}

function events.MonsterKilled(mon)
	local n = mon.NameId or 0
	if n > 0 then
		vars.MMMWE_BossKills[n] = true
	elseif MEGA_IDS[mon.Id] then
		vars.MMMWE_BossKills[MEGA_NAME] = true
	end
end

local function killed(n) return vars.MMMWE_BossKills[n] == true end

---------------------------------------------------------------------------
-- the Butler: the Speaker for the Dead
---------------------------------------------------------------------------

Quest{
	Name = "MMMWE_Boss_Speaker",
	NPC = BUTLER,
	Slot = 2,
	Quest = true,
	Exp = 8000,
	Gold = 3000,
	CheckDone = function() return killed(SPEAKER_NAME) end,
	Texts = {
		Topic = Tx"Speaker for the Dead",
		Give = Tx"There is one more thing, my lords, and I hardly know how to put it. Since the goblins took the castle, a woman in black has been seen on the highest battlements at night. The villagers call her the Speaker for the Dead.\n\nShe talks to the old lords of Harmondale who lie beneath the keep, and on some nights they answer her. And walk. The goblins won't go up there, and neither will anyone with sense. A castle whose dead won't stay buried is a poor gift for its new lords. If you could see her off the battlements, for good...",
		Undone = Tx"She is still up there. On a still night you can hear her calling the old lords by name. Please, before all of them answer.",
		Done = Tx"The tower is quiet! The first quiet night in years, the villagers say, and the old lords of Harmondale can rest at last. This was set aside for the castle's repairs, but I can think of no better use for it.",
		After = Tx"Not a sound from the tower since you went up there, my lords. Not a single one.",
		Quest = Tx"Slay the Speaker for the Dead atop Castle Harmondale and return to the Butler.",
		Award = Tx"Laid the dead of Castle Harmondale to rest",
	},
}

---------------------------------------------------------------------------
-- Lasiter the Slayer: the Mega-Dragon
---------------------------------------------------------------------------

Quest{
	Name = "MMMWE_Boss_MegaDragon",
	NPC = LASITER,
	Slot = 2,
	Quest = true,
	Exp = 60000,
	CheckDone = function() return killed(MEGA_NAME) end,
	Texts = {
		Topic = Tx"The Mega-Dragon",
		Give = Tx"You want to know why they call me the Slayer? I've killed every kind of beast there is but one. In the Land of the Giants lives a dragon older and bigger than any other: the Mega-Dragon. I went after it when I was young and foolish, and I came back with half my company.\n\nI've trained Grand Masters since, but none who could finish what I started. Kill it, and I'll show you what lies beyond Grand Master in Armsmaster, years before any other teacher would let you near it.",
		Undone = Tx"The Mega-Dragon still lives. I'd know if it didn't: every warrior in Antagarich would be talking of nothing else.",
		Done = Tx"You did it. You actually did it! Then you've earned the Slayer's Way. Any of you who is a Grand Master of Armsmaster can learn it from me, whatever your rank or your years. Ask me about it.",
		After = Tx"The Mega-Dragon is dead. I'm still getting used to the thought.",
		Quest = Tx"Slay the Mega-Dragon in the Land of the Giants and return to Lasiter the Slayer.",
		Award = Tx"Slew the Mega-Dragon",
	},
}

-- the reward: Legendary Armsmaster without the promotion and the character level
local function slayersWay()
	local i = Party.CurrentPlayer
	local pl = i and i >= 0 and i < Party.count and Party[i]
	if not pl or not MF.MakeLegendary then return end
	local skill = const.Skills.Armsmaster
	local L = MF.LegendarySettings
	local name = MF.LegendarySkillName and MF.LegendarySkillName(skill) or Game.SkillNames[skill]
	if MF.IsLegendary(pl, skill) then
		Message(string.format(Tx"%s, you walk the Slayer's Way already. I have nothing more to teach you.", pl.Name))
		return
	end
	local bad = {}
	local cur = MF.LegendarySkill(pl)
	if cur and cur ~= skill then
		bad[#bad + 1] = string.format(Tx"already %s in %s, and only one skill can be", L.Name,
			MF.LegendarySkillName and MF.LegendarySkillName(cur) or Game.SkillNames[cur])
	end
	local lvl, mas = SplitSkill(MF.SkillValue and MF.SkillValue(pl, skill) or pl.Skills[skill])
	if (mas or 0) < (const.GM or 4) then
		bad[#bad + 1] = Tx"not a Grand Master of " .. name
	elseif (lvl or 0) < L.SkillLevel then
		bad[#bad + 1] = string.format(Tx"%s at %d of %d", name, lvl or 0, L.SkillLevel)
	end
	if #bad > 0 then
		Message(string.format(Tx"The Slayer's Way isn't open to you yet, %s: %s.", pl.Name, table.concat(bad, "; ")))
		return
	end
	MF.MakeLegendary(pl, skill, true)
	local p = L.Passives[skill]
	Message(string.format(Tx"%s is now %s in %s.%s", pl.Name, L.Name, name,
		p and string.format("\n\n%s: %s.", p.Name, p.Text) or ""))
end

NPCTopic{
	Name = "MMMWE_Boss_SlayersWay",
	NPC = LASITER,
	Slot = 3,
	Topic = Tx"The Slayer's Way",
	NeverGiven = true,
	NeverDone = true,
	CanShow = function() return vars.Quests and vars.Quests.MMMWE_Boss_MegaDragon == "Done" end,
	Done = slayersWay,
}

---------------------------------------------------------------------------
-- (23.11.26) more bosses
---------------------------------------------------------------------------

local function allKilled(list)
	for _, n in ipairs(list) do
		if not killed(n) then return false end
	end
	return true
end

-- Tor Anwyn, Mount Nighon: Morcarack (Placemon 113 and 160), the Dark path
local TOR_ANWYN, DARK_PATH = 390, 612
local MORCARACK = {113, 160}

Quest{
	Name = "MMMWE_Boss_Morcarack",
	NPC = TOR_ANWYN,
	Quest = true,
	Exp = 20000,
	Gold = 5000,
	CanShow = function() return Party.QBits[DARK_PATH] end,
	CheckDone = function() return killed(MORCARACK[1]) or killed(MORCARACK[2]) end,
	Texts = {
		Topic = Tx"Morcarack",
		Give = Tx"Our ship sails from Nighon to Emerald Island, for what the island grows and what its people will sell to anyone who pays. Or it did, until Morcarack the Pitiless burned it to the waterline.\n\nThe islanders love that red dragon, you know. It keeps the pirates off their shores, they say. I say a dragon that burns ships doesn't ask whose they are. Kill it, and the sea to Emerald Island is ours. If the pirates come back after that, the islanders will learn who their real friends are.",
		Undone = Tx"Morcarack still lives in its cave on Emerald Island, and our captains still refuse to sail there. I can't say I blame them.",
		Done = Tx"Morcarack is dead! The ship sails again on the next tide. My warlocks will want a word with you about the dragon's blood, but that can wait. Take this, for now.",
		After = Tx"The ship is back on the Emerald Island route. Funny thing: the islanders have started asking us for protection.",
		Quest = Tx"Slay Morcarack the Pitiless in its cave on Emerald Island and return to Tor Anwyn in Mount Nighon.",
		Award = Tx"Slew Morcarack the Pitiless",
	},
}

-- the renegade dragons (Placemon 109 Ilsingore, 107 Yaardrake, 108 Old Loeb)
local DEFTCLAW, QUIXOTE = 17, 15
local RENEGADES = {109, 107, 108}
local HUNTERS_ALLY, DRAGONS_ALLY = 21, 22

Quest{
	Name = "MMMWE_Boss_Renegades_Dragons",
	NPC = DEFTCLAW,
	Quest = true,
	Exp = 40000,
	Gold = 15000,
	CanShow = function() return Party.QBits[DRAGONS_ALLY] end,
	CheckDone = function() return allKilled(RENEGADES) end,
	Texts = {
		Topic = Tx"The renegades",
		Give = Tx"You have proven yourselves friends of our kind, so hear this. Ilsingore, Yaardrake and Old Loeb have turned their backs on us. They think they can save our race by scattering across Jadame and raising tribes of their own. All they will do is give Quixote's butchers three easy targets, and teach them where the rest of us sleep.\n\nI will not have it. Find the three of them and end it. It is a dragon's task, but I would rather not spill the blood of my own kind myself.",
		Undone = Tx"The renegades still live. Every day they do, the hunters learn a little more about us.",
		Done = Tx"So it is done: Ilsingore, Yaardrake and Old Loeb are no more. It is a sad day for dragonkind, and a necessary one. Take this, and my thanks, for what they are worth from one who grieves.",
		After = Tx"We are fewer now, but we are one.",
		Quest = Tx"Slay the renegade dragons Ilsingore, Yaardrake and Old Loeb and return to Deftclaw Redreaver in Garrote Gorge.",
		Award = Tx"Ended the renegade dragons for Deftclaw Redreaver",
	},
}

Quest{
	Name = "MMMWE_Boss_Renegades_Hunters",
	NPC = QUIXOTE,
	Quest = true,
	Exp = 40000,
	Gold = 15000,
	CanShow = function() return Party.QBits[HUNTERS_ALLY] end,
	CheckDone = function() return allKilled(RENEGADES) end,
	Texts = {
		Topic = Tx"Lone dragons",
		Give = Tx"Good news, my friends: the dragons are quarrelling among themselves. Three of them, Ilsingore, Yaardrake and Old Loeb, have left Deftclaw's protection to make lairs of their own across Jadame. Alone, out of reach of their kin. Fair game, I'd say!\n\nBring them down, all three, and the Dragon Hunters will pay you as we pay our very best.",
		Undone = Tx"Three lone dragons, and not one of them hunted yet? My men are starting to talk.",
		Done = Tx"All three! Ilsingore, Yaardrake and Old Loeb! The camp will be drinking to your names for a month. Here is your pay, every coin of it.",
		After = Tx"Deftclaw's brood is smaller by three, and quieter for it.",
		Quest = Tx"Slay the dragons Ilsingore, Yaardrake and Old Loeb and return to Sir Charles Quixote in Garrote Gorge.",
		Award = Tx"Hunted down three dragons for Sir Charles Quixote",
	},
}

-- Bartholomew Hume: the Devil of Baa (Placemon 138), after the High Priest (112)
local HUME = 377
local HIGH_PRIEST, DEVIL = 112, 138

Quest{
	Name = "MMMWE_Boss_DevilOfBaa",
	NPC = HUME,
	Quest = true,
	Exp = 25000,
	Gold = 7500,
	CheckDone = function() return killed(DEVIL) end,
	Texts = {
		Topic = Tx"The Devil of Baa",
		Give = Tx"The High Priest of Baa is only a voice. The cult prays to something, and that something has answered them: among the cultists in their temple in AvLee there are devils, and one of them they call the Devil of Baa and worship as their god made flesh.\n\nKill the priest, and the cult loses its voice. Leave the devil, and it will rise again, as weeds rise from a root. Destroy it.",
		Undone = Tx"The Devil of Baa still walks. I feel it in my meditations, like a stone in a shoe.",
		Done = Tx"The Devil of Baa is destroyed? Then the cult has lost its root as well as its voice. You have done what generations of my order could not. Accept this, with my deepest respect.",
		After = Tx"My meditations are clear again. Thank you.",
		Quest = Tx"Destroy the Devil of Baa in the Temple of Baa in AvLee and return to Bartholomew Hume in Harmondale.",
		Award = Tx"Destroyed the Devil of Baa",
	},
}

-- the Sentinel of Varn (Placemon 136): Kastore (Dark ending) or Resurectra (Light ending)
local SENTINEL = 136
local KASTORE, RESURECTRA = 423, 419
local F, G = MF.ForgeStory, MF.GateStory

local SentinelTexts = {
	Give = Tx"My researchers have been reading the wreck's logs. VARN didn't only carry colonists: it carried Sentinels, guardians built to hold the ship's vaults should the crew be lost. One of them still keeps its watch, and as long as it does, half of what the Ancients left us stays out of reach.\n\nIt will not stop, and it will not listen. Put an end to its watch.",
	Undone = Tx"The Sentinel of Varn still keeps its watch. A thousand years of patience. We have less.",
	Done = Tx"The Sentinel has fallen? Then its watch is over, and the vaults are ours to study. Well done. You will find the reward worthy of the work.",
	After = Tx"The Sentinel's vaults keep my researchers busy day and night.",
	Quest = Tx"Destroy the Sentinel of Varn.",
	Award = Tx"Ended the watch of the Sentinel of Varn",
}

local function sentinelTexts()
	local t = {Topic = Tx"The Sentinel of Varn"}
	for k, v in pairs(SentinelTexts) do t[k] = v end
	return t
end

if F then
	Quest{
		Name = "MMMWE_Boss_Sentinel_Dark",
		NPC = KASTORE,
		Quest = true,
		Exp = 50000,
		Gold = 20000,
		CanShow = function() return Party.QBits[F.SIGNET_DONE] end,
		CheckDone = function() return killed(SENTINEL) end,
		Texts = sentinelTexts(),
	}
end
if G and G.CUBE_DONE then
	Quest{
		Name = "MMMWE_Boss_Sentinel_Light",
		NPC = RESURECTRA,
		Quest = true,
		Exp = 50000,
		Gold = 20000,
		CanShow = function() return Party.QBits[G.CUBE_DONE] end,
		CheckDone = function() return killed(SENTINEL) end,
		Texts = sentinelTexts(),
	}
end

-- Dread Pirate Stanley, Regna: his rivals (Placemon 4 Admiral Nelson, 6 Admiral Clausewitz,
-- 5 Captain Zyrain)
local STANLEY = 108
local ADMIRALS = {4, 6, 5}

Quest{
	Name = "MMMWE_Boss_Admirals",
	NPC = STANLEY,
	Quest = true,
	Exp = 30000,
	Gold = 25000,
	CheckDone = function() return allKilled(ADMIRALS) end,
	Texts = {
		Topic = Tx"The admirals",
		Give = Tx"Regna has more admirals than it has ships these days, and every one of them thinks he should be the one giving the orders. Admiral Nelson, Admiral Clausewitz and Captain Zyrain are off Dagger Wound Island right now, on their ships, sending raiders against the lizardfolk villages. Lizards! There's no plunder in that, only glory for them and orders for me.\n\nThey get in my way, they take my cut, and they don't know when to keep their mouths shut. Send the three of them to the bottom, and there's a share of the Regnan treasury in it for you. A large share. Pirate's honour.",
		Undone = Tx"I still hear those three admirals giving orders. Loudly. Do something about it.",
		Done = Tx"All three of them! Regna has learned some manners at last. Here's your share, counted twice. Don't spend it all in one port.",
		After = Tx"Business has never been better. Funny, that.",
		Quest = Tx"Slay Admiral Nelson, Admiral Clausewitz and Captain Zyrain on their ships off Dagger Wound Island and return to Dread Pirate Stanley in Regna.",
		Award = Tx"Sank Regna's admirals for Dread Pirate Stanley",
	},
}

-- Schmecker, Alvar: the Wasp Queen (Placemon 161)
local SCHMECKER = 86
Quest{
	Name = "MMMWE_Boss_WaspQueen",
	NPC = SCHMECKER,
	Quest = true,
	Exp = 15000,
	Gold = 10000,
	CheckDone = function() return killed(161) end,
	Texts = {
		Topic = Tx"The Wasp Queen",
		Give = Tx"Royal jelly from the workers' cells is good. The Queen's own is better than anything you've ever tasted, and worth more than its jar in gold. Every few years someone goes into the nest for it. You may have seen the last ones: their camp still stands in the canyon south of the hive, and nobody has come back to it.\n\nThe Queen is the problem. As long as she lives, the nest defends itself like an army. Kill her, and I'll pay you better than any of those poor souls would have earned.",
		Undone = Tx"The Queen still lives. The hum from the nest carries all the way to town on a quiet night.",
		Done = Tx"The Queen is dead? Then the nest is ours to harvest for years! Here's your pay, and more, for I'm in a generous mood today.",
		After = Tx"Business is sweet, my friends. Very sweet.",
		Quest = Tx"Slay the Wasp Queen in the Wasp Nest near Alvar and return to Schmecker in Alvar.",
		Award = Tx"Slew the Wasp Queen of Alvar",
	},
}

-- Maddigan the Tracker, Ravenshore: the Pack Master (Placemon 11)
local MADDIGAN = 71
Quest{
	Name = "MMMWE_Boss_PackMaster",
	NPC = MADDIGAN,
	Quest = true,
	Exp = 10000,
	Gold = 5000,
	CheckDone = function() return killed(11) end,
	Texts = {
		Topic = Tx"The Pack Master",
		Give = Tx"Kill all the dire wolves you like: the packs will keep coming as long as the Pack Master lives. It's the biggest wolf I've ever tracked, and the cleverest. It keeps to the Dire Wolf Den near here and sends the young ones out to hunt.\n\nBring it down, and the roads around Ravenshore will be safe for a generation.",
		Undone = Tx"The Pack Master still rules the den. I can hear it howling on still nights.",
		Done = Tx"The Pack Master, dead! I'll believe it when I see the tracks stop... no, I believe you. Here, you've earned every coin.",
		After = Tx"The packs are scattering. Without the old one, they're just wolves again.",
		Quest = Tx"Slay the Pack Master in the Dire Wolf Den and return to Maddigan the Tracker in Ravenshore.",
		Award = Tx"Slew the Pack Master of the Dire Wolf Den",
	},
}

-- the Butler: Grognard the Great (Placemon 121) and his spy Hairbaugh
local GROGNARD = 121
local LETTER, FIRE_S, FIRE_N = 1518, 779, 780
local function hasItem(id)
	for _, pl in Party do
		for _, it in pl.Items do
			if it.Number == id then return true end
		end
	end
	return Mouse.Item.Number == id
end
Quest{
	Name = "MMMWE_Boss_Grognard",
	NPC = BUTLER,
	Quest = true,
	Exp = 12000,
	Gold = 4000,
	CanShow = function()
		return vars.Quests.MMMWE_Boss_Grognard or hasItem(LETTER) or Party.QBits[FIRE_S] or Party.QBits[FIRE_N]
	end,
	CheckDone = function() return killed(GROGNARD) end,
	Texts = {
		Topic = Tx"Grognard the Great",
		Give = Tx"A letter to Hairbaugh? Hairbaugh, of all people! He has lived in Harmondale for years... and he has been a goblin spy all along, waiting for the signal fires.\n\nThis Grognard the Great is the chief who drove the goblins into the castle in the first place. If the fires are lit, he will come in person, with his whole tribe. Should that happen, my lords, the chief himself must fall, or the goblins will never leave these lands.",
		Undone = Tx"Grognard the Great still lives. Every goblin in the hills knows it, and so do the villagers.",
		Done = Tx"Grognard is dead! Without him the tribe will scatter. Harmondale owes you, my lords - again.",
		After = Tx"Not a goblin on the roads this week. I could get used to it.",
		Quest = Tx"Slay Grognard the Great, the goblin chief, and return to the Butler in Harmondale.",
		Award = Tx"Slew Grognard the Great",
	},
}

-- Anthony Green: the Druid Circlet of Power (item 638) from under the Murmurwoods stonehenge
local GREEN, CIRCLET = 389, 638
Quest{
	Name = "MMMWE_Boss_DruidCirclet",
	NPC = GREEN,
	Quest = true,
	QuestItem = CIRCLET,
	Exp = 30000,
	Gold = 10000,
	Texts = {
		Topic = Tx"The Druid Circlet",
		Give = Tx"The stonehenges of Antagarich are not the only ones. Across the sea, in the Murmurwoods of Jadame, stands another circle, older than ours. Our oldest songs say the druids of that land kept a hall beneath it, and in it the Circlet of Power, worn by the first Grand Druid.\n\nNobody has sung of that land's druids for centuries. If the hall still stands, the Circlet may still be there. Find it and bring it to me: it belongs to the circle, not to the dark.",
		Undone = Tx"The circle in the Murmurwoods guards its hall well. Look closely at the stones themselves.",
		Done = Tx"The Circlet of Power... I can feel the old songs in it. The circle will keep it safe now, as it should have been kept all along. Accept the circle's thanks, and this.",
		After = Tx"The Circlet rests with the circle. On quiet nights, I swear the stones sing.",
		Quest = Tx"Find the Druid Circlet of Power beneath the stonehenge in the Murmurwoods of Jadame and bring it to Anthony Green in the Tularean Forest.",
		Award = Tx"Returned the Druid Circlet of Power to the circle",
	},
}

-- Erik von Stromgard: the Caves of the Dragon Riders (6d20.blv) cleared
local STROMGARD, RIDERS_MAP = 800, "6d20.blv"

local function ridersLeft()
	local n = 0
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.AIState ~= const.AIState.Removed and m.AIState ~= const.AIState.Dead
				and m.AIState ~= const.AIState.Dying and m.Ally ~= 9999 then
			n = n + 1
		end
	end
	return n
end

local RidersCheck = false
local function checkRiders()
	if (Map.Name or ""):lower() == RIDERS_MAP and ridersLeft() == 0 then
		vars.MMMWE_DragonRidersCleared = true
	end
end
function events.AfterLoadMap() RidersCheck = false end
function events.MonsterKilled()
	if (Map.Name or ""):lower() == RIDERS_MAP then RidersCheck = true end
end
function events.Tick()
	if RidersCheck then RidersCheck = false; checkRiders() end
end
function events.LeaveMap() checkRiders() end

Quest{
	Name = "MMMWE_Boss_DragonRiders",
	NPC = STROMGARD,
	Quest = true,
	Exp = 20000,
	Gold = 10000,
	CheckDone = function() checkRiders() return vars.MMMWE_DragonRidersCleared == true end,
	Texts = {
		Topic = Tx"The Dragon Riders",
		Give = Tx"The Dragon Towers keep the dragons off our towns, and someone wants them dark. The Dragon Riders: brigands who have tamed what should never be tamed, and who live in caves north-west of here. They raided our towns before the towers stood, and they mean to raid them again. They've already bought themselves a keep in the south to do it, and the keys to turn the towers off.\n\nGo to their caves and break them, every last rider. The Frozen Highlands will pay you well.",
		Undone = Tx"The Dragon Riders still hold their caves. As long as they do, the towers are only as safe as their keys.",
		Done = Tx"The Dragon Riders are broken! The towns can sleep again, and the towers can do their work. Take this, with the thanks of the Frozen Highlands.",
		After = Tx"Not a rider seen in the sky since. The towers stand, and so do we.",
		Quest = Tx"Clear out the Caves of the Dragon Riders and return to Erik von Stromgard in Castle Stromgard.",
		Award = Tx"Broke the Dragon Riders for Erik von Stromgard",
	},
}

-- Lord Anthony Stone: the false Prince of Thieves (Placemon 127 Rogue Leader), once the
-- hunt for the Prince (QBit 1122) is on
local STONE, ROGUE_LEADER = 801, 127
local PRINCE_QUEST, PRINCE_DONE = 1122, 1194

Quest{
	Name = "MMMWE_Boss_FalsePrince",
	NPC = STONE,
	Quest = true,
	Exp = 15000,
	Gold = 7500,
	CanShow = function()
		return vars.Quests.MMMWE_Boss_FalsePrince or Party.QBits[PRINCE_QUEST] or Party.QBits[PRINCE_DONE]
	end,
	CheckDone = function() return killed(ROGUE_LEADER) end,
	Texts = {
		Topic = Tx"The false Prince",
		Give = Tx"One more thing about this Prince of Thieves. My agents say the rogues keep a man in their hideout who calls himself the Prince, wears his colours and gives his orders. A decoy, no doubt, while the real one hides elsewhere.\n\nBut a decoy who gives orders long enough becomes a leader. Should the real Prince fall, that one would simply take his place. Deal with him as well, and the rogues will have nobody left to follow.",
		Undone = Tx"The false Prince still holds the rogues' hideout. While he does, they have a leader in waiting.",
		Done = Tx"The impostor is dead? Good. Now when the real Prince falls, there will be no one to pick up his crown. Here, for your thoroughness.",
		After = Tx"The rogues are quarrelling among themselves over who gives orders now. Exactly as it should be.",
		Quest = Tx"Defeat the false Prince of Thieves in the rogues' hideout in the Frozen Highlands and return to Lord Anthony Stone at Castle Stone.",
		Award = Tx"Unmasked and defeated the false Prince of Thieves",
	},
}
