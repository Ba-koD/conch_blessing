// Offscreen shader compilation/pixel tests; no game or visible browser input.
// Requires Playwright Chromium, or CONCH_SHADER_BROWSER_CHANNEL=msedge/chrome.
// Does not prove Isaac's render integration; never opens a visible browser.
const fs = require('node:fs');
const {chromium} = require('playwright');
const vertex = fs.readFileSync('resources/shaders/conch_neglect_outline.vs', 'utf8');
const fragment = fs.readFileSync('resources/shaders/conch_neglect_outline.fs', 'utf8');

(async () => {
  const browser = await chromium.launch({headless: true,
    channel: process.env.CONCH_SHADER_BROWSER_CHANNEL || undefined,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage();
    const results = await page.evaluate(({vertex, fragment}) => {
      const results = [];
      const assert = (value, message) => { if (!value) throw Error(message); };
      for (const type of ['webgl', 'webgl2']) {
        const canvas = document.createElement('canvas'); canvas.width = canvas.height = 8;
        const gl = canvas.getContext(type, {antialias: false, premultipliedAlpha: false});
        assert(gl, `${type} unavailable`);
        const compile = (kind, code) => {
          const shader = gl.createShader(kind);
          gl.shaderSource(shader, (type === 'webgl2' ? '#version 300 es\n' : '') + code);
          gl.compileShader(shader);
          assert(gl.getShaderParameter(shader, gl.COMPILE_STATUS), gl.getShaderInfoLog(shader));
          return shader;
        };
        const program = gl.createProgram();
        gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex));
        gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
        gl.linkProgram(program);
        assert(gl.getProgramParameter(program, gl.LINK_STATUS), gl.getProgramInfoLog(program));
        gl.useProgram(program);
        const attribute = (name, size, values) => {
          const buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
          gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(values), gl.STATIC_DRAW);
          const index = gl.getAttribLocation(program, name);
          gl.enableVertexAttribArray(index); gl.vertexAttribPointer(index, size, gl.FLOAT, false, 0, 0);
        };
        attribute('Position', 3, [-1,-1,0, 1,-1,0, -1,1,0, 1,1,0]);
        attribute('TexCoord', 2, [0,0, 1,0, 0,1, 1,1]);
        gl.vertexAttrib4f(gl.getAttribLocation(program, 'Color'), .16, .13, .15, 1);
        gl.vertexAttrib2f(gl.getAttribLocation(program, 'TexelStep'), 1/8, 1/8);
        gl.uniformMatrix4fv(gl.getUniformLocation(program, 'Transform'), false,
          new Float32Array([1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]));
        const texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        for (const alpha of [255,128,0]) {
          const input = new Uint8Array(8*8*4);
          for (let y=2; y<6; y++) for (let x=2; x<6; x++) {
            input.set([255,0,0,alpha], (y*8+x)*4); // red interior must disappear
          }
          gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,8,8,0,gl.RGBA,gl.UNSIGNED_BYTE,input);
          gl.clearColor(0,0,0,0); gl.clear(gl.COLOR_BUFFER_BIT);
          gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
          const output = new Uint8Array(8*8*4);
          gl.readPixels(0,0,8,8,gl.RGBA,gl.UNSIGNED_BYTE,output);
          assert(gl.getError() === gl.NO_ERROR, 'shader GL error');
          for (let y=0; y<8; y++) for (let x=0; x<8; x++) {
            const edge = x>=2 && x<=5 && y>=2 && y<=5 && (x===2 || x===5 || y===2 || y===5);
            const actual = output[(y*8+x)*4+3];
            assert(Math.abs(actual-(edge ? alpha : 0))<=1, `${type} alpha ${alpha}: ${x},${y}=${actual}`);
            if (edge && alpha) assert(output[(y*8+x)*4]<50, 'source colour leaked into the outline');
          }
          // A transparent alpha alone does NOT protect the room under every
          // native blend mode. Verify RGB of a pre-existing opaque background.
          gl.enable(gl.BLEND);
          for (const [name,src,dst] of [
            ['straight',gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA],
            ['premultiplied',gl.ONE,gl.ONE_MINUS_SRC_ALPHA],
            ['additive',gl.ONE,gl.ONE],
          ]) {
            gl.blendFunc(src,dst);
            gl.clearColor(.2,.4,.6,1); gl.clear(gl.COLOR_BUFFER_BIT);
            const before = new Uint8Array(8*8*4);
            gl.readPixels(0,0,8,8,gl.RGBA,gl.UNSIGNED_BYTE,before);
            for (let frame=0; frame<3; frame++) gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
            gl.readPixels(0,0,8,8,gl.RGBA,gl.UNSIGNED_BYTE,output);
            for (let y=0; y<8; y++) for (let x=0; x<8; x++) {
              const edge = alpha>0 && x>=2 && x<=5 && y>=2 && y<=5 && (x===2 || x===5 || y===2 || y===5);
              if (edge) continue;
              for (let c=0; c<4; c++) {
                const i=(y*8+x)*4+c;
                assert(output[i]===before[i], `${type} ${name}: background changed at ${x},${y}, channel ${c}`);
              }
            }
          }
          gl.disable(gl.BLEND);
        }
        results.push(`${type}: outline/alpha passed; background RGBA unchanged across 3 blend modes and repeated draws`);
      }
      return results;
    }, {vertex, fragment});
    for (const result of results) console.log(result);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
