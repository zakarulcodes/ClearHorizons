-- ClearHorizons: clears WoW Forever's volumetric fog and weather, and mutes weather sounds.
-- Every change to volumeFogLevel throws away the fog's built-up (temporal) history, so flipping it
-- every few frames keeps the fog from ever building up. It flips between levels 0 and 1, the two
-- cheapest: the fog is never visible, so a higher quality level would only cost FPS.
local ADDON_NAME = ...

local CVAR = "volumeFogLevel"
local LOW, HIGH = 0, 1
local MAX_STRENGTH = 5

local db
local pulse = CreateFrame("Frame")

local function say(msg) print("|cff8ad4ffClearHorizons|r: " .. msg) end

-- Frames between flips. Counted in frames, not seconds, because the fog rebuilds per frame.
local function FramesPerFlip() return MAX_STRENGTH + 1 - db.strength end

-- Put the player's real fog level back and forget it.
local function RestoreLevel()
	if db.savedLevel then
		C_CVar.SetCVar(CVAR, db.savedLevel)
		db.savedLevel = nil
	end
end

local function Apply()
	pulse:SetScript("OnUpdate", nil)
	if not db.enabled then return RestoreLevel() end
	-- Keep an existing savedLevel: it is the real level (a crash mid-flip leaves 0 or 1 in the CVar).
	db.savedLevel = db.savedLevel or C_CVar.GetCVar(CVAR)
	local frames, count, high = FramesPerFlip(), 0, false
	pulse:SetScript("OnUpdate", function()
		count = count + 1
		if count >= frames then
			count = 0
			high = not high
			C_CVar.SetCVar(CVAR, high and HIGH or LOW)
		end
	end)
end

-- Weather (rain, snow, sandstorms) needs no flipping: the chosen density, 0 (off) to 3 (heavy), is set
-- directly. Both the normal and the raid copies are set, as the raid one takes over in raids.
local WEATHER_CVARS = { "weatherDensity", "RAIDweatherDensity" }
local WEATHER_LEVELS = { [0] = "Off", "Light", "Medium", "Heavy" }

-- Put the player's own weather setting back on logout, so removing the addon undoes it. A saved 0
-- means the weather was already forced off before (a manual /console, or a client that quit before
-- restoring), so the game's default is used instead.
local function RestoreWeather()
	if not db.savedWeather then return end
	for _, cvar in ipairs(WEATHER_CVARS) do
		local value = db.savedWeather[cvar]
		if not value or tonumber(value) == 0 then value = C_CVar.GetCVarDefault(cvar) end
		if value then C_CVar.SetCVar(cvar, value) end
	end
	db.savedWeather = nil
end

local function ApplyWeather()
	if not db.savedWeather then
		db.savedWeather = {}
		for _, cvar in ipairs(WEATHER_CVARS) do db.savedWeather[cvar] = C_CVar.GetCVar(cvar) end
	end
	for _, cvar in ipairs(WEATHER_CVARS) do C_CVar.SetCVar(cvar, db.weatherLevel) end
end

-- Graphics presets and other addons can change the weather. Check every few seconds and put the chosen
-- level back. A changed non-zero value is the player's new own setting, so it is the one restored on logout.
-- The fog needs no watchdog: the pulse rewrites volumeFogLevel every few frames anyway.
local function EnforceWeather()
	for _, cvar in ipairs(WEATHER_CVARS) do
		local value = tonumber(C_CVar.GetCVar(cvar))
		if value and value ~= db.weatherLevel then
			if value ~= 0 then db.savedWeather[cvar] = value end
			C_CVar.SetCVar(cvar, db.weatherLevel)
		end
	end
end

-- Weather sound files by file ID, from the wowdev/wow-listfile sound/ambience/weather/ folder.
-- Muting them leaves the rest of the zone ambience alone.
local WEATHER_SOUNDS = {
	538981, 538982, 538983, -- original rain loops (medium, heavy, light)
	538984, 538985, 538989, -- original snow (heavy, light, medium)
	538986, 538987, 538988, -- original sandstorm (heavy, medium, light)
	2057626, 2057628, 2057629, 2057630, 2057631, 2057632, -- newer rain loops (heavy, light, medium)
	2067984, -- newer medium rain ambience
	2182419, 2182420, 2182422, 2182423, 2182424, 2182425, -- lightning storm loop and thunder claps
}
local soundsMuted = false

