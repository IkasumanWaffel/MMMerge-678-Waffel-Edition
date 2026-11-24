--[[
	MMMWE_Werewolves.lua — the full moon over Blackshire, and lycanthropy (23.11.26)

	1. Werewolf nights in Blackshire
	   The moon is full on the 15th of every month (MMMWE_Moon.lua). On the night of the 15th
	   (from sunset to sunrise; ModSettings Scripts.WerewolfFullMoonNights 3: the nights of the
	   14th, 15th and 16th; 0: never), the villagers of Blackshire turn into werewolves, as the
	   town's old quest always said and never showed. At sunrise they are villagers again, where
	   the night left them. A villager killed as a werewolf stays dead, and the deed costs the
	   party's reputation as the killing of any peasant does. The houses and shops of Blackshire
	   are closed on those nights.
	   The nights end for good once the Werewolf Leader is dead (award 210, the Pearl of Purity
	   quest of the Lair of the Wolf).

	2. Lycanthropy (debuff 33, shown with the conditions)
	   A werewolf's bite may pass on the curse: LYCAN.Chance % of the hits of a werewolf
	   (Wolfman, Werewolf, Greater Werewolf), LYCAN.ChanceFullMoon % on a werewolf night.
	   The Pearl of Purity in the party's bags protects from it.
	   A cursed character turns into a beast on every full moon night, wherever the party is:
	   Might and Endurance +LYCAN.Strong %, Speed +LYCAN.Fast %, Intellect and Personality
	   -LYCAN.Mind %, no spells, and the wounds close (LYCAN.Regen % of Hit Points a minute).
	   At sunrise the beast is gone until the next full moon. The debuff's timer counts down to
	   the next transformation, and in it to the sunrise.
	   Cured by Remove Curse at Master or above cast on the character, Divine Intervention, the
	   Divine Restoration potion, and by the death of the Werewolf Leader.
	   The beast's eyes: until portraits of the beast form are drawn, a werebeast's portrait
	   gets yellow eyes with narrow pupils (the picture "lyceye" in waffel.icons.lod), drawn
	   over each frame where its eyes are open, at the pupils tracked over all frames
	   (MMMWE_LycanEyesData.lua), the way the game draws its mask over the portraits of an
	   invisible party.

	State: vars.MMMWE_Lycanthropy[roster index] = {Since = time}; map: mapvars.MMMWE_WereNight
--]]

local MF, MM = Merge.Functions, Merge.ModSettings
local Tx = MF.Text
local floor, max, min, random = math.floor, math.max, math.min, math.random

local W = {
	Map        = "outb2.odm",      -- Blackshire
	FullDay    = 15,               -- day of the month of the full moon
	Group      = 42,               -- the night's werewolves
	Wolves     = {643, 644},       -- Wolfman, Werewolf (one in WolfB is a Werewolf)
	WolfB      = 4,
	Houses     = {34, 71, 106, 174, 181, 196, 277, 278, 302, 327, 478, 1264, 1279, 1289, 1294,
		1307, 1319, 1330, 1342, 1354, 1365, 1376, 1387, 1397, 1407, 1431, 1440, 1449, 1457,
		1464, 1588},             -- 2DEvents.txt: the houses of Blackshire (map 141)
	ClosedOpen = 6, ClosedClose = 18,  -- their hours on a werewolf night (closed at night)
	LeaderAward = 210,             -- Killed the Werewolf Leader
	CheckEvery = 2,                -- seconds
}
local LYCAN = {
	Debuff         = 33,
	Chance         = 3,            -- % per werewolf hit
	ChanceFullMoon = 10,
	Strong         = 30,
	Fast           = 15,
	Mind           = 50,
	Regen          = 1,            -- % of full HP per game minute
	Wolves         = {[643] = true, [644] = true, [645] = true},
	Pearl          = 2079,         -- Pearl of Purity
	CureMastery    = const.Master or 3,
}
MF.WerewolfSettings, MF.LycanthropySettings = W, LYCAN

