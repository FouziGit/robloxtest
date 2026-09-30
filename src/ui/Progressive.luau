--!strict
-- Progressive: a long list built a chunk at a time (D-234). A screen that built everything it lists as it opened
-- drew 1 282 objects for a locker of forty-one cosmetics, 684 for a leaderboard's fifty rows and 510 for ten
-- equipped glyphs, where a screen is held to 400 (ThemeConfig.Budget.MaxScreenObjects, tests/ScreenBudget.spec.luau).
-- The first chunk is built at once, and more while the view at rest at the top is not full; once the view moves,
-- the next each time it comes within a window of the canvas's foot -- the player scrolling, or a pad's selection
-- that the engine scrolls to -- and UpTo builds as far as an item that must be there (the player's own row, before
-- the page scrolls to it). A list is only ever built down, in its order.

local Progressive = {}

export type Props = {
	-- The frame the list scrolls in, down.
	Scroller: ScrollingFrame,
	-- How many items there are, and how many are built at a time.
	Count: number,
	Chunk: number,
	-- Builds item `index`, in order: 1, 2, 3...
	Build: (index: number) -> (),
}

export type Progressive = {
	-- How many items are built.
	Built: (self: Progressive) -> number,
	-- Builds every item up to `index`.
	UpTo: (self: Progressive, index: number) -> (),
	-- Stops following the view; what was built stays with its owner.
	Destroy: (self: Progressive) -> (),
}

function Progressive.new(props: Props): Progressive
	local scroller = props.Scroller
	local built = 0

	local function upTo(_self: Progressive?, index: number)
		local last = math.min(index, props.Count)
		while built < last do
			built += 1
			props.Build(built)
		end
	end

	-- Within a window of the foot once the view has moved. At rest at the top, only until the view is full: the
	-- canvas is never shorter than its window, so a list that does not fill it yet is one as tall as it. Looking a
	-- window ahead from the top too built a locker's second chunk as it opened, 475 objects where a screen is held
	-- to 400 (tests/ScreenBudget.spec.luau, which lays the list out as the engine does). A view not laid out yet (no
	-- window) asks for nothing more.
	local function grow()
		if built >= props.Count then
			return
		end
		local window = scroller.AbsoluteWindowSize.Y
		if window <= 0 then
			return
		end
		local at = scroller.CanvasPosition.Y
		local ahead = if at > 0 then window else 0
		if at + window + ahead >= scroller.AbsoluteCanvasSize.Y then
			upTo(nil, built + props.Chunk)
		end
	end

	local connections = {
		scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(grow),
		scroller:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(grow),
		scroller:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(grow),
	}
	upTo(nil, props.Chunk)

	local function builtCount(_self: Progressive): number
		return built
	end

	local function destroy(_self: Progressive)
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local object: Progressive = {
		Built = builtCount,
		UpTo = upTo,
		Destroy = destroy,
	}
	return object
end

return Progressive
