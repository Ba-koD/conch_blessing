-- Native 48x34 animal poses inside an 80x80 transparent equipment canvas.
-- The applied side-view pixels are copied 1:1; new front/back art is native.
local root=assert(app.params.root)
local out=app.fs.joinPath(root,'docs/previews/ox-revision')
local runtime=app.fs.joinPath(root,'resources/gfx/effects')
local function palette(t)
  local p={}
  for k,h in pairs(t) do p[k]=app.pixelColor.rgba(tonumber(h:sub(1,2),16),tonumber(h:sub(3,4),16),tonumber(h:sub(5,6),16),255) end
  return p
end
local yellow=palette{K='161316',D='68432b',S='936030',M='b9823e',L='d4a15b',U='ceb184',u='96794f',H='ede0b8',h='b6a581',E='f2e4c5'}
local black=palette{K='111318',D='242731',S='343d4a',M='465260',L='687583',U='818b90',u='555f6d',H='ded7bd',h='a09c8b',E='e9e3ce'}
local wood=palette{K='211b1b',D='54402d',M='896542',L='b69360',S='525a60',I='879393',H='b9c0b4',R='bda278'}
local function pen(im,p,ox,oy,w,h)
  local d={}
  function d.pixel(x,y,k)
    assert(x>=0 and x<w and y>=0 and y<h,string.format('outside %dx%d: %d,%d',w,h,x,y))
    im:drawPixel(ox+x,oy+y,p[k])
  end
  function d.row(x,y,s)
    for i=1,#s do local k=s:sub(i,i);if k~='.' then d.pixel(x+i-1,y,k) end end
  end
  function d.poly(k,pts)
    local top,bottom=h-1,0
    for _,v in ipairs(pts) do top=math.min(top,v[2]);bottom=math.max(bottom,v[2]) end
    for y=top,bottom do for x=0,w-1 do
      local inside=false;local j=#pts
      for i=1,#pts do
        local a,b=pts[i],pts[j]
        if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
        j=i
      end
      if inside then d.pixel(x,y,k) end
    end end
  end
  return d
end
-- Shared fitted neck gear: the sleep body lies six native pixels lower.
-- Only this worn component is used in Sleep; no beam, handles or share.
local function sideYoke(gear,drop)
  gear.poly('K',{{54,26+drop},{57,27+drop},{58,35+drop},{56,39+drop},{53,37+drop},{53,33+drop}})
  gear.poly('M',{{55,28+drop},{56,29+drop},{56,35+drop},{55,37+drop},{54,35+drop}})
  gear.row(52,26+drop,'KKKKKKK')
  gear.row(52,27+drop,'KLLLMMK')
  gear.row(53,28+drop,'KDDMK')
  gear.row(54,30+drop,'LM');gear.row(54,34+drop,'RR')
  gear.row(54,35+drop,'RD')
