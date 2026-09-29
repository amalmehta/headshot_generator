import { applyStyle, circular, STYLES } from './avatars.js';
import { cropRect } from './framing.js';
import { DEFAULTS, renderHeadshot, resampleMask } from './imageops.js';
import { analyze, loadModels } from './vision.js';

const MAX_SOURCE = 4096;      // longest side kept from the original photo
const PREVIEW_SIZE = 1000;    // longest side of the on-screen headshot
const AVATAR_PREVIEW = 400;
const AVATAR_EXPORT = 1024;

const $ = (id) => document.getElementById(id);
const form = $('controls');

const state = {
  mode: 'headshot',
  settings: { ...DEFAULTS },
  source: null,        // canvas holding the photo, orientation applied
  name: 'photo',
  face: null,
  mask: null,
  showOriginal: false,
  avatarsDirty: true,
};

// ---------- Rendering ----------

function canvasOf(img) {
  const c = document.createElement('canvas');
  c.width = img.width; c.height = img.height;
  c.getContext('2d').putImageData(new ImageData(img.data, img.width, img.height), 0, 0);
  return c;
}

/**
 * Crops the source to the framing rect, scales so the longest side is maxSide (never upscaling
 * unless `exact`), and runs the pipeline.
 */
function renderAt(maxSide, settings = state.settings, exact = false) {
  const src = state.source;
  const rect = cropRect(state.face, src, settings.crop);
  const fit = maxSide / Math.max(rect.width, rect.height);
  const scale = exact ? fit : Math.min(1, fit);
  const w = Math.max(1, Math.round(rect.width * scale)), h = Math.max(1, Math.round(rect.height * scale));
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(src, rect.x, rect.y, rect.width, rect.height, 0, 0, w, h);
  const img = ctx.getImageData(0, 0, w, h);
  const mask = state.mask ? resampleMask(state.mask, src, rect, w, h) : null;
  return renderHeadshot({ data: img.data, width: w, height: h }, mask, settings);
}

function drawPreview() {
  const target = $('preview');
  let img;
  if (state.showOriginal) {
    const scale = Math.min(1, PREVIEW_SIZE / Math.max(state.source.width, state.source.height));
    target.width = Math.round(state.source.width * scale);
    target.height = Math.round(state.source.height * scale);
    target.getContext('2d').drawImage(state.source, 0, 0, target.width, target.height);
    return;
  }
  img = renderAt(PREVIEW_SIZE);
  target.width = img.width; target.height = img.height;
  target.getContext('2d').putImageData(new ImageData(img.data, img.width, img.height), 0, 0);
}

function drawAvatars() {
  const base = renderAt(AVATAR_PREVIEW, { ...state.settings, crop: 'square' }, true);
  for (const style of Object.keys(STYLES)) {
    const out = applyStyle(style, base);
    const c = document.querySelector(`[data-style="${style}"] canvas`);
    c.width = out.width; c.height = out.height;
    c.getContext('2d').putImageData(new ImageData(out.data, out.width, out.height), 0, 0);
  }
  state.avatarsDirty = false;
}

let timer;
function scheduleRender(delay = 120) {
  if (!state.source) return;
  state.avatarsDirty = true;
  clearTimeout(timer);
  setBusy('Rendering…');
  timer = setTimeout(() => {
    // A short gap lets the busy pill paint before the (synchronous) pixel work. Not
    // requestAnimationFrame: that pauses in background tabs and would stall the render.
    setTimeout(() => {
      try {
        if (state.mode === 'headshot') drawPreview(); else drawAvatars();
      } finally {
        setBusy(null);
      }
    }, 30);
  }, delay);
}

function setBusy(text) {
  $('busy').hidden = !text;
  if (text) $('busy-text').textContent = text;
}

// ---------- Loading ----------

async function loadFile(file) {
  if (!file || !file.type.startsWith('image/')) { alert('Please choose an image file.'); return; }
  setBusy('Reading photo…');
  try {
    const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
    const scale = Math.min(1, MAX_SOURCE / Math.max(bitmap.width, bitmap.height));
    const source = document.createElement('canvas');
    source.width = Math.round(bitmap.width * scale);
    source.height = Math.round(bitmap.height * scale);
    source.getContext('2d').drawImage(bitmap, 0, 0, source.width, source.height);
    bitmap.close();

    setBusy('Finding face and outline… (first time downloads the models)');
    const { face, mask } = await analyze(source);

    Object.assign(state, { source, face, mask, name: file.name.replace(/\.[^.]+$/, '') || 'photo', showOriginal: false });
    showStatus();
    $('drop').hidden = true;
    $('export').disabled = false;
    form.classList.remove('disabled');
    setCompare(false);
    showMode(state.mode);
  } catch (err) {
    console.error(err);
    setBusy(null);
    alert(`Couldn't process that photo: ${err.message || err}`);
  }
}

