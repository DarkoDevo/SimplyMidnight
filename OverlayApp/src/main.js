import "./style.css";

const captureButton = document.querySelector("#captureButton");
const alwaysOnTop = document.querySelector("#alwaysOnTop");
const cropX = document.querySelector("#cropX");
const cropY = document.querySelector("#cropY");
const cropW = document.querySelector("#cropW");
const cropH = document.querySelector("#cropH");
const scaleInput = document.querySelector("#scale");
const status = document.querySelector("#status");
const video = document.querySelector("#sourceVideo");
const canvas = document.querySelector("#previewCanvas");
const context = canvas.getContext("2d");

let activeStream = null;
let frameHandle = null;

const storageKey = "simplymidnight-overlay-settings";

function readSettings() {
  try {
    return JSON.parse(localStorage.getItem(storageKey) || "{}");
  } catch {
    return {};
  }
}

function writeSettings() {
  localStorage.setItem(
    storageKey,
    JSON.stringify({
      cropX: cropX.value,
      cropY: cropY.value,
      cropW: cropW.value,
      cropH: cropH.value,
      scale: scaleInput.value,
      alwaysOnTop: alwaysOnTop.checked
    })
  );
}

function applyStoredSettings() {
  const saved = readSettings();
  if (saved.cropX != null) cropX.value = saved.cropX;
  if (saved.cropY != null) cropY.value = saved.cropY;
  if (saved.cropW != null) cropW.value = saved.cropW;
  if (saved.cropH != null) cropH.value = saved.cropH;
  if (saved.scale != null) scaleInput.value = saved.scale;
  if (saved.alwaysOnTop != null) alwaysOnTop.checked = saved.alwaysOnTop;
}

function stopLoop() {
  if (frameHandle != null) {
    cancelAnimationFrame(frameHandle);
    frameHandle = null;
  }
}

function drawFrame() {
  if (!activeStream || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
    frameHandle = requestAnimationFrame(drawFrame);
    return;
  }

  const x = Number(cropX.value) || 0;
  const y = Number(cropY.value) || 0;
  const width = Math.max(Number(cropW.value) || 390, 1);
  const height = Math.max(Number(cropH.value) || 132, 1);
  const scale = Math.max(Number(scaleInput.value) || 1, 0.25);

  canvas.width = Math.floor(width * scale);
  canvas.height = Math.floor(height * scale);
  context.imageSmoothingEnabled = false;
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.drawImage(video, x, y, width, height, 0, 0, canvas.width, canvas.height);

  frameHandle = requestAnimationFrame(drawFrame);
}

async function startCapture() {
  if (activeStream) {
    activeStream.getTracks().forEach((track) => track.stop());
    activeStream = null;
    stopLoop();
  }

  try {
    const stream = await navigator.mediaDevices.getDisplayMedia({
      audio: false,
      video: {
        frameRate: 30
      }
    });

    activeStream = stream;
    video.srcObject = stream;
    await video.play();

    status.textContent = "Capture active";
    drawFrame();

    stream.getVideoTracks()[0].addEventListener("ended", () => {
      status.textContent = "Capture ended";
      activeStream = null;
      stopLoop();
    });
  } catch (error) {
    status.textContent = `Capture failed: ${error.message}`;
  }
}

captureButton.addEventListener("click", startCapture);

alwaysOnTop.addEventListener("change", async () => {
  writeSettings();
  if (window.simplyMidnightApi) {
    await window.simplyMidnightApi.setAlwaysOnTop(alwaysOnTop.checked);
  }
});

[cropX, cropY, cropW, cropH, scaleInput].forEach((element) => {
  element.addEventListener("input", () => {
    writeSettings();
  });
});

applyStoredSettings();

if (window.simplyMidnightApi) {
  window.simplyMidnightApi.setAlwaysOnTop(alwaysOnTop.checked);
  window.simplyMidnightApi.getMeta().then((meta) => {
    status.textContent = `Ready | overlay v${meta.version}`;
  });
}

