--[[
	MMMWE_ArmorEffects.lua — what makes Leather, Chain and Plate different besides Armor Class

	Pieces count with the slot weights of MMMWE_DamageKinds.lua (body armor 50%, helm and
	boots 15%, gauntlets and belt 10%), so a full set of one type counts 1, mixed sets a part.

	Leather — agile
	  Dodge: at Expert and up, +0.1% dodge chance per point of Leather skill for every
	         leather piece worn (+10% for a full set at skill 20). Needs the Dodging skill,
	         like all dodging (MF.DodgeChanceMods).
	  Speed: leather body armor at Master and up: attacks 5% faster (-5% attack delay).
	Chain — resilient
	  Shrug off: chance to ignore a monster's special effect (poison, disease, curse, sleep,
	         paralysis, stoning, item breaking, aging, stat / armor / resistance drains, ...)
	         = 0.5% x Chain skill x mastery x chain share of the set (40% at GM 20, full set).
	  Chain body armor at Grand Master keeps a -5% dodge penalty.
	Plate — bulwark
	  Every physical hit taken is reduced by a flat amount after all other reductions: half
	  the Plate skill at Master, the full skill at Grand Master, times the plate share of the
	  set (a hit never goes below 1).
	  Plate body armor at Grand Master keeps +5% attack delay and a -10% dodge penalty.
	Blasters are left out of the recovery changes (their recovery is fixed by design).

	Console: Merge.Functions.ArmorEffectsInfo(player)
--]]

local MF = Merge.Functions
local SK = const.Skills

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local A = {
	LeatherDodgePerSkill = 0.1,   -- % per skill point per leather piece, Expert and up
	LeatherRecovery      = -5,    -- % attack delay, leather body armor, Master and up
	ChainShrugPerSM      = 0.5,   -- % per skill x mastery, full chain set
	ChainGMDodge         = -5,    -- chain body armor at Grand Master
	PlateFlatMaster      = 0.5,   -- x Plate skill, full plate set
	PlateFlatGM          = 1.0,
	PlateGMRecovery      = 5,     -- % attack delay, plate body armor at Grand Master
	PlateGMDodge         = -10,
}
MF.ArmorEffectSettings = A

local DEFAULT_WEIGHTS = {
	{"ItemArmor", 0.50}, {"ItemHelm", 0.15}, {"ItemBoots", 0.15},
	{"ItemGauntlets", 0.10}, {"ItemBelt", 0.10},
}

---------------------------------------------------------------------------

-- share (0..1) of the set made of armor skill `skill`, and the number of such pieces
local function share(pl, skill)
	local w, n = 0, 0
	for _, sw in ipairs(MF.ArmorSlotWeights or DEFAULT_WEIGHTS) do
		local slot = pl[sw[1]]
		if slot and slot > 0 then
			local it = pl.Items[slot]
			if it.Number > 0 and not it.Broken and Game.ItemsTxt[it.Number].Skill == skill then
				w, n = w + sw[2], n + 1
			end
		end
	end
	return w, n
end

local function bodySkill(pl)
	local slot = pl.ItemArmor
	if slot <= 0 or pl.Items[slot].Broken then return nil end
	return Game.ItemsTxt[pl.Items[slot].Number].Skill
end

-- dodge chance change from armor (% points)
function MF.ArmorDodgeMod(pl)
	local m = 0
	local S, M = SplitSkill(pl:GetSkill(SK.Leather))
	if M >= 2 then
		local _, n = share(pl, SK.Leather)
		m = m + A.LeatherDodgePerSkill * S * n
	end
	local body = bodySkill(pl)
	if body == SK.Chain and select(2, SplitSkill(pl:GetSkill(SK.Chain))) >= 4 then
		m = m + A.ChainGMDodge
	elseif body == SK.Plate and select(2, SplitSkill(pl:GetSkill(SK.Plate))) >= 4 then
		m = m + A.PlateGMDodge
	end
	return m
end

-- chance (%) to shrug off a monster's special effect
function MF.ChainShrugChance(pl)
	local S, M = SplitSkill(pl:GetSkill(SK.Chain))
	if S <= 0 or M <= 0 then return 0 end
	local w = share(pl, SK.Chain)
	return A.ChainShrugPerSM * S * M * w
end

function MF.ChainShrugsOff(pl)
	local c = MF.ChainShrugChance(pl)
	if c > 0 and math.random() * 100 < c then
		Game.ShowStatusText(string.format("%s's chain mail turns the blow aside", pl.Name))
		return true
	end
	return false
end

-- flat physical damage reduction per hit
function MF.PlateFlatReduction(pl)
	local S, M = SplitSkill(pl:GetSkill(SK.Plate))
	local k = M >= 4 and A.PlateFlatGM or M == 3 and A.PlateFlatMaster or 0
	if k <= 0 then return 0 end
	return k * S * share(pl, SK.Plate)
end

-- attack recovery change from armor
function MF.ArmorRecoveryMod(pl)
	local body = bodySkill(pl)
	if body == SK.Leather and select(2, SplitSkill(pl:GetSkill(SK.Leather))) >= 3 then
		return A.LeatherRecovery
	elseif body == SK.Plate and select(2, SplitSkill(pl:GetSkill(SK.Plate))) >= 4 then
		return A.PlateGMRecovery
	end
	return 0
end

function MF.ArmorEffectsInfo(pl)
	pl = pl or Party[math.max(Game.CurrentPlayer, 0)]
	return string.format("dodge %+.1f%%, recovery %+d, shrug off %.1f%%, plate reduction %.1f",
		MF.ArmorDodgeMod(pl), MF.ArmorRecoveryMod(pl), MF.ChainShrugChance(pl), MF.PlateFlatReduction(pl))
end

---------------------------------------------------------------------------
-- hooks
---------------------------------------------------------------------------

-- Chain: monsters' special effects (the game's "bad things")
function events.DoBadThingToPlayer(t)
	if t.Allow and t.Player and MF.ChainShrugsOff(t.Player) then
		t.Allow = false
	end
end

-- Plate: flat reduction of physical hits. MMMWE_Main.lua sets the damage in a handler it
-- registers in GameInitialized2 (this file's GameInitialized2 runs before Main's), so this
-- one is registered on the first map load, to run after it.
local plateHooked = false
function events.LoadMap()
	if plateHooked then return end
	plateHooked = true
	function events.CalcDamageToPlayer(t)
		if not t.Player or t.DamageKind ~= const.Damage.Phys or (t.Result or 0) <= 1 then return end
		local r = MF.PlateFlatReduction(t.Player)
		if r > 0 then
			t.Result = math.max(1, t.Result - math.floor(r + 0.5))
		end
	end
end

-- Leather / Plate attack recovery: MF.ArmorRecoveryMod is added to the armor recovery
-- percentage in MMMWE_Main.lua (GetAttackDelay), so it is -5% / +5% of the attack delay
