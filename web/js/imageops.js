// Pixel operations on plain typed arrays, so they run (and are tested) without a DOM.
// Images are { data: Uint8ClampedArray (RGBA), width, height } — the ImageData shape.
// Masks are Float32Array, one value 0...1 per pixel (1 = person).

export const DEFAULTS = Object.freeze({
  background: 'gradient', // original | blur | solid | gradient
  backgroundColor: '#c7ccd4',
  backgroundBlur: 0.03,   // radius as a fraction of the short side
  crop: 'square',         // square | portrait | original
  autoEnhance: true,
  exposure: 0,            // EV, -1...1
  contrast: 1,            // 0.75...1.25
  saturation: 1,          // 0...2
  warmth: 0,              // -1 (cooler) ... 1 (warmer)
  smoothing: 0.3,         // 0...1
});

export function createImage(width, height) {
  return { data: new Uint8ClampedArray(width * height * 4), width, height };
}

export function cloneImage(img) {
  return { data: new Uint8ClampedArray(img.data), width: img.width, height: img.height };
}

/** Separable box blur on `channels` interleaved channels; three passes ≈ Gaussian. Returns Float32Array. */
export function blur(src, width, height, channels, radius, passes = 3) {
  let a = Float32Array.from(src);
  if (radius < 1) return a;
  const r = Math.round(radius);
  let b = new Float32Array(a.length);
  for (let p = 0; p < passes; p++) {
    boxPass(a, b, width, height, channels, r, true);
    boxPass(b, a, width, height, channels, r, false);
  }
  return a;
}

function boxPass(src, dst, width, height, channels, r, horizontal) {
  const lines = horizontal ? height : width;
  const len = horizontal ? width : height;
  const step = (horizontal ? 1 : width) * channels;
  const lineStep = (horizontal ? width : 1) * channels;
  const norm = 1 / (2 * r + 1);
  for (let line = 0; line < lines; line++) {
    const base = line * lineStep;
    for (let c = 0; c < channels; c++) {
      const at = (i) => src[base + Math.min(Math.max(i, 0), len - 1) * step + c];
      let sum = 0;
      for (let i = -r; i <= r; i++) sum += at(i);
      for (let i = 0; i < len; i++) {
        dst[base + i * step + c] = sum * norm;
        sum += at(i + r + 1) - at(i - r);
      }
    }
  }
}

/** 1st/99th-percentile luminance stretch, like a one-click "auto levels". */
export function autoLevels(img) {
  const { data } = img;
  const hist = new Uint32Array(256);
  for (let i = 0; i < data.length; i += 4) {
    hist[(data[i] * 77 + data[i + 1] * 150 + data[i + 2] * 29) >> 8]++;
  }
  const total = data.length / 4;
  let lo = 0, hi = 255, acc = 0;
  for (; lo < 255; lo++) { acc += hist[lo]; if (acc > total * 0.01) break; }
  acc = 0;
  for (; hi > 0; hi--) { acc += hist[hi]; if (acc > total * 0.01) break; }
  if (hi - lo < 32) return; // flat image: leave it
  const scale = 255 / (hi - lo);
  for (let i = 0; i < data.length; i += 4) {
    data[i] = (data[i] - lo) * scale;
    data[i + 1] = (data[i + 1] - lo) * scale;
    data[i + 2] = (data[i + 2] - lo) * scale;
  }
}

/** Exposure, contrast, saturation and warmth in one pass. Mutates `img`. */
export function adjustTone(img, { exposure = 0, contrast = 1, saturation = 1, warmth = 0 }) {
  const { data } = img;
  const gain = Math.pow(2, exposure);
  const warmR = 1 + 0.12 * warmth, warmB = 1 - 0.12 * warmth;
  for (let i = 0; i < data.length; i += 4) {
    let r = data[i] * gain * warmR, g = data[i + 1] * gain, b = data[i + 2] * gain * warmB;
    r = (r - 128) * contrast + 128; g = (g - 128) * contrast + 128; b = (b - 128) * contrast + 128;
    const l = 0.299 * r + 0.587 * g + 0.114 * b;
    data[i] = l + (r - l) * saturation;
    data[i + 1] = l + (g - l) * saturation;
    data[i + 2] = l + (b - l) * saturation;
  }
}

/**
 * Edge-preserving smoothing: blend towards a blurred copy only where the local difference is
 * small (skin), not across edges (eyes, lips, hairline). Restricted to the person mask.
 */
