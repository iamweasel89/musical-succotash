'use strict';

const video          = document.getElementById('video');
const canvas         = document.getElementById('canvas');
const placeholder    = document.getElementById('placeholder');
const startBtn       = document.getElementById('startBtn');
const stopBtn        = document.getElementById('stopBtn');
const flipBtn        = document.getElementById('flipBtn');
const clearBtn       = document.getElementById('clearBtn');
const hint           = document.getElementById('hint');
const colorRow       = document.getElementById('colorRow');
const colorPreview   = document.getElementById('colorPreview');
const colorHex       = document.getElementById('colorHex');
const toleranceInput = document.getElementById('tolerance');
const toleranceVal   = document.getElementById('toleranceVal');
const opacityInput   = document.getElementById('opacity');
const opacityVal     = document.getElementById('opacityVal');
const highlightInput = document.getElementById('highlightColor');

// willReadFrequently — performance hint for frequent getImageData calls
const ctx = canvas.getContext('2d', { willReadFrequently: true });

let stream      = null;
let animId      = null;
let pickedColor = null;  // { r, g, b }
// 'environment' = задняя камера (по умолчанию для мобильных), 'user' = фронтальная
let facingMode  = 'environment';

// ── Camera ────────────────────────────────────────────────────────────────

startBtn.addEventListener('click', () => startCamera());
flipBtn.addEventListener('click', () => {
  facingMode = facingMode === 'environment' ? 'user' : 'environment';
  startCamera();
});

async function startCamera() {
  // Stop existing stream before starting a new one
  if (stream) {
    stream.getTracks().forEach(t => t.stop());
    stream = null;
  }

  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: { ideal: facingMode } },
    });
    video.srcObject = stream;
    await video.play();

    // Cap canvas to 640px wide — full 1080p kills mobile JS performance
    const setCanvasSize = () => {
      const MAX_W = 640;
      const scale = Math.min(1, MAX_W / (video.videoWidth || MAX_W));
      canvas.width  = Math.round((video.videoWidth  || MAX_W) * scale);
      canvas.height = Math.round((video.videoHeight || 360)   * scale);
    };
    video.addEventListener('loadedmetadata', setCanvasSize, { once: true });
    if (video.videoWidth) setCanvasSize(); // already available

    placeholder.style.display = 'none';
    canvas.style.display      = 'block';
    startBtn.disabled = true;
    stopBtn.disabled  = false;
    flipBtn.disabled  = false;
    clearBtn.disabled = false;
    hint.textContent  = 'Нажмите на любую точку видео, чтобы выбрать цвет';

    if (!animId) startLoop();
  } catch (e) {
    hint.textContent = 'Не удалось получить доступ к камере: ' + e.message;
  }
}

stopBtn.addEventListener('click', stopCamera);

function stopCamera() {
  cancelAnimationFrame(animId);
  animId = null;

  if (stream) {
    stream.getTracks().forEach(t => t.stop());
    stream = null;
  }

  video.srcObject           = null;
  canvas.style.display      = 'none';
  placeholder.style.display = '';
  hint.textContent          = '';

  clearSelection();

  startBtn.disabled = false;
  stopBtn.disabled  = true;
  flipBtn.disabled  = true;
  clearBtn.disabled = true;
}

// ── Pick color by tapping the canvas ─────────────────────────────────────
// No intermediate "pick mode" needed — any tap picks the color directly.

function pickColorAt(clientX, clientY) {
  if (!stream) return;

  const rect   = canvas.getBoundingClientRect();
  const scaleX = canvas.width  / rect.width;
  const scaleY = canvas.height / rect.height;
  const x = Math.round((clientX - rect.left) * scaleX);
  const y = Math.round((clientY - rect.top)  * scaleY);

  const [r, g, b] = ctx.getImageData(x, y, 1, 1).data;

  pickedColor = { r, g, b };
  const hex = toHex(r, g, b);
  colorPreview.style.background = hex;
  colorHex.textContent          = hex;
  colorRow.style.display        = '';
  hint.textContent              = 'Цвет выбран. Нажмите снова, чтобы изменить.';
}

// Touch: use touchend to get last touch position without triggering scroll
canvas.addEventListener('touchend', (e) => {
  e.preventDefault();
  const t = e.changedTouches[0];
  pickColorAt(t.clientX, t.clientY);
}, { passive: false });

// Fallback for mouse / desktop
canvas.addEventListener('click', (e) => {
  pickColorAt(e.clientX, e.clientY);
});

clearBtn.addEventListener('click', clearSelection);

function clearSelection() {
  pickedColor            = null;
  colorRow.style.display = 'none';
  if (stream) hint.textContent = 'Нажмите на любую точку видео, чтобы выбрать цвет';
}

// ── Sliders ───────────────────────────────────────────────────────────────

toleranceInput.addEventListener('input', () => {
  toleranceVal.textContent = toleranceInput.value;
});

opacityInput.addEventListener('input', () => {
  opacityVal.textContent = opacityInput.value + '%';
});

// ── Render loop ───────────────────────────────────────────────────────────

function startLoop() {
  function loop() {
    if (!stream) return;

    // Draw current video frame
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

    // Highlight matching pixels
    if (pickedColor) {
      highlightByColor();
    }

    animId = requestAnimationFrame(loop);
  }
  animId = requestAnimationFrame(loop);
}

function highlightByColor() {
  const tolerance = parseInt(toleranceInput.value, 10);
  const alpha     = parseInt(opacityInput.value, 10) / 100;
  const hc        = fromHex(highlightInput.value);

  // Squared threshold — avoids sqrt per pixel
  const threshSq = tolerance * tolerance * 3;

  const { width, height } = canvas;
  const frame = ctx.getImageData(0, 0, width, height);
  const d     = frame.data;

  const { r: tr, g: tg, b: tb } = pickedColor;
  const hr = hc.r, hg = hc.g, hb = hc.b;
  const inv = 1 - alpha;

  for (let i = 0; i < d.length; i += 4) {
    const dr = d[i]     - tr;
    const dg = d[i + 1] - tg;
    const db = d[i + 2] - tb;

    if (dr * dr + dg * dg + db * db <= threshSq) {
      d[i]     = (d[i]     * inv + hr * alpha) | 0;
      d[i + 1] = (d[i + 1] * inv + hg * alpha) | 0;
      d[i + 2] = (d[i + 2] * inv + hb * alpha) | 0;
    }
  }

  ctx.putImageData(frame, 0, 0);
}

// ── Helpers ───────────────────────────────────────────────────────────────

function toHex(r, g, b) {
  return '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex) {
  return {
    r: parseInt(hex.slice(1, 3), 16),
    g: parseInt(hex.slice(3, 5), 16),
    b: parseInt(hex.slice(5, 7), 16),
  };
}
