-- Historical side/furrow author. Use directions.lua for the current directional draft.
-- Re-running this file replaces the preview ANM2 without the later Sleep integration.
-- Native Aseprite artwork. Ox cells stay 48x34; furrow cells stay 40x40.
-- No resizing or traced artwork. The matching ANM2 is a preview, not runtime data.
local root=assert(app.params.root)
local out=app.fs.joinPath(root,'docs/previews/ox-revision')
local source=app.fs.joinPath(root,'resources/gfx/effects')
local function palette(t)
  local p={}
  for k,h in pairs(t) do p[k]=app.pixelColor.rgba(
    tonumber(h:sub(1,2),16),tonumber(h:sub(3,4),16),tonumber(h:sub(5,6),16),255) end
  return p
end
local yellow=palette{K='161316',D='68432b',S='936030',M='b9823e',L='d4a15b',
  U='ceb184',u='96794f',H='ede0b8',h='b6a581',E='f2e4c5'}
local black=palette{K='111318',D='242731',S='343d4a',M='465260',L='687583',
  U='818b90',u='555f6d',H='ded7bd',h='a09c8b',E='e9e3ce'}
local oxLayers={'Far legs and tail','Body and muscle planes','Near legs and hooves','Horns ears and head'}
local function drawer(im,p,ox,oy)
  local d={}
  function d.pixel(x,y,k)
    assert(x>=0 and x<48 and y>=0 and y<34,'ox pixel outside its cell')
    im:drawPixel(x+ox,y+oy,p[k])
  end
  function d.row(x,y,s)
    for n=1,#s do local k=s:sub(n,n);if k~='.' then d.pixel(x+n-1,y,k) end end
  end
  function d.poly(k,points)
    local miny,maxy=33,0
    for _,v in ipairs(points) do miny=math.min(miny,v[2]);maxy=math.max(maxy,v[2]) end
    for y=miny,maxy do
      for x=0,47 do
        local inside=false
        local j=#points
        for i=1,#points do
          local a,b=points[i],points[j]
          if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
          j=i
        end
        if inside then d.pixel(x,y,k) end
      end
    end
  end
  return d
end
local function makeProject(key,w,h,names)
  local s=Sprite(w,h,ColorMode.RGB)
  local ref=s.layers[1];ref.name='Approved previous revision - hidden reference'
  local previous=key=='conch_ox' and 'previous_ox.png' or 'previous_furrow.png'
  s:newCel(ref,1,Image{fromFile=app.fs.joinPath(out,previous)},Point(0,0))
  ref.isVisible=false;ref.isEditable=false
  local images={}
  for i,name in ipairs(names) do
    images[i]=Image(w,h,ColorMode.RGB)
    local l=s:newLayer();l.name=name
  end
  return s,images
