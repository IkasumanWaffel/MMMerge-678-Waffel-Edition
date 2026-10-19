--[[
	MMMWE_WeaponEffects.lua — extra on-hit effects of melee attacks

	Unarmed stun
	  Bare-handed attacks (nothing in the main hand, no weapon in the other hand) can stun
	  the target like a Master mace or staff: chance = Unarmed skill x STUN_PER_SKILL[mastery]
	  percent (Novice 0.25, Expert 0.5, Master 0.75, Grand Master 1 per point: 20% at GM 20).
	  The stun is applied by the game's own code in damage_monster_from_party (0x436E26):
	  this script only raises its chance_to_stun flag ([ebp-24h]) at 0x437230, the point all
	  melee attacks pass before melee_damage is called. So the usual rules apply: the target
	  resists with its Earth resistance, is delayed and pushed back, the status line says so,
	  and SpellsTweaks.lua turns the stun into a short paralysis.
--]]

local MF = Merge.Functions

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local UNARMED_STUN   = true
local NO_DAGGER_TRIPLE = true
local STUN_PER_SKILL = {0.25, 0.5, 0.75, 1}   -- % per point of Unarmed skill, by mastery

---------------------------------------------------------------------------

local function playerFromPtr(ptr)
	local arr = Party.PlayersArray
	local i = (ptr - arr["?ptr"]) / arr[0]["?size"]
	if i >= 0 and i < arr.count and i == math.floor(i) then return arr[i] end
end

local function isBareHanded(pl)
	local main = pl.ItemMainHand
	if main ~= 0 and not pl.Items[main].Broken then return false end
	local extra = pl.ItemExtraHand
	if extra ~= 0 and not pl.Items[extra].Broken then
		local stat = Game.ItemsTxt[pl.Items[extra].Number].EquipStat
		if stat ~= const.ItemType.Shield - 1 then return false end   -- a shield is fine
	end
	return true
end

function MF.UnarmedStunChance(pl)
	local S, M = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
	if S <= 0 or M <= 0 then return 0 end
	return S * (STUN_PER_SKILL[M] or 0)
end

if UNARMED_STUN then
	-- melee path of damage_monster_from_party, right before melee_damage
	mem.autohook(0x437230, function(d)
		if mem.i4[d.ebp - 0x24] ~= 0 then return end          -- already stunning
		local pl = playerFromPtr(mem.u4[d.ebp - 8])
		if not pl or not isBareHanded(pl) then return end
		local chance = MF.UnarmedStunChance(pl)
		if chance > 0 and math.random() * 100 < chance then
			mem.i4[d.ebp - 0x24] = 1
		end
	end)
end

if NO_DAGGER_TRIPLE then
	mem.IgnoreProtection(true)
	for _, a in ipairs{0x48C89A, 0x48C9A6} do        -- jge short (7D) over the triple
		if mem.u1[a] == 0x7D then
			mem.u1[a] = 0xEB                             -- jmp short, same target
		elseif MF.LogError then
			MF.LogError("MMMWE_WeaponEffects: unexpected byte 0x%X at 0x%X, dagger triple left", mem.u1[a], a)
		end
	end
	mem.IgnoreProtection(false)
end
