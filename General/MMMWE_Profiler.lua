--[[
	MMMWE_Profiler.lua — how much time the Lua scripts take (03.11.26)

	Ctrl+F12 starts measuring, Ctrl+F12 again stops and writes the report to
	MMMWE_Profile.txt in the game folder. From the debug console (Ctrl+F1):
	Profiler.Start(), Profiler.Stop(), Profiler.Report().
	Profiler.Settings.Seconds = N stops it by itself after N seconds of real time.

	While it runs, every handler of every event (events.Tick, events.CalcDamageToMonster...),
	every Lua hook (mem.hook, autohook, autohook2, hookfunction...) and the timers are timed
	with the CPU's high-resolution counter. Nothing is changed when it isn't running.

	The times are exclusive: a handler that raises another event doesn't get the time of that
	event's handlers, they're listed on their own. A hook's time does include the game code it
	runs itself (the "def" call of a hookfunction, functions it calls).

	The report has:
	  * frames: average and worst frame time, Lua time per frame (average and worst), how many
	    frames went over 25 ms (below 40 FPS) and how much of those frames was Lua
	  * scripts: the time of each file, all its handlers together
	  * handlers: each handler and hook, by total time (ms per second of play), with calls per
	    second, the average and the longest single call (long calls are the hitches)
--]]

local floor, max, format = math.floor, math.max, string.format
local getinfo, getupvalue, setupvalue = debug.getinfo, debug.getupvalue, debug.setupvalue

local P = {Settings = {Seconds = 0, Key = const.Keys.F12, SlowFrame = 25}}
Profiler = P
Merge.Functions.Profiler = P

---------------------------------------------------------------------------
-- the clock
---------------------------------------------------------------------------

local now, tickMs   -- now() in ticks, tickMs = milliseconds per tick

do
	local ok = pcall(function()
		local ffi = require("ffi")
		pcall(ffi.cdef, [[
			int QueryPerformanceCounter(int64_t *c);
			int QueryPerformanceFrequency(int64_t *f);
		]])
		local C, buf = ffi.C, ffi.new("int64_t[1]")
		C.QueryPerformanceFrequency(buf)
		local freq = tonumber(buf[0])
		assert(freq and freq > 0)
		tickMs = 1000 / freq
		now = function()
			C.QueryPerformanceCounter(buf)
			return tonumber(buf[0])
		end
		now()
	end)
	if not ok then
		local ok2 = pcall(function()
			local k32, buf = mem.dll.kernel32, mem.StaticAlloc(8)
			k32.QueryPerformanceFrequency(buf)
			local freq = mem.i8[buf]
			assert(freq and freq > 0)
			tickMs = 1000 / freq
			now = function()
				k32.QueryPerformanceCounter(buf)
				return mem.i8[buf]
			end
			now()
		end)
		if not ok2 then
			-- milliseconds only: single calls aren't measured well, totals still are
			now, tickMs = timeGetTime, 1
		end
	end
end

---------------------------------------------------------------------------
-- the measuring
---------------------------------------------------------------------------

local active = false
local depth = 0
local tStart, tChild = {}, {}
local stats = {}        -- [key] = {Name =, File =, N =, Excl =, Max =}
local frame = {}        -- frame statistics
local frameLua = 0      -- Lua time in the current frame (ticks)
local frameStart, startTime

local function enter()
	depth = depth + 1
	tStart[depth] = now()
	tChild[depth] = 0
	return depth
end

local function leave(rec, d)
	if depth < d then return end       -- dropped (a yield or an error below)
	depth = d                          -- drop frames left by an error inside
	local incl = now() - tStart[d]
	local excl = incl - tChild[d]
	depth = d - 1
	if depth > 0 then
		tChild[depth] = tChild[depth] + incl
	else
		frameLua = frameLua + incl
	end
	rec.N = rec.N + 1
	rec.Excl = rec.Excl + excl
	if excl > rec.Max then rec.Max = excl end
