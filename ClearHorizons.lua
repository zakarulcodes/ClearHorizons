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

-- Weather (rain, snow, sandstorms) needs no flipping: setting the density to 0 once is enough.
-- Both the normal and the raid copies are set, as the raid one takes over in raids.
local WEATHER_CVARS = { "weatherDensity", "RAIDweatherDensity" }

local function RestoreWeather()
	if not db.savedWeather then return end
	for _, cvar in ipairs(WEATHER_CVARS) do
		if db.savedWeather[cvar] then C_CVar.SetCVar(cvar, db.savedWeather[cvar]) end
	end
	db.savedWeather = nil
end

local function ApplyWeather()
	if not db.clearWeather then return RestoreWeather() end
	if not db.savedWeather then
		db.savedWeather = {}
		for _, cvar in ipairs(WEATHER_CVARS) do db.savedWeather[cvar] = C_CVar.GetCVar(cvar) end
	end
	for _, cvar in ipairs(WEATHER_CVARS) do C_CVar.SetCVar(cvar, 0) end
end

-- Graphics presets and other addons can put the weather back. Check every few seconds and re-clear it.
-- A new non-zero value is the player's new real setting, so it becomes the one restored on logout.
-- The fog needs no watchdog: the pulse rewrites volumeFogLevel every few frames anyway.
local function EnforceWeather()
	if not db.clearWeather then return end
	for _, cvar in ipairs(WEATHER_CVARS) do
		local value = C_CVar.GetCVar(cvar)
		if value and tonumber(value) ~= 0 then
			db.savedWeather[cvar] = value
			C_CVar.SetCVar(cvar, 0)
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

local function SetWeather(clear)
	db.clearWeather = clear and true or false
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
	win:SetSize(214, 178)
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
	local syncFog = AddToggle(-28, "Clear fog", function() return db.enabled end, SetEnabled)
	local syncWeather = AddToggle(-52, "Clear weather", function() return db.clearWeather end, SetWeather)
	local syncSounds = AddToggle(-76, "Mute weather sounds", function() return db.muteWeatherSounds end, SetWeatherSounds)

	local caption = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("TOPLEFT", 14, -110)
	caption:SetText("Fog strength")

	local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -3)
	hint:SetText("Higher = smoother, but costs more FPS")

	-- One button per strength; the current one stays lit.
	local steps = {}
	for i = 1, MAX_STRENGTH do
		local step = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
		step:SetSize(34, 22)
		step:SetPoint("TOPLEFT", 12 + (i - 1) * 38, -140)
		step:SetText(i)
		step:SetScript("OnClick", function() SetStrength(i) end)
		steps[i] = step
	end

	local function Sync()
		syncFog()
		syncWeather()
		syncSounds()
		for i, step in ipairs(steps) do
			if i == db.strength then step:LockHighlight() else step:UnlockHighlight() end
		end
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
		GameTooltip:AddLine("Weather clearing: " .. OnOff(db.clearWeather), 1, 1, 1)
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
		if db.clearWeather == nil then db.clearWeather = true end
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
	if strength then
		db.enabled = true
		SetStrength(strength)
	elseif msg == "on" then
		SetEnabled(true)
	elseif msg == "off" then
		SetEnabled(false)
	elseif msg == "" then
		SetEnabled(not db.enabled)
	elseif msg == "weather" then
		SetWeather(not db.clearWeather)
	elseif msg == "sounds" then
		SetWeatherSounds(not db.muteWeatherSounds)
	elseif msg == "options" then
		return ToggleOptions()
	else
		return say("usage: /ch (toggle fog)  /ch on|off  /ch 1-5 (strength)  /ch weather (toggle weather)  /ch sounds (toggle weather sounds)  /ch options")
	end
	say(("fog %s, strength %d (flip every %d frame%s), weather %s, weather sounds %s"):format(db.enabled and "cleared" or "normal",
		db.strength, FramesPerFlip(), FramesPerFlip() == 1 and "" or "s", db.clearWeather and "cleared" or "normal",
		db.muteWeatherSounds and "muted" or "on"))
end
