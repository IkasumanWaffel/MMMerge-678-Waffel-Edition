--[[
	MMMWE_Moon.lua — the moon in the sky of outdoor maps, with its phases (07.11.26)

	Made the same way as the sun (MMMWE_Sun.lua: read it for how the object is made, kept
	and hidden): ObjList.txt "Moon" 12171, SFT groups moonwe1..moonwe7, sprites in
	Data\waffel.sprites.lod made by Tools\make_moon_sprites.py from a photo of the full moon.

	Phases follow the month (28 days): new moon at the start of the month, first quarter in
	the second week, full moon on the 15th, last quarter in the fourth week. Seven pictures
	(waxing crescent .. waning crescent); at new moon it isn't shown.

	It rises and sets like the sun, MOON.Rise hours later per day of the phase: at new moon
	with the sun, at full moon 12 hours later (it rises at sunset and sets at sunrise). By
	day it shows as well, pale against the blue (MOON.ByDay = false: only while the sun is
	down).

	Hidden: indoors, under an overcast, stormy or dark sky (MF.SunSettings.CloudySkies), in thick fog, below the skyline (the map's height grid, as the sun),
	at new moon, and on the maps in MOON.NoMoonMaps.

	The halo: pale dots around the lit part, in the pictures. At night a sprite is lit by the
	dark ambient unless its frame has its own light: MOON.LightRadius (SFT LightRadius, as
	the spells' bolts), changed live. MOON.Distance can be changed live too (the size kept).

	Console: Merge.Functions.MoonInfo() prints the phase, the moon's angles and its object;
	Merge.Functions.MoonSettings holds the settings.
--]]

local MF = Merge.Functions
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey
local floor, sin, cos, pi, max, min = math.floor, math.sin, math.cos, math.pi, math.max, math.min
local atan2 = math.atan2

local MOON = {
	Id           = 12171,      -- ObjList.txt (12110..12999, see MMMWE_Sun.lua)
	SummonId     = 555,        -- what is summoned and turned into the moon (Laser)
	Groups       = {"moonwe1", "moonwe2", "moonwe3", "moonwe4", "moonwe5", "moonwe6", "moonwe7"},
	Scale        = 267000,     -- at RefDistance: the 256 px sprite (disc 176 px, the rest its halo),
	                           -- about the sun's size
	Distance     = 6900,       -- a little nearer than the sun: in front of it when they meet
	RefDistance  = 6900,       -- the picture is scaled by Distance / RefDistance: the same size
	                           -- in the sky at any distance (nearer: less faded by the night)
	LightRadius  = 512,        -- the frames' own light: lit by it, not by the dark night ambient
	                           -- (spells 48..256); changed live
	MaxElevation = 55,         -- degrees above the horizon at its highest
	EyeHeight    = 160,
	MonthDays    = 28,
	ByDay        = true,       -- shown while the sun is up too
	Skyline      = true,
	SkylineMargin = 0,
	FogMargin    = 1.2,
	NoMoonMaps   = {},         -- ["7out05.odm"] = true ...
}
MF.MoonSettings = MOON

local moonIndex, typeIndex
local groups, stage = {}, nil
local scaledFor          -- the distance the frames are scaled for

local function findType(id)
	for i, o in Game.ObjListBin do
		if o.Id == id then return i end
	end
end

local function sunTimes()
	local S = MF.SunSettings
	return S and S.Sunrise or 5.5, S and S.Sunset or 20.5
end

-- the phase: 0 new .. 0.5 full .. 1; and the picture (0 = none, 1..7)
local function phase()
	local days = Game.Time / const.Day
	local f = (days % MOON.MonthDays) / MOON.MonthDays
	local k = floor(f * 8 + 0.5) % 8
	return f, k
end

-- the moon's azimuth (0 east, counterclockwise) and elevation (radians), nil below the horizon:
-- the sun's path, later by the phase of the month
local function moonAngles()
	local rise, set = sunTimes()
	local f = phase()
	local h = (Game.Time % const.Day) / const.Hour
	local hm = (h - f * 24) % 24
	if hm <= rise or hm >= set then return nil, nil, h end
	local g = (hm - rise) / (set - rise)
	return -pi * g, MOON.MaxElevation * pi / 180 * sin(pi * g), h
end

local function sunUp()
	local rise, set = sunTimes()
	local h = (Game.Time % const.Day) / const.Hour
	return h > rise and h < set
end

local function foggy()
	local fog = false
	pcall(function()
		local w = Game.Weather
		fog = w.Fog and (w.FogRange2 or 0) < MOON.Distance * MOON.FogMargin
	end)
	pcall(function() fog = fog or Map.OutdoorExtra.AlwaysFoggy end)
	return fog
end

-- the land's highest angle toward the azimuth (as the sun's; its own cache)
local skyKey, skyAngle
local function skyline(az)
	local eye = Party.Z + MOON.EyeHeight
	local key = string.format("%d:%d:%d:%d", floor(Party.X / 512), floor(Party.Y / 512), floor(eye / 64), floor(az * 720 / pi))
	if key == skyKey then return skyAngle end
	local best = -pi / 2
	local ok = pcall(function()
		local hm = Map.HeightMap
		local cx, cy = cos(az), sin(az)
		local d = 512
		while true do
			local ix = floor(64 + (Party.X + cx * d) / 512 + 0.5)
			local iy = floor(64 - (Party.Y + cy * d) / 512 + 0.5)
			if ix < 0 or ix > 127 or iy < 0 or iy > 127 then break end
			local a = atan2(hm[iy][ix] * 32 - eye, d)
			if a > best then best = a end
			d = d + 256
		end
	end)
	skyKey, skyAngle = key, ok and best or -pi / 2
	return skyAngle
end

local function shown()
	if not Map.IsOutdoor() or not typeIndex then return false end
	if MOON.NoMoonMaps[Map.Name:lower()] then return false end
	local _, k = phase()
	if k == 0 then return false end
	if not MOON.ByDay and sunUp() then return false end
	if foggy() then return false end
	if MF.SkyCloudy and MF.SkyCloudy() then return false end   -- overcast, stormy or dark (MMMWE_Sun.lua)
	local az, el = moonAngles()
	if not az then return false end
	if MOON.Skyline and skyline(az) >= el + MOON.SkylineMargin * pi / 180 then return false end
	return true
end

local function prepareFrames()
	groups = {}
	for k, name in ipairs(MOON.Groups) do
		local ok, g = pcall(function() return Game.SFTBin:FindGroup(name) end)
		if ok and g and g >= 0 then
			groups[k] = g
			pcall(function() Game.SFTBin:LoadGroup(g) end)
		end
	end
	stage = nil
	scaledFor = nil
end

local function scaleFrames()
	local key = MOON.Distance .. ":" .. MOON.LightRadius .. ":" .. MOON.Scale
	if scaledFor == key then return end
	local sc = floor(MOON.Scale * MOON.Distance / MOON.RefDistance)
	for _, g in pairs(groups) do
		pcall(function()
			local f = Game.SFTBin.Frames[g]
			f.Scale = sc
			f.LightRadius = MOON.LightRadius
		end)
	end
	scaledFor = key
end

local function setStage(k)
	if k == stage or not groups[k] then return end
	pcall(function()
		local d = Game.ObjListBin[typeIndex]
		if d.Name == "Moon" then d.SFTIndex = groups[k] end
	end)
	stage = k
end

-- (08.11.26) the index of the object made, if it is still in the map's object list: a loaded
-- game (the same map reloaded) can have fewer objects than the index
local function objectAt(i)
	if i and i >= 0 and i < Map.Objects.count then return Map.Objects[i] end
end

local function moonObject()
	local o = objectAt(moonIndex)
	if o and o.Type == MOON.Id and not o.Removed then return o end
	moonIndex = nil
end

local function makeMoon()
	typeIndex = findType(MOON.Id) or typeIndex
	prepareFrames()
	local before = {}
	for i = 0, Map.Objects.count - 1 do before[i] = Map.Objects[i].Type end
	local ok = pcall(Game.SummonObjects, MOON.SummonId, Party.X, Party.Y, Party.Z + 500, 0, 1)
	if not ok then return end
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == MOON.SummonId and not o.Removed and before[i] ~= MOON.SummonId then
			o.Type, o.TypeIndex = MOON.Id, typeIndex
			o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
			o.Age, o.MaxAge = 0, 30000
			o.Owner, o.Target = 0, 0
			pcall(function()
				o.Missile = false; o.Temporary = true; o.HaltTurnBased = false
				o.Visible = true; o.IgnoreRange = true
			end)
			moonIndex = i
			return o
		end
	end
end

-- hidden by removing (the Visible bit doesn't stop the game drawing it)
local function removeObject(o)
	o.Removed = true
	o.Z = -30000
	o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
end

local function removeStray()
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == MOON.Id and not o.Removed then removeObject(o) end
	end
	moonIndex = nil
end

function events.GameInitialized2()
	typeIndex = findType(MOON.Id)
	if not typeIndex then MF.LogWarning("Moon: ObjList.txt has no object %d, no moon", MOON.Id) end
end

function events.LoadMap()
	moonIndex = nil           -- the objects are the loaded game's now
end

function events.AfterLoadMap()
	removeStray()
end

function events.LeaveMap()
	removeStray()
end

function events.Tick()
	if not typeIndex then return end
	local o = moonObject()
	if not shown() then
		if o then removeObject(o); moonIndex = nil end
		return
	end
	o = o or makeMoon()
	if not o then return end
	local _, k = phase()
	setStage(k)
	scaleFrames()
	local az, el = moonAngles()
	local d = MOON.Distance
	local h = d * cos(el)
	o.X = floor(Party.X + h * cos(az))
	o.Y = floor(Party.Y + h * sin(az))
	o.Z = floor(Party.Z + MOON.EyeHeight + d * sin(el))
	o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
	o.Age = 0
	o.Visible = true
end

local PHASE_NAMES = {[0] = Tx"new moon", Tx"waxing crescent", Tx"first quarter", Tx"waxing gibbous", Tx"full moon",
	Tx"waning gibbous", Tx"last quarter", Tx"waning crescent"}

function MF.MoonInfo()
	local f, k = phase()
	local az, el, h = moonAngles()
	local o = moonObject()
	local s = string.format(Tx"day %.1f of the month: %s (picture %d); time %.2f h; moon %s; object %s; shown %s",
		f * MOON.MonthDays + 1, PHASE_NAMES[k], k, h,
		az and string.format(Tx"azimuth %d, elevation %d degrees", floor(-az * 180 / pi), floor(el * 180 / pi)) or Tx"below the horizon",
		o and string.format(Tx"%d at %d, %d, %d", moonIndex, o.X, o.Y, o.Z) or "none", tostring(shown()))
	if az then s = s .. string.format(Tx"; skyline %.1f degrees", skyline(az) * 180 / pi) end
	print(s)
	return s
end
