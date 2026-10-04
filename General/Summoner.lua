-- Druid Summoner
local LogId = "Summoner"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MT = Merge.ModSettings, Merge.Tables
if not MM.Scripts or not MF.GtSettingNum(MM.Scripts.EnableDruidSummoner, 0) then
	MF.LogInit2(LogId)
	return
end

--[=[
	--TODO - Problems with this script: Cannot target ground, summons disappear after a few seconds, lack of documentation and then line specific TODOs
	local u2 = mem.u2
	
	local function isDruid(Caster, SP)--TODO Keys.IsPressed(const.Keys.CTRL) should be in a standalone function, or the isDruid function should be renamed to reflect this part.
		return Keys.IsPressed(const.Keys.CTRL) and Caster.SP >= SP and (Caster.Class == const.Class.Druid or Caster.Class == const.Class.GreatDruid or Caster.Class == const.Class.Warlock or Caster.Class == const.Class.ArchDruid)
	end
	
	local function changeSummonName(str)--TODO: Doesn't work (no A, B or C at the end of names when right clicking a summoned monster)
		for i = 1, #str do
			local c = str:sub(i,i)
			u2[0x4f7dfc + i - 1] = string.byte(c)
			u2[0x4f7e0c + i - 1] = string.byte(c)
			u2[0x4f7e1c + i - 1] = string.byte(c)
		end

		u2[0x4f7dfc + #str] = string.byte('A\0')
		u2[0x4f7e0c + #str] = string.byte('B\0')
		u2[0x4f7e1c + #str] = string.byte('C\0')	
	end
	
	local function DruidSummon(Spell, SP, str)--TODO where is Spell used in this function?
		local Caster = Party.PlayersArray[u2[0x51d822]]
		if isDruid(Caster, SP) then
			Caster.SP = Caster.SP + 25 - SP--TODO explain functionality. Also why are 25 SP always added? 
			changeSummonName(str)
			u2[0x51d820] = 0x52--TODO explain functionality
			u2[0x51d82a] = Caster:GetSkill(const.Skills.Earth)
		end		
	end
	
	function events.GetSpellSkill(t)
		local Spell = u2[0x51d820]
		-- Normal
		if Spell == 34 then -- stun
			DruidSummon(Spell, 1, 'Dire Wolf ')
		elseif Spell == 35 then -- slow
			DruidSummon(Spell, 2, 'Elf Archer ')--TODO a table was made for summons. Current continent can be getted. It really makes no sense for a druid to summon elves (I know they did it in H4, but there it was because the game was really unfinished and they needed to fill in the slots for animals that didn't make the cut)
		elseif Spell == 36 then -- Earth Resistance
			DruidSummon(Spell, 3, 'Elf Spearman ')
		elseif Spell == 37 then -- Deadly Swarm
			DruidSummon(Spell, 4, 'Griffin ')
		-- Expert
		elseif Spell == 38 then -- Stone Skin
			DruidSummon(Spell, 5, 'Wasp Warrior ')
		elseif Spell == 39 then -- Blades
			DruidSummon(Spell, 8, 'Genie ')
		elseif Spell == 40 then -- Stone to Flesh
			DruidSummon(Spell, 10, 'Efreeti ')
		-- Master
		elseif Spell == 41 then -- Rock Blast
			DruidSummon(Spell, 15, 'Wyvern ')
		elseif Spell == 42 then -- Telekinesis
			DruidSummon(Spell, 20, 'Unicorn ')
		elseif Spell == 43 then -- Death Blossom
			DruidSummon(Spell, 25, 'Thunderbird ')
		-- Grand Master
		elseif Spell == 44 then
			DruidSummon(Spell, 30, 'Phoenix ')
		elseif Spell == 0x52 and not Keys.IsPressed(const.Keys.CTRL) then--TODO explain functionality
			changeSummonName('Angel ')
		end
		
	end
]=]

local druid_orig_spell = mem.StaticAlloc(4)
mem.u4[druid_orig_spell] = 0

function events.SpellTargetType(t)
	-- Check for being Druid
	if MT.ClassesExtra[Party.PlayersArray[t.Caster].Class].Kind ~= const.ClassKind.Druid then
		return
	end
	-- Check for Earth spell
	if t.Spell < 34 or t.Spell > 44 then
		return
	end
	-- Check for special cast, special attacks, event and scroll
	if bit.band(t.Flags, 0xE021) > 0 then
		return
	end
	-- Check for Ctrl pressed
	if bit.band(t.Flags, 0x1000) == 0 then
		return
	end
	--MF.LogInfo("Summoner SpellTargetType: Spell %d (Player %d) - 0x%X", t.Spell, t.Caster, t.Flags)
	t.Flags = bit.band(t.Flags, 0x1000)
end

function events.PlayerSpellProc(t)
	-- Check for being Druid
	if MT.ClassesExtra[Party.PlayersArray[t.Caster].Class].Kind ~= const.ClassKind.Druid then
		return
	end
	-- Check for Earth spell
	if t.Spell < 34 or t.Spell > 44 then
		return
	end
	-- Check for special cast, special attacks, event and scroll
	if bit.band(t.Flags, 0xE021) > 0 then
		return
	end
	-- Check for Ctrl pressed
	if bit.band(t.Flags, 0x1000) == 0 then
		return
	end
	--MF.LogInfo("Summoner PlayerSpellProc: Spell %d (Player %d) - 0x%X", t.Spell, t.Caster, t.Flags)
	mem.u4[druid_orig_spell] = t.Spell
	t.Spell = 82
end

-- [spell] = {{monster id, count}}
local summons = {
	[34] = {{226, 1}, {226, 2}, {227, 3}, {228, 5}}, -- Dragonfly
	[35] = {{400, 1}, {400, 2}, {401, 3}, {402, 5}}, -- Spider
	[36] = {{493, 1}, {493, 2}, {494, 3}, {495, 5}}, -- Cobra
	[37] = {{85, 1}, {85, 2}, {86, 3}, {87, 5}}, -- Dire Wolf
	[38] = {{280, 1}, {280, 2}, {281, 3}, {282, 5}}, -- Griffin
	[39] = {{118, 1}, {118, 2}, {119, 3}, {120, 5}}, -- Wasp
	[40] = {{121, 1}, {121, 2}, {122, 3}, {123, 5}}, -- Wyvern
	[41] = {{109, 1}, {109, 2}, {110, 3}, {111, 5}}, -- Unicorn
	[42] = {{391, 1}, {391, 2}, {392, 3}, {393, 5}}, -- Thunderbird
	[43] = {{130, 1}, {130, 2}, {131, 3}, {132, 5}}, -- Phoenix
	[44] = {{208, 1}, {208, 2}, {209, 3}, {210, 5}}, -- Behemoth
}

function events.PlayerSpellVar(t)
	local spell = mem.u4[druid_orig_spell]
	if t.Spell == 82 and spell > 0 then
		--MF.LogInfo("Summoner PlayerSpellVar: Spell %d, RosterIndex %d, Orig Spell %d, Flags 0x%X, VarNum %d, Value %d (%.3f)",
		--	t.Spell, t.PlayerIndex, spell, t.Flags or 0, t.VarNum, t.Value, t.Value)
		local mastery = MF.GetPlayerSkillMastery(t.Player, const.Skills.Earth)
		if t.VarNum == 3 then
			t.Value = summons[spell] and summons[spell][mastery]
				and summons[spell][mastery][1] or 0
		elseif t.VarNum == 4 then
			t.Value = summons[spell] and summons[spell][mastery]
				and summons[spell][mastery][2] or t.Value
			mem.u4[druid_orig_spell] = 0
		end
	end
end

MF.LogInit2(LogId)

