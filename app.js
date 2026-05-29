'use strict';

// ── DOM refs ──────────────────────────────────────────────────────────────────
const video       = document.getElementById('video');
const canvas      = document.getElementById('overlay');
const ctx         = canvas.getContext('2d');
const btnLoadUrl  = document.getElementById('btnLoadUrl');
const btnStart    = document.getElementById('btnStart');
const btnStop     = document.getElementById('btnStop');
const btnClear    = document.getElementById('btnClear');
const videoUrl    = document.getElementById('videoUrl');
const videoFile   = document.getElementById('videoFile');
const fileLabel   = document.getElementById('fileLabel');
const urlHint     = document.getElementById('urlHint');
const modelStatus = document.getElementById('modelStatus');
const scaleSlider = document.getElementById('scaleFactor');
const scaleValue  = document.getElementById('scaleValue');
const confSlider  = document.getElementById('confidence');
const confValue   = document.getElementById('confValue');
const statCount   = document.getElementById('statCount');
const statAvg     = document.getElementById('statAvg');
const statMax     = document.getElementById('statMax');
const statFps     = document.getElementById('statFps');

// ── State ─────────────────────────────────────────────────────────────────────
let cocoModel    = null;
let detecting    = false;
let rafId        = null;
let tracker      = null;
let lastTs       = 0;
let frameTimes   = [];

const VEHICLE_CLASSES = new Set(['car','truck','bus','motorcycle','bicycle']);

// ── Centroid tracker ──────────────────────────────────────────────────────────
class CentroidTracker {
  constructor() {
    this.objects     = new Map(); // id → {cx, cy, bbox, speed, smoothSpeed}
    this.disappeared = new Map(); // id → frames-missing count
    this.history     = new Map(); // id → [{cx, cy, ms}]
    this.nextId      = 0;
    this.MAX_GONE    = 12;
    this.MAX_DIST    = 120; // pixels
    this.HIST_LEN    = 18;
  }

  _register(cx, cy, bbox) {
    const id = this.nextId++;
    this.objects.set(id, { cx, cy, bbox, speed: 0, smoothSpeed: 0 });
    this.disappeared.set(id, 0);
    this.history.set(id, [{ cx, cy, ms: performance.now() }]);
    return id;
  }

  _deregister(id) {
    this.objects.delete(id);
    this.disappeared.delete(id);
    this.history.delete(id);
  }

  update(detections, pixelsPerMeter) {
    if (detections.length === 0) {
      for (const id of [...this.disappeared.keys()]) {
        const gone = this.disappeared.get(id) + 1;
        if (gone > this.MAX_GONE) this._deregister(id);
        else this.disappeared.set(id, gone);
      }
      return this.objects;
    }

    const inputs = detections.map(d => ({
      cx:   d.bbox[0] + d.bbox[2] / 2,
      cy:   d.bbox[1] + d.bbox[3] / 2,
      bbox: d.bbox,
    }));

    if (this.objects.size === 0) {
      inputs.forEach(i => this._register(i.cx, i.cy, i.bbox));
      return this.objects;
    }

    // Build cost matrix (Euclidean distance)
    const ids   = [...this.objects.keys()];
    const objs  = ids.map(id => this.objects.get(id));
    const costs = objs.map(o =>
      inputs.map(i => Math.hypot(o.cx - i.cx, o.cy - i.cy))
    );

    // Greedy nearest-neighbour matching (simple but effective for traffic)
    const pairs = [];
    for (let r = 0; r < costs.length; r++)
      for (let c = 0; c < costs[r].length; c++)
        pairs.push({ r, c, d: costs[r][c] });
    pairs.sort((a, b) => a.d - b.d);

    const usedR = new Set(), usedC = new Set();
    for (const { r, c, d } of pairs) {
      if (usedR.has(r) || usedC.has(c) || d > this.MAX_DIST) continue;
      usedR.add(r); usedC.add(c);

      const id  = ids[r];
      const inp = inputs[c];
      const now = performance.now();

      // Update position history
      const hist = this.history.get(id);
      hist.push({ cx: inp.cx, cy: inp.cy, ms: now });
      if (hist.length > this.HIST_LEN) hist.shift();

      // Speed from history window
      let speed = 0;
      if (hist.length >= 4) {
        const a = hist[0], b = hist[hist.length - 1];
        const dt = (b.ms - a.ms) / 1000;          // seconds
        const dp = Math.hypot(b.cx - a.cx, b.cy - a.cy); // pixels
        speed = dp / pixelsPerMeter / dt * 3.6;    // km/h
      }

      const prev = this.objects.get(id);
      // Exponential smoothing so numbers don't flicker wildly
      const smoothSpeed = prev.smoothSpeed * 0.7 + speed * 0.3;

      this.objects.set(id, {
        cx: inp.cx, cy: inp.cy, bbox: inp.bbox,
        speed, smoothSpeed
      });
      this.disappeared.set(id, 0);
    }

    // Mark unmatched existing objects as disappeared
    for (let r = 0; r < ids.length; r++) {
      if (!usedR.has(r)) {
        const id   = ids[r];
        const gone = this.disappeared.get(id) + 1;
        if (gone > this.MAX_GONE) this._deregister(id);
        else this.disappeared.set(id, gone);
      }
    }

    // Register brand-new detections
    for (let c = 0; c < inputs.length; c++) {
      if (!usedC.has(c)) {
        const i = inputs[c];
        this._register(i.cx, i.cy, i.bbox);
      }
    }

    return this.objects;
  }

