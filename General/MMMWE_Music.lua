--[[
	MMMWE_Music.lua — random map music with day / night and seasonal soundtracks

	Builds on Game.MapMusicSets from MMMWE_Main.lua (the "any time" tracks of each map)
	and adds layers on top of it. Each time the game picks the map track (entering a map,
	and whenever it starts the map music again), a track is drawn at random from:

	  1. the map's "any time" tracks          Music.Maps[id].Any, or Game.MapMusicSets[id]
	  2. + the current part of the day          Music.Maps[id].Day / .Night
	  3. + the current season                   Music.Maps[id].Seasons[s].Day / .Night / .Any
	  4. + every matching rule                  Music.Rules (groups of maps, outdoor/indoor, season...)
	  5. events.ChooseMapTrack(t)               other scripts may set t.Track (t.Pool, t.Night,
	                                            t.Season, t.MapIndex, t.Reason are for reference;
	                                            Reason = "map", "loop" or "daynight")

	A layer with Exclusive = true replaces everything collected before it instead of adding,
	e.g. a night set that should play *only* at night. Repeating a number in a list makes
	that track more likely. The last track isn't repeated twice in a row if there's a choice.
	Maps with no tracks anywhere keep the game's own track.

	Seasons (evt.CheckSeason): 0 = spring, 1 = summer, 2 = autumn, 3 = winter.

	Playback control uses MM8's start_new_music (0x4A862D, thiscall(music, track)):
	  - SwitchAtDawnDusk: when day turns to night (or back) while you're on the map and the
	    playing track doesn't belong to the new part of the day, a new track starts at once.
	  - NewTrackOnLoop: when the game restarts the same map track, a new one is drawn instead.
	  - Music.PlayNow(track) plays any track right away (after the game has played one).
	The music object and the track numbering are learned from the game's own first call on
	each map, so nothing happens before the map music has started once.

	AMBIENCE — a looping background sound (birds, wind, crickets...) next to the music.
	It plays through the game's sound player (make_sound, 0x4A87DC) on sound object -2,
	which has its own channel (14), and is switched at dawn and dusk like the music.
	Sound ids are left for you to choose: fill in Music.Ambient below, or per map:

	  Music.SetMap(7, {DayAmbient = <id>, NightAmbient = {<id>, <id>}})   -- list = random pick
	  Music.SetMap(7, {Seasons = {[3] = {DayAmbient = <id>}}})            -- winter only
	  Music.AddRule{Maps = {...}, Outdoor = true, NightAmbient = <id>}
	  NightAmbient = false                                                -- silence there

	Which ambience is used (first one found): the map's season entry, the map entry, the
	last matching rule, then Music.Ambient.Outdoor / .Indoor. Music.PlayAmbient(id) and
	Music.StopAmbient() control it by hand.

	Examples (put them in your own script or at the end of this file):

	  -- Ravenshore: calm tracks by day, tavern music at night, on top of its usual set
	  Music.SetMap(2, {Day = {53, 114}, Night = {89, 130}})

	  -- Shadowspire plays only its dark tracks at night
	  Music.SetMap(6, {Night = {64, 121}, NightExclusive = true})

	  -- Winter in Murmurwoods: its own set only
	  Music.SetMap(7, {Seasons = {[3] = {Any = {82}, Exclusive = true}}})

	  -- All outdoor maps of a list get extra night tracks
	  Music.AddRule{Maps = {1, 2, 3, 4, 5}, Outdoor = true, Night = {22}}
--]]

Music = Music or {}
local M = Music

M.Settings = M.Settings or {
	Enabled    = true,
	DayStart   = 6,      -- first hour of the day (6:00)
	NightStart = 19,     -- first hour of the night (19:00)
	NoRepeat   = true,   -- avoid playing the same track twice in a row
	SwitchAtDawnDusk = true,  -- change track when day/night changes on the map
	NewTrackOnLoop   = true,  -- draw a new track when the game would repeat the map track
	AmbientEnabled   = true,  -- play the ambience loop
	AmbientVolume    = 0,     -- 1..127 (only used with 3D sound off); 0 = game's sound volume
}
local S = M.Settings

-- Per-map layers: Music.Maps[mapIndex] = {
--   Any = {...},              -- replaces Game.MapMusicSets[mapIndex] if given
--   Day = {...}, Night = {...},
--   DayExclusive = false, NightExclusive = false,
--   Seasons = {[season] = {Any = {...}, Day = {...}, Night = {...}, Exclusive = false}},
-- }
M.Maps = M.Maps or {}