-- A mute only affects new plays, so a rain loop already playing would go on until a reload.
-- Switching ambience off and back on restarts the loops, which then honour the mute.
local function RestartAmbience()
	if C_CVar.GetCVar("Sound_EnableAmbience") ~= "1" then return end -- player turned ambience off
	C_CVar.SetCVar("Sound_EnableAmbience", 0)
	C_Timer.After(0.1, function() C_CVar.SetCVar("Sound_EnableAmbience", 1) end)
end

-- Mutes last until the client reloads, so this runs on every login.
local function ApplyWeatherSounds()
	if db.muteWeatherSounds == soundsMuted then return end
	local mute = db.muteWeatherSounds and MuteSoundFile or UnmuteSoundFile
	for _, id in ipairs(WEATHER_SOUNDS) do mute(id) end
	soundsMuted = db.muteWeatherSounds
	RestartAmbience()
end

-- UI pieces register a refresh function here, so every change shows everywhere at once.
local listeners = {}

local function Changed()
	Apply()
	ApplyWeather()
	ApplyWeatherSounds()
	for _, refresh in ipairs(listeners) do refresh() end
end

local function SetEnabled(enabled)
	db.enabled = enabled and true or false
	Changed()
end

local function SetWeatherLevel(level)
	db.weatherLevel = math.min(math.max(math.floor(level), 0), #WEATHER_LEVELS)
	if db.weatherLevel > 0 then db.lastWeatherLevel = db.weatherLevel end -- for /ch weather to toggle back to
	Changed()
end

local function SetWeatherSounds(mute)
	db.muteWeatherSounds = mute and true or false
	Changed()
end

local function SetStrength(strength)
	db.strength = math.min(math.max(math.floor(strength), 1), MAX_STRENGTH)
	Changed()
end

-- Options window (left-click the minimap button) ------------------------------------------------------

local options

local function BuildOptions()
	local win = CreateFrame("Frame", "ClearHorizonsOptions", UIParent, "BackdropTemplate")
	win:SetSize(240, 204)
	win:SetPoint("CENTER")
	win:SetFrameStrata("DIALOG")
	win:SetClampedToScreen(true)
	win:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	win:SetBackdropColor(0.04, 0.05, 0.08, 0.92)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:Hide()
	tinsert(UISpecialFrames, "ClearHorizonsOptions") -- Escape closes it

	local heading = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 12, -10)
	heading:SetText("ClearHorizons")

	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)

	local function AddToggle(y, text, isOn, setter)
		local box = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
		box:SetSize(24, 24)
		box:SetPoint("TOPLEFT", 10, y)
		box.Text:SetText(text)
		box:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
		return function() box:SetChecked(isOn()) end
	end
	local function AddCaption(y, text)
		local caption = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		caption:SetPoint("TOPLEFT", 14, y)
		caption:SetText(text)
		return caption
	end

	-- A row of buttons, one per value; the button for the current value stays lit.
	local function AddButtonRow(y, values, width, onClick, current)
		local buttons = {}
		for i, value in ipairs(values) do
			local button = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
			button:SetSize(width, 22)
			button:SetPoint("TOPLEFT", 12 + (i - 1) * (width + 4), y)
			button:SetText(value.label)
			button:SetScript("OnClick", function() onClick(value.value) end)
			buttons[i] = button
		end
		return function()
			for i, button in ipairs(buttons) do
				if values[i].value == current() then button:LockHighlight() else button:UnlockHighlight() end
			end
		end
	end

	local syncFog = AddToggle(-28, "Clear fog", function() return db.enabled end, SetEnabled)

	local strengthCaption = AddCaption(-60, "Fog strength")
	local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", strengthCaption, "BOTTOMLEFT", 0, -3)
	hint:SetText("Higher = smoother, but costs more FPS")
	local strengths = {}
	for i = 1, MAX_STRENGTH do strengths[i] = { value = i, label = i } end
	local syncStrength = AddButtonRow(-90, strengths, 34, SetStrength, function() return db.strength end)

	AddCaption(-124, "Weather")
	local levels = {}
	for i = 0, #WEATHER_LEVELS do levels[i + 1] = { value = i, label = WEATHER_LEVELS[i] } end
	local syncWeather = AddButtonRow(-140, levels, 50, SetWeatherLevel, function() return db.weatherLevel end)

	local syncSounds = AddToggle(-170, "Mute weather sounds", function() return db.muteWeatherSounds end, SetWeatherSounds)

	local function Sync()
		syncFog()
		syncStrength()
		syncWeather()
		syncSounds()
	end
	win:SetScript("OnShow", Sync)
	tinsert(listeners, function() if win:IsShown() then Sync() end end)
	return win
