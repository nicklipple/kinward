.PHONY: bootstrap format format-check lint manifest test check package stage-simulator unstage-simulator
bootstrap:
	python3 scripts/bootstrap.py
format:
	.tools/stylua/stylua Core.lua Minimap.lua Settings.lua Profile.lua Policy.lua Session.lua Requests.lua History.lua HistoryCapture.lua Protocol.lua Family.lua Pairing.lua Transport.lua WoWTransport.lua Activity.lua PairingPanel.lua PlayerMenu.lua Dashboard.lua Chat.lua WoWChat.lua LiveTest.lua tests scripts/probes types/addon.lua
format-check:
	.tools/stylua/stylua --check Core.lua Minimap.lua Settings.lua Profile.lua Policy.lua Session.lua Requests.lua History.lua HistoryCapture.lua Protocol.lua Family.lua Pairing.lua Transport.lua WoWTransport.lua Activity.lua PairingPanel.lua PlayerMenu.lua Dashboard.lua Chat.lua WoWChat.lua LiveTest.lua tests scripts/probes types/addon.lua
lint:
	python3 scripts/lint.py
manifest:
	python3 scripts/manifest.py
test:
	.tools/lua/src/lua tests/run.lua
	.tools/lua/src/lua tests/phase2.lua
	.tools/lua/src/lua tests/phase3.lua
	.tools/lua/src/lua tests/phase4.lua
	.tools/lua/src/lua tests/phase5.lua
	.tools/lua/src/lua tests/phase6.lua
	.tools/lua/src/lua tests/phase7.lua
	.tools/lua/src/lua tests/pairing.lua
	.tools/lua/src/lua tests/live_test.lua
	.tools/lua/src/lua tests/phase1_probe.lua
	python3 tests/phase1_tooling.py
	python3 tests/phase2_tooling.py
check: format-check lint manifest test
package: check
	python3 scripts/manifest.py --package

stage-simulator:
	python3 scripts/phase2_simulator.py install
unstage-simulator:
	python3 scripts/phase2_simulator.py remove
