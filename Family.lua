local _, ns = ...
---@cast ns GuardianNamespace

local function copyGrant(fields)
    local grant = { mode = fields[8], expiresAt = tonumber(fields[9]), sessionId = fields[10] }
    if grant.mode == "indefinite" then
        if fields[9] ~= "" or fields[10] ~= "" then
            return nil
        end
    elseif grant.mode == "duration" then
        if fields[10] ~= "" then
            return nil
        end
    elseif grant.mode == "session" then
        if fields[9] ~= "" then
            return nil
        end
    end
    return ns.ValidGrant(grant) and grant or nil
end

---@param profile GuardianSettings
---@param id string Verified local account identity.
---@param freshToken fun(): string Globally fresh across resets, data deletion and installations.
---@return GuardianFamily
function ns.NewFamily(profile, id, freshToken)
    return { profile = profile, id = id, freshToken = freshToken, attempts = 0, outgoing = {} }
end

local function clearWork(endpoint)
    endpoint.invite, endpoint.pending = nil, nil
    endpoint.outgoing = {}
    endpoint.profile.queues = { requests = {}, delivery = {} }
    endpoint.profile.familyReplay = {}
    endpoint.proposal, endpoint.guardianInbox = nil, {}
    endpoint.profile.pairingReceipt = nil
    endpoint.profile.requests = {}
    ns.HistoryRelationshipChanged(endpoint.profile)
end

local function rotate(endpoint)
    local token = endpoint.freshToken()
    if
        not ns.ValidIdentifier(token)
        or token == endpoint.profile.generation
        or token == "initial"
    then
        return nil
    end
    return token
end

---@param endpoint GuardianFamily
---@param peer string Intended transport identity, confirmed in the child UI.
---@param code string Adapter supplies a fresh unpredictable code; simulator uses explicit fixtures.
---@param now number
---@return boolean
function ns.FamilyInvite(endpoint, peer, code, now)
    if endpoint.profile.supervision == "recovery" or endpoint.profile.role ~= "child" then
        return false
    end
    if
        not ns.ValidIdentifier(peer)
        or type(code) ~= "string"
        or not code:match("^%d%d%d%d%d%d%d%d$")
    then
        return false
    end
    -- Replacing an invitation does not reset the endpoint-wide failed-attempt budget.
    if endpoint.attempts >= 5 then
        return false
    end
    endpoint.invite = { peer = peer, code = code, expires = now + 120 }
    endpoint.pending = nil
    return true
end

---@param endpoint GuardianFamily
---@param peer string
---@param generation string
---@return boolean
function ns.FamilyCanDeliver(endpoint, peer, generation)
    return ns.CanControl(endpoint.profile, peer, generation)
end

---@param endpoint GuardianFamily
---@param peer string
---@param operation string Exact pending pairing operation, never just a code.
---@param now number
---@param friends table<string, boolean>
---@param confirmed boolean Local child confirmation; additional guardians use authenticated approval.
---@return boolean, string
function ns.FamilyConfirm(endpoint, peer, operation, confirmed, now, friends)
    local pending = endpoint.pending
    if not confirmed or not pending or pending.peer ~= peer or pending.operation ~= operation then
        return false, "confirmation-required"
    end
    if now >= pending.expires or not friends[peer] then
        endpoint.pending = nil
        return false, "pairing-expired"
    end
    if endpoint.profile.supervision ~= "unpaired" then
        return false, "guardian-approval-required"
    end
    local generation = rotate(endpoint)
    if not generation then
        return false, "generation-unavailable"
    end
    endpoint.profile.guardians = { [peer] = true }
    endpoint.profile.policy = { channels = {}, whispers = {} }
    endpoint.profile.supervision, endpoint.profile.generation = "paired", generation
    clearWork(endpoint)
    return true, "paired"
end

---@param endpoint GuardianFamily
---@param confirmed boolean Explicit stop-supervision/recovery confirmation.
---@return boolean, string
function ns.FamilyReset(endpoint, confirmed)
    if not confirmed then
        return false, "confirmation-required"
    end
    local generation = rotate(endpoint)
    if not generation then
        return false, "generation-unavailable"
    end
    endpoint.profile.guardians = {}
    endpoint.profile.policy = { channels = {}, whispers = {} }
    endpoint.profile.supervision, endpoint.profile.generation = "unpaired", generation
    endpoint.profile.damaged = nil
    clearWork(endpoint)
    return true, "stopped"
