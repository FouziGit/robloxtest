--!strict
-- Banner: the centre splashes of a match, on their own layer under every menu (D-147, Theme.Layers.Banner).
-- A match found, each digit of a round's count, the fight called, a round won or lost: big words in the title
-- face, in the sheet on a hard ink stroke, tipped a little, on a splat and a brush swash. One at a time: a new
-- one waits for the one on screen, except a digit, which gives way to the next at once. A splash slams in from
-- larger than itself with the pop's overshoot -- a lost round drops in without one, since sad things are
-- heavy -- holds, and leaves smaller and fading. Nothing appears, nothing vanishes (docs/ART_BIBLE.md rule 3).
--
-- The player's own takedown is a small cyan sticker in the top half, off the centre, which never covers the
-- fight. While a match is announced, an ink plate under the centre names who the player faces, with their level and
-- their rank (E10-S7), and leaves when the fight is called. While a boss's attack is telegraphed the splashes wait, and one kept waiting more than two seconds is
-- not worth saying any more. A fight surface: cyan for us, ink, the sheet; no value colour (rule 11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local ScreenRoot = require(script.Parent.ScreenRoot)
local Splat = require(script.Parent.Splat)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Kind = "MatchFound" | "Countdown" | "Fight" | "RoundWon" | "RoundLost"
export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Localize: Localizer,
	Parent: Instance?,
}

export type Banner = {
	-- A splash of `kind`; a countdown's carries its digit.
	Show: (self: Banner, kind: Kind, digit: number?) -> (),
	-- The player took an opponent out.
	Pop: (self: Banner) -> (),
	-- While a boss's warning is up nothing new shows; what waited too long is dropped once it is down.
	Suppress: (self: Banner, suppressed: boolean) -> (),
	-- Who the player faces, a line each (with a first line for a quick duel), until the fight is called; nil hides it.
	ShowVersus: (self: Banner, lines: { string }?) -> (),
	-- The match is over: what waits is dropped and what shows leaves, the versus plate with it.
	Clear: (self: Banner) -> (),
	Destroy: (self: Banner) -> (),
}

type Look = {
	Key: string,
	Tint: string,
	Swash: string?,
	Ring: boolean?,
	Size: number,
	-- The whole life of the splash, in, hold and out; nil for a digit, which stays until the next.
	Seconds: number?,
	-- In with no overshoot.
	Heavy: boolean?,
}

type Entry = { Kind: Kind, Digit: number?, At: number }

type Pop = { Holder: Frame, Scale: UIScale, Sticker: Sticker.Sticker, Gone: boolean }

type Shown = {
	Kind: Kind,
	Holder: Frame,
	Scale: UIScale,
	-- The ring the fight is called with, which bursts out once.
	Ring: ImageLabel?,
	Fade: (transparency: number, preset: Motion.Preset?) -> (),
	Leaving: boolean,
}

local Banner = {}

local LOOKS: { [Kind]: Look } = {
	MatchFound = {
		Key = "hud.splash.matchFound",
		Tint = "Ally",
		Swash = "PanelRaised",
		Size = Theme.Sizes.TextHero,
		Seconds = 1.0,
	},
	Countdown = { Key = "match.countdown", Tint = "Plate", Size = Theme.Sizes.TextMega },
	Fight = {
		Key = "hud.splash.fight",
		Tint = "Ally",
		Swash = "PanelRaised",
		Ring = true,
		Size = Theme.Sizes.TextDisplay,
		Seconds = 0.8,
	},
	RoundWon = { Key = "match.roundWon", Tint = "Ally", Swash = "Ally", Size = Theme.Sizes.TextDisplay, Seconds = 1.2 },
	RoundLost = {
		Key = "match.roundLost",
		Tint = "Plate",
		Swash = "Chalk",
		Size = Theme.Sizes.TextDisplay,
		Seconds = 1.2,
		Heavy = true,
	},
}

