local LogId = "MonsterKillStat"
local MF = Merge.Functions
MF.LogInit1(LogId)

function events.MonsterKilled(mon, idx, def, killer)
	MF.LogInfo("MonsterKilled: %d %d %d %d %d %s", idx, mon.Id, mon.LastAttacker,
		--string.format("0x%X", killer.c), killer.Type, tostring(killer.Ptr), killer.Player
		killer.Type, killer.Index,
		killer.Player and (killer.Player.Name .. " " .. killer.Player.Class)
			or killer.Monster and (killer.Monster.Id .. " " .. killer.Monster.Ally)
			or killer.Object and (killer.Object.Type .. " " .. killer.Object.TypeIndex)
			or ""
	)
	if killer.Type == 4 then
		local pl = killer.Player
		pl.Attrs.MKS = pl.Attrs.MKS or {}
		pl.Attrs.MKS[mon.Id] = (pl.Attrs.MKS[mon.Id] or 0) + 1
		vars.PartyStats.MKS[mon.Id] = (vars.PartyStats.MKS[mon.Id] or 0) + 1
	elseif killer.Type == 3 and killer.Monster and killer.Monster.Ally == 9999 then
		if killer.Monster.Summoner % 8 == 4 then
			local pid = bit.rshift(killer.Monster.Summoner, 3)
			if pid >= 0 and pid < 50 then
				local pl = Party.PlayersArray[pid]
				pl.Attrs.MKS = pl.Attrs.MKS or {}
				pl.Attrs.MKS[mon.Id] = (pl.Attrs.MKS[mon.Id] or 0) + 1
			end
		end
		vars.PartyStats.MKS[mon.Id] = (vars.PartyStats.MKS[mon.Id] or 0) + 1
	end
end

function events.BeforeLoadMap(WasInGame)
	if not WasInGame then
		vars.PartyStats = vars.PartyStats or {}
		vars.PartyStats.MKS = vars.PartyStats.MKS or {}
	end
end

local function print_mks()
	if not (vars and vars.PartyStats and vars.PartyStats.MKS) then return end
	local str = "|          Monster         |"
	local str1 = "|--------------------------|"
	for i = 0, Party.count - 1 do
		str = str .. string.format(" %8s |", Party[i].Name)
		str1 = str1 .. "----------|"
	end
	str = str .. "  Party   |"
	str1 = str1 .. "----------|"
	print(str)
	print(str1)
	for i = 1, Game.MonstersTxt.high do
		if vars.PartyStats.MKS[i] then
			str = string.format("| %-24s |", Game.MonstersTxt[i].Name)
			for j = 0, Party.count - 1 do
				str = str .. string.format(" %8s |", Party[j].Attrs.MKS and Party[j].Attrs.MKS[i] or "-")
			end
			str = str .. string.format(" %8d |", vars.PartyStats.MKS[i])
			print(str)
		end
	end
end
MF.PrintMKS = print_mks

MF.LogInit2(LogId)
