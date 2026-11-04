local _, ns = ...
---@cast ns GuardianNamespace

---The adapter must supply the same token for reload and a fresh token for login.
---No live lifecycle inference is made until the Phase 1 client gate is verified.
---@param profile GuardianSettings
---@param sessionId string
---@return boolean
function ns.BeginSession(profile, sessionId)
    if not ns.ValidIdentifier(sessionId) then
        return false
    end
    profile.sessionId = sessionId
    return true
end

---@param mode 'indefinite'|'duration'|'session'
---@param context GuardianContext
---@param seconds? number
---@return GuardianGrant?
function ns.NewGrant(mode, context, seconds)
    if mode == "indefinite" then
        return { mode = mode }
    elseif mode == "session" and ns.ValidIdentifier(context.sessionId) then
        return { mode = mode, sessionId = context.sessionId }
    elseif mode == "duration" and type(seconds) == "number" and seconds > 0 then
        local grant = { mode = mode, expiresAt = context.now + seconds }
        if ns.ValidGrant(grant) then
            return grant
        end
    end
    return nil
end