  clear() {
    this.objects.clear();
    this.disappeared.clear();
    this.history.clear();
    this.nextId = 0;
  }
}

// ── Drawing ───────────────────────────────────────────────────────────────────
function speedColor(kmh) {
  if (kmh < 40)  return '#22c55e';
  if (kmh < 80)  return '#eab308';
  return '#ef4444';
}

function drawOverlay(objects, scaleX, scaleY) {
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  let totalSpeed = 0, count = 0, maxSpeed = 0;

  for (const obj of objects.values()) {
    if (obj.disappeared > 0) continue;   // only draw live tracks

    const [bx, by, bw, bh] = obj.bbox;
    const x  = bx * scaleX;
    const y  = by * scaleY;
    const w  = bw * scaleX;
    const h  = bh * scaleY;

    const kmh  = Math.round(obj.smoothSpeed);
    const col  = speedColor(kmh);
    const label = `${kmh} km/h`;

    // Bounding box
    ctx.strokeStyle = col;
    ctx.lineWidth   = 2;
    ctx.strokeRect(x, y, w, h);

    // Semi-transparent fill (subtle)
    ctx.fillStyle = col + '18';
    ctx.fillRect(x, y, w, h);

    // Speed badge above the box
    const FONT_SIZE = Math.max(12, Math.min(18, w * 0.22));
    ctx.font = `bold ${FONT_SIZE}px 'Segoe UI', system-ui, sans-serif`;
    const textW = ctx.measureText(label).width;
    const padX  = 8, padY = 4;
    const badgeW = textW + padX * 2;
    const badgeH = FONT_SIZE + padY * 2;
    const bx2   = x + w / 2 - badgeW / 2;
    const by2   = Math.max(0, y - badgeH - 4);

    // Badge background
    ctx.fillStyle = col;
    roundRect(ctx, bx2, by2, badgeW, badgeH, 5);
    ctx.fill();

    // Badge text
    ctx.fillStyle = '#fff';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, bx2 + padX, by2 + badgeH / 2);

    // Corner dots
    ctx.fillStyle = col;
    const dotR = 3;
    [[x, y],[x+w, y],[x, y+h],[x+w, y+h]].forEach(([dx, dy]) => {
      ctx.beginPath();
      ctx.arc(dx, dy, dotR, 0, Math.PI * 2);
      ctx.fill();
    });

    totalSpeed += kmh;
    count++;
    if (kmh > maxSpeed) maxSpeed = kmh;
  }

  // Update stats
  statCount.textContent = count || '—';
  statAvg.textContent   = count ? `${Math.round(totalSpeed / count)} km/h` : '—';
  statMax.textContent   = count ? `${maxSpeed} km/h` : '—';
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + w - r, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + r);
  ctx.lineTo(x + w, y + h - r);
  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  ctx.lineTo(x + r, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

// ── Detection loop ────────────────────────────────────────────────────────────
async function detect() {
  if (!detecting || video.paused || video.ended) return;

  const now = performance.now();
  const dt  = now - lastTs;
  lastTs    = now;

  // FPS measurement (rolling 30 frames)
  frameTimes.push(dt);
  if (frameTimes.length > 30) frameTimes.shift();
  const avgDt = frameTimes.reduce((a, b) => a + b, 0) / frameTimes.length;
  statFps.textContent = Math.round(1000 / avgDt);

  // Run COCO-SSD
  const minScore    = confSlider.value / 100;
  const predictions = await cocoModel.detect(video, undefined, minScore);
  const vehicles    = predictions.filter(p => VEHICLE_CLASSES.has(p.class));

  // Scale factors: canvas coords → displayed video coords
  const rect   = video.getBoundingClientRect();
  const vidW   = video.videoWidth  || rect.width;
  const vidH   = video.videoHeight || rect.height;
  const scaleX = canvas.width  / vidW;
  const scaleY = canvas.height / vidH;

  const pixelsPerMeter = Number(scaleSlider.value);
  const objects        = tracker.update(vehicles, pixelsPerMeter);
  drawOverlay(objects, scaleX, scaleY);

  rafId = requestAnimationFrame(detect);
}

// ── Canvas sizing ─────────────────────────────────────────────────────────────
function syncCanvas() {
  const rect = video.getBoundingClientRect();
  canvas.width  = rect.width;
  canvas.height = rect.height;
  canvas.style.width  = rect.width  + 'px';
  canvas.style.height = rect.height + 'px';
}

// ── Video loading helpers ─────────────────────────────────────────────────────
function isYouTubeUrl(url) {
  return /youtube\.com|youtu\.be/.test(url);
}

function onVideoReady() {
  syncCanvas();
  btnStart.disabled = false;
  videoUrl.blur();
}

function loadVideoSrc(src) {
  video.src = src;
  video.load();
  video.addEventListener('loadeddata', onVideoReady, { once: true });
  video.addEventListener('error', () => {
    setHint(urlHint, 'Could not load video. Make sure CORS headers allow cross-origin access.', 'error');
  }, { once: true });
}

function setHint(el, msg, type = '') {
  el.textContent = msg;
  el.className   = 'hint ' + type;
}

// ── Controls ──────────────────────────────────────────────────────────────────
btnLoadUrl.addEventListener('click', () => {
  const raw = videoUrl.value.trim();
  if (!raw) return;

  if (isYouTubeUrl(raw)) {
    setHint(
      urlHint,
      '⚠ YouTube blocks canvas frame access (CORS). Download the video as an .mp4 and use the file upload instead.',
      'error'
    );
    return;
  }
  setHint(urlHint, 'Loading…', 'info');
  loadVideoSrc(raw);
});

videoUrl.addEventListener('keydown', e => {
  if (e.key === 'Enter') btnLoadUrl.click();
});

videoFile.addEventListener('change', () => {
  const file = videoFile.files[0];
  if (!file) return;
  fileLabel.textContent = file.name;
  setHint(urlHint, '');
  const url = URL.createObjectURL(file);
  loadVideoSrc(url);
});

btnStart.addEventListener('click', () => {
  if (!cocoModel) return;
  tracker   = new CentroidTracker();
  detecting = true;
  lastTs    = performance.now();
  frameTimes = [];
  btnStart.disabled = true;
  btnStop.disabled  = false;
  video.play();
  syncCanvas();
  rafId = requestAnimationFrame(detect);
});

btnStop.addEventListener('click', () => {
  detecting = false;
  if (rafId) cancelAnimationFrame(rafId);
  btnStart.disabled = false;
  btnStop.disabled  = true;
  statFps.textContent = '—';
});

btnClear.addEventListener('click', () => {
  if (tracker) tracker.clear();
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  statCount.textContent = '—';
  statAvg.textContent   = '—';
  statMax.textContent   = '—';
});

// ── Sliders ───────────────────────────────────────────────────────────────────
scaleSlider.addEventListener('input', () => {
  scaleValue.textContent = scaleSlider.value + ' px/m';
});

confSlider.addEventListener('input', () => {
  confValue.textContent = confSlider.value + '%';
});

// ── Resize ────────────────────────────────────────────────────────────────────
window.addEventListener('resize', syncCanvas);

// ── Load COCO-SSD model ───────────────────────────────────────────────────────
(async () => {
  try {
    modelStatus.textContent = 'Loading AI model…';
    cocoModel = await cocoSsd.load({ base: 'lite_mobilenet_v2' });
    modelStatus.textContent = 'Model ready';
    modelStatus.classList.add('ready');
    setTimeout(() => modelStatus.classList.add('hidden'), 2000);
    // Enable start if video already loaded
    if (video.readyState >= 2) btnStart.disabled = false;
  } catch (err) {
    modelStatus.textContent = 'Model failed to load: ' + err.message;
    console.error(err);
  }
})();