local TILT = -4
-- A digit tips one way, the next the other.
local DIGIT_TILT = 6
local STROKE = 6
local ENTER_SCALE = 1.6
local EXIT_SCALE = 0.95
-- How long a leaving splash takes, from the start of its exit to its settling (the UiExit spring).
local EXIT_SECONDS = 0.36
-- The splat is this much larger than the words it backs; a word is about this wide per character.
local SPLAT_SCALE = 1.6
local CHARACTER_WIDTH = 0.55
local SWASH_HEIGHT = 0.3
local RING_SCALE = 1.4
local RING_FROM = 0.6
local RING_TO = 1.6
local RING_TRANSPARENCY = 0.2
-- Kept waiting by a boss's warning longer than this, a splash is dropped.
local SUPPRESS_DROP_SECONDS = 2
-- The takedown pop: where it stands, how large its words are.
local POP_POSITION = UDim2.fromScale(0.62, 0.35)
local POP_TEXT = 26
local POP_PADDING = 12
local POP_ENTER = 1.6
-- The versus plate: under the centre, clear of the digits and the fight's word, its lines at a readable size.
local VERSUS_POSITION = UDim2.fromScale(0.5, 0.72)
local VERSUS_TEXT = 22
local VERSUS_PADDING = 12
local VERSUS_ENTER = 0.85

