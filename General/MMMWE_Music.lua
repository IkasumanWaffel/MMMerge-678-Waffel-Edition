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
