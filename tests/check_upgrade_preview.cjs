const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {createCanvas,Image:CanvasImage}=require('@napi-rs/canvas');
const html=fs.readFileSync('docs/previews/item-upgrade-player.html','utf8');
const source=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const json=id=>JSON.parse(html.match(new RegExp('id="'+id+'"[^>]*>([\\s\\S]*?)</script>'))[1]);
const rows=json('upgrade-data');assert.equal(rows.length,37);new vm.Script(source);
assert(!/<select\b/.test(html));assert(!/fetch\(|https?:\/\//.test(source));
async function run(reduced=false){
 const els=new Map(),frames=new Map(),probe={},audio=[];let next=0,now=0;
 const stage=createCanvas(640,360),ctx=stage.getContext('2d'),calls=[];
 const imageDraw=ctx.drawImage.bind(ctx);ctx.drawImage=(...args)=>{for(const arg of args.slice(1))assert(Number.isFinite(arg));args.transform=ctx.getTransform();calls.push(args);imageDraw(...args);};
 function make(id=''){return {id,value:'',textContent:'',checked:id==='upgrade-sound',children:[],events:{},attrs:{},hidden:false,style:{setProperty(k,v){this[k]=v;}},addEventListener(k,f){this.events[k]=f;},append(e){this.children.push(e);},setAttribute(k,v){this.attrs[k]=v;},getBoundingClientRect(){return {height:this.id==='library'?98:32};}};}
 const el=id=>{if(!els.has(id))els.set(id,make(id));return els.get(id);};
 const root=el('conch-upgrade-preview'),canvas=el('upgrade-stage');canvas.getContext=()=>ctx;
 root.querySelector=s=>s==='canvas'?canvas:el(s.slice(1));root.children=['header','controls','game-frame','details','timeline','library','footer'].map(el);
 for(const id of ['upgrade-data','room-assets','effect-animations','effect-audio','kronos-pets'])el(id).textContent=JSON.stringify(json(id));
 const pending=[];
 class Image extends CanvasImage{set src(v){this.url=v;pending.push(new Promise((resolve,reject)=>{const cb=this.onload;this.onload=()=>{try{cb?.();resolve();}catch(e){reject(e);}};this.onerror=reject;}));super.src=Buffer.from(v.split(',')[1],'base64');}get src(){return this.url;}}
 class AudioContext{constructor(){audio.push('context');this.destination={};}resume(){return Promise.resolve();}decodeAudioData(b){return Promise.resolve({byteLength:b.byteLength});}createGain(){return {gain:{},connect(){}};}createBufferSource(){const s={connect(){},start(){audio.push('start');},stop(){audio.push('stop');}};return s;}}
 const window={AudioContext,innerWidth:1280,innerHeight:900,events:{},addEventListener(k,f){this.events[k]=f;},matchMedia:()=>({matches:reduced})};
 const document={body:{},events:{},getElementById:el,createElement:t=>t==='canvas'?createCanvas(32,32):make(),addEventListener(k,f){this.events[k]=f;}};
 const inject='Object.assign(probe,{drawItem,rainWetness,voidMotes,itemPose,phaseTime,floodLevel,screenShake,soundCues,scenery,animations,duration,selectKronosPets,kronosTiming,ringState,ringPoint,ringBlack,kronosPhase,petCatalog,run:()=>kronosRun,setKronosStyle:(v)=>{kronosStyle=v;choose("KRONOS");},select:(key)=>choose(key),render:(key,t)=>{choose(key);time=t;draw();},setTime:(t)=>{time=t;draw();}});})();';
 vm.runInNewContext(source.replace('})();',inject),{probe,document,window,Image,atob:v=>Buffer.from(v,'base64').toString('binary'),performance:{now:()=>now},
   localStorage:{getItem(){throw Error('unavailable');},setItem(){throw Error('unavailable');}},
   getComputedStyle:e=>e===root?{rowGap:'12'}:{paddingTop:'16',paddingBottom:'16',paddingLeft:'20',paddingRight:'20'},
   requestAnimationFrame:f=>{frames.set(++next,f);return next;},cancelAnimationFrame:id=>frames.delete(id)});
 await Promise.all(pending);await Promise.resolve();assert.equal(audio.length,0,'Initial render is silent');
 function step(ms){now+=ms;const work=[...frames.values()];frames.clear();for(const fn of work)fn(now);}
 function scrub(t){el('upgrade-time').value=String(t);calls.length=0;el('upgrade-time').events.input();}
 const cards=el('upgrade-items').children;assert.equal(cards.length,rows.length);
 for(let i=0;i<rows.length;i++){
   cards[i].events.click();assert.equal(frames.size,reduced?0:1);assert.equal(cards.filter(b=>b.attrs['aria-pressed']==='true').length,1);
   for(const t of [0,.5,1,1.43,1.5,1.6,1.75,1.9,2.1,2.3,2.7,probe.duration()]){
     scrub(t);const s=probe.itemPose(t);assert(Object.values(s).every(Number.isFinite));assert(s.w>=0&&s.h>=0&&s.alpha>=0&&s.alpha<=1);
     if(t===0)assert(calls.some(a=>a[0].src===rows[i].origin),rows[i].key+' begins with original');
     if(t===probe.duration())assert(calls.some(a=>a[0].src===rows[i].icon),rows[i].key+' ends with result');
   }
   const wanted=rows[i].key==='MONEY_TEAR';assert.equal(probe.floodLevel(3.4)>0,wanted,'Only Money = Tears floods the room; Time = Tears has no rain');
   el('upgrade-play').events.click();step(700);el('upgrade-pause').events.click();const frozen=Number(el('upgrade-time').value);assert(frozen>0&&frozen<3.4);assert.equal(frames.size,0);
   el('upgrade-pause').events.click();step(100);assert(Number(el('upgrade-time').value)>frozen);step(6000);assert.equal(frames.size,0);
 }
 probe.select('VOID_DAGGER');const mid=probe.voidMotes(.8),late=probe.voidMotes(1.7);
 mid.forEach((p,i)=>{assert(late[i].size>=p.size*.7&&late[i].alpha===1,'Motes keep their size and density while gathering');assert(Math.hypot(late[i].x-320,late[i].y-167)<=Math.hypot(p.x-320,p.y-167)+.5);});
 assert(probe.voidMotes(50/30).every(p=>p.alpha===1&&Math.hypot(p.x-320,p.y-167)<8),'They knot together on the hilt before the change');
 assert(probe.voidMotes(54/30).every(p=>p.alpha===0&&p.size===0),'They vanish within three ticks of the change');assert(probe.voidMotes(3.4).every(p=>p.alpha===0));
 probe.select('DRAGON');assert.equal(probe.itemPose(69/30).blend,0);assert.equal(probe.itemPose(70/30).blend,1,'The darkness holds until the 70-tick strike');
 assert.deepEqual(Array.from(probe.soundCues(),cue=>cue[1]),['thunder','lightning']);
 assert(probe.soundCues()[0][0]===2/30&&probe.soundCues()[1][0]===probe.phaseTime(),'The rumble starts with the blackout and the strike bangs on the conversion');
 const brightness=t=>{scrub(t);return Array.from(ctx.getImageData(420,240,1,1).data).slice(0,3).reduce((a,b)=>a+b,0);};
 const normal=brightness(0),dim=brightness(.3),dark=brightness(.8),held=brightness(69/30),flash=brightness(70/30),recover=brightness(3);
 assert(normal>dim&&dim>dark,'The rendered room dims before thunder');
 assert(held===dark,'The darkness holds until the strike');
 assert(flash>normal&&recover===normal&&brightness(77/30)===normal,'Darkness clears on strike, with only a brief flash remaining');
 const pixel=(t,x,y)=>{scrub(t);return Array.from(ctx.getImageData(x,y,1,1).data);};
 assert.deepEqual(pixel(.8,338,160),pixel(0,338,160),'Room immediately beside the item retains its real colour');
 const itemPatch=t=>{scrub(t);return Array.from(ctx.getImageData(307,147,26,26).data);};
 assert.deepEqual(itemPatch(.8),itemPatch(0),'The item stays readable inside the aperture');
 const attenuation=(x,y)=>{const base=pixel(0,x,y),shade=pixel(.8,x,y);return shade.slice(0,3).reduce((a,b)=>a+b,0)/base.slice(0,3).reduce((a,b)=>a+b,0);};
 assert(attenuation(356,160)>attenuation(374,160)&&attenuation(374,160)>attenuation(395,160),'Actual rendered light falls off gently into darkness');
 // An item without its own presentation plays the game's default flag animation.
 probe.select('RAT');assert.equal(probe.duration(),4,'The default lasts 120 ticks');
 assert.equal(probe.itemPose(59/30).blend,0);assert.equal(probe.itemPose(60/30).blend,1,'The default changes the item on tick 60');
 assert.equal(JSON.stringify(probe.soundCues()),JSON.stringify([[0,'holy',1,1]]),'The positive default plays Holy as the tint begins');
 const glow=t=>{scrub(t);return Array.from(ctx.getImageData(307,147,26,26).data).reduce((a,b,i)=>i%4===3?a:a+b,0);};
 assert(glow(59/30)>glow(0),'The positive default brightens the item before the change');
 scrub(61/30);assert(calls.some(a=>a[0]===probe.scenery.holySheet0||a[0]===probe.scenery.holySheet1),'Holy Light follows the change');
 probe.select('TIME_TEAR');for(const t of [.5,2,3.19,3.3,4.5])assert.equal(probe.rainWetness(t),0,'Time = Tears is never rained on');
 for(const key of ['MONEY_TEAR']){
   probe.select(key);assert.equal(probe.rainWetness(23/30),0);
   for(const frame of [24,40,56,72,88]){
     const wet=probe.rainWetness(frame/30),before=probe.rainWetness((frame-1)/30),after=probe.rainWetness((frame+1)/30);
     assert(after-wet>2*(wet-before),'A hit sharply increases tint velocity');
     assert(probe.rainWetness((frame+7)/30)>probe.rainWetness((frame+5)/30),'Color keeps moving between hits');
     assert(Math.abs(probe.rainWetness((frame+.001)/30)-probe.rainWetness((frame-.001)/30))<.001,'No color step at impact');
     scrub((frame+1)/30);
     const tinted=calls.find(a=>a[0].getContext&&a[1]===304&&a[2]===144);
     assert(tinted,'The accumulated tint is actually drawn on the icon');
   }
   let previous=0;for(let f=25;f<96;f++){const wet=probe.rainWetness(f/30);assert(wet>previous&&wet<=1);previous=wet;}
   scrub(95/30);assert.equal(probe.itemPose(95/30).blend,0);assert.equal(probe.rainWetness(95/30),1);
   // No snap at the change: the converted item starts wet and dries over 45 frames.
   scrub(96/30);assert(Math.abs(probe.rainWetness(96/30)-1)<1e-9);assert.equal(probe.itemPose(96/30).blend,1);
   assert(calls.some(a=>a[0].getContext&&a[1]===304&&a[2]===144),'The converted item is drawn wet right after the change');
   let last=1;for(let f=97;f<=141;f++){const wet=probe.rainWetness(f/30);assert(wet<=last+1e-12&&last-wet<=.04,'Dries gradually');last=wet;}
   for(const t of [142/30,5.8]){
     scrub(t);assert.equal(probe.rainWetness(t),0);assert.equal(probe.itemPose(t).blend,1);
     assert(calls.some(a=>a[0].src===rows.find(r=>r.key===key).icon),'Untinted target is drawn from the original image');
     assert(!calls.some(a=>a[0].getContext&&a[1]===304&&a[2]===144),'No wet overlay once dry');
   }
   scrub(0);assert.equal(probe.rainWetness(0),0);
 }
 for(const [key,texture] of [['FIRE_BREATH','fxFire'],['ICE_BREATH','fxBlueFire']]){
   probe.select(key);const image=probe.scenery[texture],ink=createCanvas(48,48),ig=ink.getContext('2d'),bottoms=new Map();
   for(let tick=1;tick<=70;tick++){
     scrub(tick/30);const draw=calls.find(a=>a[0]===image);assert(draw,'Candle flame remains visible through the reveal');
     const [,sx,sy,sw,sh,dx,dy,dw,dh]=draw;ig.clearRect(0,0,48,48);ig.drawImage(image,sx,sy,sw,sh,0,0,48,48);
     const pixels=ig.getImageData(0,0,48,48).data;let top=48,bottom=0;
     for(let y=0;y<48;y++)for(let x=0;x<48;x++)if(pixels[(y*48+x)*4+3]>64){top=Math.min(top,y);bottom=Math.max(bottom,y+1);}
     assert(Math.abs(dy+top*dh/48-146)<.00001,'Actual flame tip remains fixed as it grows');
     bottoms.set(tick,dy+bottom*dh/48);
   }
   assert(bottoms.get(6)<bottoms.get(18)&&bottoms.get(18)<bottoms.get(30)&&bottoms.get(30)<bottoms.get(42));
   assert(bottoms.get(45)>172&&bottoms.get(70)<bottoms.get(45),'Downward coverage then settling');
   assert.equal(probe.itemPose(1.5).alpha,0,'Conversion is concealed by the flame');
 }
 probe.select('KRONOS');const k=probe.run().timing,kronosRow=rows.find(r=>r.key==='KRONOS');
 assert.equal(k.style,'ring');
 assert.equal(Math.round(k.reveal*30),kronosRow.impact);assert.equal(Math.round(probe.duration()*30),kronosRow.duration,'Saturn timing comes from the catalog');
 assert(kronosRow.impact>=90,'A slow, absorbing build before the conversion');
 assert.equal(probe.itemPose(k.reveal-1/30).blend,0);assert.equal(probe.itemPose(k.reveal).blend,1);
 assert.deepEqual([probe.itemPose(k.reveal).w,probe.itemPose(k.reveal).h],[40,25.6],'Kronos lands with a squash');
 assert.equal(probe.itemPose(k.reveal+3/30).w,32);
 for(let f=0;f<kronosRow.impact;f++){const pose=probe.itemPose(f/30);assert.equal(pose.w,32);assert.equal(pose.alpha,1);}
 // Black deepens before the conversion and fades out slowly afterwards.
 assert.equal(probe.ringBlack(1),0);assert(probe.ringBlack(k.reveal-10/30)<probe.ringBlack(k.reveal-2/30));
 assert.equal(probe.ringBlack(k.reveal),1);assert(probe.ringBlack(k.reveal+.75)>0&&probe.ringBlack(k.reveal+.75)<1);
 assert.equal(probe.ringBlack(k.reveal+45/30),0,'Original colours fully return');
 // Orbit speeds up and closes in on the item.
 const early=probe.ringState(50/30),tight=probe.ringState((kronosRow.impact-14)/30);
 assert(tight.rx<early.rx*.5,'The ring closes in on the item');
 assert(probe.ringState(51/30).turn-early.turn<tight.turn-probe.ringState((kronosRow.impact-15)/30).turn,'The orbit accelerates');
 // The ring is turned with the icon: its near half passes above the item.
 const near=probe.ringPoint(tight,Math.PI/2);assert(near.front&&near.y<tight.cy);
 const heartAt=()=>calls.findIndex(a=>a[0].src===kronosRow.origin);
 const petSheets=new Set(probe.run().pets.map(pet=>probe.scenery[pet.sheet]));
 let behind=false,ahead=false;
 for(let f=50;f<kronosRow.impact-12;f++){scrub(f/30);const h=heartAt(),drawn=calls.map((a,i)=>petSheets.has(a[0])?i:-1).filter(i=>i>=0);if(drawn.some(i=>i<h))behind=true;if(drawn.some(i=>i>h))ahead=true;}
 assert(behind&&ahead,'Pets pass behind and in front of the heart on the turned orbit');
 scrub(2/30);assert(!calls.some(a=>petSheets.has(a[0])),'Pets fade in slowly instead of popping');
 assert.deepEqual(Array.from(probe.soundCues(),cue=>cue[1]),['spin','summon']);
 assert.equal(probe.screenShake(k.reveal).x===0&&probe.screenShake(k.reveal).y===0,reduced);
 assert.deepEqual(Object.values(probe.screenShake(k.reveal+.3)),[0,0]);
 const owned=[{key:'a'},{key:'modded-not-in-fallback'}],fallback=[{key:'z'},{key:'y'},{key:'w'},{key:'v'}];
 const before=JSON.stringify(owned);const picked=probe.selectKronosPets(owned,fallback,()=>.8);assert.equal(picked.source,'owned');assert.equal(picked.pets.length,2);assert(picked.pets.every(p=>owned.includes(p)));assert.equal(JSON.stringify(owned),before);
 const one=probe.selectKronosPets([owned[0]],fallback,()=>0);assert.equal(one.pets.length,1,'Do not fill remaining slots with random pets while owner has any');
 const empty=probe.selectKronosPets([],fallback,()=>.75);assert.equal(empty.source,'random');assert.equal(empty.pets.length,3);assert.equal(new Set(empty.pets).size,3);
 const emptyPool=probe.selectKronosPets([],[],()=>0);assert.equal(emptyPool.pets.length,0);
 const selectedPets=probe.run().pets.map(p=>p.key).join(',');scrub(.8);scrub(2);assert.equal(probe.run().pets.map(p=>p.key).join(','),selectedPets,'Scrubbing retains the chosen pets');
 el('kronos-no-pets').events.click();assert.equal(probe.run().source,'random');assert.equal(probe.run().pets.length,3);assert.equal(el('kronos-options').hidden,false);
 el('kronos-pet-list').children[0].events.click();assert.equal(probe.run().source,'owned');assert.equal(probe.run().pets.length,1);assert.equal(probe.run().pets[0].key,'bobby');assert.equal(probe.duration(),k.duration,'The ring keeps its catalog timing for any pet count');
 el('upgrade-play').events.click();step(probe.duration()*1000+10);assert.equal(frames.size,0);assert.equal(Number(el('upgrade-time').value),probe.duration());

 // HTML-only Kronos concepts: every frame renders, the result appears on the
 // concept's own impact frame, and each concept has its own sound cues.
 for(const style of ['sickle','dust','pit']){
   probe.setKronosStyle(style);const kk=probe.run().timing;assert.equal(kk.style,style);assert(kk.reveal<probe.duration());
   for(let f=0;f<=Math.round(probe.duration()*30);f++)probe.setTime(f/30);
   assert.equal(probe.itemPose(kk.reveal-1/30).blend,0,style+' keeps the source before impact');
   assert.equal(probe.itemPose(kk.reveal).blend,1,style+' reveals the result at impact');
   assert(probe.soundCues().length>=2&&probe.soundCues().every(c=>c[0]<=kk.reveal),style+' cues end by impact');
 }
 probe.setKronosStyle('ring');assert.deepEqual(Array.from(probe.soundCues(),cue=>cue[1]),['spin','summon']);
 probe.select('SOFLAM');assert.equal(probe.itemPose(52/30).blend,0);assert.equal(probe.itemPose(53/30).blend,1,'Rocket impact on the catalog frame');
 assert.deepEqual(Array.from(probe.soundCues(),cue=>cue[1]),['lock','launch','impact'],'The SOFLAM lock-on warning sounds as the reticle appears');
 scrub(.5);const target=calls.find(a=>a[0].getContext&&a[0].width===32&&a[0].height===32);
 assert(target,'SOFLAM draws the tinted native target texture');
 const colors=target[0].getContext('2d').getImageData(0,0,32,32).data;
 const original=createCanvas(32,32),oc=original.getContext('2d');oc.drawImage(probe.scenery.targetSheet0,0,0);
 const sourceColors=oc.getImageData(0,0,32,32).data;let red=0;
 for(let i=0;i<colors.length;i+=4){
   assert.equal(colors[i+3],sourceColors[i+3],'Tint preserves the actual native reticle silhouette');
   if(colors[i+3]>240){assert(colors[i]>colors[i+1]*4&&colors[i]>colors[i+2]*4);red++;}
 }
 assert(red>10,'The native white mask is visibly red');
 for(const key of ['TIME_MONEY','TIME_POWER','TIME_TEAR','TIME_LUCK']){
   probe.select(key);scrub(.9);const clockCalls=calls.filter(a=>a[0]===probe.scenery.clockArt);assert.equal(clockCalls.length,3);
   const rim=clockCalls[0],matrix=rim.transform;
   assert(rim[7]*Math.hypot(matrix.a,matrix.b)<=32&&rim[8]*Math.hypot(matrix.c,matrix.d)<=32,'Whole clock fits a 32px item box');
   const origin=rows.find(row=>row.key===key).origin;
   const itemIndex=calls.findIndex(a=>a[0].src===origin);
   assert(itemIndex>=0&&calls.indexOf(rim)>itemIndex,'Clock and hands are painted in front of the item');
   scrub(probe.phaseTime()+.4);assert(!calls.some(a=>a[0]===probe.scenery.clockArt),'Clock disappears after one turn');
 }
 probe.select('ANGELS_CROWN');
 assert.deepEqual(rows.find(row=>row.key==='ANGELS_CROWN').effectAnchor,[16.5,19]);
 for(const t of [.9,1.5]){
   scrub(t);const halo=calls.find(a=>a[0]===probe.scenery.halo);assert(halo);
   const item=probe.itemPose(t);
   assert.equal(halo.transform.e,item.x+.5,'Halo follows the visible crown centre, including half a pixel');
   const progress=Math.max(0,Math.min(1,(Math.round(t*30)-12)/24));
   assert.equal(halo.transform.f,item.y+3-32+progress*progress*(3-2*progress)*8);
 }
 scrub(probe.phaseTime()+.3);assert(calls.some(a=>a[0]===probe.scenery.glint));
 assert.deepEqual(Array.from(probe.soundCues(),cue=>cue[1]),['wing','holy']);
 // Isolate the actual item draw from beam/glint overlays and compare pixels
 // through the entire reveal, including the final return to native color.
 let lastPixels,changedFrames=0;
 for(let frame=41;frame<=102;frame++){
   ctx.clearRect(0,0,640,360);probe.drawItem(frame/30);
   const pixels=ctx.getImageData(304,144,32,32).data;
   if(lastPixels){
     let changed=false;
     for(let i=0;i<pixels.length;i+=4)if(pixels[i+3]===255&&lastPixels[i+3]===255){
       for(let c=0;c<3;c++){
         const delta=lastPixels[i+c]-pixels[i+c];
         assert(delta>=0&&delta<=10,'Crown colors return gradually, without a snap');
         changed||=delta>0;
       }
     }
     if(changed)changedFrames++;
     if(frame>94)assert.deepEqual(pixels,lastPixels,'Unmodified art before the effect ends');
   }
   lastPixels=new Uint8ClampedArray(pixels);
 }
 assert(changedFrames>=40,'Crown must visibly fade over the full reveal interval');

 probe.select('SOFLAM');

 assert.equal(probe.screenShake(1.82).x===0&&probe.screenShake(1.82).y===0,reduced);
 const soundBefore=audio.length;scrub(1.8);await Promise.resolve();assert.equal(audio.length,soundBefore,'Scrubbing silent');
 el('upgrade-play').events.click();await new Promise(setImmediate);step(1300);await new Promise(setImmediate);assert(audio.includes('start'));
 el('upgrade-pause').events.click();assert(audio.includes('stop'),'Pause cancels playing audio');
 el('soflam-variant').events.click();assert.equal(probe.soundCues().length,0,'Retained laser is silent');assert.equal(probe.phaseTime(),1.6);
 el('soflam-variant').events.click();assert.equal(probe.phaseTime(),53/30);
 const saved=cards.slice();el('item-search').events.compositionstart();el('item-search').value='크로노스';el('item-search').events.input({isComposing:true});assert.equal(cards.filter(b=>!b.hidden).length,rows.length);
 el('item-search').events.compositionend();assert.equal(cards.filter(b=>!b.hidden).length,1);
 el('item-search').value='서리';el('item-search').events.input({});assert.equal(cards.filter(b=>!b.hidden).length,1);
 el('item-search').value='no such item';el('item-search').events.input({});assert.equal(cards.filter(b=>!b.hidden).length,0);
 el('item-search').value='';el('item-search').events.input({});assert.deepEqual(cards,saved);
 assert.equal(rows.find(row=>row.key==='ATROPOS').applied,false);
 el('filter-applied').events.click();assert.equal(cards.filter(b=>!b.hidden).length,13);assert.equal(el('upgrade-status').textContent,'인게임 적용');
 el('item-search').value='연사';el('item-search').events.input({});assert.equal(cards.filter(b=>!b.hidden).length,2);
 el('item-search').value='';el('item-search').events.input({});el('filter-pending').events.click();assert.equal(cards.filter(b=>!b.hidden).length,rows.length-13);assert(el('upgrade-status').textContent.includes('보류'));
 el('filter-all').events.click();assert.equal(cards.filter(b=>!b.hidden).length,rows.length);probe.select('SOFLAM');
 el('upgrade-repeat').checked=true;el('upgrade-play').events.click();step(4000);assert.equal(frames.size,1);step(100);assert(Number(el('upgrade-time').value)<.2);
 document.hidden=true;document.events.visibilitychange();assert.equal(frames.size,0);
 window.innerWidth=390;window.innerHeight=700;window.events.resize();assert(parseFloat(root.style['--stage-width'])<=348);
 for(const anim of Object.values(probe.animations))for(const l of anim.layers)for(const f of l.frames){const img=probe.scenery[l.sheet];assert(f.XCrop>=0&&f.YCrop>=0&&f.XCrop<img.naturalWidth&&f.YCrop<img.naturalHeight&&f.XCrop+f.Width<=img.naturalWidth+1&&f.YCrop+f.Height<=img.naturalHeight+2,'Vanilla ANM2 crops intersect sheet; only original explosion padding overflows');}
 return {probe,stage};
}
(async()=>{
 fs.mkdirSync('.tmp',{recursive:true});
 const result=await run();await run(true);
 assert.equal(rows.find(r=>r.key==='TIME_TEAR').origin.split(',')[1],fs.readFileSync('../../extracted_resources/resources/gfx/items/trinkets/trinket_039_cancer.png').toString('base64'));
 assert.equal(json('effect-audio').lightning.split(',')[1],fs.readFileSync('resources/sfx/conch_upgrade_thunder_strike.wav').toString('base64'),'Lightning impact uses the same registered nearby strike as the game');
 // Rasterize the Canvas drawing functions directly. This is not a browser,
 // HTML navigation, DOM-layout verification or game playback.
 result.probe.select('KRONOS');
 const ringRow=rows.find(r=>r.key==='KRONOS'),ringTimes=[6,20,40,60,80,100,108,114,ringRow.impact,ringRow.impact+20];
 const sheet=createCanvas(5*256,2*260),g=sheet.getContext('2d');g.fillStyle='#171614';g.fillRect(0,0,sheet.width,sheet.height);g.imageSmoothingEnabled=false;
 for(let i=0;i<ringTimes.length;i++){const t=ringTimes[i]/30;result.probe.setTime(t);const x=i%5,y=Math.floor(i/5);g.drawImage(result.stage,210,54,220,230,x*256+18,y*260+24,220,230);g.fillStyle='#eedcc1';g.font='12px sans-serif';g.fillText(t.toFixed(2)+'s '+result.probe.kronosPhase(t),x*256+10,y*260+16);}
 fs.writeFileSync('.tmp/kronos-saturn-contact.png',sheet.toBuffer('image/png'));
 const storm=createCanvas(5*220,244),tg=storm.getContext('2d');tg.fillStyle='#171614';tg.fillRect(0,0,storm.width,storm.height);tg.imageSmoothingEnabled=false;
 result.probe.select('DRAGON');
 for(const [i,[t,label]] of [[0,'BEFORE'],[1,'HELD DARKNESS / LIT ITEM'],[1.8,'THUNDER'],[70/30,'STRIKE / DARKNESS GONE'],[3.2,'RESTORED']].entries()){
   result.probe.setTime(t);tg.drawImage(result.stage,210,30,220,224,i*220,20,220,224);
   tg.fillStyle='#eedcc1';tg.font='11px sans-serif';tg.fillText(label,i*220+8,14);
 }
 fs.writeFileSync('.tmp/dragon-storm-contact.png',storm.toBuffer('image/png'));
 const rainSheet=createCanvas(5*240,2*230),rg=rainSheet.getContext('2d');rg.fillStyle='#171614';rg.fillRect(0,0,rainSheet.width,rainSheet.height);rg.imageSmoothingEnabled=false;
 for(const [row,key] of ['MONEY_TEAR'].entries()){
   result.probe.select(key);
   for(const [col,frame] of [0,22,38,53,54].entries()){
     result.probe.setTime(frame/30);
     rg.drawImage(result.stage,272,112,96,96,col*240+24,row*230+28,192,192);
     rg.fillStyle='#eedcc1';rg.font='12px sans-serif';rg.fillText(key+' / frame '+frame,col*240+10,row*230+17);
   }
 }
 fs.writeFileSync('.tmp/rain-morph-contact.png',rainSheet.toBuffer('image/png'));
 const breathSheet=createCanvas(6*210,2*230),bg=breathSheet.getContext('2d');bg.fillStyle='#171614';bg.fillRect(0,0,breathSheet.width,breathSheet.height);bg.imageSmoothingEnabled=false;
 for(const [row,key] of ['FIRE_BREATH','ICE_BREATH'].entries()){
   result.probe.select(key);
   for(const [col,frame] of [6,24,38,45,62,80].entries()){
     result.probe.setTime(frame/30);
     bg.drawImage(result.stage,272,112,96,96,col*210+9,row*230+28,192,192);
     bg.fillStyle='#eedcc1';bg.font='12px sans-serif';bg.fillText(key+' / frame '+frame,col*210+10,row*230+17);
   }
 }
 fs.writeFileSync('.tmp/breath-morph-contact.png',breathSheet.toBuffer('image/png'));
 const polishSheet=createCanvas(6*220,3*250),pg=polishSheet.getContext('2d');pg.fillStyle='#171614';pg.fillRect(0,0,polishSheet.width,polishSheet.height);pg.imageSmoothingEnabled=false;
 const polish=[['SOFLAM',[.3,1.1,1.55,1.75,2.3,3.1]],['TIME_LUCK',[.3,.7,1.1,1.6,1.9,2.5]],['ANGELS_CROWN',[.3,.8,1.15,41/30,1.8,2.5]]];
 for(const [row,[key,times]] of polish.entries()){
   result.probe.select(key);
   for(const [col,t] of times.entries()){
     result.probe.setTime(t);pg.drawImage(result.stage,210,45,220,230,col*220,row*250+20,220,230);
     pg.fillStyle='#eedcc1';pg.font='12px sans-serif';pg.fillText(key+' / '+t.toFixed(2)+'s',col*220+8,row*250+15);
   }
 }
 fs.writeFileSync('.tmp/upgrade-polish-contact.png',polishSheet.toBuffer('image/png'));



 console.log('PASS: 37 before/after identities and playback controls; the game'+"'"+'s default flag animation for items without their own; turned Saturn ring with slow darkening and colour return; owned-only selection including modded snapshots, one-pet timing, empty-only random without replacement, stable pause/scrub snapshot; specific void/impact/chomp/flood contracts; fixed flame tip with downward growth and concealed conversion; red native reticle with the SOFLAM lock-on warning and launch/blast cues, small articulated clock, native halo/glints; Cancer trinket; original vanilla crop/padding bounds; audio gesture, pause, silent scrub, laser alternate; applied/pending filter and combined Korean search; IME/search; reduced motion; offline assets. Direct Canvas frame sheets saved, browser layout not verified.');
})().catch(e=>{console.error(e);process.exitCode=1;});
