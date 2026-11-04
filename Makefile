.PHONY: bootstrap format format-check lint manifest test check package
bootstrap:
	python3 scripts/bootstrap.py
format:
	.tools/stylua/stylua Core.lua Settings.lua tests types/addon.lua
format-check:
	.tools/stylua/stylua --check Core.lua Settings.lua tests types/addon.lua
lint:
	python3 scripts/lint.py
manifest:
	python3 scripts/manifest.py
test:
	.tools/lua/src/lua tests/run.lua
check: format-check lint manifest test
package: check
	python3 scripts/manifest.py --package
