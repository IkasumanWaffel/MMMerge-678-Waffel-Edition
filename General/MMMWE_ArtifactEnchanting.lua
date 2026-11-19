--[[
	MMMWE_ArtifactEnchanting.lua — temporary enchantments on artifacts and relics (19.11.26)

	The game refuses Fire Aura on artifacts, relics and special items (0x4272DB:
	ItemsTable::IsMaterialNonCommon, 0x45462F), and the Slaying potion on every item number
	from 500 up (0x41612B: the old start of the artifacts; in the Merge most items are past it).
	Now:
	  * Fire Aura takes artifacts and relics; special items (material 3) are still refused
	  * the Slaying potion takes any weapon, as the elemental potions already do
	    (RemoveItemsLimits.lua took their limit away)
	  * Vampiric Weapon is left as it was: no artifacts, relics or special items
	Each still needs a weapon with no enchantment of its own in the way; MMMWE_ConcurrentEnchantments.lua
	keeps an artifact's own powers working beside the temporary one.

	Switch: ModSettings "Scripts.ArtifactTempEnchant" (on unless set to 0).
--]]

local MF = Merge.Functions
local MM = Merge.ModSettings
if MM.Scripts and MM.Scripts.ArtifactTempEnchant ~= nil and not MF.GtSettingNum(MM.Scripts.ArtifactTempEnchant, 0) then
	return
end

local ITEM_MATERIAL_SPECIAL = 3

-- Fire Aura: the material check, keeping only "special" (3) as non-common.
-- this - the items table (ecx), arg - the item; the item record is 0x30 bytes, its material
-- at +0x25 from the table pointer the game passes (as in 0x45462F)
local FireAuraMat = mem.asmproc([[
	mov eax, [esp + 4]
	mov eax, [eax]
	lea eax, [eax + eax*2]
	shl eax, 4
	mov al, [eax + ecx + 0x25]
	cmp al, ]] .. ITEM_MATERIAL_SPECIAL .. [[

	jne @common
	xor eax, eax
	inc eax
	retn 4
	@common:
	xor eax, eax
	retn 4
]])
-- 0x4272DB: call 0x45462F (5 bytes) -> call the check above
if mem.u1[0x4272DB] == 0xE8 then
	mem.asmpatch(0x4272DB, "call absolute " .. FireAuraMat, 5)
else
	MF.LogWarning("[ArtifactEnchanting] Fire Aura check at 0x4272DB not found")
end

-- Slaying potion: "cmp [esi], 500 / jge refuse" (0x41612B 6 + 0x416131 6 bytes)
if mem.u4[0x41612B + 2] == 0x1F4 then
	mem.nop(0x41612B, 12)
else
	MF.LogWarning("[ArtifactEnchanting] Slaying potion check at 0x41612B not found")
end