end
local s=Sprite(720,480,ColorMode.RGB)
s.layers[1].name='Applied side view - hidden reference'
s:newCel(s.layers[1],1,Image{fromFile=app.fs.joinPath(runtime,'conch_ox.png')},Point(0,0))
s.layers[1].isVisible=false;s.layers[1].isEditable=false
local names={'Trailing wooden plough and iron share','Far legs','Ox body - native pixels','Yoke and straps'}
local images={}
for i,name in ipairs(names) do local layer=s:newLayer();layer.name=name;images[i]=Image(720,480,ColorMode.RGB) end
local side=Image{fromFile=app.fs.joinPath(runtime,'conch_ox.png')}
assert(side.width==432 and side.height==68,'Expected the applied eight-pose side-view sheet')
local stride={3,2,0,-2,-3,-1,1,3}
local lift={0,0,0,0,1,3,2,0}
local bodyBob={1,2,1,0,1,2,1,0,0}
local headBob={1,2,2,1,1,2,2,1,0}
local delays={6,5,4,3,6,5,4,3,1}
for color,p in ipairs({yellow,black}) do
  for direction=0,2 do -- right (left is native FlipX), down, up
    for frame=1,9 do
      local ox=(frame-1)*80;local oy=((color-1)*3+direction)*80
      local bob=bodyBob[frame];local nod=headBob[frame]
      local function pose(phase)
        if frame==9 then return 0,0 end
        local i=((frame-1+phase)%8)+1
        return stride[i],lift[i]
      end
      local far=pen(images[2],p,ox+24,oy+16,48,34)
      local body=pen(images[3],p,ox+24,oy+16,48,34)
      -- Back horns share the side/front crown height (native row 3 at rest).
      local head=pen(images[3],p,ox+24,oy+16+nod+(direction==2 and 1 or 0),48,34)
      local function leg(x,phase,start,near)
        local v,up=pose(phase)
        local reach=math.floor(v/2)
        local foot=31-up
        local draw=near and body or far
        draw.poly('K',{{x-1,start+bob},{x+5,start+bob},{x+5,26},{x+4+reach,foot-2},{x+5+reach,foot},{x+5+reach,foot+1},{x-1+reach,foot+1},{x-1+reach,foot-2},{x,26}})
        draw.poly(near and 'S' or 'D',{{x,start+bob},{x+4,start+bob},{x+3,26},{x+3+reach,foot-1},{x+reach,foot-1},{x+1,25}})
        draw.row(x+reach,foot-1,'DDDD');draw.row(x+reach,foot,'KKKK')
        if near then draw.row(x+1,start+bob,'MM') end
      end
      if direction==0 then
        for y=0,33 do for x=0,47 do
          images[3]:drawPixel(ox+24+x,oy+16+y,side:getPixel((frame-1)*48+x,(color-1)*34+y))
        end end
      elseif direction==1 then
        -- Down: a quadruped viewed from above its broad shoulders, not a biped.
        leg(12,6,17,false);leg(30,4,17,false)
        body.poly('K',{{19,5+bob},{29,5+bob},{34,8+bob},{38,13+bob},{38,20+bob},{35,25+bob},{31,27+bob},{17,27+bob},{12,24+bob},{10,19+bob},{11,13+bob},{15,8+bob}})
        body.poly('M',{{19,7+bob},{28,7+bob},{32,10+bob},{36,14+bob},{36,21+bob},{32,25+bob},{18,25+bob},{14,22+bob},{12,18+bob},{13,13+bob},{16,10+bob}})
        body.poly('L',{{20,7+bob},{27,7+bob},{31,10+bob},{29,13+bob},{20,12+bob},{15,15+bob},{14,12+bob}})
        body.poly('S',{{12,17+bob},{16,15+bob},{20,19+bob},{28,19+bob},{33,15+bob},{36,18+bob},{34,23+bob},{30,26+bob},{18,26+bob},{14,23+bob}})
        leg(14,2,23,true);leg(28,0,23,true)
        -- Rejoin thigh tops with the torso's colour plane.
        body.row(14,23+bob,'SSMMM');body.row(28,23+bob,'MMMSS')
        head.poly('K',{{10,3},{13,3},{13,6},{18,8},{18,12},{14,12},{10,8},{9,5}})
        head.poly('H',{{11,4},{12,4},{12,7},{16,9},{16,10},{14,10},{11,7}})
        head.poly('K',{{35,3},{38,3},{39,5},{38,8},{34,12},{30,12},{30,8},{35,6}})
        head.poly('H',{{36,4},{37,4},{37,7},{34,10},{32,10},{32,9},{36,7}})
        head.poly('K',{{13,11},{17,11},{19,14},{15,16},{11,14}})
        head.poly('K',{{31,11},{35,11},{37,14},{33,16},{29,14}})
        head.row(13,12,'uMM');head.row(32,12,'MMu')
        head.poly('K',{{19,8},{29,8},{33,11},{34,18},{32,23},{28,25},{20,25},{16,23},{14,18},{15,12}})
        head.poly('M',{{19,10},{28,10},{31,12},{32,18},{29,22},{19,22},{16,18},{17,12}})
        head.poly('L',{{20,10},{27,10},{29,12},{28,14},{20,14},{18,12}})
        head.poly('S',{{17,16},{20,17},{28,17},{31,16},{31,20},{28,23},{20,23},{17,20}})
        head.row(17,14,'KKKK');head.row(27,14,'KKKK')
        head.row(18,15,'EEK');head.row(27,15,'KEE')
        head.poly('K',{{19,19},{29,19},{32,21},{32,24},{29,27},{19,27},{16,24},{16,21}})
        head.poly('U',{{20,20},{28,20},{30,22},{30,24},{28,25},{20,25},{18,24},{18,22}})
        head.row(19,23,'uuuuuuuuuu');head.row(20,24,'uuuuuuuu')
        head.row(19,21,'KK');head.row(27,21,'KK');head.row(22,25,'KKKK')
      else
        -- Up: horns and nape above a deep back, rounded haunches and tail.
        leg(12,0,16,false);leg(30,4,16,false)
        head.poly('K',{{13,2},{16,2},{17,5},{20,7},{19,11},{16,10},{13,7},{12,4}})
        head.poly('H',{{14,3},{15,3},{16,6},{18,8},{17,9},{14,6}})
        head.poly('K',{{32,2},{35,2},{36,4},{35,7},{32,10},{29,11},{28,7},{31,5}})
        head.poly('H',{{33,3},{34,3},{34,6},{31,9},{30,8},{32,6}})
        head.poly('K',{{20,6},{28,6},{32,10},{30,14},{18,14},{16,10}})
        head.poly('S',{{20,8},{28,8},{30,10},{28,13},{20,13},{18,10}})
        head.row(20,8,'MMMMMMMM');head.row(21,9,'LLLLLL')
        body.poly('K',{{18,10+bob},{30,10+bob},{34,13+bob},{36,18+bob},{35,24+bob},{32,28+bob},{17,28+bob},{13,24+bob},{12,18+bob},{14,13+bob}})
        body.poly('M',{{18,12+bob},{29,12+bob},{32,14+bob},{34,19+bob},{33,24+bob},{30,26+bob},{18,26+bob},{15,23+bob},{14,18+bob},{16,14+bob}})
        body.poly('L',{{19,12+bob},{27,12+bob},{30,14+bob},{29,17+bob},{24,18+bob},{19,17+bob},{16,19+bob},{16,15+bob}})
        body.poly('S',{{15,20+bob},{20,20+bob},{24,22+bob},{28,20+bob},{33,20+bob},{32,25+bob},{28,27+bob},{19,27+bob},{16,25+bob}})
        body.row(18,22+bob,'MMM');body.row(28,22+bob,'MM')
        leg(16,2,25,true);leg(27,6,25,true)
        body.row(16,25+bob,'SSMMM');body.row(27,25+bob,'MMMSS')
        -- A short tail hangs between the hocks without a black joint ring.
        body.row(24,23+bob,'D');body.row(24,24+bob,'MD');body.row(24,25+bob,'MD')
        body.row(25,26+bob,'DK');body.row(25,27+bob,'DK');body.row(24,28+bob,'KDDK');body.row(25,29+bob,'KK')
      end
      local rear=pen(images[1],wood,ox,oy,80,80)
      local gear=pen(images[4],wood,ox,oy,80,80)
      local jolt=(frame==2 or frame==3 or frame==6 or frame==7) and 1 or 0
      if direction==0 then
        -- Hooves and iron share meet the same ground row (47). The old draft
        -- hung the share 14 pixels below it. Only the handle rocks on impact.
        rear.poly('K',{{12,38+jolt},{53,29+bob},{55,32+bob},{15,42+jolt}})
        rear.poly('M',{{14,38+jolt},{53,30+bob},{54,31+bob},{15,40+jolt}})
        rear.poly('K',{{5,23+jolt},{10,22+jolt},{18,37+jolt},{21,40},{17,43},{13,39+jolt}})
        rear.poly('L',{{7,24+jolt},{9,24+jolt},{16,38+jolt},{18,40},{16,40},{14,37+jolt}})
        rear.row(4,22+jolt,'KKKKKKKK');rear.row(5,23+jolt,'MLLMM');rear.row(5,24+jolt,'KKKKK')
        rear.poly('K',{{10,29+jolt},{28,30+jolt},{26,33+jolt},{12,32+jolt}})
        rear.poly('M',{{12,30+jolt},{26,31+jolt},{25,32+jolt},{13,31+jolt}})
        rear.row(14,30+jolt,'LLL')
        rear.poly('K',{{15,38},{20,38},{22,40},{23,43},{28,44},{25,47},{17,48},{11,46},{10,44}})
        rear.poly('I',{{16,40},{19,39},{21,41},{21,44},{25,45},{22,46},{16,46},{12,44}})
        rear.row(15,41,'HHH');rear.row(13,46,'SSSSSSSSS')
        sideYoke(gear,bob)
      elseif direction==1 then
        -- The distant tool is foreshortened and tucked close behind the ox.
        rear.poly('K',{{40,10},{43,9},{49,17},{54,9},{57,10},{51,21},{50,31},{46,31},{46,21}})
        rear.poly('M',{{42,11},{43,11},{48,18},{55,11},{55,13},{50,21},{49,31},{47,31},{47,20}})
        rear.row(43,13,'KKKKKKKKKK');rear.row(44,14,'MLLMMMLM');rear.row(44,15,'KKKKKKKK')
        rear.poly('K',{{45,16+jolt},{50,16+jolt},{55,20+jolt},{49,24+jolt},{42,20+jolt}})
        rear.poly('I',{{46,17+jolt},{50,17+jolt},{53,20+jolt},{49,22+jolt},{44,20+jolt}})
        rear.row(46,18+jolt,'HH');rear.row(47,21+jolt,'SSS')
        rear.row(32,29+bob,'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK')
        rear.row(33,30+bob,'MLLLLLMMMMMMMMMMMMMMMMMLLLLLMM')
        rear.row(33,31+bob,'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKK')
        -- Exposed wooden ends and the bows read around, not across, the face.
        gear.row(32,30+bob,'KLMMK');gear.row(60,30+bob,'KMMLK')
        gear.row(33,31+bob,'KMDK');gear.row(60,31+bob,'KDMK')
        gear.row(34,32+bob,'KR');gear.row(60,32+bob,'RK')
        gear.row(34,33+bob,'KR');gear.row(60,33+bob,'RK')
        gear.row(35,34+bob,'RD');gear.row(59,34+bob,'DR')
        gear.row(36,35+bob,'DD');gear.row(58,35+bob,'DD')
      else
        -- Up: just a short exposed shaft behind the hocks. The rear extent is
        -- 15 pixels beyond the hooves instead of the previous 29 pixels.
        rear.poly('K',{{46,31},{50,31},{50,54+jolt},{48,56+jolt},{46,54+jolt}})
        rear.poly('M',{{47,32},{49,32},{49,53+jolt},{48,54+jolt},{47,53+jolt}})
        rear.poly('K',{{47,50+jolt},{51,52+jolt},{55,56+jolt},{52,59+jolt},{44,59+jolt},{41,56+jolt}})
        rear.poly('I',{{48,52+jolt},{50,53+jolt},{53,56+jolt},{51,57+jolt},{45,57+jolt},{43,56+jolt}})
        rear.row(46,55+jolt,'HHH');rear.row(45,57+jolt,'SSSSSS')
        rear.poly('K',{{46,54},{49,54},{44,63},{41,63}})
        rear.poly('M',{{46,56},{47,56},{43,61},{42,61}})
        rear.poly('K',{{49,54},{52,54},{57,63},{54,63}})
        rear.poly('M',{{50,56},{51,56},{55,61},{54,61}})
        rear.row(40,62,'KLLMK');rear.row(53,62,'KMLLK')
        gear.row(42,28+bob,'KKKKKKKKKKKK')
        gear.row(38,29+bob,'KKMLLLMMMMMMMMLLLMKK')
        gear.row(38,30+bob,'KMLMDDDDDDDDDDDDMLMK')
        gear.row(39,31+bob,'KKKDDKKKKKKKKDDKKK')
        gear.row(40,32+bob,'RM');gear.row(55,32+bob,'MR')
      end
    end
  end
