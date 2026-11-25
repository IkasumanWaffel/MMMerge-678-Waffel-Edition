--[[
	MMMWE_HitVoices.lua - the characters speak up when they get hurt (25.11.26)

	Why the "being hit" lines (Character voices.txt, SoftInjure1/2 - the face animation's speech
	type 15) were next to never heard:
	  MM8 plays them for a single hit (face animation 24, Damaged) only one time in ten
	    (ShowFaceAnimation 0x492C35: random % 100 > 10 drops the sound);
	  a hit on the whole party (face animation 44, DamagedParty: explosions, area spells) has no
	    speech type in the game's table at all (StandardFaceAnimations[44].Sound1 = 0).
	Here both play the injury lines at V.Chance %, and not more often than once in
	V.Cooldown seconds for the same character, so a long fight doesn't turn into chatter.
	The badly hurt (face animation 48, HardInjured) and dying lines are left as they are.
--]]

local MF = Merge.Functions

local V = {
	Chance = 35,          -- % of hits with a line
	Cooldown = 6,         -- seconds between two lines of one character
	Speech = 15,          -- SoftInjure1/2
}
MF.HitVoiceSettings = V

local Last = {}

function events.FaceAnimation(t)
	local a = t.Animation
	if a ~= const.FaceAnimation.Damaged and a ~= const.FaceAnimation.DamagedParty then return end
	local i = t.PlayerIndex or -1
	local now = os.clock()
	if math.random(100) <= V.Chance and now - (Last[i] or -1e9) >= V.Cooldown then
		Last[i] = now
		t.Sound = V.Speech
		t.ForceSound = true
	else
		t.Sound = 0
	end
end
