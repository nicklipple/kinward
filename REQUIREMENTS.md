# Guardian product requirements

Agreed requirements from the parent/child workflow discussion. This document
specifies intended behavior, not functionality already implemented. The current
runtime includes the Phase 2 profile/policy foundation; live enforcement remains
pending.

## Scope and trust

Guardian supports cooperative children. It cannot prevent disabling the addon,
editing/deleting saved data or communicating outside the supported game UI.
Parent and child use separate WoW accounts. Development currently takes place
in `_retail_/Interface/AddOns/Guardian/`; the target remains Forever. Verify
behavior in the available client without assuming the two clients are identical.
Mail, group-finder text and other non-chat player-written text are out of scope.

## Profiles and pairing

- Child policy and pairing use account-level SavedVariables. All existing and
  new characters on that WoW account inherit the local profile.
- Do not depend on automatic settings synchronization between computers.
  Export/import is a proposed convenience, not a prerequisite for version one.
- Guardians and children must be Battle.net friends. Verify usable identity and
  alt discovery in-client; friendship alone is not authorization to control a
  child or read their history.
- Pair with a short code and explicit confirmation. Before pairing completes,
  Guardian imposes no restrictions. After pairing, permissions default closed
  except the necessary guardian communication and control path.
- One guardian can supervise multiple children. A child can have multiple
  guardians; adding another requires approval from an existing guardian.
- Either guardian can edit policy or remove another guardian after confirmation.
  Removing the last requires an explicit stop-supervision confirmation: unpaired
  profiles are unrestricted.
- Deleting saved data permits a fresh pairing. Old guardians must not silently
  regain access to a newly paired profile.

## Chat permissions

- Separate read and send permissions for say, yell, emotes, party, instance,
  raid, guild, officer, public/custom channels, communities and supported
  Battle.net chat. Disable voice access where feasible; no voice recording or
  transcription is required.
- Allowing a channel allows everyone in that channel, within that channel only.
  Party membership never implicitly grants whisper permission.
- Whisper permission is bidirectional and applies across the child's alts.
  Support explicit character approval and Battle.net-friend approval where the
  client reliably establishes identity. Unresolved identities remain blocked.
  Never infer account ownership from a character name or an untrusted claim.
- Cover default chat, separate whisper windows and speech bubbles where feasible.
  Prefer shared filtering paths to support chat addons such as ElvUI; actual
  coverage and outbound enforcement require client verification.
- Do not claim universal interception or enforcement before it is demonstrated.

## Requests and expiry

- Children can request channel access, whisper permission or a temporary
  exception, with a reason. Guardians approve or deny requests.
- For a blocked incoming whisper, show the sender's character name, hide the
  message body, and offer a request to read/send whispers with that character.
- Guardians can configure whether stranger-whisper prompts appear. Suppress
  duplicate prompts and rate-limit them as a proposed default.
- Permission duration supports indefinite, until logout, or an explicit time
  period such as 15 or 45 minutes. Session grants survive UI reloads; timed
  grants continue expiring while offline. No conversation-based expiry.
- Whether granting permission reveals previously blocked messages is undecided;
  do not automatically replay old blocked content without resolving this.

## Synchronization and supervision

- Enforce the last approved policy while guardians are offline or monitoring is
  unavailable. Queue requests locally for delivery when communication resumes.
- Track pending, delivered and applied/acknowledged states; do not show a queued
  guardian edit as already enforced.
- Conflicting edits use last-write-wins per setting, ordered by application on
  the child, rather than relying on synchronized guardian clocks.
- Guardians can monitor incoming messages, outgoing messages, blocked incoming
  messages and intercepted blocked-send attempts, where accessible. Distinguish
  attempts from successfully sent messages.
- Queue history locally for later guardian delivery. Bound retention and queue
  size, report missing/expired history and monitoring gaps. Seven days and
  10,000 records per child are proposed configurable defaults, not settled limits.
- The child should visibly know chat is monitored (proposed UI default).
- Presence reports responding, last seen or unreachable. An unreachable addon
  does not establish whether the child is offline, disconnected or has disabled it.
- Secret values, messaging lockdown, protected actions and taint may limit
  filtering, identity resolution, monitoring and delivery. Do not attempt to
  bypass client restrictions; communicate limitations accurately.

## Development verification

Provide a single-client development simulator with isolated parent/child
profiles, using the same policy and protocol logic as production and a simulated
transport. Never alter live pairing or policy through simulator actions.
Exercise pairing, extra guardians, requests, expiry, conflicting edits, duplicate
and delayed messages, reconnects, monitoring gaps and bounded history.
Actual delivery, Battle.net identity/alt discovery, chat coverage, outgoing
blocking, bubbles, voice control and UI integration still require real-client
tests, including two logged-in accounts for cross-player behavior.
