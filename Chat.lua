local _, ns = ...
---@cast ns KinwardNamespace

---No message bodies enter this module. The adapter supplies accessible metadata.
---@param profile KinwardSettings
---@param context fun(): KinwardContext
---@return KinwardChat
function ns.NewChat(profile, context)
    return {
        profile = profile,
        context = context,
        seen = {},
        order = {},
        decisions = 0,
        blockedReads = 0,
        blockedSends = 0,
        attemptedSends = 0,
        observedOutputs = 0,
    }
end

---@param chat KinwardChat
---@param channel string
---@param direction 'read'|'send'
---@param identity? KinwardIdentity
---@param line? number Accessible positive event line ID, never text-derived.
---@return boolean, string
function ns.ChatDecision(chat, channel, direction, identity, line)
    local key
    if direction == "read" and type(line) == "number" and line > 0 and line < math.huge then
        key = channel .. ":" .. tostring(line)
        local cached = chat.seen[key]
        if cached then
            return cached.allowed, cached.reason
        end
    end
    local allowed, reason = ns.Evaluate(chat.profile, channel, direction, identity, chat.context())
    -- Without a usable line ID evaluate display, but do not claim once-only capture.
    if direction == "send" or key then
        chat.decisions = chat.decisions + 1
        if direction == "send" then
            if allowed then
                chat.attemptedSends = chat.attemptedSends + 1
            else
                chat.blockedSends = chat.blockedSends + 1
            end
        elseif not allowed then
            chat.blockedReads = chat.blockedReads + 1
        end
    end
    if not allowed and direction == "read" and channel == "whisper" and key and identity then
        ns.ChatWhisperPrompt(chat, identity)
    end
    if key then
        if #chat.order == 256 then
            chat.seen[table.remove(chat.order, 1)] = nil
        end
        chat.order[#chat.order + 1] = key
        chat.seen[key] = { allowed = allowed, reason = reason }
    end
    return allowed, reason
end
