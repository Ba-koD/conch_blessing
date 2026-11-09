"""Production item contracts, including the installed provider when available."""
import unittest
from pathlib import Path
import test_real_eyes

class EyeUpgradesTests(unittest.TestCase):
    def setUp(self):
        test_real_eyes.RealEyesTests.setUp(self)
        self.lua.execute('''
            Isaac.GetItemIdByName=function(name) return name=='AR Glasses' and 901 or 902 end
            for _,p in ipairs(players) do
                p.inventory={}; p.ControllerIndex=0
                function p:HasCollectible(id) return (self.inventory[id] or 0)>0 end
                function p:GetCollectibleNum(id) return self.inventory[id] or 0 end
                function p:ToPlayer() return self end
            end
            REPENTOGON={Real=true}
            ModCallbacks={MC_EVALUATE_TEAR_HIT_PARAMS=1490,MC_PRE_TEAR_UPDATE=1161}
            WeaponType={WEAPON_TEARS=1,WEAPON_BRIMSTONE=2,WEAPON_LASER=3,WEAPON_KNIFE=4}
            TearFlags={TEAR_NORMAL=0}
            EntityCollisionClass={ENTCOLL_NONE=0}; EntityGridCollisionClass={GRIDCOLL_NONE=0}
            SoundEffect={SOUND_NULL=0}
            Isaac.GetEntityTypeByName=function() return 2 end
            Isaac.GetEntityVariantByName=function() return 9001 end
            GetPtrHash=function(e) return e end
            AR=require('scripts.items.collectibles.ar_glasses')
            NEG=require('scripts.items.collectibles.hemispatial_neglect')
        ''')

    def test_ar_glasses_is_a_twelve_charge_active_starting_half_full(self):
        import xml.etree.ElementTree as ET
        root = Path(__file__).resolve().parents[1]
        rows = [row for row in ET.parse(root / 'content/items.xml').getroot() if row.get('name') == 'AR Glasses']
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row.tag, 'active')
        self.assertEqual((row.get('maxcharges'), row.get('chargetype'), row.get('initcharge')), ('12', 'normal', '6'))

    def test_ar_glasses_has_no_hud_row_or_c_key_beside_real_eyes(self):
        self.lua.execute('''
            players[1].inventory[900]=1; players[1].inventory[901]=1
            draws={}; spriteDraws={}; M.onRender()
            assert(#draws==2 and draws[2].text:find('예측 #1: ',1,true)==1, tostring(draws[2] and draws[2].text))
            assert(#spriteDraws==1, 'one icon: Real Eyes alone')
            for _,d in ipairs(draws) do assert(not d.text:find('C:',1,true), d.text) end
            assert(AR.onRender==nil and AR.onUpdate==nil and AR.cycle==nil and AR.reset==nil,
                'AR Glasses is an active now: no HUD row, no C key, no per-room reset')
            assert(type(AR.onUseItem)=='function')
            -- Another item's use passes through untouched.
            assert(AR.onUseItem(nil,902,nil,players[1])==nil)
            players[1].inventory[900]=0; draws={}; M.onRender(); assert(#draws==0)
        ''')

    def test_damage_registration_stack_loss_drift_and_player_isolation(self):
        self.lua.execute('''
            local states={}; sets,saves,removes=0,0,0
            ConchBlessing.getUnifiedMultiplierState=function(p)
                states[p]=states[p] or {itemMultipliers={}}; return states[p]
            end
            um={SetItemMultiplier=function(_,p,id,stat,value)
                    sets=sets+1; local s=ConchBlessing.getUnifiedMultiplierState(p)
                    s.itemMultipliers[id]={[stat]={value=value}}
                end,
                RemoveItemMultiplier=function(_,p,id) removes=removes+1; states[p].itemMultipliers[id]=nil end,
                QueueCacheUpdate=function() end, SaveToSaveManager=function() saves=saves+1 end}
            ConchBlessing.stats={unifiedMultipliers=um}
            local p=players[1]
            for _,n in ipairs({0,1,2,1,0,1,0}) do
                p.inventory[902]=n; NEG.onPlayerUpdate(nil,p)
                local row=states[p].itemMultipliers[902]
                assert(n==0 and row==nil or n>0 and row.Damage.value==2^n)
                local before=sets+saves+removes
                for i=1,30 do NEG.onPlayerUpdate(nil,p) end
                assert(sets+saves+removes==before,'no per-frame cache/save churn')
            end
            players[2].inventory[902]=1; NEG.onPlayerUpdate(nil,players[2])
            assert(states[players[2]].itemMultipliers[902].Damage.value==2)
            assert(states[p].itemMultipliers[902]==nil)
            p.inventory[902]=1; NEG.onPlayerUpdate(nil,p)
            states[p].itemMultipliers={}; NEG.onPlayerUpdate(nil,p)
            assert(states[p].itemMultipliers[902].Damage.value==2,'provider drift repair')

            -- A native wardrobe removal disables only the procedural appearance.
            Isaac.GetItemConfig=function() return {GetCollectible=function()
                return {ID=902,Type=1,Costume={ID=902}}
            end} end
            p.GetCostumeSpriteDescs=function() return {} end
            NEG.resetVisual(); NEG.onPlayerUpdate(nil,p)
            assert(NEG.onPrePlayerRender(nil,p,Vector(0,0))==nil)
            assert(states[p].itemMultipliers[902].Damage.value==2 and p.inventory[902]==1)
            local params={TearVariant=12,TearDamage=7,TearFlags=31}
            NEG.onTearParams(nil,p,params,WeaponType.WEAPON_TEARS,1,1,nil)
            assert(params.TearDamage==0 and params.TearVariant==9001,'cosmetic off must not restore right tears')
        ''')

    def test_native_sprites_and_half_flavors(self):
        from PIL import Image
        root=Path(__file__).resolve().parents[1]
        for key in ('real_eyes','ar_glasses','hemispatial_neglect'):
            with Image.open(root/'resources/gfx/items/collectibles'/f'{key}.png') as im:
                self.assertEqual(im.size,(32,32)); self.assertEqual(im.mode,'RGBA')
                self.assertEqual(set(im.getchannel('A').tobytes()),{0,255})
                if key=='hemispatial_neglect': self.assertIsNone(im.crop((0,0,16,32)).getbbox())
        self.lua.execute('''
            for _,lang in ipairs({'en','kr','urimal'}) do
                local s=require('scripts.locale.'..lang).items.HEMISPATIAL_NEGLECT.description
                assert(s:sub(1,14)==string.rep(' ',14))
                assert(s:sub(-1)=='?')
            end
        ''')

    def test_only_right_direct_player_tear_params_change(self):
        self.lua.execute('''
            local p=players[1]; p.inventory[902]=1
            p.FireDelay=8; p.MaxFireDelay=10; p.tearDisplacement=1
            function p:SetTearDisplacement() error('must never move an eye') end
            function params() return {TearVariant=12,TearDamage=7,TearFlags=31,TearColor={}} end
            for _,eye in ipairs({1,0,-1}) do
                for weapon=1,16 do
                    local t=params(); local color=t.TearColor
                    NEG.onTearParams(nil,p,t,weapon,1,eye,nil)
                    if eye==1 and weapon==1 then
                        assert(t.TearVariant==9001 and t.TearDamage==0 and t.TearFlags==0)
                    else assert(t.TearVariant==12 and t.TearDamage==7 and t.TearColor==color) end
                end
            end
            local familiar={ToPlayer=function() return nil end}
            for _,source in ipairs({familiar,players[2]}) do
                local t=params(); NEG.onTearParams(nil,p,t,1,1,1,source)
                assert(t.TearVariant==12 and t.TearDamage==7)
            end
            local t=params(); NEG.onTearParams(nil,p,t,1,1,1,p); assert(t.TearVariant==9001)
            assert(p.FireDelay==8 and p.MaxFireDelay==10 and p.tearDisplacement==1)
            p.inventory[902]=0
            t=params(); NEG.onTearParams(nil,p,t,1,1,1,nil); assert(t.TearVariant==12)
            assert(NEG.onPrePlayerUpdate==nil)
        ''')

    def tear_fixture(self):
        self.lua.execute('''
            function tear(variant)
                local t={Type=2,Variant=variant,Visible=true,CollisionDamage=7,TearFlags=31,
                    EntityCollisionClass=4,GridCollisionClass=5,data={},removes=0}
                function t:GetData() return self.data end
                function t:Remove() self.removes=self.removes+1 end
                function t:Die() error('must not trigger impact/death effects') end
                function t:SetInitSound(s) self.sound=s end
                return t
            end
        ''')

    def test_init_is_silent_then_removed_before_update_or_collision(self):
        self.tear_fixture()
        self.lua.execute('''
            for _,finish in ipairs({NEG.onFireTear,NEG.onPreTearUpdate,NEG.onTearCollision}) do
                local t=tear(9001); NEG.onTearInit(nil,t)
                assert(t.removes==0 and not t.Visible and t.sound==0)
                -- The remaining native initialization can overwrite properties.
                t.Variant=12; t.Visible=true; t.CollisionDamage=7; t.TearFlags=31
                finish(nil,t)
                assert(t.removes==1 and not t.Visible and t.CollisionDamage==0 and t.TearFlags==0)
                assert(t.EntityCollisionClass==0 and t.GridCollisionClass==0)
            end
            local late=tear(9001); NEG.onPreTearUpdate(nil,late); assert(late.removes==1)
            local left=tear(12); NEG.onTearInit(nil,left); NEG.onFireTear(nil,left)
            assert(NEG.onPreTearUpdate(nil,left)==nil and NEG.onTearCollision(nil,left)==nil)
            assert(left.removes==0 and left.Visible and left.CollisionDamage==7 and left.TearFlags==31)
            local laser=tear(9001); laser.Type=7; NEG.onFireTear(nil,laser); assert(laser.removes==0)
        ''')

    def test_split_inheritance_and_multishot_per_result_not_player_eye(self):
        self.tear_fixture()
        self.lua.execute('''
            players[1].inventory[902]=2
            for _,eye in ipairs({-1,1,-1,1,1,-1}) do
                local p={TearVariant=12,TearDamage=14,TearFlags=31}
                NEG.onTearParams(nil,players[1],p,1,1,eye,nil)
                local parent=tear(p.TearVariant); NEG.onTearInit(nil,parent)
                local child=tear(12); NEG.onSplitTear(nil,child,parent)
                assert((child.removes==1)==(eye==1))
                if eye==-1 then assert(child.CollisionDamage==7 and child.TearFlags==31) end
            end
            -- A blocked tear stays blocked if the item is lost before its update.
            local t=tear(9001); NEG.onTearInit(nil,t); players[1].inventory[902]=0
            NEG.onPreTearUpdate(nil,t); assert(t.removes==1)
        ''')

    def test_missing_capability_fails_open_without_changing_tears(self):
        self.lua.execute('''
            players[1].inventory[902]=1
            for _,cb in ipairs({'MC_EVALUATE_TEAR_HIT_PARAMS','MC_PRE_TEAR_UPDATE'}) do
                local saved=ModCallbacks[cb]; ModCallbacks[cb]=nil
                local p={TearVariant=12,TearDamage=7,TearFlags=31}
                NEG.onTearParams(nil,players[1],p,1,1,1,nil)
                assert(not NEG.canRestrictTears() and p.TearDamage==7 and p.TearVariant==12)
                ModCallbacks[cb]=saved
            end
            Isaac.GetEntityTypeByName=function() return -1 end
            hostLoaded['scripts.items.collectibles.hemispatial_neglect']=nil
            local missing=require('scripts.items.collectibles.hemispatial_neglect')
            assert(not missing.canRestrictTears())
        ''')

if __name__=='__main__': unittest.main()
