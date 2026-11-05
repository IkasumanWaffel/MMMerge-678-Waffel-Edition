--[[
	MMMWE_Sun.lua — a sun in the sky of outdoor maps (06.11.26, prototype)

	The sun is a game object (ObjList.txt "Sun" 12070, SFT group sunwe, sprite sunwe in
	Data\waffel.sprites.lod: a placeholder glow) kept every frame at SUN.Distance from the
	party in the direction of the sun. It rises in the east at SUN.Sunrise, is highest in the
	south at noon (SUN.MaxElevation degrees) and sets in the west at SUN.Sunset. Mountains,
	trees and buildings between the party and the sun hide it, as it is a real object.

	Known limit: the sun can't be farther than the game draws objects, so at sunrise and
	sunset it shows in front of mountains that are farther away than SUN.Distance.

	Not shown: indoors, at night, in thick fog (weather fog that ends before the sun, and
	always-foggy maps like Deyja after the Necromancers' quest), and on the maps in
	SUN.NoSunMaps. Light weather fog only fades it.

	The object is made from a summoned Laser (555) whose type is changed to 12070: the game
	doesn't draw objects summoned with a type added to ObjList.txt, but draws them once made.
	It is removed and made anew on every map load, so saved games may hold a stray one that
	is cleaned up when the map is loaded.

	Console: Merge.Functions.SunInfo() prints the time, the sun's angles, its object and its
	picture. Merge.Functions.SunRemake() makes the object anew (after changing SunSettings).
--]]

local MF = Merge.Functions
local floor, sin, cos, pi, max, min = math.floor, math.sin, math.cos, math.pi, math.max, math.min

local SUN = {
	Id           = 12070,      -- ObjList.txt
	SummonId     = 555,        -- what is summoned and turned into the sun (Laser)
	Group        = "sunwe",    -- SFT group
	Picture      = "own",      -- "bolt": the blaster bolt's picture (a test)
	Scale        = 196608,     -- size of the picture (65536 = 1:1; at 7000 the 128 px sun is about 3 degrees)
	Distance     = 7000,       -- from the party (keep below ViewDistanceD3D in mm8.ini)
	Sunrise      = 5.5,        -- hours
	Sunset       = 20.5,
	MaxElevation = 60,         -- degrees above the horizon at noon
	EyeHeight    = 160,
	FogMargin    = 1.2,        -- weather fog hides the sun when it ends closer than Distance x this
	NoSunMaps    = {},         -- ["7out05.odm"] = true ...
}
MF.SunSettings = SUN

local sunIndex     -- Map.Objects index of the sun
local typeIndex    -- ObjList line of SUN.Id

local function findType(id)
	for i, o in Game.ObjListBin do
		if o.Id == id then return i end
	end
end

local function group()
	local ok, g = pcall(function() return Game.SFTBin:FindGroup(SUN.Group) end)
	return ok and g and g >= 0 and g or nil
end

-- the frame of the sun's group, loaded, at SUN.Scale; with SUN.Picture = "bolt" it shows the
-- blaster bolt's picture instead (to tell a picture that doesn't load from an object that
-- isn't drawn)
local function prepareFrame()
	local g = group()
	if not g then return end
	pcall(function()
		local SFT = Game.SFTBin
		SFT:LoadGroup(g)
		local f = SFT.Frames[g]
		if SUN.Picture == "bolt" then
			local b = SFT:FindGroup("lzrbolt")
			SFT:LoadGroup(b)
			for k = 0, 7 do f.SpriteIndex[k] = SFT.Frames[b].SpriteIndex[k] end
			f.Loaded = true
		end
		f.Scale = SUN.Scale
	end)
	-- the ObjList line points to the group (in case the table was compiled before the group existed)
	pcall(function()
		local d = Game.ObjListBin[typeIndex]
		if d.SFTIndex ~= g then
			MF.LogWarning("Sun: ObjList %d pointed to SFT %d, set to %d (%s)", SUN.Id, d.SFTIndex, g, SUN.Group)
			d.SFTIndex = g
		end
	end)
end

local function diag()
	local t = {}
	pcall(function()
		local d = Game.ObjListBin[typeIndex]
		t[#t + 1] = string.format("objlist %d '%s' SFTIndex %d Bits %X", typeIndex, d.Name, d.SFTIndex, d.Bits)
	end)
	local g = group()
	t[#t + 1] = "group " .. tostring(g)
	if g then pcall(function()
		local f = Game.SFTBin.Frames[g]
		t[#t + 1] = string.format("frame '%s'/'%s' sprite %d loaded %s scale %d", f.GroupName, f.SpriteName,
			f.SpriteIndex[0], tostring(f.Loaded), f.Scale)
	end) end
	return table.concat(t, "; ")
end

function events.GameInitialized2()
	typeIndex = findType(SUN.Id)
	if not typeIndex then
		MF.LogWarning("Sun: ObjList.txt has no object %d, no sun", SUN.Id)
	end
end

-- hours of the day (0..24), the sun's direction: azimuth (radians, 0 = east, counterclockwise)
-- and elevation (radians); nil at night
local function sunAngles()
	local day = Game.Time % const.Day
	local h = day / const.Hour
	if h <= SUN.Sunrise or h >= SUN.Sunset then return nil, nil, h end
	local f = (h - SUN.Sunrise) / (SUN.Sunset - SUN.Sunrise)       -- 0 sunrise .. 1 sunset
	local az = -pi * f                                              -- east -> south -> west
	local el = SUN.MaxElevation * pi / 180 * sin(pi * f)
	return az, el, h
end

-- too foggy to see the sun: an always-foggy map, or weather fog that ends before the sun
-- (light fog only fades it, as it does everything far away)
local function foggy()
	local fog = false
	pcall(function()
		local w = Game.Weather
		fog = w.Fog and (w.FogRange2 or 0) < SUN.Distance * SUN.FogMargin
	end)
	pcall(function() fog = fog or Map.OutdoorExtra.AlwaysFoggy end)
	return fog
end

local function shown()
	if not Map.IsOutdoor() or not typeIndex then return false end
	if SUN.NoSunMaps[Map.Name:lower()] then return false end
	if foggy() then return false end
	return sunAngles() ~= nil
end

local function sunObject()
	local o = sunIndex and Map.Objects[sunIndex]
	if o and o.Type == SUN.Id and not o.Removed then return o end
	sunIndex = nil
end

local function makeSun()
	prepareFrame()
	local before = {}
	for i = 0, Map.Objects.count - 1 do before[i] = Map.Objects[i].Type end
	local ok = pcall(Game.SummonObjects, SUN.SummonId, Party.X, Party.Y, Party.Z + 500, 0, 1)
	if not ok then return end
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == SUN.SummonId and not o.Removed and before[i] ~= SUN.SummonId then
			o.Type, o.TypeIndex = SUN.Id, typeIndex
			o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
			o.Age, o.MaxAge = 0, 0
			o.Owner, o.Target = 0, 0
			pcall(function()
				o.Missile = false; o.Temporary = false; o.HaltTurnBased = false
				o.Visible = true; o.IgnoreRange = true
			end)
			sunIndex = i
			MF.LogInfo("Sun: object %d made; %s", i, diag())
			return o
		end
	end
end

-- the sun's object left from a saved game or an earlier visit
local function removeStray()
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == SUN.Id and not o.Removed then o.Removed = true; o.Visible = false end
	end
	sunIndex = nil
end

function events.AfterLoadMap()
	removeStray()
end

function events.LeaveMap()
	removeStray()
end

function events.Tick()
	if not typeIndex then return end
	local o = sunObject()
	if not shown() then
		if o then o.Visible = false end
		return
	end
	o = o or makeSun()
	if not o then return end
	local az, el = sunAngles()
	local d = SUN.Distance
	if SUN.Test == "front" then          -- a test: right in front of the party, at eye height
		az, el, d = (Party.Direction or 0) * pi / 1024, 0, 600
	end
	local h = d * cos(el)
	o.X = floor(Party.X + h * cos(az))
	o.Y = floor(Party.Y + h * sin(az))
	o.Z = floor(Party.Z + SUN.EyeHeight + d * sin(el))
	o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
	o.Visible = true
end

function MF.SunInfo()
	local az, el, h = sunAngles()
	local o = sunObject()
	local s = string.format("time %.2f h; sun %s; object %s", h,
		az and string.format("azimuth %d, elevation %d degrees", floor(-az * 180 / pi), floor(el * 180 / pi)) or "below the horizon",
		o and string.format("%d at %d, %d, %d, visible %s", sunIndex, o.X, o.Y, o.Z, tostring(o.Visible)) or "none")
	local fr = "?"
	pcall(function() fr = string.format("%s, ends at %d", tostring(Game.Weather.Fog), Game.Weather.FogRange2) end)
	s = s .. string.format("\nshown %s (outdoor %s, too foggy %s; weather fog %s)", tostring(shown()),
		tostring(Map.IsOutdoor()), tostring(foggy()), fr)
	s = s .. "\n" .. diag()
	print(s)
	return s
end

function MF.SunRemake()
	removeStray()
end

-- a test: a plain Laser (the blaster bolt, which the game is known to draw) standing still
-- 600 in front of the party, untouched by this script after it is made
function MF.SunTestLaser()
	local ang = (Party.Direction or 0) * pi / 1024
	local x, y, z = floor(Party.X + 600 * cos(ang)), floor(Party.Y + 600 * sin(ang)), Party.Z + SUN.EyeHeight
	local before = {}
	for i = 0, Map.Objects.count - 1 do before[i] = Map.Objects[i].Type end
	if MF.LoadSFTGroup then MF.LoadSFTGroup("lzrbolt") end
	Game.SummonObjects(SUN.SummonId, x, y, z, 0, 1)
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == SUN.SummonId and not o.Removed and before[i] ~= SUN.SummonId then
			o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
			o.Age, o.MaxAge = 0, 2000
			pcall(function() o.Visible = true; o.Missile = false end)
			local s = string.format("laser %d at %d, %d, %d", i, o.X, o.Y, o.Z)
			print(s)
			return s
		end
	end
	return "no laser made"
end
