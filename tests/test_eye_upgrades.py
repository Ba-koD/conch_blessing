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
            paused=false; game.IsPaused=function() return paused end
            pressed={}; Input={IsButtonPressed=function(key) return pressed[key] or false end, IsButtonTriggered=function() error('one-frame input must not be used') end}
            Keyboard={KEY_C=67,KEY_LEFT_CONTROL=341,KEY_ESCAPE=256,KEY_LEFT=263,KEY_RIGHT=262,KEY_UP=265,KEY_DOWN=264,KEY_ENTER=257}
            ButtonAction={ACTION_SHOOTLEFT=1,ACTION_SHOOTRIGHT=2,ACTION_SHOOTUP=3,ACTION_SHOOTDOWN=4,ACTION_DROP=5}
            InputHook={GET_ACTION_VALUE=2}
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

    def install_provider(self):
        test_real_eyes.RealEyesTests.install_real_provider(self)
        self.lua.execute('players[1].inventory[901]=1')

    def test_each_choice_is_per_use_and_does_not_mutate_forced_setting(self):
        self.install_provider()
        self.lua.execute('''
            for _,forced in ipairs({'None','Positive','Negative'}) do
                MagicConch.Config.forcedReply=forced; AR.reset()
                for _,kind in ipairs({'positive','negative','neutral'}) do
                    frame=frame+20; state.state='idle'; state.canInput=true
                    local before=usage
                    assert(AR.cycle()); assert(AR.isOpen())
                    local p=AR.getSelection(); assert(p.type==kind)
                    for i=1,25 do assert(AR.getSelection().id==p.id) end
                    assert(usage==before)
                    local r=MagicConch.API.TriggerMagicConch("ordinary activation"); assert(r.success,tostring(r.reason))
                    assert(r.pendingResult.type==kind and r.pendingResult.text==p.text)
                    assert(usage==before+1 and not AR.isOpen())
                    assert(MagicConch.Config.forcedReply==forced)
                end
            end
        ''')

    def test_rejected_use_does_not_consume_and_removal_room_exit_reset(self):
        self.install_provider()
        self.lua.execute("""
            AR.cycle(); AR.cycle()
            MagicConch.Config.attemptsPerRoom=1; usage=1
            assert(not MagicConch.API.TriggerMagicConch('ordinary').success)
            assert(usage==1 and AR.isOpen())
            MagicConch.Config.attemptsPerRoom=0; state.state='shaking'
            assert(not MagicConch.API.TriggerMagicConch('ordinary').success and usage==1)
            -- Exact ownership guard, even BEFORE AR's next update callback.
            players[1].inventory[901]=0
            assert(MagicConch.API.GetNextResultReservation()==nil)
            assert(not AR.isOpen()); AR.onUpdate()
            players[2].inventory[901]=2; state.state='idle'; assert(AR.hasOwner())
            assert(not AR.getSelection()); AR.cycle()
            assert(AR.getSelection().type=='positive'); AR.reset()
            assert(not AR.isOpen() and not MagicConch.API.GetNextResultReservation())
        """)

    def test_c_immediately_cycles_and_never_intercepts_native_controls(self):
        self.install_provider()
        self.lua.execute("""
            pressed[341]=true; AR.onUpdate(); assert(not AR.isOpen(),'Ctrl belongs to the game')
            pressed={[67]=true}; paused=true; AR.onUpdate(); assert(not AR.isOpen())
            paused=false; AR.onUpdate(); assert(not AR.isOpen(),'held key across pause is not a new press')
            pressed={}; AR.onUpdate(); pressed={[67]=true}; AR.onUpdate()
            assert(AR.getSelection().type=='positive')
            for i=1,180 do AR.onUpdate(); AR.onRender(); assert(AR.getSelection().type=='positive') end
            pressed={[262]=true,[341]=true,[257]=true,[256]=true}
            for i=1,180 do AR.onUpdate(); assert(AR.getSelection().type=='positive') end
            assert(AR.onInput==nil and AR.confirm==nil,'no native input interception or direct use')
            pressed={[67]=true}; AR.onUpdate(); assert(AR.getSelection().type=='negative')
            pressed={}; AR.onRender(); pressed={[67]=true}; AR.onRender()
            assert(AR.getSelection().type=='neutral','short tap on render frames must be detected')
            AR.onUpdate(); assert(AR.getSelection().type=='neutral','update must not duplicate render press')
            pressed={}; AR.onRender(); pressed={[67]=true}; AR.onRender()
            assert(AR.getSelection().type=='positive' and usage==0)
        """)

    def test_c_order_ignores_zero_probability_usage_and_unequal_provider_reply_pools(self):
        self.install_provider()
        self.lua.execute('''
            -- Installed provider has 8 positive, 8 negative and 4 neutral replies.
            for _,weights in ipairs({{100,0,0},{0,100,0},{0,0,100},{0,0,0},{5,90,5}}) do
                MagicConch.Config.chances={positive=weights[1],negative=weights[2],neutral=weights[3]}
                for _,language in ipairs({'KR','EN'}) do
                    MagicConch.Config.language=language; AR.reset()
                    for _,kind in ipairs({'positive','negative','neutral','positive','negative','neutral'}) do
                        usage=usage+7 -- external usage changes must not advance selection
                        local before=usage
                        pressed={[67]=true}; AR.onUpdate()
                        for i=1,20 do assert(AR.getSelection().type==kind) end
                        assert(usage==before)
                        pressed={}; AR.onUpdate(); assert(AR.getSelection().type==kind)
                    end
                end
            end
        ''')

    def test_old_or_throwing_provider_cannot_offer_an_unforced_choice(self):
        self.lua.execute("""
            players[1].inventory[901]=1
            MagicConch.API.TriggerMagicConch=function() error('must not activate') end
            assert(not AR.getSelection()); assert(not AR.cycle())
            MagicConch.API.PreviewResult=function() error('bad provider') end
            assert(not AR.getSelection() and #errors==1)
            MagicConch=nil; assert(not AR.cycle())
        """)

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

    def test_compact_chooser_has_only_three_categories_and_coownership_has_one_panel(self):
        self.install_provider()
        self.lua.execute("""
            local function render()
                draws={}; spriteDraws={}; AR.onRender(); M.onRender()
                for _,d in ipairs(draws) do assert(d.y<MagicConch.Config.iconY-30 and d.scale<=0.65) end
            end
            render(); assert(#draws==2 and draws[2].text=='C: 다음 답변 변경' and #spriteDraws==1)
            for _,expected in ipairs({'다음: 긍정','다음: 부정','다음: 중립','다음: 긍정'}) do
                AR.cycle(); render()
                assert(#draws==2 and draws[2].text==expected and #spriteDraws==1)
            end
            assert(AR.getSelection().type=='positive' and usage==0)
            players[1].inventory[900]=1
            render(); assert(#draws==2,'Real Eyes must yield to a reserved choice')
            assert(M.getPrediction().type==AR.getSelection().type,'forecast also sees provider reservation')
            AR.cancel(); render()
            assert(#draws==4 and draws[2].text:find('예측 #1: ',1,true)==1)
            assert(draws[4].text=='C: 다음 답변 변경' and #spriteDraws==2)
            players[1].inventory[901]=0; AR.onUpdate(); render()
            assert(#draws==2 and #spriteDraws==1,'removing glasses leaves only foresight')
            players[1].inventory[900]=0; render(); assert(#draws==0)
        """)

    def test_keyboard_reserves_without_using_then_native_activation_consumes_once(self):
        self.install_provider()
        self.lua.execute("""
            players[1].inventory[900]=1
            pressed={[67]=true}; AR.onUpdate()
            pressed={}; AR.onUpdate(); pressed={[67]=true}; AR.onUpdate()
            assert(AR.getSelection().type=='negative')
            pressed={[257]=true}; AR.onUpdate(); assert(usage==0 and AR.isOpen())
            local forecast=M.getPrediction(); assert(forecast.type=='negative')
            assert(apiModule.ExecuteMagicConchSequence('hotkey'))
            assert(usage==1 and state.pendingType=='negative' and not AR.isOpen())
            assert(M.getPrediction().useNumber==2)
            for i=1,60 do AR.onUpdate(); AR.onRender() end
            assert(usage==1 and MagicConch.Config.forcedReply=='None')
        """)

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
