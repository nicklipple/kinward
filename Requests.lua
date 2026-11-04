local _, ns = ...
---@cast ns GuardianNamespace

local states = { pending = true, approved = true, denied = true, cancelled = true, expired = true }
local function integer(value, maximum)
    return type(value) == "number" and value >= 0 and value <= maximum and value % 1 == 0
end
local function text(value, limit)
    return type(value) == "string" and #value <= limit and not value:find("%c")
end
local function scope(channel, direction, target)
    if not text(channel, 64) or channel == "" or (direction ~= "read" and direction ~= "send") then
        return false
    end
    if channel == "whisper-character" then
        return text(target, 128) and target ~= "" and ns.CharacterKey(target) == target
    elseif channel == "whisper-account" then
        return text(target, 128) and target ~= ""
    end
    return channel ~= "whisper" and target == ""
end

---@param r unknown
---@return boolean
function ns.ValidRequest(r)
    return type(r) == "table"
        and text(r.id, 128)
        and r.id ~= ""
        and ns.ValidIdentifier(r.generation)
        and scope(r.channel, r.direction, r.target)
        and text(r.reason, 160)
        and integer(r.expires, 9007199254740991)
        and r.expires > 0
        and integer(r.baseRevision, 2147483647)
        and text(r.sessionId, 128)
        and states[r.state] == true
end

---@param profile GuardianRequestState
---@return boolean
function ns.ValidRequestState(profile)
    if profile.requestPrompts ~= nil and type(profile.requestPrompts) ~= "boolean" then
        return false
    end
    if profile.requestSequence ~= nil and not integer(profile.requestSequence, 2147483647) then
        return false
    end
    if profile.requests == nil then
        return true
    end
    if type(profile.requests) ~= "table" then
        return false
    end
    local count = 0
    for id, r in pairs(profile.requests) do
        if not ns.ValidRequest(r) or id ~= r.id or r.generation ~= profile.generation then
            return false
        end
        if profile.requestSequence ~= nil then
            local suffix = r.id:match(":request:(%d+)$")
            local sequence = tonumber(suffix)
            if
                not sequence
                or sequence < 1
                or sequence > profile.requestSequence
                or tostring(sequence) ~= suffix
            then
                return false
            end
        end
        count = count + 1
    end
    return count <= 32
end

---@param profile GuardianSettings
---@param now number
function ns.ExpireRequests(profile, now)
    for _, r in pairs(profile.requests or {}) do
        if r.state == "pending" and now >= r.expires then
            r.state = "expired"
        end
    end
end

