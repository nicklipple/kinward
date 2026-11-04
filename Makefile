.PHONY: bootstrap format format-check lint manifest test check package
bootstrap:
	python3 scripts/bootstrap.py
format:
	.tools/stylua/stylua Core.lua Settings.lua Profile.lua Policy.lua Session.lua Protocol.lua Family.lua Transport.lua WoWTransport.lua Dashboard.lua tests scripts/probes types/addon.lua
format-check:
	.tools/stylua/stylua --check Core.lua Settings.lua Profile.lua Policy.lua Session.lua Protocol.lua Family.lua Transport.lua WoWTransport.lua Dashboard.lua tests scripts/probes types/addon.lua
lint:
	python3 scripts/lint.py
manifest:
	python3 scripts/manifest.py
test:
	.tools/lua/src/lua tests/run.lua
	.tools/lua/src/lua tests/phase2.lua
	.tools/lua/src/lua tests/phase3.lua
	.tools/lua/src/lua tests/phase4.lua
	.tools/lua/src/lua tests/phase1_probe.lua
	python3 tests/phase1_tooling.py
	python3 tests/phase2_tooling.py
check: format-check lint manifest test
package: check
	python3 scripts/manifest.py --package
