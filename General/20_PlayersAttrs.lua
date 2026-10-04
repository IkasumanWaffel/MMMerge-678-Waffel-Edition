-- Save and restore Player.Attrs to/from vars.PlayersAttrs
local LogId = "PlayersAttrs"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MC, MM, MT, MV = Merge.Consts, Merge.ModSettings, Merge.Tables, Merge.Vars

function events.GameInitialized2()
	MV.PlayersAttrs = MV.PlayersAttrs or {}

	-- Rod:
	-- "Player" is lua table with custom metatable, thus we have
	--     to edit metatable to properly add new field:
	local player = Party.PlayersArray[0]
	local metatable = getmetatable(player)
	local updated = false
	if not metatable.offsets.Attrs then
		metatable.offsets.Attrs = 0
		metatable.members.Attrs = function(offset, parent, field, value)
			--local playerId = (parent["?ptr"] - Party.PlayersArray["?ptr"])/parent["?size"]
			local playerId = parent.RosterBitIndex - 400
			if value then
				MV.PlayersAttrs[playerId] = value
			else
				return MV.PlayersAttrs[playerId]
			end
		end
		updated = true
	end
	if not metatable.offsets.Extra then
		metatable.offsets.Extra = 0
		metatable.members.Extra = function(offset, parent, field, value)
			local playerId = parent.RosterBitIndex - 400
			if value then
				Game.PlayersExtra[playerId] = value
			else
				return Game.PlayersExtra[playerId]
			end
		end
		updated = true
	end
	if updated then
		setmetatable(player, metatable)
	end
	-- Rod.
end

local spc_attack_fields = {
	'Spell', 'Skill', 'DamageType', 'SpellPoints', 'Recovery',
	'NextTime', 'Bits', 'Cooldown', 'Projectile', 'Sound'
}

local function set_race_spc_attack(roster_id, race, ranged, face)
	if tonumber(ranged) then
		ranged = (tonumber(ranged) > 0) and 1 or 0
	else
		ranged = ranged and 1 or 0
	end
	if MT.Races[race] and MT.Races[race].SpcAttack and MT.Races[race].SpcAttack[ranged] then
		for _, k in pairs(spc_attack_fields) do
			Game.PlayersExtra[roster_id].SpcAttack[ranged][k] =
				MT.Races[race].SpcAttack[ranged][k] or 0
		end
	end
	if face then
		if ranged == 0 then
			Game.PlayersExtra[roster_id].SpcAttackMelee.Spell =
				MF.GetPortraitSpcAttack(Party.PlayersArray[roster_id].Face)
		else
			Game.PlayersExtra[roster_id].SpcAttackRanged.Spell =
				MF.GetPortraitSpcAttack(Party.PlayersArray[roster_id].Face, true)
		end
	end
end
MF.SetRaceSpcAttack = set_race_spc_attack

local function set_spell_buff(buff, t)
	buff.Bits = t and t.Bits or 0
	buff.Caster = t and t.Caster or 0
	buff.ExpireTime = t and t.ExpireTime or 0
	buff.OverlayId = t and t.OverlayId or 0
	buff.Power = t and t.Power or 0
	buff.Skill = t and t.Skill or 0
end

