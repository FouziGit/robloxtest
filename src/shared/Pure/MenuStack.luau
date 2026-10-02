--!strict
-- The way a player walked through the menus to the screen in front (D-147). Pure module: no requires, no
-- Roblox globals. MenuController keeps one stack and asks it what each move does; every answer names the
-- screen that leaves and the screen that arrives, so the rules of navigation live here, under test.
--
--   open from a screen, over an open one   pushes: Back returns where the player came from
--   open from anywhere else                replaces whatever was open (the HUD, a hub prompt, a key, a
--                                          match that ends)
--   open a screen already under the top    goes back down to it, never stacks a second copy
--   open the screen already in front       does nothing
--   back                                   pops; from the first screen, closes it
--   clear                                  closes everything

-- A screen on the stack, and what it was opened with (the Shop's tab).
export type Entry = { Id: string, Args: any? }
export type Stack = { Entries: { Entry } }
-- What a move does: the screen that leaves and the screen that arrives, either of them possibly none.
export type Move = { Leave: Entry?, Arrive: Entry? }

local MenuStack = {}

function MenuStack.new(): Stack
	return { Entries = {} }
end

-- The screen in front, or nil when none is open.
function MenuStack.top(stack: Stack): Entry?
	return stack.Entries[#stack.Entries]
end

function MenuStack.depth(stack: Stack): number
	return #stack.Entries
end

-- Opens `id` with `args`. `fromScreen` says a screen asked (its OnNavigate), which stacks the new screen on
-- the one in front; anything else replaces the stack.
function MenuStack.open(stack: Stack, id: string, args: any?, fromScreen: boolean): Move
	local entries = stack.Entries
	local top = entries[#entries]
	if top ~= nil and top.Id == id then
		return {}
	end
	if fromScreen and top ~= nil then
		for index = #entries - 1, 1, -1 do
			local entry = entries[index]
			if entry.Id == id then
				for _ = #entries, index + 1, -1 do
					table.remove(entries)
				end
				if args ~= nil then
					entry.Args = args
				end
				return { Leave = top, Arrive = entry }
			end
		end
		local pushed: Entry = { Id = id, Args = args }
		table.insert(entries, pushed)
		return { Leave = top, Arrive = pushed }
	end
	local only: Entry = { Id = id, Args = args }
	stack.Entries = { only }
	return { Leave = top, Arrive = only }
end

-- One step back: the screen in front leaves, the one it was opened from comes back with its arguments. The
-- first screen has none under it and simply closes.
function MenuStack.back(stack: Stack): Move
	local entries = stack.Entries
	local top = table.remove(entries)
	if top == nil then
		return {}
	end
	return { Leave = top, Arrive = entries[#entries] }
end

-- Everything closes; only the screen in front was showing.
function MenuStack.clear(stack: Stack): Move
	local top = stack.Entries[#stack.Entries]
	stack.Entries = {}
	return { Leave = top }
end

return MenuStack
