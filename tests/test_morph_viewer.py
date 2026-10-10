"""Shipped Lua visual lifecycle/input checks, not evidence of engine rendering."""
import json
import contextlib
import io
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET
from lupa.lua53 import LuaRuntime
from PIL import Image
from generate_xml import find_matching_brace, parse_lua_file

ROOT = Path(__file__).resolve().parents[1]


class MorphVisualTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().repo = ROOT.as_posix()
        self.lua.execute('''
            package.path=repo..'/?.lua;'..package.path
            -- The host uses package internally for fixture loading. Production
            -- code sees Isaac's sandbox, where that global is absent.
            testModules=package.loaded
            benchRunning=false
            testModules['scripts.dev.test_bench']={isRunning=function() return benchRunning end}
            package=nil
            callbacks={}; errors={}; messages={}; drawings={}; sounds={}; pitches={}; paused=false; pressed={}
            ModCallbacks={MC_POST_UPDATE=1,MC_POST_RENDER=2,MC_POST_NEW_ROOM=3,MC_POST_GAME_STARTED=4,
                MC_PRE_GAME_EXIT=5,MC_EXECUTE_CMD=6,MC_INPUT_ACTION=7,MC_PRE_BACKDROP_RENDER_WATER=8,
                MC_POST_BACKDROP_PRE_RENDER_WALLS=9}
            InputHook={GET_ACTION_VALUE=2,IS_ACTION_PRESSED=0,IS_ACTION_TRIGGERED=1}
            ButtonAction={ACTION_RESTART=16,ACTION_SHOOTLEFT=4,ACTION_SHOOTRIGHT=5,
                ACTION_LEFT=0,ACTION_RIGHT=1,ACTION_UP=2,ACTION_DOWN=3,ACTION_SHOOTUP=6,ACTION_SHOOTDOWN=7}
            Keyboard={KEY_R=82,KEY_LEFT=263,KEY_RIGHT=262,KEY_UP=265,KEY_DOWN=264,KEY_BACKSPACE=259}
            Input={IsButtonTriggered=function(k) local p=pressed[k]; pressed[k]=nil; return p end}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350}
            SoundEffect={SOUND_HOLY=1,SOUND_THUNDER=2,SOUND_ROCKET_LAUNCH=3,SOUND_BOSS1_EXPLOSIONS=4,
                SOUND_CANDLE_LIGHT=5,SOUND_FLAME_BURST=6,SOUND_FREEZE=7,SOUND_SMB_LARGE_CHEWS_4=8,SOUND_VAMP_GULP=9,
                SOUND_PORTAL_OPEN=10,SOUND_BEEP=11,SOUND_ANGEL_WING=12,SOUND_LOW_INHALE=13,
                SOUND_REDLIGHTNING_ZAP_STRONG=14,SOUND_BONE_SNAP=15,SOUND_LIGHTBOLT=16}
            function Vector(x,y) return {X=x,Y=y} end
            function GetPtrHash(entity) return tostring(entity) end
            EntityPtr=setmetatable({}, {__call=function(_,entity)
                return setmetatable({}, {__index=function(_,key)
                    if key=='Ref' and entity:Exists() then return entity end
                end})
            end})
            local colorMt={}
            local function makeColor(r,g,b,a,ro,go,bo)
                return setmetatable({R=r,G=g,B=b,A=a,RO=ro or 0,GO=go or 0,BO=bo or 0},colorMt)
            end
            Color=setmetatable({Lerp=function(a,b,t)
                local result=makeColor(1,1,1,1)
                for k,v in pairs(a) do
                    result[k]=type(v)=='number' and v+(b[k]-v)*t or v
                end
                return result
            end}, {__call=function(_,...) return makeColor(...) end})
            colorMt.__eq=function(a,b)
                for _,k in ipairs({'R','G','B','A','RO','GO','BO','colorize'}) do
                    if a[k]~=b[k] then return false end
                end
                return true
            end
            colorMt.__mul=function(a,b)
                return Color(a.R*b.R,a.G*b.G,a.B*b.B,a.A*b.A,a.RO+b.RO,a.GO+b.GO,a.BO+b.BO)
            end
            -- Engine-bound properties can expose the same mutable backing
            -- value on every read. A saved userdata reference is not a copy.
            function borrowSpriteProperties(s)
                local values={Color=s.Color,Scale=s.Scale}
                s.Color=nil; s.Scale=nil
                return setmetatable(s,{
                    __index=function(_,key) return values[key] end,
                    __newindex=function(self,key,value)
                        local target=values[key]
                        if target then
                            local detached={}
                            for k,v in pairs(value) do detached[k]=v end
                            for k in pairs(target) do target[k]=nil end
                            for k,v in pairs(detached) do target[k]=v end
                        else rawset(self,key,value) end
                    end})
            end
            function SFXManager() return {Play=function(_,id,volume,delay,loop,pitch) sounds[#sounds+1]=id; pitches[#pitches+1]=pitch end,
                Stop=function() error('must not stop shared sounds') end,
                AdjustVolume=function() error('must not change shared sound volume') end} end
            room={GetCenterPos=function() return Vector(320,180) end,
                GetBottomRightPos=function() return Vector(600,320) end,
                GetGridSize=function() return 9 end,
                GetGridPosition=function(_,i) return Vector(240+i%3*40,140+math.floor(i/3)*40) end,
                IsPositionInRoom=function() return true end}
            owner={InitSeed=123}; entities={}; players=1
            game={GetRoom=function() return room end,IsPaused=function() return paused end,
                GetNumPlayers=function() return players end,ShakeScreen=function() shakes=(shakes or 0)+1 end}
            function Game() return game end
            config={GetCollectible=function(_,id) return {GfxFileName='c'..id..'.png'} end,
                GetTrinket=function(_,id) return {GfxFileName='t'..id..'.png'} end}
            Isaac={GetItemConfig=function() return config end,WorldToScreen=function(p) return p end,
                GetPlayer=function() return owner end,GetRoomEntities=function()
                    local live={}
                    for _,entity in ipairs(entities) do
                        if not entity.Exists or entity:Exists() then live[#live+1]=entity end
                    end
                    return live
                end,
                GetItemIdByName=function() return 401 end,GetTrinketIdByName=function() return 42 end,
                GetScreenWidth=function() return 640 end,GetScreenHeight=function() return 360 end,
                RenderText=function(...) end,GetTextWidth=function(s) return #s*5 end,
                ConsoleOutput=function(s) messages[#messages+1]=s end,DebugString=function() end,
                Spawn=function() error('cosmetics cannot spawn entities') end,
                ExecuteCommand=function() error('cosmetics cannot change runs') end}
            Sprite=setmetatable({}, {__call=function()
                local s={Color=Color(1,1,1,1),Scale=Vector(1,1),Offset=Vector(0,0),Rotation=0,layers={}}
                function s:GetLayer(id)
                    if id=='head' then id=1 elseif id=='body' then id=0 end
                    if not self.layers[id] then
                        local l={id=id,visible=true,pos=Vector(0,0),size=Vector(1,1),rotation=0}
                        function l:GetLayerID() return self.id end
                        function l:IsVisible() return self.visible end
                        function l:SetVisible(value) self.visible=value end
                        function l:GetPos() return self.pos end
                        function l:GetSize() return self.size end
                        function l:GetRotation() return self.rotation end
                        function l:GetFlipX() return false end
                        function l:GetFlipY() return false end
                        self.layers[id]=l
                    end
                    return self.layers[id]
                end
                function s:GetLayerFrameData(id)
                    local f={}
                    function f:GetPos() return s.itemPos or Vector(0,id==1 and -6-(s.frame or 0)%5 or -1) end
                    function f:GetPivot() return Vector(16,id==1 and 32 or 24) end
                    function f:GetScale() return s.itemScale or Vector(1,1) end
                    function f:GetRotation() return 0 end
                    function f:GetWidth() return 32 end
                    function f:GetHeight() return 32 end
                    return f
                end
                function s:RenderLayer(id,p)
                    assert(self:GetLayer(id):IsVisible())
                    self:Render(p)
                    drawings[#drawings].layer=id
                    drawings[#drawings].native=self
                end
                function s:Load(path) self.path=path; if missing and path:find(missing,1,true) then error('missing asset') end end
                function s:IsLoaded() return true end
                function s:LoadGraphics() end
                function s:ReplaceSpritesheet(_,path) self.sheet=path end
                function s:SetFrame(animation,f) self.animation=animation; self.frame=f end
                function s:GetFilename() return self.path end
                function s:GetAnimation() return self.animation end
                function s:GetFrame() return self.frame end
                function s:Play(animation) self.animation=animation end
                function s:Update() self.frame=(self.frame or 0)+1 end
                function s:IsFinished() return false end
                function s:Render(p)
                    if drawFails then error('render failure') end
                    assert(p.X==p.X and p.Y==p.Y)
                    if self.Scale then assert(self.Scale.X==self.Scale.X and self.Scale.Y==self.Scale.Y) end
                    drawings[#drawings+1]={sheet=self.sheet,path=self.path,frame=self.frame,pos=p,alpha=self.Color.A,
                        scale=self.Scale,rotation=self.Rotation,color=self.Color}
                end
                return s
            end})
            ConchBlessing={ItemData={},AddCallback=function(_,id,fn)
                callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],fn)
            end,printError=function(s) errors[#errors+1]=s end}
            function event(id,...)
                if id==1 and not paused and spawned then
                    for _,p in ipairs(spawned) do if p:Exists() then p.FrameCount=p.FrameCount+1 end end
                end
                local result
                for _,f in ipairs(callbacks[id] or {}) do local r=f(nil,...); if r~=nil then result=r end end
                return result
            end
            V=require('scripts.lib.upgrade_visuals')
            for i,row in ipairs(V.catalog) do
                ConchBlessing.ItemData[row.key]={id=1000+i,type=i>=24 and 'trinket' or 'passive',
                    flag='positive',origin={id=i,type=i>=24 and 'trinket' or 'collectible'}}
            end
            function pickup(id)
                local p={Position=Vector(320,180),SpriteOffset=Vector(0,0),Variant=100,SubType=id or 1,alive=true,sprite=Sprite()}
                p.sprite.Color=Color(1,1,1,0.8); p.sprite.Color.original=true
                function p:Exists() return self.alive end
                function p:GetSprite() return self.sprite end
                return p
            end
            T=require('scripts.template'); ConchBlessing.template=T
        ''')

    def test_all_profiles_render_every_tick_without_entities_or_run_commands(self):
        self.lua.execute('''
            local applied=0
            for _,row in ipairs(V.catalog) do
                if V.isApplied(row.key) then applied=applied+1 end
                local s=V.create(row.key,Vector(320,180))
                for f=0,s.duration do
                    s.frame=f; V.renderFloor(s); V.render(s)
                end
            end
            assert(applied==12 and #errors==0 and #drawings>1000)
        ''')

    def test_hidden_item_layer_holds_until_commit_without_hiding_pedestal(self):
        self.lua.execute('''
            p=pickup(); state={}; custom=T.forItem('DRAGON','positive')
            assert(custom.onBeforeChange(p.Position,p,state)==45 and not p.sprite:GetLayer(1):IsVisible())
            assert(p.sprite.Color.A==0.8 and p.sprite:GetLayer(0):IsVisible())
            for i=1,70 do T.updateAllAnimations(); T.renderAllAnimations() end
            assert(state.morphScene.frame==44 and not p.sprite:GetLayer(1):IsVisible() and #T._activeAnimations==1)
            T.cancelForPickup(p); assert(p.sprite.Color.original and p.sprite:GetLayer(1):IsVisible())
            p.SubType=456
            assert(custom.onAfterChange(p.Position,p,state)==57)
            assert(state.morphScene.frame==45 and state.morphScene.after.sheet=='c456.png')
            for i=1,57 do T.updateAllAnimations() end
            assert(#T._activeAnimations==0 and p.sprite.Color.original and p.sprite.Color.A==0.8)
        ''')

    def test_native_pedestal_and_item_position_survive_void_before_and_after_morph(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','void_dagger'); local p=spawned[1]
            p.SpriteOffset=Vector(7,-13)
            p.sprite.Offset=Vector(3,4); p.sprite.Scale=Vector(1.2,0.9); p.sprite.Rotation=15
            local originalColor=p.sprite.Color
            for tick=1,180 do
                p.Position=Vector(320+tick/4,180+tick/8)
                p.sprite.frame=tick; p.sprite.itemPos=Vector(tick%3,-6-tick%5)
                event(1); drawings={}; event(2)
                assert(p.sprite.Color==originalColor and p.sprite:GetLayer(0):IsVisible(), 'native pedestal stays visible')
                for _,id in ipairs({2,3,4,5}) do assert(p.sprite:GetLayer(id):IsVisible()) end
                for _,d in ipairs(drawings) do
                    if d.native==p.sprite then
                        assert(d.layer==1 and d.alpha==0.8)
                        assert(math.abs(d.pos.X-(p.Position.X+7))<0.00001)
                        assert(math.abs(d.pos.Y-(p.Position.Y-13))<0.00001)
                        assert(d.scale.X==1.2 and d.scale.Y==0.9 and d.rotation==15)
                    end
                end
            end
            assert(#morphs==1 and W.isRunning() and p.sprite:GetLayer(1):IsVisible())
            event(6,'conch_morph','stop'); assert(not p:Exists() and #errors==0)
        ''')

    def test_borrowed_sprite_values_restore_after_every_effect_frame_and_completion(self):
        self.lua.execute('''
            for _,row in ipairs(V.catalog) do
                if V.isApplied(row.key) then
                    local p=pickup(); local s=borrowSpriteProperties(p.sprite)
                    s.Color=Color(.7,.8,.9,.8,.03,.04,.05); s.Color.colorize=.45
                    s.Scale=Vector(1.2,.9); s.Rotation=17
                    local expected=Color.Lerp(s.Color,s.Color,0)
                    local function restored()
                        assert(s.Color==expected, row.key..' left temporary tint/alpha on the native pickup')
                        assert(s.Scale.X==1.2 and s.Scale.Y==.9 and s.Rotation==17,
                            row.key..' left temporary native transforms')
                        assert(s:GetLayer(0):IsVisible(), 'pedestal remains visible')
                    end
                    local state={}; local custom=T.forItem(row.key,'positive')
                    local before=custom.onBeforeChange(p.Position,p,state)
                    for i=1,before+3 do
                        T.updateAllAnimations()
                        T.renderAllAnimations(); restored()
                        T.renderAllAnimations(); restored()
                    end
                    T.cancelForPickup(p); restored()
                    p.SubType=999
                    local after=custom.onAfterChange(p.Position,p,state)
                    for i=1,after+1 do
                        T.updateAllAnimations()
                        T.renderAllAnimations(); restored()
                        T.renderAllAnimations(); restored()
                    end
                    assert(#T._activeAnimations==0 and s:GetLayer(1):IsVisible())
                end
            end
            assert(#errors==0)
        ''')

    def test_borrowed_original_color_restores_default_templates_and_interruptions(self):
        self.lua.execute('''
            for _,key in ipairs({'positive','neutral','negative','DRAGON'}) do
                for _,finish in ipairs({'complete','cancel','render-error','room','exit'}) do
                    local p=pickup(); local s=borrowSpriteProperties(p.sprite)
                    s.Color=Color(.7,.8,.9,.6,.03,.04,.05); s.Color.colorize=.45
                    local expected=Color.Lerp(s.Color,s.Color,0)
                    local state={}; local custom=key=='DRAGON' and T.forItem(key,'positive') or T[key]
                    custom.onBeforeChange(p.Position,p,state)
                    for i=1,24 do T.updateAllAnimations(); T.renderAllAnimations() end
                    T.cancelForPickup(p)
                    assert(s.Color==expected, key..' original snapshot was mutated')
                    custom.onAfterChange(p.Position,p,state)
                    for i=1,3 do T.updateAllAnimations(); T.renderAllAnimations() end
                    if finish=='cancel' then T.cancelForPickup(p)
                    elseif finish=='room' then event(3)
                    elseif finish=='exit' then event(5)
                    elseif finish=='render-error' and key=='DRAGON' then
                        drawFails=true; T.renderAllAnimations(); drawFails=false
                        T.updateAllAnimations()
                    else for i=1,120 do T.updateAllAnimations(); T.renderAllAnimations() end end
                    assert(s.Color==expected and s:GetLayer(1):IsVisible(), key..' '..finish)
                    assert(s.Scale.X==1 and s.Scale.Y==1 and #T._activeAnimations==0)
                end
            end
        ''')

    def test_kronos_real_morph_reveals_opaque_result_after_swallow_with_borrowed_color(self):
        self.viewer()
        self.lua.execute('''
            for _,ownedPets in ipairs({0,1,3}) do
                entities={}
                for i=1,ownedPets do
                    local pet={Player=owner,InitSeed=i,pointerHash=700+i}
                    local sprite=Sprite(); sprite:Load('test_familiar.anm2'); sprite:SetFrame('FloatDown',0)
                    function pet:ToFamiliar() return self end
                    function pet:GetSprite() return sprite end
                    entities[#entities+1]=pet
                end
                event(6,'conch_morph','kronos')
                local p=spawned[#spawned]; local sprite=borrowSpriteProperties(p.sprite)
                sprite.Color=Color(1,1,1,1)
                event(1)
                local job=ConchBlessing._upgradeJobs[1]
                local visual,revealFrames,settledFrames
                revealFrames=0; settledFrames=0
                for tick=1,180 do
                    event(1); drawings={}; event(2)
                    visual=job.templateState.morphScene or visual
                    assert(sprite.Color.A==1, 'temporary swallow/reveal alpha leaked into the native item')
                    assert(sprite.Scale.X==1 and sprite.Scale.Y==1, 'swallow must not leave the result shrunk')
                    assert(sprite:GetLayer(0):IsVisible(), 'native pedestal stays visible')
                    if job.committed and job.templateState.upgradeAnim then
                        assert(p.SubType==ConchBlessing.ItemData.KRONOS.id)
                        revealFrames=revealFrames+1
                        assert(visual.impact==visual.devour.gone, 'no empty delay after mouth disappearance')
                        assert(sprite:GetLayer(1):IsVisible(), 'native result shows from the actual commit')
                        for _,draw in ipairs(drawings) do
                            assert(draw.native~=sprite, 'released item is drawn only by the engine')
                        end
                    elseif job.committed then
                        settledFrames=settledFrames+1
                        assert(sprite:GetLayer(1):IsVisible(), 'completed native Kronos remains visible')
                    end
                end
                assert(revealFrames>=9 and settledFrames>30)
                assert(#visual.pets==(ownedPets==0 and 3 or ownedPets))
                assert(W.isRunning() and p:Exists() and #T._activeAnimations==0 and #errors==0)
                event(6,'conch_morph','stop')
            end
        ''')

    def test_dragon_result_is_native_visible_from_commit_while_lightning_art_continues(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','dragon')
            local p=spawned[#spawned]; local s=borrowSpriteProperties(p.sprite)
            s.Color=Color(1,1,1,1)
            event(1); local job=ConchBlessing._upgradeJobs[1]
            while not job.committed do event(1) end
            local scene=job.templateState.morphScene
            assert(job.templateState.upgradeAnim, 'test the first post-commit frame, not completion')
            assert(s:GetLayer(1):IsVisible() and s.Color.A==1)
            assert(scene.pickupVisual.released and scene.frame>=scene.impact)
            -- An engine-drawn result must not depend on RenderLayer succeeding
            -- during the flash or on a later post-render visibility toggle.
            function s:RenderLayer() error('manual result rendering is forbidden') end
            for i=1,75 do
                assert(s:GetLayer(1):IsVisible(), 'visible in the native draw pass BEFORE post-render')
                drawings={}; event(2)
                for _,d in ipairs(drawings) do assert(d.native~=s) end
                event(1)
                assert(s.Color.A==1 and s:GetLayer(1):IsVisible())
            end
            assert(#errors==0 and #T._activeAnimations==0 and W.isRunning())
            event(6,'conch_morph','stop')
        ''')

    def test_released_result_is_not_rehidden_or_forced_visible_by_later_cleanup(self):
        self.lua.execute('''
            local p=pickup(); local state={}; local custom=T.forItem('DRAGON','positive')
            custom.onBeforeChange(p.Position,p,state); T.cancelForPickup(p)
            custom.onAfterChange(p.Position,p,state)
            assert(p.sprite:GetLayer(1):IsVisible())
            T.updateAllAnimations(); assert(p.sprite:GetLayer(1):IsVisible())
            -- A later native acquisition/foreign presentation now owns it.
            p.sprite:GetLayer(1):SetVisible(false)
            T.cancelForPickup(p)
            assert(not p.sprite:GetLayer(1):IsVisible())
        ''')

    def test_navigation_reuses_exact_position_until_viewer_is_closed(self):
        self.viewer()
        self.lua.execute('''
            local searches=0
            function room:FindFreePickupSpawnPosition(pos)
                searches=searches+1; return Vector(pos.X+40*searches,pos.Y+20*searches)
            end
            event(6,'conch_morph','liveeye'); local x,y=spawned[1].Position.X,spawned[1].Position.Y
            for _,key in ipairs({Keyboard.KEY_RIGHT,Keyboard.KEY_R,Keyboard.KEY_LEFT}) do
                for i=1,180 do event(1) end
                pressed[key]=true; event(2)
                assert(spawned[#spawned].Position.X==x and spawned[#spawned].Position.Y==y)
                assert(searches==1)
            end
            event(6,'conch_morph','stop'); event(6,'conch_morph','void_dagger')
            assert(searches==2 and #errors==0)
        ''')

    def test_missing_native_layer_api_falls_back_without_hiding_pedestal(self):
        self.lua.execute('''
            local p=pickup(); local state={}; p.sprite.GetLayerFrameData=nil
            local custom=T.forItem('VOID_DAGGER','positive')
            assert(custom.onBeforeChange(p.Position,p,state)==60 and state.morphFallback)
            assert(p.sprite:GetLayer(1):IsVisible() and p.sprite:GetLayer(0):IsVisible())
            for i=1,60 do T.updateAllAnimations() end
            assert(p.sprite.Color.original and #errors==1)
            T.cancelForPickup(p)
        ''')

    def test_item_frame_disappearance_releases_all_applied_visuals_to_native_animation(self):
        self.lua.execute('''
            for _,row in ipairs(V.catalog) do
                if V.isApplied(row.key) then
                    for _,phase in ipairs({'before','after'}) do
                        for _,firstCallback in ipairs({'render','update'}) do
                            for _,removeLayer in ipairs({false,true}) do
                                local p=pickup(); local s=borrowSpriteProperties(p.sprite)
                                local state={}; local custom=T.forItem(row.key,'positive')
                                local expected=Color.Lerp(s.Color,s.Color,0)
                                custom.onBeforeChange(p.Position,p,state)
                                if phase=='after' then
                                    T.cancelForPickup(p); p.SubType=999
                                    custom.onAfterChange(p.Position,p,state)
                                end
                                T.updateAllAnimations(); T.renderAllAnimations()
                                local getLayer,getFrame=s.GetLayer,s.GetLayerFrameData
                                -- Picked-up pedestals stay alive for their Collect
                                -- animation but no longer have an item-layer frame.
                                s:Play('Collect')
                                function s:GetLayerFrameData() return nil end
                                if removeLayer then function s:GetLayer() return nil end end
                                if firstCallback=='render' then T.renderAllAnimations() end
                                T.updateAllAnimations(); T.renderAllAnimations()
                                assert(s.Color==expected and s.Scale.X==1 and s.Scale.Y==1)
                                assert(s:GetAnimation()=='Collect', 'native acquisition keeps its own pose')
                                assert(#T._activeAnimations==0 and #errors==0, row.key..' '..phase..' '..firstCallback)
                                if not removeLayer then assert(s:GetLayer(1):IsVisible()) end
                                s.GetLayer=getLayer; s.GetLayerFrameData=getFrame
                            end
                        end
                    end
                end
            end
        ''')

    def test_all_shipped_result_images_have_visible_pixels(self):
        with contextlib.redirect_stdout(io.StringIO()):
            registry = parse_lua_file(ROOT / 'scripts/conch_blessing_items.lua')
        xml = ET.parse(ROOT / 'content/items.xml').getroot()
        configs = {node.get('name'): node for node in xml}
        for row in self.lua.globals().V.catalog.values():
            key = row.key
            with self.subTest(item=key):
                item = registry[key]
                directory = 'trinkets' if item['type'] == 'trinket' else 'collectibles'
                config = configs[item['name']]
                path = ROOT / 'resources' / xml.get('gfxroot') / directory / config.get('gfx')
                with Image.open(path) as image:
                    alpha = image.convert('RGBA').getchannel('A')
                    self.assertIsNotNone(alpha.point(lambda a: 255 if a >= 128 else 0).getbbox())
                    self.assertEqual(image.size, (32, 32))

    def test_all_real_morph_results_restore_visibility_with_actual_flags_and_borrowed_properties(self):
        source = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        for row in self.lua.globals().V.catalog.values():
            match = re.search(r'\b' + row.key + r'\s*=\s*{', source)
            body = source[match.end():find_matching_brace(source, match.end()-1)]
            for field in ('type', 'flag'):
                value = re.search(r'\b' + field + r'\s*=\s*"([^"]+)"', body)[1]
                self.lua.globals().ConchBlessing.ItemData[row.key][field] = value
        self.viewer()
        self.lua.execute('''
            checked=0
            for _,row in ipairs(V.catalog) do
                for _,newSprite in ipairs({false,true}) do
                    event(6,'conch_morph',string.lower(row.key))
                    local p=spawned[#spawned]
                    p.sprite=borrowSpriteProperties(p.sprite)
                    p.sprite.Color=Color(1,1,1,1); p.sprite.Scale=Vector(1.2,.9)
                    local nativeMorph=p.Morph
                    function p:Morph(...)
                        nativeMorph(self,...)
                        if newSprite then
                            self.sprite=borrowSpriteProperties(Sprite())
                            self.sprite.Scale=Vector(1.2,.9)
                        end
                    end
                    event(1); local job=ConchBlessing._upgradeJobs[1]
                    local id=p.Variant==350 and 0 or 1
                    local restoredTicks=0; local customDrawn=false
                    local firstMessage=#messages
                    for tick=1,250 do
                        event(1); drawings={}; event(2); event(2)
                        local s=p.sprite
                        assert(s.Color.A==1, row.key..' native alpha was not restored')
                        assert(s.Scale.X==1.2 and s.Scale.Y==.9, row.key..' native scale was not restored')
                        if p.Variant==100 then assert(s:GetLayer(0):IsVisible()) end
                        if job.committed then
                            for _,draw in ipairs(drawings) do
                                if draw.native==s and draw.alpha>.99 then customDrawn=true end
                            end
                            if not job.templateState.upgradeAnim then
                                restoredTicks=restoredTicks+1
                                assert(s:GetLayer(id):IsVisible(), row.key..' final native layer remains hidden')
                                assert(s.Color==Color(1,1,1,1), row.key..' final tint remains modified')
                            end
                        end
                    end
                    assert(job.status=='complete' and restoredTicks>30)
                    assert(not row.effect or row.nativeResult or customDrawn, row.key..' never draws the revealed result')
                    assert(p.SubType==ConchBlessing.ItemData[row.key].id and W.isRunning())
                    assert(#errors==0 and #T._activeAnimations==0)
                    local displayLogs=0
                    for i=firstMessage+1,#messages do
                        if messages[i]:find('DISPLAY ',1,true) then
                            displayLogs=displayLogs+1
                            assert(messages[i]:find('alpha=1.000 scale=1.200,0.900',1,true))
                            assert(messages[i]:find('layerVisible=true frame=present',1,true))
                        end
                    end
                    assert(displayLogs==1, 'one post-animation property report per preview')
                    checked=checked+1
                    event(6,'conch_morph','stop')
                end
            end
            assert(checked==#V.catalog*2)
        ''')

    def test_native_render_failure_restores_layer_visibility_color_scale_and_rotation(self):
        self.lua.execute('''
            local p=pickup(); local state={}; local s=p.sprite
            local originalColor,originalScale=s.Color,s.Scale
            s.Rotation=23; s.Offset=Vector(2,6)
            T.forItem('FIRE_BREATH','positive').onBeforeChange(p.Position,p,state)
            function s:RenderLayer() error('native layer draw failed') end
            T.renderAllAnimations(); T.updateAllAnimations()
            assert(s.Color==originalColor and s.Scale.X==originalScale.X and s.Scale.Y==originalScale.Y and s.Rotation==23)
            assert(s.Offset.X==2 and s.Offset.Y==6 and s:GetLayer(1):IsVisible())
            assert(s:GetLayer(0):IsVisible() and #T._activeAnimations==0 and #errors==1)
        ''')

    def test_originally_hidden_item_layer_remains_hidden_after_cancellation(self):
        self.lua.execute('''
            local p=pickup(); p.sprite:GetLayer(1):SetVisible(false)
            T.forItem('VOID_DAGGER','positive').onBeforeChange(p.Position,p,{})
            T.renderAllAnimations()
            T.cancelForPickup(p)
            assert(not p.sprite:GetLayer(1):IsVisible() and p.sprite:GetLayer(0):IsVisible() and #errors==0)
        ''')

    def test_trinket_native_pose_and_reinitialized_sprite_are_bound_per_phase(self):
        self.lua.execute('''
            local p=pickup(); p.Variant=350; p.SpriteOffset=Vector(4,-3)
            local before=p.sprite; local state={}; local custom=T.forItem('TIME_POWER','positive')
            custom.onBeforeChange(p.Position,p,state); T.renderAllAnimations()
            assert(not before:GetLayer(0):IsVisible() and before:GetLayer(1):IsVisible())
            local found=false
            for _,d in ipairs(drawings) do
                if d.native==before then
                    assert(d.layer==0 and d.pos.X==324 and d.pos.Y==177); found=true
                end
            end
            assert(found)
            T.cancelForPickup(p); assert(before:GetLayer(0):IsVisible())
            -- Morph/provider reinitialization can replace the entire sprite.
            p.sprite=Sprite(); p.sprite.Offset=Vector(-2,9); p.SubType=456
            custom.onAfterChange(p.Position,p,state); drawings={}; T.renderAllAnimations()
            found=false
            for _,d in ipairs(drawings) do
                assert(d.native~=before)
                if d.native==p.sprite then
                    assert(d.layer==0 and d.pos.X==324 and d.pos.Y==177); found=true
                end
            end
            assert(found and not p.sprite:GetLayer(0):IsVisible())
            T.cancelForPickup(p); assert(p.sprite:GetLayer(0):IsVisible() and #errors==0)
        ''')

    def test_conversion_chain_does_not_inherit_invisible_color(self):
        self.lua.execute('''
            p=pickup(); a={}; b={}; c=T.forItem('FIRE_BREATH','positive')
            c.onBeforeChange(p.Position,p,a); T.cancelForPickup(p); c.onAfterChange(p.Position,p,a)
            assert(not p.sprite:GetLayer(1):IsVisible() and p.sprite.Color.A==0.8)
            c.onBeforeChange(p.Position,p,b); T.cancelForPickup(p)
            assert(p.sprite.Color.original and p.sprite.Color.A==0.8)
        ''')

    def test_reroll_during_after_animation_releases_the_changed_pickup(self):
        self.lua.execute('''
            p=pickup(); a={}; c=T.forItem('DRAGON','positive')
            c.onBeforeChange(p.Position,p,a); T.cancelForPickup(p); c.onAfterChange(p.Position,p,a)
            p.SubType=999; T.updateAllAnimations()
            assert(p.sprite.Color.original and #T._activeAnimations==0)
        ''')

    def test_concurrent_pickup_cancellation_and_all_boundaries(self):
        for boundary in (3, 4, 5):
            self.lua.execute(f'''
                p=pickup(); q=pickup(); a={{}}; b={{}}; c=T.forItem('ICE_BREATH','positive')
                c.onBeforeChange(p.Position,p,a); c.onBeforeChange(q.Position,q,b)
                T.cancelForPickup(p); assert(p.sprite:GetLayer(1):IsVisible() and not q.sprite:GetLayer(1):IsVisible())
                event({boundary}); assert(q.sprite.Color.original and #T._activeAnimations==0)
            ''')

    def test_missing_assets_fall_back_and_render_failure_unhides(self):
        self.lua.execute('''
            p=pickup(); state={}; missing='conch_upgrade_ice'
            local custom=T.forItem('ICE_BREATH','positive')
            assert(custom.onBeforeChange(p.Position,p,state)==60 and state.morphFallback and #errors==1)
            T.cancelForPickup(p); missing=nil; state={}
            custom.onBeforeChange(p.Position,p,state); drawFails=true
            T.renderAllAnimations(); T.updateAllAnimations()
            assert(p.sprite.Color.original and #T._activeAnimations==0 and #errors==2)
        ''')

    def test_cues_only_advance_on_updates_and_missile_shakes_once(self):
        self.lua.execute('''
            local s=V.create('SOFLAM',Vector(320,180))
            for i=1,10 do V.render(s) end
            assert(#sounds==0 and s.frame==0)
            for i=1,102 do V.update(s) end
            assert(#sounds==5 and shakes==1)
            assert(sounds[1]==SoundEffect.SOUND_BEEP and sounds[2]==sounds[1] and sounds[3]==sounds[1])
            assert(pitches[1]<pitches[2] and pitches[2]<pitches[3])
            assert(sounds[4]==SoundEffect.SOUND_ROCKET_LAUNCH and sounds[5]==SoundEffect.SOUND_BOSS1_EXPLOSIONS)
            local after=V.create('SOFLAM',Vector(320,180),100,1,53)
            V.update(after); V.update(after); assert(shakes==2 and #sounds==7)
            assert(sounds[6]~=SoundEffect.SOUND_BEEP and sounds[7]~=SoundEffect.SOUND_BEEP)
            SoundEffect.SOUND_BEEP=nil
            local compatible=V.create('SOFLAM',Vector(320,180)); for i=1,60 do V.update(compatible) end
            assert(#errors==0)
        ''')

    def test_correct_origin_type_golden_normalization_and_aliases(self):
        self.lua.execute('''
            local s=V.create('TIME_TEAR',Vector(320,180),350,32768+39)
            assert(s.before.sheet=='t39.png' and s.sourceVariant==350)
            assert(V.resolveKey('liveeye')=='LIVE_EYE' and V.resolveKey('live_eye')=='LIVE_EYE')
            assert(V.resolveKey('liveeye trailing')==nil)
            assert(T.forItem('KRONOS','positive')~=T.positive)
            for _,key in ipairs({'F_MINUS','C_MINUS','B_MINUS','A_MINUS','ATROPOS'}) do
                assert(not V.isApplied(key))
                assert(T.forItem(key,'positive')==T.positive)
            end
        ''')

    def viewer(self):
        self.lua.execute('''
            ConchBlessing.printDebug=function() end
            ConchBlessing.ItemDataReady=true
            ModCallbacks.MC_PRE_PICKUP_COLLISION=10
            ModCallbacks.MC_POST_NEW_LEVEL=11
            ModCallbacks.MC_PRE_CHANGE_ROOM=12
            ModCallbacks.MC_PRE_MOD_UNLOAD=13
            EntityType={ENTITY_PICKUP=5}
            SoundEffect.SOUND_POWERUP_SPEWER=16
            function room:FindFreePickupSpawnPosition(pos) return Vector(pos.X,pos.Y) end
            spawned={}; titles={}; morphs={}
            function GetPtrHash(entity) return assert(entity.pointerHash) end
            EntityPtr=setmetatable({}, {__call=function(_,entity)
                if pointerFails then error('reference unavailable') end
                local generation=entity.generation
                return setmetatable({}, {__index=function(_,key)
                    if key=='Ref' and entity:Exists() and entity.generation==generation then return entity end
                end})
            end})
            ConchBlessing.EID={showItemText=function(item) titles[#titles+1]=item.id end}
            MagicConch={API={Config={deleteMode=true},IsReady=function() return true end,
                RegisterCallback=function(fn) actualConchResult=fn; return true end}}
            Isaac.Spawn=function(t,v,id,pos,velocity,spawner)
                assert(t==5, 'no combat entities')
                if spawnFails then error('spawn failure') end
                local p=pickup(id)
                p.Type=t; p.Variant=v; p.Position=pos; p.InitSeed=500+#spawned; p.FrameCount=0
                p.pointerHash=10000+#spawned
                p.generation=0
                p.data={}; p.Wait=0; p.Timeout=-1; p.Touched=false; p.State=0
                p.ShopItemId=-1; p.Price=0; p.AutoUpdatePrice=true; p.OptionsPickupIndex=0
                function p:ToPickup()
                    return setmetatable({}, {__index=p,__newindex=function(_,k,v) p[k]=v end})
                end
                function p:ToFamiliar() return nil end
                function p:GetData() return self.data end
                function p:IsShopItem() return self.ShopItemId~=-1 end
                function p:Remove() self.alive=false; self.removals=(self.removals or 0)+1 end
                function p:Morph(kind,variant,subtype,keepPrice,keepSeed,ignoreModifiers)
                    assert(keepPrice and keepSeed and ignoreModifiers, 'production morph arguments')
                    if morphFails then error('morph failure') end
                    morphs[#morphs+1]={pickup=self,from=self.SubType,to=subtype}
                    self.Type=kind; self.Variant=variant; self.SubType=subtype
                    -- A native reinitialization/provider may replace GetData.
                    -- Ownership must survive without relying on its contents.
                    self.data={}
                    -- Morph can reinitialize the entity even with KeepSeed.
                    -- The old EntityPtr expires although the call's pickup
                    -- remains usable. A new reference must be bound at Morph.
                    self.generation=self.generation+1
                end
                spawned[#spawned+1]=p
                entities[#entities+1]=p
                if spawnReplaced then p.SubType=999 end
                return p
            end
            require('scripts.conch_blessing_upgrade')
            W=ConchBlessing.morphViewer
        ''')

    def test_isaac_sandbox_start_tick_replay_select_stop_without_package(self):
        self.viewer()
        self.lua.execute('''
            assert(package==nil)
            event(6,'conch_morph',''); assert(W.isRunning())
            for i=1,3 do event(1); event(2) end
            pressed[82]=true; event(2)
            pressed[262]=true; event(2); assert(W.index==2)
            event(1); event(2)
            event(6,'conch_morph','stop')
            assert(not W.isRunning() and event(7,nil,0,16)==nil and #errors==0)
        ''')

    def test_viewer_selection_replay_wrapping_unknown_and_stop(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','liveeye'); assert(W.isRunning() and W.index==1)
            pressed[263]=true; event(2); assert(W.index==#V.catalog)
            pressed[262]=true; event(2); assert(W.index==1)
            pressed[82]=true; event(2); assert(W.index==1 and W.isRunning())
            event(6,'conch_morph','liveeye trailing'); assert(W.index==1)
            event(6,'conch_morph','stop'); assert(not W.isRunning())
            event(6,'conch_morph','soflam'); assert(W.index==16)
            pressed[259]=true; event(2); assert(not W.isRunning())
        ''')

    def test_viewer_input_scope_pause_and_transitions(self):
        self.viewer()
        self.lua.execute('''
            assert(event(7,nil,0,16)==nil)
            event(6,'conch_morph',''); assert(event(7,nil,0,16)==false)
            assert(event(7,nil,2,16)==0 and event(7,nil,1,4)==false)
            assert(event(7,nil,0,99)==nil)
            paused=true; pressed[262]=true; event(2); assert(W.index==1)
            pressed={}; paused=false; event(3); assert(not W.isRunning())
            assert(event(7,nil,0,16)==nil)
            event(6,'conch_morph',''); event(4); assert(not W.isRunning())
            event(6,'conch_morph',''); event(5); assert(not W.isRunning())
        ''')

    def test_viewer_releases_capture_on_errors_and_test_suite(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph',''); drawFails=true; event(2)
            assert(not W.isRunning() and event(7,nil,0,16)==nil)
            drawFails=false; event(6,'conch_morph','')
            benchRunning=true
            event(1); assert(not W.isRunning())
            event(6,'conch_morph',''); assert(not W.isRunning())
        ''')

    def test_no_repentogon_floor_hook_still_runs(self):
        self.lua.execute('ModCallbacks.MC_PRE_BACKDROP_RENDER_WATER=nil')
        self.viewer()
        self.lua.execute("event(6,'conch_morph','moneytear'); event(1); event(2); assert(W.isRunning() and #errors==0)")

    def test_localized_font_hud_and_hud_failure_release_input(self):
        self.lua.execute('''
            hudText={}
            testModules['scripts.conch_blessing_config']={GetCurrentLanguage=function() return 'kr' end}
            function KColor(...) return {...} end
            Font=setmetatable({}, {__call=function() return {
                Load=function() end,IsLoaded=function() return true end,
                GetStringWidthUTF8=function(_,s) return #s*3 end,
                DrawStringScaledUTF8=function(_,s)
                    if hudFailure then error('HUD failure') end
                    hudText[#hudText+1]=s
                end} end})
        ''')
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','soflam'); event(2)
            assert(W.isRunning() and #hudText>0)
            local found=false
            for _,s in ipairs(hudText) do if s=='인게임 적용' then found=true end end
            assert(found)
            hudFailure=true; event(2); assert(not W.isRunning() and event(7,nil,0,16)==nil)
        ''')

    def test_html_approval_list_exactly_matches_runtime_catalog(self):
        html = (ROOT/'docs/previews/item-upgrade-player.html').read_text(encoding='utf-8')
        rows = json.loads(re.search(r'id="upgrade-data"[^>]*>(.*?)</script>', html, re.S)[1])
        catalog = self.lua.globals().V.catalog
        for index, row in enumerate(rows, 1):
            self.assertEqual(row['key'], catalog[index].key)
            self.assertEqual(row['applied'], bool(catalog[index].effect))
        self.assertEqual(sum(row['applied'] for row in rows), 12)
        self.assertFalse(next(row['applied'] for row in rows if row['key'] == 'ATROPOS'))
        self.assertIn('id="filter-applied"', html)
        self.assertIn('id="filter-pending"', html)

    def test_devour_freezes_only_owners_pets_and_preserves_live_sprites(self):
        self.lua.execute('''
            local foreign={InitSeed=456}
            local live=Sprite(); live:Load('modded-pet.anm2'); live:SetFrame('FloatDown',3)
            live.sheet='modded-replacement.png'
            function live:Copy()
                local result=Sprite(); result:Load(self.path); result:SetFrame(self.animation,self.frame)
                result.sheet=self.sheet; return result
            end
            local pet={Player=owner,InitSeed=22,GetSprite=function() return live end}
            local other={Player=foreign,InitSeed=11,GetSprite=function() error('foreign pet was read') end}
            entities={{ToFamiliar=function() return pet end},{ToFamiliar=function() return other end}}
            local s=V.create('KRONOS',Vector(320,180))
            assert(s.petSource=='owned' and #s.pets==1 and s.pets[1]~=live)
            assert(s.pets[1].sheet=='modded-replacement.png')
            entities={}; live:SetFrame('ShootDown',9)
            for f=0,s.duration do s.frame=f; V.render(s) end
            assert(s.pets[1].animation=='FloatDown' and s.pets[1].frame==3)
            assert(live.animation=='ShootDown' and live.frame==9 and live.Scale.X==1 and live.Scale.Y==1)
            local empty=V.create('KRONOS',Vector(320,180))
            assert(empty.petSource=='random' and #empty.pets==3 and empty.impact>s.impact)
            assert(empty.pets[1].path~=empty.pets[2].path and empty.pets[2].path~=empty.pets[3].path)
            players=2
            local unknown=V.create('KRONOS',Vector(320,180))
            assert(unknown.petSource=='unknown' and #unknown.pets==0)
            local explicit=V.create('KRONOS',Vector(320,180),nil,nil,nil,owner)
            assert(explicit.petSource=='random' and #explicit.pets==3)
        ''')

    def test_devour_copy_fallback_and_unreadable_owned_roster_never_fills_random(self):
        self.lua.execute('''
            local live=Sprite(); live:Load('original-familiar.anm2'); live:SetFrame('FloatDown',5)
            local pet={Player=owner,InitSeed=22,GetSprite=function() return live end}
            entities={{ToFamiliar=function() return pet end}}
            local s=V.create('KRONOS',Vector(320,180))
            assert(#s.pets==1 and s.pets[1].path==live.path and s.pets[1].frame==5)
            missing='original-familiar'
            local failed=V.create('KRONOS',Vector(320,180))
            assert(failed.petSource=='owned' and #failed.pets==0 and #errors==1)
        ''')

    def test_devour_mouth_closes_before_reveal_and_actual_transaction_restores(self):
        self.lua.execute('''
            local s=V.create('KRONOS',Vector(320,180))
            assert(s.devour.open>58 and s.impact>s.devour.closed)
            for f=s.devour.swallowed,s.impact-1 do
                drawings={}; s.frame=f; V.render(s)
                for _,d in ipairs(drawings) do assert(d.sheet~=s.before.sheet and d.sheet~=s.after.sheet) end
            end
            p=pickup(); state={}; local custom=T.forItem('KRONOS','positive')
            local before=custom.onBeforeChange(p.Position,p,state)
            for i=1,before+20 do T.updateAllAnimations() end
            assert(state.morphScene.frame==before-1 and not p.sprite:GetLayer(1):IsVisible())
            T.cancelForPickup(p); p.SubType=555
            local after=custom.onAfterChange(p.Position,p,state)
            for i=1,after do T.updateAllAnimations(); T.renderAllAnimations() end
            assert(#T._activeAnimations==0 and p.sprite.Color.original)
        ''')

    def test_devour_suction_has_no_arms_spin_or_bff_bounce_and_rigid_jaws(self):
        self.lua.execute('''
            local D=require('scripts.lib.upgrade_devour')
            local s=V.create('KRONOS',Vector(320,180))
            local previous=100
            for f=s.devour.first,s.devour.first+20 do
                local p=D.petPose(s,1,f,320,158)
                local distance=(p.x-320)^2+(p.y-161)^2
                assert(distance<=previous*previous)
                previous=math.sqrt(distance)
            end
            for f=0,s.duration do
                s.frame=f; drawings={}; V.render(s)
                for _,d in ipairs(drawings) do
                    assert(not d.path:find('conch_upgrade_pixel'), 'no hands or grabbing lines')
                    assert(d.rotation==0, 'no cartoon spin')
                    if d.sheet==s.before.sheet and f<s.devour.swallow then
                        assert(d.scale.X==1 and d.scale.Y==1)
                    end
                    if d.path:find('maw_upper') or d.path:find('maw_lower') then
                        assert(d.scale.X==d.scale.Y, 'teeth must not squash')
                    end
                end
            end
            local open=D.mawPose(s,s.devour.swallow)
            local shut=D.mawPose(s,s.devour.closed)
            assert(open.gape==1 and shut.gape==0 and open.width==shut.width)
            assert(open.width>=3*32 and open.yOffset==0 and shut.yOffset==0)
            assert(s.devour.closed-s.devour.open<=6 and s.devour.gone-s.devour.open<=10)
            assert(D.mawPose(s,s.devour.gone).alpha==0 and s.impact==s.devour.gone)
            -- Depth is proved by draw order, not merely a fixed screen Y.
            s.frame=s.devour.open+1; drawings={}; V.render(s)
            assert(drawings[#drawings].sheet==s.before.sheet, 'mouth appears behind the heart')
            s.frame=s.devour.close+1; drawings={}; V.render(s)
            local sourceIndex,lastJaw
            for i,d in ipairs(drawings) do
                if d.sheet==s.before.sheet then
                    sourceIndex=i; assert(d.pos.X==320 and d.pos.Y==158)
                    assert(d.scale.X==d.scale.Y, 'heart recedes into depth without vertical dragging')
                end
                if d.path:find('maw_upper') then lastJaw=i end
            end
            assert(sourceIndex and lastJaw>sourceIndex, 'jaws cross in front only during the bite')
            for f=s.devour.gone,s.duration do
                s.frame=f; drawings={}; V.render(s)
                for _,d in ipairs(drawings) do assert(not d.path:find('maw_'), 'no lingering mouth') end
            end
            sounds={}; shakes=0; s.frame=0
            for f=1,s.duration do V.update(s) end
            local bites=0
            for _,sound in ipairs(sounds) do if sound==SoundEffect.SOUND_BONE_SNAP then bites=bites+1 end end
            assert(bites==1, 'only the final mouth bites; BFF does not chew')
            assert(#sounds==2 and sounds[1]==SoundEffect.SOUND_PORTAL_OPEN)
            assert(sounds[2]==SoundEffect.SOUND_BONE_SNAP and shakes==1)
        ''')

    def test_authored_jaws_leave_center_throat_open_in_front_of_bff(self):
        for part in ('upper', 'lower', 'sides'):
            tree = ET.parse(ROOT / f'resources/gfx/effects/conch_upgrade_maw_{part}.anm2')
            self.assertEqual(tree.find('.//Spritesheet').get('Path'), 'conch_upgrade_maw.png')
            for f in tree.findall('.//LayerAnimation/Frame'):
                px, py, w, h = [float(f.get(k)) for k in ('XPivot', 'YPivot', 'Width', 'Height')]
                self.assertFalse(-px <= 0 < w-px and -py <= 0 < h-py,
                                 'opaque throat crop would hide the heart before the bite')

    def test_flood_uses_per_frame_floor_pass_and_fades_without_mutating_room(self):
        self.viewer()
        self.lua.execute('''
            assert(callbacks[9]==nil)
            event(6,'conch_morph','moneytear')
            for i=1,30 do event(1) end
            drawings={}; event(8); assert(#drawings==9); local first=drawings[1].alpha
            for i=1,40 do event(1) end
            drawings={}; event(8); assert(#drawings==9 and drawings[1].alpha>first)
            for i=1,80 do event(1) end
            drawings={}; event(8); assert(#drawings==0)
            event(6,'conch_morph','stop'); event(8); assert(#drawings==0)
        ''')

    def test_rain_strikes_accumulate_tint_only_before_conversion_and_replay_resets(self):
        self.lua.execute('''
            for _,key in ipairs({'MONEY_TEAR','TIME_TEAR'}) do
                local s=V.create(key,Vector(320,180))
                local function at(f)
                    s.frame=f; drawings={}; V.render(s)
                    for _,d in ipairs(drawings) do
                        if d.sheet==s.before.sheet or d.sheet==s.after.sheet then return d end
                    end
                    error('missing item')
                end
                assert(at(13).color.BO==0, 'original color before the first hit')
                for _,landing in ipairs({14,22,30,38,46}) do
                    local before=at(landing-1)
                    local struck=at(landing)
                    local after=at(landing+1)
                    assert(after.sheet==s.before.sheet and after.color.BO>struck.color.BO)
                    assert(after.color.R<struck.color.R and after.color.A==1)
                    assert(math.abs(at(landing+.001).color.BO-at(landing-.001).color.BO)<.001,
                        'landing must not jump the color value')
                    assert(after.color.BO-struck.color.BO>2*(struck.color.BO-before.color.BO),
                        'landing sharply accelerates color change')
                    assert(at(landing+7).color.BO>at(landing+5).color.BO,
                        'blue absorption continues between impacts')
                end
                local previous=0
                for f=15,s.impact-1 do
                    local wet=at(f).color.BO
                    assert(wet>previous and wet<=.35, 'continuous monotonic buildup')
                    previous=wet
                end
                assert(at(s.impact-1).color.BO==.35)
                for _,f in ipairs({s.impact,s.impact+1,s.duration}) do
                    local after=at(f)
                    assert(after.sheet==s.after.sheet and after.color.R==1 and after.color.G==1)
                    assert(after.color.B==1 and after.color.BO==0 and after.color.GO==0)
                end
                assert(at(0).color.R==1 and at(0).color.BO==0, 'replay cannot retain wetness')
            end
        ''')

    def test_rain_waiting_for_commit_stays_blue_and_cancellation_preserves_pickup_color(self):
        self.lua.execute('''
            for _,key in ipairs({'MONEY_TEAR','TIME_TEAR'}) do
                local p=pickup(); local state={}; local custom=T.forItem(key,'positive')
                local original=p.sprite.Color
                local function lastNativeColor()
                    for i=#drawings,1,-1 do
                        if drawings[i].native==p.sprite then return drawings[i].color end
                    end
                    error('native item was not rendered')
                end
                custom.onBeforeChange(p.Position,p,state)
                for i=1,90 do T.updateAllAnimations() end
                T.renderAllAnimations()
                assert(state.morphScene.frame==53 and lastNativeColor().BO>0)
                assert(original.original and original.A==0.8, 'source Color never mutated')
                T.cancelForPickup(p); assert(p.sprite.Color==original)
                p.SubType=456; custom.onAfterChange(p.Position,p,state); T.renderAllAnimations()
                assert(state.morphScene.frame==54 and lastNativeColor().BO==0)
                assert(lastNativeColor().R==1)
                event(3); assert(p.sprite.Color==original and #T._activeAnimations==0)
            end
        ''')

    def test_flame_tip_stays_fixed_and_grows_down_over_candle_with_sound_cues(self):
        render = self.lua.eval("""function(key, frame)
            local s=V.create(key,Vector(320,180)); s.frame=frame; drawings={}; V.render(s)
            return drawings[#drawings]
        end""")
        for key, effect, sheet in [('FIRE_BREATH', 'fire', 'red'), ('ICE_BREATH', 'ice', 'blue')]:
            frames = ET.parse(ROOT / f'resources/gfx/effects/conch_upgrade_{effect}.anm2').findall(
                './Animations/Animation/LayerAnimations/LayerAnimation/Frame')
            with Image.open(ROOT.parent.parent / f'extracted_resources/resources/gfx/effects/effect_005_fire_{sheet}.png') as image:
                bottoms = {}
                for tick in range(71):
                    draw = render(key, tick)
                    self.assertTrue(draw.path.endswith(f'conch_upgrade_{effect}.anm2'))
                    frame = frames[int(draw.frame)].attrib
                    x, y, w, h = (int(frame[k]) for k in ('XCrop', 'YCrop', 'Width', 'Height'))
                    bounds = image.convert('RGBA').crop((x, y, x+w, y+h)).getchannel('A').point(
                        lambda alpha: 255 if alpha > 64 else 0).getbbox()
                    # Measure the actual visible artwork, not merely Sprite.Position.
                    top = draw.pos.Y + (bounds[1] - int(frame['YPivot'])) * draw.scale.Y
                    bottom = draw.pos.Y + (bounds[3] - int(frame['YPivot'])) * draw.scale.Y
                    self.assertAlmostEqual(top, 144, places=5)
                    bottoms[tick] = bottom
                self.assertLess(bottoms[0], 152)  # tiny initial flame at the wick
                self.assertLess(bottoms[6], bottoms[18])
                self.assertLess(bottoms[18], bottoms[30])
                self.assertLess(bottoms[30], bottoms[42])
                self.assertGreater(bottoms[45], 170)  # wraps below the candle body
                self.assertLess(bottoms[70], bottoms[45])  # settles toward the result
        self.lua.execute('''
            for _,key in ipairs({'FIRE_BREATH','ICE_BREATH'}) do
                local s=V.create(key,Vector(320,180))
                sounds={}; s.frame=0
                for i=1,s.duration do V.update(s) end
                assert(sounds[1]==SoundEffect.SOUND_CANDLE_LIGHT and sounds[2]==SoundEffect.SOUND_FLAME_BURST)
                assert(#sounds==(key=='ICE_BREATH' and 3 or 2))
            end
        ''')

    def test_real_viewer_all_profiles_use_production_morph_and_leave_native_result(self):
        self.viewer()
        self.lua.execute('''
            for _,row in ipairs(V.catalog) do
                local startMorphs,startTitles=#morphs,#titles
                event(6,'conch_morph',string.lower(row.key))
                local p=spawned[#spawned]
                local sourceVariant,sourceId=V.origin(ConchBlessing.ItemData[row.key])
                assert(W.isRunning() and p.SubType==sourceId and p.Variant==sourceVariant)
                assert(p.FrameCount==0 and #ConchBlessing._upgradeJobs==0, 'native source initializes before queue')
                event(1); assert(#ConchBlessing._upgradeJobs==1)
                local job=ConchBlessing._upgradeJobs[1]
                assert(GetPtrHash(job.pickup)==GetPtrHash(p) and job.itemKey==row.key and job.status=='queued')
                event(1)
                assert(p.SubType==sourceId and #morphs==startMorphs and #titles==startTitles)
                assert(job.template==nil or job.template.onBeforeChange, 'actual template selected')
                for i=1,job.counter-1 do event(1) end
                assert(p.SubType==sourceId, 'source stays unchanged until actual commit')
                event(1)
                assert(job.committed and p.SubType==ConchBlessing.ItemData[row.key].id)
                assert(#morphs==startMorphs+1 and #titles==startTitles+1 and titles[#titles]==p.SubType)
                for i=1,180 do event(1) end
                assert(job.status=='complete' and #ConchBlessing._upgradeJobs==0 and #T._activeAnimations==0)
                assert(W.isRunning() and p:Exists() and p.sprite.Color.original, 'real pedestal remains after the animation')
                assert(event(10,p,nil)==true, 'fixture stays uncollectable after commit')
                event(6,'conch_morph','stop')
                assert(not p:Exists() and p.removals==1)
                assert(event(10,p,nil)==nil and not W.isRunning())
            end
            assert(#errors==0)
        ''')

    def test_real_viewer_targets_only_its_fixture_and_uses_same_conch_callbacks(self):
        self.viewer()
        self.lua.execute('''
            local id=ConchBlessing.ItemData.DRAGON.origin.id
            local unrelated=Isaac.Spawn(5,100,id,Vector(80,80),Vector(0,0),nil)
            unrelated.OptionsPickupIndex=7; unrelated.Price=15; unrelated.ShopItemId=4
            event(6,'conch_morph','dragon'); local own=spawned[#spawned]
            for i=1,160 do event(1) end
            assert(own.SubType~=id and unrelated.SubType==id and unrelated.Price==15)
            assert(event(10,unrelated,nil)==nil and #morphs==1)
            event(6,'conch_morph','stop')
            assert(unrelated:Exists() and unrelated.OptionsPickupIndex==7 and unrelated.removals==nil)
            MagicConch.API.Config.deleteMode=false
            actualConchResult({type='positive'})
            for i=1,160 do event(1) end
            assert(unrelated.SubType==own.SubType and #morphs==2)
            assert(unrelated.Price==15 and unrelated.ShopItemId==4 and unrelated.OptionsPickupIndex==7)
            assert(titles[1]==titles[2], 'both routes announce the committed target')
            assert(#errors==0)
        ''')

    def test_navigation_at_commit_boundaries_never_strands_pickups_or_animations(self):
        self.viewer()
        self.lua.execute('''
            for index,row in ipairs(V.catalog) do
                for _,stage in ipairs({'before','after','complete'}) do
                    for _,button in ipairs({263,262,82}) do
                        event(6,'conch_morph',string.lower(row.key))
                        local p=spawned[#spawned]
                        local sprite=borrowSpriteProperties(p.sprite)
                        sprite.Color=Color(1,1,1,1); sprite.Scale=Vector(1.1,.95)
                        event(1); event(1)
                        local job=ConchBlessing._upgradeJobs[1]
                        for i=1,job.counter-1 do event(1); event(2) end
                        assert(not job.committed, 'last tick before native morph')
                        if stage~='before' then
                            event(1); event(2)
                            assert(job.committed and next(p:GetData())==nil, 'morph reset fixture data')
                        end
                        if stage=='complete' then for i=1,180 do event(1); event(2) end end
                        assert(W.isRunning() and event(10,p,nil)==true)
                        local count=#morphs
                        pressed[button]=true; event(2)
                        local offset=button==263 and -1 or (button==262 and 1 or 0)
                        assert(W.index==(index+offset-1)%#V.catalog+1 and W.isRunning())
                        assert(not p:Exists() and p.removals==1, 'remove even after GetData was reset')
                        assert(sprite.Color==Color(1,1,1,1), row.key..' cancelled tint/alpha remains')
                        assert(sprite.Scale.X==1.1 and sprite.Scale.Y==.95)
                        assert(sprite:GetLayer(p.Variant==350 and 0 or 1):IsVisible())
                        assert(#ConchBlessing._upgradeJobs==0 and #T._activeAnimations==0)
                        local fresh=spawned[#spawned]
                        assert(fresh~=p and fresh:Exists() and event(10,fresh,nil)==true)
                        for _,entity in ipairs(spawned) do assert(entity==fresh or not entity:Exists()) end
                        event(6,'conch_morph','stop')
                        for i=1,180 do event(1) end
                        assert(#morphs==count and not fresh:Exists(), 'cancelled jobs cannot resume')
                    end
                end
            end
            assert(#errors==0)
        ''')

    def test_room_wide_results_and_preview_cancellation_are_isolated_in_both_directions(self):
        self.viewer()
        self.lua.execute('''
            for i=1,10 do event(1) end -- provider registration
            for _,age in ipairs({0,12,47,200}) do
                event(6,'conch_morph','dragon'); local preview=spawned[#spawned]
                for i=1,age do event(1) end
                local queued=#ConchBlessing._upgradeJobs
                -- Covers not-yet-queued, before, after and completed fixtures.
                -- Delete mode must not delete a preview on a mismatching roll.
                actualConchResult({type='negative'})
                actualConchResult({type='positive'})
                assert(preview:Exists() and #ConchBlessing._upgradeJobs==queued)
                local real=Isaac.Spawn(5,100,ConchBlessing.ItemData.DRAGON.origin.id,Vector(80,80),Vector(0,0),nil)
                real.Price=15; real.ShopItemId=2; real.OptionsPickupIndex=8
                actualConchResult({type='positive'})
                local job
                for _,pending in ipairs(ConchBlessing._upgradeJobs) do
                    if GetPtrHash(pending.pickup)==GetPtrHash(real) then job=pending end
                end
                assert(job and not W.ownsPickup(real) and W.ownsPickup(preview))
                for i=1,8 do event(1) end
                local remaining,frame=job.counter,job.templateState.morphScene.frame
                pressed[262]=true; event(2)
                assert(not preview:Exists() and real:Exists() and job.status=='queued')
                assert(job.counter==remaining and job.templateState.morphScene.frame==frame)
                event(6,'conch_morph','stop')
                for i=1,180 do event(1) end
                assert(job.status=='complete' and job.committed and real.SubType==ConchBlessing.ItemData.DRAGON.id)
                assert(real.Price==15 and real.ShopItemId==2 and real.OptionsPickupIndex==8)
                assert(real.sprite.Color.original and event(10,real,nil)==nil)
                real:Remove()
            end
            assert(#errors==0 and #ConchBlessing._upgradeJobs==0 and #T._activeAnimations==0)
        ''')

    def test_preview_and_real_upgrade_share_timing_with_independent_visual_state(self):
        self.viewer()
        self.lua.execute('''
            for i=1,10 do event(1) end -- provider registration
            event(6,'conch_morph','dragon'); local preview=spawned[#spawned]
            event(1); local previewJob=ConchBlessing._upgradeJobs[1]
            local real=Isaac.Spawn(5,100,preview.SubType,Vector(80,80),Vector(0,0),nil)
            actualConchResult({type='positive'}); local realJob=ConchBlessing._upgradeJobs[2]
            assert(GetPtrHash(realJob.pickup)==GetPtrHash(real))
            for i=1,150 do
                event(1)
                assert(previewJob.phase==realJob.phase and previewJob.counter==realJob.counter)
                assert(previewJob.committed==realJob.committed and preview.SubType==real.SubType)
                assert(previewJob.templateState~=realJob.templateState)
                local a,b=previewJob.templateState.morphScene,realJob.templateState.morphScene
                assert(a~=b and a.frame==b.frame and a.assets~=b.assets and a.sounded~=b.sounded)
            end
            assert(previewJob.status=='complete' and realJob.status=='complete' and #titles==2)
            event(6,'conch_morph','stop'); assert(not preview:Exists() and real:Exists() and #errors==0)
        ''')

    def test_native_identity_survives_data_reset_and_distinct_callback_wrappers(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','voiddagger'); local p=spawned[#spawned]
            local wrapper=setmetatable({}, {__index=p, __newindex=p})
            assert(wrapper~=p and GetPtrHash(wrapper)==GetPtrHash(p))
            for i=1,180 do
                event(1)
                assert(W.isRunning() and event(10,wrapper,nil)==true)
            end
            local foreign=Isaac.Spawn(5,p.Variant,p.SubType,p.Position,Vector(0,0),nil)
            foreign.InitSeed=p.InitSeed
            assert(event(10,foreign,nil)==nil, 'same seed/type/position is not identity')
            p.data={foreignProvider={value=42}}
            event(1); assert(W.isRunning())
            event(6,'conch_morph','stop')
            assert(p.removals==1 and foreign:Exists() and foreign.removals==nil)
            assert(p.data.foreignProvider.value==42 and #errors==0)
        ''')

    def test_real_pickup_reroll_cancels_only_its_job_while_preview_finishes(self):
        self.viewer()
        self.lua.execute('''
            for i=1,10 do event(1) end
            event(6,'conch_morph','dragon'); local preview=spawned[#spawned]
            event(1); local previewJob=ConchBlessing._upgradeJobs[1]
            local real=Isaac.Spawn(5,100,preview.SubType,Vector(80,80),Vector(0,0),nil)
            actualConchResult({type='positive'}); local realJob=ConchBlessing._upgradeJobs[2]
            for i=1,12 do event(1) end
            real.SubType=999 -- another gameplay operation changed this pedestal
            event(1)
            assert(realJob.status=='cancelled' and previewJob.status=='queued')
            assert(real:Exists() and real.sprite.Color.original and W.isRunning())
            for i=1,160 do event(1) end
            assert(previewJob.status=='complete' and preview.SubType==ConchBlessing.ItemData.DRAGON.id)
            assert(real.SubType==999 and W.isRunning() and #titles==1 and #errors==0)
            event(6,'conch_morph','stop'); assert(real:Exists())
        ''')

    def test_expired_reference_does_not_claim_a_recycled_address(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','dragon'); local p=spawned[#spawned]
            p:Remove()
            local replacement=Isaac.Spawn(5,p.Variant,p.SubType,p.Position,Vector(0,0),nil)
            replacement.pointerHash=p.pointerHash; replacement.InitSeed=p.InitSeed
            assert(event(10,replacement,nil)==nil)
            event(1)
            assert(not W.isRunning() and replacement:Exists() and replacement.removals==nil)
            assert(p.removals==1 and #errors==1 and event(7,nil,0,16)==nil)
            pointerFails=true; event(6,'conch_morph','dragon')
            assert(not W.isRunning() and not spawned[#spawned]:Exists() and #errors==2)
            assert(replacement:Exists(), 'failed constructor removes only its fresh spawn')
        ''')

    def test_real_viewer_cancel_replay_pause_and_pre_transition_cleanup(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','dragon'); local first=spawned[#spawned]
            for i=1,18 do event(1) end
            local job=ConchBlessing._upgradeJobs[1]
            local f=job.templateState.morphScene.frame; local ticks=job.counter
            paused=true; for i=1,10 do event(1); event(2) end
            assert(job.counter==ticks and job.templateState.morphScene.frame==f and #morphs==0)
            paused=false; pressed[82]=true; event(2)
            assert(not first:Exists() and job.status=='cancelled' and #T._activeAnimations==0)
            local replacement=spawned[#spawned]; assert(replacement~=first and replacement.SubType==first.SubType)
            for i=1,160 do event(1) end
            assert(#morphs==1 and replacement.SubType==ConchBlessing.ItemData.DRAGON.id)
            for _,boundary in ipairs({12,3,4,5}) do
                event(6,'conch_morph','soflam'); local p=spawned[#spawned]
                for i=1,12 do event(1) end
                event(boundary)
                assert(not W.isRunning() and not p:Exists() and #ConchBlessing._upgradeJobs==0)
                assert(#T._activeAnimations==0 and event(7,nil,0,16)==nil)
                for i=1,150 do event(1) end
                assert(#morphs==1, 'cancelled preview cannot morph later')
            end
            event(6,'conch_morph','dragon'); local p=spawned[#spawned]
            event(13,{}); assert(W.isRunning() and p:Exists(), 'foreign mod unload does not own viewer')
            event(13,ConchBlessing); assert(not p:Exists() and not W.isRunning())
        ''')

    def test_real_viewer_failures_remove_fixture_without_inventory_or_other_jobs(self):
        self.viewer()
        self.lua.execute('''
            spawnFails=true; event(6,'conch_morph','dragon'); assert(not W.isRunning() and #spawned==0)
            spawnFails=false; spawnReplaced=true; event(6,'conch_morph','dragon')
            assert(not W.isRunning() and not spawned[#spawned]:Exists())
            spawnReplaced=false; event(6,'conch_morph','dragon'); local p=spawned[#spawned]
            morphFails=true; for i=1,65 do event(1) end
            assert(not p:Exists() and not W.isRunning() and #ConchBlessing._upgradeJobs==0 and #T._activeAnimations==0)
            morphFails=false; event(6,'conch_morph','dragon'); p=spawned[#spawned]
            for i=1,7 do event(1) end
            p.SubType=999; event(1)
            assert(not p:Exists() and not W.isRunning() and #ConchBlessing._upgradeJobs==0)
            local p2=Isaac.Spawn(5,100,ConchBlessing.ItemData.SOFLAM.origin.id,Vector(60,60),Vector(0,0),nil)
            local other=assert(ConchBlessing.upgrade.queuePickup(p2,'SOFLAM'))
            assert(not ConchBlessing.upgrade.queuePickup(p2,'SOFLAM'), 'duplicate refused')
            event(6,'conch_morph','dragon'); event(1); event(6,'conch_morph','stop')
            assert(p2:Exists() and other.status=='queued' and #ConchBlessing._upgradeJobs==1)
            for i=1,180 do event(1) end
            assert(other.committed and p2.SubType==ConchBlessing.ItemData.SOFLAM.id)
            ModCallbacks.MC_PRE_CHANGE_ROOM=nil
            local n=#spawned; event(6,'conch_morph','dragon')
            assert(not W.isRunning() and #spawned==n, 'missing cleanup capability fails before spawning')
        ''')

    def test_dragon_darkens_then_thunders_strikes_and_restores_scene_brightness(self):
        self.lua.execute('''
            game.Darken=function() error('cosmetic storm must not mutate game darkness') end
            local s=V.create('DRAGON',Vector(320,180))
            local function veils(frame)
                s.frame=frame; drawings={}; V.render(s)
                local found={}
                for _,d in ipairs(drawings) do
                    if d.scale.X==640 and d.scale.Y==360 then
                        assert(d.pos.X==0 and d.pos.Y==0)
                        found[#found+1]=d
                    end
                end
                return found
            end
            assert(#veils(0)==0)
            local function aperture(frame)
                veils(frame)
                for _,d in ipairs(drawings) do
                    if d.path:find('conch_upgrade_spotlight.anm2',1,true) then return d end
                end
            end
            local early=aperture(9).alpha
            local dark=aperture(20).alpha
            assert(early>0 and early<dark and dark<1)
            assert(#veils(44)==0 and #drawings==6, 'one aperture, four edge fills, no early lightning')
            local hit=veils(45)
            assert(#hit==1 and hit[1].color.R>0.9, 'darkness clears exactly on the strike')
            assert(drawings[1].sheet==s.after.sheet, 'conversion exactly at lightning')
            for f=45,s.duration do assert(not aperture(f), 'no darkness after lightning') end
            assert(#veils(52)==0 and #drawings==1, 'only the result remains after the brief flash')
            assert(#veils(75)==0 and #veils(s.duration)==0)
            s.frame=0; sounds={}; pitches={}
            for f=1,19 do V.update(s) end
            assert(#sounds==0)
            V.update(s); assert(#sounds==1 and sounds[1]==SoundEffect.SOUND_THUNDER and pitches[1]<1)
            for f=21,44 do V.update(s) end
            assert(#sounds==1)
            V.update(s); assert(#sounds==2 and sounds[2]==SoundEffect.SOUND_LIGHTBOLT and pitches[2]==1)
            for f=46,s.duration do V.update(s) end
            assert(#sounds==2, 'each cue plays once')
            sounds={}; pitches={}; local late=V.create('DRAGON',Vector(320,180),nil,nil,45)
            V.update(late); assert(#sounds==1 and sounds[1]==SoundEffect.SOUND_LIGHTBOLT and pitches[1]==1)
            SoundEffect.SOUND_LIGHTBOLT=nil
            sounds={}; V.update(V.create('DRAGON',Vector(320,180),nil,nil,45))
            assert(#sounds==0, 'missing lightning must not substitute thunder or a tech zap')
        ''')
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','dragon'); for i=1,24 do event(1) end
            drawings={}; event(2); assert(#drawings>1)
            event(6,'conch_morph','stop'); drawings={}; event(2); assert(#drawings==0)
            event(6,'conch_morph','dragon'); for i=1,24 do event(1) end
            event(3); drawings={}; event(2); assert(#drawings==0)
        ''')

    def test_storm_aperture_keeps_item_and_nearby_room_lit_and_covers_screen_edges(self):
        mask = Image.open(ROOT / 'resources/gfx/effects/conch_upgrade_spotlight.png').convert('RGBA')
        self.lua.globals().maskAlpha = lambda x, y: mask.getpixel((int(x), int(y)))[3] / 255
        self.lua.execute('''
            local s=V.create('DRAGON',Vector(320,180)); s.frame=24
            local function opacity(x,y)
                local clear=1
                for _,d in ipairs(drawings) do
                    local alpha=0
                    if d.path:find('conch_upgrade_spotlight.anm2',1,true) then
                        local mx,my=x-d.pos.X+80,y-d.pos.Y+80
                        if mx>=0 and mx<160 and my>=0 and my<160 then alpha=d.alpha*maskAlpha(mx,my) end
                    elseif d.path:find('conch_upgrade_pixel.anm2',1,true) then
                        assert(d.scale.X>0 and d.scale.Y>0)
                        if x>=d.pos.X and x<d.pos.X+d.scale.X and y>=d.pos.Y and y<d.pos.Y+d.scale.Y then
                            alpha=d.alpha
                        end
                    end
                    clear=clear*(1-alpha)
                end
                return 1-clear
            end
            drawings={}; V.render(s)
            assert(opacity(320,158)==0 and opacity(336,174)==0, 'whole icon stays readable')
            assert(opacity(338,158)==0, 'nearby floor is lit, not just the icon drawn again')
            local a,b,c=opacity(356,158),opacity(374,158),opacity(395,158)
            assert(a>0 and a<b and b<c and c<0.9, 'soft feather into surrounding darkness')
            for _,xy in ipairs({{320,180},{10,30},{630,350},{-100,180}}) do
                s.pos=Vector(xy[1],xy[2]); drawings={}; V.render(s)
                for x=0,639,19 do for y=0,359,17 do
                    if (x-xy[1])^2+(y-(xy[2]-22))^2>=80^2 then
                        assert(math.abs(opacity(x,y)-.88)<.0001, 'screen coverage has no hole or double-dark seam')
                    end
                end end
            end
            Isaac.GetScreenWidth=nil; Isaac.GetScreenHeight=nil
            s.pos=Vector(320,180); drawings={}; V.render(s)
            assert(math.abs(opacity(639,180)-.88)<.0001, 'older screen-size fallback')
        ''')

    def test_native_reticle_and_missile_never_decelerates_before_impact(self):
        self.lua.execute('''
            local s=V.create('SOFLAM',Vector(320,180)); local lastY,velocity=nil,0
            for f=s.impact-16,s.impact-1 do
                s.frame=f; drawings={}; V.render(s)
                local reticle,rocket
                for _,d in ipairs(drawings) do
                    if d.path=='gfx/1000.030_dr. fetus target.anm2' then reticle=d end
                    if d.path=='gfx/1000.031_dr. fetus rocket.anm2' then rocket=d end
                end
                assert(reticle and reticle.pos.Y==158 and rocket)
                assert(reticle.color.R==1 and reticle.color.G==0.12 and reticle.color.B==0.12)
                if lastY then assert(rocket.pos.Y-lastY>=velocity); velocity=rocket.pos.Y-lastY end
                lastY=rocket.pos.Y
            end
            assert(velocity>20)
            s.frame=s.impact; drawings={}; V.render(s)
            for _,d in ipairs(drawings) do assert(d.path~='gfx/1000.031_dr. fetus rocket.anm2') end
        ''')

    def test_clock_completes_one_smooth_turn_then_disappears(self):
        self.lua.execute('''
            local s=V.create('TIME_MONEY',Vector(320,180)); local rotations={}
            for f=s.impact-28,s.impact do
                s.frame=f; drawings={}; V.render(s)
                assert(drawings[1].sheet, 'item is behind the clock')
                local hand=drawings[4]
                assert(drawings[2].path:find('clock_rim') and drawings[3].path:find('clock_hour'))
                assert(hand.path:find('clock_minute') and hand.scale.X==2/3 and hand.scale.Y==2/3)
                rotations[#rotations+1]=hand.rotation
            end
            local total=0
            for i=2,#rotations do
                local step=(rotations[i]-rotations[i-1])%360
                assert(step>0 and step<20); total=total+step
            end
            assert(math.abs(total-360)<.001)
            s.frame=s.impact+11; drawings={}; V.render(s)
            assert(drawings[1].sheet==s.after.sheet)
            for _,d in ipairs(drawings) do
                assert(d.sheet or d.scale.X<2) -- only the small falling coin remains.
            end
        ''')

    def test_clock_fits_item_box_in_front_for_every_time_item(self):
        rim = ET.parse(ROOT / 'resources/gfx/effects/conch_upgrade_clock_rim.anm2').find('.//LayerAnimation/Frame').attrib
        for key in ('TIME_MONEY', 'TIME_POWER', 'TIME_TEAR', 'TIME_LUCK'):
            self.lua.globals().clockKey = key
            draw = self.lua.execute('''
                local s=V.create(clockKey,Vector(320,180)); s.frame=35; drawings={}; V.render(s)
                local itemIndex,rimIndex,rim
                for i,d in ipairs(drawings) do
                    if d.sheet==s.before.sheet then itemIndex=i end
                    if d.path:find('clock_rim') then rimIndex=i; rim=d end
                end
                assert(rimIndex>itemIndex, 'clock must overlap the item, not sit behind it')
                return rim
            ''')
            self.assertLessEqual(int(rim['Width']) * float(rim['XScale']) / 100 * draw.scale.X, 32)
            self.assertLessEqual(int(rim['Height']) * float(rim['YScale']) / 100 * draw.scale.Y, 32)

    def test_authored_clock_rim_has_a_transparent_item_window(self):
        path = ROOT / 'resources/gfx/effects/conch_upgrade_clock_rim.anm2'
        frame = ET.parse(path).find('.//LayerAnimation/Frame').attrib
        scale = float(frame['XScale']) / 100
        self.assertLessEqual(int(frame['Width']) * scale, 43)
        with Image.open(ROOT / 'resources/gfx/effects/conch_upgrade_clock.png') as image:
            x = int(frame['XCrop']) + int(frame['XPivot'])
            y = int(frame['YCrop']) + int(frame['YPivot'])
            # A 24px-diameter circular window stays open. A square's corners
            # fall outside that circle and legitimately intersect the dial ticks.
            radius = int(12 / scale)
            alpha = image.getchannel('A')
            self.assertLessEqual(max(alpha.getpixel((x+dx, y+dy))
                for dx in range(-radius, radius+1) for dy in range(-radius, radius+1)
                if dx*dx+dy*dy <= radius*radius), 16)

    def test_eligibility_tint_yields_until_the_whole_morph_finishes(self):
        self.viewer()
        self.lua.execute('''
            ModCallbacks.MC_POST_PICKUP_INIT=14; ModCallbacks.MC_POST_PICKUP_UPDATE=15
            local frame=0; function game:GetFrameCount() return frame end
            local H=require('scripts.conch_blessing_highlight')
            event(4)
            for _,key in ipairs({'LIVE_EYE','ANGELS_CROWN','TIME_LUCK','DRAGON','KRONOS'}) do
                local item=ConchBlessing.ItemData[key]
                local variant,origin=V.origin(item)
                local p=Isaac.Spawn(5,variant,origin,Vector(320,180))
                p.sprite=borrowSpriteProperties(p.sprite)
                p.sprite.Color=Color(0.8,0.7,0.6,0.9,0.01,0.02,0.03)
                p.sprite.Color.colorize=0.25
                local original=Color.Lerp(p.sprite.Color,p.sprite.Color,0)
                H.ScanRoom(frame); frame=frame+6; event(1)
                assert(p.sprite.Color~=original, 'fixture must start with a real eligibility pulse')
                local job=assert(ConchBlessing.upgrade.queuePickup(p,key))
                assert(p.sprite.Color==original, 'queue must restore exact tint before snapshot')
                -- Keep the result eligible too, as in chained upgrades. Native
                -- Morph must not restart a pulse when it replaces GetData.
                local prefix=variant==350 and 'T:' or 'C:'
                ConchBlessing.ItemMaps[prefix..item.id]={positive={}}
                local morph=p.Morph
                function p:Morph(...)
                    morph(self,...); event(14,self); H.ScanRoom(frame)
                    assert(not H._activePickups[tostring(GetPtrHash(self))])
                end
                local before,after=false,false
                for tick=1,220 do
                    frame=frame+1; event(1)
                    if ConchBlessing.upgrade.isAnimatingPickup(p) then
                        event(15,p); H.ScanRoom(frame)
                        assert(not H._activePickups[tostring(GetPtrHash(p))], key)
                        for _,anim in ipairs(T._activeAnimations) do
                            if GetPtrHash(anim.pickup)==GetPtrHash(p) then
                                assert(anim.originalColor==original, 'must not capture eligibility tint')
                                before=before or anim.phase=='before'
                                after=after or anim.phase=='after'
                            end
                        end
                    end
                    event(2)
                    if job.status=='complete' then break end
                end
                assert(job.status=='complete' and before and after)
                assert(not ConchBlessing.upgrade.isAnimatingPickup(p))
                H.ScanRoom(frame)
                assert(H._activePickups[tostring(GetPtrHash(p))], 'ordinary eligibility resumes after completion')
                H.StopForPickup(p); assert(p.sprite.Color==original)
                p:Remove()
            end
            assert(#errors==0)
        ''')

    def test_cancelled_morph_releases_only_its_eligibility_suppression(self):
        self.viewer()
        self.lua.execute('''
            ModCallbacks.MC_POST_PICKUP_INIT=14; ModCallbacks.MC_POST_PICKUP_UPDATE=15
            local frame=0; function game:GetFrameCount() return frame end
            local H=require('scripts.conch_blessing_highlight'); event(4)
            local item=ConchBlessing.ItemData.TIME_LUCK
            local variant,origin=V.origin(item)
            for _,ticks in ipairs({0,12,60}) do
                local p=Isaac.Spawn(5,variant,origin,Vector(320,180))
                local peer=Isaac.Spawn(5,variant,origin,Vector(350,180))
                local original=Color.Lerp(p.sprite.Color,p.sprite.Color,0)
                H.ScanRoom(frame)
                local job=assert(ConchBlessing.upgrade.queuePickup(p,'TIME_LUCK'))
                for tick=1,ticks do frame=frame+1; event(1); event(2) end
                assert(not H._activePickups[tostring(GetPtrHash(p))])
                assert(H._activePickups[tostring(GetPtrHash(peer))], 'unrelated eligibility stays active')
                ConchBlessing.upgrade.cancel(job)
                assert(not ConchBlessing.upgrade.isAnimatingPickup(p) and p.sprite.Color==original)
                H.ScanRoom(frame)
                if ticks<48 then assert(H._activePickups[tostring(GetPtrHash(p))]) end
                H.StopForPickup(p); H.StopForPickup(peer); p:Remove(); peer:Remove()
            end
            assert(#errors==0)
        ''')

    def test_time_luck_keeps_the_clock_without_extra_green_shapes(self):
        self.lua.execute('''
            local s=V.create('TIME_LUCK',Vector(320,180))
            local seenClock=false
            for f=0,s.duration do
                s.frame=f; drawings={}; V.render(s)
                for _,d in ipairs(drawings) do
                    assert(d.path~='gfx/effects/conch_upgrade_pixel.anm2', 'no extra rings above the item')
                    if d.path and d.path:find('conch_upgrade_clock') then seenClock=true end
                end
            end
            assert(seenClock)
        ''')

    def test_crown_reveals_all_colors_gradually_before_native_handoff(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','angelscrown')
            local history={}
            for tick=1,150 do
                event(1)
                assert(#T._activeAnimations<=1, 'before phase must be retired before after phase begins')
                local p=spawned[1]
                if p and not p.observed then
                    p.observed=true; p.sprite=borrowSpriteProperties(p.sprite)
                    local render=p.sprite.RenderLayer
                    function p.sprite:RenderLayer(id,pos)
                        local anim=T._activeAnimations[1]
                        if anim and anim.phase=='after' then
                            history[#history+1]={frame=anim.morphScene.frame,
                                color=Color.Lerp(self.Color,self.Color,0)}
                        end
                        render(self,id,pos)
                    end
                end
                event(2)
            end
            assert(#history>40)
            -- Test the rendered transfer for both dark outlines and pale
            -- crown highlights; additive clipping must not delay the reveal.
            for _,pixel in ipairs({0.05,0.45,0.9}) do
                local previous,changes=1,0
                for _,sample in ipairs(history) do
                    local c=sample.color
                    local value=pixel*c.R+c.RO
                    assert(value<=previous+0.000001 and value>=pixel-0.000001)
                    assert(previous-value<0.04, 'no abrupt color jump')
                    if value<previous-0.000001 then changes=changes+1 end
                    previous=value
                    assert(c.A==0.8, 'whitening preserves native alpha')
                end
                assert(changes>=40, 'light and dark pixels must both reveal throughout the fade')
                assert(math.abs(previous-pixel)<0.000001, 'fade finishes before native handoff')
            end
            local last=history[#history].color
            assert(last==spawned[1].sprite.Color)
            assert(#T._activeAnimations==0, 'no stale before animation may keep redrawing the result')
            assert(spawned[1].sprite:GetLayer(0):IsVisible() and #errors==0)
        ''')

    def test_expired_animation_cannot_restore_onto_a_reused_native_address(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','angelscrown')
            for i=1,12 do event(1); event(2) end
            local p=spawned[1]
            assert(#T._activeAnimations==1)
            -- Simulate removal/reallocation with the same raw address and seed.
            -- An expired EntityPtr is authoritative despite those coincidences.
            p.generation=p.generation+1
            p.sprite=Sprite(); p.sprite.Color=Color(0.2,0.3,0.4,0.5)
            p.sprite:GetLayer(0):SetVisible(false)
            T.renderAllAnimations(); T.updateAllAnimations()
            assert(#T._activeAnimations==0)
            assert(p.sprite.Color==Color(0.2,0.3,0.4,0.5))
            assert(not p.sprite:GetLayer(0):IsVisible())
        ''')

    def test_crown_uses_native_halo_and_glints_without_covering_the_item(self):
        self.lua.execute('''
            local s=V.create('ANGELS_CROWN',Vector(320,180)); s.frame=30; drawings={}; V.render(s)
            local halo,item
            for index,d in ipairs(drawings) do
                if d.path:find('conch_upgrade_halo') then halo=index end
                if d.sheet==s.before.sheet then item=index end
            end
            assert(halo and item and halo<item)
            -- Visible halo reaches 7px below its centre; crown starts 6px
            -- above its canvas centre. Preserve separation, not an arbitrary
            -- absolute screen height that ignores the art's padding.
            assert(drawings[halo].pos.Y+7 < drawings[item].pos.Y-6)
            s.frame=s.impact+8; drawings={}; V.render(s)
            local glint=false
            for _,d in ipairs(drawings) do
                if d.path=='gfx/1000.103_ultragreedbling.anm2' then glint=true end
            end
            assert(glint)
            sounds={}; s.frame=0; for i=1,s.duration do V.update(s) end
            assert(#sounds==2 and sounds[1]==SoundEffect.SOUND_ANGEL_WING and sounds[2]==SoundEffect.SOUND_HOLY)
        ''')

    def test_atropos_uses_only_default_animation_in_real_morph_viewer(self):
        self.viewer()
        self.lua.execute('''
            event(6,'conch_morph','atropos')
            for i=1,180 do
                event(1); event(2)
                for _,anim in ipairs(T._activeAnimations) do
                    assert(anim.type=='positive' and not anim.morphScene, 'pending item must use default')
                end
            end
            assert(W.isRunning() and #morphs==1 and spawned[1]:Exists() and #errors==0)
            event(6,'conch_morph','stop')
        ''')

    def test_crown_effect_anchor_matches_source_and_result_visible_art(self):
        profile = self.lua.eval("V.profile('ANGELS_CROWN')")
        vanilla = ROOT.parent.parent/'extracted_resources/resources'
        for path in (ROOT/'resources/gfx/items/trinkets/angels_crown.png',
                     vanilla/'gfx/items/trinkets/trinket_146_devilscrown.png'):
            with Image.open(path) as image:
                x1, y1, x2, y2 = image.getchannel('A').getbbox()
            self.assertEqual((profile.anchorX, profile.anchorY), ((x1+x2)/2, (y1+y2)/2))
        self.lua.execute('''
            local p=pickup(); p.Variant=350; p.SpriteOffset=Vector(7,-13)
            p.sprite.Scale=Vector(2,1); p.sprite.Offset=Vector(3,4)
            p.sprite.itemScale=Vector(1.5,0.75); p.sprite.itemPos=Vector(2,-3)
            local custom=T.forItem('ANGELS_CROWN','positive'); local state={}
            custom.onBeforeChange(p.Position,p,state)
            local function check(frame)
                state.morphScene.frame=frame; drawings={}; T.renderAllAnimations()
                local halo,item
                for _,d in ipairs(drawings) do
                    if d.path and d.path:find('conch_upgrade_halo') then halo=d end
                    if d.native==p.sprite then item=d end
                end
                -- Crown's visible centre (16.5,19), trinket pivot (16,24),
                -- frame transform, sprite transform and entity offset.
                local x=320+7+3+(2+0.5*1.5)*2
                local y=180-13+4+(-3-5*0.75)
                local t=math.max(0,math.min(1,(frame-12)/24))
                assert(halo and halo.pos.X==x)
                assert(math.abs(halo.pos.Y-(y-32+t*t*(3-2*t)*8))<0.00001)
                assert(item and item.pos.X==327 and item.pos.Y==167, 'anchor must not shift item')
            end
            check(30)
            T.cancelForPickup(p); p.SubType=456; custom.onAfterChange(p.Position,p,state)
            check(45); T.cancelForPickup(p)
            assert(#errors==0 and p.sprite:GetLayer(0):IsVisible())
        ''')

    def test_runtime_assets_have_bounded_frames_and_resolvable_sheets(self):
        # Missing vanilla extraction is a limitation, never an engine-render PASS.
        vanilla = ROOT.parent.parent/'extracted_resources/resources'
        for path in (ROOT/'resources/gfx/effects').glob('conch_upgrade_*.anm2'):
            tree = ET.parse(path)
            for sheet in tree.findall('.//Spritesheet'):
                local = (path.parent/sheet.get('Path')).resolve()
                relative = Path('gfx/effects')/sheet.get('Path')
                self.assertTrue(local.exists() or (vanilla/relative).exists(), str(relative))
            for frame in tree.findall('.//LayerAnimation/Frame'):
                self.assertGreater(int(frame.get('Width')), 0)
                self.assertGreater(int(frame.get('Height')), 0)


if __name__ == '__main__':
    unittest.main()
