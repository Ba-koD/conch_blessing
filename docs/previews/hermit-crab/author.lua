-- Native-pixel source for the applied front-only poses and walk cycles.
-- Normal forms are authored on 32x32. Larger pose studies are authored on 48x48.
local root=assert(app.params.root)
local out=app.params.out or app.fs.joinPath(root,'docs/previews/hermit-crab')
local palette={
 K='17141c',S='4f586f',M='7d91ac',L='b2c5cc',H='e2e5d9',
 B='302933',D='493845',R='976b70',T='c19a91',E='f1eadb',
}
local colors={}
for k,h in pairs(palette) do colors[k]=app.pixelColor.rgba(tonumber(h:sub(1,2),16),tonumber(h:sub(3,4),16),tonumber(h:sub(5,6),16),255) end
local function painter(im,mask)
 local p={}
 function p.dot(x,y,c)
  assert(x>=0 and y>=0 and x<im.width and y<im.height,'native pixel outside canvas')
  if mask and app.pixelColor.rgbaA(mask:getPixel(x,y))==0 then return end
  im:drawPixel(x,y,assert(colors[c],c))
 end
 function p.row(x,y,s) for i=1,#s do local c=s:sub(i,i);if c~='.' then p.dot(x+i-1,y,c) end end end
 function p.line(x1,y1,x2,y2,c)
  local dx,dy=math.abs(x2-x1),-math.abs(y2-y1);local sx=x1<x2 and 1 or -1;local sy=y1<y2 and 1 or -1;local err=dx+dy
  while true do p.dot(x1,y1,c);if x1==x2 and y1==y2 then break end;local e=2*err;if e>=dy then err=err+dy;x1=x1+sx end;if e<=dx then err=err+dx;y1=y1+sy end end
 end
 function p.poly(v,c)
  local miny,maxy=im.height,0;for _,a in ipairs(v) do miny=math.min(miny,a[2]);maxy=math.max(maxy,a[2]) end
  for y=miny,maxy do
   local xs={};for i=1,#v do local a,b=v[i],v[i%#v+1]
    if (a[2]<=y and b[2]>y) or (b[2]<=y and a[2]>y) then xs[#xs+1]=a[1]+(y-a[2])*(b[1]-a[1])/(b[2]-a[2]) end
   end
   table.sort(xs);for i=1,#xs,2 do if xs[i+1] then for x=math.ceil(xs[i]),math.floor(xs[i+1]) do p.dot(x,y,c) end end end
  end
  for i=1,#v do local a,b=v[i],v[i%#v+1];p.line(a[1],a[2],b[1],b[2],c) end
 end
 return p
end
local layerNames={'Visible legs','Conch shell','Dark face and round eyes','Arms and pincers','Actual trinket icons','Foreground grip'}
local master=Sprite(48,48,ColorMode.RGB)
for i,name in ipairs(layerNames) do local l=i==1 and master.layers[1] or master:newLayer();l.name=name end
master.layers[5].name='Trinkets are rendered separately'
for i=1,2 do local l=master:newLayer();l.name='Original trinket '..i..' - unscaled reference';l.isVisible=false end
local atlas=Image(384,240,ColorMode.RGB);local gripAtlas=Image(384,240,ColorMode.RGB)
local manifest=assert(io.open(app.fs.joinPath(out,'attachments.tsv'),'w'))
manifest:write('mode\tdirection\tstep\tsize\tcell_x\tcell_y\tframe\tslot1_x\tslot1_bottom\tslot1_scale\tslot1_min_top\tslot2_x\tslot2_bottom\tslot2_scale\tslot2_min_top\n')
local frames={}
local function draw(mode,row,step)
 local big=mode:sub(1,4)=='bffs';local size=big and 48 or 32
 local bob=(step==2 or step==6) and -1 or 0
 local sprite=Sprite(size,size,ColorMode.RGB);local layers={}
 for i,name in ipairs(layerNames) do
  local l=i==1 and sprite.layers[1] or sprite:newLayer();l.name=name
  local im=Image(size,size,ColorMode.RGB);layers[i]={layer=l,im=im,p=painter(im)}
 end
 local legImages,legMasks={},{}
 if step%4~=0 then for i=1,6 do legImages[i]=Image(size,size,ColorMode.RGB) end end
 local function legPainter(leg)
  local base=legImages[leg] and painter(legImages[leg],legMasks[leg]) or layers[1].p
  local phase=(step+(({0,4,0,4,0,4})[leg]))%8+1
  local swing=({0,1,1,0,0,-1,-1,0})[phase]
  local lift=({0,-1,-2,-1,0,0,0,0})[phase]*(big and 1 or 0.5)
  local function point(x,y)
   local weight=math.max(0,math.min(1,(y-(big and 30 or 24))/(big and 14 or 6)))
   local dx=math.floor(weight*swing+0.5)
   local dy=math.floor(weight*lift+(1-weight)*bob+0.5)
   return math.max(1,math.min(size-2,x+dx)),math.max(1,math.min(size-2,y+dy))
  end
  local lp={}
  function lp.poly(v,c) local q={};for _,a in ipairs(v) do local x,y=point(a[1],a[2]);q[#q+1]={x,y} end;base.poly(q,c) end
  function lp.line(x,y,u,v,c) x,y=point(x,y);u,v=point(u,v);base.line(x,y,u,v,c) end
  function lp.dot(x,y,c) x,y=point(x,y);base.dot(x,y,c) end
  function lp.row(x,y,s) for i=1,#s do lp.dot(x+i-1,y,s:sub(i,i)) end end
  return lp
 end
 local p=layers[1].p
 -- Six coloured legs with separate feet and open spaces between the knees.
 -- The front claws sit above the walking legs rather than merging into them.
 local paths=big and {
  {{14,30},{8,33},{5,36},{5,39},{7,39},{9,36},{16,33}},{{15,33},{10,37},{9,41},{10,43},{12,43},{13,39},{18,35}},{{19,35},{16,40},{16,44},{18,45},{20,44},{20,39},{22,36}},
  {{34,30},{40,33},{43,36},{43,39},{41,39},{39,36},{32,33}},{{33,33},{38,37},{39,41},{38,43},{36,43},{35,39},{30,35}},{{29,35},{32,40},{32,44},{30,45},{28,44},{28,39},{26,36}},
 } or {
  {{9,24},{5,25},{2,27},{2,29},{4,29},{5,27},{10,26}},{{11,25},{8,27},{7,29},{8,30},{10,30},{10,28},{13,26}},{{14,26},{12,28},{12,30},{14,30},{15,27}},
  {{23,24},{27,25},{30,27},{30,29},{28,29},{27,27},{22,26}},{{21,25},{24,27},{25,29},{24,30},{22,30},{22,28},{19,26}},{{18,26},{20,28},{20,30},{18,30},{17,27}},
 }
 for i,v in ipairs(paths) do
  legPainter(i).poly(v,'K')
  if legImages[i] then legMasks[i]=Image(legImages[i]) end
 end
 if big then
  p=legPainter(1)
  p.poly({{14,31},{9,34},{6,37},{6,38},{8,35},{15,32}},'R');p.line(9,34,7,36,'T')
  p=legPainter(2)
  p.poly({{16,34},{11,38},{10,41},{11,42},{12,38},{17,35}},'R');p.line(11,38,10,40,'T')
  p=legPainter(3)
  p.poly({{20,36},{17,41},{17,43},{18,44},{19,43},{19,39}},'R');p.line(18,39,17,42,'T')
  p=legPainter(4)
  p.poly({{34,31},{39,34},{42,37},{42,38},{40,35},{33,32}},'R');p.line(39,34,41,36,'T')
  p=legPainter(5)
  p.poly({{32,34},{37,38},{38,41},{37,42},{36,38},{31,35}},'R');p.line(37,38,38,40,'T')
  p=legPainter(6)
  p.poly({{28,36},{31,41},{31,43},{30,44},{29,43},{29,39}},'R');p.line(30,39,31,42,'T')
 else
  p=legPainter(1)
  p.poly({{8,25},{5,26},{3,28},{3,27},{6,25}},'R');p.row(4,26,'TTR');p.dot(3,28,'T')
  p=legPainter(2)
  p.poly({{11,26},{9,28},{8,29},{9,29},{10,27}},'R');p.dot(9,27,'T')
  p=legPainter(3);p.line(13,27,13,29,'T')
  p=legPainter(4)
  p.poly({{24,25},{27,26},{29,28},{29,27},{26,25}},'R');p.row(26,26,'RTT');p.dot(29,28,'T')
  p=legPainter(5)
  p.poly({{21,26},{23,28},{24,29},{23,29},{22,27}},'R');p.dot(23,27,'T')
  p=legPainter(6);p.line(19,27,19,29,'T')
 end
 for _,im in ipairs(legImages) do layers[1].im:drawImage(im,Point(0,0)) end
 p=layers[2].p
 if big then
  p.poly({{26,3},{29,3},{31,5},{31,8},{35,10},{36,14},{39,17},{39,25},{37,30},{33,34},{17,35},{11,31},{9,25},{10,19},{8,13},{13,16},{17,12},{20,11},{20,7},{24,7},{24,5}},'K')
  p.poly({{26,4},{28,4},{30,6},{29,9},{34,11},{35,15},{38,18},{38,25},{35,30},{31,33},{17,33},{12,30},{10,25},{11,19},{10,16},{14,18},{18,14},{22,12},{21,9},{25,9},{25,6}},'S')
  p.poly({{26,5},{28,5},{29,7},{25,8},{22,9},{23,11},{30,11},{33,13},{34,16},{29,14},{23,13},{19,15},{14,19},{12,23},{12,28},{15,31},{18,32},{17,27},{19,20},{27,18},{33,20},{36,24},{36,19},{33,16},{29,15},{24,14}},'M')
  p.poly({{26,5},{28,5},{28,6},{25,7},{25,6}},'H')
  p.poly({{22,9},{27,9},{31,11},{31,12},{27,11},{23,11}},'L')
  p.poly({{18,14},{23,13},{28,14},{32,16},{33,18},{28,16},{23,15},{19,16},{14,20},{13,24},{12,23},{13,19}},'L')
  p.row(18,14,'HHH');p.row(15,17,'HH');p.row(13,20,'H')
  p.line(29,8,31,9,'S');p.line(24,12,29,13,'S')
  p.poly({{37,19},{41,18},{39,22},{37,22}},'K');p.row(38,20,'LM')
 else
  p.poly({{18,2},{20,2},{22,4},{22,6},{25,8},{25,11},{27,14},{27,20},{25,24},{21,26},{10,26},{6,22},{6,16},{5,10},{9,12},{12,9},{14,8},{14,5},{17,4}},'K')
  p.poly({{18,3},{20,3},{21,4},{20,6},{24,9},{24,12},{26,15},{26,20},{23,24},{20,25},{10,25},{7,21},{7,16},{7,12},{10,14},{13,10},{16,9},{15,6},{18,5}},'S')
  p.poly({{18,3},{20,4},{18,5},{16,6},{17,8},{21,8},{23,10},{23,12},{20,11},{16,10},{12,12},{9,16},{8,21},{10,23},{11,19},{14,14},{20,13},{24,15},{25,18},{25,14},{21,12},{16,11}},'M')
  p.row(18,3,'HL');p.row(16,6,'LLM');p.row(17,7,'HLLM');p.row(21,8,'LM')
  p.poly({{12,12},{16,11},{20,12},{23,14},{20,13},{16,12},{13,13},{10,16},{9,20},{8,20},{9,16}},'L')
  p.row(13,12,'HH');p.dot(10,15,'H');p.dot(8,17,'L')
  p.poly({{25,15},{28,14},{27,17},{26,18}},'K');p.dot(26,16,'M')
 end
 p=layers[3].p
 if big then
  p.poly({{21,18},{28,18},{33,20},{35,25},{34,31},{30,35},{19,35},{15,32},{14,26},{16,21}},'K')
  p.poly({{21,20},{28,20},{32,22},{33,26},{31,31},{28,33},{20,33},{17,31},{16,26},{18,22}},'B')
  p.poly({{18,29},{21,31},{29,31},{32,28},{31,32},{28,34},{20,34},{17,31}},'D')
  p.row(18,24,'EEE');p.row(18,25,'EEEE');p.row(18,26,'EEEE');p.row(19,27,'EE')
  p.row(28,24,'EEE');p.row(27,25,'EEEE');p.row(27,26,'EEEE');p.row(28,27,'EE')
  p.row(23,29,'KK');p.row(24,30,'R')
 else
  p.poly({{14,14},{19,14},{23,16},{24,20},{23,24},{20,26},{12,26},{9,23},{9,18},{11,15}},'K')
  p.poly({{14,15},{19,15},{22,17},{23,20},{21,24},{18,25},{12,24},{10,22},{10,18},{12,16}},'B')
  p.poly({{11,22},{14,23},{20,23},{22,21},{21,24},{18,25},{13,25}},'D')
  p.row(12,17,'EE');p.row(11,18,'EEE');p.row(12,19,'EE')
  p.row(19,17,'EE');p.row(19,18,'EEE');p.row(19,19,'EE')
  p.row(15,21,'KK');p.dot(16,22,'R')
 end
 p=layers[4].p
 local function claw(x,y,flip,large,raised)
  -- Offset fingers form an open pincer, with a broad palm and narrow wrist.
  local rows
  if raised then rows={
   '..KK....K..','.KTTK..KTK.','KTTTK..KTRK','KTTRK..KRRK','KTTRRKKRRRK','.KTRRRRRRK.','..KRRRRRK..','...KRRRK...','....KKK....',
  }
  elseif large then rows={
   '...KKKKKK..','..KTTTTTTK.','.KTTTRRKKK.','KTTRRRK....','KTRRRRK....','KRRRRRRKK..','.KRRRRRRTK.','..KRRRRKKK.','...KKKKK...',
  }
  else rows={
   '...KKKK..','.KKTTTTK.','KTTRRKKK.','KTRRK....','KTRRRKK..','.KRRRRTK.','..KKKKK..',
  } end
  for j,s in ipairs(rows) do
   if flip then s=s:reverse() end
   p.row(x,y+j-1,s)
  end
 end
 if mode=='bffs-claws' or mode=='bffs-one' then
  p.poly({{14,28},{11,29},{8,27},{5,23},{5,20},{8,20},{9,24},{12,26},{15,26}},'K')
  p.poly({{7,21},{7,23},{10,26},{12,27},{13,27},{11,25},{8,22}},'R');p.line(8,24,10,26,'T')
  claw(1,13,false,true,true)
  if mode=='bffs-claws' then
   p.poly({{34,28},{37,29},{40,27},{43,23},{43,20},{40,20},{39,24},{36,26},{33,26}},'K')
   p.poly({{41,21},{41,23},{38,26},{36,27},{35,27},{37,25},{40,22}},'R');p.line(40,24,38,26,'T')
   claw(36,13,true,true,true)
  else
   -- The empty right claw stays gathered low in front.
   p.poly({{34,28},{38,30},{37,33},{33,35},{30,34},{32,31}},'K');p.line(36,31,33,33,'R')
   claw(29,29,true,true,false)
  end
 elseif big then
  p.poly({{14,28},{10,30},{11,33},{15,35},{18,34},{16,31}},'K');p.line(12,31,15,33,'R')
  p.poly({{34,28},{38,30},{37,33},{33,35},{30,34},{32,31}},'K');p.line(36,31,33,33,'R')
  claw(9,29,false,true,false);claw(29,29,true,true,false)
 else
  p.poly({{10,20},{7,21},{7,24},{11,26},{13,24}},'K');p.line(8,22,11,24,'R')
  p.poly({{22,20},{25,21},{25,24},{21,26},{19,24}},'K');p.line(24,22,21,24,'R')
  claw(5,20,false,false,false);claw(19,20,true,false,false)
 end

 -- Remove the few protruding shell tips and square up the nearby contour.
 -- All face pixels and the accepted shell colour areas stay on their native grid.
 local shell=layers[2].im
 local erase=big and {{41,18},{40,18}} or {{28,14}}
 for _,q in ipairs(erase) do shell:drawPixel(q[1],q[2],0) end
 local contour=big and {{13,16},{14,15},{15,14},{16,13},{17,12},{18,11},{19,10}} or {{10,11},{11,10},{12,9},{13,8},{14,7},{15,6}}
 for _,q in ipairs(contour) do
  for x=0,q[2]-1 do shell:drawPixel(x,q[1],0) end
  layers[2].p.dot(q[2],q[1],'K')
 end
 if big then layers[2].p.dot(39,19,'K') else layers[2].p.dot(27,15,'K') end
 if not big then
  -- Three curling shell ridges, authored directly on the 32px shell.
  -- Keep the approved outer contour; separate each lit lip from its shadow.
  local rows={
   {17,4,'MMLM'},{17,5,'LLMS'},{16,6,'HLLMS'},
   {16,7,'SMMLMS'},{16,8,'LLLMMM'},{15,9,'LMMMMLLMS'},
   {14,10,'MSSMMMMMLS'},{8,16,'ML'},
   {7,17,'LM'},{7,18,'LM'},{7,19,'LM'},
   {25,17,'LM'},{25,18,'MS'},{25,19,'LS'},
  }
  for _,r in ipairs(rows) do for i=1,#r[3] do
   local x,y=r[1]+i-1,r[2];local previous=shell:getPixel(x,y)
   if app.pixelColor.rgbaA(previous)>0 and previous~=colors.K then layers[2].p.dot(x,y,r[3]:sub(i,i)) end
  end end
 end
 -- Carry the original PNG at a fixed display scale. No cropped miniature is
 -- painted into the crab frame. The exact source files are also kept as hidden
 -- unscaled reference cels in the Aseprite document.
 local slots={}
 if mode=='carry-one' then
  -- top just under the eyes (row 19); a short icon sits on the fingertips
  slots={{16,28,0.5625,20}}
 elseif mode=='bffs-one' then
  slots={{7,19.5,0.75}}
 elseif mode=='bffs-claws' then
  slots={{7,19.5,0.75},{40.5,19.5,0.75}}
 end
 local function grip(x,y,s)
  for i=1,#s do
   layers[6].p.dot(x+i-1,y,s:sub(i,i))
  end
 end
 if mode=='carry-one' then
  grip(12,25,'KT');grip(19,25,'TK')
 elseif mode=='bffs-one' then
  grip(3,18,'KT');grip(9,18,'TK')
 elseif mode=='bffs-claws' then
  grip(3,18,'KT');grip(9,18,'TK');grip(37,18,'KT');grip(44,18,'TK')
 end
 -- The shell, face, arms and carried objects share a one-pixel weight shift.
 -- Feet have their own alternating lift; they are not translated as one image.
 if bob~=0 then
  for i=2,6 do local moved=Image(size,size,ColorMode.RGB);moved:drawImage(layers[i].im,Point(0,bob));layers[i].im=moved end
  for _,slot in ipairs(slots) do slot[2]=slot[2]+bob;if slot[4] then slot[4]=slot[4]+bob end end
 end
 for _,v in ipairs(layers) do sprite:newCel(v.layer,1,v.im,Point(0,0)) end
 layers[6].layer.isVisible=false -- runtime draws these fingertips after the actual item
 if step==0 then sprite:saveCopyAs(app.fs.joinPath(out,mode..'.png')) end
 local flat=Image(size,size,ColorMode.RGB);flat:drawSprite(sprite,1,Point(0,0))
 local offset=big and Point(0,0) or Point(8,12)
 local cellX,cellY=step*48,row*48
 atlas:drawImage(flat,Point(cellX+offset.x,cellY+offset.y))
 gripAtlas:drawImage(layers[6].im,Point(cellX+offset.x,cellY+offset.y))
 local f=#frames==0 and master.frames[1] or master:newEmptyFrame();frames[#frames+1]=f
 f.duration=0.1
 for i,v in ipairs(layers) do master:newCel(master.layers[i],f,v.im,offset) end
 local files={'trinket_035_curvedhorn.png','trinket_001_swallowedpenny.png'}
 for i,slot in ipairs(slots) do
  local original=Image{fromFile=app.fs.joinPath(root,'../../extracted_resources/resources/gfx/items/trinkets/'..files[i])}
  master:newCel(master.layers[6+i],f,original,Point(offset.x+math.floor(slot[1])-16,offset.y+math.floor(slot[2])-28))
 end
 local values={mode,'front',step,size,cellX,cellY,#frames}
 for i=1,2 do for j=1,4 do values[#values+1]=slots[i] and slots[i][j] or '' end end
 for i,v in ipairs(values) do values[i]=tostring(v) end
 manifest:write(table.concat(values,'\t')..'\n')
 sprite:close()
end
for row,mode in ipairs({'shell-base','carry-one','bffs-empty','bffs-one','bffs-claws'}) do
 for step=0,7 do draw(mode,row-1,step) end
end
-- Set ranges only after appending frames, so Aseprite cannot extend an earlier
-- tag when its final frame was the old end of the timeline.
for row,mode in ipairs({'shell-base','carry-one','bffs-empty','bffs-one','bffs-claws'}) do
 local tag=master:newTag(master.frames[(row-1)*8+1],master.frames[row*8]);tag.name=mode..'-walk-front'
end
manifest:close()
atlas:saveAs(app.fs.joinPath(out,'directions_sheet.png'))
gripAtlas:saveAs(app.fs.joinPath(out,'grip_sheet.png'))
master:saveAs(app.fs.joinPath(out,'hermit_crab_proposals.aseprite'));master:close()
print('Saved native source: five front poses, eight-frame walks, separate grip overlay and 1.5x carried icons')
