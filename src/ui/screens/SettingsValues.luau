--!strict
-- SettingsValues: what the Settings screen sends through UpdateSettings, which is one remote -- the two
-- volumes, "Shakes and flashes" and the graphics tier -- and the two pages that edit only those: Audio and
-- Accessibility (D-147). The Graphics page stays the screen's and reaches its tier through Quality,
-- SetQuality and FollowQuality.
--
-- Values are sent automatically after a short debounce, coalesced so a single call is in flight at a time
-- and consecutive calls stay inside the remote's budget; a push adopts the profile's values unless a change
-- is still on its way. The Effects slider plays a click at its new volume once the player lets go -- after
-- the push, when the sounds really play at it. The Accessibility page also shows the three settings Roblox
-- itself asks every player about (reduced motion, text size, background transparency), which the interface
-- follows (UiPrefs) and which are changed in the Roblox menu: a toggle of ours for the same thing would be
-- a second switch that disagrees with the first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ListRow = require(script.Parent.Parent.components.ListRow)
local QualityConfig = require(Shared.Config.QualityConfig)
local Remotes = require(Shared.Remotes)
local Slider = require(script.Parent.Parent.components.Slider)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Toggle = require(script.Parent.Parent.components.Toggle)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)
local UiPrefs = require(script.Parent.Parent.UiPrefs)
local UiSound = require(script.Parent.Parent.UiSound)

export type Props = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	-- Where the pages' rows go.
	Content: ScrollingFrame,
}

export type Values = {
	BuildAudio: (self: Values, page: any) -> (),
	BuildAccessibility: (self: Values, page: any) -> (),
	-- A row of a settings page: its name (and a line under it), its control on the right. It belongs to `page`.
	Row: (self: Values, page: any, left: string, right: GuiObject, order: number, subtitle: string?) -> (),
	Quality: (self: Values) -> string,
	SetQuality: (self: Values, tier: string) -> (),
	-- The strip shows the tier the profile holds whenever it is adopted, for as long as `page` lives.
	FollowQuality: (self: Values, page: any, strip: Tabs.Tabs) -> (),
	-- The screen opens: a send whose push never came stops blocking the next, and the values follow the
	-- profile again.
	Open: (self: Values) -> (),
	Destroy: (self: Values) -> (),
}

type State = { MusicVolume: number, SfxVolume: number, CameraShake: boolean, Quality: string }

local SettingsValues = {}

local DEBOUNCE_SECONDS = 0.5
local UPDATE_SETTINGS_RATE = Remotes.Definitions.UpdateSettings.Rate
-- Minimum spacing between two UpdateSettings calls: one per refilled token, so a long tweaking session
-- never outruns the remote bucket (the registry drops a rate-limited call and the change would be lost).
local MIN_INTERVAL_SECONDS = if UPDATE_SETTINGS_RATE ~= nil and UPDATE_SETTINGS_RATE.Refill > 0
	then 1 / UPDATE_SETTINGS_RATE.Refill
	else DEBOUNCE_SECONDS
local VOLUME_STEP = 0.05
local ROW_HEIGHT = Theme.Sizes.RowHeight + Theme.Sizes.PaddingSmall
local PERCENT = 100
local TEXT_SIZE_PREFIX = "settings.textSize."

