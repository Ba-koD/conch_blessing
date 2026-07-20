local GalleryManager = require("scripts.rooms.gallery_manager")

GalleryManager.bootstrapStageAPI()

return {
    GalleryManager = GalleryManager,
}
