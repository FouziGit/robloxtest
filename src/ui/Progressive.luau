--!strict
-- Progressive: a long list built a chunk at a time (D-XXX). A screen that built everything it lists as it opened
-- drew 1 282 objects for a locker of forty-one cosmetics, 684 for a leaderboard's fifty rows and 510 for ten
-- equipped glyphs, where a screen is held to 400 (ThemeConfig.Budget.MaxScreenObjects, tests/ScreenBudget.spec.luau).
-- The first chunk is built at once; the next each time the view comes within a window of the canvas's foot -- the
-- player scrolling, or a pad's selection that the engine scrolls to -- and UpTo builds as far as an item that must
-- be there (the player's own row, before the page scrolls to it). A list is only ever built down, in its order.

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

	-- Within a window of the foot: a view not laid out yet (no window) asks for nothing more.
	local function grow()
		if built >= props.Count then
			return
		end
		local window = scroller.AbsoluteWindowSize.Y
		if window <= 0 then
			return
		end
		if scroller.CanvasPosition.Y + window * 2 >= scroller.AbsoluteCanvasSize.Y then
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
