-- A real pickup keeps its native pedestal, shadow and overlay. Only its item
-- layer is temporarily withheld so the shared effect can draw it in order.
local PickupVisual = {}

function PickupVisual.copyColor(value)
    -- A property getter can lend mutable engine storage. Lerp allocates a
    -- complete Color, retaining colorize as well as tint/alpha/offset.
    return Color.Lerp(value, value, 0)
end

local function rotate(x, y, degrees)
    local r = math.rad(degrees)
    return x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r)
end

local function requireMethods(value, names)
    assert(value, "pickup presentation data unavailable")
    for _, name in ipairs(names) do
        assert(type(value[name]) == "function", "pickup presentation requires " .. name)
    end
end

function PickupVisual.bind(pickup)
    local s = pickup:GetSprite()
    requireMethods(s, { "GetLayer", "GetLayerFrameData", "RenderLayer" })
    local name = pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and "head" or "body"
    local layer = s:GetLayer(name)
    requireMethods(layer, { "GetLayerID", "IsVisible", "SetVisible", "GetPos", "GetSize",
        "GetRotation", "GetFlipX", "GetFlipY" })
    local id = layer:GetLayerID()
    requireMethods(s:GetLayerFrameData(id), { "GetPos", "GetPivot", "GetScale", "GetRotation",
        "GetWidth", "GetHeight" })
    return { pickup = pickup, sprite = s, id = id, visible = layer:IsVisible() }
end

function PickupVisual.hide(view)
    if view.released then return end
    view.sprite:GetLayer(view.id):SetVisible(false)
end

function PickupVisual.hasFrame(view)
    -- Collect/other native poses can keep the pickup alive without an item
    -- frame. Stop borrowing its presentation; never force it back to Idle.
    return view and view.sprite:GetLayer(view.id) ~= nil
        and view.sprite:GetLayerFrameData(view.id) ~= nil
end

function PickupVisual.restore(view)
    if view and not view.released and view.pickup:Exists() then
        local layer = view.sprite:GetLayer(view.id)
        if layer then layer:SetVisible(view.visible) end
    end
end

function PickupVisual.release(view)
    PickupVisual.restore(view)
    view.released = true
end

-- Frame data already includes interpolation and the ANM2 root transform.
-- Use it only to centre effects; RenderLayer retains the actual native art,
-- animation, crop, shader and bobbing instead of redrawing a config PNG.
local function localCenter(view, sourcePoint)
    local s, id = view.sprite, view.id
    local frame, layer = s:GetLayerFrameData(id), s:GetLayer(id)
    local pivot, scale, pos = frame:GetPivot(), frame:GetScale(), frame:GetPos()
    local x = (sourcePoint and sourcePoint.X or frame:GetWidth() / 2) - pivot.X
    local y = (sourcePoint and sourcePoint.Y or frame:GetHeight() / 2) - pivot.Y
    x, y = rotate(x * scale.X, y * scale.Y, frame:GetRotation())
    local size, shift = layer:GetSize(), layer:GetPos()
    x, y = (x + pos.X) * size.X, (y + pos.Y) * size.Y
    if layer:GetFlipX() then x = -x end
    if layer:GetFlipY() then y = -y end
    x, y = rotate(x, y, layer:GetRotation())
    return x + shift.X, y + shift.Y
end

local function spriteCenter(view, sourcePoint)
    local s = view.sprite
    local x, y = localCenter(view, sourcePoint)
    if s.FlipX then x = -x end
    if s.FlipY then y = -y end
    x, y = rotate(x * s.Scale.X, y * s.Scale.Y, s.Rotation)
    return x + s.Offset.X, y + s.Offset.Y
end

function PickupVisual.center(view, sourcePoint)
    local p = view.pickup
    local pos = Isaac.WorldToScreen(p.Position)
    local offset = p.SpriteOffset
    local x, y = spriteCenter(view, sourcePoint)
    return Vector(pos.X + offset.X + x, pos.Y + offset.Y + y)
end

function PickupVisual.render(view, x, y, sx, sy, color, rotation)
    if view.released or not view.visible then return end
    local s, layer = view.sprite, view.sprite:GetLayer(view.id)
    local previousColor = PickupVisual.copyColor(s.Color)
    local previousScale, previousRotation = Vector(s.Scale.X, s.Scale.Y), s.Rotation
    local visible = layer:IsVisible()
    -- Restore every borrowed field even if a render/provider throws.
    local ok, err = pcall(function()
        s.Scale = Vector(previousScale.X * (sx or 1), previousScale.Y * (sy or sx or 1))
        s.Rotation = previousRotation + (rotation or 0)
        s.Color = previousColor * color
        layer:SetVisible(view.visible)
        local cx, cy = spriteCenter(view)
        s:RenderLayer(view.id, Vector(x - cx, y - cy))
    end)
    s.Color, s.Scale, s.Rotation = previousColor, previousScale, previousRotation
    layer:SetVisible(visible)
    if not ok then error(err, 0) end
end

return PickupVisual