end

-- Persisted sliding replay window. Old sequence numbers remain rejected after
-- cache eviction/reload. Up to 64 reordered operations are accepted once each.
local function replay(endpoint, peer, fields, wire)
    local ledgers = endpoint.profile.familyReplay
    local ledger = ledgers[peer]
    if not ledger then
        ledger = { high = 0, entries = {} }
        ledgers[peer] = ledger
    end
    local sequence = tonumber(fields[5])
    if sequence <= ledger.high - 64 then
        return nil, "replay-too-old"
    end
    local previous = ledger.entries[fields[5]]
    if previous then
        return nil, previous.wire == wire and previous.result or "operation-collision"
    end
    -- IDs are scoped by sender/generation and must equal the sequence's canonical ID.
    if fields[3] ~= peer .. ":" .. fields[5] then
        return nil, "invalid-operation"
    end
    ledger.high = math.max(ledger.high, sequence)
    for key in pairs(ledger.entries) do
        if tonumber(key) <= ledger.high - 64 then
            ledger.entries[key] = nil
        end
    end
    return ledger, nil
end

local function apply(endpoint, fields, now, friends)
    local p, kind = endpoint.profile, fields[2]
    if kind == "history-config" and #fields == 8 then
        local deadline = tonumber(fields[8])
        if not deadline or deadline ~= deadline or deadline > now + 300 or now >= deadline then
            return "delivery-expired"
        end
        local retention, count = tonumber(fields[6]), tonumber(fields[7])
        if not retention or not count then
            return "invalid-history-limits"
        end
        return ns.ConfigureHistory(p, retention, count, now) and "applied"
            or "invalid-history-limits"
    elseif kind == "request-decision" then
        return ns.ApplyRequestDecision(p, fields, now, function(policyFields)
            return apply(endpoint, policyFields, now, friends)
        end)
    elseif kind == "request-prompts" and #fields == 7 then
        local deadline = tonumber(fields[7])
        if not deadline or deadline ~= deadline or deadline > now + 300 or now >= deadline then
            return "delivery-expired"
        end
        if fields[6] ~= "true" and fields[6] ~= "false" then
            return "invalid-prompts"
        end
        p.requestPrompts = fields[6] == "true"
        return "applied"
    elseif kind == "policy" and (#fields == 11 or #fields == 12) then
        if (p.policyRevision or 0) >= 2147483647 then
            return "revision-limit"
        end
        -- Phase 4 sends an absolute delivery deadline; legacy simulator calls remain supported.
        if #fields == 12 then
            local deadline = tonumber(fields[12])
            if not deadline or deadline ~= deadline or deadline > now + 300 or now >= deadline then
                return "delivery-expired"
            end
        end
        local channel, direction = fields[6], fields[7]
        if not ns.ValidIdentifier(channel) or (direction ~= "read" and direction ~= "send") then
            return "invalid-policy"
        end
        local grant = copyGrant(fields)
        local revoke = fields[8] == "revoke" and fields[9] == "" and fields[10] == ""
        if not grant and not revoke then
            return "invalid-policy"
        end
        if channel == "whisper-character" or channel == "whisper-account" then
            local target = fields[11]
            if not ns.ValidIdentifier(target) then
                return "invalid-policy"
            end
            local identityKind = channel == "whisper-character" and "character" or "account"
            local normalized = target
            if identityKind == "character" then
                normalized = ns.CharacterKey(target)
            end
            if not normalized then
                return "invalid-policy"
            end
            if grant then
                grant.kind, grant.target = identityKind, normalized
            end
            p.policy.whispers[channel .. ":" .. normalized] = grant
        elseif fields[11] == "" then
            p.policy.channels[channel] = p.policy.channels[channel] or {}
            p.policy.channels[channel][direction] = grant
        else
            return "invalid-policy"
        end
        p.policyRevision = (p.policyRevision or 0) + 1
        return "applied"
    elseif kind == "history" and #fields == 5 then
        -- Phase 7 supplies bounded records; no content is returned in this phase.
        return "history-authorized"
    elseif kind == "add" and #fields == 8 then
        local pending = endpoint.pending
        if
            fields[8] ~= "confirm"
            or not pending
            or pending.peer ~= fields[6]
            or pending.operation ~= fields[7]
        then
            return "confirmation-required"
        end
        if now >= pending.expires or not friends[pending.peer] then
            return "pairing-expired"
        end
        local count = 0
        for _ in pairs(p.guardians) do
            count = count + 1
        end
        if count >= 8 or p.guardians[pending.peer] then
            return "guardian-limit"
        end
        local generation = rotate(endpoint)
        if not generation then
            return "generation-unavailable"
        end
        local proposal = endpoint.proposal
        p.guardians[pending.peer] = true
        p.generation = generation
        clearWork(endpoint)
        if proposal and proposal.peer == pending.peer and proposal.token == pending.operation then
            ns.StorePairingReceipt(endpoint, proposal)
        end
        return "guardian-added"
    elseif kind == "remove" and #fields == 7 then
        local target = fields[6]
        if not p.guardians[target] then
            return "unknown-guardian"
        end
        local count = 0
        for _ in pairs(p.guardians) do
            count = count + 1
        end
        if count == 1 then
            if fields[7] ~= "stop" then
                return "stop-confirmation-required"
            end
            local _, result = ns.FamilyReset(endpoint, true)
            return result
        end
        if fields[7] ~= "confirm" then
            return "confirmation-required"
        end
        local generation = rotate(endpoint)
        if not generation then
            return "generation-unavailable"
        end
        p.guardians[target], p.generation = nil, generation
        clearWork(endpoint)
        return "guardian-removed"
    end
    return "unsupported-operation"
end

---@param endpoint GuardianFamily
---@param peer string Transport-reported verified identity. Never extracted from payload.
---@param wire unknown
---@param now number
---@param friends table<string, boolean> Trusted friendship lookup from adapter.
---@return boolean, string, string? Acknowledgement bytes contain no history or policy content.
function ns.FamilyReceive(endpoint, peer, wire, now, friends)
    local fields, reason = ns.DecodeMessage(wire)
    if not fields or not ns.ValidIdentifier(peer) then
        return false, reason
    end
    if fields[3] ~= peer .. ":" .. fields[5] then
        return false, "invalid-operation"
    end
    local p, kind = endpoint.profile, fields[2]
    if kind == "guardian-request" or kind == "guardian-accept" or kind == "guardian-decline" then
        return ns.ReceiveGuardianship(endpoint, peer, fields, now, friends)
    end
    if kind == "pair" then
        if
            #fields ~= 6
            or fields[4] ~= "pairing"
            or p.role ~= "child"
            or p.supervision == "recovery"
        then
            return false, "invalid-pairing"
        end
        local pending = endpoint.pending
        if
            pending
            and pending.peer == peer
            and pending.wire == wire
            and now < pending.expires
            and friends[peer]
        then
            return true,
                "confirmation-required",
                ns.EncodeMessage({
                    "1",
                    "ack",
                    fields[3],
                    fields[4],
                    fields[5],
                    "confirmation-required",
                })
        end
        local invite = endpoint.invite
        if not invite or now >= invite.expires or endpoint.attempts >= 5 then
            return false, "pairing-unavailable"
        end
        endpoint.attempts = endpoint.attempts + 1
        if
            not friends[peer]
            or invite.peer ~= peer
            or invite.code ~= fields[6]
            or fields[3] ~= peer .. ":" .. fields[5]
        then
            return false, "pairing-rejected"
        end
        endpoint.pending =
            { peer = peer, operation = fields[3], expires = invite.expires, wire = wire }
        endpoint.invite = nil -- Single use even before explicit confirmation.
        local ack = ns.EncodeMessage({
            "1",
            "ack",
            fields[3],
            fields[4],
            fields[5],
            "confirmation-required",
        })
        return true, "confirmation-required", ack
    end
    if kind == "sync" and #fields == 5 and p.supervision == "paired" and p.guardians[peer] then
        local values = {
            "1",
            "state",
            fields[3],
            p.generation,
            fields[5],
            "paired",
            tostring(p.policyRevision or 0),
        }
        for guardian in pairs(p.guardians) do
            values[#values + 1] = guardian
        end
        local state = ns.EncodeMessage(values)
        return true, "state", state
    end
    if not ns.FamilyCanDeliver(endpoint, peer, fields[4]) then
        return false, "unauthorized"
    end
    if kind == "pairing-pending" and #fields == 5 then
        local proposal = endpoint.proposal
        local pending = proposal
            and proposal.state == "awaiting-approval"
            and now < proposal.expires
            and friends[proposal.peer]
        return true,
            "pairing-candidate",
            ns.EncodeMessage({
                "1",
                "pairing-candidate",
                fields[3],
                p.generation,
                fields[5],
                pending and proposal and proposal.peer or "",
                pending and proposal and proposal.token or "",
                pending and proposal and tostring(proposal.expires) or "0",
            })
    end
    if kind == "history" and #fields == 6 then
        local batch = ns.HistoryBatch(p, fields, now)
        return batch ~= nil, batch and "history-batch" or "invalid-history-cursor", batch
    end
    if kind == "request-list" then
        local page = ns.RequestPage(p, fields, now)
        return page ~= nil, page and "requests" or "invalid-cursor", page
    end
    if kind == "snapshot" and #fields == 7 then
        local cursor, revision = tonumber(fields[6]), tostring(p.policyRevision or 0)
        if not cursor or cursor < 1 or cursor > 128 or cursor % 1 ~= 0 then
            return false, "invalid-cursor"
        end
        if cursor > 1 and fields[7] ~= revision then
            return false, "snapshot-changed"
        end
        local entries = {}
        for channel, permissions in pairs(p.policy.channels) do
            for direction, grant in pairs(permissions) do
                entries[#entries + 1] = {
                    key = channel .. "/" .. direction,
                    channel = channel,
                    direction = direction,
                    target = "",
                    grant = grant,
                }
            end
        end
        for _, grant in pairs(p.policy.whispers) do
            local channel = "whisper-" .. grant.kind
            entries[#entries + 1] = {
                key = channel .. "/" .. grant.target,
                channel = channel,
                direction = "read",
                target = grant.target,
                grant = grant,
            }
        end
        table.sort(entries, function(a, b)
            return a.key < b.key
        end)
        local entry = entries[cursor]
        local grant = entry and entry.grant
        local nextCursor = cursor < #entries
                and (cursor < 128 and tostring(cursor + 1) or "truncated")
            or "done"
        return true,
            "snapshot",
            ns.EncodeMessage({
                "1",
                "snapshot",
                fields[3],
                p.generation,
                fields[5],
                revision,
                tostring(cursor),
                nextCursor,
                entry and entry.channel or "",
                entry and entry.direction or "",
                entry and entry.target or "",
                grant and grant.mode or "revoke",
                grant and grant.expiresAt and tostring(grant.expiresAt) or "",
                grant and grant.sessionId or "",
            })
    end
    if kind == "inspect" and #fields == 8 then
        local channel, direction, target = fields[6], fields[7], fields[8]
        if not ns.ValidIdentifier(channel) or (direction ~= "read" and direction ~= "send") then
            return false, "invalid-policy"
        end
        local grant
        if channel == "whisper-character" or channel == "whisper-account" then
            local normalized = channel == "whisper-character" and ns.CharacterKey(target) or target
            if not normalized or normalized == "" then
                return false, "invalid-policy"
            end
            grant = p.policy.whispers[channel .. ":" .. normalized]
        elseif target == "" then
            grant = p.policy.channels[channel] and p.policy.channels[channel][direction]
        else
            return false, "invalid-policy"
        end
        return true,
            "setting",
            ns.EncodeMessage({
                "1",
                "setting",
                fields[3],
                p.generation,
                fields[5],
                channel,
                direction,
                target,
                grant and grant.mode or "revoke",
                grant and grant.expiresAt and tostring(grant.expiresAt) or "",
                grant and grant.sessionId or "",
                tostring(p.policyRevision or 0),
            })
    end
    local ledger, previous = replay(endpoint, peer, fields, wire)
    local result = previous or "invalid-operation"
    if ledger then
        result = apply(endpoint, fields, now, friends)
        ledger.entries[fields[5]] =
            { wire = wire, result = result, revision = p.policyRevision or 0 }
    end
    local entry = p.familyReplay[peer] and p.familyReplay[peer].entries[fields[5]]
    local ack = ns.EncodeMessage({
        "1",
        "ack",
        fields[3],
        fields[4],
        fields[5],
        result,
        tostring(entry and entry.revision or p.policyRevision or 0),
    })
    return result == "applied"
        or result == "history-authorized"
        or result == "guardian-added"
        or result == "guardian-removed"
        or result == "stopped"
        or result == "request-denied",
        result,
        ack
end

---@param endpoint GuardianFamily
---@param peer string
---@param generation string
---@param kind string
---@param arguments string[]
---@return string?
function ns.FamilyRequest(endpoint, peer, generation, kind, arguments)
    if
        (
            endpoint.profile.role ~= "guardian"
            and not (endpoint.profile.role == "child" and kind == "guardian-request")
        ) or not ns.ValidIdentifier(peer)
    then
        return nil
    end
    if kind == "pair" then
        generation = "pairing" -- Bootstrap cannot require knowledge of a previous relationship.
    end
    local sequences = endpoint.profile.familySequence
    local count, pending = 0, 0
    for _ in pairs(sequences) do
        count = count + 1
    end
    for _ in pairs(endpoint.outgoing) do
        pending = pending + 1
    end
    if (not sequences[peer] and count >= 16) or pending >= 64 then
        return nil
    end
    local sequence = (sequences[peer] or 0) + 1
    local fields = { "1", kind, endpoint.id .. ":" .. sequence, generation, tostring(sequence) }
    for _, value in ipairs(arguments) do
        fields[#fields + 1] = value
    end
    local wire = ns.EncodeMessage(fields)
    if not wire or sequence > 2147483647 then
        return nil
    end
    sequences[peer] = sequence
    endpoint.outgoing[peer .. "/" .. fields[3]] =
        { kind = kind, generation = generation, sequence = fields[5] }
    return wire
end

---@param endpoint GuardianFamily
---@param peer string Verified child identity from transport.
---@param wire unknown
---@return boolean, string
function ns.FamilyReply(endpoint, peer, wire)
    local fields, reason = ns.DecodeMessage(wire)
    if
        not fields
        or (
            #fields ~= 6
            and not (fields[2] == "ack" and #fields == 7)
            and not (fields[2] == "state" and #fields >= 7 and #fields <= 15)
        )
    then
        return false, reason
    end
    local key = peer .. "/" .. fields[3]
    local pending = endpoint.outgoing[key]
    if not pending or fields[5] ~= pending.sequence then
        return false, "unsolicited-reply"
    end
    local child = endpoint.profile.childProfiles[peer]
    local sequence = tonumber(fields[5])
    if child and child.replySequence and sequence <= child.replySequence then
        endpoint.outgoing[key] = nil
        return false, "stale-reply"
    end
    if
        fields[2] == "state"
        and (pending.kind == "sync" or pending.kind == "guardian-accept")
        and fields[6] == "paired"
    then
        endpoint.profile.children[peer] = true
        local record = child and child.generation == fields[4] and child or {}
        record.generation, record.result, record.replySequence = fields[4], "paired", sequence
        endpoint.profile.childProfiles[peer] = record
    elseif
        fields[2] == "ack"
        and fields[4] == pending.generation
        and ns.ValidIdentifier(fields[6])
    then
        if child and pending.kind ~= "pair" then
            if child.generation ~= fields[4] then
                endpoint.outgoing[key] = nil
                return false, "stale-reply"
            end
            child.result, child.replySequence = fields[6], sequence
        end
    else
        return false, "invalid-reply"
    end
    endpoint.outgoing[key] = nil
    return true, fields[6]
end
