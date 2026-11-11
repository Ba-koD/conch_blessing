"""Self-contained, real-mesh review with an embedded asset download."""
import base64
import gzip
import json
from pathlib import Path
from PIL import Image, ImageDraw
from build import ROOT,OUT,PREVIEW


def crab_preview():
    """Use the actual generated attachment table and actual mod trinket art."""
    from lupa.lua53 import LuaRuntime
    v=LuaRuntime().execute((ROOT/'scripts/items/familiars/hermit_crab_visuals.lua').read_text(encoding='utf-8'))
    body=Image.open(ROOT/'resources/gfx/familiar/familiar_hermit_crab_af3d.png')
    grip=Image.open(ROOT/'resources/gfx/familiar/familiar_hermit_crab_grip_af3d.png')
    out=Image.new('RGBA',(800,380),(38,36,40));d=ImageDraw.Draw(out)
    for row,pose in enumerate(['NormalEmpty','NormalOne','BffsEmpty','BffsOne','BffsTwo']):
        tile=Image.new('RGBA',(80,72));tile.alpha_composite(body.crop((0,row*48,48,row*48+48)),(16,12))
        foot=45 if row>1 else 42
        for i,slot in v['poses'][pose]['frames'][1].items():
            name='a_minus.png' if i==1 else 'angels_crown.png';bounds=v['trinketBounds'][name]
            scale=slot['scale'];bottom=slot['bottom']
            if slot['minTop'] is not None:bottom=max(bottom,slot['minTop']+(bounds[3]-bounds[2])*scale)
            im=Image.open(ROOT/'resources/gfx/items/trinkets'/name.replace('.png','_af3d.png'))
            im=im.resize((round(32*scale),round(32*scale)),Image.Resampling.NEAREST)
            x=16+24+slot['x']-bounds[1]*scale;y=12+foot+bottom-bounds[3]*scale
            tile.alpha_composite(im,(round(x),round(y)))
        tile.alpha_composite(grip.crop((0,row*48,48,row*48+48)),(16,12))
        # Trim empty presentation padding, not the original Sprite or attachment layout.
        tile=tile.crop((0,10,80,65)).resize((240,165),Image.Resampling.NEAREST)
        x=row%3*265;y=row//3*190;out.alpha_composite(tile,(x,y));d.text((x+8,y+170),pose,fill='white')
    out.save(PREVIEW/'crab_carried.png')


def main():
    rows=json.loads((OUT/'items.json').read_text(encoding='utf-8'))
    payload={}
    for r in rows:
        key=r['key']
        payload[key]={name:base64.b64encode(path.read_bytes()).decode() for name,path in {
            'glb':OUT/'models'/f'{key}.glb','original':ROOT/'resources'/r['source'],
            'still':ROOT/'resources'/r['still'],'spin':ROOT/'resources'/r['spin']}.items()}
        ax,ay,az=r.get('rotationAxis',[0,0,0]);payload[key]['pivot']=[ax,az,-ay]
        payload[key]['pitch']=r.get('cameraPitch',0)
    packed=base64.b64encode(gzip.compress(json.dumps(payload).encode(),mtime=0)).decode()
    page=TEMPLATE.replace('__DATA__',packed)
    (OUT/'review.html').write_text(page,encoding='utf-8')
    crab_preview()
    print('Wrote',OUT/'review.html',len(page),'bytes')


