-- Race and class resistances
local LogId = "Resistances"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MT = Merge.ModSettings, Merge.Tables

local asmpatch, nop = mem.asmpatch, mem.nop
local strformat, strlen = string.format, string.len

local function ProcessResistancesTxt()
	local resistances = {}
	local TableFile = "Data/Tables/Resistances.txt"
	local header = "#\9Race\9RaceName\9Class\9ClassName\9Resistance\9Value"

	-- Fill resistances with 0 by default
	for race = 0, Game.RacesCount - 1 do
		resistances[race] = {}
		resistances[race][-1] = {}
		for res = 0, 10 do
			resistances[race][-1][res] = 0
		end
	end

	local result = 0
	local TxtTable = io.open(TableFile, "r")

	if not TxtTable then
		MF.LogWarning("No Resistances.txt found, creating one.")
		TxtTable = io.open(TableFile, "w")
		TxtTable:write(header .. "\n")

		local line_num = 0

		for race = 0, Game.RacesCount - 1 do
			if Game.Races[race].Kind == const.RaceKind.Human then
				resistances[race][-1][6] = 5
				-- MM7
				resistances[race][-1][8] = 5
			elseif Game.Races[race].Kind == const.RaceKind.Elf then
				if Game.Races[race].BaseRace == const.Race.DarkElf then
					resistances[race][-1][0] = 5
					resistances[race][-1][1] = 5
					resistances[race][-1][2] = 5
					resistances[race][-1][3] = 5
				elseif Game.Races[race].BaseRace == const.Race.Elf then
					-- MM7
					resistances[race][-1][7] = 10
				end
			elseif Game.Races[race].Kind == const.RaceKind.Minotaur then
				resistances[race][-1][6] = 5
				resistances[race][-1][7] = 5
				resistances[race][-1][8] = 5
			elseif Game.Races[race].Kind == const.RaceKind.Troll then
				resistances[race][-1][3] = 5
				resistances[race][-1][8] = 5
			elseif Game.Races[race].Kind == const.RaceKind.Dragon then
				resistances[race][-1][0] = 5
				resistances[race][-1][1] = 5
				resistances[race][-1][2] = 5
				resistances[race][-1][3] = 5
				resistances[race][-1][6] = 5
				resistances[race][-1][7] = 5
				resistances[race][-1][8] = 5
			elseif Game.Races[race].Kind == const.RaceKind.Goblin then
				-- MM7
				resistances[race][-1][0] = 5
				resistances[race][-1][1] = 5
			elseif Game.Races[race].Kind == const.RaceKind.Dwarf then
				-- MM7
				resistances[race][-1][2] = 5
				resistances[race][-1][3] = 5
			elseif Game.Races[race].Family == const.RaceFamily.Undead then
				resistances[race][-1][7] = 65000
				resistances[race][-1][8] = 65000
			elseif Game.Races[race].Family == const.RaceFamily.Vampire then
				resistances[race][-1][7] = 65000
			elseif Game.Races[race].Family == const.RaceFamily.Ghost then
				resistances[race][-1][7] = 65000
				resistances[race][-1][8] = 65000
			end
			for _, res in pairs({0, 1, 2, 3, 6, 7, 8}) do
				if resistances[race][-1][res] > 0 then
					line_num = line_num + 1
					TxtTable:write(strformat("%d\9%d\9%s\9%d\9-\9%d\9%d\n",
						line_num, race, Game.Races[race].Name, -1, res,
						resistances[race][-1][res]))
				end
			end
		end
		result = line_num
		MF.LogInfo("Resistances.txt created, %d lines written.", line_num)
	else
		local LineIt = TxtTable:lines()
		if LineIt() ~= header then
			MF.LogError("Resistances.txt header differs from expected one, table is ignored. Regenerate or fix it.")
			result = -1
		else
			local line_num = 1
			for line in LineIt do
				line_num = line_num + 1
				local words = string.split(line, "\9")
				if strlen(words[1]) == 0 then
					MF.LogWarning(
						"Resistances.txt line %d first field is empty. Skipping following lines.",
						line_num)
					break
				end
				-- Ignore lines that don't start with number
				if words[1] and tonumber(words[1]) then
					-- Also ignore lines that have either less or more than 7 columns
					if #words == 7 then
						local race = tonumber(words[2])
						local class = tonumber(words[4])
						local res = tonumber(words[6])
						local value = tonumber(words[7])
						if not resistances[race] then
							MF.LogError("Invalid race %d at line %d",
								race, line_num)
						else
							resistances[race][class] = resistances[race][class] or {}
							resistances[race][class][res] = value
							result = result + 1
						end
					else
						MF.LogWarning(
							"Resistances.txt line %d has %d columns. Ignoring line.",
							line_num, #words)
					end
				else
					MF.LogWarning(
						"Resistances.txt line %d first field is not a number. Ignoring line.",
						line_num)
				end
			end
		end
	end
	io.close(TxtTable)
	Game.Resistances = resistances
	MT.Resistances = resistances
	return result
end

local function GetPlayer(ptr)
	local PlayerId = (ptr - Party.PlayersArray["?ptr"])/Party.PlayersArray[0]["?size"]
	return Party.PlayersArray[PlayerId], PlayerId
end

local function SetResistancesHook()

	local StatsRes = {
		[10] = 0, [11] = 1, [12] = 2, [13] = 3, [14] = 7, [15] = 8, [33] = 6,
		[50] = 9, [51] = 10, [52] = 4, [53] = 5
	}

	-- GetBaseResistance
	local NewCode = mem.asmpatch(0x48DBAB, [[
	mov esi, ecx
	nop
	nop
	nop
	nop
	nop
	cmp ebx, 0xFFFF
	jge absolute 0x48DD65
	cmp eax, 0xfde8
	jge absolute 0x48dd65
	jmp absolute 0x48dd4a]])

	mem.hook(NewCode + 2, function(d)
		d.ebx = StatsRes[d.eax] or 0xFFFF
		if d.ebx == 0xFFFF then
			d.eax = 0
		else
			local player = GetPlayer(d.ecx)
			local race = GetCharRace(player)
			local t = {Resistance = d.ebx, Player = player}
			t.Result = MT.Resistances[race]
				and (MT.Resistances[race][player.Class]
				and MT.Resistances[race][player.Class][d.ebx]
				or (MT.Resistances[race][-1]
					and MT.Resistances[race][-1][d.ebx])) or 0
			events.call("GetRaceClassResistance", t)

			d.edi = t.Result
			d.eax = t.Result
		end
	end)

	-- GetResistance
	NewCode = mem.asmpatch(0x48DDC6, [[
	nop
	nop
	nop
	nop
	nop
	cmp edi, 0xFFFF
	jge absolute 0x48DF7A
	cmp eax, 0xFDE8
	jge absolute 0x48DF7A
	jmp absolute 0x48DF50]])

	mem.hook(NewCode, function(d)
		d.edi = StatsRes[d.eax] or 0xFFFF
		if d.edi == 0xFFFF then
			d.eax = 0
		else
			local player = GetPlayer(d.esi)
			local race = GetCharRace(player)
			local t = {Resistance = d.edi, Player = player}
			t.Result = MT.Resistances[race]
				and (MT.Resistances[race][player.Class]
				and MT.Resistances[race][player.Class][d.edi]
				or (MT.Resistances[race][-1]
					and MT.Resistances[race][-1][d.edi])) or 0
			events.call("GetRaceClassResistance", t)

			d.ebp = d.ebp + t.Result
			d.eax = t.Result
		end
	end)

	NewCode = mem.asmpatch(0x48df7a, [[
	nop
	nop
	nop
	nop
	nop
	pop edi
	pop esi
	pop ebp
	pop ebx
	retn 0x4]])

	mem.hook(NewCode, function(d)
		if d.edi ~= 0xFFFF then
			local t = {Resistance = d.edi, Player = GetPlayer(d.esi), Result = d.eax}
			events.call("GetResistance", t)
			d.eax = t.Result
		end
	end)

	-- CalcDamageToPlayer
	--    Physical and "Magic" resistances
	mem.asmpatch(0x48CDC0, [[
	dec eax
	jnz @magic
	push 0x34
	jmp absolute 0x48CDE5
	@magic:
	dec eax
	jnz @spirit
	push 0x35
	jmp absolute 0x48CDE5
	@spirit:
	dec eax
	jz absolute 0x48CDD3
	]])
	--   Light and Dark resistances
	mem.asmpatch(0x48CDC9, [[
	jnz @light
	push 0xF
	jmp absolute 0x48CDE5
	@light:
	dec eax
	jnz @dark
	push 0x32
	jmp absolute 0x48CDE5
	@dark:
	dec eax
	jnz @ener
	push 0x33
	jmp absolute 0x48CDE5
	@ener:
	sub eax, 2
	jnz @extra
	push 0x35
	jmp absolute 0x48CDE5
	@extra:
	xor eax, eax
	jmp absolute 0x48CDEE
	]])
	--   Combined damage type: to player
	asmpatch(0x48CDAC, [[
	push ebx
	push esi
	push edi
	xor edi, edi
	and eax, 0xF
	]])
	nop(0x48CDEC, 2)
	asmpatch(0x48CDEE, [[
	test edi, edi
	jnz @compare
	mov ebx, eax
	mov eax, dword ptr [ebp + 8]
	sar eax, 4
	test eax, eax
	jnz @second
	mov edi, ebx
	jmp @end
	@second:
	inc edi
	jmp absolute 0x48CDB7
	@compare:
	mov edi, eax
	cmp eax, ebx
	jle @end
	mov edi, ebx
	@end:
	mov ebx, dword ptr [ebp + 0xC]
	]], 0x48CE00 - 0x48CDEE)

	-- Resistances. If < 65000 - print number, else - "Immune"
	mem.asmpatch(0x418550, "jl 0x418576 - 0x418550")
	mem.asmpatch(0x41861a, "jl 0x418640 - 0x41861a")
	mem.asmpatch(0x4186e4, "jl 0x41870a - 0x4186e4")
	mem.asmpatch(0x4187ae, "jl 0x4187d4 - 0x4187ae")
	mem.asmpatch(0x418878, "jl 0x41889e - 0x418878")
	mem.asmpatch(0x418939, "jl 0x41895f - 0x418939")

end

-- Max evt resistance value
-- TODO: change resistances to signed
-- Base resistances
asmpatch(0x448A00, [[
movzx ecx, word ptr [eax]; TODO: movsx
cmp ecx, ]] .. (MM.ResistancesEvtBaseMax or 255) .. [[;
jae @end; TODO: jge
mov cx, word ptr [ebp + 0xC]
add word ptr [eax], cx
mov cx, word ptr [eax]
cmp cx, ]] .. (MM.ResistancesEvtBaseMax or 255) .. [[;
jbe @end; TODO: jle
mov word ptr [eax], ]] .. (MM.ResistancesEvtBaseMax or 255) .. [[;
@end:
]], 0x448A16 - 0x448A00)

-- Bonus resistances
asmpatch(0x448A6A, [[
movzx ecx, word ptr [eax]; TODO: movsx
cmp ecx, ]] .. (MM.ResistancesEvtBonusMax or 255) .. [[;
jae @end; TODO: jge
mov cx, word ptr [ebp + 0xC]
add word ptr [eax], cx
mov cx, word ptr [eax]
cmp cx, ]] .. (MM.ResistancesEvtBonusMax or 255) .. [[;
jbe @end; TODO: jle
mov word ptr [eax], ]] .. (MM.ResistancesEvtBonusMax or 255) .. [[;
@end:
]], 0x448A80 - 0x448A6A)

-- Max evt stat value
--   (use resistances code in vanilla)
-- Base stat
asmpatch(0x448968, [[
movzx ecx, word ptr [eax];
cmp ecx, ]] .. (MM.StatEvtBaseMax or 255) .. [[;
jae @end;
mov cx, word ptr [ebp + 0xC]
add word ptr [eax], cx
mov cx, word ptr [eax]
cmp cx, ]] .. (MM.StatEvtBaseMax or 255) .. [[;
jbe @end;
mov word ptr [eax], ]] .. (MM.StatEvtBaseMax or 255) .. [[;
@end:
jmp absolute 0x448A16
]], 0x448982 - 0x448968)

-- Bonus stat
asmpatch(0x448918, [[
movzx ecx, word ptr [eax];
cmp ecx, ]] .. (MM.StatEvtBonusMax or 255) .. [[;
jae @end;
mov cx, word ptr [ebp + 0xC]
add word ptr [eax], cx
mov cx, word ptr [eax]
cmp cx, ]] .. (MM.StatEvtBonusMax or 255) .. [[;
jbe @end;
mov word ptr [eax], ]] .. (MM.StatEvtBonusMax or 255) .. [[;
@end:
jmp absolute 0x448A80
]], 0x448932 - 0x448918)

function events.GameInitialized1()
	MF.LogVerbose("%s: GameInitialized1", LogId)
	SetResistancesHook()
end

function events.GameInitialized2()
	MF.LogVerbose("%s: GameInitialized2", LogId)
	local result = ProcessResistancesTxt()
	if result > 0 then
		MF.LogInfo("Loaded Resistances.txt: %d effective lines", result)
	end
end

MF.LogInit2(LogId)