local MONTH_DAYS = 28
local EyePtrReset

local function nightsSetting()
	local v = MM.Scripts and tonumber(MM.Scripts.WerewolfFullMoonNights)
	if v == nil then return 1 end
	return v
end

local function sunTimes()
	local S = MF.SunSettings
	return S and S.Sunrise or 5.5, S and S.Sunset or 20.5
end

-- the day of the month (1..28) whose evening the current night belongs to, or nil by day
local function nightDay(time)
	time = time or Game.Time
	local rise, set = sunTimes()
	local days = time / const.Day
	local day = floor(days)
	local h = (days - day) * 24
	if h >= set then return day % MONTH_DAYS + 1 end
	if h < rise then return (day - 1) % MONTH_DAYS + 1 end
end

-- is this a full moon night (by the setting: the 15th, or the 14th to the 16th)?
local function fullMoonNight(time)
	local n = nightsSetting()
	if n <= 0 then return false end
	local d = nightDay(time)
	if not d then return false end
	if n >= 3 then return d >= W.FullDay - 1 and d <= W.FullDay + 1 end
	return d == W.FullDay
end
MF.FullMoonNight = fullMoonNight

local function leaderDead()
	for _, pl in Party do
		if pl.Awards[W.LeaderAward] then return true end
	end
	return false
end

-- the start of the next full moon night after time, and the sunrise ending the current one
local function nextNightStart(time)
	local rise, set = sunTimes()
	local day = floor(time / const.Day)
	for k = 0, MONTH_DAYS + 1 do
		local t = (day + k) * const.Day + floor(set * const.Hour)
		if t > time and fullMoonNight(t + 1) then return t end
	end
	return time + const.Month
end
local function sunriseAfter(time)
	local rise = sunTimes()
	local day = floor(time / const.Day)
	local t = day * const.Day + floor(rise * const.Hour)
	if t <= time then t = t + const.Day end
	return t
end

---------------------------------------------------------------------------
-- 1. the werewolf nights of Blackshire
---------------------------------------------------------------------------

local function isPeasant(m)
	local src = Game.Bolster and Game.Bolster.MonstersSource and Game.Bolster.MonstersSource[m.Id]
	return src and src.Creed == const.Bolster.Creed.Peasant and m.Group ~= 38 and m.Group ~= 55
end

local function alive(m)
	return m.HP > 0 and m.AIState ~= const.AIState.Removed and m.AIState ~= const.AIState.Dead
		and m.AIState ~= const.AIState.Dying
end

local KEEP = {"NPC_ID", "Group", "Ally", "NameId", "MoveType", "Direction", "GuardX", "GuardY", "GuardZ",
	"GuardRadius", "StartX", "StartY", "StartZ"}

local function copyFrom(m)
	local r = {Id = m.Id}
	for _, k in ipairs(KEEP) do
		local ok, v = pcall(function() return m[k] end)
		if ok then r[k] = v end
	end
	return r
end

local function copyTo(m, r)
	for _, k in ipairs(KEEP) do
		if r[k] ~= nil then pcall(function() m[k] = r[k] end) end
	end
end

local savedHours
local function closeHouses()
	if savedHours then return end
	savedHours = {}
	for _, i in ipairs(W.Houses) do
		local h = Game.Houses[i]
		if h then
			savedHours[i] = {h.OpenHour, h.CloseHour}
			h.OpenHour, h.CloseHour = W.ClosedOpen, W.ClosedClose
		end
	end
end
local function openHouses()
	if not savedHours then return end
	for i, v in pairs(savedHours) do
		local h = Game.Houses[i]
		if h then h.OpenHour, h.CloseHour = v[1], v[2] end
	end
	savedHours = nil
end

