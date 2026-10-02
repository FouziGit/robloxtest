--!strict
-- Breath: one value sprung back and forth for everything that idles the same way (D-147). Ten badges, or
-- five loading rows, breathe on ONE Motion.loop between them rather than one each, which is what keeps a
-- screen inside ThemeConfig.Budget.MaxIdleLoops however much it shows -- and why things that wait
-- together breathe together. The value lives in the PlayerGui (Motion only springs what is in the
-- DataModel) for as long as anything reads it, and goes with the last reader.

local Players = game:GetService("Players")

local Motion = require(script.Parent.Motion)

export type Reader = {
	Value: NumberValue,
	-- Stop reading; the last reader to leave stops the loop.
	Leave: () -> (),
}

type Shared = { Value: NumberValue, Readers: number, Stop: () -> () }

local Breath = {}

local breaths: { [string]: Shared } = {}

-- Reads the breath `name`, which springs between `from` and `to` on `preset`, resting `holdSeconds` at each
-- end. Every reader of one name shares one value; the first one's numbers are the ones it breathes by.
function Breath.join(name: string, from: number, to: number, holdSeconds: number, preset: Motion.Preset?): Reader
	local shared = breaths[name]
	if shared == nil then
		local value = Instance.new("NumberValue")
		value.Name = name .. "Breath"
		value.Value = from
		value.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local created: Shared = {
			Value = value,
			Readers = 0,
			Stop = Motion.loop(value, { Value = from }, { Value = to }, preset or "Ui", holdSeconds),
		}
		breaths[name] = created
		shared = created
	end
	local joined = shared :: Shared
	joined.Readers += 1
	local left = false
	local function leave()
		if left then
			return
		end
		left = true
		joined.Readers -= 1
		if joined.Readers > 0 then
			return
		end
		if breaths[name] == joined then
			breaths[name] = nil
		end
		joined.Stop()
		Motion.cancel(joined.Value)
		joined.Value:Destroy()
	end
	return { Value = joined.Value, Leave = leave }
end

return Breath
