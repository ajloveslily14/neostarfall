--[[
	All code related to editor themes.
]]

SF.Editor.Themes = {}

include("xml.lua")

SF.Editor.Themes.Themes = {}
SF.Editor.Themes.CurrentTheme = nil -- Theme table

local DEFAULT_THEME = "vsdark"
SF.Editor.Themes.ThemeConVar = CreateClientConVar("sf_editor_theme", DEFAULT_THEME, true, false)

SF.Editor.Themes.DebugOutput = false

local themeformat_version = 1 --Change that if previous themes arent compatibile anymore
SF.Editor.Themes.Version = themeformat_version

local function debugPrint(...)
	if not SF.Editor.Themes.DebugOutput then
		return
	end
	local args = { ... }
	args[1] = "[TextMate Debug]" .. args[1]
	return print(string.format(...))
end

function SF.Editor.Themes.Load()
	if not file.Exists("sf_themes.txt", "DATA") then
		SF.Editor.Themes.SwitchTheme(DEFAULT_THEME)
		return
	end

	-- Load themes from file

	local contents = file.Read("sf_themes.txt")
	local result = util.JSONToTable(contents)

	if not result then
		print("A problem occured during parsing sf_themes.txt, the file will be renamed to sf_themes_old.txt")
		file.Write("sf_themes_old.txt", contents)
		file.Delete("sf_themes.txt")

		SF.Editor.Themes.SwitchTheme(DEFAULT_THEME)

		return
	end

	SF.Editor.Themes.Themes = result

	-- Switch the theme, if invalid - switch to default

	local conVarTheme = SF.Editor.Themes.ThemeConVar:GetString()
	if SF.Editor.Themes.Themes[conVarTheme] then
		SF.Editor.Themes.SwitchTheme(conVarTheme)
	else
		SF.Editor.Themes.SwitchTheme(DEFAULT_THEME)
	end
end

function SF.Editor.Themes.Save()
	file.Write("sf_themes.txt", util.TableToJSON(SF.Editor.Themes.Themes))
end

function SF.Editor.Themes.AddTheme(name, tbl)
	tbl.Version = themeformat_version
	SF.Editor.Themes.Themes[name] = tbl
	SF.Editor.Themes.Save()
end

function SF.Editor.Themes.RemoveTheme(name)
	if table.Count(SF.Editor.Themes.Themes) == 1 then
		print("Can't remove the last theme")
		return
	end

	SF.Editor.Themes.Themes[name] = nil

	if SF.Editor.Themes.ThemeConVar:GetString() == name then
		SF.Editor.Themes.SwitchTheme(next(SF.Editor.Themes.Themes))
	end

	SF.Editor.Themes.Save()
end

function SF.Editor.Themes.SwitchTheme(name)
	local theme = SF.Editor.Themes.Themes[name]

	if not theme then
		print("No such theme " .. name)
		return
	end
	if theme.Version ~= themeformat_version then
		SF.Editor.Themes.SwitchTheme(DEFAULT_THEME)
		print("Theme " .. name .. " isnt compatibile with this Neostarfall version, you have to reimport it!")
		return
	end

	SF.Editor.Themes.CurrentTheme = theme
	SF.Editor.Themes.ThemeConVar:SetString(name)
	if SF.Editor.editor then
		SF.Editor.editor:OnThemeChange(theme)
	end
end