-- Rules for groups of maps: {
--   Maps = {ids...} (nil = every map), Outdoor = true/false/nil, Season = 0..3/nil,
--   Any = {...}, Day = {...}, Night = {...}, Exclusive = false,
-- }
M.Rules = M.Rules or {
	-- Snowy outdoor maps in winter (was hard-coded in MMMWE_Main.lua)
	{
		Maps = {63, 64, 65, 69, 70, 71, 72, 73, 137, 146, 147, 148, 149, 150, 151},
		Outdoor = true, Season = 3,
		Day = {82}, Night = {22},
	},
}

function M.SetMap(mapIndex, layers)
	M.Maps[mapIndex] = layers
end

function M.AddRule(rule)
	table.insert(M.Rules, rule)
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

function M.IsNight()
	local h = Game.Hour
	if S.DayStart < S.NightStart then
		return h < S.DayStart or h >= S.NightStart
	end
	return h >= S.NightStart and h < S.DayStart
end

function M.GetSeason()
	for s = 0, 3 do
		if evt.CheckSeason{Season = s} then
			return s
		end
	end
end

local function addTracks(pool, list, exclusive)
	if not list or #list == 0 then
		return pool
	end
	if exclusive then
		pool = {}
	end
	for _, track in ipairs(list) do
		pool[#pool + 1] = track
	end
	return pool
end

local function ruleMatches(rule, mapIndex, outdoor, season)
	if rule.Maps and not table.find(rule.Maps, mapIndex) then return false end
	if rule.Outdoor ~= nil and rule.Outdoor ~= outdoor then return false end
	if rule.Season ~= nil and rule.Season ~= season then return false end
	return true
end

-- Track pool for a map right now (a new table, safe to modify)
function M.GetPool(mapIndex)
	local night = M.IsNight()
	local season = M.GetSeason()
	local outdoor = Map.IsOutdoor()
	local part = night and "Night" or "Day"

	local entry = M.Maps[mapIndex] or {}
	local base = entry.Any or (Game.MapMusicSets and Game.MapMusicSets[mapIndex])
	local pool = addTracks({}, base)

	pool = addTracks(pool, entry[part], entry[part .. "Exclusive"])

	local seasonal = entry.Seasons and season and entry.Seasons[season]
	if seasonal then
		local list = addTracks(addTracks({}, seasonal.Any), seasonal[part])
		pool = addTracks(pool, list, seasonal.Exclusive)
	end

	for _, rule in ipairs(M.Rules) do
		if ruleMatches(rule, mapIndex, outdoor, season) then
			local list = addTracks(addTracks({}, rule.Any), rule[part])
			pool = addTracks(pool, list, rule.Exclusive)
		end
	end

	return pool, night, season
end

---------------------------------------------------------------------------
-- track choice
---------------------------------------------------------------------------

local LastTrack

-- Random track for a map now, or nil if the map has no tracks
function M.PickTrack(mapIndex, reason, default)
	local pool, night, season = M.GetPool(mapIndex)

	-- don't repeat the previous track if there's anything else to play
	if S.NoRepeat and LastTrack and #pool > 1 then
		local others = {}
		for _, track in ipairs(pool) do
			if track ~= LastTrack then
				others[#others + 1] = track
			end
		end
		if #others > 0 then
			pool = others
		end
	end

	local c = {
		MapIndex = mapIndex, Pool = pool, Night = night, Season = season, Reason = reason,
		Track = #pool > 0 and pool[math.random(1, #pool)] or default,
	}
	events.call("ChooseMapTrack", c)
	if c.Track then
		LastTrack = c.Track
	end
	return c.Track
end

---------------------------------------------------------------------------
-- playback control (MM8 start_new_music)
---------------------------------------------------------------------------

local START_NEW_MUSIC = 0x4A862D

local MusicThis      -- music object passed by the game in ecx
local TrackDelta     -- start_new_music track = map track + TrackDelta
local PendingPick    -- map track chosen in PlayMapTrack, waiting for its start_new_music call
local CurrentTrack   -- map track playing now (map numbering)
local Forcing        -- our own start_new_music call is in progress

mem.hookfunction(START_NEW_MUSIC, 1, 1, function(d, def, this, track)
	MusicThis = this

	if Forcing then
		-- our own call (PlayNow)
	elseif PendingPick then
		-- the game starts the map track it just asked us for
		TrackDelta = track - PendingPick
		CurrentTrack = PendingPick
		PendingPick = nil
	elseif S.Enabled and S.NewTrackOnLoop and TrackDelta and CurrentTrack
			and track - TrackDelta == CurrentTrack and Game.CurrentScreen == 0 then
		-- the game restarts the same map track: play another one
		local new = M.PickTrack(Map.MapStatsIndex, "loop", CurrentTrack)
		if new then
			CurrentTrack = new
			track = new + TrackDelta
		end
	end

	return def(this, track)
end)

-- Play a map track right away. Returns false until the game has started music once.
function M.PlayNow(track)
	if not (MusicThis and TrackDelta) then
		return false
	end
	CurrentTrack = track
	Forcing = true
	local ok, err = pcall(mem.call, START_NEW_MUSIC, 1, MusicThis, track + TrackDelta)
	Forcing = false
	if not ok then
		error(err)
	end
	return true
end

---------------------------------------------------------------------------
-- map track choice
---------------------------------------------------------------------------

function events.PlayMapTrack(t)
	if not S.Enabled then
		PendingPick = t.Track
		return
	end
	t.Track = M.PickTrack(t.MapIndex, "map", t.Track)
	PendingPick = t.Track
end

---------------------------------------------------------------------------
-- ambience
---------------------------------------------------------------------------

-- Default ambience by map type. Fill in sound ids (a number, or a list for a random pick);
-- nil = no ambience.
M.Ambient = M.Ambient or {
	Outdoor = {Day = nil, Night = nil},
	Indoor  = {Day = nil, Night = nil},
}

local AMBIENT_OBJ = -2   -- the game gives sound object -2 its own channel (14)

-- make_sound internals (from the MM8 disassembly)
local SoundMgr                                     -- 'this' of make_sound
mem.autohook(0x4A87E9, function(d)                 -- mov esi, ecx (after the prologue)
	SoundMgr = d.ecx
end)
local function importAt(callAddr)                  -- call ds:[import] -> function address
	return mem.u4[mem.u4[callAddr + 2]]
end
local AIL_end_sample    = importAt(0x4A8FF9)
local AIL_end_3D_sample = importAt(0x4A8A8D)
local FreeChannel2D     = 0x4AA258                 -- thiscall(mgr, channel)
local FreeChannel3D     = 0x4AA329

local CurrentAmbient       -- sound id playing now (nil = none)

local function pickOne(v)
	if type(v) == "table" then
		return #v > 0 and v[math.random(1, #v)] or nil
	end
	return v
end

-- Ambience setting for a map now: a sound id, a list, false (silence) or nil (not set)
function M.GetAmbient(mapIndex)
	local night = M.IsNight()
	local key = night and "NightAmbient" or "DayAmbient"
	local season = M.GetSeason()
	local outdoor = Map.IsOutdoor()

	local entry = M.Maps[mapIndex]
	local seasonal = entry and entry.Seasons and season and entry.Seasons[season]
	if seasonal and seasonal[key] ~= nil then return seasonal[key] end
	if entry and entry[key] ~= nil then return entry[key] end

	local found
	for _, rule in ipairs(M.Rules) do
		if rule[key] ~= nil and ruleMatches(rule, mapIndex, outdoor, season) then
			found = rule[key]
		end
	end
	if found ~= nil then return found end

	local def = M.Ambient[outdoor and "Outdoor" or "Indoor"]
	return def and def[night and "Night" or "Day"]
end

-- Stop every channel playing this sound id (both 2D and 3D sound channels)
local function stopSoundId(id)
	if not SoundMgr or not id then return end
	local m = SoundMgr
	-- 2D channels: 16-byte entries at +2E8h (handle, object, index, sound id), count at +3E8h
	for ch = 0, mem.i4[m + 0x3E8] - 1 do
		local e = m + 0x2E8 + ch * 16
		if mem.i4[e + 0xC] == id and mem.i4[e + 4] == AMBIENT_OBJ then
			mem.call(AIL_end_sample, 0, mem.u4[e])
			mem.call(FreeChannel2D, 1, m, e)
		end
	end
	-- 3D channels: 16-byte entries at +14h (handle, object, index, sound id), count at +10h
	for ch = 0, mem.i4[m + 0x10] - 1 do
		local e = m + 0x14 + ch * 16
		if mem.i4[e + 0xC] == id and mem.i4[e + 4] == AMBIENT_OBJ then
			mem.call(AIL_end_3D_sample, 0, mem.u4[e])
			mem.call(FreeChannel3D, 1, m, e)
		end
	end
end

function M.StopAmbient()
	stopSoundId(CurrentAmbient)
	CurrentAmbient = nil
end

-- Start a looping ambience sound (stops the previous one). Calling it again with the
-- sound that is already playing does nothing: the game doesn't restart a playing sound.
function M.PlayAmbient(id)
	if id ~= CurrentAmbient then
		M.StopAmbient()
	end
	if id then
		Game.PlaySound(id, AMBIENT_OBJ, 1, -1, 0, 0, S.AmbientVolume or 0, 0)  -- loops = 1: forever
		CurrentAmbient = id
	end
end

local AmbientSetting   -- the setting the current sound was picked from (to keep a random pick)

local function updateAmbient(force)
	if not (S.Enabled and S.AmbientEnabled) then
		if CurrentAmbient then M.StopAmbient() end
		AmbientSetting = nil
		return
	end
	local setting = M.GetAmbient(Map.MapStatsIndex)
	if force or setting ~= AmbientSetting then
		AmbientSetting = setting
		M.PlayAmbient(setting and pickOne(setting) or nil)
	elseif CurrentAmbient then
		-- restart it if the game ended it (e.g. a louder sound took the channel)
		M.PlayAmbient(CurrentAmbient)
	end
end
M.UpdateAmbient = updateAmbient

---------------------------------------------------------------------------
-- dawn / dusk switch
---------------------------------------------------------------------------

local WasNight

local function trackFits(track, pool)
	for _, v in ipairs(pool) do
		if v == track then
			return true
		end
	end
	return false
end

local function checkDayNight()
	local night = M.IsNight()
	if WasNight == nil then
		WasNight = night
		return
	end
	if night == WasNight then
		return
	end
	-- only switch while walking around the map; otherwise try again next minute
	if not (S.Enabled and S.SwitchAtDawnDusk) or Game.CurrentScreen ~= 0 then
		if not (S.Enabled and S.SwitchAtDawnDusk) then
			WasNight = night
		end
		return
	end
	WasNight = night

	local mapIndex = Map.MapStatsIndex
	local pool = M.GetPool(mapIndex)
	if #pool == 0 or (CurrentTrack and trackFits(CurrentTrack, pool)) then
		return
	end
	local new = M.PickTrack(mapIndex, "daynight", CurrentTrack)
	if new then
		M.PlayNow(new)
	end
end

local function everyMinute()
	checkDayNight()
	updateAmbient()
end

function events.AfterLoadMap()
	WasNight = M.IsNight()
	M.StopAmbient()           -- in case the previous map's loop is still running
	updateAmbient(true)
	Timer(everyMinute, const.Minute)
end

	-- Random music for all maps
	---- MM8 Music
	Music.SetMap(1, {Any = {4}, Day = {59}, Night = {}})						-- Daggerwound Island
	Music.SetMap(2, {Any = {9}, Day = {53,114}, Night = {112}})					-- Ravenshore
	Music.SetMap(3, {Any = {3}, Day = {92,98,113,114}, Night = {127}})			-- Alvar
	Music.SetMap(4, {Any = {6}, Day = {58,90,105}, Night = {}})					-- Ironsand Desert
	Music.SetMap(5, {Any = {6}, Day = {87,92,128}, Night = {}})					-- Garrote Gorge
	Music.SetMap(6, {Any = {11,121}, Day = {66,92,128}, Night = {22,72}})		-- Shadowspire
	Music.SetMap(7, {Any = {13,64}, Day = {55,92,128}, Night = {67}})			-- Murmurwoods
	Music.SetMap(8, {Any = {6}, Day = {93,95,96}, Night = {}})					-- Ravage Roaming
	Music.SetMap(9, {Any = {9,76,64}})											-- Plane of Air
	Music.SetMap(10, {Any = {3,97,123}})										-- Plane of Earth
	Music.SetMap(11, {Any = {10,68,79,86,103}})									-- Plane of Fire
	Music.SetMap(12, {Any = {7,84,107}, Night = {24}})							-- Plane of Water
	Music.SetMap(13, {Any = {}, Day = {59,94,107}, Night = {}})					-- Regna
	Music.SetMap(14, {Any = {15,119}, Day = {106}, Night = {115,116,117,118}})	-- Plane Between Planes
	Music.SetMap(15, {Any = {2}})												-- Tutorial
	Music.SetMap(16, {Any = {3,122}})											-- Abandoned temple
	Music.SetMap(17, {Any = {10,134}})											-- Pirate Outpost
	Music.SetMap(18, {Any = {11,54,56}})										-- Smuggler's Cove
	Music.SetMap(19, {Any = {5,56,61}})											-- Dire Wolf Den
	Music.SetMap(20, {Any = {4,34}})											-- Merchant House of Alvar
	Music.SetMap(21, {Any = {2,118}})											-- Escaton's Crystal
	Music.SetMap(22, {Any = {12,56}})											-- Wasp Nest
	Music.SetMap(23, {Any = {13,56,62,89}})										-- Ogre Fortress
	Music.SetMap(24, {Any = {2,20,57,115,116}})									-- Troll Tomb
	Music.SetMap(25, {Any = {4,31,89}})											-- Cyclops Larder
	Music.SetMap(26, {Any = {7,79,103}})										-- Chain of Fire
	Music.SetMap(27, {Any = {9,89,130}})										-- Dragon Hunter's Camp
	Music.SetMap(28, {Any = {13,60}})											-- Dragon Cave
	Music.SetMap(29, {Any = {2,12}})											-- Naga Vault
	Music.SetMap(30, {Any = {11,72,106,34}})									-- Necromancer's Guild
	Music.SetMap(31, {Any = {86,88,106}})										-- Mad Necromancer's Lab
	Music.SetMap(32, {Any = {3,54,57,63}})										-- Vampire Crypt
	Music.SetMap(33, {Any = {13,132}})											-- Temple of the Sun
	Music.SetMap(34, {Any = {12,97,123}})										-- Druid Circle
	Music.SetMap(35, {Any = {11,116,137}})										-- Balthazar Lair
	Music.SetMap(36, {Any = {9,89}})											-- Barbarian Fortress
	Music.SetMap(37, {Any = {3,54,57,63}})										-- The Crypt of Korbu
	Music.SetMap(38, {Any = {4,134}})											-- Castle of Air
	Music.SetMap(39, {Any = {12,20}})											-- Tomb of Lord Brinne
	Music.SetMap(40, {Any = {6,79,86,103}})										-- Castle of Fire
	Music.SetMap(41, {Any = {7,86,103}})										-- War Camp
	Music.SetMap(42, {Any = {12,62,89,134}})									-- Pirate Stronghold
	Music.SetMap(43, {Any = {12,62,89,134}})									-- Abandoned Pirate Keep
	Music.SetMap(44, {Any = {12,60}})											-- Passage under Regna
	Music.SetMap(45, {Any = {11,23,116}})										-- Small Sub Pen
	Music.SetMap(46, {Any = {2,117}})											-- Escaton's Palace
	Music.SetMap(47, {Any = {3}})												-- Prison of the Lord of Air
	Music.SetMap(48, {Any = {5}})												-- Prison of the Lord of Fire
	Music.SetMap(49, {Any = {8,136}})											-- Prison of the Lord of Water
	Music.SetMap(50, {Any = {10,123}})											-- Prison of the Lord of Earth
	Music.SetMap(51, {Any = {7,24,134}})										-- Uplifted Library
	Music.SetMap(52, {Any = {3,54,56,61}})										-- Dark Dwarf Compound
	Music.SetMap(53, {Any = {5}})												-- Arena
	Music.SetMap(54, {Any = {8,136}})											-- Ancient Troll Home
	Music.SetMap(55, {Any = {10,88,89}})										-- Grand Temple of Eep
	Music.SetMap(56, {Any = {14}})												-- Chapel of Eep
	Music.SetMap(57, {Any = {2,10,89}})											-- Church of Eep
	Music.SetMap(58, {Any = {4,60}})											-- Old Loeb's Cave
	Music.SetMap(59, {Any = {7,60}})											-- Ilsingore's Cave
	Music.SetMap(60, {Any = {9,60}})											-- Yaardrake's Cave
	Music.SetMap(61, {Any = {6}})												-- NWC (MM8)
	Music.SetMap(205, {Any = {3,115,116,117,118,119}})							-- The Breach
	
	---- MM7 Music
	Music.SetMap(62, {Any = {35}, Day = {83,114}, Night = {}})					-- Emerald Island
	Music.SetMap(63, {Any = {19}, Day = {102,110,111,112,114,127}, Night = {}})	-- Harmondale
	Music.SetMap(64, {Any = {32}, Day = {69,80,111,112,114,128,131}, Night = {}})-- Erathia
	Music.SetMap(65, {Any = {33}, Day = {73,85,87,91,114,131,133}, Night = {}})	-- Tularean Forest
	Music.SetMap(66, {Any = {17,58}, Day = {74,104}, Night = {101}})			-- Deyja
	Music.SetMap(67, {Any = {17,58}, Day = {81,91,105}, Night = {}})			-- The Bracada Desert
	Music.SetMap(68, {Any = {21}, Day = {129}, Night = {}})						-- Evenmorn Island
	Music.SetMap(69, {Any = {26,71}, Day = {76,80,126}, Night = {}})			-- Mount Nighon
	Music.SetMap(70, {Any = {27}, Day = {80,120}, Night = {101}})				-- The Barrow Downs
	Music.SetMap(71, {Any = {27}, Day = {80,120,126}, Night = {}})				-- The Land of Giants
	Music.SetMap(72, {Any = {19}, Day = {65,83,126,128}, Night = {}})			-- Tatalia
	Music.SetMap(73, {Any = {19}, Day = {73,85,87,109}, Night = {}})			-- Avlee
	Music.SetMap(74, {Any = {24}, Day = {}, Night = {}})						-- Shoals
	Music.SetMap(75, {Any = {18,56,62}})										-- The Erathian Sewers
	Music.SetMap(76, {Any = {18,54,62,70}})										-- The Maze
	Music.SetMap(77, {Any = {22,72,108,117}})									-- Castle Gloaming
	Music.SetMap(78, {Any = {28,134}})											-- The Temple of Baa
	Music.SetMap(79, {Any = {23}})												-- Arena
	Music.SetMap(80, {Any = {28,134}})											-- The Temple of the Moon
	Music.SetMap(81, {Any = {31,70,79}})										-- Thunderfist Mountain
	Music.SetMap(82, {Any = {18,54,56,62}})										-- The Tularean Caves
	Music.SetMap(83, {Any = {31,71,137}})										-- The Titan's Stronghold
	Music.SetMap(84, {Any = {18,60,62,68,123}})									-- The Breeding Zone
	Music.SetMap(85, {Any = {18,60,62,76,116}})									-- The Walls of Mist
	Music.SetMap(86, {Any = {18,86,88}})										-- Clanker's Laboratory
	Music.SetMap(87, {Any = {20,57,63,68,115}})									-- Zokarr's Tomb
	Music.SetMap(88, {Any = {34,76}})											-- The School of Sorcery
	Music.SetMap(89, {Any = {18,54,68,72}})										-- Watchtower 6
	Music.SetMap(90, {Any = {56,57,63,68}})										-- The Wine Cellar
	Music.SetMap(91, {Any = {18,56,62}})										-- The Tidewater Caverns
	Music.SetMap(92, {Any = {34}})												-- Lord Markham's Manor
	Music.SetMap(93, {Any = {28,134}})											-- Grand Temple of the Moon
	Music.SetMap(94, {Any = {34}})												-- The Mercenary Guild
	Music.SetMap(95, {Any = {18,54,56,61}})										-- White Cliff Cave
	Music.SetMap(96, {Any = {18,84,133}})										-- The Hall under the Hill
	Music.SetMap(97, {Any = {23,116}})											-- The Lincoln
	Music.SetMap(98, {Any = {34,70,84}})										-- Stone City
	Music.SetMap(99, {Any = {25,99,75,132}})									-- Celeste
	Music.SetMap(100, {Any = {22,72,117,121,134}})								-- The Pit
	Music.SetMap(101, {Any = {108,122,123}})									-- Colony Zod
	Music.SetMap(102, {Any = {28,60}})											-- The Dragon's Lair
	Music.SetMap(103, {Any = {34,135,138}})										-- Castle Harmondale
	Music.SetMap(104, {Any = {30,31,75}})										-- Castle Lambent
	Music.SetMap(105, {Any = {34}})												-- Fort Riverstride
	Music.SetMap(106, {Any = {29,109}})											-- Castle Navan
	Music.SetMap(107, {Any = {29, 100}})										-- Castle Gryphonheart
	Music.SetMap(108, {Any = {18,54,56,61}})									-- The Red Dwarf Mines
	Music.SetMap(109, {Any = {18,60,61,119}})									-- Nighon Tunnels
	Music.SetMap(110, {Any = {31,54,61,71}})									-- Tunnels to Eeofol
	Music.SetMap(111, {Any = {57,63,68,117}})									-- The Haunted Mansion
	Music.SetMap(112, {Any = {20,57,63,68,115}})								-- Barrow VII
	Music.SetMap(113, {Any = {20,57,63,68,115}})								-- Barrow IV
	Music.SetMap(114, {Any = {20,57,63,68,115}})								-- Barrow II
	Music.SetMap(115, {Any = {20,57,63,68,115}})								-- Barrow XIV
	Music.SetMap(116, {Any = {20,57,63,68,115}})								-- Barrow III
	Music.SetMap(117, {Any = {20,57,63,68,115}})								-- Barrow IX
	Music.SetMap(118, {Any = {20,57,63,68,115}})								-- Barrow VI
	Music.SetMap(119, {Any = {20,57,63,68,115}})								-- Barrow I
	Music.SetMap(120, {Any = {20,57,63,68,115}})								-- Barrow VIII
	Music.SetMap(121, {Any = {20,57,63,68,115}})								-- Barrow XIII
	Music.SetMap(122, {Any = {20,57,63,68,115}})								-- Barrow X
	Music.SetMap(123, {Any = {20,57,63,68,115}})								-- Barrow XII
	Music.SetMap(124, {Any = {20,57,63,68,115}})								-- Barrow V
	Music.SetMap(125, {Any = {20,57,63,68,115}})								-- Barrow XI
	Music.SetMap(126, {Any = {20,57,63,68,115}})								-- Barrow XV
	Music.SetMap(127, {Any = {18,60}})											-- Wromthrax's Cave
	Music.SetMap(128, {Any = {34}})												-- William Setag's Tower
	Music.SetMap(129, {Any = {18,62,117}})										-- The Hidden Tomb
	Music.SetMap(130, {Any = {31,71}})											-- The Dragon Caves
	Music.SetMap(131, {Any = {34}})												-- The Bandit Caves
	Music.SetMap(132, {Any = {34}})												-- The Small House
	Music.SetMap(133, {Any = {28,132}})											-- The Temple of the Light
	Music.SetMap(134, {Any = {28,134}})											-- The Temple of the Dark
	Music.SetMap(135, {Any = {28,132}})											-- Grand Temple of the Sun
	Music.SetMap(136, {Any = {18,60,62,68}})									-- The Hall of the Pit
	Music.SetMap(207, {Any = {34}})												-- The Strange Temple
	
	---- MM6 Music
	Music.SetMap(137, {Any = {40}, Day = {80,104,134}, Night = {}})				-- Sweet Water
	Music.SetMap(138, {Any = {51}, Day = {58}, Night = {}})						-- Paradise Valley
	Music.SetMap(139, {Any = {41}, Day = {58,105}, Night = {}})					-- Hermit's Isle
	Music.SetMap(140, {Any = {47}, Day = {80,82,91,126}, Night = {}})			-- Kriegspire
	Music.SetMap(141, {Any = {41}, Day = {67,80,90,92}, Night = {}})			-- Blackshire
	Music.SetMap(142, {Any = {41,58}, Day = {81,105}, Night = {}})				-- Dragonsand
	Music.SetMap(143, {Any = {47}, Day = {75,82,91,126}, Night = {}})			-- The Frozen Highlands
	Music.SetMap(144, {Any = {51}, Day = {77,92,93,98,127,130,131}, Night = {}})-- Free Haven
	Music.SetMap(145, {Any = {48,65,83}, Day = {66}, Night = {67,106}})			-- Mire of the Damned
	Music.SetMap(146, {Any = {37,38,39}, Day = {73,78,114,127}, Night = {67}})	-- Silver Cove
	Music.SetMap(147, {Any = {37,38,39}, Day = {92,94,107}, Night = {65}})		-- Bootleg Bay
	Music.SetMap(148, {Any = {37,38,39}, Day = {78,80,112,127,128,131}, Night = {}})-- Castle Ironfist
	Music.SetMap(149, {Any = {37,38,39}, Day = {91,94,107}, Night = {65}})		-- Eel Infested Waters
	Music.SetMap(150, {Any = {37,38,39}, Day = {91,94,107}, Night = {65}})		-- Misty Islands
	Music.SetMap(151, {Any = {37,38,39}, Day = {111,114,127,128}, Night = {}})	-- New Sorpigal
	Music.SetMap(152, {Any = {43,62}})											-- Goblinwatch
	Music.SetMap(153, {Any = {44,122}})											-- Abandoned Temple
	Music.SetMap(154, {Any = {41,42,43,56,61,62,134}})							-- Shadow Guild Hideout
	Music.SetMap(155, {Any = {41,42,43,79,97,123}})								-- Hall of the Fire Lord
	Music.SetMap(156, {Any = {41,42,43,54,56,61}})								-- Snergle's Caverns
	Music.SetMap(157, {Any = {41,42,43,56,61,62}})								-- Dragoon's Caverns
	Music.SetMap(158, {Any = {41,42,43,134,137}})								-- Silver Helm Outpost
	Music.SetMap(159, {Any = {41,42,43,56,61,62,134}})							-- Shadow Guild
	Music.SetMap(160, {Any = {41,42,43,54,56,61}})								-- Snergle's Iron Mines
	Music.SetMap(161, {Any = {41,42,43,56,61,62}})								-- Dragoon's Keep
	Music.SetMap(162, {Any = {41,42,43,57,63,68,115}})							-- Corlagon's Estate
	Music.SetMap(163, {Any = {41,42,43,134,137}})								-- Silver Helm Stronghold
	Music.SetMap(164, {Any = {41,42,43,123}})									-- The Monolith
	Music.SetMap(165, {Any = {41,42,43,57,115,116}})							-- Tomb of Ethric The Mad
	Music.SetMap(166, {Any = {41,42,43,62,89}})									-- Icewind Keep
	Music.SetMap(167, {Any = {41,42,43,62,89}})									-- Warlord's Fortress
	Music.SetMap(168, {Any = {41,42,43,54,56}})									-- Wolf's Lair
	Music.SetMap(169, {Any = {41,42,43,86,88}})									-- Gharik's Forge
	Music.SetMap(170, {Any = {41,42,43,86,88}})									-- Agar's Laboratory
	Music.SetMap(171, {Any = {41,42,43,56,62}})									-- Caves of the Dragon Riders
	Music.SetMap(172, {Any = {49,50,129,134,137}})								-- Temple of Baa
	Music.SetMap(173, {Any = {49,50,129,134,137}})								-- Temple of the Fist
	Music.SetMap(174, {Any = {49,50,122,123}})									-- Temple of Tsantsa
	Music.SetMap(175, {Any = {49,50,129,134,137}})								-- Temple of the Sun
	Music.SetMap(176, {Any = {49,50,129,134,137}})								-- Temple of the Moon
	Music.SetMap(177, {Any = {49,50,129,134,137}})								-- Spreme Temple of Baa
	Music.SetMap(178, {Any = {49,50,129,134,137}})								-- Superior Temple of Baa
	Music.SetMap(179, {Any = {49,50,122,123}})									-- Temple of the Snake
	Music.SetMap(180, {Any = {50,86,116,117}})									-- Castle Alamos
	Music.SetMap(181, {Any = {50,54,116,117,118,119,121}})						-- Castle Darkmoor
	Music.SetMap(182, {Any = {50,54,70,71,116,117,118,119}})					-- Castle Kriegspire
	Music.SetMap(183, {Any = {44,56,62}})										-- Free Haven Sewer
	Music.SetMap(184, {Any = {23,46,116}})										-- Tomb of VARN
	Music.SetMap(185, {Any = {23,46,116}})										-- Oracle of Enroth
	Music.SetMap(186, {Any = {23,46,116}})										-- Control Center
	Music.SetMap(187, {Any = {122,123,108}})									-- The Hive
	Music.SetMap(188, {Any = {45}})												-- The Arena
	Music.SetMap(189, {Any = {42,60}})											-- Dragon's Lair
	Music.SetMap(192, {Any = {42}})												-- Warehouse
	Music.SetMap(202, {Any = {42,108}})											-- Devil Outpost
	Music.SetMap(203, {Any = {37,38,39}})										-- New World Computing
	Music.SetMap(204, {Any = {37,38,39}})										-- The Breach
	Music.SetMap(206, {Any = {42}})												-- Basement of the Breach
