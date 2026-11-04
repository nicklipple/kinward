local _, ns = ...
---@cast ns KinwardNamespace

---A character key always includes an explicit realm; no local-realm inference.
---@param name unknown
---@param realm? string
---@return string?
function ns.CharacterKey(name, realm)
    if type(name) ~= "string" or #name > 128 then
        return nil
    end
    if realm then
        name = name .. "-" .. realm
    end
    local character, server = name:match("^([^%s%-]+)%-(.+)$")
    if
        not character
        or character:find("[^%a\128-\255]")
        or not server
        or server:find("[^%w%s'%-\128-\255]")
    then
        return nil
    end
    server = server:gsub("[%s'%-]", "")
    if server == "" then
        return nil
    end
    return string.lower(character .. "-" .. server)
end

---@param grant KinwardGrant?
---@param context KinwardContext
---@return boolean
function ns.GrantActive(grant, context)
    if not ns.ValidGrant(grant) then
        return false
    end
    return grant.mode == "indefinite"
        or (grant.mode == "duration" and context.now < grant.expiresAt)
        or (grant.mode == "session" and context.sessionId == grant.sessionId)
end

---@param profile KinwardSettings
---@param channel string Stable channel key, never a transient channel number.
---@param direction 'read'|'send'
---@param identity KinwardIdentity?
---@param context KinwardContext Verified mappings must come from the identity adapter.
---@return boolean, string
function ns.Evaluate(profile, channel, direction, identity, context)
    if direction ~= "read" and direction ~= "send" then
        return false, "invalid-direction"
    end
    if profile.supervision == "unpaired" then
        return true, "unpaired"
    end
    if profile.supervision ~= "paired" then
        return false, "recovery-required"
    end
    if channel == "whisper" then
        local character = identity and ns.CharacterKey(identity.character)
        local account = identity and identity.account
        -- An account claim is usable only when the caller's trusted map confirms it.
        local verified = account and character and context.accounts[character] == account
        if verified and profile.guardians[account] then
            return true, "guardian"
        end
        for _, grant in pairs(profile.policy.whispers) do
            if
                ns.GrantActive(grant, context)
                and (
                    (grant.kind == "character" and character == grant.target)
                    or (grant.kind == "account" and verified and account == grant.target)
                )
            then
                return true, "whisper-grant"
            end
        end
        return false, "closed"
    end
    local permissions = profile.policy.channels[channel]
    if permissions and ns.GrantActive(permissions[direction], context) then
        return true, "channel-grant"
    end
    return false, "closed"
end

---Control bypass is for a future authenticated adapter, never arbitrary chat.
---@param profile KinwardSettings
---@param verifiedAccount string Transport-verified identity, not a payload field.
---@param generation string
---@return boolean
function ns.CanControl(profile, verifiedAccount, generation)
    return profile.supervision == "paired"
        and profile.generation == generation
        and profile.guardians[verifiedAccount] == true
end