local function parseTextMate(text)
	local xml = SF.Editor.Themes.CreateXMLParser()
	xml:parse(text:Trim())

	if not xml._handler.root.children then
		error("No XML tags found.")
	end

	local plist = xml._handler.root.children[1]

	-- Parse dict

	local function parseDict(dict)
		if not dict.children then
			return {}
		end

		local tbl = {}

		for i = 1, #dict.children, 2 do
			local value = dict.children[i + 1]

			if value.name == "string" then
				tbl[dict.children[i].value] = value.value
			elseif value.name == "dict" then
				tbl[dict.children[i].value] = parseDict(value)
			elseif value.name == "array" then
				tbl[dict.children[i].value] = {}

				for k, v in pairs(value.children) do
					tbl[dict.children[i].value][#tbl[dict.children[i].value] + 1] = parseDict(v)
				end
			end
		end

		return tbl
	end

	local parsed = parseDict(plist.children[1])

	local tbl = {}

	-- Editor values

	tbl.Name = parsed.name or "No name"

	local function parseColor(hex)
		if not hex then
			return
		end -- In case there is no color just return nil
		return Color(
			tonumber("0x" .. hex:sub(2, 3)),
			tonumber("0x" .. hex:sub(4, 5)),
			tonumber("0x" .. hex:sub(6, 7)),
			#hex >= 9 and tonumber("0x" .. hex:sub(8, 9))
		)
	end

	tbl.background = parseColor(parsed.settings[1].settings.background)
	tbl.line_highlight = parseColor(parsed.settings[1].settings.lineHighlight)
	tbl.caret = parseColor(parsed.settings[1].settings.caret)
	tbl.selection = parseColor(parsed.settings[1].settings.selection)
	tbl.notfound = { parseColor(parsed.settings[1].settings.foreground), nil, 0 }
	tbl.operator = { parseColor(parsed.settings[1].settings.foreground), nil, 0 }

	-- Gutter settings

	if parsed.gutterSettings then
		tbl.gutter_foreground = parseColor(parsed.gutterSettings.foreground)
		tbl.gutter_background = parseColor(parsed.gutterSettings.background)
		tbl.gutter_divider = parseColor(parsed.gutterSettings.divider)
	end

	-- Token settings
	local map = {
		["Keyword"] = { "keyword", "storageType" },
		["Built-in constant"] = { "constant", "directive" },
		["Constant"] = { "constant", "directive" },
		["Constants"] = { "constant", "directive" },
		["Function name"] = { "function", "userfunction", "method" },
		["Function"] = { "function", "userfunction", "method" },
		["Library function"] = { "function", "userfunction", "method" },
		["String"] = { "string" },
		["Number"] = { "number" },
		["Comment"] = { "comment" },
		["Class name"] = { "library" },
		["Operators"] = { "operator" },
		["Storage type"] = { "storageType" },
		["Variable"] = { "identifier" },
	}

	local newmap = {}
	for k, v in pairs(map) do -- It's not "normalized" in source for readability
		k = k:gsub("%s", ""):lower()
		newmap[k] = v
	end
	map = newmap

	PrintTable(parsed.settings)
	for k, v in pairs(parsed.settings) do
		local foreground, background, fontStyle =
			parseColor(v.settings.foreground), parseColor(v.settings.background), v.settings.fontStyle
		fontStyle = fontStyle or "normal"

		if fontStyle:lower() == "italic" then
			fontStyle = 1
		elseif fontStyle:lower() == "bold" then
			fontStyle = 1
		else
			fontStyle = 0
		end
		if not v.name then
			goto cont
		end
		local names = string.Explode(",", v.name:gsub("%s", ""):lower())
		for _, name in pairs(names) do
			local token = map[name] -- Potential token
			if token then
				debugPrint("Parsing %q as %s", name, table.concat(token, ","))
				for k, v in pairs(token) do
					tbl[v] = { foreground, background, fontStyle }
				end
			else
				debugPrint("[TextMate Import] Ignored setting:%q", name)
			end
		end

		::cont::
	end

	tbl.operator = tbl.operator or tbl.keyword

	-- Copy values from default theme to avoid problems with nil values

	local strId = tbl.Name:Trim():Replace(" ", ""):lower()

	return tbl, strId
end

--- Parses a TextMate XML theme file.
-- @param text The contents of XML file
-- @return Theme table that can be used with SF.Editor.Themes.AddTheme, nil if there was an error
-- @return Sanitized string identifier for the theme - a lowercase string without whitespace, nil if there was an error
-- @return Parsing error string
function SF.Editor.Themes.ParseTextMate(text)
	local ok, themeTable, strId = pcall(parseTextMate, text)

	if not ok then
		return nil, nil, themeTable
	end

	return themeTable, strId
end

local VS_Control_Light = Color(156, 220, 254)
local VS_Control = Color(86, 156, 214)

local VS_FunctionName = Color(220, 220, 170)
local VS_Keyword = Color(197, 134, 192)

SF.Editor.Themes.AddTheme("vsdark", {
	Name = "VS Dark Modern",

	["background"] = Color(30, 30, 30),
	["line_highlight"] = Color(0, 0, 0, 0),

	["gutter_foreground"] = Color(146, 144, 140),
	["gutter_background"] = Color(36, 36, 31),
	["gutter_divider"] = Color(47, 49, 41),

	["caret"] = Color(248, 248, 242),
	["selection"] = Color(129, 164, 219, 20),

	["word_highlight"] = Color(30, 150, 30),

	--{foreground color, background color, fontStyle}
	["keyword"] = { VS_Keyword, nil, 0 },
	["storageType"] = { VS_Keyword, nil, 0 },
	["directive"] = { VS_Control, nil, 0 },
	["comment"] = { Color(106, 153, 85), nil, 1 },
	["string"] = { Color(206, 145, 120), nil, 0 },
	["number"] = { Color(181, 206, 168), nil, 0 },
	["function"] = { VS_FunctionName, nil, 0 },
	["method"] = { VS_FunctionName, nil, 0 },
	["library"] = { VS_FunctionName, nil, 0 },
	["operator"] = { Color(212, 212, 212), nil, 0 },
	["notfound"] = { Color(248, 248, 242), nil, 0 },
	["bracket"] = { Color(212, 212, 212), nil, 0 },
	["userfunction"] = { VS_FunctionName, nil, 0 },
	["constant"] = { VS_Control, nil, 0 },
	["identifier"] = { VS_Control_Light, nil, 0 },
})

SF.Editor.Themes.AddTheme("monokai", {
	Name = "Monokai Theme",

	["background"] = Color(30, 30, 30),
	["line_highlight"] = Color(39, 40, 34),

	["gutter_foreground"] = Color(143, 144, 138),
	["gutter_background"] = Color(47, 49, 41),
	["gutter_divider"] = Color(47, 49, 41),

	["caret"] = Color(240, 240, 240),
	["selection"] = Color(73, 72, 62),

	["word_highlight"] = Color(30, 150, 30),

	--{foreground color, background color, fontStyle}
	["keyword"] = { Color(249, 38, 114), nil, 0 },
	["storageType"] = { Color(249, 38, 114), nil, 0 },
	["directive"] = { Color(230, 219, 116), nil, 0 },
	["comment"] = { Color(117, 113, 94), nil, 1 },
	["string"] = { Color(230, 219, 116), nil, 0 },
	["number"] = { Color(174, 129, 255), nil, 0 },
	["function"] = { Color(137, 189, 255), nil, 0 },
	["method"] = { Color(137, 189, 255), nil, 0 },
	["library"] = { Color(137, 189, 255), nil, 0 },
	["operator"] = { Color(249, 38, 114), nil, 0 },
	["notfound"] = { Color(230, 230, 230), nil, 0 },
	["bracket"] = { Color(230, 230, 230), nil, 0 },
	["userfunction"] = { Color(166, 226, 42), nil, 0 },
	["constant"] = { Color(174, 129, 255), nil, 0 },
	["identifier"] = { Color(230, 230, 230), nil, 0 },
})

SF.Editor.Themes.Load()
