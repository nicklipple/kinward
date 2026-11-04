local _, ns = ...
---@cast ns KinwardNamespace

local function identifier(value)
    return type(value) == "string" and #value > 0 and #value <= 128
end
ns.ValidIdentifier = identifier

---@param grant unknown
---@return boolean
function ns.ValidGrant(grant)
    if type(grant) ~= "table" then
        return false
    end
    return grant.mode == "indefinite"
        or (grant.mode == "duration" and type(grant.expiresAt) == "number" and grant.expiresAt == grant.expiresAt and grant.expiresAt > 0 and grant.expiresAt < math.huge)
        or (grant.mode == "session" and identifier(grant.sessionId))
end

---@param policy unknown
---@return boolean
local function validPolicy(policy)
    if
        type(policy) ~= "table"
        or type(policy.channels) ~= "table"
        or type(policy.whispers) ~= "table"
    then
        return false
    end
    for key, permissions in pairs(policy.channels) do
        if not identifier(key) or type(permissions) ~= "table" then
            return false
        end
        for direction, grant in pairs(permissions) do
            if (direction ~= "read" and direction ~= "send") or not ns.ValidGrant(grant) then
                return false
            end
        end
    end
    for _, grant in pairs(policy.whispers) do
        if
            type(grant) ~= "table"
            or (grant.kind ~= "character" and grant.kind ~= "account")
            or not identifier(grant.target)
            or not ns.ValidGrant(grant)
        then
            return false
        end
        if grant.kind == "character" and ns.CharacterKey(grant.target) ~= grant.target then
            return false
        end
    end
    return true
end

local function validPeers(peers, limit)
    if type(peers) ~= "table" then
        return false
    end
    local count = 0
    for key, value in pairs(peers) do
        count = count + 1
        if count > limit or not identifier(key) or value ~= true then
            return false
        end
    end
    return true
end

local function validChildView(child)
    if
        child.revision ~= nil
        and (
            type(child.revision) ~= "number"
            or child.revision < 0
            or child.revision > 2147483647
            or child.revision % 1 ~= 0
        )
    then
        return false
    end
    if child.members ~= nil and not validPeers(child.members, 8) then
        return false
    end
    if child.settings ~= nil then
        if type(child.settings) ~= "table" then
            return false
        end
        local count = 0
        for key, value in pairs(child.settings) do
            count = count + 1
            if
                count > 128
                or type(key) ~= "string"
                or #key > 400
                or type(value) ~= "table"
                or (value.mode ~= "revoke" and not ns.ValidGrant(value))
                or type(value.revision) ~= "number"
                or value.revision < 0
                or value.revision > 2147483647
                or value.revision % 1 ~= 0
            then
                return false
            end
        end
    end
    return true
end

local function validFamilyState(settings)
    if
        settings.policyRevision ~= nil
        and (
            type(settings.policyRevision) ~= "number"
            or settings.policyRevision < 0
            or settings.policyRevision > 2147483647
            or settings.policyRevision % 1 ~= 0
        )
    then
        return false
    end
    if settings.familyReplay ~= nil then
        if type(settings.familyReplay) ~= "table" then
            return false
        end
        for peer, ledger in pairs(settings.familyReplay) do
            if
                not settings.guardians[peer]
                or type(ledger) ~= "table"
                or type(ledger.high) ~= "number"
                or ledger.high < 0
                or ledger.high > 2147483647
                or ledger.high % 1 ~= 0
                or type(ledger.entries) ~= "table"
            then
                return false
            end
            local count = 0
            for key, entry in pairs(ledger.entries) do
                local number = type(key) == "string" and tonumber(key)
                if
                    not number
                    or tostring(number) ~= key
                    or number < 1
                    or number % 1 ~= 0
                    or number > ledger.high
                    or number <= ledger.high - 64
                    or type(entry) ~= "table"
                    or type(entry.wire) ~= "string"
                    or #entry.wire > 2048
                    or not identifier(entry.result)
                    or (
                        entry.revision ~= nil
                        and (
                            type(entry.revision) ~= "number"
                            or entry.revision < 0
                            or entry.revision > 2147483647
                            or entry.revision % 1 ~= 0
                        )
                    )
                then
                    return false
                end
                count = count + 1
            end
            if count > 64 then
                return false
            end
        end
    end
    for _, name in ipairs({ "familySequence", "childProfiles" }) do
        if settings[name] ~= nil and type(settings[name]) ~= "table" then
            return false
        end
    end
    local count = 0
    for peer, sequence in pairs(settings.familySequence or {}) do
        if
            not identifier(peer)
            or type(sequence) ~= "number"
            or sequence < 0
            or sequence > 2147483647
            or sequence % 1 ~= 0
        then
            return false
        end
        count = count + 1
    end
    if count > 16 then
        return false
    end
    count = 0
    for peer, child in pairs(settings.childProfiles or {}) do
        if
            not identifier(peer)
            or type(child) ~= "table"
            or not identifier(child.generation)
            or not identifier(child.result)
            or not validChildView(child)
            or (child.history ~= nil and not ns.ValidHistory(child.history, child.generation))
            or not ns.ValidRequestState({
                requests = child.requests,
                generation = child.generation,
                requestPrompts = child.requestPrompts,
            })
            or (
                child.replySequence ~= nil
                and (
                    type(child.replySequence) ~= "number"
                    or child.replySequence < 1
                    or child.replySequence > 2147483647
                    or child.replySequence % 1 ~= 0
                )
            )
        then
            return false
        end
        count = count + 1
    end
    return count <= 16