-- dusk: every villager becomes a werewolf (the wolves are summoned first, then the
-- villagers taken away, so no wolf takes a villager's place in the monster list)
local function turnToWolves()
	local list = {}
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if isPeasant(m) and alive(m) then list[#list + 1] = m end
	end
	local recs = {}
	for _, m in ipairs(list) do
		local id = random(W.WolfB) == 1 and W.Wolves[2] or W.Wolves[1]
		local ok, w = pcall(SummonMonster, id, m.X, m.Y, m.Z, false)
		if ok and w then
			pcall(w.LoadFramesAndSounds, w)
			w.Group = W.Group
			w.Ally = 0
			w.Hostile = true
			pcall(function() w.ShowAsHostile = true end)
			recs[#recs + 1] = {Wolf = w:GetIndex(), WolfId = id, Was = copyFrom(m)}
		end
	end
	for _, m in ipairs(list) do m.AIState = const.AIState.Removed end
	mapvars.MMMWE_WereNight = {Wolves = recs}
	if #recs > 0 then
		Game.ShowStatusText(Tx"The full moon rises over Blackshire... and the howling begins.", 5)
	end
end

-- dawn: the werewolves still alive are villagers again, where the night left them
local function turnBack()
	local st = mapvars.MMMWE_WereNight
	if not st then return end
	for _, r in ipairs(st.Wolves or {}) do
		local w = r.Wolf < Map.Monsters.count and Map.Monsters[r.Wolf]
		if w and w.Id == r.WolfId and w.Group == W.Group and alive(w) then
			local x, y, z = w.X, w.Y, w.Z
			w.AIState = const.AIState.Removed
			local ok, m = pcall(SummonMonster, r.Was.Id, x, y, z, false)
			if ok and m then
				pcall(m.LoadFramesAndSounds, m)
				copyTo(m, r.Was)
				m.Hostile = false
				pcall(function() m.ShowAsHostile = false end)
			end
		end
	end
	-- anything left of the night's pack
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.Group == W.Group and alive(m) then m.AIState = const.AIState.Removed end
	end
	mapvars.MMMWE_WereNight = nil
end

local function blackshire() return (Map.Name or ""):lower() == W.Map end

local function checkNight()
	if not blackshire() then return end
	local night = fullMoonNight() and not leaderDead()
	if night then
		closeHouses()
		if not mapvars.MMMWE_WereNight then turnToWolves() end
	else
		openHouses()
		if mapvars.MMMWE_WereNight then turnBack() end
	end
end

function events.MonsterKilled(mon)
	if mon.Group ~= W.Group or not blackshire() then return end
	-- a villager, cursed or not
	local rs = MF.ReputationSettings and MF.ReputationSettings()
	local pen = rs and rs.PenKillPeas
	if pen and pen ~= 0 then
		evt.ForPlayer(0)
		evt.Add("Reputation", pen)
	end
end

function events.LeaveMap() openHouses() end
function events.LeaveGame() savedHours = nil; EyePtrReset = true end

---------------------------------------------------------------------------
-- 2. lycanthropy
---------------------------------------------------------------------------

local function store()
	if not vars then return {} end
	vars.MMMWE_Lycanthropy = vars.MMMWE_Lycanthropy or {}
	return vars.MMMWE_Lycanthropy
end

local function debuff(pl)
	local ok, d = pcall(function() return Game.PlayersExtra[pl:GetIndex()].Debuffs[LYCAN.Debuff] end)
	return ok and d or nil
end

local function cursed(pl) return store()[pl:GetIndex()] ~= nil end
local function beast(pl) return cursed(pl) and fullMoonNight() end
MF.IsLycanthrope, MF.IsWerebeast = cursed, beast

local function cure(pl, quiet)
	local s = store()
	local k = pl:GetIndex()
	if not s[k] then return end
	s[k] = nil
	local d = debuff(pl)
	if d then d.ExpireTime = 0 end
	if not quiet then
		Game.ShowStatusText(string.format(Tx"%s is free of the werewolf's curse", pl.Name), 4)
	end
end
MF.CureLycanthropy = cure

local function pearlInParty()
	for _, pl in Party do
		for _, it in pl.Items do
			if it.Number == LYCAN.Pearl then return true end
		end
	end
	return Mouse.Item.Number == LYCAN.Pearl
end

local function infect(pl)
	local s = store()
	local k = pl:GetIndex()
	if s[k] then return end
	s[k] = {Since = Game.Time}
	Game.ShowStatusText(string.format(Tx"%s has been bitten by a werewolf... the wound burns strangely.", pl.Name), 4)
end

-- the werewolf behind the hit the party is taking right now
local function attacker()
	if not WhoHitPlayer then return end
	local who = WhoHitPlayer()
	if type(who) == "table" and who.Monster then return who.Monster end
end

function events.CalcDamageToPlayer(t)
	if not t.Player or (t.Result or 0) <= 0 then return end
	local m = attacker()
	if not m or not LYCAN.Wolves[m.Id] then return end
	if cursed(t.Player) or pearlInParty() then return end
	local ch = fullMoonNight() and LYCAN.ChanceFullMoon or LYCAN.Chance
	if random(100) <= ch then infect(t.Player) end
end

-- the beast's body and mind
local STATS = const.Stats
function events.CalcStatBonusByMagic(t)
	local pl = t.Player
	if not pl or not beast(pl) then return end
	local s = t.Stat
	local pct
	if s == STATS.Might or s == STATS.Endurance then pct = LYCAN.Strong
	elseif s == STATS.Speed then pct = LYCAN.Fast
	elseif s == STATS.Intellect or s == STATS.Personality then pct = -LYCAN.Mind
	end
	if not pct then return end
	local names = {[STATS.Might] = "Might", [STATS.Endurance] = "Endurance", [STATS.Speed] = "Speed",
		[STATS.Intellect] = "Intellect", [STATS.Personality] = "Personality"}
	local ok, base = pcall(pl["GetBase" .. names[s]], pl)
	if ok and base then t.Result = t.Result + floor(base * pct / 100) end
end

function events.CanPlayerCastSpell(t)
	local pl = t.PlayerPtr and MF.GetPlayerFromPtr and MF.GetPlayerFromPtr(t.PlayerPtr)
	if pl and beast(pl) then
		t.Result = false
		if t.Source ~= 4 then
			Game.ShowStatusText(string.format(Tx"%s can only snarl: no spells under the full moon", pl.Name), 2)
		end
	end
end

-- cures
function events.PlayerCastSpell(t)
	if t.SpellId == 88 then   -- Divine Intervention
		for _, pl in Party do cure(pl) end
	elseif t.SpellId == const.Spells.RemoveCurse and (t.Mastery or 0) >= LYCAN.CureMastery then
		if t.TargetKind == 4 and t.TargetId and t.TargetId < Party.count then
			cure(Party[t.TargetId])
		end
	end
end
do
	local old = evt.PotionEffects and evt.PotionEffects[32]   -- Divine Restoration
	if old then
		evt.PotionEffects[32] = function(IsDrunk, Target, Power, ...)
			local r = old(IsDrunk, Target, Power, ...)
			if IsDrunk and Target then cure(Target) end
			return r
		end
	end
end

-- the debuff's timer, the turning at dusk and dawn, the beast's healing
local Was = {}
local BeastSlots = {}   -- party slots of the werebeasts now (for the portraits)
local function lycanTick()
	local night = fullMoonNight()
	local now = Game.Time
	local dead = leaderDead()
	local slots = {}
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		if night and not dead and cursed(pl) then slots[slot] = true end
	end
	BeastSlots = slots
	for _, pl in Party do
		local k = pl:GetIndex()
		if cursed(pl) and dead then
			cure(pl)
		elseif cursed(pl) then
			local d = debuff(pl)
			if d then
				d.ExpireTime = night and sunriseAfter(now) or nextNightStart(now)
				d.Power = 1
			end
			if night and not Was[k] then
				Game.ShowStatusText(string.format(Tx"%s howls at the full moon!", pl.Name), 3)
			elseif not night and Was[k] then
				Game.ShowStatusText(string.format(Tx"The beast in %s sleeps until the next full moon", pl.Name), 2)
			end
			Was[k] = night or nil
		else
			Was[k] = nil
		end
	end
end

local LastMinute
local function regen()
	local minute = floor(Game.Time / const.Minute)
	if LastMinute and minute > LastMinute and fullMoonNight() then
		local n = min(minute - LastMinute, 60)
		for _, pl in Party do
			if beast(pl) and pl.HP > 0 and pl:IsConscious() then
				pl.HP = min(pl:GetFullHP(), pl.HP + max(1, floor(pl:GetFullHP() * LYCAN.Regen * n / 100)))
			end
		end
	end
	LastMinute = minute
end

local LastCheck = 0
function events.Tick()
	local now = os.clock()
	if now - LastCheck < W.CheckEvery then return end
	LastCheck = now
	pcall(checkNight)
	pcall(lycanTick)
	pcall(regen)
end

-- (24.11.26) no eyes until the werebeasts are found again for the map / game just loaded
function events.BeforeLoadMap()
	BeastSlots = {}
end

function events.AfterLoadMap()
	LastCheck, LastMinute = 0, nil
	pcall(checkNight)
end

---------------------------------------------------------------------------
-- the beast's eyes on the portrait
-- The party's portraits are drawn one by one (0x490C2D..0x490DFC: ebp the party slot, edi the
-- y, [0x4FD9D0 + slot * 2] the x, [esp+10h] the frame's picture, from the frames of the slot's
-- face, [0xAB2B34 + (face slot * 56 + frame) * 4], the face slot in [0xAB2FEC + slot * 4]).
-- After a werebeast's portrait, its eyes are drawn with the game's transparent draw
-- (0x4A419B), as the mask over an invisible party's faces is.
---------------------------------------------------------------------------

-- (24.11.26) the picture is found by its index, checked by name before every use: the game
-- frees and reuses the icons loaded during play (a load, a map change), so a kept pointer
-- could point at freed memory after loading a save (a crash when the portrait was drawn)
local EyeIdx
local function eyeBitmap()
	if EyePtrReset then EyeIdx, EyePtrReset = nil, nil end
	local lod = Game.IconsLod
	if EyeIdx then
		local ok, same = pcall(function()
			return EyeIdx < lod.Bitmaps.count and lod.Bitmaps[EyeIdx].Name:lower() == "lyceye"
		end)
		if not (ok and same) then EyeIdx = nil end
	end
	if not EyeIdx then
		local ok, idx = pcall(function() return lod:LoadBitmap("lyceye") end)
		if not ok or not idx or idx < 0 then return nil end
		EyeIdx = idx
	end
	return lod.Bitmaps[EyeIdx]["?ptr"]
end

mem.autohook(0x490DFC, function(d)
	local slot = d.ebp
	if not BeastSlots[slot] then return end
	local ok, err = pcall(function()
		local pl = Party[slot]
		local eyes = MF.LycanEyes and MF.LycanEyes[pl.Face]
		if not eyes then return end
		local img = mem.u4[d.esp + 0x10]
		local base = mem.u4[0xAB2FEC + slot * 4] * 0x38
		local frame
		for k = 0, 0x37 do
			if mem.u4[0xAB2B34 + (base + k) * 4] == img then frame = k + 1 break end
		end
		local e = frame and eyes[frame]
		local bmp = e and eyeBitmap()
		if not bmp then return end
		local x, y = mem.i2[0x4FD9D0 + slot * 2], d.edi
		mem.call(0x4A419B, 1, 0xEC1980, x + e[2] - 2, y + e[1] - 1, bmp, 0)
		mem.call(0x4A419B, 1, 0xEC1980, x + e[4] - 2, y + e[3] - 1, bmp, 0)
	end)
	if not ok and MF.LogWarning then MF.LogWarning("Werewolves: portrait eyes: %s", tostring(err)) end
end)
