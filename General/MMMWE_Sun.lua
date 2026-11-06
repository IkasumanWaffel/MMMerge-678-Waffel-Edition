--[[
	MMMWE_Sun.lua — a sun in the sky of outdoor maps (06.11.26, prototype)

	The sun is a game object (ObjList.txt "Sun" 12170, SFT group sunwe, sprite sunwe in
	Data\waffel.sprites.lod, palette 536: cut from a photo by Tools\make_sun_sprite.py) kept every frame at SUN.Distance from the
	party in the direction of the sun. It rises in the east at SUN.Sunrise, is highest in the
	south at noon (SUN.MaxElevation degrees) and sets in the west at SUN.Sunset. Mountains,
	trees and buildings between the party and the sun hide it, as it is a real object.

	Low in the sky it turns golden, orange and red (SUN.Groups, by SUN.Redden degrees of
	elevation): the four pictures are the photo tinted by Tools\make_sun_sprite.py --set.

	The skyline: mountains closer than SUN.Distance hide the sun as they stand in front of it,
	but the land farther away doesn't. So the script looks along the map's height grid toward
	the sun, up to the map's edge, and hides the sun once its centre sinks below the highest
	land in its direction (SUN.SkylineMargin degrees lower or higher). It is checked again when
	the party moves to another 512 x 512 square, climbs or drops, or the sun moves a quarter
	of a degree.

	Not shown: indoors, at night, under an overcast, stormy or dark sky (SUN.CloudySkies, also
	for the moon), in thick fog (weather fog that ends before the sun, and
	always-foggy maps like Deyja after the Necromancers' quest), and on the maps in
	SUN.NoSunMaps. Light weather fog only fades it.

	Its id must be from 12110 to 12999. The game hands objects with ids 500-599 and 1000-12999
	to its spell effects code, which draws only the spells it knows (12070 was never drawn);
	Spells.lua lets ids from 12110 up through (or Game.MissileSetup flags, if set). Ids from
	13000 up are taken for items by RemoveItemsLimits.lua and crash the game (13070 did).

	The object is made from a summoned Laser (555) whose type is changed to the sun's: the game
	doesn't draw objects summoned with a type added to ObjList.txt, but draws them once made.
	It must be a Temporary object (ObjList.txt and the object's bit): the game takes objects
	that aren't temporary for items lying around and draws the item's picture, so an object
	without an item isn't drawn at all. Its age is reset every frame, so it never runs out.
	It is removed when hidden (night, fog, below the skyline) and made anew when shown, and on every map load, so saved games may hold a stray one that
	is cleaned up when the map is loaded.

	Console: Merge.Functions.SunInfo() prints the time, the sun's angles, its object and its
	picture. Merge.Functions.SunRemake() makes the object anew (after changing SunSettings).
--]]

local MF = Merge.Functions
local floor, sin, cos, pi, max, min = math.floor, math.sin, math.cos, math.pi, math.max, math.min
local atan2 = math.atan2

local SUN = {
	Id           = 12170,      -- ObjList.txt (12110..12999: see above)
	SummonId     = 555,        -- what is summoned and turned into the sun (Laser)
	Groups       = {"sunwe", "sunwe1", "sunwe2", "sunwe3"},   -- SFT groups: white, golden, orange, red
	Redden       = {15, 8, 3}, -- elevation (degrees) below which the sun is golden, orange, red
	Skyline      = true,       -- hidden below the land in its direction
	SkylineMargin = 0,         -- degrees: above 0 hides it earlier, below 0 later
	Convert      = true,       -- false: the summoned Laser stays a Laser (a test)
	Scale        = 291200,     -- size of the picture (65536 = 1:1; the 256 px sprite, its disc about 155 px)
	Distance     = 7000,       -- from the party (keep below ViewDistanceD3D in mm8.ini)
	Sunrise      = 5.5,        -- hours
	Sunset       = 20.5,
	MaxElevation = 60,         -- degrees above the horizon at noon
	EyeHeight    = 160,
	FogMargin    = 1.2,        -- weather fog hides the sun when it ends closer than Distance x this
	NoSunMaps    = {},         -- ["7out05.odm"] = true ...
	-- skies (the sky bitmap in use: Weather.lua's clear .. storm sets, maps' own skies) that
	-- are overcast, stormy or dark: no sun and no moon under them (07.11.26)
	CloudySkies  = {["6sky02"] = true, sky03 = true, stormclds = true, ["6sky19"] = true,
		cloudsabove = true, sky04 = true, sunsetclouds = true},
}
MF.SunSettings = SUN

-- the sky bitmap in use (lower case), cached by its index
local skyIdx, skyName
local function skyBitmapName()
	local idx = Map.LoadedSkyBitmap
	if idx ~= skyIdx then
		skyIdx, skyName = idx, nil
		pcall(function() skyName = Game.BitmapsLod.Bitmaps[idx].Name:lower() end)
	end
	return skyName
end

-- true under an overcast, stormy or dark sky (also used by MMMWE_Moon.lua)
function MF.SkyCloudy()
	local n = skyBitmapName()
	return n ~= nil and SUN.CloudySkies[n] == true
end

local OldIds = {[12070] = true, [13070] = true}   -- ids of earlier versions (13070 crashes when drawn)

local sunIndex     -- Map.Objects index of the sun
local typeIndex    -- ObjList line of SUN.Id

local function findType(id)
	for i, o in Game.ObjListBin do
		if o.Id == id then return i end
	end
end

local groups = {}    -- SFT indexes of SUN.Groups
local stage          -- the picture shown (index in SUN.Groups)

local function findGroup(name)
	local ok, g = pcall(function() return Game.SFTBin:FindGroup(name) end)
	return ok and g and g >= 0 and g or nil
end

local function group()
	return groups[stage or 1] or groups[1]
end

-- the sun's frames, loaded, at SUN.Scale
local function prepareFrame()
	groups = {}
	for k, name in ipairs(SUN.Groups) do
		local g = findGroup(name)
		if g then
			groups[k] = g
			pcall(function()
				Game.SFTBin:LoadGroup(g)
				Game.SFTBin.Frames[g].Scale = SUN.Scale
			end)
		elseif k == 1 then
			MF.LogWarning("Sun: no SFT group %s", name)
		end
	end
	stage = nil
end

-- the ObjList line points to the group of the picture to show
local function setStage(k)
	if k == stage then return end
	local g = groups[k] or groups[1]
	if not g then return end
	pcall(function()
		local d = Game.ObjListBin[typeIndex]
		if d.Name == "Sun" then d.SFTIndex = g end
	end)
	stage = k
end

local function diag()
	local t = {}
	pcall(function()
		local d = Game.ObjListBin[typeIndex]
		t[#t + 1] = string.format("objlist %d '%s' SFTIndex %d Bits %X", typeIndex, d.Name, d.SFTIndex, d.Bits)
	end)
	local g = group()
	t[#t + 1] = string.format("group %s (picture %s)", tostring(g), tostring(stage))
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

-- the highest angle (radians) of the land seen from the party's eyes toward the azimuth, from
-- the map's height grid (512 per square, heights x 32), up to the map's edge
local skyKey, skyAngle
local function skyline(az)
	local eye = Party.Z + SUN.EyeHeight
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
MF.SunSkyline = skyline

local function shown()
	if not Map.IsOutdoor() or not typeIndex then return false end
	if SUN.NoSunMaps[Map.Name:lower()] then return false end
	if foggy() then return false end
	if MF.SkyCloudy() then return false end
	local az, el = sunAngles()
	if not az then return false end
	if SUN.Skyline and skyline(az) >= el + SUN.SkylineMargin * pi / 180 then return false end
	return true
end

local function sunObject()
	local o = sunIndex and Map.Objects[sunIndex]
	if o and (o.Type == SUN.Id or not SUN.Convert and o.Type == SUN.SummonId) and not o.Removed then return o end
	sunIndex = nil
end

local function makeSun()
	typeIndex = findType(SUN.Id) or typeIndex      -- SUN.Id can be changed for a test
	prepareFrame()
	local before = {}
	for i = 0, Map.Objects.count - 1 do before[i] = Map.Objects[i].Type end
	local ok = pcall(Game.SummonObjects, SUN.SummonId, Party.X, Party.Y, Party.Z + 500, 0, 1)
	if not ok then return end
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == SUN.SummonId and not o.Removed and before[i] ~= SUN.SummonId then
			if SUN.Convert then o.Type, o.TypeIndex = SUN.Id, typeIndex end
			o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
			o.Age, o.MaxAge = 0, 30000
			o.Owner, o.Target = 0, 0
			pcall(function()
				o.Missile = false; o.Temporary = true; o.HaltTurnBased = false
				o.Visible = true; o.IgnoreRange = true
			end)
			sunIndex = i
			MF.LogInfo("Sun: object %d made; %s", i, diag())
			return o
		end
	end
end

-- the object's Visible bit only marks it as seen (for the map), the game draws it anyway:
-- an object is hidden by removing it (and, until the game clears it, moving it deep underground)
local function removeObject(o)
	o.Removed = true
	o.Z = -30000
	o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
end

-- the sun's object, and any left from a saved game or an earlier visit
local function removeStray()
	local cur = sunIndex and Map.Objects[sunIndex]
	if cur and not cur.Removed and (cur.Type == SUN.Id or OldIds[cur.Type]) then removeObject(cur) end
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if (o.Type == SUN.Id or OldIds[o.Type]) and not o.Removed then removeObject(o) end
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
	if not shown() then             -- night, fog, below the skyline: removed, made anew when shown
		if o then removeObject(o); sunIndex = nil end
		return
	end
	o = o or makeSun()
	if not o then return end
	local az, el = sunAngles()
	local d = SUN.Distance
	local k = 1
	for i, deg in ipairs(SUN.Redden) do
		if el < deg * pi / 180 then k = i + 1 end
	end
	setStage(k)
	if SUN.Test == "front" then          -- a test: right in front of the party, at eye height
		az, el, d = (Party.Direction or 0) * pi / 1024, 0, 600
	end
	local h = d * cos(el)
	o.X = floor(Party.X + h * cos(az))
	o.Y = floor(Party.Y + h * sin(az))
	o.Z = floor(Party.Z + SUN.EyeHeight + d * sin(el))
	o.VelocityX, o.VelocityY, o.VelocityZ = 0, 0, 0
	o.Age = 0                            -- it never runs out
	o.Visible = true
end

function MF.SunInfo()
	local az, el, h = sunAngles()
	local o = sunObject()
	local s = string.format("time %.2f h; sun %s; object %s", h,
		az and string.format("azimuth %d, elevation %d degrees", floor(-az * 180 / pi), floor(el * 180 / pi)) or "below the horizon",
		o and string.format("%d at %d, %d, %d, visible %s", sunIndex, o.X, o.Y, o.Z, tostring(o.Visible)) or "none")
	local fr = "?"
	pcall(function() fr = string.format("%s, ends at %d; sky %s%s", tostring(Game.Weather.Fog), Game.Weather.FogRange2,
		tostring(skyBitmapName()), MF.SkyCloudy() and " (cloudy)" or "") end)
	s = s .. string.format("\nshown %s (outdoor %s, too foggy %s; weather fog %s)", tostring(shown()),
		tostring(Map.IsOutdoor()), tostring(foggy()), fr)
	if az then s = s .. string.format("\nskyline toward the sun %.1f degrees", skyline(az) * 180 / pi) end
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
