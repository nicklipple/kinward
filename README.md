# Kinward

The planned parental-control behavior is specified in
[REQUIREMENTS.md](REQUIREMENTS.md). The policy and simulated family-pairing foundation is implemented; live pairing
and chat enforcement are pending. The [Phase 4 transport/dashboard walkthrough](docs/PHASE4_TRANSPORT.md) documents
`/kinward ui` (visual role, child, permission and family controls) and the
isolated `/kinward demo` network demo (requires the staged development harness). Live transport activation remains
gated by unverified Phase 1 identity/routing.
See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for phased tasks and
acceptance criteria. Phase 1 source evidence, support limits and developer-only
probe instructions are in [docs/CAPABILITIES.md](docs/CAPABILITIES.md). Live-client
and two-account acceptance is still pending.

WoW: Forever addon with versioned profiles, a pure policy engine and an isolated
[command-driven simulator](docs/PHASE2_SIMULATOR.md). `/kinward` prints the
version and whether initialization completed. Target source: **1.60.1.70755**,
interface **16001** (confirm the running client with `/dump GetBuildInfo()`).
See [ARCHITECTURE.md](ARCHITECTURE.md) for pins, evidence and verification limits.

Requires Linux x86_64 (or WSL), Python 3.12+, curl, make and a C compiler.
Bootstrap downloads checksum-verified dependencies and builds Lua 5.1.5 locally;
no globally installed LuaLS, StyLua, LuaRocks or editor extension is required.
From this project's directory:

```sh
make bootstrap
make format
make check
make package
```

`make lint`, `make test`, `make manifest` and `make format-check` can be run
individually. Runtime sources and `Kinward.toc` are at the repository root;
development dependencies, annotations and UI references stay outside the package. Logs and generated
reports live in ignored `.reports/`; downloads and binaries in `.tools/`.
Re-run the deliberate failure probes (temporarily edits files, always restores):

```sh
python3 scripts/verify_guardrails.py
```

If the development simulator is staged, remove it before packaging:

```sh
make unstage-simulator
make package
```

`make stage-simulator` enables it again for `/kinward demo`. Staging copies the
simulator from `scripts/probes/` to the addon root and adds its TOC load entry;
unstaging removes that copy and entry, keeping the source. Unstaging is safe to
repeat and refuses to remove a copy with local edits. Reload WoW after changing
staging to update the loaded simulator hooks and slash commands.

The zip is `dist/Kinward-0.1.0.zip` with a single top-level `Kinward/` directory.
The development checkout currently lives at
`_retail_/Interface/AddOns/Kinward/`, as requested until Forever releases.
It is already in the client's addon discovery location; edits require only a
`/reload` (restart the client after adding the addon). The shared manifest lists Forever interface 16001 and Retail interface 120105
(the latter reported by the user from build 70783). This enables loading for
Retail development; runtime behavior remains unverified on both clients.

For installation elsewhere, choose the client's AddOns directory, close the
game, then run:

```sh
export WOW_ADDONS_DIR="/path/to/client/Interface/AddOns"
mkdir -p "$WOW_ADDONS_DIR"
python3 -m zipfile -e dist/Kinward-0.1.0.zip "$WOW_ADDONS_DIR"
```

This overwrites matching Kinward runtime files. No user's installation path is
hardcoded. Only the Kinward checkout is modified during development. `.pkgmeta` excludes
tests, tooling, annotations and references from CurseForge packages.

Manual smoke test in the Forever client:

1. Enable Kinward at character selection, enable errors with
   `/console scriptErrors 1`, and log in. `/dump GetBuildInfo()` should show
   1.60.1, build 70755 for this baseline, and fourth return 16001. A newer build
   needs its APIs/interface verified before updating the pinned baseline.
2. Run `/kinward`; expect `Kinward 0.1.0; initialized: true` and no Lua error.
3. Run `/run KinwardDB.enabled = false`, then `/reload`. Verify the slash output
   again and `/dump KinwardDB.enabled` returns false.
4. Log out and back in; check that false persists. Restore the default with
   `/run KinwardDB.enabled = true`, then `/reload` and verify true persists.
