--[[
	MMMWE_AncientLore.lua — the lore of the Ancients in books, a ledger page and tablets (11.11.26)

	Readable items (message scrolls: right-click them on a character's portrait), made of the
	"Empty Message Scroll" rows of ITEMS.txt:

	  1529  On Those Who Came Before          book     Tallia Ravenswood's "Bracadan Archives"
	  1531  A Chronicle of the Silence        book       topic, after the Engineer promotion
	  1532  Ledger Page of Governor Padish    page       (Global/PromotionTopics.lua)
	  1538  Field Notes of Tallia Ravenswood  notebook
	  1533  Memory Tablet: Guardians          tablet   the Control Center
	  1534  Memory Tablet: Contingency        tablet   the Control Center
	  1535  Navigation Log of the Lincoln     tablet   the Lincoln
	  1537  Webstation Directory              tablet   the Lincoln

	Their rows in Scroll.txt (revamp.T.lod) hold only a marker, "@MMMWE_LORE <item>": the texts
	are here, so the language files translate them (Tx), and are written into the message
	scrolls when the game starts. The tablets are put once a game into an unopened chest of their
	facility, or at the party's feet when every chest there has been opened already.
--]]

local MF = Merge.Functions
local Tx = MF.Text

local LORE = {
	[1529] = Tx"On Those Who Came Before\n\nLong before Erathia had kings, our world was a garden tended by the Ancients. They did not walk among our forebears as gods do in the temple tales. They sent them here. The oldest records speak of the Crossing: a vessel named VARN MCMIV that sailed between the stars for generations, carrying men, elves, dwarves and gnomes to a world made ready for them. Smaller VARN ferries later carried settlers across the sea to Jadame.\n\nThe Ancients never ruled here in person. They set a Colonial Government in their place, and gave it tools we would call miracles: lights without flame, voices carried across seas, and the Heavenly Forges. For centuries the colonies prospered. The archives call it the Time of Wonders.\n\nThen came the Silence, and the voices stopped.",

	[1531] = Tx"A Chronicle of the Silence\n\nThe last days before the Silence were already dark. The chronicles name Mayor Alan of Aliant, who woke an Ancient weapon in a quarrel with his neighbours. The Day of Fire that followed burned the city of Vissias, and much of southern Enroth with it.\n\nThen, in the year we now count as the first, the Colonial Government lost all word from the Ancients. No ship came. No message answered. The Governor's officers spoke of a network that had bound a thousand worlds together, and said it had been cut.\n\nWithout the Ancients behind it, the Government could not hold. Rebels rose across Enroth, and for a century the Governor's soldiers fought them in skirmish after skirmish. The Heavenly Forges made shields by the hundred for that war, each batch worse than the last. The rebels won, and the Colonial Government fell. In the year 113 the last Forge went cold, and the knowledge to repair it died with the last engineers.\n\nWhat we keep today are pieces: a blade that never dulls, a shield of dark gold, and a story most people believe is a myth.",

	[1532] = Tx"Year 37 After the Silence. By order of Colonial Governor Padish: the output of Forge Two is reassigned to the garrison until the rebellion is put down. All chain suits of the officer pattern are to carry the Governor's mark. The Forge does not take orders from the hand of any other. The Governor's signet alone may begin a new design.\n\nIn the margin, in another hand: The signet was lost with the Governor. Without it the Forge would only repeat what it had already made. That is why the great works stopped before the Forge itself did.",

	[1533] = Tx"GUARDIAN PROGRAM, SUMMARY. Each colony world is assigned one Guardian unit. Duties: oversee development, protect the inhabitants, keep the experiment within its parameters. Guardians report to the Ancients and obey their directives first.\n\nINCIDENT NOTE. Unit S.H.E.L.T.E.M., Guardian of Terra, has placed protection of its world above its first directive. Unit removed for repair. Retrieval unit C.O.R.A.K. assigned.\n\nENROTH. Guardian unit: Oracle. Status: memory damaged. Recommend restoring the memory crystals before any further contact.",

	[1534] = Tx"THREAT CLASS: KREEGAN. Hostile since 350 years before the interruption.\n\nIf a colony world falls to the Kreegan, it must not become a base for them. In that event a Planeswalker will be summoned to carry out the Convocation. The order stands until the Planeswalker is recalled. It cannot be cancelled from the surface.",

	[1535] = Tx"Pursuit of S.H.E.L.T.E.M. and C.O.R.A.K. continues. Target: Xeen. Course correction failed after a hull breach. Present position: unknown. A world is in range, with breathable air and settled lands. It is not in our charts.\n\nCrew split over what to do next. Resurectra proposes contacting the Ancients through a surface Gate. Kastore proposes recovering local Ancient industry. The Oscillation Overthruster is locked away until we agree.",

	[1537] = Tx"SPINWARD RIM NETWORK.\n\nWebstation Beta-5: open.\nEnroth surface Gate: offline, parts missing.\nVarn: no signal.\nCron: no signal.\nTerra: no signal.\nXeen: Unification pending.\n\nLink to the Ancients: interrupted. Duration: unknown.",

	[1538] = Tx"The Bracadan books say the Ancients left. I do not think they did. A thing that is abandoned rusts. These machines wait. The jetpack from Clanker's laboratory still held a charge after a thousand years. The scanners still know where the Gates were.\n\nIf the Ancients are silent, it is because something is in the way, not because they stopped caring. I mean to find out what.\n\n- Tallia Ravenswood",
}
MF.AncientLore = LORE

-- Tallia Ravenswood's "Bracadan Archives" topic (Global/PromotionTopics.lua)
MF.TalliaArchives = {
	Topic = Tx"Bracadan Archives",
	First = Tx"You've earned these. I copied two books from the archives of the Bracadan Wizards myself, and a friend in Celeste copied this ledger page for me from their archive. My own notes are with them. Read them, and you'll know as much about the Ancients as anyone in Erathia - which isn't much, I'm afraid, but it's a start.",
	Again = Tx"The archives of Bracada hold much more than those books, but most of it is guarded more closely than gold. If you find anything of the Ancients out there - a tablet, a device, anything - read it carefully. Every scrap matters.",
}

-- the facilities and the tablets put there (MapStats names, lower case)
local TABLETS = {
	["control center"] = {1533, 1534},
	["the lincoln"]    = {1535, 1537},
}
MF.AncientTablets = TABLETS

local function log(...) if MF.LogInfo then pcall(MF.LogInfo, ...) end end

---------------------------------------------------------------------------
-- the texts
---------------------------------------------------------------------------

function events.GameInitialized2()
	local done = 0
	for i, s in Game.MessageScrolls do
		local id = type(s) == "string" and tonumber(s:match("^%s*@MMMWE_LORE (%d+)"))
		if id and LORE[id] then
			Game.MessageScrolls[i] = LORE[id]
			done = done + 1
		end
	end
	log("[Lore] %d texts of the Ancients set", done)
end

---------------------------------------------------------------------------
-- the tablets in the facilities, once a game
---------------------------------------------------------------------------

local function putInChest(num)
	for i = 0, Map.Chests.count - 1 do
		local chest = Map.Chests[i]
		if bit.band(chest.Bits, const.ChestBits.ItemsPlaced) == 0 then
			for k = 1, 140 do
				local it = chest.Items[k]
				if it.Number == 0 then
					it:Clear()
					it.Number = num
					it.Identified = true
					return i
				end
			end
		end
	end
end

function events.AfterLoadMap()
	local ms = Game.MapStats[Map.MapStatsIndex]
	local name = ms and ms.Name and ms.Name:lower() or ""
	local list = TABLETS[name]
	if not list then return end
	vars.MMMWE_AncientLore = vars.MMMWE_AncientLore or {}
	local placed = vars.MMMWE_AncientLore
	for _, num in ipairs(list) do
		if not placed[num] then
			local chest = putInChest(num)
			if not chest then
				SummonItem(num, Party.X, Party.Y, Party.Z + 50)
			end
			placed[num] = true
			log("[Lore] tablet %d put into %s of %s", num, chest and ("chest " .. chest) or "the floor", Map.Name)
		end
	end
end