end

---@param saved unknown
---@return KinwardSettings
function ns.NormalizeSettings(saved)
    -- nil and the old enabled-only scaffold are the only fresh-profile migrations.
    local settings = type(saved) == "table" and saved or {}
    local legacy = type(saved) == "table"
        and settings.schemaVersion == nil
        and settings.role == nil
        and settings.supervision == nil
        and settings.generation == nil
        and settings.guardians == nil
        and settings.children == nil
        and settings.policy == nil
        and settings.queues == nil
        and settings.sessionId == nil
        and settings.familyReplay == nil
        and settings.familySequence == nil
        and settings.childProfiles == nil
        and settings.requests == nil
        and settings.requestPrompts == nil
        and settings.requestSequence == nil
        and settings.history == nil
        and settings.pairingReceipt == nil
    local fresh = saved == nil or legacy
    if type(settings.enabled) ~= "boolean" then
        settings.enabled = true
    end
    if fresh then
        settings.schemaVersion = 1
        settings.role = "unset"
        settings.supervision = "unpaired"
        settings.generation = "initial"
        settings.guardians = {}
        settings.children = {}
        settings.policy = { channels = {}, whispers = {} }
        settings.queues = { requests = {}, delivery = {} }
    else
        local valid = settings.schemaVersion == 1
            and (settings.role == "unset" or settings.role == "guardian" or settings.role == "child")
            and (settings.supervision == "unpaired" or settings.supervision == "paired")
            and identifier(settings.generation)
            and validPeers(settings.guardians, 8)
            and validPeers(settings.children, 16)
            and validPolicy(settings.policy)
            and (settings.sessionId == nil or identifier(settings.sessionId))
            and type(settings.queues) == "table"
            and type(settings.queues.requests) == "table"
            and type(settings.queues.delivery) == "table"
            and validFamilyState(settings)
            and ns.ValidPairingReceipt(settings)
            and ns.ValidRequestState(settings)
            and (settings.history == nil or ns.ValidHistory(settings.history, settings.generation))
            and (not next(settings.requests or {}) or settings.requestSequence ~= nil)
        if valid and settings.supervision == "paired" then
            valid = settings.role == "child" and next(settings.guardians) ~= nil
        elseif valid then
            valid = next(settings.guardians) == nil
        end
        if not valid then
            -- Preserve the original data for explicit recovery; never infer unpairing.
            local damaged = saved
            if settings.supervision == "recovery" and settings.damaged ~= nil then
                damaged = settings.damaged
            end
            return {
                enabled = settings.enabled,
                schemaVersion = 1,
                role = "child",
                supervision = "recovery",
                generation = "recovery",
                guardians = {},
                children = {},
                policy = { channels = {}, whispers = {} },
                queues = { requests = {}, delivery = {} },
                damaged = damaged,
                familyReplay = {},
                familySequence = {},
                childProfiles = {},
            }
        end
    end
    settings.requests = settings.requests or {}
    if settings.requestPrompts == nil then
        settings.requestPrompts = true
    end
    settings.requestSequence = settings.requestSequence or 0
    settings.familyReplay = settings.familyReplay or {}
    settings.familySequence = settings.familySequence or {}
    settings.childProfiles = settings.childProfiles or {}
    -- Phase 2 queues store opaque, bounded work IDs only. Later phases define payloads.
    for _, name in ipairs({ "requests", "delivery" }) do
        local bounded = {}
        for index = 1, 64 do
            local value = settings.queues[name][index]
            if identifier(value) and #bounded < 64 then
                bounded[#bounded + 1] = value
            end
        end
        settings.queues[name] = bounded
    end
    return settings
end
