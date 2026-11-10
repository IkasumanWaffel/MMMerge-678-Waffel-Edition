--[[
	MMMWE_PersonalWard.lua — Protection from Magic for one character (11.11.26)

	The Protection from Magic potion wards only the character who drinks it. The game knows
	the spell as a party buff alone and checks it inside Player:AddCondition (0x49165D), so
	the personal ward is lent to the game for the length of that call: when a warded
	character is about to get a condition and the party has no Protection from Magic of
	its own, the ward's time, charges and rank are put into the party buff, the game does
	what it does with the spell (blocks the condition, takes a charge off), and what is left
	goes back into the ward. A real party Protection from Magic comes first and leaves the
	ward untouched.

	The ward is the extra character buff SpellBuffs2[WARD_BUFF] (kept with the saved game,
	shown with the other buffs): ExpireTime, Power = charges left, Skill = the spell's rank
	(4: also protects from death and eradication, as the potion always did).

	MF.SetPersonalWard(player, minutes, charges, rank)
--]]

local MF = Merge.Functions
local WARD_BUFF = 30

local function wardOf(index)
	local ok, b = pcall(function() return Game.PlayersExtra[index].SpellBuffs2[WARD_BUFF] end)
	return ok and b or nil
end

function MF.SetPersonalWard(pl, minutes, charges, rank)
	local b = wardOf(pl:GetIndex())
	if not b then return false end
	b.ExpireTime = Game.Time + const.Minute * minutes
	b.Power = charges
	b.Skill = rank or 3
	return true
end

mem.hookfunction(0x49165D, 1, 2, function(d, def, this, cond, canResist)
	local ward, party
	local ok = pcall(function()
		party = Party.SpellBuffs[const.PartyBuff.ProtectionFromMagic]
		if party.ExpireTime > Game.Time then
			party = nil      -- the party's own spell does the work
			return
		end
		local arr = Party.PlayersArray
		local index = (this - arr[0]["?ptr"]) / arr[0]["?size"]
		if index ~= math.floor(index) or index < 0 or index >= arr.count then return end
		local b = wardOf(index)
		if b and b.ExpireTime > Game.Time and b.Power > 0 then ward = b end
	end)
	if not ok or not ward or not party then
		return def(this, cond, canResist)
	end
	-- lend the ward to the game
	party.ExpireTime, party.Power, party.Skill = ward.ExpireTime, ward.Power, ward.Skill
	local res = def(this, cond, canResist)
	-- what is left of it
	if party.ExpireTime > Game.Time and party.Power > 0 then
		ward.Power = party.Power
	else
		ward.ExpireTime, ward.Power, ward.Skill = 0, 0, 0
	end
	party.ExpireTime, party.Power, party.Skill = 0, 0, 0
	return res
end)