local function before_save_game()
	vars.PlayersAttrs = MV.PlayersAttrs
	vars.PlayersExtra = vars.PlayersExtra or {}
	for i = 0, Party.PlayersArray.count - 1 do
		vars.PlayersExtra[i] = vars.PlayersExtra[i] or {}
		vars.PlayersExtra[i].SpcAttackMelee = vars.PlayersExtra[i].SpcAttackMelee or {}
		vars.PlayersExtra[i].SpcAttackRanged = vars.PlayersExtra[i].SpcAttackRanged or {}
		for _, k in pairs(spc_attack_fields) do
			vars.PlayersExtra[i].SpcAttackMelee[k] = Game.PlayersExtra[i].SpcAttackMelee[k]
			vars.PlayersExtra[i].SpcAttackRanged[k] = Game.PlayersExtra[i].SpcAttackRanged[k]
		end
		-- Player buffs and debuffs
		vars.PlayersExtra[i].SpellBuffs2 = vars.PlayersExtra[i].SpellBuffs2 or {}
		for j = 27, 27 + MC.PlayerBuffs2Count - 1 do
			vars.PlayersExtra[i].SpellBuffs2[j] = vars.PlayersExtra[i].SpellBuffs2[j] or {}
			set_spell_buff(vars.PlayersExtra[i].SpellBuffs2[j],
				Game.PlayersExtra[i].SpellBuffs2[j])
		end
		vars.PlayersExtra[i].Debuffs = vars.PlayersExtra[i].Debuffs or {}
		for j = 0, MC.PlayerDebuffsCount - 1 do
			vars.PlayersExtra[i].Debuffs[j] = vars.PlayersExtra[i].Debuffs[j] or {}
			set_spell_buff(vars.PlayersExtra[i].Debuffs[j],
				Game.PlayersExtra[i].Debuffs[j])
		end
	end
	-- Party buffs and debuffs
	vars.PartyStats = vars.PartyStats or {}
	vars.PartyStats.SpellBuffs2 = vars.PartyStats.SpellBuffs2 or {}
	for i = 20, 20 + MC.PartyBuffs2Count - 1 do
		vars.PartyStats.SpellBuffs2[i] = vars.PartyStats.SpellBuffs2[i] or {}
		set_spell_buff(vars.PartyStats.SpellBuffs2[i], Party.SpellBuffs2[i])
	end
	vars.PartyStats.Debuffs = vars.PartyStats.Debuffs or {}
	for i = 0, MC.PartyDebuffsCount - 1 do
		vars.PartyStats.Debuffs[i] = vars.PartyStats.Debuffs[i] or {}
		set_spell_buff(vars.PartyStats.Debuffs[i], Party.Debuffs[i])
	end
end

function events.BeforeSaveGame()
	MF.LogVerbose("%s: BeforeSaveGame", LogId)
	before_save_game()
end

function events.BeforeNewGameAutosave()
	MF.LogVerbose("%s: BeforeNewGameAutosave", LogId)
	-- set default race spc attack parameters
	for i = 0, 49 do
		local pl = Party.PlayersArray[i]
		local race = pl.Attrs.Race or Game.CharacterPortraits[pl.Face].Race
		set_race_spc_attack(i, race, false, true)
		--Game.PlayersExtra[i].SpcAttackMelee.Spell =
		--	MF.GetPortraitSpcAttack(pl.Face)
		set_race_spc_attack(i, race, true, true)
		--Game.PlayersExtra[i].SpcAttackRanged.Spell =
		--	MF.GetPortraitSpcAttack(pl.Face, true)
	end
	before_save_game()
end

local function determine_player_maturity(player)
	-- FIXME
	return math.min(Game.ClassesExtra[player.Class].Step, MM.Races.MaxMaturity)
end
MF.DeterminePlayerMaturity = determine_player_maturity

