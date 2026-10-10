"""Exercise the shipped cosmetic renderer; these do not prove GPU/game rendering."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class NeglectVisualTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            package=nil
            errors,images,draws,captures,native,shaderLoads={},{},{},{},{},{}
            width,height=640,360
            Direction={LEFT=0,UP=1,RIGHT=2,DOWN=3}
            REPENTOGON={Real=true}; ModCallbacks={MC_PRE_PLAYER_RENDER=1082}
            Vector=setmetatable({}, {__call=function(_,x,y) return {X=x,Y=y} end})
            KColor=setmetatable({}, {__call=function(_,r,g,b,a) return {R=r,G=g,B=b,A=a} end})
            Isaac={GetItemIdByName=function() return 902 end,
                GetScreenWidth=function() return width end,GetScreenHeight=function() return height end,
                WorldToScreen=function(p) return Vector(p.X+20,p.Y+10) end}
            itemConfig={ID=902,Type=1,Costume={ID=902}}
            Isaac.GetItemConfig=function() return {GetCollectible=function() return itemConfig end} end
            GetPtrHash=function(p) return p.key end
            SourceQuad={NewFromBounds=function(a,b) return {a=a,b=b} end}
            DestinationQuad={NewFromBounds=function(a,b) return {a=a,b=b} end}
            ConchBlessing={printError=function(msg) errors[#errors+1]=msg end,originalMod={}}
            currentTarget='screen'
            Renderer={CreateImage=function(w,h,name)
                if failCreate then error('create failed') end
                local image={width=w,height=h,name=name}
                function image:Render(source,destination,colour)
                    assert(currentTarget=='screen','target must be restored before final draw')
                    if failDisplay then error('display failed') end
                    draws[#draws+1]={image=self,source=source,destination=destination,colour=colour}
                end
                function image:GetPaddedWidth() return 1024 end
                function image:GetPaddedHeight() return 512 end
                function image:RenderWithShader(source,destination,colour,shader,attributes)
                    if failShaderDraw then error('shader draw failed') end
                    self:Render(source,destination,colour)
                    draws[#draws].shader=shader; draws[#draws].attributes=attributes
                end
                images[#images+1]=image
                return image
            end,RenderToImage=function(image,fn)
                local oldTarget=currentTarget
                currentTarget=image
                captures[#captures+1]=image
                local ok,err=pcall(fn,{Clear=function() image.cleared=(image.cleared or 0)+1 end})
                currentTarget=oldTarget -- provider guarantees restoration even when fn throws
                if not ok then error(err) end
            end, VertexAttributeFormat={POSITION=1,COLOR=2,TEX_COORD=3,VEC2=4},
            LoadShader=function(path,descriptor)
                if failShaderLoad then error('shader load failed') end
                assert(path=='shaders/conch_neglect_outline')
                assert(descriptor[1][2]==1 and descriptor[2][2]==2 and descriptor[3][2]==3)
                assert(descriptor[4][1]=='TexelStep' and descriptor[4][2]==4)
                local shader={path=path}; shaderLoads[#shaderLoads+1]=shader; return shader
            end}
            M=require('scripts.items.collectibles.hemispatial_neglect_visual')
            function makePlayer(key)
                local p={key=key,copies=1,costume=true,Visible=true,Position=Vector(300,200),
                    SpriteOffset=Vector(3,-7),direction=Direction.DOWN,colour={R=.5,G=.3,B=.7,A=.4}}
                function p:HasCollectible(id) assert(id==902); return self.copies>0 end
                function p:GetCostumeSpriteDescs()
                    if failCostumeRead then error('costume read failed') end
                    local rows={{GetItemConfig=function() return {ID=902,Type=0} end},
                        {GetItemConfig=function() return nil end}}
                    if self.costume then rows[#rows+1]={GetItemConfig=function() return itemConfig end} end
                    return rows
                end
                function p:AddCostume(item, itemStateOnly)
                    assert(item==itemConfig and not itemStateOnly)
                    self.costume=true
                end
                function p:RemoveCostume(item) assert(item==itemConfig); self.costume=false end
                function p:GetHeadDirection() return self.direction end
                function p:Render(offset)
                    local answer=M.onPrePlayerRender(nil,self,offset)
                    assert(answer==nil,'nested native render must not be cancelled or captured again')
                    assert(currentTarget~='screen' and currentTarget.cleared>0)
                    if failNative then error('native render failed') end
                    native[#native+1]={player=self,offset=offset,colour=self.colour}
                end
                return p
            end
            p=makePlayer(1); q=makePlayer(2); offset=Vector(6,4)
        ''')

    def test_front_right_half_is_removed_without_tinting_or_rescaling(self):
        self.lua.execute('''
            local colour=p.colour; local position=p.Position; local spriteOffset=p.SpriteOffset
            assert(M.onPrePlayerRender(nil,p,offset)==false)
            assert(#native==1 and #captures==1 and #draws==1 and #images==1)
            local d=draws[1]
            assert(d.source.a.X==329 and d.source.b.X==640,'front: keep screen-right half')
            assert(d.source.a.Y==0 and d.source.b.Y==360)
            assert(d.destination.a.X==d.source.a.X and d.destination.b.X==d.source.b.X)
            assert(d.colour.R==1 and d.colour.G==1 and d.colour.B==1 and d.colour.A==1)
            assert(p.Visible and p.colour==colour and p.Position==position and p.SpriteOffset==spriteOffset)
            assert(native[1].offset==offset,'do not relocate the player for capture')
        ''')

    def test_all_four_directions_use_the_requested_side(self):
        self.lua.execute('''
            p.direction=Direction.UP; M.onPrePlayerRender(nil,p,offset)
            assert(draws[1].source.a.X==0 and draws[1].source.b.X==329)
            p.direction=Direction.LEFT
            assert(M.onPrePlayerRender(nil,p,offset)==nil and #draws==1 and #captures==1,
                'left-facing native appearance must not be clipped or tinted')
            p.direction=Direction.RIGHT; assert(M.onPrePlayerRender(nil,p,offset)==false)
            local right=draws[2]
            assert(right.source.a.X==0 and right.source.b.X==640 and right.shader)
            assert(right.attributes.TexelStep[1]==1/1024 and right.attributes.TexelStep[2]==1/512)
            p.direction=Direction.DOWN; M.onPrePlayerRender(nil,p,offset)
            assert(draws[#draws].source.a.X==329 and draws[#draws].source.b.X==640)
            assert(not draws[#draws].shader and #images==1 and #shaderLoads==1)
        ''')

    def test_right_profile_reuses_shader_and_left_needs_no_shader_support(self):
        self.lua.execute('''
            p.direction=Direction.RIGHT
            for i=1,10 do assert(M.onPrePlayerRender(nil,p,offset)==false) end
            assert(#shaderLoads==1 and #images==1 and #draws==10)
            local renderer=Renderer; Renderer=nil; M.reset()
            p.direction=Direction.LEFT; assert(M.onPrePlayerRender(nil,p,offset)==nil)
            assert(#errors==0 and #draws==10)
            Renderer=renderer
        ''')

    def test_missing_or_broken_shader_falls_back_to_black_silhouette_once(self):
        self.lua.execute('''
            failShaderLoad=true; p.direction=Direction.RIGHT
            for i=1,3 do assert(M.onPrePlayerRender(nil,p,offset)==false) end
            assert(#errors==1 and #draws==3)
            for _,d in ipairs(draws) do
                assert(d.colour.R==0 and d.colour.G==0 and d.colour.B==0 and d.colour.A==1)
                assert(not d.shader and d.source.a.X==0 and d.source.b.X==640)
            end
            failShaderLoad=false; M.reset()
            assert(M.onPrePlayerRender(nil,p,offset)==false and draws[4].shader)
            failShaderDraw=true; assert(M.onPrePlayerRender(nil,p,offset)==nil and #errors==2)
            p.direction=Direction.LEFT; assert(M.onPrePlayerRender(nil,p,offset)==nil)
            assert(currentTarget=='screen' and p.Visible)
        ''')

    def test_stack_removal_reacquire_and_players_are_independent(self):
        self.lua.execute('''
            for _,n in ipairs({1,2,1}) do p.copies=n; assert(M.onPrePlayerRender(nil,p,offset)==false) end
            assert(#images==1 and #native==3,'one surface and one draw, regardless of copies')
            q.direction=Direction.UP; M.onPrePlayerRender(nil,q,offset)
            assert(#images==2 and draws[4].image~=draws[1].image)
            assert(draws[4].source.a.X==0)
            p.copies=0; M.onPlayerUpdate(nil,p)
            assert(M.onPrePlayerRender(nil,p,offset)==nil and #draws==4)
            p.copies=1; M.onPrePlayerRender(nil,p,offset)
            assert(#images==3 and draws[5].source.a.X==329)
            M.onPrePlayerRender(nil,q,offset); assert(#images==3)
        ''')

    def test_invisible_or_unowned_player_is_never_reintroduced(self):
        self.lua.execute('''
            p.Visible=false; assert(M.onPrePlayerRender(nil,p,offset)==nil)
            p.Visible=true; p.copies=0; assert(M.onPrePlayerRender(nil,p,offset)==nil)
            assert(#native==0 and #captures==0 and #draws==0 and #images==0)
        ''')

    def test_capture_clears_every_frame_and_resize_reallocates_once(self):
        self.lua.execute('''
            for i=1,10 do M.onPrePlayerRender(nil,p,offset) end
            assert(#images==1 and images[1].cleared==10)
            width,height=853,480
            M.onPrePlayerRender(nil,p,offset); M.onPrePlayerRender(nil,p,offset)
            assert(#images==2 and images[2].width==853 and images[2].height==480)
            assert(images[2].cleared==2 and draws[#draws].source.b.X==853)
        ''')

    def test_unavailable_provider_leaves_native_draw_and_warns_once(self):
        self.lua.execute('''
            local renderer=Renderer; Renderer=nil
            for i=1,20 do assert(M.onPrePlayerRender(nil,p,offset)==nil) end
            assert(#errors==1 and #native==0 and #draws==0 and p.Visible)
            Renderer=renderer; M.reset(); assert(M.onPrePlayerRender(nil,p,offset)==false)
            REPENTOGON=nil; M.reset(); assert(M.onPrePlayerRender(nil,p,offset)==nil)
        ''')

    def test_errors_restore_target_guard_and_do_not_hide_native_player(self):
        for flag in ('failCreate', 'failNative', 'failDisplay'):
            with self.subTest(flag=flag):
                self.setUp()
                self.lua.globals()[flag] = True
                self.lua.execute('''
                    assert(M.onPrePlayerRender(nil,p,offset)==nil)
                    assert(currentTarget=='screen' and p.Visible and #errors==1)
                    assert(M.onPrePlayerRender(nil,p,offset)==nil and #errors==1)
                    failCreate,failNative,failDisplay=false,false,false
                    M.reset(); assert(M.onPrePlayerRender(nil,p,offset)==false)
                    assert(currentTarget=='screen')
                ''')

    def test_lifecycle_cleanup_and_foreign_unload(self):
        self.lua.execute('''
            M.onPrePlayerRender(nil,p,offset)
            M.onUnload(nil,{}); M.onPrePlayerRender(nil,p,offset); assert(#images==1)
            M.onUnload(nil,ConchBlessing.originalMod)
            M.onPrePlayerRender(nil,p,offset); assert(#images==2)
            M.reset(); M.onPrePlayerRender(nil,p,offset); assert(#images==3)
            assert(images[1].name~=images[2].name and images[2].name~=images[3].name)
        ''')

    def test_native_wardrobe_toggle_only_changes_appearance_and_never_readds(self):
        self.lua.execute('''
            M.onPrePlayerRender(nil,p,offset); assert(#captures==1)
            -- Exact native calls used by installed Old Wardrobe's item tab.
            p:RemoveCostume(itemConfig)
            local originalAdd=p.AddCostume
            p.AddCostume=function() error('must not undo wardrobe removal') end
            for i=1,120 do
                M.onPlayerUpdate(nil,p)
                assert(M.onPrePlayerRender(nil,p,offset)==nil)
            end
            assert(#captures==1 and p.copies==1 and p.Visible and #errors==0)
            M.reset(); M.onPlayerUpdate(nil,p)
            assert(M.onPrePlayerRender(nil,p,offset)==nil,'room/load cannot re-enable a removed costume')
            q.direction=Direction.RIGHT; assert(M.onPrePlayerRender(nil,q,offset)==false)
            assert(p.copies==1 and q.copies==1,'co-op cosmetic switch cannot mutate inventory')
            p.AddCostume=originalAdd; p:AddCostume(itemConfig,false)
            assert(M.onPrePlayerRender(nil,p,offset)==false)
            for _,n in ipairs({2,1}) do
                p.copies=n; p:RemoveCostume(itemConfig)
                assert(M.onPrePlayerRender(nil,p,offset)==nil,'extra copies must not force cosmetic on')
            end
            p.copies=0; p:AddCostume(itemConfig,false)
            assert(M.onPrePlayerRender(nil,p,offset)==nil,'a wardrobe favourite must not grant item powers')
        ''')

    def test_costume_capability_or_loading_failure_leaves_player_visible(self):
        for setup in ('p.GetCostumeSpriteDescs=nil', 'itemConfig.Costume.ID=-1', 'failCostumeRead=true'):
            with self.subTest(setup=setup):
                self.setUp()
                self.lua.execute(setup)
                self.lua.execute('''
                    for i=1,10 do
                        M.onPlayerUpdate(nil,p)
                        assert(M.onPrePlayerRender(nil,p,offset)==nil)
                    end
                    assert(p.Visible and #captures==0 and #errors==1)
                ''')

    def test_failed_player_does_not_disable_coop_owner(self):
        self.lua.execute('''
            failNative=true; assert(M.onPrePlayerRender(nil,p,offset)==nil)
            failNative=false; assert(M.onPrePlayerRender(nil,q,offset)==false)
            assert(#draws==1 and native[1].player==q)
        ''')

    def test_bounds_at_viewport_edges_remain_valid(self):
        self.lua.execute('''
            p.Position.X=-100; assert(M.onPrePlayerRender(nil,p,offset)==false)
            assert(draws[1].source.a.X==0)
            p.Position.X=1000; assert(M.onPrePlayerRender(nil,p,offset)==false)
            assert(#draws==1,'empty retained rectangle is not submitted')
            p.direction=Direction.UP; M.onPrePlayerRender(nil,p,offset)
            assert(draws[2].source.b.X==640)
        ''')


if __name__ == '__main__':
    unittest.main()
