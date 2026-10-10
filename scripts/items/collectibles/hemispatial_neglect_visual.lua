-- Cosmetic only: clip the native player draw, including its current costumes.
-- Never change Visible, sprite colours, costumes, inventory, or save data.
local M = {}
local ID = Isaac.GetItemIdByName("Hemispatial Neglect")
local surfaces, capturing, failures = {}, {}, {}
local serial = 0
local outlineShader, outlineUnavailable

local function supported(player)
    local rg, renderer = rawget(_G, "REPENTOGON"), rawget(_G, "Renderer")
    return type(rg) == "table" and rg.Real == true
        and ModCallbacks and type(ModCallbacks.MC_PRE_PLAYER_RENDER) == "number"
        and type(renderer) == "table" and type(renderer.CreateImage) == "function"
        and type(renderer.RenderToImage) == "function"
        and SourceQuad and type(SourceQuad.NewFromBounds) == "function"
        and DestinationQuad and type(DestinationQuad.NewFromBounds) == "function"
        and type(Isaac.GetScreenWidth) == "function" and type(Isaac.GetScreenHeight) == "function"
        and type(Isaac.WorldToScreen) == "function" and type(player.Render) == "function"
end

local function report(key, reason)
    if failures[key] then return end
    failures[key] = true
    ConchBlessing.printError("Hemispatial Neglect appearance: " .. tostring(reason)
        .. "; keeping the native player visible.")
end

local function costumeEquipped(player)
    -- Read the native costume list, not ownership or the top visible layer.
    -- Old Wardrobe uses AddCostume/RemoveCostume for registered item costumes.
    -- Never re-add it here: that would undo the user's wardrobe choice.
    assert(type(Isaac.GetItemConfig) == "function", "item costume config unavailable")
    local config = Isaac.GetItemConfig():GetCollectible(ID)
    assert(config and config.Costume and config.Costume.ID >= 0,
        "item costume not loaded; fully restart the game after updating content/costumes2.xml")
    assert(type(player.GetCostumeSpriteDescs) == "function", "costume inspection API unavailable")
    local costumes = player:GetCostumeSpriteDescs()
    assert(type(costumes) == "table", "invalid costume list")
    for _, desc in ipairs(costumes) do
        local item = desc:GetItemConfig()
        if item and item.ID == ID and item.Type == config.Type then return true end
    end
    return false
end

local function appearanceEnabled(player, key)
    if failures[key] then return false end
    local ok, equipped = pcall(costumeEquipped, player)
    if not ok then report(key, equipped) end
    if not ok or not equipped then surfaces[key] = nil; return false end
    return true
end

local function surfaceFor(key)
    local width, height = math.ceil(Isaac.GetScreenWidth()), math.ceil(Isaac.GetScreenHeight())
    assert(width > 0 and height > 0 and width <= 8192 and height <= 8192, "invalid render dimensions")
    local state = surfaces[key]
    if state and state.width == width and state.height == height then return state end
    serial = serial + 1
    local image = Renderer.CreateImage(width, height, "ConchBlessingNeglect" .. serial)
    assert(image and type(image.Render) == "function", "Image.Render unavailable")
    state = { image = image, width = width, height = height }
    surfaces[key] = state
    return state
end

local function bounds(player, offset, state, direction)
    if direction == Direction.RIGHT then return 0, state.width end
    -- Front hides screen-left; rear hides screen-right. Right-facing profile
    -- is outline-only; left-facing profile uses the untouched native draw.
    local rear = direction == Direction.UP
    local anchor = Isaac.WorldToScreen(player.Position)
    local spriteOffset = player.SpriteOffset
    local x = anchor.X + offset.X + (spriteOffset and spriteOffset.X or 0)
    x = math.max(0, math.min(state.width, x))
    return rear and 0 or x, rear and x or state.width
end

