"""Production Real Eyes contracts with engine doubles; no visual/Continue claim."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class RealEyesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            frame,usage,roomIndex,stage=100,0,10,1
            calls,errors,draws,spriteDraws={}, {}, {}, {}
            players={{copies=1},{copies=0}}
            for _,p in ipairs(players) do
                function p:HasCollectible(id) assert(id==900); return self.copies>0 end
                function p:AnimatePickup() end
            end
            hudVisible=true
            descriptor={SafeGridIndex=10,ListIndex=1,Data={}}
            local level={GetCurrentRoomDesc=function() descriptor.SafeGridIndex=roomIndex; return descriptor end,
                GetRoomByIdx=function(_,idx,dim) return dim==0 and descriptor or {} end,
                GetStage=function() return stage end, GetStageType=function() return 0 end,
                GetCurrentRoomIndex=function() return roomIndex end}
            local room={GetSpawnSeed=function() return 451 end,GetDecorationSeed=function() return 779 end}
            game={GetNumPlayers=function() return #players end,GetFrameCount=function() return frame end,
                GetLevel=function() return level end,GetRoom=function() return room end,
                GetSeeds=function() return {GetStartSeed=function() return 321088 end} end,
                GetHUD=function() return {IsVisible=function() return hudVisible end} end,ShakeScreen=function() end}
            Game=function() return game end
            Vector=function(x,y) return {X=x,Y=y} end
            Color=function(...) return {...} end
            KColor=function(r,g,b,a) return {R=r,G=g,B=b,A=a} end
            Isaac={GetPlayer=function(i) return players[i+1] end,GetItemIdByName=function() return 900 end,
                GetScreenWidth=function() return 640 end,GetScreenHeight=function() return 360 end,
                GetTextWidth=function(text) return #text*6 end,
                RenderText=function(text,x,y,r,g,b,a) draws[#draws+1]={text=text,x=x,y=y,r=r,g=g,b=b} end}
            local function newSprite() return {Load=function() end,ReplaceSpritesheet=function() end,
                LoadGraphics=function() end,SetFrame=function() end,Update=function() end,IsLoaded=function() return true end,
                RenderLayer=function(_,layer,pos) spriteDraws[#spriteDraws+1]={layer=layer,pos=pos} end} end
            Sprite=setmetatable({}, {__call=newSprite})
            Font=setmetatable({}, {__call=function() return {
                Load=function() end,IsLoaded=function() return true end,
                GetStringWidthUTF8=function(_,text) return utf8.len(text)*8 end,
                DrawStringScaledUTF8=function(_,text,x,y,sx,sy,color)
                    draws[#draws+1]={text=text,x=x,y=y,scale=sx,r=color.R,g=color.G,b=color.B}
                end} end})
            local en=require('scripts.locale.en'); local kr=require('scripts.locale.kr')
            language='kr'
            local function textIn(lang,path,...)
                local value=lang=='kr' and kr or en
                for key in path:gmatch('[^.]+') do value=value[key] end
                return string.format(value,...)
            end
            ConchBlessing={printError=function(err) errors[#errors+1]=err end,
                Locale={textIn=textIn,text=function(path,...) return textIn(language,path,...) end}}
            ready=true
            MagicConch={Config={enabled=true,iconX=430,iconY=265},API={IsReady=function() return ready end}}
            MagicConch.API.PreviewResult=function(offset)
                calls[#calls+1]=offset
                return {id='answer'..usage,text='answer '..usage,type='positive',usageCount=usage,useNumber=usage+1}
            end
            hostLoaded=package and package.loaded or hostLoaded; package=nil
            M=require('scripts.items.collectibles.real_eyes')
        ''')

    def test_ownership_stack_removal_reacquisition_and_coop(self):
        self.lua.execute('''
            for _,n in ipairs({0,1,2,1,0,1,0}) do
                players[1].copies=n
                local prediction,reason=M.getPrediction()
                assert((prediction~=nil)==(n>0))
                if n==0 then assert(reason=='NO_OWNER') end
            end
            assert(#calls==4,'copies must not multiply reads/answers')
            players[2].copies=1; assert(M.getPrediction())
            players[2].copies=0; M.onRender(); assert(#draws==0 and #spriteDraws==0)
            players={}; assert(not M.hasOwner())
        ''')

    def test_read_only_copy_immediate_usage_and_disabled_changes(self):
        self.lua.execute('''
            for _=1,100 do assert(M.getPrediction().useNumber==1) end
            assert(usage==0); usage=4
            local a=M.getPrediction(); assert(a.useNumber==5); a.text='mutated'
            assert(M.getPrediction().text=='answer 4')
            MagicConch.Config.enabled=false; local n=#calls
            assert(not M.getPrediction()); assert(#calls==n)
            MagicConch.Config.enabled=true; ready=false
            assert(not M.getPrediction()); assert(#calls==n)
            ready=true; assert(M.getPrediction()); assert(#errors==0)
            for _,offset in ipairs(calls) do assert(offset==0) end
        ''')

    def test_missing_api_error_and_malformed_response_recover_without_faking_answer(self):
        self.lua.execute('''
            local original=MagicConch.API.PreviewResult
            MagicConch.API.PreviewResult=nil
            for _=1,5 do assert(not M.getPrediction()) end
            assert(#errors==1)
            MagicConch.API.PreviewResult=function() error('bad provider') end
            for _=1,5 do assert(not M.getPrediction()) end
            assert(#errors==2)
            for _,result in ipairs({false,7,{text='x',type='unknown'},{text='',type='positive'}}) do
                MagicConch.API.PreviewResult=function() return result end
                assert(not M.getPrediction())
            end
            assert(#errors==3)
            MagicConch.API.PreviewResult=original; assert(M.getPrediction())
            MagicConch=nil; assert(not M.getPrediction())
        ''')

    def test_hud_has_prediction_label_above_provider_result_and_respects_anchor(self):
        self.lua.execute('''
            M.onRender()
            assert(#draws==2 and #spriteDraws==1 and #errors==0)
            assert(draws[2].text=='예측 #1: 긍정')
            assert(draws[2].y==265-44 and draws[2].scale==0.65)
            assert(draws[2].y+12<265-30,'above the persistent last-result line')
            assert(spriteDraws[1].layer==1,'pedestal must not be drawn in HUD')
            local first=draws[2]
            MagicConch.Config.iconX=230; MagicConch.Config.iconY=165
            draws={}; M.onRender(); assert(draws[2].x==first.x-200 and draws[2].y==first.y-100)
            draws={}; hudVisible=false; M.onRender(); assert(#draws==0)
            hudVisible=true; players[1].copies=0; M.onRender(); assert(#draws==0)
        ''')

    def test_hud_clamps_long_text_and_missing_cjk_font_has_english_type_fallback(self):
        self.lua.execute('''
            MagicConch.API.PreviewResult=function() return {text=string.rep('가',100),type='negative'} end
            MagicConch.Config.iconX=999; MagicConch.Config.iconY=-99
            M.onRender(); assert(#errors==0)
            assert(#draws==2 and draws[2].text=='예측: 부정','never show the long randomized reply')
            assert(draws[2].x+utf8.len(draws[2].text)*8*draws[2].scale<=640-8 and draws[2].y==4)
            hostLoaded['scripts.items.collectibles.real_eyes']=nil; hostLoaded['scripts.lib.conch_answer_view']=nil
            Font=nil; draws={}
            M=require('scripts.items.collectibles.real_eyes'); M.onRender()
            assert(#draws==2 and draws[2].text=='Prediction: negative')
            assert(#errors==1,'one observable fallback, not a render exception')
        ''')

    def test_live_api_usage_and_status_anchor_ignore_unrelated_popup_position(self):
        self.lua.execute("""
            MagicConch.API.GetCurrentRoomUsage=function() return 7 end
            MagicConch.API.GetResultPosition=function() return {mode='custom',x=200,y=150,anchor='top_left'} end
            assert(M.getPrediction().useNumber==8)
            M.onRender(); assert(draws[2].y==221)
            assert(draws[2].text=='예측 #8: 긍정')
            local first=draws[2]
            MagicConch.API.GetResultPosition=function() return {mode='hud'} end
            draws={}; M.onRender(); assert(draws[2].x==first.x and draws[2].y==first.y)
            MagicConch.Config.iconX=230; MagicConch.Config.iconY=165
            draws={}; M.onRender(); assert(draws[2].x==first.x-200 and draws[2].y==first.y-100)
            MagicConch.API.GetResultPosition=function() error('popup API must not be used') end
            MagicConch.Config.iconX=0/0; MagicConch.Config.iconY=0/0
            draws={}; M.onRender(); assert(#errors==0 and draws[2].y==221)
        """)

    def install_real_provider(self):
        providers = list(ROOT.parent.glob('!magic_conch_*/magic_conch_api.lua'))
        if not providers:
            self.skipTest('optional installed Magic Conch provider reference is unavailable')
        self.lua.globals().provider_root = providers[0].parent.as_posix()
        self.lua.execute('''
            include=function(name) return assert(loadfile(provider_root..'/'..name..'.lua'))() end
            SoundEffect={SOUND_COIN_SLOT=1}; SFXManager=function() return {Play=function() end} end
            Options={Language='kr'}
            MagicConch.Config.language='KR'; MagicConch.Config.forcedReply='None'
            MagicConch.Config.chances={positive=40,neutral=20,negative=40}
            MagicConch.GetCurrentRoomUsage=function() return usage end
            MagicConch.RecordRoomUse=function() usage=usage+1 end
            MagicConch.printDebug=function() end; MagicConch.printError=function() end
            state={state='idle',timer=0,canInput=true,lastInputTime=-100}
            lang=include('magic_conch_lang'); apiModule=include('magic_conch_api')
            apiModule.Init(MagicConch,state,function() return {shake=1,wait=1,display=1,cooldown=0} end,
                lang,{VERSION='test'})
            MagicConch.API=apiModule.CreateInterface()
            assert(type(MagicConch.API.PreviewResult)=='function','installed provider lacks PreviewResult')
        ''')

    def test_installed_provider_preview_matches_actual_activation_across_room_config_and_use(self):
        self.install_real_provider()
        self.lua.execute('''
            math.random=function() error('prediction must not consume random state') end
            for _,forced in ipairs({'None','Positive','Neutral','Negative'}) do
                MagicConch.Config.forcedReply=forced
                for _,code in ipairs({'EN','KR','Auto'}) do
                    MagicConch.Config.language=code
                    for room=10,12 do
                        roomIndex=room; stage=room-9; usage=0
                        for use=1,5 do
                            frame=frame+20; state.state='idle'; state.canInput=true
                            local prediction=M.getPrediction(); assert(prediction.useNumber==use)
                            for _=1,15 do assert(M.getPrediction().id==prediction.id) end
                            assert(usage==use-1)
                            local actual=MagicConch.API.TriggerMagicConch('offline provider contract')
                            assert(actual.success,actual.reason)
                            assert(actual.pendingResult.text==prediction.text and actual.pendingResult.type==prediction.type)
                            assert(usage==use)
                            assert(M.getPrediction().useNumber==use+1,'busy state must show the next unconsumed use')
                        end
                    end
                end
            end
            assert(#errors==0)
        ''')

    def test_provider_state_restoration_and_room_limit_do_not_cache_old_prediction(self):
        self.install_real_provider()
        self.lua.execute('''
            usage=3; roomIndex=17
            local before=M.getPrediction()
            usage=8; roomIndex=19; M.getPrediction()
            usage=3; roomIndex=17 -- restored provider context, not a real Continue test
            hostLoaded['scripts.items.collectibles.real_eyes']=nil; hostLoaded['scripts.lib.conch_answer_view']=nil
            M=require('scripts.items.collectibles.real_eyes')
            local restored=M.getPrediction()
            assert(before.id==restored.id and before.text==restored.text and restored.useNumber==4)
            MagicConch.Config.attemptsPerRoom=3
            assert(M.getPrediction().id==restored.id and usage==3)
            players[1].copies=0; assert(not M.getPrediction())
        ''')


if __name__ == '__main__':
    unittest.main()
