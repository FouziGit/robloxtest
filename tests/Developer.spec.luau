--!strict
-- What a developer account may do that a player may not (DeveloperConfig), held on the code that grants it.
local DeveloperConfig = require("../src/server/Config/DeveloperConfig")
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CURRENCY = "src/server/Services/CurrencyService.luau"

local function body(path: string, header: string): string
	local source = (fs.readFile(path)):gsub("%-%-[^\n]*", "")
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
end

describe("a developer's Folios", function()
	it("buy without paying, and never write an unearned balance (D-129)", function()
		expect(type(DeveloperConfig.UnlimitedFolios)).toBe("boolean")
		-- One predicate says who is waived: trySpend and the shop's record of what the waiver bought ask it.
		local waives = body(CURRENCY, "function CurrencyService.waives(")
		expect(
			waives:find(
				"return DeveloperConfig.UnlimitedFolios and DeveloperConfig.isDeveloper(player.UserId, player.Name)",
				1,
				true
			)
		).never.toBe(nil)
		local spend = body(CURRENCY, "function CurrencyService.trySpend(")
		local waiver = "if CurrencyService.waives(player) then"
		local waived = spend:find(waiver, 1, true)
		local balanceCheck = spend:find("if data.Currency.Folios < amount then", 1, true)
		expect(waived).never.toBe(nil)
		expect(balanceCheck).never.toBe(nil)
		-- Before the balance is read, so an empty purse still buys; and the branch only returns.
		expect((waived :: number) < (balanceCheck :: number)).toBe(true)
		local branch = spend:sub(waived :: number, (balanceCheck :: number) - 1)
		expect(branch:find("return true end", 1, true)).never.toBe(nil)
		expect(branch:find("Folios -=", 1, true)).toBe(nil)
		expect(branch:find("Folios +=", 1, true)).toBe(nil)
		expect(branch:find("Folios =", 1, true)).toBe(nil)
		-- A player is never waived: the grant is the developer list's, nobody else's.
		expect(DeveloperConfig.isDeveloper(123456789, "AnotherPlayer")).toBe(false)
	end)
end)
