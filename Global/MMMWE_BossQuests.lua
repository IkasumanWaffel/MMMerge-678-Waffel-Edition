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
	  The Devil of Baa (Bartholomew Hume): after the High Priest of Baa is dead.
	  The Sentinel of Varn (Kastore, the Dark ending; Resurectra, the Light ending): after the
	    Signet or the Cube.
	  The admirals of Regna (Dread Pirate Stanley): Admiral Nelson, Admiral Clausewitz and
	    Captain Zyrain, his rivals.

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
	CanShow = function() return killed(HIGH_PRIEST) end,
	CheckDone = function() return killed(DEVIL) end,
	Texts = {
		Topic = Tx"The Devil of Baa",
		Give = Tx"The High Priest of Baa is dead, and I thank you for it. But a priest is only a voice. The cult of Baa prays to something, and that something answered them: a devil, the scrolls from the temple call it, the Devil of Baa itself, walking our world in the flesh.\n\nWhile it walks, the cult will rise again, as weeds rise from a root. Find it and destroy it.",
		Undone = Tx"The Devil of Baa still walks. I feel it in my meditations, like a stone in a shoe.",
		Done = Tx"The Devil of Baa is destroyed? Then the cult has lost its root as well as its voice. You have done what generations of my order could not. Accept this, with my deepest respect.",
		After = Tx"My meditations are clear again. Thank you.",
		Quest = Tx"Destroy the Devil of Baa and return to Bartholomew Hume in Harmondale.",
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
		Give = Tx"Regna has more admirals than it has ships these days, and every one of them thinks he should be the one giving the orders. Admiral Nelson, Admiral Clausewitz, Captain Zyrain... they get in my way, they take my cut, and they don't know when to keep their mouths shut.\n\nSend the three of them to the bottom, and there's a share of the Regnan treasury in it for you. A large share. Pirate's honour.",
		Undone = Tx"I still hear those three admirals giving orders. Loudly. Do something about it.",
		Done = Tx"All three of them! Regna has learned some manners at last. Here's your share, counted twice. Don't spend it all in one port.",
		After = Tx"Business has never been better. Funny, that.",
		Quest = Tx"Slay Admiral Nelson, Admiral Clausewitz and Captain Zyrain and return to Dread Pirate Stanley in Regna.",
		Award = Tx"Sank Regna's admirals for Dread Pirate Stanley",
	},
}
