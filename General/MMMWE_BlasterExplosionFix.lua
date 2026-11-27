--[[
	MMMWE_BlasterExplosionFix.lua - objects the engine does not draw indoors

	The engine draws some objects of ObjList.txt only as a light flash (the blaster impact, 556)
	or not at all (the boulder that cyclopes, trolls and boulders throw, 565) on indoor maps,
	whatever sprite or flags they are given, so those ids themselves are treated specially there.
	Every new such object is turned into a copy of it with an unused id (ObjList.txt), which the
	engine draws like any other object:
	  556 blaster explosion -> 12050 (damage was dealt at impact; no longer a flying missile)
	  565 Cyclops Projectile -> 12052 "Cyclops Projectile (indoors)" (27.11.26), the same flags,
	      speed and sprite; 565 has no case of its own in the engine's impact and damage code
	      (both fall to their default), so the copy hits and hurts the same way.
--]]

local SWAP = {
	[556] = {To = 12050, NotMissile = true},
	[565] = {To = 12052},
}

local MF = Merge.Functions

local function findIndex(id)
	for i, o in Game.ObjListBin do
		if o.Id == id then return i end
	end
end

local active = false

function events.GameInitialized2()
	for from, s in pairs(SWAP) do
		s.Index = findIndex(s.To)
		if s.Index then
			active = true
		else
			MF.LogWarning("BlasterExplosionFix: ObjList.txt has no object %d, %d stays as it is", s.To, from)
		end
	end
end

function events.Tick()
	if not active or Map.IsOutdoor() then return end
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		local s = SWAP[o.Type]
		if s and s.Index then
			o.Type = s.To
			o.TypeIndex = s.Index
			if s.NotMissile then
				o.Missile = false   -- an explosion, not a flying weapon missile
			end
		end
	end
end
