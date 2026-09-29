// Stylized avatars from a square headshot. Pure pixel code; mirrors Sources/HeadshotCore/AvatarStyler.swift.
import { adjustTone, blur, cloneImage, createImage, smoothSkin } from './imageops.js';

export const STYLES = {
  cartoon: 'Cartoon',
  popArt: 'Pop Art',
  sketch: 'Pencil Sketch',
  duotone: 'Duotone',
  halftone: 'Halftone',
  pixel: 'Pixel',
};

const luma = (d, i) => 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];

function posterize(img, levels) {
  const d = img.data, step = 255 / (levels - 1);
  for (let i = 0; i < d.length; i += 4) {
    d[i] = Math.round(d[i] / step) * step;
    d[i + 1] = Math.round(d[i + 1] / step) * step;
    d[i + 2] = Math.round(d[i + 2] / step) * step;
  }
}

/** Sobel edge strength on luminance, 0...1 per pixel. */
function edges(img) {
  const { data, width: w, height: h } = img;
  const L = new Float32Array(w * h);
  for (let p = 0, i = 0; p < L.length; p++, i += 4) L[p] = luma(data, i) / 255;
  const S = blur(L, w, h, 1, Math.max(1, w / 512), 1);
  const out = new Float32Array(w * h);
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const p = y * w + x;
      const gx = S[p - w + 1] + 2 * S[p + 1] + S[p + w + 1] - S[p - w - 1] - 2 * S[p - 1] - S[p + w - 1];
      const gy = S[p + w - 1] + 2 * S[p + w] + S[p + w + 1] - S[p - w - 1] - 2 * S[p - w] - S[p - w + 1];
      out[p] = Math.hypot(gx, gy);
    }
  }
  return out;
}

function cartoon(src) {
  const img = cloneImage(src);
  smoothSkin(img, null, 1);
  smoothSkin(img, null, 1);
  posterize(img, 7);
  const e = edges(src), d = img.data;
  for (let p = 0, i = 0; p < e.length; p++, i += 4) {
    const ink = Math.min(1, Math.max(0, (e[p] - 0.18) * 6));
    d[i] *= 1 - ink; d[i + 1] *= 1 - ink; d[i + 2] *= 1 - ink;
  }
  return img;
}

function popArt(src) {
  const img = cloneImage(src);
  adjustTone(img, { saturation: 2.2, contrast: 1.3 });
  posterize(img, 4);
  return img;
}

/** Classic dodge sketch: grey, colour-dodged by its own blurred negative, then darkened. */
function sketch(src) {
  const { width: w, height: h } = src;
  const img = createImage(w, h), d = img.data;
  const g = new Float32Array(w * h);
  for (let p = 0, i = 0; p < g.length; p++, i += 4) g[p] = luma(src.data, i);
  const inv = blur(g.map((v) => 255 - v), w, h, 1, w / 85);
  for (let p = 0, i = 0; p < g.length; p++, i += 4) {
    const dodge = Math.min(255, (g[p] * 255) / Math.max(1, 255 - inv[p]));
    const v = 255 * Math.pow(dodge / 255, 3);
    d[i] = d[i + 1] = d[i + 2] = v; d[i + 3] = 255;
  }
  return img;
}

function duotone(src) {
  const img = cloneImage(src);
  adjustTone(img, { contrast: 1.35 });
  const dark = [26, 31, 89], light = [255, 199, 158], d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const t = Math.min(1, Math.max(0, luma(d, i) / 255));
    d[i] = dark[0] + (light[0] - dark[0]) * t;
    d[i + 1] = dark[1] + (light[1] - dark[1]) * t;
    d[i + 2] = dark[2] + (light[2] - dark[2]) * t;
  }
  return img;
}

/** CMY halftone: one rotated dot screen per ink, multiplied onto white paper. */
function halftone(src) {
  const { width: w, height: h } = src;
  const cell = Math.max(4, w / 100);
  const soft = blur(src.data, w, h, 4, cell / 2, 1);
  const img = createImage(w, h), d = img.data;
  const screens = [15, 75, 0].map((deg) => { const a = (deg * Math.PI) / 180; return [Math.cos(a), Math.sin(a)]; });
  for (let y = 0, i = 0; y < h; y++) {
    for (let x = 0; x < w; x++, i += 4) {
      for (let c = 0; c < 3; c++) {
        const [cos, sin] = screens[c];
        // Rotate into screen space, find this cell's centre, rotate back to sample the ink amount there.
        const u = x * cos + y * sin, v = -x * sin + y * cos;
        const cu = (Math.floor(u / cell) + 0.5) * cell, cv = (Math.floor(v / cell) + 0.5) * cell;
        const sx = Math.min(w - 1, Math.max(0, Math.round(cu * cos - cv * sin)));
        const sy = Math.min(h - 1, Math.max(0, Math.round(cu * sin + cv * cos)));
        const ink = 1 - soft[(sy * w + sx) * 4 + c] / 255;
        const radius = Math.sqrt(ink) * cell * 0.72;
        const dist = Math.hypot(u - cu, v - cv);
        d[i + c] = 255 * (1 - Math.min(1, Math.max(0, radius - dist + 0.5)));
      }
      d[i + 3] = 255;
    }
  }
  return img;
}

function pixel(src) {
  const { width: w, height: h } = src;
  const img = createImage(w, h), d = img.data, s = src.data;
  const blocks = 40, size = w / blocks;
  for (let by = 0; by < blocks; by++) {
    for (let bx = 0; bx < blocks; bx++) {
      const x0 = Math.floor(bx * size), x1 = Math.floor((bx + 1) * size);
      const y0 = Math.floor(by * size), y1 = Math.floor((by + 1) * size);
      let r = 0, g = 0, b = 0, n = 0;
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
        const i = (y * w + x) * 4; r += s[i]; g += s[i + 1]; b += s[i + 2]; n++;
      }
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
        const i = (y * w + x) * 4; d[i] = r / n; d[i + 1] = g / n; d[i + 2] = b / n; d[i + 3] = 255;
      }
    }
  }
  return img;
}

const RENDERERS = { cartoon, popArt, sketch, duotone, halftone, pixel };

/** `src` must be square. */
export function applyStyle(style, src) {
  return RENDERERS[style](src);
}

/** Transparent outside an anti-aliased circle — the usual profile-picture shape. Returns a new image. */
export function circular(src) {
  const img = cloneImage(src), { width: w, height: h } = img;
  const r = Math.min(w, h) / 2, cx = w / 2, cy = h / 2;
  for (let y = 0, i = 0; y < h; y++) {
    for (let x = 0; x < w; x++, i += 4) {
      const edge = Math.min(1, Math.max(0, r - Math.hypot(x + 0.5 - cx, y + 0.5 - cy)));
      img.data[i + 3] *= edge;
    }
  }
  return img;
}
