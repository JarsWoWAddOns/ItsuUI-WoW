// builds the bar textures as 256x32 uncompressed 32 bit TGAs. value is brightness 0-1
const fs = require('fs');
const path = require('path');
const W = 256, H = 32;
const OUT = path.join(__dirname, 'JarForever', 'textures');

// repeatable noise so a rebuild gives the same files
let seed = 13;
const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const rowNoise = Array.from({ length: H }, () => rand());
const colNoise = Array.from({ length: W }, () => rand());

const lerp = (a, b, t) => a + (b - a) * t;
const TEXTURES = {
    smooth: (x, y, v) => lerp(1, 0.72, v),
    soft: (x, y, v) => 0.76 + 0.24 * Math.sin(v * Math.PI),
    gloss: (x, y, v) => (v < 0.5 ? lerp(1, 0.84, v * 2) : lerp(0.68, 0.82, (v - 0.5) * 2)),
    tube: (x, y, v) => 0.5 + 0.5 * Math.sin(Math.pow(v, 0.75) * Math.PI),
    bevel: (x, y) => (y < 2 ? 1 : y >= H - 2 ? 0.5 : 0.82),
    inset: (x, y, v) => (v < 0.3 ? lerp(0.55, 0.95, v / 0.3) : 0.95),
    chrome: (x, y, v) => (v < 0.45 ? lerp(1, 0.72, v / 0.45) : v < 0.55 ? lerp(0.72, 0.5, (v - 0.45) / 0.1) : lerp(0.5, 0.9, (v - 0.55) / 0.45)),
    edge: (x, y) => (y < 3 ? 1 : 0.68),
    fade: (x) => lerp(0.42, 1, x / (W - 1)),
    stripes: (x, y) => ((x + y) % 32 < 16 ? 1 : 0.76),
    hatch: (x, y) => ((x + y) % 8 < 2 ? 1 : 0.74),
    lines: (x, y) => (y % 4 < 2 ? 1 : 0.72),
    pixel: (x, y) => (x % 8 < 6 && y % 8 < 6 ? 1 : 0.62),
    brushed: (x, y) => 0.8 + 0.12 * (rowNoise[y] - 0.5) + 0.2 * (colNoise[x] - 0.5),
};

function pixels(fn) {
    const out = new Uint8Array(W * H);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const v = Math.min(1, Math.max(0, fn(x, y, y / (H - 1))));
            out[y * W + x] = Math.round(v * 255);
        }
    }
    return out;
}

function writeTga(file, px) {
    const buf = Buffer.alloc(18 + W * H * 4);
    buf[2] = 2; // uncompressed truecolor
    buf.writeUInt16LE(W, 12);
    buf.writeUInt16LE(H, 14);
    buf[16] = 32;
    buf[17] = 8; // 8 alpha bits, rows bottom up
    let o = 18;
    for (let y = H - 1; y >= 0; y--) {
        for (let x = 0; x < W; x++) {
            const v = px[y * W + x];
            buf[o++] = v; buf[o++] = v; buf[o++] = v; buf[o++] = 255;
        }
    }
    fs.writeFileSync(file, buf);
}

fs.mkdirSync(OUT, { recursive: true });
for (const [name, fn] of Object.entries(TEXTURES)) {
    writeTga(path.join(OUT, name + '.tga'), pixels(fn));
}
console.log(`wrote ${Object.keys(TEXTURES).length} textures to ${OUT}`);
module.exports = { TEXTURES, pixels, W, H };
