"""Upgrade presentation cannot create attack entities or outlive its room.

Production Lua with Sprite doubles; these checks do not validate engine rendering.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class UpgradeCosmeticsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            callbacks={}; errors={}; visuals={}; sounds=0
            ModCallbacks={MC_POST_UPDATE=1,MC_POST_RENDER=2,MC_POST_NEW_ROOM=3,
                MC_POST_GAME_STARTED=4,MC_PRE_GAME_EXIT=5}
            ConchBlessing={AddCallback=function(_,id,fn) callbacks[id]=fn end,
                printError=function(s) errors[#errors+1]=s end}
            function GetPtrHash(entity) return tostring(entity) end
            EntityPtr=setmetatable({}, {__call=function(_,entity)
                return setmetatable({}, {__index=function(_,key)
                    if key=='Ref' and entity:Exists() then return entity end
                end})
            end})
            Isaac={Spawn=function() error('Cosmetic upgrade attempted entity spawn') end,
                WorldToScreen=function(pos) return pos end}
            Color=setmetatable({Lerp=function(a,b,t)
                local result={}
                for k,v in pairs(a) do result[k]=type(v)=='number' and v+(b[k]-v)*t or v end
                return result
            end}, {__call=function(_,r,g,b,a,ro,go,bo)
                return {R=r,G=g,B=b,A=a or 1,RO=ro or 0,GO=go or 0,BO=bo or 0}
            end})
            SoundEffect={SOUND_HOLY=1,SOUND_POWERUP_SPEWER=2}
            function SFXManager() return {
                Stop=function() error('stops unrelated playback of this sound ID') end,
                Play=function(_,id,volume,delay,loop) assert(not loop); sounds=sounds+1 end,
                AdjustVolume=function() error('changes unrelated playback of this sound ID') end} end
            Sprite=setmetatable({}, {__call=function()
                local s={frame=0,renders=0}
                function s:Load(path) self.path=path; if loadFails then error('missing asset') end end
                function s:IsLoaded() return true end
                function s:Play(name) self.animation=name end
                function s:Update() self.frame=self.frame+1 end
                function s:IsFinished() return self.frame>=24 end
                function s:Render(pos) self.renders=self.renders+1; self.pos=pos end
                visuals[#visuals+1]=s; return s
            end})
            function pickup()
                local p={alive=true,sprite={Color={R=1,G=1,B=1,A=.8,RO=0,GO=0,BO=0,original=true}}}
                function p:Exists() return self.alive end
                function p:GetSprite() return self.sprite end
                return p
            end
            p=pickup(); data={}; pos={X=100,Y=120}
        ''')
        self.lua.globals().T = self.lua.execute((ROOT/'scripts/template.lua').read_text(encoding='utf-8'))

    def test_light_is_sprite_only_and_updates_at_game_tick(self):
        self.lua.execute('''
            assert(T.positive.onAfterChange(pos,p,data)==60)
            assert(#visuals==1 and visuals[1].animation=='Spotlight')
            for i=1,4 do callbacks[2]() end
            assert(visuals[1].frame==0 and visuals[1].renders==4)
            callbacks[1](); assert(visuals[1].frame==1)
            for i=2,24 do callbacks[1]() end
            assert(data.upgradeAnim.lightSprite==nil)
            assert(data.upgradeAnim.frames==36)
        ''')

    def test_missing_art_reports_failure_but_keeps_morph_fade(self):
        self.lua.execute('''
            loadFails=true
            assert(T.positive.onAfterChange(pos,p,data)==60)
            assert(#errors==1 and data.upgradeAnim.lightSprite==nil)
            for i=1,60 do callbacks[1]() end
            assert(data.upgradeAnim==nil and p.sprite.Color.original)
        ''')

    def test_cancellation_only_removes_its_own_visual(self):
        self.lua.execute('''
            q=pickup(); second={}
            T.positive.onAfterChange(pos,p,data)
            T.positive.onAfterChange(pos,q,second)
            T.cancelForPickup(p); callbacks[2]()
            assert(data.upgradeAnim==nil and p.sprite.Color.original)
            assert(second.upgradeAnim and visuals[1].renders==0 and visuals[2].renders==1)
        ''')

    def test_concurrent_default_cues_never_modify_shared_sound_channels(self):
        for kind in ('positive', 'neutral', 'negative'):
            with self.subTest(kind=kind):
                self.lua.execute(f'''
                    q=pickup(); first={{}}; second={{}}; local preset=T.{kind}
                    local before=sounds
                    preset.onBeforeChange(pos,p,first); preset.onBeforeChange(pos,q,second)
                    for i=1,8 do T.updateAllAnimations() end
                    local frames=second.upgradeAnim.frames
                    T.cancelForPickup(p)
                    assert(second.upgradeAnim.frames==frames and sounds==before+2)
                    for i=1,60 do T.updateAllAnimations() end
                    preset.onAfterChange(pos,q,second)
                    for i=1,60 do T.updateAllAnimations() end
                    assert(#T._activeAnimations==0 and q.sprite.Color.original)
                ''')

    def test_room_and_game_boundaries_clear_art_and_restore_color(self):
        for event in (3, 4, 5):
            with self.subTest(callback=event):
                self.lua.execute(f'''
                    T.positive.onAfterChange(pos,p,data)
                    callbacks[{event}]()
                    assert(#T._activeAnimations==0 and data.upgradeAnim==nil)
                    assert(p.sprite.Color.original)
                ''')

    def test_removed_pickup_cannot_render_or_leave_a_visual(self):
        self.lua.execute('''
            T.positive.onAfterChange(pos,p,data); p.alive=false
            callbacks[2](); assert(visuals[1].renders==0)
            callbacks[1](); assert(#T._activeAnimations==0 and data.upgradeAnim==nil)
        ''')

    def test_replacing_animation_clears_previous_light(self):
        self.lua.execute('''
            T.positive.onAfterChange(pos,p,data); old=data.upgradeAnim
            T.neutral.onBeforeChange(pos,p,data)
            assert(old.lightSprite==nil and #T._activeAnimations==1)
            callbacks[2](); assert(visuals[1].renders==0)
        ''')

    def test_debug_mode_logs_default_cue_and_engine_playback(self):
        self.lua.execute('''
            local logs={}; ConchBlessing.printDebug=function(t) logs[#logs+1]=t end
            T.neutral.onBeforeChange(pos,p,data)
            for _,line in ipairs(logs) do assert(not line:find('SOUND',1,true), 'debug off logs no cue') end
            ConchBlessing.Config={debugMode=true}; logs={}
            T.cancelForPickup(p); T.positive.onBeforeChange(pos,p,data)
            local found
            for _,line in ipairs(logs) do if line:find('[Upgrade] SOUND',1,true) then found=line end end
            assert(found=='[Upgrade] SOUND positive id=1 volume=1.00 playing=unknown', tostring(found))
            ConchBlessing.Config=nil
        ''')


if __name__ == '__main__':
    unittest.main()
