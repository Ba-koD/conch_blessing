local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

local beltCases={ "book_of_virtues", "d_infinity", "blank_card", "placebo", "clear_rune", "glowing_hour_glass", "jar_of_wisps" }
for _, name in ipairs(beltCases) do
    S.add("UTILITY_BELT", name, { synergies = true, conditions = true }, function(plan, id)
        for _, first in ipairs({ "active", "belt" }) do
            plan.section("UTILITY_BELT / " .. name .. " / first=" .. first)
            plan.act(function(player, ctx)
                ctx.activeId = assert(CollectibleType["COLLECTIBLE_" .. string.upper(name)], "missing vanilla active")
                if first == "active" then player:AddCollectible(ctx.activeId, 0, false)
                else player:AddCollectible(id, 0, false) end
            end)
            plan.wait(4)
            plan.act(function(player, ctx)
                player:AddCollectible(first == "active" and id or ctx.activeId, 0, false)
            end)
            plan.wait(4)
            plan.check("excluded active stays in main slot in both acquisition orders", function(player, ctx)
                return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == ctx.activeId
                    and player:GetActiveItem(ActiveSlot.SLOT_POCKET) == 0, "main=" .. player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            end)
            plan.act(function(player, ctx)
                player:RemoveCollectible(id)
                player:RemoveCollectible(ctx.activeId, true, ActiveSlot.SLOT_PRIMARY)
            end)
            plan.wait(4)
        end
    end, { name })
end

S.sequenceBundle("UTILITY_BELT","excluded_actives",{synergies=true,conditions=true},beltCases,
    function(plan)
        plan.require("active-slot fixture starts clean",function(player)
            return player:GetActiveItem(0)==0 and player:GetActiveItem(1)==0
                and player:GetActiveItem(2)==0 and player:GetActiveItem(3)==0,"all active slots empty"
        end)
    end,
    function(plan,id)
        plan.require("belt and excluded active fully removed before next case",function(player)
            return not player:HasCollectible(id) and player:GetActiveItem(0)==0
                and player:GetActiveItem(1)==0 and player:GetActiveItem(2)==0 and player:GetActiveItem(3)==0
                and not ConchBlessing.utilitybelt._pendingPlayers[GetPtrHash(player)],
                "no belt, active or pending transfer remains"
        end)
    end)

for _, pair in ipairs({ {"ROUND", "CEIL"}, {"FLOOR", "CEIL"}, {"FLOOR", "ROUND"} }) do
    local key, other = pair[1], pair[2]
    S.add(key, string.lower(other), { synergies = true }, function(plan, id)
        plan.act(function(player)
            player:AddCollectible(CollectibleType.COLLECTIBLE_SMB_SUPER_FAN, 0, false)
            player:AddCollectible(CollectibleType.COLLECTIBLE_SCREW, 0, false)
        end)
        plan.wait(4)
        plan.act(function(player, ctx) ctx.raw = H.stats(player) end)
        for _, order in ipairs({ {key,other}, {other,key} }) do
            for _, which in ipairs(order) do
                plan.act(function(player) player:AddCollectible(ConchBlessing.ItemData[which].id, 0, false) end)
                plan.wait(4)
            end
            plan.check("priority is independent of acquisition order", function(player, ctx)
                local base = require("scripts.lib.character_base_stats").get(player)
                for stat, actual in pairs(H.stats(player)) do
                    local hud = math.floor(ctx.raw[stat] * 100 + 0.5) / 100
                    local expected = other == "CEIL" and math.ceil(hud) or math.floor(hud + 0.5)
                    if other == "ROUND" and stat ~= "Luck" and hud > 0 then expected = math.max(1, expected) end
                    if key == "FLOOR" then expected = math.max(expected, base[stat]) end
                    if not H.near(actual, expected) then return false, stat .. " actual=" .. actual .. " expected=" .. expected end
                end
                return true, "six actual stats match independent priority formula"
            end)
            for _, which in ipairs(order) do
                plan.act(function(player) player:RemoveCollectible(ConchBlessing.ItemData[which].id) end)
                plan.wait(4)
            end
            plan.check("removing both restores unrounded inputs", function(player, ctx) return H.sameStats(player, ctx.raw) end)
        end
    end, { string.lower(other) })
end