end

local function shortFile(src)
	src = (src or "?"):gsub("^@", "")
	return src:match("([^\\/]+)$") or src
end

local function funcInfo(fn)
	local i = getinfo(fn, "S")
	return shortFile(i and i.source), i and i.linedefined or 0
end

---------------------------------------------------------------------------
-- events: the dispatching functions of Core/EventsList.lua are swapped while measuring
---------------------------------------------------------------------------

local function findUp(fn, name)
	for i = 1, 200 do
		local n, v = getupvalue(fn, i)
		if not n then return end
		if n == name then return i, v end
	end
end

local evCall, evPcalls, evCocalls = rawget(events, "call"), rawget(events, "pcalls"), rawget(events, "cocalls")
local _, Handlers = findUp(evCall, "t")
local iDocall, origDocall = findUp(evCall, "docall")
local iSpec, origSpeccall = findUp(evPcalls, "speccall")
local iCoPart, origCocallPart = findUp(evCocalls, "cocallPart")
local ProcessReloc
if origDocall then _, ProcessReloc = findUp(origDocall, "ProcessReloc") end
local cocall2 = cocall2

local listName = setmetatable({}, {__mode = "k"})
local evRecs = setmetatable({}, {__mode = "k"})   -- [handler] = {[event] = rec}

local function eventName(f)
	local n = listName[f]
	if n then return n end
	for k, v in pairs(Handlers or {}) do listName[v] = k end
	return listName[f] or "?"
end

local function evRec(f, v)
	local byEv = evRecs[v]
	if not byEv then byEv = {}; evRecs[v] = byEv end
	local ev = eventName(f)
	local rec = byEv[ev]
	if not rec then
		local file, line = funcInfo(v)
		local key = ev .. "  " .. file .. ":" .. line
		rec = stats[key]
		if not rec then
			rec = {Name = key, File = file, N = 0, Excl = 0, Max = 0}
			stats[key] = rec
		end
		byEv[ev] = rec
	end
	return rec
end

local function pDocall(f, i, to, ...)
	local ret
	while i <= to do
		local v = f[i]
		i = i + 1
		if v then
			local rec, d = evRec(f, v), enter()
			local tmp = v(...)
			leave(rec, d)
			if tmp ~= nil then
				ret = tmp
			end
		elseif v == false then
			f, i, to = ProcessReloc(f, i - 1, to)
		end
	end
	return ret
end

local function pSpeccall(call, f, i, to, ...)
	local ret
	while i <= to do
		local v = f[i]
		i = i + 1
		if v then
			local rec, d = evRec(f, v), enter()
			local ok, tmp = call(v, ...)
			leave(rec, d)
			if tmp ~= nil and ok then
				ret = tmp
			end
		elseif v == false then
			f, i, to = ProcessReloc(f, i - 1, to)
		end
	end
	return ret
end

local function pCocallPart(ret, f, i, to, ...)
	local d0 = depth
	local ok = cocall2(function(...)
		while i <= to do
			local v = f[i]
			i = i + 1
			if v then
				local rec, d = evRec(f, v), enter()
				local tmp = v(...)
				leave(rec, d)
				if tmp ~= nil then
					ret = tmp
				end
			elseif v == false then
				f, i, to = ProcessReloc(f, i - 1, to)
			end
		end
	end, ...)
	if depth > d0 then depth = d0 end   -- a handler yielded or failed
	local i2 = i
	i = to + 1
	return ret, f, i2, to, ok
end

local function patchEvents(on)
	if not (Handlers and iDocall and iSpec and iCoPart and ProcessReloc and cocall2) then return false end
	setupvalue(evCall, iDocall, on and pDocall or origDocall)
	setupvalue(evPcalls, iSpec, on and pSpeccall or origSpeccall)
	setupvalue(evCocalls, iCoPart, on and pCocallPart or origCocallPart)
	return true
