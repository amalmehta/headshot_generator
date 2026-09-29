import assert from 'node:assert/strict';
import { test } from 'node:test';
import { applyStyle, circular, STYLES } from '../js/avatars.js';
import { cropRect } from '../js/framing.js';
import { adjustTone, blur, createImage, DEFAULTS, renderHeadshot, resampleMask } from '../js/imageops.js';

const image = { width: 3000, height: 4000 };
const inside = (r, img) => r.x >= 0 && r.y >= 0 && r.x + r.width <= img.width && r.y + r.height <= img.height;

test('square crop is square, contains the face and keeps it above centre', () => {
  const face = { x: 1200, y: 1100, width: 600, height: 700 };
  const r = cropRect(face, image, 'square');
  assert.ok(Math.abs(r.width - r.height) <= 1);
  assert.ok(inside(r, image));
  assert.ok(r.x <= face.x && r.y <= face.y && r.x + r.width >= face.x + face.width && r.y + r.height >= face.y + face.height);
  assert.ok(face.y + face.height / 2 < r.y + r.height / 2);
});

test('portrait crop is 4:5', () => {
  const r = cropRect({ x: 1200, y: 1100, width: 600, height: 700 }, image, 'portrait');
  assert.ok(Math.abs(r.width / r.height - 0.8) < 0.01);
});

test('face near an edge stays inside; huge face shrinks to fit', () => {
  assert.ok(inside(cropRect({ x: 10, y: 20, width: 500, height: 480 }, image, 'square'), image));
  const r = cropRect({ x: 200, y: 500, width: 2600, height: 3000 }, image, 'square');
  assert.equal(r.width, 3000);
  assert.ok(inside(r, image));
});

test('no face centre-crops; uncropped keeps everything', () => {
  assert.deepEqual(cropRect(null, image, 'square'), { x: 0, y: 500, width: 3000, height: 3000 });
  assert.deepEqual(cropRect(null, image, 'original'), { x: 0, y: 0, width: 3000, height: 4000 });
});

function gradientImage(w, h) {
  const img = createImage(w, h);
  for (let y = 0, i = 0; y < h; y++) for (let x = 0; x < w; x++, i += 4) {
    img.data[i] = (x / w) * 255; img.data[i + 1] = (y / h) * 255; img.data[i + 2] = 120; img.data[i + 3] = 255;
  }
  return img;
}

test('blur preserves a flat image and smooths a spike', () => {
  const flat = new Float32Array(100).fill(7);
  assert.ok(blur(flat, 10, 10, 1, 2).every((v) => Math.abs(v - 7) < 1e-4));
  const spike = new Float32Array(121); spike[60] = 121;
  const out = blur(spike, 11, 11, 1, 1);
  assert.ok(out[60] < 121 && out[60] > 0 && out[0] >= 0);
});

test('warmth +1 pushes red above blue on grey', () => {
  const img = createImage(4, 4); img.data.fill(128);
  adjustTone(img, { warmth: 1 });
  assert.ok(img.data[0] > img.data[2] + 10);
});

test('every background renders with a mask, and the mask decides fg vs bg', () => {
  const src = gradientImage(64, 64);
  const mask = new Float32Array(64 * 64).map((_, p) => (p % 64 < 32 ? 1 : 0));
  for (const background of ['original', 'blur', 'solid', 'gradient']) {
    const out = renderHeadshot(src, mask, { ...DEFAULTS, background, autoEnhance: false, smoothing: 0 });
    assert.equal(out.data.length, src.data.length, background);
  }
  const out = renderHeadshot(src, mask, { ...DEFAULTS, background: 'solid', backgroundColor: '#ff0000', autoEnhance: false, smoothing: 0 });
  const right = (10 * 64 + 60) * 4, left = (10 * 64 + 5) * 4;
  assert.deepEqual([...out.data.slice(right, right + 3)], [255, 0, 0]);
  assert.deepEqual([...out.data.slice(left, left + 3)], [...src.data.slice(left, left + 3)]);
});

test('every avatar style returns a same-size opaque image; circle has transparent corners', () => {
  const src = gradientImage(128, 128);
  for (const style of Object.keys(STYLES)) {
    const out = applyStyle(style, src);
    assert.equal(out.width, 128, style);
    assert.equal(out.data.length, src.data.length, style);
    assert.equal(out.data[(64 * 128 + 64) * 4 + 3], 255, style);
  }
  const c = circular(src);
  assert.equal(c.data[3], 0);
  assert.equal(c.data[(64 * 128 + 64) * 4 + 3], 255);
});

test('resampleMask maps the crop region of a low-res mask to the output size', () => {
  // 4×4 mask covering an 400×400 image: left half person, right half background.
  const mask = { data: new Float32Array(16).map((_, p) => (p % 4 < 2 ? 1 : 0)), width: 4, height: 4 };
  const out = resampleMask(mask, { width: 400, height: 400 }, { x: 0, y: 0, width: 400, height: 400 }, 40, 40);
  assert.equal(out.length, 1600);
  assert.ok(out[20 * 40 + 2] > 0.95 && out[20 * 40 + 37] < 0.05);
  const rightOnly = resampleMask(mask, { width: 400, height: 400 }, { x: 300, y: 0, width: 100, height: 100 }, 10, 10);
  assert.ok(rightOnly.every((v) => v < 0.05));
});
