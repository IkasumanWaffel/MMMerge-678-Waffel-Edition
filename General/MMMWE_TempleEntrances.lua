--[[
	MMMWE_TempleEntrances.lua (22.11.26): the Temples of the Light and the Dark get their
	unreleased MM7 entrance screens. After Xfing's ShowTempleAnims.lua (Celestial Heavens).

	The doors to both dungeons are NPCs inside the temples (428 "Temple of Light" in house 316,
	Celeste; 429 "Temple of Dark" in house 317, the Pit). MM7 sends the party straight in;
	here the NPC opens a dungeon entrance screen with the temple's own movie ("out07 temple
	of the light", "out08 temple of the dark", House Movies 316 and 319) and its Trans.txt
	description.

	How: choosing the NPC closes its dialog, the house's movie record is borrowed for the
	entrance movie, and evt.MoveToMap opens the entrance screen for the house. OK enters the
	dungeon, Close goes back into the temple; either way the house is put back as it was.
	The NPCs' own events are switched off while a game runs and put back for saving, so
	saves stay as they were.
--]]

local Entrances = {
	[428] = {NPC = 428, House = 316, MovieRecord = 215, CustomMovieRecord = 316, TextIndex = 104,
		Map = "t01.blv", X = -6784, Y = -2832, Z = 1649, Direction = 512},
	[429] = {NPC = 429, House = 317, MovieRecord = 213, CustomMovieRecord = 319, TextIndex = 106,
		Map = "t02.blv", X = 0, Y = -4059, Z = 513, Direction = 512},
}

local SCR = const.Screens
local SelectionPending, EntrancePending, EntrancePendingWait, SelectionOriginMap
local ActiveEntrance, EntranceScreenSeen

local function SameMap(a, b)
	return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- the NPCs' MoveToMap events
local OrigEventA = {[428] = 923, [429] = 924}   -- NPCData.txt
local function DisableNPCEvents()
	for npc in pairs(Entrances) do
		local n = Game.NPC[npc]
		if n.EventA ~= 0 then
			OrigEventA[npc] = n.EventA
			n.EventA = 0
		end
	end
end
local function RestoreNPCEvents()
	for npc, ev in pairs(OrigEventA) do
		Game.NPC[npc].EventA = ev
	end
end

function events.LoadMap()
	DisableNPCEvents()
end
function events.BeforeSaveGame() RestoreNPCEvents() end
function events.AfterSaveGame() DisableNPCEvents() end

-- the borrowed house movie and text
local saved
local function ActivatePresentation(cfg)
	local movie, custom = Game.HouseMovies[cfg.MovieRecord], Game.HouseMovies[cfg.CustomMovieRecord]
	saved = {
		Trans = Game.TransTxt[1],
		EnterText = Game.Houses[cfg.House].EnterText,
		FileName = movie.FileName, NPCPic = movie.NPCPic, Sounds = movie.Sounds,
	}
	Game.TransTxt[1] = Game.TransTxt[cfg.TextIndex]
	Game.Houses[cfg.House].EnterText = "0"
	movie.FileName = custom.FileName
	movie.NPCPic = custom.NPCPic
	movie.Sounds = custom.Sounds
end

local function RestorePresentation(cfg)
	if not saved then return end
	Game.TransTxt[1] = saved.Trans
	Game.Houses[cfg.House].EnterText = saved.EnterText
	local movie = Game.HouseMovies[cfg.MovieRecord]
	movie.FileName = saved.FileName
	movie.NPCPic = saved.NPCPic
	movie.Sounds = saved.Sounds
	saved = nil
end

function events.EnterNPC(id)
	local cfg = Entrances[id]
	if cfg and Game.GetCurrentHouse() == cfg.House
			and not SelectionPending and not EntrancePending and not ActiveEntrance then
		SelectionPending = cfg
		SelectionOriginMap = Map.Name
	end
end

function events.Tick()
	if not (SelectionPending or EntrancePending or ActiveEntrance) then return end
	local screen, house = Game.CurrentScreen, Game.GetCurrentHouse()

	-- 1: the NPC was chosen: close its dialog
	if SelectionPending and screen == SCR.House and house == SelectionPending.House
			and Game.HouseScreen == 1 and GetCurrentNPC() == SelectionPending.NPC then
		EntrancePending, EntrancePendingWait = SelectionPending, true
		SelectionPending = nil
		Game.ExitHouseScreen()
		return
	end

	-- 2: back in the house menu (one tick later): open the entrance screen
	if EntrancePending then
		local cfg = EntrancePending
		if screen == SCR.House and house == cfg.House and Game.HouseScreen == 0 and GetCurrentNPC() == nil then
			if EntrancePendingWait then
				EntrancePendingWait = false
			else
				EntrancePending = nil
				ActiveEntrance = {Config = cfg, OriginMap = SelectionOriginMap}
				SelectionOriginMap, EntranceScreenSeen = nil, false
				ActivatePresentation(cfg)
				evt.MoveToMap{X = cfg.X, Y = cfg.Y, Z = cfg.Z, Direction = cfg.Direction, LookAngle = 0,
					SpeedZ = 0, HouseId = cfg.House, Icon = 1, Name = cfg.Map}
			end
		elseif screen ~= SCR.House then
			EntrancePending = nil   -- the party left the house meanwhile
		end
		return
	end

	-- 3: the entrance screen closed: OK (in the dungeon) or Close (back into the temple)
	if ActiveEntrance then
		if screen == SCR.MapEntrance then
			EntranceScreenSeen = true
		elseif EntranceScreenSeen and screen == SCR.Game then
			local cfg, origin = ActiveEntrance.Config, ActiveEntrance.OriginMap
			ActiveEntrance, EntranceScreenSeen = nil, false
			RestorePresentation(cfg)
			if not SameMap(Map.Name, cfg.Map) and SameMap(Map.Name, origin) then
				ReloadHouse(cfg.House)
			end
		end
	end
end

-- a game loaded with an entrance screen half-way: nothing is left borrowed
function events.LeaveGame()
	if ActiveEntrance then RestorePresentation(ActiveEntrance.Config) end
	SelectionPending, EntrancePending, ActiveEntrance = nil, nil, nil
end