function SettingsValues.new(props: Props): Values
	local trove = Trove.new()
	local t = props.Localize.t
	-- Neutral until the profile is loaded; adopt overwrites it.
	local state: State = { MusicVolume = 1, SfxVolume = 1, CameraShake = true, Quality = QualityConfig.Default }
	local timer: thread? = nil
	local inFlight = false
	local pending = false
	local lastSentAt = 0
	-- The Effects slider was let go while its value was still on its way: the click waits for the push.
	local previewOnPush = false
	-- True while a push is adopted. Tabs.Select fires OnSelect exactly like a click, so without this the
	-- adoption of a value that came FROM the server would send it straight back.
	local adopting = false
	local music: Slider.Slider? = nil
	local sfx: Slider.Slider? = nil
	local shake: Toggle.Toggle? = nil
	local strip: Tabs.Tabs? = nil

	local function adopt()
		local data = props.ClientData.get()
		if data == nil then
			return
		end
		state.MusicVolume = data.Settings.MusicVolume
		state.SfxVolume = data.Settings.SfxVolume
		state.CameraShake = data.Settings.CameraShake
		state.Quality = if QualityConfig.isTier(data.Settings.Quality)
			then data.Settings.Quality
			else QualityConfig.Default
		adopting = true
		if strip ~= nil then
			strip:Select(state.Quality)
		end
		if music ~= nil then
			music:SetValue(state.MusicVolume)
		end
		if sfx ~= nil then
			sfx:SetValue(state.SfxVolume)
		end
		if shake ~= nil then
			shake:SetValue(state.CameraShake)
		end
		adopting = false
	end

	local function cancelTimer()
		local running = timer
		if running ~= nil then
			task.cancel(running)
			timer = nil
		end
	end
	trove:Add(cancelTimer)

	-- A send whose push has not arrived yet keeps the state pending instead of queuing a second call: the
	-- push re-arms it, so only one call is ever in flight and the last change is never dropped.
	local function send()
		if props.ClientData.get() == nil or inFlight then
			return
		end
		pending = false
		inFlight = true
		lastSentAt = os.clock()
		props.RemoteClient.fire("UpdateSettings", table.clone(state))
	end

	-- Debounces a burst of drags and keeps two sends at least one remote token apart. The timer outlives the
	-- screen's Close on purpose, so a change made just before closing is still sent.
	local function schedule()
		if adopting then
			return
		end
		pending = true
		cancelTimer()
		local delay = math.max(DEBOUNCE_SECONDS, MIN_INTERVAL_SECONDS - (os.clock() - lastSentAt))
		timer = task.delay(delay, function()
			timer = nil
			send()
		end)
	end

	trove:Connect(props.ClientData.Changed, function(section: string)
		if section ~= "*" and section ~= "Settings" then
			return
		end
		if inFlight then
			inFlight = false
			if previewOnPush and not pending then
				previewOnPush = false
				UiSound.play("UiClick")
			end
		end
		if pending then
			-- A change made while the previous send was in flight: send it now that the push landed.
			if timer == nil then
				schedule()
			end
		elseif timer == nil then
			-- Do not fight a drag in progress: the debounced send will push the latest values.
			adopt()
		end
	end)

	local function row(_self: Values?, page: any, left: string, right: GuiObject, order: number, subtitle: string?)
		local created = ListRow.new({
			Left = left,
			Right = right,
			Subtitle = subtitle,
			Height = ROW_HEIGHT,
			LayoutOrder = order,
			Parent = props.Content,
		})
		page:Add(function()
			created:Destroy()
		end)
	end

	local function percent(value: number): string
		return t("common.percent", { value = math.round(value * PERCENT) })
	end

	local function volume(value: number, onChange: (number) -> (), onRelease: ((number) -> ())?): Slider.Slider
		return Slider.new({
			Min = 0,
			Max = 1,
			Step = VOLUME_STEP,
			Value = value,
			Format = percent,
			OnChange = function(next: number)
				onChange(next)
				schedule()
			end,
			OnRelease = onRelease,
		})
	end

	local function buildAudio(_self: Values, page: any)
		local musicSlider = volume(state.MusicVolume, function(value: number)
			state.MusicVolume = value
		end)
		local sfxSlider = volume(state.SfxVolume, function(value: number)
			state.SfxVolume = value
		end, function()
			-- A click at the new volume: once the server holds it, which is when the sounds play at it.
			if pending or inFlight then
				previewOnPush = true
			else
				UiSound.play("UiClick")
			end
		end)
		for _, slider in ipairs({ musicSlider, sfxSlider }) do
			page:Add(function()
				slider:Destroy()
			end)
		end
		row(nil, page, t("settings.music"), musicSlider.Instance, 1)
		row(nil, page, t("settings.sfx"), sfxSlider.Instance, 2)
		music, sfx = musicSlider, sfxSlider
		page:Add(function()
			music, sfx = nil, nil
		end)
	end

	local function buildAccessibility(_self: Values, page: any)
		local toggle = Toggle.new({
			Value = state.CameraShake,
			OnText = t("common.on"),
			OffText = t("common.off"),
			OnChange = function(value: boolean)
				state.CameraShake = value
				schedule()
			end,
		})
		page:Add(function()
			toggle:Destroy()
		end)
		row(nil, page, t("settings.cameraShake"), toggle.Instance, 1)
		shake = toggle
		page:Add(function()
			shake = nil
		end)

		-- Roblox's own three: shown as they are, with where they are changed.
		local function value(): TextLabel
			local label = Instance.new("TextLabel")
			label.Name = "Value"
			label.BackgroundTransparency = 1
			label.AutomaticSize = Enum.AutomaticSize.X
			label.Size = UDim2.fromScale(0, 1)
			label.FontFace = Theme.Fonts.Bold
			label.TextSize = Theme.Sizes.TextButton
			label.TextColor3 = Theme.Colors.Text
			return label
		end
		local motion, size, transparency = value(), value(), value()
		local system = t("settings.systemHint")
		row(nil, page, t("settings.reducedMotion"), motion, 2, system)
		row(nil, page, t("settings.textSize"), size, 3, system)
		row(nil, page, t("settings.transparency"), transparency, 4, system)
		local function refresh()
			motion.Text = t(if UiPrefs.reducedMotion() then "common.on" else "common.off")
			size.Text = t(TEXT_SIZE_PREFIX .. UiPrefs.textSize())
			transparency.Text = percent(UiPrefs.transparency())
		end
		refresh()
		local following = UiPrefs.Changed:Connect(refresh)
		page:Add(function()
			following:Disconnect()
		end)
	end

	local function quality(_self: Values): string
		return state.Quality
	end

	local function setQuality(_self: Values, tier: string)
		state.Quality = tier
		schedule()
	end

	local function followQuality(_self: Values, page: any, next: Tabs.Tabs)
		strip = next
		page:Add(function()
			if strip == next then
				strip = nil
			end
		end)
	end

	local function open(_self: Values)
		inFlight = false
		if not pending then
			adopt()
		end
	end

	local function destroy(_self: Values)
		trove:Destroy()
	end

	return {
		BuildAudio = buildAudio,
		BuildAccessibility = buildAccessibility,
		Row = row,
		Quality = quality,
		SetQuality = setQuality,
		FollowQuality = followQuality,
		Open = open,
		Destroy = destroy,
	}
end

return SettingsValues
