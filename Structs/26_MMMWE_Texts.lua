-- MMMWE script texts: a translation lookup for the texts the Waffel Edition scripts show.
--
-- The scripts write their texts as Tx"English text". Tx (Merge.Functions.Text) returns the
-- translation of the text in the chosen language, or the English text itself when there is
-- none, so the game reads exactly the same in English.
-- Tn"Name" (Merge.Functions.TextKey) marks an English name the scripts also use as a key
-- (class families, resources, stances...): it always stays English in the data and is
-- translated where it is shown, through Tx(name).
--
-- The language: MMMWE_Language.txt in the game folder, one line with the language's name
-- (the name of its folder), e.g. "Russian". No file, an empty one or "English": no lookup.
-- The texts: Data\Text localization\<Language>\Scripts.txt, one text per line:
--     English text<TAB>Translated text
-- with the escapes \n (new line), \t (tab), \\ and \" in both columns, lines starting with #
-- ignored, and a missing or empty translation leaving the English text. The file is read
-- as it is (the game's code page, e.g. Windows-1251 for Russian).
-- The template with every text and where it is used: Data\Text localization\Template\Scripts.txt
-- (Tools/script_texts.py makes it from the scripts). Changes are read when the game starts.

local MF = Merge.Functions

local function identity(s) return s end
MF.TextKey = identity
MF.Text = identity
MF.TextLanguage = "English"

local function readAll(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local function trim(s)
	return (s:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local UNESCAPE = {n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"', r = "\r"}
local function unescape(s)
	return (s:gsub("\\(.)", function(c) return UNESCAPE[c] or ("\\" .. c) end))
end

local lang = readAll(AppPath .. "MMMWE_Language.txt")
lang = lang and trim(lang:match("^[^\r\n]*") or "") or ""
if lang ~= "" and lang:lower() ~= "english" then
	MF.TextLanguage = lang
	local path = AppPath .. "Data\\Text localization\\" .. lang .. "\\Scripts.txt"
	local src = readAll(path)
	if not src then
		MF.LogWarning("MMMWE texts: no " .. path .. " - the script texts stay in English")
	else
		local T, n = {}, 0
		src = src:gsub("^\239\187\191", "")
		for line in src:gmatch("[^\r\n]+") do
			if line:sub(1, 1) ~= "#" then
				local en, tr = line:match("^(.-)\t(.*)$")
				if en and en ~= "" and tr and tr ~= "" then
					T[unescape(en)] = unescape(tr)
					n = n + 1
				end
			end
		end
		MF.TextTable = T
		MF.Text = function(s)
			return s ~= nil and T[s] or s
		end
		MF.LogInfo(string.format("MMMWE texts: %d translations (%s)", n, lang))
	end
end
