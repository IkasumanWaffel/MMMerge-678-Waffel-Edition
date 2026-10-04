if Game.Version ~= 8 then
	return
end

local i4, i2, i1, u4, u2, u1, pchar = mem.i4, mem.i2, mem.i1, mem.u4, mem.u2, mem.u1, mem.pchar
local BLASTER = const.Skills.Blaster

function round(num)
	return num >= 0 and math.floor(num + 0.5) or math.ceil(num - 0.5)
end
-- shoot
mem.autohook(0x42D8C8, function(d)
	if Game.ItemsTxt[d.ecx].Skill == BLASTER then
		i4[d.ebp - 0x10] = 2
	end
end)

mem.asmhook(0x42DAA9, [[
	cmp dword [ebp - 0x10], 1
	jz @f
	mov ecx, 135
	jmp absolute 0x42DAB5
@@:
]])

function round(num)
	return num >= 0 and math.floor(num + 0.5) or math.ceil(num - 0.5)
end

-- character screen
local function HasBlaster(p)
	local i = (p - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]
	local pl = Party.PlayersArray[i]
	local slot = pl.ItemMainHand
	local it = (slot ~= 0 and pl.Items[slot])
	return it and it.Condition:And(2) == 0 and Game.ItemsTxt[it.Number].Skill == BLASTER and pl
end

local function DamageHook(ret)
	return function(d)
		local pl = HasBlaster(d.ecx)
		if pl then
			local slot = pl.ItemMainHand
			local item = (slot ~= 0 and pl.Items[slot])
			local BLASTER = const.Skills.Blaster
			local BS,BM = SplitSkill(pl:GetSkill(BLASTER))
			local Charge = item.Charges
			local ModTier = math.floor(Charge/1000)
			local itnum = item.Number
			local BlasterType = itnum - select(math.floor(itnum/800),865,1665)
			local DMin = select(BlasterType, 10, 15)
			local DMax = select(BlasterType, 20, 30)
			if ModTier > 0 then
				DMin = round(DMin + ModTier*0.05*DMin*BS)
				DMax = round(DMax + ModTier*0.05*DMax*BS)
			end
			d.edi = DMin
			d.eax = DMax
			d:push(ret)
			return true
		end
	end
end

mem.autohook(0x48CC0D, DamageHook(0x48CC32))
mem.autohook(0x48CCAA, DamageHook(0x48CCCF))

mem.autohook(0x48CA02, function(d)
	local pl = HasBlaster(d.ecx)
	if HasBlaster(d.ecx) then
		d.eax = pl:GetMeleeAttack(true)
		d:push(0x48CA34)
		return true
	end
end)

