Forever corrections require a path and symbol in the pinned Forever source,
or recorded real-client evidence. Upstream annotations alone do not establish
API availability.

`ChatFrameUtil.lua` defines only the filter registration/removal functions used
by the developer probe and gated Phase 5 candidate adapter, evidenced by
`Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua` at the
Forever revision recorded in ARCHITECTURE.md. It does not establish runtime
filter accessibility or coverage.

`DropdownButton.lua` adds the native `SetupMenu` signature omitted by upstream
widget annotations. Evidence is pinned in `Blizzard_Menu/DropdownButton.lua` and
`Blizzard_Menu/11_0_0_MenuImplementationGuide.lua`; the radio descriptions use
the existing menu proxy types.
