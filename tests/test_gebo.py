"""Gebo (Cereal's rune): production Lua with engine doubles.

The user's design (2026-11-25): used near a pedestal it may change, the item on
the nearest one within reach turns into one of the items whose number uses the
same digits read as a three-digit tag (Cereal's rule for what a number may
make), a shop item keeps its
price, a rotating pedestal keeps its circle behind the item on show, and an
item with no other arrangement, a quest item or one out of reach stays. While
anyone holds it a pedestal's EID lists what it may become. `cb test gebo`
covers the real card in game.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
EntityType={ENTITY_PICKUP=5,ENTITY_EFFECT=1000}
PickupVariant={PICKUP_COLLECTIBLE=100}
EffectVariant={POOF01=15}
SoundEffect={SOUND_BONE_SNAP=40}
ItemConfig={TAG_QUEST=1<<15}
ModCallbacks={MC_USE_CARD=5,MC_POST_UPDATE=1,MC_POST_RENDER=2,MC_POST_NEW_ROOM=19,MC_POST_GAME_STARTED=15}
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
Vector.Zero=Vector(0,0)
function Color() return {} end
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return setmetatable({},{__index=function(_,k) if k=='Ref' and not e.removed then return e end end}) end
-- items: id -> config; 300 is a quest item, 281 is hidden, 999 is in no pool
items={}
for _,id in ipairs({25,52,118,128,182,218,245,254,281,300,425,452,524,542,999,1019,1091,1109,1190,1901,1910}) do
    items[id]={ID=id,Hidden=(id==281),HasTags=function(self,tag) return id==300 and tag==ItemConfig.TAG_QUEST end,
        IsAvailable=function() return true end}
end
cereal={}
for id,c in pairs(items) do
    -- Cereal's own rule, in short: hidden, quest and pool-less numbers are not made
    cereal[id]=(not c.Hidden) and id~=300 and id~=999
end
ConchBlessing={printError=function(m) lastError=m end,printDebug=function() end,
    PocketData={GEBO={id=88}},
    Locale={text=function(path,...) return path..':'..table.concat({...},'|') end},
    cereal={digitsOf=function(n) local t={} for c in tostring(n):gmatch('%d') do t[#t+1]=tonumber(c) end return t end,
        lookup=function(d) local n=0 for _,x in ipairs(d) do n=n*10+x end
            if not items[n] then return 'none',n end
            return cereal[n] and 'ok' or 'nocraft', n end}}
callbacks={}
function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
pickups={}
nextHash=0
function pedestal(id,x,y,extra)
    nextHash=nextHash+1
    local p={hash=nextHash,Type=5,Variant=100,SubType=id,Position=Vector(x,y),PositionOffset=Vector(0,0),Price=0,
        ShopItemId=-1,AutoUpdatePrice=true,OptionsPickupIndex=0,Touched=false,removed=false}
    for k,v in pairs(extra or {}) do p[k]=v end
    function p:Exists() return not self.removed end
    function p:ToPickup() return self end
    function p:IsShopItem() return self.Price~=0 end
    function p:Morph(t,v,sub,keepPrice) self.SubType=sub; if not keepPrice then self.Price=0 end
        self.OptionsPickupIndex=0; self.morphed=(self.morphed or 0)+1
        if self.cycle then self.cycle={} end end
    if extra and extra.cycle then
        function p:GetCollectibleCycle() return self.cycle end
        function p:RemoveCollectibleCycle() self.cycle={} end
        function p:AddCollectibleCycle(id) self.cycle[#self.cycle+1]=id; return true end
    end
    pickups[#pickups+1]=p
    return p
end
spawned=0
Isaac={GetItemConfig=function() return {GetCollectible=function(_,id) return items[id] end} end,
    FindByType=function(t,v) local out={} for _,p in ipairs(pickups) do
        if not p.removed and p.Type==t and (v==nil or p.Variant==v) then out[#out+1]=p end end return out end,
    Spawn=function() spawned=spawned+1 end,
    GetFrameCount=function() return frame or 1 end,
    GetPlayer=function(i) return players[i+1] end,
    WorldToScreen=function(p) return p end}
players={}
Game=function() return {GetNumPlayers=function() return #players end} end
function SFXManager() return {Play=function() end} end
function player(x,y,cards)
    nextHash=nextHash+1
    local p={hash=nextHash,Position=Vector(x or 100,y or 100),cards=cards or {}}
    function p:Exists() return true end
    function p:IsDead() return false end
    function p:IsCoopGhost() return false end
    function p:GetCard(slot) return self.cards[slot+1] or 0 end
    function p:GetCardRNG() return {RandomInt=function(_,n) return (rollAt or 0)%n end} end
    players[#players+1]=p
    return p
end
local stubs={['scripts.lib.sound_volume']={volume=function(v) return v end}}
require=function(name) return assert(stubs[name],'unexpected require '..name) end
M=dofile(root..'/scripts/items/cards/gebo.lua')
T=M._test
function list(t) local o={} for i,v in ipairs(t) do o[i]=tostring(v) end return table.concat(o,',') end
"""


class GeboTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_rearrangements_are_every_other_order_of_the_digits(self):
        result = self.run_lua('''
            return list(M.rearrangements(182)), list(M.rearrangements(25)), list(M.rearrangements(4)),
                list(M.rearrangements(11)), list(M.rearrangements(105)), #M.rearrangements(1234)
        ''')
        # read as a three-digit tag (user decision 2026-11-25): 25 is 025, 4 is 004, and a
        # zero moved to the front shortens the number (105 -> 15, 51); no repeats, not itself
        self.assertEqual(result, ('128,218,281,812,821', '52,205,250,502,520', '40,400', '101,110',
                                  '15,51,150,501,510', 23))

    def test_options_are_items_that_are_not_hidden_quest_or_locked(self):
        # 281 is hidden, 812/821 are no items: 182 may become 128 or 218. An item in no
        # pool counts (user request 2026-11-25): 999 is in none, so 9999 is not its
        # concern, but 118 may become 181, White Pony, which is in no pool.
        result = self.run_lua('''
            items[181]={ID=181,HasTags=function() return false end,IsAvailable=function() return true end}
            cereal[181]=false
            items[452].IsAvailable=function() return false end
            return list(M.options(182)), list(M.options(25)), list(M.options(118)), list(M.options(245))
        ''')
        self.assertEqual(result, ('128,218', '52', '181', '254,425,524,542'))

    def test_a_use_changes_the_nearest_pedestal_into_one_of_its_options(self):
        result = self.run_lua('''
            local p=player(100,100,{88}); local a=pedestal(182,100,150); local b=pedestal(245,100,40)
            rollAt=1; M.onUseCard(nil,88,p)
            return a.SubType, b.SubType, spawned
        ''')
        self.assertEqual(result, (218, 245, 1))

    def test_only_a_pedestal_that_may_change_is_marked(self):
        result = self.run_lua('''
            local p=player(100,100,{88})
            local out={}
            local function try(id,x,y,extra)
                for _,e in ipairs(pickups) do e.removed=true end
                pedestal(id,x,y,extra); M.onUpdate()
                out[#out+1]=tostring(T.target(p)~=nil)
            end
            try(182,100,170)                 -- in reach (70)
            try(182,100,190)                 -- out of reach (90)
            try(118,100,150)                 -- no other arrangement
            try(300,100,150)                 -- a quest item
            try(182,100,150,{Price=15})      -- a shop item changes too
            try(0,100,150)                   -- an empty pedestal
            ConchBlessing.upgrade={isAnimatingPickup=function() return true end}
            try(182,100,150)                 -- the Magic Conch is upgrading it
            return table.concat(out,',')
        ''')
        self.assertEqual(result, 'true,false,false,false,true,false,false')

    def test_the_rune_in_another_slot_marks_nothing(self):
        result = self.run_lua('''
            local p=player(100,100,{0,88}); pedestal(182,100,150); M.onUpdate()
            return tostring(T.target(p)~=nil), M.anyHolder()
        ''')
        self.assertEqual(result, ('false', True))

    def test_a_shop_item_keeps_its_price_and_choice_group(self):
        result = self.run_lua('''
            local p=player(100,100,{88}); local a=pedestal(182,100,150,{Price=15,AutoUpdatePrice=false,OptionsPickupIndex=4})
            M.onUseCard(nil,88,p)
            return a.SubType, a.Price, a.AutoUpdatePrice, a.OptionsPickupIndex
        ''')
        self.assertEqual(result, (128, 15, False, 4))

    def test_a_rotating_pedestal_keeps_its_circle(self):
        result = self.run_lua('''
            local p=player(100,100,{88}); local a=pedestal(182,100,150,{cycle={25,118}})
            M.onUseCard(nil,88,p)
            return a.SubType, list(a.cycle)
        ''')
        self.assertEqual(result, (128, '25,118'))

    def test_with_nothing_in_reach_nothing_changes(self):
        result = self.run_lua('''
            local p=player(100,100,{88}); local a=pedestal(182,400,400); local b=pedestal(118,100,140)
            M.onUseCard(nil,88,p)
            return a.SubType, b.SubType, spawned
        ''')
        self.assertEqual(result, (182, 118, 0))

    def test_other_cards_are_ignored(self):
        result = self.run_lua('''
            local p=player(100,100,{88}); local a=pedestal(182,100,150)
            M.onUseCard(nil,77,p)
            return a.SubType
        ''')
        self.assertEqual(result, 182)

    def test_the_eid_line_lists_what_it_may_become(self):
        result = self.run_lua('''
            local a=M.eidLine(182); local b=M.eidLine(118); local c=M.eidLine(300)
            local d=M.describe({ObjSubType=25,Description='desc'}).Description
            return a, b, tostring(c), d
        ''')
        self.assertEqual(result, ('ui.gebo.options:88|{{Collectible128}}{{Collectible218}}', 'ui.gebo.none:88',
                                  'nil', 'descui.gebo.options:88|{{Collectible52}}'))

    def test_four_digit_numbers_rearrange_too(self):
        result = self.run_lua('return list(M.options(1019))')
        self.assertEqual(result, '1091,1109,1190,1901,1910')


if __name__ == "__main__":
    unittest.main()