end

---------------------------------------------------------------------------
-- hooks: the entries of mem.hooks are wrapped while measuring
---------------------------------------------------------------------------

local hookOrig = {}     -- [wrapper] = original

local function hookName(p, fn)
	local file, line = funcInfo(fn)
	if file == "RSMem.lua" then   -- autohook & co.: the script's function is the upvalue 'f'
		local _, uf = findUp(fn, "f")
		if type(uf) == "function" then file, line = funcInfo(uf) end
	end
	return format("hook %X  %s:%d", p, file, line), file
end

local function wrapHooks()
	local hooks = mem.hooks
	if not hooks then return 0 end
	local n = 0
	for p, fn in pairs(hooks) do
		if type(fn) == "function" and not hookOrig[fn] then
			local name, file = hookName(p, fn)
			local rec = stats[name] or {Name = name, File = file, N = 0, Excl = 0, Max = 0}
			stats[name] = rec
			local w = function(data)
				local d = enter()
				fn(data)
				leave(rec, d)
			end
			hookOrig[w] = fn
			hooks[p] = w
			n = n + 1
		end
	end
	return n
end

local function unwrapHooks()
	local hooks = mem.hooks
	if not hooks then return end
	for p, fn in pairs(hooks) do
		local o = hookOrig[fn]
		if o then hooks[p] = o end
	end
	hookOrig = {}
end

---------------------------------------------------------------------------
-- timers and frames
---------------------------------------------------------------------------

local origOnTimer
local timerRec

local function onTimer(...)
	-- a game loop pass: one frame
	local t = now()
	if frameStart then
		local ft = t - frameStart
		frame.N = frame.N + 1
		frame.Time = frame.Time + ft
		frame.Lua = frame.Lua + frameLua
		if ft > frame.MaxTime then frame.MaxTime, frame.MaxTimeLua = ft, frameLua end
		if frameLua > frame.MaxLua then frame.MaxLua = frameLua end
		if ft * tickMs > P.Settings.SlowFrame then
			frame.Slow = frame.Slow + 1
			frame.SlowTime = frame.SlowTime + ft
			frame.SlowLua = frame.SlowLua + frameLua
		end
	end
	frameStart, frameLua = t, 0
	if P.Settings.Seconds > 0 and (t - startTime) * tickMs > P.Settings.Seconds * 1000 then
		P.Stop()
	end
	local d = enter()
	origOnTimer(...)
	leave(timerRec, d)
end

---------------------------------------------------------------------------
-- control
---------------------------------------------------------------------------

local function status(s)
	pcall(Game.ShowStatusText, s)
end

function P.Start()
	if active then return end
	stats, evRecs = {}, setmetatable({}, {__mode = "k"})
	frame = {N = 0, Time = 0, Lua = 0, MaxTime = 0, MaxTimeLua = 0, MaxLua = 0, Slow = 0, SlowTime = 0, SlowLua = 0}
	depth, frameLua, frameStart = 0, 0, nil
	timerRec = {Name = "timers, sleeps and Keys (Core/timers.lua)", File = "timers.lua", N = 0, Excl = 0, Max = 0}
	stats[timerRec.Name] = timerRec
	if not patchEvents(true) then
		status("Profiler: can't reach the events of this MMExtension version")
		return
	end
	wrapHooks()
	origOnTimer = internal.OnTimer
	internal.OnTimer = onTimer
	startTime = now()
	active = true
	status("Profiler: measuring (Ctrl+F12 to stop)")
end

function P.Stop()
	if not active then return end
	active = false
	P.Duration = (now() - startTime) * tickMs
	patchEvents(false)
	unwrapHooks()
	if internal.OnTimer == onTimer then internal.OnTimer = origOnTimer end
	local file = P.Report()
	status("Profiler: report saved to " .. (file or "?"))
end

