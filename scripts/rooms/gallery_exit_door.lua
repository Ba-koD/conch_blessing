-- Appraisal's return door is vanilla's EXIT door (a frame with a lit EXIT sign that
-- flickers) re-skinned green, the way Angel's Crown re-skins the Treasure Room door:
-- vanilla's ANM2 and sheet layout, only the spritesheet swapped, so every animation
-- the ANM2 drives keeps working. The sheet keeps vanilla's sign plate and every
-- pixel outside the frame and door panels.
local GalleryExitDoor = {}

GalleryExitDoor.ANM2 = "gfx/grid/door_01x_ghostexit.anm2"
local SHEET = "gfx/grid/door_01x_ghostexit_green.png"
-- `Sprite:ReplaceSpritesheet` takes a layer id; this ANM2 draws its one sheet on six
-- layers: Background, Door1, Door2, Frame, Key, Sign.
local LAYER_COUNT = 6
local OPENED = "Opened"

local function callbackId(stageAPI, name)
    local callbacks = stageAPI.Enum and stageAPI.Enum.Callbacks
    return callbacks and callbacks[name] or name
end

local function addCallbacks(stageAPI, doorName)
    local owner = "ConchBlessing.GalleryExitDoor." .. doorName
    if type(stageAPI.UnregisterCallbacks) == "function" then stageAPI.UnregisterCallbacks(owner) end
    stageAPI.AddCallback(owner, callbackId(stageAPI, "POST_SPAWN_CUSTOM_DOOR"), 0, function(_, _, sprite)
        for layer = 0, LAYER_COUNT - 1 do
            sprite:ReplaceSpritesheet(layer, SHEET)
        end
        sprite:LoadGraphics()
    end, doorName)
    -- The sign's flicker lives in the non-looping Opened animation; replaying it keeps
    -- the sign flickering now and then. StageAPI drives no other animation on an
    -- always-open door.
    stageAPI.AddCallback(owner, callbackId(stageAPI, "POST_CUSTOM_DOOR_UPDATE"), 0, function(_, _, sprite)
        if sprite:IsFinished(OPENED) then sprite:Play(OPENED, true) end
    end, doorName)
end

---Dress the StageAPI custom door registered as `doorName`. StageAPI calls both
---callbacks only for that door name, after it has loaded and started the sprite.
---The look is cosmetic: if this fails the door keeps vanilla's EXIT sheet and works.
function GalleryExitDoor.register(stageAPI, doorName)
    local ok, err = pcall(addCallbacks, stageAPI, doorName)
    if not ok then
        ConchBlessing.printError("Appraisal exit-door sheet unavailable: " .. tostring(err))
    end
end

return GalleryExitDoor