TEMPLATE=r'''<!doctype html><html lang="ko"><meta charset="utf-8"><title>Conch — April Fools 3D</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#18191e;color:#eee;font:16px system-ui,sans-serif}
main{max-width:1200px;margin:auto;padding:28px}h1{font-size:27px;margin:0 0 8px}p{color:#b9bdc9;line-height:1.6}
.bar{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0}button,select{background:#303440;color:#fff;border:1px solid #555b6c;border-radius:8px;padding:10px;font:inherit}
.grid{display:grid;grid-template-columns:2fr 1fr;gap:20px}.panel{background:#22252d;border-radius:16px;padding:20px}canvas{width:100%;height:520px;touch-action:none;border-radius:12px;background:radial-gradient(#383e4b,#22252d)}
.icon{width:128px;height:128px;image-rendering:pixelated;background:repeating-conic-gradient(#282b32 0% 25%,#30343d 0% 50%) 50%/20px 20px}
#spin{background-image:var(--sheet);background-size:4096px 128px;image-rendering:pixelated;width:128px;height:128px}.compare{display:flex;gap:18px;flex-wrap:wrap}
small{color:#aaa}.tag{color:#9ee9d2;font-size:13px;letter-spacing:.15em}@media(max-width:750px){.grid{grid-template-columns:1fr}canvas{height:380px}}
</style><main><div class="tag">CONCH'S BLESSING · APRIL FOOLS</div><h1>실제 3D 모델 · 아이작 회전 미리보기</h1>
<p>모델을 드래그해 앞·옆·뒤를 확인하세요. 오른쪽은 원본과 실제 32×32 게임용 렌더입니다.</p>
<div class="bar"><select id="select" aria-label="아이템"></select><button id="pause">회전 멈추기</button><button id="front">정면</button><button id="download">GLB 모델 저장</button></div>
<div class="grid"><section class="panel"><canvas id="view"></canvas><small>실제 메시 · 미리보기 조명 / 게임에서는 렌더된 PNG 프레임 사용</small></section>
<section class="panel"><h2 id="name">불러오는 중…</h2><div class="compare"><div><p>원본</p><img id="original" class="icon"></div><div><p>3D 정면 · 4배 확대</p><img id="still" class="icon"></div></div><p>게임용 360° 회전 · 32프레임</p><div id="spin"></div><p id="stats"></p><small>폰트와 투명 제어 이미지는 유지합니다. 엔진 내 화면 검증은 게임 재시작 후 별도로 필요합니다.</small></section></div>
<p>설정: MCM → General → April Fools 3D → Auto (April 1) / Always ON / OFF</p><p id="error" role="status"></p></main>
<script>
'use strict';
const packed='__DATA__';
const $=id=>document.getElementById(id), bytes=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
let data,model,draws=[],pivot=[0,0,0],yaw=0,pitch=0,frontPitch=0,playing=true,last=0;
const gl=$('view').getContext('webgl2',{alpha:false,antialias:true});
function shader(type,src){const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s}
const vs=`#version 300 es
in vec3 pos;in vec3 nor;uniform vec3 pivot;uniform float yaw;uniform float pitch;uniform float aspect;out vec3 n;
vec3 rotate(vec3 p){float c=cos(yaw),s=sin(yaw);vec3 q=vec3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);return vec3(q.x,cos(pitch)*q.y-sin(pitch)*q.z,sin(pitch)*q.y+cos(pitch)*q.z);}
void main(){vec3 p=rotate(pos-pivot)+pivot;n=rotate(nor);gl_Position=vec4(p.x/(17.*aspect),p.y/17.,-p.z/80.,1.);}`;
const fs=`#version 300 es
precision highp float;in vec3 n;uniform vec4 color;uniform float metal;uniform float rough;out vec4 pixel;
void main(){vec3 N=normalize(n),L=normalize(vec3(-.55,.8,1.)),V=vec3(0,0,1);float diffuse=max(0.,dot(N,L));float spec=pow(max(0.,dot(N,normalize(L+V))),mix(75.,8.,rough));vec3 c=color.rgb*(.25+.7*diffuse+.17*max(0.,N.x)) + mix(vec3(1),color.rgb,metal)*spec*.55;pixel=vec4(c,color.a);}`;
let program;
function initGL(){if(!gl)throw Error('이 브라우저는 WebGL 2를 지원하지 않습니다.');program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,vs));gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fs));gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));gl.useProgram(program);gl.enable(gl.DEPTH_TEST);gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);}
function load(key){
 for(const d of draws){gl.deleteVertexArray(d.vao);for(const b of d.buffers)gl.deleteBuffer(b)}draws=[];
 const entry=data[key],raw=bytes(entry.glb),dv=new DataView(raw.buffer),jsonLength=dv.getUint32(12,true);pivot=entry.pivot||[0,0,0];frontPitch=(entry.pitch||0)*Math.PI/180;pitch=frontPitch;
 model=JSON.parse(new TextDecoder().decode(raw.slice(20,20+jsonLength)));const bin=raw.slice(28+jsonLength);
 function accessor(i){const a=model.accessors[i],v=model.bufferViews[a.bufferView];const start=(v.byteOffset||0)+(a.byteOffset||0),count=a.count*(a.type==='VEC3'?3:1);return a.componentType===5125?new Uint32Array(bin.buffer,bin.byteOffset+start,count):new Float32Array(bin.buffer,bin.byteOffset+start,count)}
 let triangles=0;
 for(const p of model.meshes[0].primitives){const vao=gl.createVertexArray(),buffers=[];gl.bindVertexArray(vao);
  for(const [name,i] of [['pos',p.attributes.POSITION],['nor',p.attributes.NORMAL]]){const b=gl.createBuffer();buffers.push(b);gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,accessor(i),gl.STATIC_DRAW);const loc=gl.getAttribLocation(program,name);gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,3,gl.FLOAT,false,0,0)}
  const index=accessor(p.indices),b=gl.createBuffer();buffers.push(b);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,b);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,index,gl.STATIC_DRAW);
  draws.push({vao,buffers,count:index.length,mat:model.materials[p.material].pbrMetallicRoughness});triangles+=index.length/3;
 }
 draws.sort((a,b)=>b.mat.baseColorFactor[3]-a.mat.baseColorFactor[3]);
 $('name').textContent=key;$('stats').textContent=triangles.toLocaleString()+' triangles · '+draws.length+' materials';
 $('original').src='data:image/png;base64,'+entry.original;$('still').src='data:image/png;base64,'+entry.still;$('spin').style.setProperty('--sheet','url(data:image/png;base64,'+entry.spin+')');yaw=0;
}
function frame(t){const dt=Math.min((t-last)/1000,.1);last=t;if(playing){yaw+=dt*2*Math.PI*15/32}const canvas=$('view'),dpr=Math.min(devicePixelRatio,2);canvas.width=Math.round(canvas.clientWidth*dpr);canvas.height=Math.round(canvas.clientHeight*dpr);gl.viewport(0,0,canvas.width,canvas.height);gl.clearColor(.13,.145,.18,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(program);gl.uniform3fv(gl.getUniformLocation(program,'pivot'),pivot);for(const [k,v]of Object.entries({yaw,pitch,aspect:canvas.width/canvas.height}))gl.uniform1f(gl.getUniformLocation(program,k),v);
 for(const d of draws){gl.depthMask(d.mat.baseColorFactor[3]>=1);gl.bindVertexArray(d.vao);gl.uniform4fv(gl.getUniformLocation(program,'color'),d.mat.baseColorFactor);gl.uniform1f(gl.getUniformLocation(program,'metal'),d.mat.metallicFactor);gl.uniform1f(gl.getUniformLocation(program,'rough'),d.mat.roughnessFactor);gl.drawElements(gl.TRIANGLES,d.count,gl.UNSIGNED_INT,0)}gl.depthMask(true);$('spin').style.backgroundPosition=(-Math.floor(((yaw/(2*Math.PI))%1+1)%1*32)*128)+'px 0';requestAnimationFrame(frame)}
let drag=null;$('view').onpointerdown=e=>{drag=[e.clientX,e.clientY];$('view').setPointerCapture(e.pointerId)};$('view').onpointermove=e=>{if(!drag)return;yaw+=(e.clientX-drag[0])*.009;pitch=Math.max(-1.4,Math.min(1.4,pitch+(e.clientY-drag[1])*.009));drag=[e.clientX,e.clientY]};$('view').onpointerup=()=>drag=null;
$('pause').onclick=()=>{playing=!playing;$('pause').textContent=playing?'회전 멈추기':'회전 재생'};$('front').onclick=()=>{yaw=0;pitch=frontPitch;playing=false;$('pause').textContent='회전 재생'};
$('download').onclick=()=>{const key=$('select').value,url=URL.createObjectURL(new Blob([bytes(data[key].glb)],{type:'model/gltf-binary'})),a=document.createElement('a');a.href=url;a.download=key+'.glb';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
(async()=>{try{initGL();const stream=new Blob([bytes(packed)]).stream().pipeThrough(new DecompressionStream('gzip'));data=JSON.parse(await new Response(stream).text());for(const key of Object.keys(data)){const o=new Option(key,key);$('select').append(o)}$('select').value='conch_pearl';$('select').onchange=()=>load($('select').value);load('conch_pearl');requestAnimationFrame(frame)}catch(e){$('error').textContent=e.message}})();
</script></html>'''

if __name__=='__main__':main()