function events.InternalBeforeLoadMap(WasInGame)
	if not WasInGame then
		MF.LogVerbose("%s: InternalBeforeLoadMap", LogId)
		-- Looks like new game start time can be bigger than 138240
		if not vars.PlayersAttrs and Game.Time <= 138245 and not MV.NewGame then
			-- Clear PlayersAttrs on non-initial new game autosave load
			MF.LogWarning("%s: [%d] No vars.PlayersAttrs, reset PlayersAttrs", LogId, Game.Time)
			MF.ResetPlayersAttrs()
		end

		MV.PlayersAttrs = vars.PlayersAttrs or MV.PlayersAttrs
		if MV.PlayersAttrs == nil then
			MF.LogInfo("%s: neither MV.PlayersAttrs nor vars.PlayersAttrs", LogId)
			MV.PlayersAttrs = {}
		end

		local t

		for i = 0, Party.PlayersArray.count - 1 do
			local player = Party.PlayersArray[i]
			--Log(Merge.Log.Info, "PlayersAttrs: Player %d", k)
			MV.PlayersAttrs[i] = MV.PlayersAttrs[i] or {}
			if player.Attrs.Race == nil then
				player.Attrs.Race = GetCharRace(player)
				MF.LogInfo("Set default race %d for player %d", player.Attrs.Race, i)
			end
			if player.Attrs.Maturity == nil then
				player.Attrs.Maturity = determine_player_maturity(player)
			end
			if player.Attrs.PromoAwards == nil then
				player.Attrs.PromoAwards = {}
			end
			if player.Attrs.ExtraQuickSpells == nil then
				player.Attrs.ExtraQuickSpells = {}
			end
			if vars.PlayersExtra and vars.PlayersExtra[i] and vars.PlayersExtra[i].SpcAttackMelee then
				for _, k in pairs(spc_attack_fields) do
					Game.PlayersExtra[i].SpcAttackMelee[k] =
						vars.PlayersExtra[i].SpcAttackMelee[k] or 0
				end
			else
				set_race_spc_attack(i, player.Attrs.Race, false, true)
			end
			if vars.PlayersExtra and vars.PlayersExtra[i] and vars.PlayersExtra[i].SpcAttackRanged then
				for _, k in pairs(spc_attack_fields) do
					Game.PlayersExtra[i].SpcAttackRanged[k] =
						vars.PlayersExtra[i].SpcAttackRanged[k] or 0
				end
			else
				set_race_spc_attack(i, player.Attrs.Race, true, true)
			end
			-- Player buffs and debuffs
			t = vars.PlayersExtra and vars.PlayersExtra[i] and vars.PlayersExtra[i].SpellBuffs2
			for j = 27, 27 + MC.PlayerBuffs2Count - 1 do
				set_spell_buff(Game.PlayersExtra[i].SpellBuffs2[j],
					t and t[j])
			end
			t =  vars.PlayersExtra and vars.PlayersExtra[i] and vars.PlayersExtra[i].Debuffs
			for j = 0, MC.PlayerDebuffsCount - 1 do
				set_spell_buff(Game.PlayersExtra[i].Debuffs[j],
					t and t[j])
			end
		end
		-- Party buffs and debuffs
		t = vars.PartyStats and vars.PartyStats.SpellBuffs2
		for j = 20, 20 + MC.PartyBuffs2Count - 1 do
			set_spell_buff(Party.SpellBuffs2[j], t and t[j])
		end
		t = vars.PartyStats and vars.PartyStats.SpellDebuffs
		for j = 0, MC.PartyDebuffsCount - 1 do
			set_spell_buff(Party.Debuffs[j], t and t[j])
		end
	end
end

local function player_attrs_clear(roster_id)
	if not roster_id then return end
	--MV.PlayersAttrs[roster_id] = {}
	MV.PlayersAttrs[roster_id] = MV.PlayersAttrs[roster_id] or {}
	local attrs = MV.PlayersAttrs[roster_id]
	attrs.Race = nil
	attrs.Maturity = nil
	attrs.Alignment = nil
	attrs.PromoAwards = {}
	attrs.ExtraQuickSpells = {}
	-- Buffs and debuffs
	for i = 27, 27 + MC.PlayerBuffs2Count - 1 do
		set_spell_buff(Game.PlayersExtra[roster_id].SpellBuffs2[i], nil)
	end
	for i = 0, MC.PlayerDebuffsCount - 1 do
		set_spell_buff(Game.PlayersExtra[roster_id].Debuffs[i], nil)
	end
end
MF.PlayerAttrsClear = player_attrs_clear

local function reset_players_attrs()
	for k = 0, Party.PlayersArray.count - 1 do
		player_attrs_clear(k)
	end
end
MF.ResetPlayersAttrs = reset_players_attrs

function events.NewGame(WasInGame, Continent)
	MF.LogInfo("%s: NewGame, was in game: %d", LogId, WasInGame and 1 or 0)
	reset_players_attrs()
end

MF.LogInit2(LogId)