---@param profile GuardianSettings
---@param now number
---@return GuardianRequest[]
function ns.RequestRows(profile, now)
    ns.ExpireRequests(profile, now)
    local rows = {}
    for _, r in pairs(profile.requests or {}) do
        rows[#rows + 1] = r
    end
    table.sort(rows, function(a, b)
        return a.id < b.id
    end)
    return rows
end

---@param profile GuardianSettings
---@param id string Verified local identity, never user-entered authority.
---@param channel string
---@param direction 'read'|'send'
---@param target string
---@param reason string
---@param now number
---@return GuardianRequest?, string
function ns.CreateRequest(profile, id, channel, direction, target, reason, now)
    if profile.supervision ~= "paired" or profile.role ~= "child" then
        return nil, "supervision-required"
    end
    if channel == "whisper-character" then
        target = ns.CharacterKey(target) or ""
    end
    if not scope(channel, direction, target) or not text(reason, 160) then
        return nil, "invalid-request"
    end
    local rows = ns.RequestRows(profile, now)
    for _, r in ipairs(rows) do
        if
            r.state == "pending"
            and r.channel == channel
            and r.target == target
            and (r.direction == direction or channel:find("^whisper%-"))
        then
            return r, "already-pending"
        end
    end
    local discard
    if #rows >= 32 then
        for _, r in ipairs(rows) do
            if r.state ~= "pending" and (not discard or r.expires < discard.expires) then
                discard = r
            end
        end
        if not discard then
            return nil, "request-queue-full"
        end
    end
    local sequence = (profile.requestSequence or 0) + 1
    local requestId = id .. ":request:" .. sequence
    local r = {
        id = requestId,
        generation = profile.generation,
        channel = channel,
        direction = direction,
        target = target,
        reason = reason,
        expires = math.floor(now) + 86400,
        state = "pending",
        baseRevision = profile.policyRevision or 0,
        sessionId = profile.sessionId or "",
    }
    if sequence > 2147483647 or not ns.ValidRequest(r) then
        return nil, "invalid-request"
    end
    if discard then
        profile.requests[discard.id] = nil
    end
    profile.requestSequence = sequence
    profile.requests = profile.requests or {}
    profile.requests[r.id] = r
    return r, "queued-locally"
end

---@param profile GuardianSettings
---@param id string
---@param now number
---@return boolean, string
function ns.CancelRequest(profile, id, now)
    ns.ExpireRequests(profile, now)
    local r = profile.requests and profile.requests[id]
    if not r or r.state ~= "pending" then
        return false, "request-not-pending"
    end
    r.state = "cancelled"
    return true, "cancelled"
end

---Runs only behind Family's current-guardian authorization and durable replay gate.
---@param profile GuardianSettings
---@param fields string[]
---@param now number
---@param applyPolicy fun(fields: string[]): string
---@return string
function ns.ApplyRequestDecision(profile, fields, now, applyPolicy)
    if #fields ~= 11 then
        return "invalid-decision"
    end
    local deadline = tonumber(fields[11])
    if not deadline or deadline ~= deadline or deadline > now + 300 or now >= deadline then
        return "delivery-expired"
    end
    ns.ExpireRequests(profile, now)
    local r = profile.requests and profile.requests[fields[6]]
    if not r or r.generation ~= profile.generation or r.state ~= "pending" then
        return "request-not-pending"
    end
    if
        fields[7] == "deny"
        and fields[8] == ""
        and fields[9] == ""
        and fields[10] == tostring(r.baseRevision)
    then
        r.state = "denied"
        return "request-denied"
    end
    if
        fields[7] ~= "approve"
        or fields[10] ~= tostring(r.baseRevision)
        or r.baseRevision ~= (profile.policyRevision or 0)
    then
        return "request-policy-changed"
    end
    local mode, seconds = fields[8], tonumber(fields[9])
    if
        (mode == "duration" and (not integer(seconds, 86400) or seconds < 1))
        or (mode ~= "duration" and fields[9] ~= "")
    then
        return "invalid-duration"
    end
    if mode == "session" and (r.sessionId == "" or r.sessionId ~= profile.sessionId) then
        return "request-session-changed"
    end
    local grant = ns.NewGrant(
        mode,
        { now = now, sessionId = profile.sessionId or "", accounts = {} },
        seconds
    )
    if not grant then
        return "invalid-duration"
    end
    -- Reuse the existing policy mutation/revision logic, using this operation ID.
    local result = applyPolicy({
        fields[1],
        "policy",
        fields[3],
        fields[4],
        fields[5],
        r.channel,
        r.direction,
        grant.mode,
        grant.expiresAt and tostring(grant.expiresAt) or "",
        grant.sessionId or "",
        r.target,
        fields[11],
    })
    if result == "applied" then
        r.state = "approved"
    end
    return result
end

---Body-free prompt creation; never receives message text or transport claims.
---@param chat GuardianChat
---@param identity GuardianIdentity
function ns.ChatWhisperPrompt(chat, identity)
    local p, now = chat.profile, chat.context().now
    local character = ns.CharacterKey(identity.character)
    if p.supervision ~= "paired" or p.requestPrompts == false or not character then
        return
    end
    chat.promptSeen = chat.promptSeen or {}
    if now < (chat.nextPrompt or 0) or now < (chat.promptSeen[character] or 0) then
        return
    end
    local count = 0
    for key, deadline in pairs(chat.promptSeen) do
        if now >= deadline then
            chat.promptSeen[key] = nil
        else
            count = count + 1
        end
    end
    if count >= 64 then
        return
    end
    chat.promptSeen[character], chat.nextPrompt = now + 60, now + 10
    chat.prompt = { character = character, expires = now + 60, generation = p.generation }
end

---@param profile GuardianSettings
---@param fields string[]
---@param now number
---@return string?
function ns.RequestPage(profile, fields, now)
    if #fields ~= 6 then
        return nil
    end
    local cursor = tonumber(fields[6])
    if not cursor or cursor < 1 or cursor > 32 or cursor % 1 ~= 0 then
        return nil
    end
    local rows = ns.RequestRows(profile, now)
    local r = rows[cursor]
    return ns.EncodeMessage({
        "1",
        "requests",
        fields[3],
        profile.generation,
        fields[5],
        fields[6],
        (profile.requestPrompts == false and "0/" or "1/")
            .. (cursor < #rows and tostring(cursor + 1) or "done"),
        r and r.id or "",
        r and r.channel or "",
        r and r.direction or "",
        r and r.target or "",
        r and r.reason or "",
        r and tostring(r.expires) or "",
        r and r.state or "",
        r and tostring(r.baseRevision) or "",
        r and r.sessionId or "",
    })
end

---@param t GuardianTransport
---@param peer string
---@param fields string[]
---@param item GuardianDelivery
---@return boolean
function ns.AcceptRequestPage(t, peer, fields, item)
    local child = t.family.profile.childProfiles[peer]
    local requested = ns.DecodeMessage(item.wire)
    if
        #fields ~= 16
        or not child
        or child.generation ~= fields[4]
        or not requested
        or requested[6] ~= fields[6]
    then
        return false
    end
    local prompt, nextCursor = fields[7]:match("^([01])/(.+)$")
    local cursor = tonumber(fields[6])
    if not prompt or not cursor or cursor < 1 or cursor > 32 or cursor % 1 ~= 0 then
        return false
    end
    if nextCursor ~= "done" and (tonumber(nextCursor) ~= cursor + 1 or cursor >= 32) then
        return false
    end
    local r
    if fields[8] ~= "" then
        r = {
            id = fields[8],
            generation = fields[4],
            channel = fields[9],
            direction = fields[10],
            target = fields[11],
            reason = fields[12],
            expires = tonumber(fields[13]),
            state = fields[14],
            baseRevision = tonumber(fields[15]),
            sessionId = fields[16],
        }
        if not ns.ValidRequest(r) then
            return false
        end
    elseif nextCursor ~= "done" or cursor ~= 1 then
        return false
    end
    t.requestSnapshots = t.requestSnapshots or {}
    if cursor == 1 then
        t.requestSnapshots[peer] = { generation = fields[4], cursor = 1, requests = {} }
    end
    local snapshot = t.requestSnapshots[peer]
    if not snapshot or snapshot.generation ~= fields[4] or snapshot.cursor ~= cursor then
        return false
    end
    if r then
        if snapshot.requests[r.id] then
            return false
        end
        snapshot.requests[r.id] = r
    end
    t.family.outgoing[peer .. "/" .. item.operation] = nil
    if nextCursor == "done" then
        child.requests, child.requestPrompts = snapshot.requests, prompt == "1"
        t.requestSnapshots[peer] = nil
    else
        snapshot.cursor = cursor + 1
        ns.TransportRequest(t, peer, "request-list", { nextCursor }, 60)
    end
    return true
end

---@param t GuardianTransport
function ns.PollRequests(t)
    local now = t.io.now()
    if now < (t.nextRequestPoll or 0) then
        return
    end
    t.nextRequestPoll = now + 20
    for peer, child in pairs(t.family.profile.childProfiles) do
        if t.family.profile.children[peer] and child.members and child.members[t.family.id] then
            local pending = false
            for _, item in ipairs(t.work) do
                if
                    item.peer == peer
                    and item.kind == "request-list"
                    and (item.state == "pending" or item.state == "delivered")
                then
                    pending = true
                end
            end
            if not pending then
                ns.TransportRequest(t, peer, "request-list", { "1" }, 60)
            end
        end
    end
end
