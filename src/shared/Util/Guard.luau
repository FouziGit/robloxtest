--!strict
-- Guard: strict runtime validation of untrusted values (remote arguments, persisted data).
-- Pure module: no requires, no Roblox globals. Schemas are plain tables; `check` never throws.

export type Schema = {
	kind: string,
	min: number?,
	max: number?,
	integer: boolean?,
	value: any?,
	values: { any }?,
	item: Schema?,
	fields: { [string]: Schema }?,
	inner: Schema?,
	minLength: number?,
	maxLength: number?,
}

local Guard = {}

function Guard.any(): Schema
	return { kind = "any" }
end

function Guard.string(options: { min: number?, max: number? }?): Schema
	local opts: { min: number?, max: number? } = options or {}
	return { kind = "string", min = opts.min, max = opts.max or 256 }
end

function Guard.number(options: { min: number?, max: number?, integer: boolean? }?): Schema
	local opts: { min: number?, max: number?, integer: boolean? } = options or {}
	return { kind = "number", min = opts.min, max = opts.max, integer = opts.integer }
end

function Guard.boolean(): Schema
	return { kind = "boolean" }
end

function Guard.literal(value: any): Schema
	return { kind = "literal", value = value }
end

function Guard.oneOf(values: { any }): Schema
	return { kind = "oneOf", values = values }
end

-- `minLength` is unbounded by default; `maxLength` defaults to 64 so an untyped array cannot be used
-- to flood a handler.
function Guard.array(item: Schema, options: { minLength: number?, maxLength: number? }?): Schema
	local opts: { minLength: number?, maxLength: number? } = options or {}
	return { kind = "array", item = item, minLength = opts.minLength, maxLength = opts.maxLength or 64 }
end

-- Table with exactly the given fields (unknown keys rejected; optional fields may be nil).
function Guard.strict(fields: { [string]: Schema }): Schema
	return { kind = "strict", fields = fields }
end

-- Table whose values all match `item` and whose keys are strings.
function Guard.map(item: Schema, options: { maxLength: number? }?): Schema
	local opts: { maxLength: number? } = options or {}
	return { kind = "map", item = item, maxLength = opts.maxLength or 64 }
end

function Guard.optional(inner: Schema): Schema
	return { kind = "optional", inner = inner }
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function checkValue(schema: Schema, value: any, path: string): (boolean, string?)
	local kind = schema.kind

	if kind == "any" then
		return true, nil
	elseif kind == "optional" then
		if value == nil then
			return true, nil
		end
		return checkValue(schema.inner :: Schema, value, path)
	elseif kind == "string" then
		if type(value) ~= "string" then
			return false, path .. ": expected string"
		end
		if schema.min ~= nil and #value < schema.min then
			return false, path .. ": string too short"
		end
		if schema.max ~= nil and #value > schema.max then
			return false, path .. ": string too long"
		end
		return true, nil
	elseif kind == "number" then
		if not isFiniteNumber(value) then
			return false, path .. ": expected finite number"
		end
		if schema.integer and value ~= math.floor(value) then
			return false, path .. ": expected integer"
		end
		if schema.min ~= nil and value < schema.min then
			return false, path .. ": below minimum"
		end
		if schema.max ~= nil and value > schema.max then
			return false, path .. ": above maximum"
		end
		return true, nil
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then
			return false, path .. ": expected boolean"
		end
		return true, nil
	elseif kind == "literal" then
		if value ~= schema.value then
			return false, path .. ": expected literal " .. tostring(schema.value)
		end
		return true, nil
	elseif kind == "oneOf" then
		for _, allowed in ipairs(schema.values :: { any }) do
			if value == allowed then
				return true, nil
			end
		end
		return false, path .. ": value not allowed"
	elseif kind == "array" then
		if type(value) ~= "table" then
			return false, path .. ": expected array"
		end
		local count = 0
		for key in pairs(value) do
			count += 1
			if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
				return false, path .. ": non-array key"
			end
		end
		if count ~= #value then
			return false, path .. ": array has holes"
		end
		if schema.minLength ~= nil and count < schema.minLength then
			return false, path .. ": array too short"
		end
		if schema.maxLength ~= nil and count > schema.maxLength then
			return false, path .. ": array too long"
		end
		for index, item in ipairs(value) do
			local ok, err = checkValue(schema.item :: Schema, item, path .. "[" .. tostring(index) .. "]")
			if not ok then
				return false, err
			end
		end
		return true, nil
	elseif kind == "strict" then
		if type(value) ~= "table" then
			return false, path .. ": expected table"
		end
		local fields = schema.fields :: { [string]: Schema }
		for key in pairs(value) do
			if type(key) ~= "string" or fields[key] == nil then
				return false, path .. ": unexpected key " .. tostring(key)
			end
		end
		for key, fieldSchema in pairs(fields) do
			local ok, err = checkValue(fieldSchema, value[key], path .. "." .. key)
			if not ok then
				return false, err
			end
		end
		return true, nil
	elseif kind == "map" then
		if type(value) ~= "table" then
			return false, path .. ": expected map"
		end
		local count = 0
		for key, item in pairs(value) do
			count += 1
			if type(key) ~= "string" then
				return false, path .. ": non-string key"
			end
			if schema.maxLength ~= nil and count > schema.maxLength then
				return false, path .. ": map too large"
			end
			local ok, err = checkValue(schema.item :: Schema, item, path .. "." .. key)
			if not ok then
				return false, err
			end
		end
		return true, nil
	end

	return false, path .. ": unknown schema kind " .. tostring(kind)
end

-- Returns (true) or (false, reason). Never throws.
function Guard.check(schema: Schema, value: any): (boolean, string?)
	return checkValue(schema, value, "$")
end

return Guard
