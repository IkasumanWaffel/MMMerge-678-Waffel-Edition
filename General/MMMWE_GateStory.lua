--[[
	MMMWE_GateStory.lua — the Gate and Webstation Beta-5 after the Light ending of MM7 (11.11.26)

	The Light side's counterpart of MMMWE_ForgeStory.lua. Once the Gate is open ("Got the
	sci-fi part", QBit 633, on the path of Light, 611):
	  - Resurectra talks about Beta-5 ("The Gate") and sends the party for a Colonial command
	    cube (the Command Cube, item 2220): the station opens its doors but keeps its stores
	    and fabricators sealed without one. Her researchers found the way with the Pathfinder
	    Beacon: thin places in the world, one of them leading to Enroth years back, to the
	    Control Center under Free Haven (quest bit 877).
	  - In the Control Center a guardian droid carries the Cube (the engine of
	    MMMWE_ForgeStory.lua).
	  - Resurectra links the Cube to the station and gives it back (QBit 878): the station's
	    stores, kept by the second C.O.R.A.K. module (house 46, an unused armor shop), sell
	    blasters and Energy Shields with upgraded boards, Ancient devices and Colonial gear.
	  - Two tablets lie in Celeste (MMMWE_AncientLore.lua: 1541, 1575).
	The topics are in Global/MMMWE_GateQuests.lua; the texts here, for the language files.
--]]

local MF = Merge.Functions
local Tx = MF.Text

local GATE_DONE  = 633          -- QBit "Got the sci-fi part" (the end of either path)
local LIGHT_PATH = 611          -- QBit "Chose the path of Light"
local CUBE_QUEST = 877          -- QBit: looking for the Cube
local CUBE_DONE  = 878          -- QBit: the station knows the Cube
local CUBE       = 2220         -- the Command Cube
local SUPPLY     = 46           -- house
local GUARDIAN   = 389          -- Sentinel Droid

local STOCK = {
	{Share = 30, Items = {866, 867}, Upgrades = {2, 4}},          -- blaster pistol, rifle
	{Share = 25, Items = {968}, Upgrades = {1, 3}},               -- Energy Shield
	{Share = 25, Items = {962, 963, 967, 967, 966}},              -- Toolkit, Lantern, Reflector Shield, Jetpack
	{Share = 20, Items = {877, 1677, 890, 1690, 1654, 1624, 1648}},   -- Colonial gear from the station's stores
}

MF.AncientQuests = MF.AncientQuests or {}
table.insert(MF.AncientQuests, {Name = "Gate", Map = "sci-fi.blv", Quest = CUBE_QUEST,
	Done = CUBE_DONE, Item = CUBE, Guardian = GUARDIAN, Key = "MMMWE_CubeGuard",
	Shop = SUPPLY, Stock = STOCK})

MF.GateStory = {
	GATE_DONE = GATE_DONE, LIGHT_PATH = LIGHT_PATH, CUBE_QUEST = CUBE_QUEST, CUBE_DONE = CUBE_DONE,
	CUBE = CUBE, SUPPLY = SUPPLY,

	GateTopic = Tx"The Gate",
	GateText = Tx"We did it. The Gate is open, and on the other side is Webstation Beta-5, a station of the Ancients, still holding air after all these centuries. Another C.O.R.A.K. module was waiting for us there. It knows who we are, and it knows a great deal more than it can tell us yet.\n\nBut the station is half asleep. Its stores and fabricators answer to no one from this world, and the line to the Ancients themselves is still silent. One step at a time.",

	CubeTopic = Tx"Command Cube",
	CubeGive = Tx"The station keeps asking for the same thing: a command cube of the Colonial Government. Without one, Beta-5 opens its doors to us and nothing else.\n\nThe Pathfinder Beacon you brought me has been listening ever since. It found thin places in the world, worn through like old cloth, and one of them leads to Enroth - Enroth as it was years ago. Under Free Haven lies the Control Center, the Oracle's own facility. If a command cube survived anywhere on this world, it is there, and the old machines will still be guarding it.\n\nBring it to me, and Beta-5 will wake up for us.",
	CubeUndone = Tx"No cube yet? The Control Center under Free Haven, in Enroth - the Beacon's thin places will take you there. Be careful: those machines don't know the war is over.",
	CubeDone = Tx"The cube! Let me link it to the station... There. Beta-5 knows us now. Its stores are open, and C.O.R.A.K. has agreed to keep them for us.\n\nKeep the cube - it will serve you better than it would on a shelf. Ask for the station's supplies whenever you need them; I'll make sure the way through the Gate stays open.",
	CubeAfter = Tx"Beta-5 hums like a hive now. One day it will reach the Ancients themselves. Until then, we have work to do.",

	SupplyTopic = Tx"Webstation Supply",
}
