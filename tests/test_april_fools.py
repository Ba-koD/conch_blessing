"""Appearance-only acceptance cases through the shipped Lua module.

These establish state/ownership and asset contracts, not engine raster output.
"""
import json
import sys
import unittest
from pathlib import Path
from PIL import Image
import numpy as np
from lupa.lua53 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'docs/previews/aprilfools'


class AppearanceTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            local hostRequire=require
            package=nil -- Isaac has no package global
            require=hostRequire
            today={month=3,day=31};tick=0
            os.date=function() return today end
            function Vector(x,y) return {X=x,Y=y} end
            ModCallbacks={MC_POST_UPDATE=1,MC_PRE_GAME_EXIT=2,MC_POST_GAME_STARTED=3,
                MC_PRE_MOD_UNLOAD=4,MC_POST_ENTITY_REMOVE=5,MC_PRE_CHANGE_ROOM=6}
            ConchBlessing={Config={aprilFools3D='auto'},callbacks={},errors={}}
            function ConchBlessing:AddCallback(id,fn) self.callbacks[id]=fn end
            function ConchBlessing.printError(m) table.insert(ConchBlessing.errors,m) end
            function ConchBlessing.printDebug() end
            function Game() return {GetFrameCount=function() return tick end} end
            function EntityPtr(e) return {Ref=e} end
            function GetPtrHash(e) return e.hash end
            Config=require('scripts.conch_blessing_config')
            A=require('scripts.lib.april_fools')
            function sprite(path)
                local layer={path=path,crop=Vector(0,0),pos=Vector(8,-6),size=Vector(1,1),visible=true}
                function layer:GetLayerID() return 1 end
                function layer:GetSpritesheetPath() return self.path end
                function layer:GetCropOffset() return self.crop end
                function layer:SetCropOffset(v) self.crop=v end
                local s={layer=layer,loads=0,animation='Idle',frame=4}
                function s:GetAllLayers() return {self.layer} end
                function s:GetLayer(id) assert(id==1);return self.layer end
                function s:ReplaceSpritesheet(id,p) assert(id==1);self.layer.path=p end
                function s:LoadGraphics() self.loads=self.loads+1 end
                return s
            end
            own='gfx/items/collectibles/conch_pearl.png'
        ''')

    def run_lua(self,text):self.lua.execute(text)

    def test_calendar_and_override_without_mutating_preference(self):
        self.run_lua('''
            assert(not Config.IsAprilFools3D())
            today.day=1;today.month=4; assert(Config.IsAprilFools3D())
            assert(ConchBlessing.Config.aprilFools3D=='auto')
            today.day=2;assert(not Config.IsAprilFools3D())
            ConchBlessing.Config.aprilFools3D='on';assert(Config.IsAprilFools3D())
            ConchBlessing.Config.aprilFools3D='off';today.day=1;assert(not Config.IsAprilFools3D())
            ConchBlessing.Config.aprilFools3D='auto';os=nil;assert(not Config.IsAprilFools3D())
        ''')

    def test_full_turn_pause_and_exact_restoration(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            s=sprite(own);s.layer.crop=Vector(0,3)
            A.Apply(s);assert(s.layer.path:find('_spin.png',1,true))
            for f=0,31 do tick=f*2;A.Apply(s);assert(s.layer.crop.X==f*32) end
            A.Apply(s);assert(s.layer.crop.X==992) -- same paused tick
            tick=64;A.Apply(s);assert(s.layer.crop.X==0)
            assert(s.loads==1 and s.frame==4 and s.animation=='Idle')
            assert(s.layer.pos.X==8 and s.layer.pos.Y==-6 and s.layer.visible)
            ConchBlessing.Config.aprilFools3D='off';A.Refresh()
            assert(s.layer.path==own and s.layer.crop.X==0 and s.layer.crop.Y==3)
        ''')

    def test_entity_sprite_wrappers_do_not_accumulate_rotation(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            shared=sprite(own).layer
            actor={hash=29}
            function actor:Exists() return true end
            function actor:GetSprite()
                local wrapper=sprite(own);wrapper.layer=shared;return wrapper
            end
            -- The engine returns a new Sprite userdata on every GetSprite.
            -- Update and pre-render both visit the same actual layer.
            assert(actor:GetSprite()~=actor:GetSprite())
            for f=0,255 do
                tick=f
                A.Apply(actor:GetSprite(),actor)
                A.Apply(actor:GetSprite(),actor)
                assert(shared.crop.X==(math.floor(f/2)%32)*32, 'rotation drift at '..f..': '..shared.crop.X)
                if f%11==0 then collectgarbage('collect') end
            end
            ConchBlessing.Config.aprilFools3D='off';A.Refresh()
            assert(shared.path==own and shared.crop.X==0)
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            tick=10;A.Apply(actor:GetSprite(),actor)
            -- A foreign replacement remains authoritative even through a new
            -- wrapper. Unload removes only our old crop, not that replacement.
            shared.path='gfx/another_mod.png'
            ConchBlessing.callbacks[4](nil,ConchBlessing)
            assert(shared.path=='gfx/another_mod.png' and shared.crop.X==0)
        ''')

    def test_orphan_strip_and_removed_owner_do_not_reuse_a_phase(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            local strip='gfx/items/collectibles/conch_pearl_af3d_spin.png'
            local shared=sprite(strip).layer;shared.crop=Vector(1000000,3)
            local actor={hash=29,alive=true}
            function actor:Exists() return self.alive end
            function actor:GetSprite()
                local wrapper=sprite(own);wrapper.layer=shared;return wrapper
            end
            tick=4;A.Apply(actor:GetSprite(),actor);assert(shared.crop.X==64)
            ConchBlessing.callbacks[5](nil,actor);actor.alive=false
            local nextSprite=sprite(own);nextSprite.layer.crop=Vector(0,7)
            local replacement={hash=29}
            function replacement:Exists() return true end
            function replacement:GetSprite() return nextSprite end
            A.Apply(replacement:GetSprite(),replacement)
            ConchBlessing.Config.aprilFools3D='off';A.Refresh()
            assert(nextSprite.layer.crop.X==0 and nextSprite.layer.crop.Y==7)
            assert(shared.crop.X==64) -- removed entity must never be accessed
        ''')

    def test_unknown_foreign_and_reroll_do_not_reveal_or_restore_wrong_item(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            unknown=sprite('gfx/items/collectibles/questionmark.png');A.Apply(unknown)
            assert(unknown.loads==0)
            s=sprite(own);tick=12;A.Apply(s);assert(s.layer.crop.X==192)
            s.layer.path='gfx/items/collectibles/questionmark.png';A.Apply(s)
            assert(s.layer.crop.X==0 and s.layer.path:find('questionmark',1,true))
            s.layer.path=own;A.Apply(s)
            s.layer.path='gfx/another_mod.png'
            ConchBlessing.Config.aprilFools3D='off';A.Refresh()
            assert(s.layer.path=='gfx/another_mod.png')
        ''')

    def test_entity_pose_does_not_spin_and_missing_capability_is_safe(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            s=sprite('gfx/familiar/familiar_hermit_crab.png');s.animation='BffsOneWalk';s.frame=17
            tick=33;A.Apply(s)
            assert(s.layer.path:find('_af3d.png',1,true) and s.layer.crop.X==0)
            assert(s.frame==17 and s.animation=='BffsOneWalk')
            A.Apply({});A.Apply({});assert(#ConchBlessing.errors==1)
        ''')

    def test_own_unload_and_room_exit_restore(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            s=sprite(own);A.Apply(s)
            ConchBlessing.callbacks[6]();assert(s.layer.path==own)
            A.Apply(s);ConchBlessing.callbacks[4](nil,{})
            assert(s.layer.path~=own)
            ConchBlessing.callbacks[4](nil,ConchBlessing);assert(s.layer.path==own)
            A.Apply(s);assert(s.layer.path==own)
        ''')

    def test_missing_crop_methods_get_static_image(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            s=sprite(own);s.layer.SetCropOffset=nil;s.layer.GetCropOffset=nil
            A.Apply(s);assert(s.layer.path=='gfx/items/collectibles/conch_pearl_af3d.png')
            ConchBlessing.Config.aprilFools3D='off';A.Refresh();assert(s.layer.path==own)
        ''')

    def test_anm2_relative_sheet_paths_resolve_without_matching_foreign_basenames(self):
        self.run_lua('''
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            s=sprite('familiar/familiar_hermit_crab.png')
            function s:GetFilename() return 'gfx/hermit_crab.anm2' end
            A.Apply(s);assert(s.layer.path=='gfx/familiar/familiar_hermit_crab_af3d.png')
            ConchBlessing.Config.aprilFools3D='off';A.Refresh()
            assert(s.layer.path=='gfx/familiar/familiar_hermit_crab.png')
            ConchBlessing.Config.aprilFools3D='on';A.Refresh()
            other=sprite('familiar_hermit_crab.png')
            function other:GetFilename() return 'gfx/another_mod/actor.anm2' end
            A.Apply(other);assert(other.loads==0)
        ''')


