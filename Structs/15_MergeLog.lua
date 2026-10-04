-- Merge Log
local MF = Merge.Functions
local strformat, strmatch = string.format, string.match

local function log_main(LogLevel, StackLvl, Fmt, ...)
	local settings_loglevel = Merge.Settings.Logging.LogLevel
	if settings_loglevel > Merge.Log.Disabled and LogLevel <= settings_loglevel
			and Merge.Log.LogFile then
		local source = ""
		if Merge.Settings.Logging.PrintSources == 1 then
			-- local info = debug.getinfo(3, "Sl")
			local info = debug.getinfo(StackLvl, "Sl")
			source = strmatch(info.short_src, "[^/\\]+$") .. ":" .. info.currentline
		end
		-- Note: pcall is xpcall wrapper in MMExtension
		local result, fmt_msg = pcall(strformat, Fmt, ...)
		Merge.Log.LogFile:write(((Merge.Settings.Logging.PrintTimes == 1) and os.date("[%X")
				.. (Merge.Settings.Logging.PrintOsClock == 1 and ", " .. os.clock() or "")
				.. "] " or "")
				.. "(" .. Merge.Log.Indicator[LogLevel] .. ") "
				.. ((Merge.Settings.Logging.PrintSources == 1) and "[" .. source .. "] " or "")
				.. (result and fmt_msg or "Error formatting log message \"" .. Fmt .. "\": "
					.. (Merge.Settings.Logging.PrintFormatTraceback == 1 and fmt_msg
						or fmt_msg:split("\n")[1]))
				.. "\n")
		if (Merge.Settings.Logging.ForceFlush == 1) then
			Merge.Log.LogFile:flush()
		end
	end
end

local function log_base(LogLevel, Fmt, ...)
	log_main(LogLevel, 3, Fmt, ...)
end
Log = log_base
MF.Log = log_base

local function log_error(Fmt, ...)
	log_main(Merge.Log.Error, 3, Fmt, ...)
end
MF.LogError = log_error

local function log_warning(Fmt, ...)
	log_main(Merge.Log.Warning, 3, Fmt, ...)
end
MF.LogWarning = log_warning

local function log_info(Fmt, ...)
	log_main(Merge.Log.Info, 3, Fmt, ...)
end
MF.LogInfo = log_info

local function log_verbose(Fmt, ...)
	log_main(Merge.Log.Verbose, 3, Fmt, ...)
end
MF.LogVerbose = log_verbose

local function log_init1(log_id)
	log_main(Merge.Log.Verbose, 3, "Init started: %s", log_id)
end
MF.LogInit1 = log_init1

local function log_init2(log_id)
	log_main(Merge.Log.Verbose, 3, "Init finished: %s", log_id)
end
MF.LogInit2 = log_init2

local function log_mem(Fmt, ...)
	log_main(Merge.Log.Verbose, 4, Fmt, ...) 
end
MF.LogMem = log_mem

local function log_mem2(StackLvl, Fmt, ...)
	log_main(Merge.Log.Verbose, StackLvl, Fmt, ...)
end
MF.LogMem2 = log_mem2

-- Initialize Merge.Log
if not Merge or not Merge.Log then
	Merge = Merge or {}
	Merge.Log = {}
	-- Log Levels, update corresponding values in 10_MergeSettings.lua if changed
	Merge.Log.Disabled = 0
	Merge.Log.Fatal = 1
	Merge.Log.Error = 2
	Merge.Log.Warning = 3
	Merge.Log.Info = 4
	Merge.Log.Verbose = 5
	Merge.Log.Debug = 6
	-- Log Level indicators
	Merge.Log.Indicator = {}
	Merge.Log.Indicator[Merge.Log.Fatal] = "FF"
	Merge.Log.Indicator[Merge.Log.Error] = "EE"
	Merge.Log.Indicator[Merge.Log.Warning] = "WW"
	Merge.Log.Indicator[Merge.Log.Info] = "II"
	Merge.Log.Indicator[Merge.Log.Verbose] = "VV"
	Merge.Log.Indicator[Merge.Log.Debug] = "DD"
	if Merge.Settings.Logging.LogLevel > Merge.Log.Disabled then
		if not Merge.Log.LogFile then
			local settings_logfile = Merge.Settings.Logging.LogFile
			-- Rotate last logs
			if (string.sub(settings_logfile, -4) == ".txt") then
				local res1, errmsg1 = os.remove(string.sub(settings_logfile, 1, -4)
						.. Merge.Settings.Logging.OldLogsCount .. ".txt")
				if not res1 then
					print("Can't remove " .. errmsg1)
				end
				local res2, errmsg2
				for logn = Merge.Settings.Logging.OldLogsCount, 2, -1 do
					res2, errmsg2 = os.rename(string.sub(settings_logfile, 1, -4)
							.. (logn - 1) ..".txt",
							string.sub(settings_logfile, 1, -4)
							.. logn .. ".txt")
					if not res2 then
						print("Can't rename " .. errmsg2)
					end
				end
				local res3, errmsg3 = os.rename(settings_logfile,
						string.sub(settings_logfile, 1, -4) .. "1.txt")
				if not res3 then
					print("Can't rename " .. errmsg3)
				end
			else
				local res1, errmsg1 = os.remove(settings_logfile .. "."
						.. Merge.Settings.Logging.OldLogsCount)
				if not res1 then
					print("Can't remove " .. errmsg1)
				end
				local res2, errmsg2
				for logn = Merge.Settings.Logging.OldLogsCount, 2, -1 do
					res2, errmsg2 = os.rename(settings_logfile
							.. "." .. (logn - 1),
							settings_logfile .. "." .. logn)
					if not res2 then
						print("Can't rename " .. errmsg2)
					end
				end
				local res3, errmsg3 = os.rename(settings_logfile,
						settings_logfile .. ".1")
				if not res3 then
					print("Can't rename " .. errmsg3)
				end
			end
			-- Open new log file
			local errmsg, errnum
			Merge.Log.LogFile, errmsg, errnum = io.open(settings_logfile, "w")
			if not Merge.Log.LogFile then
				print("Can't create log file '" .. settings_logfile
						.. "'. Error " .. errnum .. ": " .. errmsg)
			else
				Merge.Log.LogFile:write("Log started on " .. os.date("%Y-%m-%d at %X")
						.. (Merge.Settings.Logging.PrintOsClock == 1 and ", " .. os.clock() or "")
						.. "\n")
				if (Merge.Settings.Logging.ForceFlush == 1) then
					Merge.Log.LogFile:flush()
				end
			end
		end
	end
end
