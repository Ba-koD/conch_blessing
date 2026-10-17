local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local GalleryManager = require("scripts.rooms.gallery_manager")

GalleryManager.bootstrapStageAPI()

return {
    GalleryManager = GalleryManager,
}
