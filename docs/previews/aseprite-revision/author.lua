-- Native 32x32 pixels authored through Aseprite; no resizing or quantization.
-- Run: aseprite -b --script-param root=REPO --script author.lua
local root = assert(app.params.root, 'Pass the repository root')
local out = app.fs.joinPath(root, 'docs/previews/aseprite-revision')
local originals = app.fs.joinPath(root, 'resources/gfx/items/collectibles')
local function color(hex)
  return app.pixelColor.rgba(tonumber(hex:sub(1,2),16),
    tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16),255)
end
local function palette(values)
  local result={}
  for key,value in pairs(values) do result[key]=color(value) end
  return result
end
local function pixels(image, pal, rows)
  for _,row in ipairs(rows) do
    local y,x,text=row[1],row[2],row[3]
    assert(y>=0 and y<32 and x>=0 and x+#text<=32)
    for i=1,#text do
      local key=text:sub(i,i)
      if key~='.' then image:drawPixel(x+i-1,y,assert(pal[key],key)) end
    end
  end
end
local function layer(sprite,name,pal,rows)
  local image=Image(32,32,ColorMode.RGB)
  pixels(image,pal,rows)
  local result=sprite:newLayer()
  result.name=name
  sprite:newCel(result,1,image,Point(0,0))
  return image,result
end
local function project(key)
  local sprite=Sprite(32,32,ColorMode.RGB)
  local reference=sprite.layers[1]
  reference.name='Original - hidden reference'
  sprite:newCel(reference,1,Image{fromFile=app.fs.joinPath(originals,key..'.png')},Point(0,0))
  reference.isVisible=false
  reference.isEditable=false
  return sprite
end
local function save(sprite,key)
  sprite:saveAs(app.fs.joinPath(out,key..'.aseprite'))
  sprite:saveCopyAs(app.fs.joinPath(out,key..'.png'))
  print('Saved '..key..': 32x32, '..#sprite.layers..' layers')
  sprite:close()
end

local swordPalette={K='1b1420',H='ded0c6',L='ada0b5',M='64536f',D='3a293e',S='261e2e',
  R='dc4254',r='8f273f',g='f48a69',G='c4ad80',b='72504d'}
swordPalette.s=swordPalette.S
-- Native diagonal construction: point (29,2), guard (10,22), pommel (5,28).
-- The blade is drawn in this orientation; no rotated/scaled upright sword is used.
local blade={
  {2,29,'K'},{3,28,'KLK'},{4,27,'KLsK'},{5,26,'KLMDK'},
  {6,24,'KKLMDsK'},{7,22,'KKLMMDsK'},{8,21,'KLMMDsK'},
  {9,20,'KLMMssK'},{10,19,'KLMMssK'},{11,18,'KLMMDsK'},
  {12,17,'KLMMDsK'},{13,17,'KLMssK'},{14,15,'KLMMsssK'},
  {15,14,'KLMMDsK'},{16,13,'KLMMDsK'},{17,12,'KLMMDsK'},
  {18,10,'KKLMMDssK'},{19,10,'KLMMDsK'},{20,10,'KLMDsK'},
  {21,10,'KKKKK'}
}
local hilt={
  {15,7,'K'},{16,6,'KGK'},{17,5,'KGGK'},
  {18,5,'KGbK'},{19,6,'KGbK'},{20,7,'KGbDK'},
  {21,8,'KbDDDK'},{22,9,'KDDGbK'},{23,10,'KDDGbK'},
  {24,11,'KDDGbK'},{25,12,'KbGGGK'},{26,13,'KbbGGK'},
  {27,14,'KKKKK'},{24,19,'K'},{25,18,'KGK'},{26,16,'KGGK'},
  {21,8,'KrrrK'},{22,7,'KrgKRrK'},{23,8,'KrRrK'},{24,9,'KKK'},
  {24,7,'KbK'},{25,6,'KbDK'},{26,5,'KbDrK'},{27,4,'KGbK'},
  {28,3,'KGRK'},{29,4,'KK'}
}
do
  local sprite=project('tyrfing')
  local p=palette(swordPalette)
  layer(sprite,'Long diagonal blade - taper and reverse edge',p,blade)
  layer(sprite,'Red fracture within the blade',p,{
    {6,26,'r'},{7,25,'R'},{8,24,'g'},{9,23,'R'},
    {10,22,'R'},{11,21,'R.r'},{12,20,'rRr'},
    {13,20,'R'},{14,19,'g'},{15,17,'Rr'},
    {16,16,'R'},{17,15,'r'},{18,14,'R'},{19,13,'r'}
  })
  layer(sprite,'Diagonal horned guard and compact grip',p,hilt)
  save(sprite,'tyrfing')
end
do
  local sprite=project('sealed_demon_sword')
  local muted={}
  for k,v in pairs(swordPalette) do muted[k]=v end
  muted.R='594044';muted.r='3b303a';muted.g='92745e'
  layer(sprite,'Long diagonal blade - subdued steel',palette(muted),blade)
  layer(sprite,'Diagonal guard and compact grip',palette(muted),hilt)
  local p=palette{K='1c1720',t='998568',T='d1bd92',W='f0dfb4',R='bd3b42',r='6a2634',H='e27463'}
  layer(sprite,'Two bindings and connecting cord',p,{
    {7,21,'KtK'},{8,21,'KWWtK'},{9,22,'KWWtK'},
    {10,23,'KtK'},{11,24,'K'},
    {14,14,'KtK'},{15,14,'KWWtK'},{16,15,'KWWtK'},
    {17,16,'KtK'},{18,17,'K'},
    {10,22,'t'},{11,21,'t'},{12,20,'t'},{13,19,'t'},{14,18,'t'},{15,17,'t'}
  })
  layer(sprite,'Wax seal',p,{
    {10,20,'KKK'},{11,19,'KHRrK'},{12,19,'KRRrK'},
    {13,19,'KrRrK'},{14,20,'KKK'}
  })
  save(sprite,'sealed_demon_sword')
end

do
  local sprite=project('oral_steroids')
  local p=palette{K='20212a',D='354a56',M='587580',L='8da8ad',H='c7d7cc',
    W='e6dfc2',w='a8b4ae',s='6e8a91'}
  -- Preserve the original native silhouette, then redraw the folds and loose pills.
  local original=Image{fromFile=app.fs.joinPath(originals,'oral_steroids.png')}
  local function inside(x,y)
    return x>=0 and x<32 and y>=0 and y<32 and
      app.pixelColor.rgbaA(original:getPixel(x,y))>=128
  end
  local bag,bagLayer=layer(sprite,'Original bag silhouette - hard pixel contour',p,{})
  for y=0,31 do
    for x=0,31 do
      if inside(x,y) then
        local edge=not inside(x-1,y) or not inside(x+1,y) or
          not inside(x,y-1) or not inside(x,y+1)
        bag:drawPixel(x,y,edge and p.K or ((x>=21 or y>=24) and p.D or p.M))
      end
    end
  end
  sprite.cels[#sprite.cels].image=bag
  layer(sprite,'Folded zipper and crumpled plastic',p,{
    {4,11,'LLL'},{5,10,'LHHHLLLL'},{6,9,'LLHHHHHHLLLLLLLL'},
    {7,10,'DDDLLLHHHHHHHLLLL'},{8,10,'MMMDDDLLLHHHHLLL'},
    {9,9,'LMMMMMDDDDLLLLDDD'},{10,9,'LMMMMMMMMDDDDDD'},
    {11,9,'L'},{12,8,'L'},{13,8,'L'},{15,7,'L'},
    {16,7,'L'},{17,7,'s'},{19,21,'s'},{20,21,'s'},
    {21,20,'s'},{22,6,'L'},{23,5,'LL'},{24,6,'Lssssss'},
    {25,9,'DMMsssss'},{26,15,'DDMsss'},{27,20,'DD'}
  })
  layer(sprite,'Nine loose tablets - separated shapes and score lines',p,{
    {11,12,'ww'},{12,11,'wWWw'},{13,11,'wWw'},{14,12,'s'},
    {11,17,'www'},{12,16,'wWsWw'},{13,17,'www'},
    {14,21,'wWw'},{15,21,'wWw'},{16,21,'www'},
    {16,9,'ww'},{17,8,'wWWw'},{18,8,'wWw'},{19,9,'s'},
    {15,15,'ww'},{16,14,'wWWw'},{17,14,'wWw'},{18,15,'s'},
    {18,19,'w'},{19,18,'wWw'},{20,18,'www'},
    {21,8,'www'},{22,7,'wWsWw'},{23,8,'www'},
    {21,14,'ww'},{22,13,'wWWw'},{23,12,'wWWw'},{24,13,'www'},
    {23,19,'ww'},{24,18,'wWWw'},{25,19,'www'}
  })
  layer(sprite,'Creases over the pills',p,{
    {16,12,'sL'},{17,13,'s'},{18,14,'s'},
    {21,18,'Ls'},{22,19,'s'},{23,20,'s'}
  })
  save(sprite,'oral_steroids')
end

do
  local sprite=project('severed_oath')
  local p=palette{K='211c23',S='58676e',M='8fa5a6',L='d1dfd7',W='f0ead5',
    r='741b32',R='c93448',H='ee6a66'}
  -- Direct native redraw, with the open jaws leaning clockwise.
  layer(sprite,'Taut red thread inside the open jaws',p,{
    {8,3,'rrr'},{9,3,'rRRrrr'},{10,5,'rrRRRRrrrr'},
    {11,9,'rrRRRRRrrrr'},{12,13,'rrRRRRRrrrr'},
    {13,17,'rrRRRRRrrrr'},{14,21,'rrRRRRRRr'},{15,27,'rrr'}
  })
  layer(sprite,'Thick left blade and right finger loop',p,{
    {3,11,'K'},{4,10,'KLK'},{5,10,'KLLK'},
    {6,11,'KLLK'},{7,11,'KLLSK'},{8,11,'KLLSK'},
    {9,12,'KLMSK'},{10,12,'KLMSK'},{11,12,'KLMSK'},
    {12,13,'KLMSK'},{13,13,'KLMSK'},{14,14,'KLMSK'},
    {15,14,'KLMSK'},{16,15,'KLMSK'},{17,15,'KLMSK'},
    {18,16,'KLMSK'},{19,17,'KLMSK'},{20,18,'KLMSK'},
    {21,19,'KLMSK'},{22,18,'KKLMSK'},
    {23,16,'KKLLMMKK'},{24,15,'KLLKKKMSK'},
    {25,15,'KLK...KSK'},{26,15,'KLK...KSK'},
    {27,15,'KMK...KSK'},{28,16,'KMSKKMSK'},
    {29,17,'KMMSSK'},{30,18,'KKKK'}
  })
  layer(sprite,'Thick right blade and left finger loop',p,{
    {10,29,'K'},{11,26,'KKLWK'},{12,24,'KLLMSK'},
    {13,22,'KLLMSKK'},{14,20,'KLLMSKK'},
    {15,18,'KLLMSKK'},{16,16,'KLLMSKK'},
    {17,15,'KLMSKK'},{18,14,'KLMSK'},{19,13,'KLMSK'},
    {20,12,'KLMSK'},{21,11,'KLMSK'},{22,10,'KLMSK'},
    {20,6,'KKKK'},{21,4,'KKLLMMKK'},
    {22,3,'KLLKKKMSK'},{23,3,'KLK...KSK'},
    {24,3,'KLK...KSK'},{25,3,'KMK...KSK'},
    {26,4,'KMSKKMSK'},{27,5,'KMMSSK'},{28,6,'KKKK'}
  })
  layer(sprite,'Wide pivot and visible screw',p,{
    {15,15,'KKK'},{16,14,'KLLSK'},{17,14,'KLKSK'},
    {18,14,'KMSSK'},{19,15,'KKK'}
  })
  save(sprite,'severed_oath')
end