export function smoothSkin(img, mask, amount) {
  if (amount <= 0) return;
  const { data, width, height } = img;
  const radius = Math.max(2, Math.round(Math.min(width, height) / 160));
  const soft = blur(data, width, height, 4, radius, 2);
  const sigma2 = 2 * 18 * 18;
  for (let p = 0, i = 0; i < data.length; p++, i += 4) {
    const dr = data[i] - soft[i], dg = data[i + 1] - soft[i + 1], db = data[i + 2] - soft[i + 2];
    const diff2 = (dr * dr + dg * dg + db * db) / 3;
    const w = amount * 0.85 * Math.exp(-diff2 / sigma2) * (mask ? mask[p] : 1);
    data[i] += (soft[i] - data[i]) * w;
    data[i + 1] += (soft[i + 1] - data[i + 1]) * w;
    data[i + 2] += (soft[i + 2] - data[i + 2]) * w;
  }
}

/** out = fg·mask + bg·(1-mask). Mutates and returns `fg`. */
export function composite(fg, bg, mask) {
  const a = fg.data, b = bg.data;
  for (let p = 0, i = 0; i < a.length; p++, i += 4) {
    const m = mask[p];
    a[i] = a[i] * m + b[i] * (1 - m);
    a[i + 1] = a[i + 1] * m + b[i + 1] * (1 - m);
    a[i + 2] = a[i + 2] * m + b[i + 2] * (1 - m);
    a[i + 3] = 255;
  }
  return fg;
}

export function blurredCopy(img, radius) {
  return { data: Uint8ClampedArray.from(blur(img.data, img.width, img.height, 4, radius)), width: img.width, height: img.height };
}

export function solid(width, height, [r, g, b]) {
  const img = createImage(width, height);
  for (let i = 0; i < img.data.length; i += 4) { img.data[i] = r; img.data[i + 1] = g; img.data[i + 2] = b; img.data[i + 3] = 255; }
  return img;
}

/** Soft studio light: brighter behind the head, falling off towards the edges. */
export function studioGradient(width, height, [r, g, b]) {
  const img = createImage(width, height);
  const cx = width / 2, cy = height * 0.38;
  const r0 = Math.min(width, height) * 0.05, r1 = Math.max(width, height) * 0.8;
  const inner = [r + 38, g + 38, b + 38], outer = [r * 0.6, g * 0.6, b * 0.6];
  for (let y = 0, i = 0; y < height; y++) {
    for (let x = 0; x < width; x++, i += 4) {
      const t = Math.min(1, Math.max(0, (Math.hypot(x - cx, y - cy) - r0) / (r1 - r0)));
      img.data[i] = inner[0] + (outer[0] - inner[0]) * t;
      img.data[i + 1] = inner[1] + (outer[1] - inner[1]) * t;
      img.data[i + 2] = inner[2] + (outer[2] - inner[2]) * t;
      img.data[i + 3] = 255;
    }
  }
  return img;
}

export function hexToRGB(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** Full headshot pipeline on an already-cropped image + matching mask (or null). Returns a new image. */
export function renderHeadshot(src, mask, s) {
  const img = cloneImage(src);
  const { width, height } = img;
  if (s.autoEnhance) autoLevels(img);
  adjustTone(img, s);
  smoothSkin(img, mask, s.smoothing);
  if (s.background !== 'original' && mask) {
    const rgb = hexToRGB(s.backgroundColor);
    const bg = s.background === 'blur' ? blurredCopy(img, Math.min(width, height) * s.backgroundBlur / 2)
      : s.background === 'solid' ? solid(width, height, rgb)
      : studioGradient(width, height, rgb);
    composite(img, bg, mask);
  }
  return img;
}

/**
 * Bilinear-samples the part of a low-res mask covering `rect` (in source-image pixels) into an
 * outW×outH mask, then softens the edge slightly.
 * @param {{data: Float32Array, width: number, height: number}} mask covers the whole source image
 */
export function resampleMask(mask, source, rect, outW, outH) {
  const out = new Float32Array(outW * outH);
  const sx = mask.width / source.width, sy = mask.height / source.height;
  for (let y = 0; y < outH; y++) {
    const my = Math.min(mask.height - 1, Math.max(0, (rect.y + ((y + 0.5) / outH) * rect.height) * sy - 0.5));
    const y0 = Math.floor(my), y1 = Math.min(mask.height - 1, y0 + 1), fy = my - y0;
    for (let x = 0; x < outW; x++) {
      const mx = Math.min(mask.width - 1, Math.max(0, (rect.x + ((x + 0.5) / outW) * rect.width) * sx - 0.5));
      const x0 = Math.floor(mx), x1 = Math.min(mask.width - 1, x0 + 1), fx = mx - x0;
      const d = mask.data, w = mask.width;
      const top = d[y0 * w + x0] * (1 - fx) + d[y0 * w + x1] * fx;
      const bottom = d[y1 * w + x0] * (1 - fx) + d[y1 * w + x1] * fx;
      out[y * outW + x] = top * (1 - fy) + bottom * fy;
    }
  }
  return blur(out, outW, outH, 1, Math.max(1, Math.min(outW, outH) / 400), 1);
}
