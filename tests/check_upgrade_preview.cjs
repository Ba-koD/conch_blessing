const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {createCanvas,Image:CanvasImage}=require('@napi-rs/canvas');
const html=fs.readFileSync('docs/previews/item-upgrade-player.html','utf8');
const source=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const json=id=>JSON.parse(html.match(new RegExp('id="'+id+'"[^>]*>([\\s\\S]*?)</script>'))[1]);
const rows=json('upgrade-data');assert.equal(rows.length,31);new vm.Script(source);
assert(!/<select\b/.test(html));assert(!/fetch\(|https?:\/\//.test(source));
async function run(reduced=false){
 const els=new Map(),frames=new Map(),probe={},audio=[];let next=0,now=0;
 const stage=createCanvas(640,360),ctx=stage.getContext('2d'),calls=[];
 const imageDraw=ctx.drawImage.bind(ctx);ctx.drawImage=(...args)=>{for(const arg of args.slice(1))assert(Number.isFinite(arg));calls.push(args);imageDraw(...args);};
 function make(id=''){return {id,value:'',textContent:'',checked:id==='upgrade-sound',children:[],events:{},attrs:{},hidden:false,style:{setProperty(k,v){this[k]=v;}},addEventListener(k,f){this.events[k]=f;},append(e){this.children.push(e);},setAttribute(k,v){this.attrs[k]=v;},getBoundingClientRect(){return {height:this.id==='library'?98:32};}};}
 const el=id=>{if(!els.has(id))els.set(id,make(id));return els.get(id);};
 const root=el('conch-upgrade-preview'),canvas=el('upgrade-stage');canvas.getContext=()=>ctx;
 root.querySelector=s=>s==='canvas'?canvas:el(s.slice(1));root.children=['header','controls','game-frame','details','timeline','library','footer'].map(el);
 for(const id of ['upgrade-data','room-assets','effect-animations','effect-audio','kronos-pets'])el(id).textContent=JSON.stringify(json(id));
 const pending=[];
 class Image extends CanvasImage{set src(v){this.url=v;pending.push(new Promise(resolve=>{const cb=this.onload;this.onload=()=>{cb?.();resolve();};}));super.src=Buffer.from(v.split(',')[1],'base64');}get src(){return this.url;}}
 class AudioContext{constructor(){audio.push('context');this.destination={};}resume(){return Promise.resolve();}decodeAudioData(b){return Promise.resolve({byteLength:b.byteLength});}createGain(){return {gain:{},connect(){}};}createBufferSource(){const s={connect(){},start(){audio.push('start');},stop(){audio.push('stop');}};return s;}}
 const window={AudioContext,innerWidth:1280,innerHeight:900,events:{},addEventListener(k,f){this.events[k]=f;},matchMedia:()=>({matches:reduced})};
 const document={body:{},events:{},getElementById:el,createElement:t=>t==='canvas'?createCanvas(32,32):make(),addEventListener(k,f){this.events[k]=f;}};
 const inject='Object.assign(probe,{voidMotes,itemPose,phaseTime,floodLevel,screenShake,soundCues,scenery,animations,duration,selectKronosPets,kronosTiming,petFlight,bigMawPose,kronosPhase,petCatalog,run:()=>kronosRun,select:(key)=>choose(key),render:(key,t)=>{choose(key);time=t;draw();},setTime:(t)=>{time=t;draw();}});})();';
 vm.runInNewContext(source.replace('})();',inject),{probe,document,window,Image,atob:v=>Buffer.from(v,'base64').toString('binary'),performance:{now:()=>now},
   localStorage:{getItem(){throw Error('unavailable');},setItem(){throw Error('unavailable');}},
   getComputedStyle:e=>e===root?{rowGap:'12'}:{paddingTop:'16',paddingBottom:'16',paddingLeft:'20',paddingRight:'20'},
   requestAnimationFrame:f=>{frames.set(++next,f);return next;},cancelAnimationFrame:id=>frames.delete(id)});
 await Promise.all(pending);await Promise.resolve();assert.equal(audio.length,0,'Initial render is silent');
 function step(ms){now+=ms;const work=[...frames.values()];frames.clear();for(const fn of work)fn(now);}
 function scrub(t){el('upgrade-time').value=String(t);calls.length=0;el('upgrade-time').events.input();}
 const cards=el('upgrade-items').children;assert.equal(cards.length,31);
 for(let i=0;i<rows.length;i++){
   cards[i].events.click();assert.equal(frames.size,reduced?0:1);assert.equal(cards.filter(b=>b.attrs['aria-pressed']==='true').length,1);
   for(const t of [0,.5,1,1.43,1.5,1.6,1.75,1.9,2.1,2.3,2.7,probe.duration()]){
     scrub(t);const s=probe.itemPose(t);assert(Object.values(s).every(Number.isFinite));assert(s.w>=0&&s.h>=0&&s.alpha>=0&&s.alpha<=1);
     if(t===0)assert(calls.some(a=>a[0].src===rows[i].origin),rows[i].key+' begins with original');
     if(t===probe.duration())assert(calls.some(a=>a[0].src===rows[i].icon),rows[i].key+' ends with result');
   }
   const wanted=rows[i].key==='MONEY_TEAR'||rows[i].key==='TIME_TEAR';assert.equal(probe.floodLevel(3.4)>0,wanted,'Only both requested tear concepts flood room');
   el('upgrade-play').events.click();step(700);el('upgrade-pause').events.click();const frozen=Number(el('upgrade-time').value);assert(frozen>0&&frozen<3.4);assert.equal(frames.size,0);
   el('upgrade-pause').events.click();step(100);assert(Number(el('upgrade-time').value)>frozen);step(6000);assert.equal(frames.size,0);
 }
 probe.select('VOID_DAGGER');const mid=probe.voidMotes(.8),late=probe.voidMotes(1.7);
 mid.forEach((p,i)=>{assert(late[i].size<=p.size);assert(Math.hypot(late[i].x-320,late[i].y-167)<=Math.hypot(p.x-320,p.y-167));});assert(probe.voidMotes(3.4).every(p=>p.alpha===0));
 probe.select('DRAGON');assert.equal(probe.itemPose(1.49).blend,0);assert.equal(probe.itemPose(1.5).blend,1);
 probe.select('KRONOS');const k=probe.run().timing;
 assert(k.bigOpen>k.feedEnd&&k.reveal>k.closed,'BFF feeds, then bigger mouth swallows, then Kronos appears');
 assert.equal(probe.itemPose(k.swallowEnd+.02).alpha,0);assert.equal(probe.itemPose(k.reveal-.01).blend,0);assert.equal(probe.itemPose(k.reveal+.01).blend,1);
 assert(probe.bigMawPose(k.swallowStart).width>65);
 const owned=[{key:'a'},{key:'modded-not-in-fallback'}],fallback=[{key:'z'},{key:'y'},{key:'w'},{key:'v'}];
 const before=JSON.stringify(owned);const picked=probe.selectKronosPets(owned,fallback,()=>.8);assert.equal(picked.source,'owned');assert.equal(picked.pets.length,2);assert(picked.pets.every(p=>owned.includes(p)));assert.equal(JSON.stringify(owned),before);
 const one=probe.selectKronosPets([owned[0]],fallback,()=>0);assert.equal(one.pets.length,1,'Do not fill remaining slots with random pets while owner has any');
 const empty=probe.selectKronosPets([],fallback,()=>.75);assert.equal(empty.source,'random');assert.equal(empty.pets.length,3);assert.equal(new Set(empty.pets).size,3);
 const emptyPool=probe.selectKronosPets([],[],()=>0);assert.equal(emptyPool.pets.length,0);
 const selectedPets=probe.run().pets.map(p=>p.key).join(',');scrub(.8);scrub(2);assert.equal(probe.run().pets.map(p=>p.key).join(','),selectedPets,'Scrubbing retains the chosen pets');
 el('kronos-no-pets').events.click();assert.equal(probe.run().source,'random');assert.equal(probe.run().pets.length,3);assert.equal(el('kronos-options').hidden,false);
 el('kronos-pet-list').children[0].events.click();assert.equal(probe.run().source,'owned');assert.equal(probe.run().pets.length,1);assert.equal(probe.run().pets[0].key,'bobby');assert(probe.duration()<k.duration,'One pet does not wait through three feed cycles');
 el('upgrade-play').events.click();step(probe.duration()*1000+10);assert.equal(frames.size,0);assert.equal(Number(el('upgrade-time').value),probe.duration());

 probe.select('SOFLAM');assert.equal(probe.itemPose(1.74).blend,0);assert.equal(probe.itemPose(1.75).blend,1);
 assert.equal(probe.screenShake(1.82).x===0&&probe.screenShake(1.82).y===0,reduced);
 const soundBefore=audio.length;scrub(1.8);await Promise.resolve();assert.equal(audio.length,soundBefore,'Scrubbing silent');
 el('upgrade-play').events.click();await new Promise(setImmediate);step(950);await new Promise(setImmediate);assert(audio.includes('start'));
 el('upgrade-pause').events.click();assert(audio.includes('stop'),'Pause cancels playing audio');
 el('soflam-variant').events.click();assert.equal(probe.soundCues().length,0,'Retained laser is silent');assert.equal(probe.phaseTime(),1.6);
 el('soflam-variant').events.click();assert.equal(probe.phaseTime(),1.75);
 const saved=cards.slice();el('item-search').events.compositionstart();el('item-search').value='크로노스';el('item-search').events.input({isComposing:true});assert.equal(cards.filter(b=>!b.hidden).length,31);
 el('item-search').events.compositionend();assert.equal(cards.filter(b=>!b.hidden).length,1);
 el('item-search').value='서리';el('item-search').events.input({});assert.equal(cards.filter(b=>!b.hidden).length,1);
 el('item-search').value='no such item';el('item-search').events.input({});assert.equal(cards.filter(b=>!b.hidden).length,0);
 el('item-search').value='';el('item-search').events.input({});assert.deepEqual(cards,saved);
 el('filter-applied').events.click();assert.equal(cards.filter(b=>!b.hidden).length,16);assert.equal(el('upgrade-status').textContent,'인게임 적용');
 el('item-search').value='연사';el('item-search').events.input({});assert.equal(cards.filter(b=>!b.hidden).length,2);
 el('item-search').value='';el('item-search').events.input({});el('filter-pending').events.click();assert.equal(cards.filter(b=>!b.hidden).length,15);assert(el('upgrade-status').textContent.includes('보류'));
 el('filter-all').events.click();assert.equal(cards.filter(b=>!b.hidden).length,31);probe.select('SOFLAM');
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
 // Rasterize the Canvas drawing functions directly. This is not a browser,
 // HTML navigation, DOM-layout verification or game playback.
 result.probe.select('KRONOS');
 const k=result.probe.run().timing;
 const times=[0,.68,1.0,k.feedEnd,k.bigOpen+.2,k.swallowStart,k.swallowEnd,k.close+.1,k.reveal+.12,k.reveal+.6];
 const sheet=createCanvas(5*256,2*260),g=sheet.getContext('2d');g.fillStyle='#171614';g.fillRect(0,0,sheet.width,sheet.height);g.imageSmoothingEnabled=false;
 for(let i=0;i<times.length;i++){const t=times[i];result.probe.setTime(t);const x=i%5,y=Math.floor(i/5);g.drawImage(result.stage,210,54,220,230,x*256+18,y*260+24,220,230);g.fillStyle='#eedcc1';g.font='12px sans-serif';g.fillText(t.toFixed(2)+'s '+result.probe.kronosPhase(t),x*256+10,y*260+16);}
 fs.writeFileSync('.tmp/kronos-v5-contact.png',sheet.toBuffer('image/png'));
 console.log('PASS: 31 before/after identities and playback controls; native BFF/large jaw sequence; owned-only selection including modded snapshots, one-pet timing, empty-only random without replacement, stable pause/scrub snapshot; specific void/impact/chomp/flood contracts; Cancer trinket; original vanilla crop/padding bounds; audio gesture, pause, silent scrub, laser alternate; applied/pending filter and combined Korean search; IME/search; reduced motion; offline assets. Direct Canvas frame sheets saved, browser layout not verified.');
})().catch(e=>{console.error(e);process.exitCode=1;});