end
local function finish(s,images,key)
  for i,im in ipairs(images) do s:newCel(s.layers[i+1],1,im,Point(0,0)) end
  s:saveAs(app.fs.joinPath(out,key..'.aseprite'))
  s:saveCopyAs(app.fs.joinPath(out,key..'.png'))
  print(key..': '..s.width..'x'..s.height..', '..#s.layers..' layers')
  s:close()
end

local s,images=makeProject('conch_ox',432,68,oxLayers)
-- Contact, settle, push, pass for alternating sides. Each hoof has a genuine
-- lifted return, while the body sinks only after contact. The head lags it.
local stride={3,2,0,-2,-3,-1,1,3}
local lift={0,0,0,0,1,3,2,0}
local steps={
  {body=1,head=1,delay=6},{body=2,head=2,delay=5},
  {body=1,head=2,delay=4},{body=0,head=1,delay=3},
  {body=1,head=1,delay=6},{body=2,head=2,delay=5},
  {body=1,head=2,delay=4},{body=0,head=1,delay=3},
  {body=0,head=0,delay=1,idle=true}
}
for colorIndex,p in ipairs({yellow,black}) do
  for frame,step in ipairs(steps) do
    local cx=(frame-1)*48;local cy=(colorIndex-1)*34;local bob=step.body
    local function legPose(phase)
      if step.idle then return 0,0 end
      local i=((frame-1+phase)%8)+1
      return stride[i],lift[i]
    end
    local back=drawer(images[1],p,cx,cy)
    -- Dark far-side limbs remain distinct from the brighter near-side limbs.
    for _,leg in ipairs({{14,6},{28,4}}) do
      local x=leg[1];local v,up=legPose(leg[2])
      back.poly('K',{{x-2,20+bob},{x+4,20+bob},{x+3,25},{x+v+2,29-up},{x+v+4,29-up},{x+v+4,31-up},{x+v-2,31-up},{x+v-2,27-up},{x-2,25}})
      back.poly('D',{{x,21+bob},{x+2,21+bob},{x+1,26-up},{x+v+1,28-up},{x+v+1,29-up},{x+v,29-up},{x,26-up}})
    end
    back.poly('K',{{8,12+bob},{5,13+bob},{3,17+bob},{3,24},{6,25},{8,22},{6,20},{6,16},{9,15+bob}})
    back.row(5,16+bob,'S');back.row(4,18+bob,'S');back.row(4,19+bob,'S')
    back.row(4,22,'DD');back.row(4,23,'D')

    local body=drawer(images[2],p,cx,cy+bob)
    body.poly('K',{{6,13},{9,10},{15,9},{19,7},{23,5},{29,5},{33,8},{35,12},{36,18},{35,22},{32,25},{27,24},{22,25},{17,24},{12,25},{8,22},{6,18}})
    body.poly('M',{{8,13},{11,11},{17,11},{21,8},{25,7},{29,7},{32,9},{34,13},{34,20},{31,23},{27,22},{21,23},{16,22},{12,23},{10,21},{8,18}})
    body.poly('S',{{9,17},{12,16},{17,18},{21,19},{26,18},{29,20},{34,19},{32,23},{27,22},{21,23},{16,22},{12,23},{10,21}})
    body.poly('L',{{10,12},{14,11},{18,11},{22,8},{26,7},{29,8},{26,10},{22,11},{19,14},{13,14},{10,15}})
    -- Haunch: one broad lit volume and a short curved crease, no fur noise.
    body.poly('S',{{11,15},{13,14},{17,15},{19,18},{18,21},{16,23},{12,22},{10,20},{10,18}})
    body.poly('M',{{11,16},{13,15},{16,16},{17,18},{17,20},{15,22},{12,21},{11,19}})
    body.row(12,16,'LLL');body.row(12,17,'LL');body.row(17,18,'S')
    -- High shoulder, thick neck and deltoid, separated into a few flat planes.
    body.poly('S',{{27,10},{25,13},{25,18},{27,21},{31,24},{34,21},{34,16},{32,12},{29,10}})
    body.poly('M',{{27,12},{29,11},{32,14},{33,19},{31,22},{28,20},{27,17}})
    body.poly('L',{{28,12},{30,12},{32,15},{32,17},{30,17},{28,15}})
    body.row(20,16,'SS');body.row(19,17,'S');body.row(20,18,'SS')
    body.row(24,11,'M');body.row(24,12,'M');body.row(24,13,'S')

    local legs=drawer(images[3],p,cx,cy)
    local function nearLeg(x,phase,front)
      local v,up=legPose(phase)
      legs.poly('K',{{x-2,21+bob},{x+4,21+bob},{x+4,25},{x+v+2,28-up},{x+v+4,29-up},{x+v+4,32-up},{x+v-3,32-up},{x+v-3,29-up},{x+v-2,27-up},{x-2,25}})
      legs.poly('S',{{x,22+bob},{x+3,22+bob},{x+2,26-up},{x+v+1,29-up},{x+v+2,30-up},{x+v-1,30-up},{x+v-1,27-up},{x,25}})
      legs.row(x,22+bob,'MM');legs.row(x,23+bob,'M')
      legs.row(x+v-2,30-up,'DDDDD');legs.row(x+v-2,31-up,'KKKKK')
      legs.pixel(x+v,30-up,'K')
      if front then legs.row(x,24+bob,'L') end
    end
    nearLeg(11,2,false);nearLeg(30,0,true)
    -- Remove only buried joint contours. Genuine outer contours/hooves remain.
    local function solid(layer,x,y)
      return x>=0 and x<48 and y>=0 and y<34 and
        app.pixelColor.rgbaA(images[layer]:getPixel(cx+x,cy+y))>0
    end
    local function joined(x,y) return solid(2,x,y) or solid(3,x,y) end
    for y=20,28 do for x=5,36 do
      if images[3]:getPixel(cx+x,cy+y)==p.K and solid(2,x,y) and
        joined(x-1,y) and joined(x+1,y) and joined(x,y-1) and joined(x,y+1) then
        legs.pixel(x,y,'S')
      end
    end end

    local head=drawer(images[4],p,cx,cy+step.head)
    head.poly('K',{{29,2},{32,3},{32,6},{35,8},{35,11},{32,11},{29,8},{28,5},{28,3}})
    head.poly('h',{{30,4},{31,4},{31,7},{34,9},{33,10},{30,7}})
    head.row(29,3,'H');head.row(30,5,'H')
    head.poly('K',{{40,3},{44,2},{44,7},{42,10},{38,12},{35,11},{36,8},{40,6}})
    head.poly('H',{{42,4},{43,4},{43,7},{40,10},{38,10},{38,9},{41,7}})
    head.row(38,10,'hh')
    head.poly('K',{{27,10},{31,10},{34,12},{32,15},{29,15},{26,13}})
    head.row(28,11,'SS');head.row(28,12,'uSM');head.row(29,13,'SM')
    head.poly('K',{{32,9},{37,9},{40,11},{41,15},{44,17},{45,19},{45,22},{43,24},{37,24},{34,22},{32,20},{30,15},{30,11}})
    head.poly('M',{{32,11},{36,10},{38,12},{39,15},{41,18},{40,21},{37,22},{35,20},{33,18},{32,15}})
    head.poly('L',{{32,11},{35,10},{37,11},{37,13},{34,14},{32,14}})
    head.poly('S',{{34,16},{37,15},{40,17},{40,21},{37,22},{35,20}})
    -- Heavy brow and a tiny exposed eye; broad muzzle and nostril below it.
    head.row(35,13,'KKKK');head.row(36,14,'EK');head.row(37,15,'K')
    head.poly('K',{{38,17},{43,17},{45,19},{45,22},{43,24},{37,24},{36,22},{36,19}})
    head.poly('U',{{39,18},{42,18},{44,20},{44,22},{41,23},{38,22},{37,20}})
    head.row(38,21,'uuuuu');head.row(39,22,'uuu');head.row(42,19,'K');head.row(41,20,'KK')
    head.row(39,23,'KKKK')
    -- The neck meets the torso through a warm/cool shadow, not a black plate.
    local function headJoined(x,y) return joined(x,y) or solid(4,x,y) end
    for y=15+step.head,22+step.head do for x=30,34 do
      if images[4]:getPixel(cx+x,cy+y)==p.K and solid(2,x,y) and
        headJoined(x-1,y) and headJoined(x+1,y) and headJoined(x,y-1) and headJoined(x,y+1) then
        images[4]:drawPixel(cx+x,cy+y,p.S)
      end
    end end
  end
end
finish(s,images,'conch_ox')

-- Preview animation asset: the GIF and a future runtime application use these
-- same durations, crops and pivots. Merely slowing a GIF is not the animation.
do
  local lines={'<AnimatedActor>', '  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />',
    '  <Content><Spritesheets><Spritesheet Id="0" Path="conch_ox.png" /></Spritesheets>',
    '    <Layers><Layer Id="0" Name="body" SpritesheetId="0" /></Layers><Nulls /><Events /></Content>',
    '  <Animations DefaultAnimation="YellowIdle">'}
  local attrs='XPosition="0" YPosition="0" XScale="100" YScale="100" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false"'
  for index,name in ipairs({'Yellow','Black'}) do
    for _,idle in ipairs({false,true}) do
      local duration=idle and 1 or 36
      lines[#lines+1]=string.format('    <Animation Name="%s%s" FrameNum="%d" Loop="true">',name,idle and 'Idle' or 'Walk',duration)
      lines[#lines+1]=string.format('      <RootAnimation><Frame %s Delay="%d" /></RootAnimation>',attrs,duration)
      lines[#lines+1]='      <LayerAnimations><LayerAnimation LayerId="0" Visible="true">'
      for frame=idle and 9 or 1,idle and 9 or 8 do
        lines[#lines+1]=string.format('        <Frame %s Delay="%d" XCrop="%d" YCrop="%d" Width="48" Height="34" XPivot="24" YPivot="32" />',attrs,steps[frame].delay,(frame-1)*48,(index-1)*34)
      end
      lines[#lines+1]='      </LayerAnimation></LayerAnimations><NullAnimations /><Triggers /></Animation>'
    end
  end
  lines[#lines+1]='  </Animations></AnimatedActor>'
  local file=assert(io.open(app.fs.joinPath(out,'conch_ox.anm2'),'wb'))
  file:write(table.concat(lines,'\n')..'\n');file:close()
end

local soilNames={'Broken soil ridges','Dark plough cuts','Clods and small stones'}
local fs,soil=makeProject('conch_ox_furrow',160,40,soilNames)
local soilPalettes={
  palette{K='55402a',D='61452a',S='705032',M='7d5a39',L='89653f'},
  palette{K='37333a',D='3e3a41',S='484249',M='514b51',L='5c545a'}
}
-- The channels join across x=0/39; the other edges are ragged/transparent.
-- Each local tile is painted directly; the vertical variant transposes pixels.
local wave={0,0,0,0,1,1,1,0,0,0,-1,-1,-1,0,0,0,0,1,1,2,2,1,1,0,0,-1,-1,-1,0,0,1,1,1,0,0,0,0,0,0,0}
local width={0,0,1,1,1,0,0,-1,-1,0,0,1,1,0,0,0,1,1,0,0,0,-1,-1,0,0,1,1,1,0,0,-1,-1,0,0,1,1,0,0,0,0}
for c,p in ipairs(soilPalettes) do
  local tile={Image(40,40,ColorMode.RGB),Image(40,40,ColorMode.RGB),Image(40,40,ColorMode.RGB)}
  local function px(l,x,y,k)
    assert(x>=0 and x<40 and y>=0 and y<40)
    tile[l]:drawPixel(x,y,p[k])
  end
  -- Broad disturbed earth ties the cuts together, instead of separate rails.
  for x=0,39 do
    local top=2+wave[x+1]
    local bottom=37+wave[((x+11)%40)+1]
    for y=top,bottom do
      local edge=y==top or y==bottom
      px(1,x,y,edge and 'D' or 'S')
    end
  end
  for row,base in ipairs({11,28}) do
    for x=0,39 do
      local idx=row==1 and x+1 or ((40-x)%40)+1
      local y=base+wave[idx]
      local top=y-5-width[idx];local bottom=y+4+width[((x+17)%40)+1]
      for yy=top,bottom do
        local k=yy<y-2 and 'M' or 'D'
        px(1,x,yy,k)
      end
      px(2,x,y-1,'K');px(2,x,y,'K');px(2,x,y+1,'K')
      if x%13>=4 and x%13<=8 then px(2,x,y+2,'K') end
      if x%17>=4 and x%17<=10 then px(1,x,top,'L') end
    end
  end
  -- Individually shaped clods: broad planes and broken lower edges, no pebble noise.
  local clods={
    {3,3,{'..DD','DLLLM','DMMMMMD','.SSSDD','..DD'}},
    {18,4,{'.DDD','DLLMM','DMMMSD','.DSSD','..DD'}},
    {31,2,{'..DD','.DLMM','DMMMMMD','.SMMSD','..DDD'}},
    {8,15,{'..DD','.DMMM','DLLMMMD','DMMMMSD','.DSSDD','..DD'}},
    {24,18,{'.DDD','DLLLMD','DMMMMMD','.SSSDD','..DD'}},
    {1,21,{'..DD','.DLMMD','DMMMMD','.DSSD','..DD'}},
    {15,23,{'.DD','DLMMD','DMMMSD','.SSDD','..D'}},
    {32,30,{'..DD','.DLLMD','DMMMMD','.SSSD','..DD'}},
    {4,34,{'.DD','DLMMMD','DMMMSD','.DDDD'}},
    {21,33,{'.DDD','DLLMMD','DMMMSD','.SSDD','..D'}}
  }
  for _,clod in ipairs(clods) do
    for dy,row in ipairs(clod[3]) do
      for dx=1,#row do
        local k=row:sub(dx,dx)
        if k~='.' then px(3,clod[1]+dx-1,clod[2]+dy-1,k) end
      end
    end
  end
  for orientation=0,1 do
    local offset=((c-1)*2+orientation)*40
    for y=0,39 do for x=0,39 do
      -- Paint each final pixel on one layer only, so transparent strokes cannot
      -- accumulate opacity where the editable soil layers overlap.
      local top=0
      for l=1,3 do if app.pixelColor.rgbaA(tile[l]:getPixel(x,y))>0 then top=l end end
      if top>0 then
      local value=tile[top]:getPixel(x,y)
      local alpha=128
      local outerTop=2+wave[x+1];local outerBottom=37+wave[((x+11)%40)+1]
      if y<=outerTop+1 or y>=outerBottom-1 then alpha=80 end
      value=app.pixelColor.rgba(app.pixelColor.rgbaR(value),app.pixelColor.rgbaG(value),app.pixelColor.rgbaB(value),alpha)
      local dx,dy=x,y
      if orientation==1 then dx,dy=y,x end
      soil[top]:drawPixel(offset+dx,dy,value)
      end
    end end
  end
end
finish(fs,soil,'conch_ox_furrow')
