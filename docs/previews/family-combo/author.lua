-- Family Combo: a full Binge Eater-like display, with only the lower plate visible.
-- The plate is preserved. Vanilla frames keep their native scale and colours.
-- Small individual tilts were explicitly authorized on 2026-11-08.
-- Separate the original head/body regions so bodies cannot cover another face.
-- The tilted layout is sampled directly on this 32x32 grid, with no redraw or resize.
local root=assert(app.params.root)
local out=app.params.out or app.fs.joinPath(root,'docs/previews/family-combo')
local palette={K='080000',P='f8f7f2',Q='dedbd3',E='a6a29c'}
local colors={}
for key,hex in pairs(palette) do
 colors[key]=app.pixelColor.rgba(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16),255)
end
local sprite=Sprite(32,32,ColorMode.RGB)
local function layer(name,first)
 local target=first and sprite.layers[1] or sprite:newLayer();target.name=name
 local im=Image(32,32,ColorMode.RGB);local draw={}
 function draw.row(x,y,text)
  assert(x>=0 and y>=0 and x+#text<=32 and y<32,name..' row exceeds native canvas')
  for i=1,#text do local key=text:sub(i,i)
   if key~='.' then im:drawPixel(x+i-1,y,assert(colors[key],key)) end
  end
 end
 function draw.finish() sprite:newCel(target,1,im,Point(0,0)) end
 return draw
end

local dish=layer('White plate - shallow oval surface viewed from above',true)
-- This approved plate layer is unchanged. Its native oval ratio
-- follows the supplied reference; a second inner oval describes the shallow well.
local outer={
 {18,12,19},{19,8,23},{20,5,26},{21,3,28},{22,2,29},{23,1,30},
 {24,1,30},{25,1,30},{26,2,29},{27,3,28},{28,5,26},{29,8,23},{30,12,19},
}
for i,r in ipairs(outer) do
 local y,x1,x2=r[1],r[2],r[3]
 if i==1 or i==#outer then dish.row(x1,y,string.rep('K',x2-x1+1))
 else
  local prev,next=outer[i-1],outer[i+1]
  local left=math.max(1,prev[2]-x1,next[2]-x1)
  local right=math.max(1,x2-prev[3],x2-next[3])
  dish.row(x1,y,string.rep('K',left)..string.rep('P',x2-x1+1-left-right)..string.rep('K',right))
 end
end
local inner={
 {20,12,19},{21,8,23},{22,6,25},{23,4,27},
 {24,4,27},{25,6,25},{26,9,22},{27,12,19},
}
for i,r in ipairs(inner) do
 local y,x1,x2=r[1],r[2],r[3]
 if i==1 or i==#inner then dish.row(x1,y,string.rep('E',x2-x1+1))
 else
  local prev,next=inner[i-1],inner[i+1]
  local left=math.max(1,prev[2]-x1,next[2]-x1)
  local right=math.max(1,x2-prev[3],x2-next[3])
  dish.row(x1,y,string.rep('E',left)..string.rep('Q',x2-x1+1-left-right)..string.rep('E',right))
 end
end
dish.finish()



-- Centre positions and clockwise angles in degrees.
-- Ghost is highest; Bobby and Rotten lean at different heights;
-- Maggy sits in the front well; the small figures sit at unequal heights
-- inside the side lip instead of protruding beyond the plate.
local layout={B={7,14,-19},M={16,22,20},R={23,12,-18},G={11,6,-7},W={25,20,15},K={6,22,25}}
local order={'M','W','R','G','K','B'}

local source=app.fs.joinPath(root,'../../extracted_resources/resources/gfx/familiar')
local entries={
 B={'Brother Bobby','familiar_shooters_01_brotherbobby.png',0,32,15.5,10},
 M={'Sister Maggy','familiar_shooters_07_sistermaggie.png',0,32,15.5,10},
 R={'Rotten Baby','familiar_shooters_268_rottenbaby.png',0,32,15.5,10},
 G={'Ghost Baby','familiar_shooters_09_ghostbaby.png',64,32,15.5,10},
 W={'Mini Isaac','familiar_minisaac.png',0,16,7.5,6.5},
 K={'Mini Isaac black','familiar_minisaac_black.png',0,16,7.5,6.5},
}
-- Direct unit-scale inverse rotation on the native canvas. No antialiasing,
-- colour mixing or resize; every written pixel is sampled from the source.
-- The contents meet the existing plate along its curved inner footprint.
-- Only the lower silhouette is tucked behind the side/front lip.
local well={[23]={4,27},[24]={4,27},[25]={5,26},[26]={7,24},[27]={10,21}}
local function insideWell(x,y)
 local edge=well[y];return not edge or (x>=edge[1] and x<=edge[2])
end
local function part(key,head)
 local e=entries[key];local p=layout[key]
 local src=Image{fromFile=app.fs.joinPath(source,e[2])}
 local dest=Image(32,32,ColorMode.RGB)
 local theta=math.rad(p[3]);local c,s=math.cos(theta),math.sin(theta)
 for y=0,27 do for x=0,31 do
  local dx,dy=x-p[1],y-p[2]
  local sx=math.floor(c*dx+s*dy+e[5]+0.5)
  local sy=math.floor(-s*dx+c*dy+e[6]+0.5)
  local ok
  if e[4]==32 then ok=sx>=0 and sx<32 and sy>=0 and sy<32 and ((head and sy<17) or (not head and sy>=17))
  else
   if head then ok=sx>=0 and sx<16 and sy>=0 and sy<16
   else sy=sy-2+16;ok=sx>=0 and sx<16 and sy>=16 and sy<32 end
  end
  if ok and insideWell(x,y) then dest:drawPixel(x,y,src:getPixel(e[3]+sx,sy)) end
 end end
 local l=sprite:newLayer();l.name=e[1]..(head and ' - face' or ' - body')
 sprite:newCel(l,1,dest,Point(0,0))
end
for _,key in ipairs(order) do part(key,false) end
for _,key in ipairs(order) do part(key,true) end
-- Reuse the original plate surface outside the inner footprint as a foreground
-- lip. This changes occlusion, not the approved plate's drawing or palette.
local lip=sprite:newLayer();lip.name='Plate side lip and exposed well'
local exposed=Image(32,32,ColorMode.RGB)
local originalPlate=sprite.layers[1]:cel(1).image
for y=23,27 do for x=0,31 do
 if not insideWell(x,y) then exposed:drawPixel(x,y,originalPlate:getPixel(x,y)) end
end end
sprite:newCel(lip,1,exposed,Point(0,0))
local rim=layer('Curved white front lip below the unchanged familiars')
-- Preserve the approved front lip exactly, joining the exposed side curves.
rim.row(5,28,'KKK'..string.rep('P',16)..'KKK')
rim.row(8,29,'KKKK'..string.rep('Q',8)..'KKKK')
rim.row(12,30,'KKKKKKKK')
rim.finish()

sprite:saveAs(app.fs.joinPath(out,'family_combo.aseprite'))
sprite:saveCopyAs(app.fs.joinPath(out,'family_combo.png'))
print('Saved native 32x32 six-familiar display with '..#sprite.layers..' editable layers')
sprite:close()