end
for i,im in ipairs(images) do s:newCel(s.layers[i+1],1,im,Point(0,0)) end
s:saveAs(app.fs.joinPath(out,'conch_ox_directions.aseprite'))
s:saveCopyAs(app.fs.joinPath(out,'conch_ox_directions.png'))
print('Directional ox: 54 native poses, 720x480, layered plough/body/yoke')
s:close()

-- Preserve the applied sleeping body, folded legs and Z animation 1:1.
local sleep=Image{fromFile=app.fs.joinPath(runtime,'conch_ox_sleep.png')}
assert(sleep.width==192 and sleep.height==68,'Expected four 48x34 sleep poses per colour')
local resting=Sprite(320,160,ColorMode.RGB)
resting.layers[1].name='Applied sleeping body - native pixels'
local sleepBody=Image(320,160,ColorMode.RGB)
local sleepGear=Image(320,160,ColorMode.RGB)
for color=0,1 do for frame=0,3 do
  for y=0,33 do for x=0,47 do
    sleepBody:drawPixel(frame*80+24+x,color*80+16+y,sleep:getPixel(frame*48+x,color*34+y))
  end end
  sideYoke(pen(sleepGear,wood,frame*80,color*80,80,80),6)
end end
resting:newCel(resting.layers[1],1,sleepBody,Point(0,0))
local sleepYoke=resting:newLayer();sleepYoke.name='Worn yoke and straps only'
resting:newCel(sleepYoke,1,sleepGear,Point(0,0))
resting:saveAs(app.fs.joinPath(out,'conch_ox_sleep_equipped.aseprite'))
resting:saveCopyAs(app.fs.joinPath(out,'conch_ox_sleep_equipped.png'))
print('Sleeping ox: applied body preserved; worn gear only, no trailing plough')
resting:close()