end

local function ToggleOptions()
	options = options or BuildOptions()
	options:SetShown(not options:IsShown())
end

-- Minimap button --------------------------------------------------------------------------------------

local function BuildMinimapButton()
	local btn = CreateFrame("Button", "ClearHorizonsMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- Standard minimap button layout: icon inset in the tracking ring.
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Spell_Nature_Cyclone")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 7, -6)

	local ring = btn:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")

	local function Place()
		local rad = math.rad(db.minimapAngle)
		local r = Minimap:GetWidth() / 2 + 5
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(rad), r * math.sin(rad))
	end

	local function FollowCursor()
		local scale = Minimap:GetEffectiveScale()
		local px, py = GetCursorPosition()
		local mx, my = Minimap:GetCenter()
		db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
		Place()
	end

	btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	btn:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then SetEnabled(not db.enabled) else ToggleOptions() end
	end)

	local function OnOff(on) return on and "|cff00ff00on|r" or "|cffff4040off|r" end
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("ClearHorizons")
		GameTooltip:AddLine("Fog clearing: " .. OnOff(db.enabled) .. ", strength " .. db.strength, 1, 1, 1)
		GameTooltip:AddLine("Weather: " .. WEATHER_LEVELS[db.weatherLevel], 1, 1, 1)
		GameTooltip:AddLine("Weather sounds muted: " .. OnOff(db.muteWeatherSounds), 1, 1, 1)
		GameTooltip:AddLine("Left-click: options   Right-click: fog on/off   Drag: move", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Grey icon while fog clearing is off.
	local function SyncIcon()
		icon:SetDesaturated(not db.enabled)
		icon:SetAlpha(db.enabled and 1 or 0.6)
	end
	tinsert(listeners, SyncIcon)

	Place()
	SyncIcon()
end

-- Events ----------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == ADDON_NAME then
		ClearHorizonsDB = ClearHorizonsDB or {}
		db = ClearHorizonsDB
		if db.enabled == nil then db.enabled = true end
		db.strength = db.strength or 3
		db.weatherLevel = db.weatherLevel or 0
		db.clearWeather = nil -- replaced by weatherLevel in 1.1.0
		if db.muteWeatherSounds == nil then db.muteWeatherSounds = true end
		db.minimapAngle = db.minimapAngle or 220
	elseif event == "PLAYER_LOGIN" then
		BuildMinimapButton()
		Apply()
		ApplyWeather()
		ApplyWeatherSounds()
		C_Timer.NewTicker(2, EnforceWeather)
	elseif event == "PLAYER_LOGOUT" then
		pulse:SetScript("OnUpdate", nil)
		RestoreLevel() -- so Config.wtf never saves a mid-flip level
		RestoreWeather() -- so removing the addon brings normal weather back
	end
end)

-- Slash command ---------------------------------------------------------------------------------------

SLASH_CLEARHORIZONS1 = "/ch"
SLASH_CLEARHORIZONS2 = "/clearhorizons"
SlashCmdList.CLEARHORIZONS = function(msg)
	msg = strtrim(msg or ""):lower()
	local strength = tonumber(msg)
	local weatherLevel = tonumber(msg:match("^weather%s+(%d)$"))
	if weatherLevel then
		SetWeatherLevel(weatherLevel)
	elseif strength then
		db.enabled = true
		SetStrength(strength)
	elseif msg == "on" then
		SetEnabled(true)
	elseif msg == "off" then
		SetEnabled(false)
	elseif msg == "" then
		SetEnabled(not db.enabled)
	elseif msg == "weather" then
		SetWeatherLevel(db.weatherLevel > 0 and 0 or (db.lastWeatherLevel or #WEATHER_LEVELS))
	elseif msg == "sounds" then
		SetWeatherSounds(not db.muteWeatherSounds)
	elseif msg == "options" then
		return ToggleOptions()
	else
		return say("usage: /ch (toggle fog)  /ch on|off  /ch 1-5 (strength)  /ch weather (off/on)  /ch weather 0-3 (off to heavy)  /ch sounds (toggle weather sounds)  /ch options")
	end
	say(("fog %s, strength %d (flip every %d frame%s), weather %s, weather sounds %s"):format(db.enabled and "cleared" or "normal",
		db.strength, FramesPerFlip(), FramesPerFlip() == 1 and "" or "s", WEATHER_LEVELS[db.weatherLevel]:lower(),
		db.muteWeatherSounds and "muted" or "on"))
end
