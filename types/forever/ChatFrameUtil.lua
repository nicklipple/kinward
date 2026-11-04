---@meta
-- Forever 1.60.1.70755, Gethe 17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c.
-- Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua:
-- AddMessageEventFilter/RemoveMessageEventFilter forward event and callback
-- into the shared registry. Mainline annotations do not define this namespace.
---@class GuardianForeverChatFrameUtil
---@field AddMessageEventFilter fun(event: string, callback: fun(frame: Frame, event: string, ...: unknown): boolean?)
---@field RemoveMessageEventFilter fun(event: string, callback: fun(frame: Frame, event: string, ...: unknown): boolean?)
ChatFrameUtil = {}