class AssetTests(unittest.TestCase):
    def test_exhaustive_manifest_and_native_layouts(self):
        audit=json.loads((SOURCE/'coverage.json').read_text())
        original={p.relative_to(ROOT/'resources').as_posix() for p in (ROOT/'resources/gfx').rglob('*.png')
                  if 'notused' not in p.parts and '_af3d' not in p.stem}
        self.assertEqual(original,{r['source'] for r in audit})
        self.assertFalse([r for r in audit if r['status']=='MISSING'])
        for group in ['items','actors','extras']:
            for row in json.loads((SOURCE/f'{group}.json').read_text()):
                with Image.open(ROOT/'resources'/row['source']) as a, Image.open(ROOT/'resources'/row['still']) as b:
                    self.assertEqual(a.size,b.size,row['source'])
                if 'spin' in row:
                    with Image.open(ROOT/'resources'/row['spin']) as im:
                        self.assertEqual(im.size,(32*32,32))
                        for f in range(32):
                            alpha=np.array(im.crop((f*32,0,f*32+32,32)))[...,3]
                            self.assertTrue((alpha>128).any(),(row['key'],f))
                            self.assertFalse((alpha[[0,-1],:]>128).any(),(row['key'],f,'vertical clipping'))
                            self.assertFalse((alpha[:,[0,-1]]>128).any(),(row['key'],f,'horizontal clipping'))

    def test_pearl_is_a_true_sphere_not_a_height_map(self):
        sys.path.insert(0,str(SOURCE))
        from objects import build
        m=build(ROOT/'resources/gfx/items/collectibles/conch_pearl.png','conch_pearl')
        self.assertEqual(len(m.parts),1)
        vertices=m.parts[0].v
        centre=(vertices.min(axis=0)+vertices.max(axis=0))/2
        radius=np.linalg.norm(vertices-centre,axis=1)
        self.assertLess(radius.max()-radius.min(),1e-10)
        self.assertEqual(m.parts[0].mat,'pearl')

    def test_ink_stays_visible_on_the_slanted_paper_and_off_the_back(self):
        sys.path.insert(0,str(SOURCE))
        from objects import build
        from build import view
        for letter in ['a','b','c','f']:
            key=letter+'_minus'
            m=build(ROOT/f'resources/gfx/items/trinkets/{key}.png',key)
            counts=[]
            for angle in [0,45,180]:
                a=np.array(view(m,angle,size=128))
                counts.append(np.count_nonzero((a[...,0]>50)&(a[...,0].astype(float)>a[...,1]*1.8)&(a[...,0].astype(float)>a[...,2]*1.8)&(a[...,3]>128)))
            self.assertGreater(counts[0],100,key)
            self.assertGreater(counts[1],counts[0]*.4,(key,counts))
            self.assertEqual(counts[2],0,(key,counts))

    def test_painted_shading_does_not_change_constructed_anatomy(self):
        import tempfile
        sys.path.insert(0,str(SOURCE))
        from objects import build
        source=ROOT/'resources/gfx/items/collectibles/ox.png'
        a=np.array(Image.open(source).convert('RGBA'));a[a[...,3]>0,:3]=225
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'ox.png';Image.fromarray(a).save(path)
            def points(p):
                return np.vstack([part.v for part in build(p,'ox').parts if not part.mat.startswith('ink_')])
            np.testing.assert_array_equal(points(source),points(path))

    def test_closed_primitive_winding_and_bevel_inset(self):
        sys.path.insert(0,str(SOURCE))
        from mesh3d import sphere,lathe,extrude,sweep
        from build import clean
        geometries=[[sphere(2,'x')],lathe([(0,-2),(2,-2),(2,2),(0,2)],'x'),
                    extrude([(-2,-2),(2,-2),(2,2),(-2,2)],4,'x',bevel=.3),
                    sweep([(0,0,-2),(0,0,2)],2,'x')]
        for parts in geometries:
            parts=clean(parts);vertices=np.vstack([p.v for p in parts])
            _,inv=np.unique(np.round(vertices,7),axis=0,return_inverse=True)
            faces=[];offset=0;volume=0
            for p in parts:
                faces.append(inv[p.f+offset]);offset+=len(p.v)
                tri=p.v[p.f];volume+=np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])).sum()/6
            f=np.vstack(faces)
            edges=np.sort(np.vstack([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1)
            _,counts=np.unique(edges,axis=0,return_counts=True)
            self.assertTrue((counts==2).all(),counts)
            self.assertGreater(volume,0)
            self.assertLessEqual(np.abs(vertices).max(),2.000001)

    def test_orthographic_depth_is_affine_for_small_and_large_triangles(self):
        sys.path.insert(0,str(SOURCE))
        from mesh3d import Part,Camera,render,material
        cam=Camera(yaw=0,pitch=0,dist=20,ortho=12)
        for divisions in [1,16]:
            v=[];f=[]
            for z in np.linspace(-4,4,divisions+1):
                for x in np.linspace(-4,4,divisions+1):v.append((x,.8*x+.4*z,z))
            for i in range(divisions):
                for j in range(divisions):
                    a=i*(divisions+1)+j;b=a+1;c=a+divisions+1;d=c+1
                    f.extend([(a,b,c),(b,d,c)])
            _,depth=render([Part(v,f,'x')],{'x':material((100,100,100))},cam,size=48,ss=1,return_depth=True)
            yy,xx=np.indices(depth.shape);expected=20+.8*((xx+.5)/4-6)+.4*(6-(yy+.5)/4)
            valid=np.isfinite(depth)
            self.assertGreater(valid.sum(),900)
            np.testing.assert_allclose(depth[valid],expected[valid],atol=1e-10)

    def test_turn_returns_to_the_same_fixed_camera_view(self):
        sys.path.insert(0,str(SOURCE))
        from objects import build
        from build import view,frame_for_turn
        for key in ['kids_menu','tyrfing','conch_pearl']:
            m=build(ROOT/f'resources/gfx/items/collectibles/{key}.png',key);frame_for_turn(m)
            a=np.array(view(m,0,size=64)).astype(int);b=np.array(view(m,360,size=64)).astype(int)
            self.assertLessEqual(np.abs(a-b).max(),1,key)


if __name__=='__main__':unittest.main()
