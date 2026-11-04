local _, ns = ...
---@cast ns KinwardNamespace

local function once(chat, key)
    chat.captureSeen, chat.captureOrder = chat.captureSeen or {}, chat.captureOrder or {}
    if chat.captureSeen[key] then
        return false
    end
    if #chat.captureOrder == 256 then
        chat.captureSeen[table.remove(chat.captureOrder, 1)] = nil
    end
    chat.captureSeen[key] = true
    chat.captureOrder[#chat.captureOrder + 1] = key
    return true
end
local function live(chat)
    return chat.monitoring and chat.profile.supervision == "paired"
end

---@param chat KinwardChat
---@param reason string Fixed accessible description; never secret data.
---@param since? number
function ns.HistoryGap(chat, reason, since)
    if not live(chat) then
        return
    end
    local now = chat.context().now
    ns.AppendHistory(
        chat.profile,
        math.min(since or now, now),
        "system",
        "monitoring",
        nil,
        "gap",
        reason,
        now
    )
end

---@param chat KinwardChat
---@param channel string
---@param identity KinwardIdentity?
---@param body string? nil means inaccessible; the boundary never passes a secret.
---@param allowed boolean
---@param line number?
---@param gapReason? string
function ns.CaptureRead(chat, channel, identity, body, allowed, line, gapReason)
    if not live(chat) then
        return
    end
    if type(line) ~= "number" or line <= 0 or line >= math.huge then
        local now = chat.context().now
        if now >= (chat.nextCaptureGap or 0) then
            chat.nextCaptureGap = now + 10
            ns.HistoryGap(chat, "Message identity unavailable; capture skipped.")
        end
        return
    end
    if not once(chat, "read/" .. channel .. "/" .. line) then
        return
    end
    if not body then
        ns.HistoryGap(chat, gapReason or "Incoming text inaccessible; capture skipped.")
        return
    end
    ns.AppendHistory(
        chat.profile,
        chat.context().now,
        "read",
        channel,
        identity,
        allowed and "allowed" or "blocked",
        body
    )
end

---@param chat KinwardChat
---@param force? boolean
function ns.FlushHistorySends(chat, force)
    local now, keep = chat.context().now, {}
    chat.pendingCaptures, chat.recentCaptures =
        chat.pendingCaptures or {}, chat.recentCaptures or {}
    for _, pending in ipairs(chat.pendingCaptures) do
        if pending.generation == chat.profile.generation then
            if force or now >= pending.time + 2 then
                if live(chat) then
                    local record = ns.AppendHistory(
                        chat.profile,
                        pending.time,
                        "send",
                        pending.channel,
                        pending.identity,
                        "attempted",
                        pending.text
                    )
                    if record then
                        record.truncated = pending.truncated
                    end
                    chat.recentCaptures[#chat.recentCaptures + 1] = pending
                    if #chat.recentCaptures > 64 then
                        table.remove(chat.recentCaptures, 1)
                    end
                end
            else
                keep[#keep + 1] = pending
            end
        end
    end
    chat.pendingCaptures = keep
    local recent = {}
    for _, pending in ipairs(chat.recentCaptures) do
        if pending.generation == chat.profile.generation and now < pending.time + 60 then
            recent[#recent + 1] = pending
        end
    end
    chat.recentCaptures = recent
end

---@param chat KinwardChat
---@param channel string
---@param identity KinwardIdentity?
---@param body string?
---@param allowed boolean
function ns.CaptureSend(chat, channel, identity, body, allowed)
    if not live(chat) then
        return
    end
    ns.FlushHistorySends(chat)
    if not body then
        ns.HistoryGap(chat, "Outgoing text inaccessible; capture skipped.")
        return
    end
    local now = chat.context().now
    if not allowed then
        ns.AppendHistory(chat.profile, now, "send", channel, identity, "blocked-attempt", body)
    else
        if #chat.pendingCaptures >= 64 then
            ns.FlushHistorySends(chat, true)
        end
        chat.pendingCaptures[#chat.pendingCaptures + 1] = {
            generation = chat.profile.generation,
            time = now,
            channel = channel,
            identity = identity,
            text = body:sub(1, 256),
            truncated = #body > 256,
        }
    end
end

---@param chat KinwardChat
---@param channel string
---@param identity KinwardIdentity?
---@param body string?
---@param line number?
function ns.CaptureOutput(chat, channel, identity, body, line)
    if not live(chat) then
        return
    end
    if type(line) ~= "number" or line <= 0 or line >= math.huge then
        return
    end
    if not once(chat, "output/" .. channel .. "/" .. line) then
        return
    end
    if not body then
        ns.HistoryGap(chat, "Local output text inaccessible; capture skipped.")
        return
    end
    ns.FlushHistorySends(chat)
    local candidate, index, matches, old = nil, nil, 0, false
    local character = identity and identity.character or ""
    for i, pending in ipairs(chat.pendingCaptures) do
        if
            pending.channel == channel
            and (pending.identity and pending.identity.character or "") == character
            and (pending.truncated or pending.text == body)
        then
            candidate, index, matches = pending, i, matches + 1
        end
    end
    for _, pending in ipairs(chat.recentCaptures) do
        if
            pending.channel == channel
            and (pending.identity and pending.identity.character or "") == character
            and (pending.truncated or pending.text == body)
        then
            old = true
        end
    end
    if old or matches > 1 or (candidate and candidate.truncated) then
        ns.HistoryGap(chat, "Local output could not be matched to one send attempt.")
    elseif candidate then
        table.remove(chat.pendingCaptures, index)
        ns.AppendHistory(
            chat.profile,
            candidate.time,
            "send",
            channel,
            identity,
            "output",
            body,
            chat.context().now
        )
    else
        ns.AppendHistory(
            chat.profile,
            chat.context().now,
            "send",
            channel,
            identity,
            "output",
            body
        )
    end
end

---@param chat KinwardChat
---@param restricted boolean
function ns.HistoryHeartbeat(chat, restricted)
    if not live(chat) then
        return
    end
    local now = chat.context().now
    local h = chat.profile.history or ns.NewHistory(chat.profile.generation)
    chat.profile.history = h
    if not chat.captureStarted then
        if h.lastSeen > 0 then
            ns.HistoryGap(
                chat,
                "Capture restarted; any in-flight sends in the preceding interval are unconfirmed.",
                h.lastSeen
            )
        end
        if h.lastSeen == 0 then
            ns.HistoryGap(chat, "Monitoring started; preceding chat was not captured.")
        end
        chat.captureStarted = true
    end
    if restricted and not chat.restrictedSince then
        chat.restrictedSince = now
        ns.HistoryGap(chat, "Restricted chat state: capture coverage may be unavailable.")
    elseif not restricted and chat.restrictedSince then
        ns.HistoryGap(chat, "Restricted capture interval ended.", chat.restrictedSince)
        chat.restrictedSince = nil
    end
    h.lastSeen = math.floor(now)
    ns.FlushHistorySends(chat)
    ns.PruneHistory(h, now)
end
