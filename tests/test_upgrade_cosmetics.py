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
            Isaac={Spawn=function() error('Cosmetic upgrade attempted entity spawn') end,
                WorldToScreen=function(pos) return pos end}
            function Color(...) return {...} end
            SoundEffect={SOUND_HOLY=1,SOUND_POWERUP_SPEWER=2}
            function SFXManager() return {Stop=function() end,Play=function() end,AdjustVolume=function() end} end
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
                local p={alive=true,sprite={Color={original=true}}}
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


if __name__ == '__main__':
    unittest.main()