S.add("LIVE_EYE", "weapon_and_rock_bottom", { synergies = true, conditions = true }, function(plan, id)
    plan.act(function(player, ctx)
        player:AddCollectible(id, 0, false)
        ctx.damage = player.Damage
    end)
    plan.wait(4)
    for _, spec in ipairs({ {true,false,1.5}, {false,false,1}, {false,true,3}, {true,true,3} }) do
        plan.act(function(player)
            S.collectible(player, CollectibleType.COLLECTIBLE_BRIMSTONE, spec[1] and 1 or 0)
            S.collectible(player, CollectibleType.COLLECTIBLE_ROCK_BOTTOM, spec[2] and 1 or 0)
        end)
        plan.wait(4)
        plan.check("weapon and Rock Bottom change the applied multiplier", function(player)
            return H.expect(player:GetData().__conchLiveEyeApplied, spec[3])
        end)
    end
    plan.act(function(player)
        player:RemoveCollectible(id)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_ROCK_BOTTOM)
    end)
    plan.wait(4)
    plan.check("removing Eye and its synergy restores actual damage", function(player,ctx)
        return H.expect(player.Damage,ctx.base.Damage)
    end)
end, { "rock_bottom" })

S.add("SOFLAM", "mr_mega_and_multishot", { synergies = true, damage = true, conditions = true }, function(plan, id)
    plan.require("confirmed-damage callback available", function()
        return require("scripts.lib.damage_provenance").hasAppliedDamageCallback() or nil, "requires applied-damage evidence"
    end)
    plan.act(function(player)
        player:AddCollectible(id, 0, false)
        S.collectible(player, CollectibleType.COLLECTIBLE_LUCKY_FOOT, 20)
        player.Position = Game():GetRoom():GetCenterPos() - Vector(180, 0)
    end)
    for _, spec in ipairs({ {mega=0,shots=1}, {mega=1,shots=1}, {mega=2,shots=1},
        {mega=0,shots=2}, {mega=0,shots=1} }) do
        plan.section("SOFLAM / Mr. Mega=" .. spec.mega .. " shots=" .. spec.shots)
        plan.act(function(player)
            S.collectible(player, CollectibleType.COLLECTIBLE_MR_MEGA, spec.mega)
            S.collectible(player, CollectibleType.COLLECTIBLE_20_20, spec.shots == 2 and 1 or 0)
        end)
        plan.wait(4)
        plan.act(function(player, ctx)
            H.isolateAttack()
            ctx.target=H.target(player)
            ctx.firstDamage,ctx.firstRocket=nil,nil
            ctx.expected=player.Damage*3*(2^spec.mega)*spec.shots
        end)
        H.fireWeaponAtTarget(plan,"laser")
        plan.wait(2)
        plan.act(function(player,ctx)
            -- Spawn range witnesses only after the actual direct laser is gone.
            -- Its piercing input damage must not be counted as missile damage.
            local center=ctx.weaponTargetPosition
            ctx.nearTarget,ctx.outsideTarget=H.target(player),H.target(player)
            ctx.nearTarget.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
            ctx.outsideTarget.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
            -- Attack Fly's native radius is 17. Place its complete hitbox
            -- outside the normal 75px radius and inside the 112.5px Mega
            -- radius, rather than assuming that a target is a point or <=14px.
            ctx.nearDistance=(75+112.5)/2
            ctx.outsideDistance=112.5+ctx.outsideTarget.Size+12
            assert(ctx.nearDistance-ctx.nearTarget.Size>75
                and ctx.nearDistance+ctx.nearTarget.Size<112.5,
                "range witness does not separate normal and Mega explosions")
            ctx.nearTarget.Position=center+Vector(ctx.nearDistance,0)
            ctx.outsideTarget.Position=center+Vector(ctx.outsideDistance,0)
            ctx.markedAt=ctx.weaponHitAt
            ctx.hp,ctx.nearHp,ctx.farHp=ctx.target.HitPoints,ctx.nearTarget.HitPoints,ctx.outsideTarget.HitPoints
        end)
        plan.waitUntil(function(_,ctx)
            return H.targetReady(ctx.nearTarget) and H.targetReady(ctx.outsideTarget)
        end,20,"range witnesses become damageable during lock-on")
        plan.require("one strike queued by the real attack", function()
            return H.expect(#ConchBlessing.soflam._pendingStrikes, 1)
        end)
        plan.waitUntil(function(_, ctx)
            ctx.target.Position=ctx.weaponTargetPosition;ctx.target.Velocity=Vector.Zero
            ctx.nearTarget.Position=ctx.weaponTargetPosition+Vector(ctx.nearDistance,0);ctx.nearTarget.Velocity=Vector.Zero
            ctx.outsideTarget.Position=ctx.weaponTargetPosition+Vector(ctx.outsideDistance,0);ctx.outsideTarget.Velocity=Vector.Zero
            local strike=ConchBlessing.soflam._pendingStrikes[1]
            if not ctx.firstRocket and strike and strike.phase=="rocket"
                and strike.rocketEffect and strike.rocketEffect:Exists() then
                ctx.firstRocket=Game():GetFrameCount()
            end
            if ctx.target.HitPoints < ctx.hp and not ctx.firstDamage then ctx.firstDamage = Game():GetFrameCount() end
            return ctx.firstDamage and #ConchBlessing.soflam._pendingStrikes == 0
                and #Isaac.FindByType(EntityType.ENTITY_BOMB, -1, -1) == 0
        end, 180, "all real missiles explode")
        plan.check("actual total missile HP loss includes copies and multishot", function(_, ctx)
            local loss = ctx.hp - ctx.target.HitPoints
            return math.abs(loss-ctx.expected) <= math.max(0.02,ctx.expected*0.002), "HP loss=" .. loss .. " expected=" .. ctx.expected
        end)
        plan.check("missiles respect the 45-update lock-on delay", function(_, ctx)
            if not ctx.firstRocket then return false,"no actual falling rocket observed" end
            local elapsed=ctx.firstRocket-ctx.markedAt
            -- Lock-on ends when the rocket starts falling. The visual fall and
            -- buffered bomb damage happen afterward; they are not a 45-tick hit.
            return elapsed>=44 and elapsed<=46 and ctx.firstDamage>ctx.firstRocket,
                "rocket starts after "..elapsed.." frame deltas; HP loss after "..(ctx.firstDamage-ctx.markedAt)
        end)
        plan.check("Mr. Mega extends range once; outside enemy remains unharmed", function(_, ctx)
            local near = ctx.nearHp - ctx.nearTarget.HitPoints
            return (spec.mega > 0 and near > 0 or spec.mega == 0 and near == 0)
                and ctx.outsideTarget.HitPoints == ctx.farHp, ctx.nearDistance.."px HP loss=" .. near
                    .."; "..ctx.outsideDistance.."px HP loss=" .. (ctx.farHp-ctx.outsideTarget.HitPoints)
        end)
        plan.act(function(_, ctx)
            for _, field in ipairs({"target","nearTarget","outsideTarget"}) do ctx[field]:Remove(); ctx[field]=nil end
        end)
    end
    plan.section("SOFLAM / removal cancels pending strike")
    plan.act(function(player,ctx) H.isolateAttack();ctx.target=H.target(player) end)
    H.fireWeaponAtTarget(plan,"laser")
    plan.require("a real laser has queued a strike before removal",function()
        return H.expect(#ConchBlessing.soflam._pendingStrikes,1)
    end)
    plan.act(function(player,ctx) ctx.hp=ctx.target.HitPoints;player:RemoveCollectible(id) end)
    plan.wait(65)
    plan.check("no late damage after final removal", function(_,ctx)
        return ctx.target.HitPoints == ctx.hp and #ConchBlessing.soflam._pendingStrikes == 0,
            "HP loss=" .. (ctx.hp-ctx.target.HitPoints)
    end)
end, { "mr_mega" })

S.link("APPRAISAL_CERTIFICATE","conch_test appraisal detail",{synergies=true,conditions=true},{"atropos"})

local function dcCollectibleStock()
    local stock = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1)) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() and pickup.SubType > 0 then
            stock[#stock+1] = string.format("%d@%.2f,%.2f",pickup.SubType,pickup.Position.X,pickup.Position.Y)
        end
    end
    table.sort(stock)
    return table.concat(stock,";"), #stock
end

S.add("ATROPOS","death_certificate",{synergies=true,conditions=true},function(plan,id)
    plan.require("native dimension and transition evidence available",function(player)
        return (type(Game():GetLevel().GetDimension)=="function"
            and type(RoomTransition)=="table" and type(RoomTransition.GetTransitionMode)=="function"
            and type(player.IsItemQueueEmpty)=="function") or nil,"dimension, transition mode and pickup queue capabilities required"
    end)
    plan.act(function(player,ctx)
        ctx.originIndex=Game():GetLevel():GetCurrentRoomDesc().ListIndex
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE,UseFlag.USE_NOANIM,-1)
    end)
    plan.waitUntil(function() return Game():GetLevel():GetDimension()==2 end,300,"actual native Death Certificate entry")
    plan.wait(8)
    plan.act(function(_,ctx)
        ctx.entranceIndex=Game():GetLevel():GetCurrentRoomDesc().ListIndex
        ctx.entranceGrid=Game():GetLevel():GetCurrentRoomIndex()
        ctx.foolsBefore=#Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TAROTCARD,Card.CARD_FOOL)
    end)
    plan.act(function(player) player:AddTrinket(id,false) end)
    plan.wait(4)
    plan.check("acquiring Atropos inside DC creates no Fool card",function(_,ctx)
        return H.expect(#Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TAROTCARD,Card.CARD_FOOL),ctx.foolsBefore)
    end)
    plan.require("first room has the actual return door",function()
        local doors=StageAPI.GetCustomDoors("ConchBlessingAtroposDeathCertificateReturn")
        local door=doors and doors[1] and doors[1].Data and doors[1].Data.DoorEntity
        return door and door:Exists() and #doors==1,"one live Atropos return door"
    end)
    plan.check("return door loads the EXIT animation resource",function()
        local door=StageAPI.GetCustomDoors("ConchBlessingAtroposDeathCertificateReturn")[1].Data.DoorEntity
        local sprite=door:GetSprite()
        if type(sprite.GetFilename)~="function" or type(sprite.IsLoaded)~="function" then
            return nil,"sprite resource inspection unavailable; appearance still requires visual verification"
        end
        local path=sprite:GetFilename()
        return sprite:IsLoaded() and path:lower():find("door_01x_ghostexit.anm2",1,true)~=nil,
            "loaded=" .. tostring(sprite:IsLoaded()) .. " anm2=" .. tostring(path)
    end)
    plan.check("EXIT door frame uses the green spritesheet",function()
        local sprite=StageAPI.GetCustomDoors("ConchBlessingAtroposDeathCertificateReturn")[1].Data.DoorEntity:GetSprite()
        local layer=type(sprite.GetLayer)=="function" and sprite:GetLayer(3) or nil
        if not (layer and type(layer.GetSpritesheetPath)=="function") then return nil,"spritesheet inspection unavailable" end
        local sheet=layer:GetSpritesheetPath()
        return sheet:lower():find("door_01x_ghostexit_green.png",1,true)~=nil,tostring(sheet)
    end)
    plan.require("return door is on the reachable left wall",function(player)
        local grid=StageAPI.GetCustomDoors("ConchBlessingAtroposDeathCertificateReturn")[1]
        local door=grid.Data.DoorEntity
        local index,pos=require("scripts.rooms.native_return_door").leftWall(Game():GetRoom())
        return index~=nil and grid.GridIndex==index and door.Position:DistanceSquared(pos)<=1
            and Game():GetRoom():IsPositionInRoom(door.Position+Vector(40,0),0),
            string.format("grid=%s expected=%s; door=(%.1f,%.1f); player=(%.1f,%.1f)",
                tostring(grid.GridIndex),tostring(index),door.Position.X,door.Position.Y,player.Position.X,player.Position.Y)
    end)
    plan.act(function(player,ctx)
        local room=Game():GetRoom()
        for slot=0,7 do
            local door=room:GetDoor(slot)
            if door and door.TargetRoomIndex>=0 then
                ctx.stockGrid=door.TargetRoomIndex
                Game():StartRoomTransition(ctx.stockGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player,2)
                return
            end
        end
        error("no native stock-room route from Death Certificate entrance")
    end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomIndex()==ctx.stockGrid end,180,"real stock-room entry")
    plan.wait(4)
    -- Preload another real stock room so a comparison can detect cross-room
    -- deletion instead of only checking newly generated stock after the choice.
    plan.act(function(player,ctx)
        ctx.stockIndex=Game():GetLevel():GetCurrentRoomDesc().ListIndex
        for slot=0,7 do
            local door=Game():GetRoom():GetDoor(slot)
            if door and door.TargetRoomIndex>=0 and door.TargetRoomIndex~=ctx.entranceGrid then
                ctx.otherStockGrid=door.TargetRoomIndex
                Game():StartRoomTransition(ctx.otherStockGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player,2)
                return
            end
        end
        error("no second stock-room route for room-local choice verification")
    end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomIndex()==ctx.otherStockGrid end,180,"visit another stock room before choosing")
    plan.act(function(_,ctx) ctx.otherStock,ctx.otherStockCount=dcCollectibleStock() end)
    plan.require("other room has stock to preserve",function(_,ctx)
        return ctx.otherStockCount>1,"collectibles=" .. ctx.otherStockCount
    end)
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.stockGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player,2) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.stockIndex end,180,"return to room to make a choice")
    plan.act(function(player,ctx)
        local list=Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1)
        assert(#list>1,"stock room needs multiple actual collectibles")
        ctx.reward=list[1]:ToPickup(); ctx.rewardId=ctx.reward.SubType
        ctx.beforeReward=player:GetCollectibleNum(ctx.rewardId,true)
        ctx.stockIndex=Game():GetLevel():GetCurrentRoomDesc().ListIndex
        ctx.reward.Wait=0; player.Position=ctx.reward.Position
    end)
    plan.waitUntil(function(player,ctx)
        local queued=player.QueuedItem and player.QueuedItem.Item
        return (queued and queued.ID==ctx.rewardId) or player:GetCollectibleNum(ctx.rewardId,true)>ctx.beforeReward
    end,180,"natural collectible accepted into pickup queue")
    plan.check("room stock disappears immediately on accepted pickup, before waiting for animation",function(_,ctx)
        local level=Game():GetLevel()
        return #Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1)==0
            and level:GetDimension()==2 and level:GetCurrentRoomDesc().ListIndex==ctx.stockIndex,
            "remaining collectibles="..#Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1)
    end)
    -- Observe completion of the real pickup queue, including its delayed vanilla
    -- return, instead of assuming everything has settled after twelve updates.
    plan.waitUntil(function(player) return player:IsItemQueueEmpty() end,180,"selected collectible queue finishes")
    plan.wait(1)
    plan.require("choice stays in the selected room after pickup completion",function(_,ctx)
        local level=Game():GetLevel()
        local mode=RoomTransition.GetTransitionMode()
        return level:GetDimension()==2 and level:GetCurrentRoomDesc().ListIndex==ctx.stockIndex and mode==0,
            string.format("dimension=%s expected=2; room=%s expected=%s; transition=%s expected=0",level:GetDimension(),level:GetCurrentRoomDesc().ListIndex,ctx.stockIndex,mode)
    end)
    plan.check("choice removes remaining collectible pedestals",function()
        return H.expect(#Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1),0)
    end)
    plan.check("selected collectible is retained exactly once",function(player,ctx)
        return H.expect(player:GetCollectibleNum(ctx.rewardId,true),ctx.beforeReward+1)
    end)
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.otherStockGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player,2) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomIndex()==ctx.otherStockGrid end,180,"revisit unselected stock room")
    plan.check("choice preserves other room stock",function(_,ctx)
        local stock,count=dcCollectibleStock()
        return stock==ctx.otherStock,string.format("collectibles=%d expected=%d; stock identity matches=%s",count,ctx.otherStockCount,tostring(stock==ctx.otherStock))
    end)
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.stockGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player,2) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.stockIndex end,180,"revisit closed choice room")
    plan.check("closed room stays empty on revisit",function()
        return H.expect(#Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1),0)
    end)
    plan.act(function(player) player:TryRemoveTrinket(id) end)
    plan.wait(4)
    plan.require("Atropos is removed before returning to the entrance",function(player)
        return not player:HasTrinket(id),"return door must survive final item loss"
    end)
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.entranceGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player,2) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.entranceIndex end,180,"return to entrance")
    plan.check("return door survives item loss and entrance revisit without granting cards",function(_,ctx)
        local doors=StageAPI.GetCustomDoors("ConchBlessingAtroposDeathCertificateReturn")
        local entity=doors and doors[1] and doors[1].Data and doors[1].Data.DoorEntity
        return doors and #doors==1 and entity and entity:Exists()
            and #Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TAROTCARD,Card.CARD_FOOL)==ctx.foolsBefore,
            "one retained return door; original card count"
    end)
    plan.waitUntil(function(player)
        if Game():GetLevel():GetDimension()~=2 then return true end
        for _,grid in ipairs(StageAPI.GetCustomDoors("ConchBlessingAtroposDeathCertificateReturn")) do
            local door=grid.Data and grid.Data.DoorEntity
            if door and door:Exists() then player.Velocity=(door.Position-player.Position):Resized(5); break end
        end
        return false
    end,300,"walk through the physical return door")
    plan.act(function(player) player.Velocity=Vector.Zero end)
    plan.check("physical door returns to the exact saved origin",function(_,ctx)
        return H.expect(Game():GetLevel():GetCurrentRoomDesc().ListIndex,ctx.originIndex)
    end)
end,{"death_certificate"})

return S