local function getOutlineShader(image)
    if outlineShader then return outlineShader end
    if outlineUnavailable then return end
    local ok, result = pcall(function()
        local fmt = Renderer.VertexAttributeFormat
        assert(fmt and type(Renderer.LoadShader) == "function"
            and type(image.RenderWithShader) == "function"
            and type(image.GetPaddedWidth) == "function" and type(image.GetPaddedHeight) == "function",
            "outline shader API unavailable")
        return Renderer.LoadShader("shaders/conch_neglect_outline", {
            {"Position", fmt.POSITION}, {"Color", fmt.COLOR}, {"TexCoord", fmt.TEX_COORD},
            {"TexelStep", fmt.VEC2},
        })
    end)
    if ok and result then outlineShader = result; return result end
    outlineUnavailable = true
    ConchBlessing.printError("Hemispatial Neglect appearance: " .. tostring(result)
        .. "; right-facing profile uses a black silhouette until shaders are available.")
end

local function drawOutline(image, source, destination)
    local shader = getOutlineShader(image)
    if shader then
        image:RenderWithShader(source, destination, KColor(0.16, 0.13, 0.15, 1), shader, {
            TexelStep = {1 / image:GetPaddedWidth(), 1 / image:GetPaddedHeight()},
        })
    else
        image:Render(source, destination, KColor(0, 0, 0, 1))
    end
end

function M.onPrePlayerRender(_, player, offset)
    local key = GetPtrHash(player)
    if capturing[key] then return end -- exactly one nested native draw
    if ID <= 0 or not player:HasCollectible(ID) then
        surfaces[key], failures[key] = nil, nil
        return
    end
    if player.Visible == false then return end
    if not appearanceEnabled(player, key) then return end
    -- The intact side needs no replacement renderer, even after a previous
    -- capture failure. This also avoids needless offscreen passes facing left.
    local direction = player:GetHeadDirection()
    if direction == Direction.LEFT or failures[key] then return end
    if not supported(player) then
        report(key, "requires REPENTOGON player-render and procedural-image APIs")
        return
    end

    local ok, err = pcall(function()
        local state = surfaceFor(key)
        local left, right = bounds(player, offset, state, direction)
        -- Keep native screen coordinates and the full viewport. Moving a small
        -- capture to (0,0) would break native water/mirror clipping and offsets.
        local topLeft, bottomRight = Vector(left, 0), Vector(right, state.height)
        local source = SourceQuad.NewFromBounds(topLeft, bottomRight)
        local destination = DestinationQuad.NewFromBounds(topLeft, bottomRight)
        local colour = KColor(1, 1, 1, 1)
        capturing[key] = true
        Renderer.RenderToImage(state.image, function(controller)
            controller:Clear()
            player:Render(offset)
        end)
        capturing[key] = nil
        -- Cancel the outer native draw only after capture AND display succeed.
        -- The omitted half is transparent: no black rectangle over the room.
        if direction == Direction.RIGHT then drawOutline(state.image, source, destination)
        elseif right > left then state.image:Render(source, destination, colour) end
    end)
    capturing[key] = nil -- including exceptions in native render callbacks
    if not ok then
        surfaces[key] = nil
        report(key, err)
        return
    end
    return false
end

function M.onPlayerUpdate(_, player)
    local key = GetPtrHash(player)
    if ID <= 0 or not player:HasCollectible(ID) then
        surfaces[key], failures[key] = nil, nil
    elseif appearanceEnabled(player, key) and not supported(player) then
        -- This path also reports a missing pre-render callback, where the
        -- optional callback registration cannot invoke the renderer at all.
        report(key, "requires REPENTOGON player-render and procedural-image APIs")
    end
end

function M.reset()
    surfaces, capturing, failures = {}, {}, {}
    outlineShader, outlineUnavailable = nil, nil
end

function M.onUnload(_, mod)
    if mod == ConchBlessing or mod == ConchBlessing.originalMod then M.reset() end
end

return M
