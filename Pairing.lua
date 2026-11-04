local _, ns = ...
---@cast ns KinwardNamespace

local function state(endpoint, fields)
    local p = endpoint.profile
    local values = {
        "1",
        "state",
        fields[3],
        p.generation,
        fields[5],
        "paired",
        tostring(p.policyRevision or 0),
    }
    for peer in pairs(p.guardians) do
        values[#values + 1] = peer
    end
    return ns.EncodeMessage(values)
end
local function ack(fields, result)
    return ns.EncodeMessage({ "1", "ack", fields[3], fields[4], fields[5], result })
end

---@param profile KinwardSettings
---@return boolean
function ns.ValidPairingReceipt(profile)
    local r = profile.pairingReceipt
    return r == nil
        or (
            type(r) == "table"
            and profile.supervision == "paired"
            and profile.guardians[r.peer] == true
            and r.generation == profile.generation
            and ns.ValidIdentifier(r.token)
            and ns.ValidIdentifier(r.requestGeneration)
            and type(r.sequence) == "string"
            and tonumber(r.sequence) ~= nil
            and tonumber(r.sequence) >= 1
            and tonumber(r.sequence) <= 2147483647
            and tostring(tonumber(r.sequence)) == r.sequence
            and r.operation == r.peer .. ":" .. r.sequence
            and type(r.expires) == "number"
            and r.expires > 0
            and r.expires < math.huge
        )
end

---@param endpoint KinwardFamily
---@param proposal? KinwardPairingProposal
function ns.StorePairingReceipt(endpoint, proposal)
    if
        proposal
        and proposal.operation
        and proposal.sequence
        and endpoint.profile.guardians[proposal.peer]
    then
        endpoint.profile.pairingReceipt = {
            peer = proposal.peer,
            token = proposal.token,
            requestGeneration = proposal.generation,
            generation = endpoint.profile.generation,
            operation = proposal.operation,
            sequence = proposal.sequence,
            expires = proposal.expires,
        }
    end
end

---@param t KinwardTransport
---@param name string
---@return string?
function ns.ResolveGuardianPeer(t, name)
    local peer
    if t.io.findPeer then
        peer = t.io.findPeer(name)
    else
        for candidate in pairs(t.io.friends()) do
            if candidate:lower() == name:lower() then
                if peer and peer ~= candidate then
                    return nil
                end
                peer = candidate
            end
        end
    end
    return peer
end

---@param t KinwardTransport
---@param name string
---@param expectedPeer? string
---@return boolean, string
function ns.RequestGuardianship(t, name, expectedPeer)
    local f, now = t.family, t.io.now()
    if f.profile.role ~= "child" or f.profile.supervision == "recovery" then
        return false, "Choose the child role before requesting guardianship."
    end
    local peer = ns.ResolveGuardianPeer(t, name)
    if expectedPeer and peer ~= expectedPeer then
        return false,
            "That name now identifies a different account. Review the guardian and send again."
    end
    if not peer or peer == f.id or not t.io.friends()[peer] then
        return false,
            "Guardian not found. Use a verified friend's character name, Name-Realm or BattleTag."
    end
    if f.profile.guardians[peer] then
        return false, "That guardian already supervises you."
    end
    if
        f.proposal
        and (f.proposal.state == "pending" or f.proposal.state == "awaiting-approval")
        and now < f.proposal.expires
    then
        return false, "A request is already waiting. Cancel it before choosing another guardian."
    end
    local token = f.freshToken()
    if
        not ns.ValidIdentifier(token)
        or token == f.profile.generation
        or token == "initial"
        or (f.proposal and token == f.proposal.token)
    then
        return false, "A fresh pairing request is unavailable."
    end
    local proposal = {
        peer = peer,
        token = token,
        generation = f.profile.generation,
        expires = math.floor(now) + 120,
        state = "pending",
    }
    local previous = f.proposal
    f.proposal = proposal
    local item =
        ns.TransportRequest(t, peer, "guardian-request", { token, tostring(proposal.expires) }, 120)
    if not item then
        f.proposal = previous
        return false, "Could not queue the request. Try again."
    end
    return true,
        "Guardianship requested from "
            .. peer
            .. ". They can accept in Family; requests expire after two minutes."
end

---@param t KinwardTransport
---@param peer string
---@param token string Exact rendered request; never read from an input field.
---@param accept boolean
---@return boolean, string
function ns.AnswerGuardianship(t, peer, token, accept)
    local r = t.family.guardianInbox and t.family.guardianInbox[peer]
    if
        t.family.profile.role ~= "guardian"
        or not r
        or r.token ~= token
        or r.state ~= "pending"
        or t.io.now() >= r.expires
    then
        return false, "This guardianship request is no longer available."
    end
    if not t.io.friends()[peer] then
        return false, "The requesting account could not be verified."
    end
    local kind = accept and "guardian-accept" or "guardian-decline"
    local item = ns.TransportRequest(
        t,
        peer,
        kind,
        { token, tostring(r.expires) },
        math.min(60, r.expires - t.io.now())
    )
    if not item then
        return false, "Could not queue your answer. Try again."
    end
    r.state = accept and "accepting" or "declining"
    return true, accept and "Acceptance sent. Waiting for the child to apply it." or "Decline sent."
end

---@param endpoint KinwardFamily
---@param peer string
---@param fields string[]
---@param now number
---@param friends table<string, boolean>
---@return boolean, string, string?
function ns.ReceiveGuardianship(endpoint, peer, fields, now, friends)
    local p, kind = endpoint.profile, fields[2]
    local expires = tonumber(fields[7])
    if
        #fields ~= 7
        or not friends[peer]
        or not ns.ValidIdentifier(fields[6])
        or not expires
        or expires ~= expires
        or now >= expires
        or expires > now + 120
    then
        return false, "pairing-expired"
    end
    if kind == "guardian-request" then
        if p.role ~= "guardian" or peer == endpoint.id then
            return false, "guardian-role-required"
        end
        endpoint.guardianInbox = endpoint.guardianInbox or {}
        local previous = endpoint.guardianInbox[peer]
        if previous and tonumber(fields[5]) <= tonumber(previous.sequence) then
            if
                fields[5] ~= previous.sequence
                or fields[6] ~= previous.token
                or fields[4] ~= previous.generation
                or expires ~= previous.expires
            then
                return false, "stale-pairing-request"
            end
            return true, "request-received", ack(fields, "request-received")
        end
        local count = 0
        for key, r in pairs(endpoint.guardianInbox) do
            if now >= r.expires then
                endpoint.guardianInbox[key] = nil
            else
                count = count + 1
            end
        end
        if not previous and count >= 16 then
            return false, "pairing-inbox-full"
        end
        endpoint.guardianInbox[peer] = {
            peer = peer,
            token = fields[6],
            generation = fields[4],
            expires = expires,
            sequence = fields[5],
            state = "pending",
        }
        return true, "request-received", ack(fields, "request-received")
    end
    if p.role ~= "child" or p.supervision == "recovery" then
        return false, "child-role-required"
    end
    local receipt = p.pairingReceipt
    if
        kind == "guardian-accept"
        and receipt
        and receipt.peer == peer
        and receipt.token == fields[6]
        and receipt.requestGeneration == fields[4]
        and receipt.operation == fields[3]
        and receipt.sequence == fields[5]
        and receipt.generation == p.generation
        and p.guardians[peer]
        and receipt.expires == expires
    then
        return true, "paired", state(endpoint, fields)
    end
    local proposal = endpoint.proposal
    if
        not proposal
        or proposal.peer ~= peer
        or proposal.token ~= fields[6]
        or proposal.generation ~= fields[4]
        or proposal.generation ~= p.generation
        or proposal.expires ~= expires
        or now >= proposal.expires
    then
        return false, "unsolicited-acceptance"
    end
    if kind == "guardian-decline" and proposal.state == "declined" then
        return true, "declined", ack(fields, "declined")
    end
    if proposal.state ~= "pending" and proposal.state ~= "awaiting-approval" then
        return false, "request-not-pending"
    end
    if kind == "guardian-decline" then
        proposal.state = "declined"
        endpoint.pending = nil
        return true, "declined", ack(fields, "declined")
    end
    proposal.operation, proposal.sequence = fields[3], fields[5]
    endpoint.pending = {
        peer = peer,
        operation = proposal.token,
        expires = proposal.expires,
        wire = ns.EncodeMessage(fields) or "",
    }
    if p.supervision == "paired" then
        proposal.state = "awaiting-approval"
        return true, "guardian-approval-required", ack(fields, "guardian-approval-required")
    end
    -- Clicking Request already confirmed the child's exact intended guardian.
    local ok, result = ns.FamilyConfirm(endpoint, peer, proposal.token, true, now, friends)
    if not ok then
        return false, result, ack(fields, result)
    end
    ns.StorePairingReceipt(endpoint, proposal)
    return true, "paired", state(endpoint, fields)
end

---@param t KinwardTransport
---@param peer string
---@param fields string[]
---@param item KinwardDelivery
---@return boolean
function ns.AcceptGuardianCandidate(t, peer, fields, item)
    local child = t.family.profile.childProfiles[peer]
    if
        #fields ~= 8
        or not child
        or child.generation ~= fields[4]
        or item.kind ~= "pairing-pending"
    then
        return false
    end
    local expires = tonumber(fields[8])
    if not expires or expires ~= expires or expires > t.io.now() + 120 then
        return false
    end
    if
        fields[6] ~= ""
        and (
            not ns.ValidIdentifier(fields[6])
            or not ns.ValidIdentifier(fields[7])
            or expires <= t.io.now()
        )
    then
        return false
    end
    t.guardianCandidates = t.guardianCandidates or {}
    t.nextCandidatePoll = t.nextCandidatePoll or {}
    t.nextCandidatePoll[peer] = t.io.now() + (fields[6] ~= "" and 5 or 30)
    t.guardianCandidates[peer] = fields[6] ~= ""
            and { peer = fields[6], token = fields[7], generation = fields[4], expires = expires }
        or nil
    t.family.outgoing[peer .. "/" .. item.operation] = nil
    return true
end

---@param t KinwardTransport
function ns.TickGuardianship(t)
    local now, f = t.io.now(), t.family
    if f.proposal and now >= f.proposal.expires then
        f.proposal.state = "expired"
        f.pending = nil
    end
    if now < (t.nextPairingPoll or 0) then
        return
    end
    t.nextPairingPoll = now + 5
    for peer, r in pairs(f.guardianInbox or {}) do
        if now >= r.expires then
            r.state = "expired"
        elseif
            (r.state == "accepting" or r.state == "awaiting-approval") and t.io.friends()[peer]
        then
            local pending = false
            for _, item in ipairs(t.work) do
                if
                    item.peer == peer
                    and (item.kind == "sync" or item.kind == "guardian-accept")
                    and (item.state == "pending" or item.state == "delivered")
                then
                    pending = true
                end
            end
            if not pending then
                ns.TransportRequest(t, peer, "sync", {}, math.min(30, r.expires - now))
            end
        end
    end
    if not t.pairingPolling then
        return
    end
    for peer, child in pairs(f.profile.childProfiles) do
        if
            f.profile.children[peer]
            and child.members
            and child.members[f.id]
            and now >= (t.nextCandidatePoll and t.nextCandidatePoll[peer] or 0)
        then
            local pending = false
            for _, item in ipairs(t.work) do
                if
                    item.peer == peer
                    and item.kind == "pairing-pending"
                    and (item.state == "pending" or item.state == "delivered")
                then
                    pending = true
                end
            end
            if not pending then
                ns.TransportRequest(t, peer, "pairing-pending", {}, 30)
            end
        end
    end
end

---@param t KinwardTransport
---@param item KinwardDelivery
---@return boolean
function ns.PairingWorkValid(t, item)
    if item.reply then
        return true
    end
    local f = t.family
    if item.kind == "guardian-request" then
        local r, fields = f.proposal, ns.DecodeMessage(item.wire)
        return r ~= nil
            and fields ~= nil
            and r.state == "pending"
            and r.peer == item.peer
            and r.token == fields[6]
            and r.generation == f.profile.generation
            and t.io.now() < r.expires
    elseif item.kind == "guardian-accept" or item.kind == "guardian-decline" then
        local r = f.guardianInbox and f.guardianInbox[item.peer]
        local fields = ns.DecodeMessage(item.wire)
        return r ~= nil
            and fields ~= nil
            and r.token == fields[6]
            and r.generation == item.generation
            and t.io.now() < r.expires
            and (r.state == "accepting" or r.state == "declining" or r.state == "awaiting-approval")
    end
    return true
end