5. Watch for Lua errors throughout login, reload and logout. Initialization,
   actual saved-variable loading and client behavior are not proven by mocks.

Secret values, protected actions, taint and combat lockdown require real-client
testing when applicable to added features. This scaffold does not implement
combat or protected actions. No in-game verification is claimed.


Phase 5 adds candidate ordinary whisper/party chat boundaries and isolated
network-to-chat scenarios. Live enforcement remains inactive pending the Phase 1
and Phase 4 client gates. See [Phase 5 scope and checklists](docs/PHASE5_CHAT.md)
for simulator commands, source evidence and uncovered routes.


Phase 6 adds a **Requests** tab for child requests and guardian approvals:
indefinite, until logout, 15 minutes or 45 minutes. **Connection** retains delivery
diagnostics; chat histories remain Phase 7. [Request contracts and the isolated
demo](docs/PHASE6_REQUESTS.md) cover offline requests, sender-only whisper prompts,
expiry and cancellation. Live transport/enforcement and client privacy acceptance
remain gated; the staged demo shares production logic with fixture data only.


Phase 7 implements the guardian **Activity** browser for captured child chat,
with per-child/channel/time/conversation/outcome filters and bounded reconnect
catchup. **Connection** stays separate for diagnostics. Development retention
defaults are seven days/10,000 rows; blocked bodies stay out of child/debug views.
[History scope, privacy and demo](docs/PHASE7_HISTORY.md) document the candidate
capture surfaces and limitations. Live activation, real-client coverage/privacy
and two-account delivery are still unverified; demo history is synthetic only.


Pairing is now **child requests by guardian name → guardian clicks Accept child**.
There are no manual code/operation fields. A second guardian still needs approval
from an existing guardian, also through buttons. See [pairing walkthrough](docs/PAIRING.md).
The simulator is left enabled in this development checkout; reload and use
`/kinward demo`, enter `parent` on child, then accept on parent. Live routing and
identity remain gated; this demonstration uses isolated fixtures.


Click the shield button at the minimap's lower-left edge to open Kinward.
It opens the same local dashboard as `/kinward ui`; the Single-session demo
button inside the dashboard remains available when the development simulator is
staged. Reload after updating to see the minimap launcher.

## Rename from Guardian

The addon and installation directory are now **Kinward**. Use `/kinward ui`
to open it, `/kinward demo` for the staged demo, and `/kinwardsim` for
development simulator commands. Restart WoW after renaming the folder so the
client discovers `Kinward/Kinward.toc`.

Kinward uses its own `KinwardDB` saved variable and `Kinward4` addon-message
prefix. It starts with fresh settings; existing Guardian save files are left
untouched. The guardian/child role names and permission semantics are unchanged.

## GitHub Releases

Push a version tag such as `v0.1.0-alpha2` after the release workflow has reached
GitHub. The **Kinward release** action bootstraps pinned tools, runs the package
checks, and publishes a GitHub Release with the installable
`Kinward-0.1.0-alpha2.zip` attached. It stamps the packaged TOC version from the
tag without changing the committed source version. Tags with a prerelease
suffix (including alpha, beta and rc) become GitHub prereleases; plain version
tags become normal releases. The workflow uses GitHub's built-in token and needs
no additional secret.

For an existing tag created before the workflow was added, open **Actions →
Kinward release → Run workflow**, select `main`, and enter the existing tag
(for example `v0.1.0-alpha1`). The build checks out that exact tag. A tag must
exist remotely; the action never creates or moves tags. Creating a release that
already exists fails rather than replacing published files.

Download the attached `Kinward-*.zip` to install the addon. GitHub's automatic
**Source code** archives contain the repository and are intended for development.
CurseForge packaging continues separately through its repository webhook.

## Consenting two-account tests

Live adapters are inactive by default. For the explicit Retail test procedure,
including right-click player selection, run `/kinward test start` on both
accounts after choosing Child/Guardian roles. See [pairing test instructions](docs/PAIRING.md#right-click-selection-and-explicit-retail-live-tests).
Use `/kinward test status` for status and `/kinward test stop` followed by reload
to stop. This test mode covers candidate ordinary whispers/party only and does
not establish production enforcement or complete chat coverage.
