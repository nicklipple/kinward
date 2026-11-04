# Guardian

The planned parental-control behavior is specified in
[REQUIREMENTS.md](REQUIREMENTS.md). It is not implemented by the scaffold yet.
See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for phased tasks and
acceptance criteria.

Minimal WoW: Forever addon: saved settings and `/guardian`, which prints the
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
individually. Runtime sources and `Guardian.toc` are at the repository root;
development dependencies, annotations and UI references stay outside the package. Logs and generated
reports live in ignored `.reports/`; downloads and binaries in `.tools/`.
Re-run the deliberate failure probes (temporarily edits files, always restores):

```sh
python3 scripts/verify_guardrails.py
```

The zip is `dist/Guardian-0.1.0.zip` with a single top-level `Guardian/` directory.
The development checkout currently lives at
`_retail_/Interface/AddOns/Guardian/`, as requested until Forever releases.
It is already in the client's addon discovery location; edits require only a
`/reload` (restart the client after adding the addon). The manifest still targets
Forever interface 16001; this placement does not verify Retail compatibility.

For installation elsewhere, choose the client's AddOns directory, close the
game, then run:

```sh
export WOW_ADDONS_DIR="/path/to/client/Interface/AddOns"
mkdir -p "$WOW_ADDONS_DIR"
python3 -m zipfile -e dist/Guardian-0.1.0.zip "$WOW_ADDONS_DIR"
```

This overwrites matching Guardian runtime files. No user's installation path is
hardcoded. Only the Guardian checkout is modified during development. `.pkgmeta` excludes
tests, tooling, annotations and references from CurseForge packages.

Manual smoke test in the Forever client:

1. Enable Guardian at character selection, enable errors with
   `/console scriptErrors 1`, and log in. `/dump GetBuildInfo()` should show
   1.60.1, build 70755 for this baseline, and fourth return 16001. A newer build
   needs its APIs/interface verified before updating the pinned baseline.
2. Run `/guardian`; expect `Guardian 0.1.0; initialized: true` and no Lua error.
3. Run `/run GuardianDB.enabled = false`, then `/reload`. Verify the slash output
   again and `/dump GuardianDB.enabled` returns false.
4. Log out and back in; check that false persists. Restore the default with
   `/run GuardianDB.enabled = true`, then `/reload` and verify true persists.
5. Watch for Lua errors throughout login, reload and logout. Initialization,
   actual saved-variable loading and client behavior are not proven by mocks.

Secret values, protected actions, taint and combat lockdown require real-client
testing when applicable to added features. This scaffold does not implement
combat or protected actions. No in-game verification is claimed.
