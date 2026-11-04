local _, ns = ...
---@cast ns GuardianNamespace

-- Length-prefixed strings only: no executable deserialization or ambiguous escaping.
-- A transport adapter must authenticate the peer separately from these bytes.
local function atom(value)
    return type(value) == "string" and #value <= 256 and not value:find("%c")
end

---@param fields string[]
---@return string?
function ns.EncodeMessage(fields)
    if #fields < 5 or #fields > 16 then
        return nil
    end
    local parts = {}
    for _, value in ipairs(fields) do
        if not atom(value) then
            return nil
        end
        parts[#parts + 1] = #value .. ":" .. value
    end
    local wire = table.concat(parts)
    return #wire <= 2048 and wire or nil
end

---@param wire unknown
---@return string[]?, string
function ns.DecodeMessage(wire)
    if type(wire) ~= "string" or #wire > 2048 then
        return nil, "malformed"
    end
    local fields, cursor = {}, 1
    while cursor <= #wire do
        if #fields == 16 then
            return nil, "malformed"
        end
        local first, last, digits = wire:find("^(%d+):", cursor)
        if not first or #digits > 3 or (#digits > 1 and digits:sub(1, 1) == "0") then
            return nil, "malformed"
        end
        local size = tonumber(digits)
        if not size or size > 256 or last + size > #wire then
            return nil, "malformed"
        end
        local value = wire:sub(last + 1, last + size)
        if not atom(value) then
            return nil, "malformed"
        end
        fields[#fields + 1], cursor = value, last + size + 1
    end
    if #fields < 5 then
        return nil, "malformed"
    end
    if fields[1] ~= "1" then
        return nil, "unsupported-version"
    end
    if not ns.ValidIdentifier(fields[3]) or not ns.ValidIdentifier(fields[4]) then
        return nil, "malformed"
    end
    local sequence = tonumber(fields[5])
    if
        not sequence
        or sequence < 1
        or sequence > 2147483647
        or sequence % 1 ~= 0
        or tostring(sequence) ~= fields[5]
    then
        return nil, "malformed"
    end
    return fields, "decoded"
end