function showStatus() {
  const s = $('status');
  s.hidden = false;
  s.innerHTML = '';
  const add = (ok, yes, no) => {
    const div = document.createElement('div');
    div.className = ok ? 'ok' : 'warn';
    div.textContent = `${ok ? '✓' : '⚠'} ${ok ? yes : no}`;
    s.append(div);
  };
  add(!!state.face, 'Face found', 'No face found, so it crops from the centre');
  add(!!state.mask, 'Person outlined', 'No person outline, so the background is unchanged');
}

// ---------- Export ----------

function download(img, filename) {
  canvasOf(img).toBlob((blob) => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
  }, 'image/png');
}

function exportHeadshot() {
  setBusy('Exporting…');
  setTimeout(() => {
    try { download(renderAt(MAX_SOURCE), `${state.name}-headshot.png`); } finally { setBusy(null); }
  }, 30);
}

function exportAvatar(style) {
  setBusy('Exporting…');
  setTimeout(() => {
    try {
      let out = applyStyle(style, renderAt(AVATAR_EXPORT, { ...state.settings, crop: 'square' }, true));
      if ($('circle').checked) out = circular(out);
      download(out, `${state.name}-avatar-${style}.png`);
    } finally { setBusy(null); }
  }, 30);
}

// ---------- UI wiring ----------

function showMode(mode) {
  state.mode = mode;
  $('tab-headshot').setAttribute('aria-selected', mode === 'headshot');
  $('tab-avatars').setAttribute('aria-selected', mode === 'avatars');
  for (const fs of form.querySelectorAll('fieldset')) fs.hidden = fs.dataset.mode !== mode;
  $('export').hidden = mode !== 'headshot';
  if (!state.source) return;
  $('view-headshot').hidden = mode !== 'headshot';
  $('view-avatars').hidden = mode !== 'avatars';
  if (mode === 'headshot' || state.avatarsDirty) {
    state.avatarsDirty = true;
    scheduleRender(0);
  }
}

function setCompare(original) {
  state.showOriginal = original;
  $('before').setAttribute('aria-pressed', original);
  $('after').setAttribute('aria-pressed', !original);
}

function syncForm() {
  for (const el of form.elements) {
    if (!el.name || !(el.name in state.settings)) continue;
    if (el.type === 'checkbox') el.checked = state.settings[el.name];
    else el.value = state.settings[el.name];
  }
  for (const el of form.querySelectorAll('[data-when]')) {
    el.hidden = !el.dataset.when.split(' ').includes(state.settings.background);
  }
}

form.addEventListener('input', (e) => {
  const el = e.target;
  if (!el.name || !(el.name in state.settings)) return;
  state.settings[el.name] = el.type === 'checkbox' ? el.checked
    : el.type === 'range' ? Number(el.value) : el.value;
  syncForm();
  scheduleRender();
});
form.addEventListener('submit', (e) => e.preventDefault());
$('reset').addEventListener('click', () => { state.settings = { ...DEFAULTS }; syncForm(); scheduleRender(0); });
$('circle').addEventListener('change', () => $('view-avatars').classList.toggle('circle', $('circle').checked));

for (const id of ['file', 'file2']) $(id).addEventListener('change', (e) => { loadFile(e.target.files[0]); e.target.value = ''; });
$('tab-headshot').addEventListener('click', () => showMode('headshot'));
$('tab-avatars').addEventListener('click', () => showMode('avatars'));
$('before').addEventListener('click', () => { setCompare(true); scheduleRender(0); });
$('after').addEventListener('click', () => { setCompare(false); scheduleRender(0); });
$('export').addEventListener('click', exportHeadshot);

const stage = $('stage');
stage.addEventListener('dragover', (e) => { e.preventDefault(); stage.classList.add('dragging'); });
stage.addEventListener('dragleave', () => stage.classList.remove('dragging'));
stage.addEventListener('drop', (e) => {
  e.preventDefault();
  stage.classList.remove('dragging');
  loadFile(e.dataTransfer.files[0]);
});

const tab = $('feedback-tab'), panel = $('feedback-panel');
tab.addEventListener('click', () => {
  panel.hidden = !panel.hidden;
  tab.setAttribute('aria-expanded', !panel.hidden);
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { panel.hidden = true; tab.setAttribute('aria-expanded', 'false'); } });

// Avatar cards
const gallery = $('view-avatars');
gallery.classList.add('circle');
for (const [style, label] of Object.entries(STYLES)) {
  const card = document.createElement('div');
  card.className = 'card';
  card.dataset.style = style;
  card.innerHTML = `<canvas width="1" height="1" aria-label="${label} avatar"></canvas><h3>${label}</h3>`;
  const btn = document.createElement('button');
  btn.className = 'btn'; btn.textContent = 'Export';
  btn.addEventListener('click', () => exportAvatar(style));
  card.append(btn);
  gallery.append(card);
}

form.classList.add('disabled');
syncForm();
showMode('headshot');
// Warm the models up in the background once the page is idle, so the first photo is quicker.
(window.requestIdleCallback || setTimeout)(() => loadModels().catch(() => {}));