function Banner.new(props: Props): Banner
	local trove = Trove.new()
	local localize = props.Localize
	local queue: { Entry } = {}
	local current: Shown? = nil
	local suppressed = false
	local lastPop: Pop? = nil
	local versus: Pop? = nil

	local root = ScreenRoot.new({ Name = "Banner", DisplayOrder = Theme.Layers.Banner, Parent = props.Parent })
	trove:Add(function()
		root:Destroy()
	end)
	local stage = root.Content

	local pump: () -> ()

	-- Builds a splash's words, splat, swash and ring, and the function that fades them all together.
	local function build(entry: Entry): Shown
		local look = LOOKS[entry.Kind]
		local holder = Instance.new("Frame")
		holder.Name = entry.Kind
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.new()
		local scale = Instance.new("UIScale")
		scale.Parent = holder

		local text = localize.t(look.Key, if entry.Digit ~= nil then { seconds = entry.Digit } else nil)
		local width = math.max(look.Size, (utf8.len(text) or #text) * look.Size * CHARACTER_WIDTH)
		local splatSide = SPLAT_SCALE * width
		local splat = Splat.new({
			Size = UDim2.fromOffset(splatSide, splatSide),
			Tint = Theme.color(look.Tint),
			Rotation = Splat.rotation(if entry.Digit ~= nil then entry.Digit else 1),
			ZIndex = 1,
			Name = "Splat",
			Parent = holder,
		})

		local swash: ImageLabel? = nil
		local swashTint = look.Swash
		local swashId = if swashTint ~= nil then Theme.texture("BrushStroke") else ""
		if swashTint ~= nil and swashId ~= "" then
			local image = Instance.new("ImageLabel")
			image.Name = "Swash"
			image.BackgroundTransparency = 1
			image.Image = swashId
			image.ImageColor3 = Theme.color(swashTint)
			image.AnchorPoint = Vector2.new(0.5, 0)
			image.Position = UDim2.fromOffset(0, look.Size * 0.35)
			image.Size = UDim2.fromOffset(width * 1.1, look.Size * SWASH_HEIGHT)
			image.ZIndex = 2
			image.Parent = holder
			swash = image
		end

		local ring: ImageLabel? = nil
		local ringId = if look.Ring then Theme.texture("ShockwaveRing") else ""
		if ringId ~= "" then
			local image = Instance.new("ImageLabel")
			image.Name = "Ring"
			image.BackgroundTransparency = 1
			image.Image = ringId
			image.ImageColor3 = Theme.Colors.PanelRaised
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Size = UDim2.fromOffset(width * RING_SCALE, width * RING_SCALE)
			image.ImageTransparency = 1
			image.ZIndex = 2
			local burst = Instance.new("UIScale")
			burst.Parent = image
			image.Parent = holder
			ring = image
		end

		local words = Instance.new("TextLabel")
		words.Name = "Words"
		words.BackgroundTransparency = 1
		words.AnchorPoint = Vector2.new(0.5, 0.5)
		words.Size = UDim2.fromOffset(width, look.Size)
		words.FontFace = Theme.Fonts.Title
		words.TextSize = look.Size
		words.TextColor3 = Theme.Colors.PanelRaised
		words.Text = text
		words.ZIndex = 3
		words.Rotation = if entry.Digit ~= nil then (if entry.Digit % 2 == 0 then DIGIT_TILT else -DIGIT_TILT) else TILT
		local stroke = Theme.stroke(words, "Outline", STROKE, "Contextual")
		words.Parent = holder

		local function fade(transparency: number, preset: Motion.Preset?)
			local function apply(instance: Instance, goals: { [string]: any })
				if preset == nil then
					Motion.set(instance, goals)
				else
					Motion.to(instance, goals, preset)
				end
			end
			apply(words, { TextTransparency = transparency })
			apply(stroke, { Transparency = transparency })
			if splat ~= nil then
				Splat.fade(splat, transparency, preset)
			end
			if swash ~= nil then
				apply(swash, { ImageTransparency = transparency })
			end
		end

		holder.Parent = stage
		return { Kind = entry.Kind, Holder = holder, Scale = scale, Ring = ring, Fade = fade, Leaving = false }
	end

	local function leave(shown: Shown)
		if shown.Leaving then
			return
		end
		shown.Leaving = true
		if current == shown then
			current = nil
		end
		shown.Fade(1, "UiExit")
		Motion.to(shown.Scale, { Scale = EXIT_SCALE }, "UiExit", function()
			shown.Holder:Destroy()
		end)
		task.delay(EXIT_SECONDS, pump)
	end

	local function present(entry: Entry)
		local shown = build(entry)
		current = shown
		local look = LOOKS[entry.Kind]
		shown.Fade(1)
		shown.Fade(0, "Ui")
		if look.Heavy then
			-- Sad things are heavy: it drops into place with no bounce.
			Motion.set(shown.Scale, { Scale = ENTER_SCALE })
			Motion.to(shown.Scale, { Scale = 1 }, "UiExit")
		else
			Motion.set(shown.Scale, { Scale = ENTER_SCALE })
			Motion.to(shown.Scale, { Scale = 1 }, "UiPop")
		end
		-- The fight is called with a ring slammed out of the words, once.
		local ring = shown.Ring
		local burst = if ring ~= nil then ring:FindFirstChildOfClass("UIScale") else nil
		if ring ~= nil and burst ~= nil then
			Motion.set(ring, { ImageTransparency = RING_TRANSPARENCY })
			Motion.set(burst, { Scale = RING_FROM })
			Motion.to(ring, { ImageTransparency = 1 }, "Ui")
			Motion.to(burst, { Scale = RING_TO }, "Ui")
		end
		local seconds = look.Seconds
		if seconds ~= nil then
			task.delay(math.max(0, seconds - EXIT_SECONDS), function()
				leave(shown)
			end)
		end
	end

	pump = function()
		if suppressed then
			return
		end
		local shown = current
		if shown ~= nil and shown.Kind == "Countdown" and #queue > 0 then
			-- A digit stays only until something follows it.
			leave(shown)
		end
		if current ~= nil or #queue == 0 then
			return
		end
		present(table.remove(queue, 1) :: Entry)
	end

	local function show(_self: Banner, kind: Kind, digit: number?)
		table.insert(queue, { Kind = kind, Digit = digit, At = os.clock() })
		pump()
	end

	local function dismiss(taken: Pop)
		if taken.Gone then
			return
		end
		taken.Gone = true
		if lastPop == taken then
			lastPop = nil
		end
		Motion.to(taken.Scale, { Scale = 0 }, "UiExit", function()
			taken.Sticker:Destroy()
			taken.Holder:Destroy()
		end)
	end

	local function pop(_self: Banner)
		-- An older pop still up leaves as the new one lands.
		local previous = lastPop
		if previous ~= nil then
			dismiss(previous)
		end
		local holder = Instance.new("Frame")
		holder.Name = "Takedown"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = POP_POSITION
		holder.Size = UDim2.fromOffset(0, POP_TEXT + POP_PADDING * 2)
		holder.AutomaticSize = Enum.AutomaticSize.X
		local sticker = Sticker.new({
			Kind = "Card",
			Fill = Theme.Colors.Ally,
			Corner = Theme.Pill,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
			Name = "Sticker",
		})
		local words = Instance.new("TextLabel")
		words.Name = "Words"
		words.BackgroundTransparency = 1
		words.AutomaticSize = Enum.AutomaticSize.X
		words.Size = UDim2.fromScale(0, 1)
		words.FontFace = Theme.Fonts.Title
		words.TextSize = POP_TEXT
		words.TextColor3 = Theme.inkOn(Theme.Colors.Ally)
		words.Text = localize.t("hud.splash.defeated")
		words.ZIndex = 3
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, POP_PADDING)
		padding.PaddingRight = UDim.new(0, POP_PADDING)
		padding.Parent = words
		words.Parent = holder
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		holder.Parent = stage
		local taken: Pop = { Holder = holder, Scale = scale, Sticker = sticker, Gone = false }
		lastPop = taken
		Motion.set(scale, { Scale = POP_ENTER })
		Motion.to(scale, { Scale = 1 }, "UiPop")
		task.delay(math.max(0, Theme.Timing.KillPopSeconds - EXIT_SECONDS), dismiss, taken)
	end

	-- The plate that names the opponents: the Encre vive plate, sized to its lines (Sticker's Host, D-170), that grows
	-- into place and leaves the way the takedown pop does.
	local function showVersus(_self: Banner, lines: { string }?)
		local previous = versus
		if previous ~= nil then
			versus = nil
			dismiss(previous)
		end
		if lines == nil or #lines == 0 then
			return
		end
		local holder = Instance.new("Frame")
		holder.Name = "Versus"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = VERSUS_POSITION
		holder.Size = UDim2.new()
		holder.AutomaticSize = Enum.AutomaticSize.XY
		local sticker = Sticker.new({
			Kind = "Plate",
			Fill = Theme.Colors.Plate,
			Corner = UDim.new(0, Theme.Sizes.CornerCard),
			Host = holder,
		})
		local words = Instance.new("TextLabel")
		words.Name = "Words"
		words.BackgroundTransparency = 1
		words.AutomaticSize = Enum.AutomaticSize.XY
		words.Size = UDim2.new()
		words.FontFace = Theme.Fonts.Bold
		words.TextSize = VERSUS_TEXT
		words.TextColor3 = Theme.Colors.TextInverse
		words.Text = table.concat(lines, "\n")
		words.ZIndex = 3
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, VERSUS_PADDING)
		padding.PaddingRight = UDim.new(0, VERSUS_PADDING)
		padding.PaddingTop = UDim.new(0, VERSUS_PADDING)
		padding.PaddingBottom = UDim.new(0, VERSUS_PADDING)
		padding.Parent = words
		words.Parent = holder
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		holder.Parent = stage
		versus = { Holder = holder, Scale = scale, Sticker = sticker, Gone = false }
		Motion.set(scale, { Scale = VERSUS_ENTER })
		Motion.to(scale, { Scale = 1 }, "UiPop")
	end

	local function suppress(_self: Banner, next: boolean)
		suppressed = next
		if next then
			return
		end
		-- What waited too long for the warning to go is not worth saying any more.
		local now = os.clock()
		for index = #queue, 1, -1 do
			if now - queue[index].At > SUPPRESS_DROP_SECONDS then
				table.remove(queue, index)
			end
		end
		pump()
	end

	local function clear(self: Banner)
		table.clear(queue)
		local shown = current
		if shown ~= nil then
			leave(shown)
		end
		showVersus(self, nil)
	end

	local function destroy(_self: Banner)
		table.clear(queue)
		trove:Destroy()
	end

	local object: Banner = {
		Show = show,
		Pop = pop,
		ShowVersus = showVersus,
		Suppress = suppress,
		Clear = clear,
		Destroy = destroy,
	}
	return object
end

return Banner