function P.Report()
	local dur = P.Duration or (startTime and (now() - startTime) * tickMs) or 0
	if dur <= 0 then return end
	local sec = dur / 1000
	local out = {}
	local function add(s, ...) out[#out + 1] = format(s, ...) end
	local function ms(t) return t * tickMs end

	add("MMMWE profiler report, %s", os.date("%Y-%m-%d %H:%M:%S"))
	add("Measured %.1f s of real time. Clock: %s.", sec, tickMs < 0.01 and "high-resolution" or "milliseconds only")
	add("")
	local total = 0
	for _, r in pairs(stats) do total = total + r.Excl end
	if frame.N > 0 then
		add("FRAMES")
		add("  frames: %d, average %.2f ms (%.0f FPS), worst %.1f ms (Lua in it %.1f ms)",
			frame.N, ms(frame.Time) / frame.N, 1000 * frame.N / ms(frame.Time), ms(frame.MaxTime), ms(frame.MaxTimeLua))
		add("  Lua per frame: average %.2f ms (%.0f%% of the frame time), worst %.1f ms",
			ms(frame.Lua) / frame.N, 100 * frame.Lua / max(frame.Time, 1), ms(frame.MaxLua))
		add("  frames over %d ms: %d (%.1f%%), Lua in them %.0f%% of their time",
			P.Settings.SlowFrame, frame.Slow, 100 * frame.Slow / frame.N, 100 * frame.SlowLua / max(frame.SlowTime, 1))
		add("")
	end
	add("All measured Lua: %.2f ms per second of play (%.1f%% of the time)", ms(total) / sec, ms(total) / dur * 100)
	add("")

	-- by file
	local files, flist = {}, {}
	for _, r in pairs(stats) do
		local f = files[r.File]
		if not f then f = {File = r.File, Excl = 0, N = 0, Max = 0}; files[r.File] = f; flist[#flist + 1] = f end
		f.Excl, f.N, f.Max = f.Excl + r.Excl, f.N + r.N, max(f.Max, r.Max)
	end
	table.sort(flist, function(a, b) return a.Excl > b.Excl end)
	add("SCRIPTS (all handlers and hooks of a file)")
	add("  %9s %6s %10s %9s  %s", "ms/s", "share", "calls/s", "max ms", "file")
	for _, f in ipairs(flist) do
		if f.N > 0 then
			add("  %9.3f %5.1f%% %10.1f %9.2f  %s", ms(f.Excl) / sec, 100 * f.Excl / max(total, 1), f.N / sec, ms(f.Max), f.File)
		end
	end
	add("")

	-- by handler
	local list = {}
	for _, r in pairs(stats) do if r.N > 0 then list[#list + 1] = r end end
	table.sort(list, function(a, b) return a.Excl > b.Excl end)
	add("HANDLERS AND HOOKS")
	add("  %9s %6s %10s %9s %9s  %s", "ms/s", "share", "calls/s", "avg us", "max ms", "event / hook  file:line")
	for _, r in ipairs(list) do
		add("  %9.3f %5.1f%% %10.1f %9.1f %9.2f  %s", ms(r.Excl) / sec, 100 * r.Excl / max(total, 1),
			r.N / sec, ms(r.Excl) / r.N * 1000, ms(r.Max), r.Name)
	end
	add("")
	add("ms/s: milliseconds per second of play; at 60 FPS a frame has 16.7 ms.")
	add("max ms: the longest single call; long ones are what is felt as a hitch.")

	local path = (AppPath or "") .. "MMMWE_Profile.txt"
	local ok = pcall(function()
		local f = assert(io.open(path, "w"))
		f:write(table.concat(out, "\n"), "\n")
		f:close()
	end)
	return ok and path or nil
end

function events.KeyDown(t)
	if t.Key == P.Settings.Key and Keys.IsPressed(const.Keys.CTRL) then
		t.Key = 0
		if active then P.Stop() else P.Start() end
	end
end
