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

	Kills: vars.MMMWE_BossKills[Placemon line] = true (whenever the boss dies).
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text

local BUTLER, LASITER = 397, 541
local SPEAKER_NAME = MF.BossSpeaker and MF.BossSpeaker.NameId or 163
local MEGA_NAME = 118
local MEGA_IDS = {[460] = true, [461] = true, [462] = true}

vars.MMMWE_BossKills = vars.MMMWE_BossKills or {}

function events.MonsterKilled(mon)
	local n = mon.NameId or 0
	if n == SPEAKER_NAME or n == MEGA_NAME then
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
