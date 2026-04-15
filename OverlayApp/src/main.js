import "./style.css";
import { getOverlayProfile, getOverlayProfileKeys } from "./profiles";

const isMirrorMode = new URLSearchParams(window.location.search).get("mirror") === "1";

if (isMirrorMode) {
  const app = document.querySelector("#app");
  const mirrorApp = document.querySelector("#mirrorApp");
  const mirrorCanvas = document.querySelector("#mirrorCanvas");
  const mirrorContext = mirrorCanvas.getContext("2d");
  const frameImage = new Image();

  if (app) app.hidden = true;
  if (mirrorApp) mirrorApp.hidden = false;

  frameImage.addEventListener("load", () => {
    mirrorCanvas.width = frameImage.width;
    mirrorCanvas.height = frameImage.height;
    mirrorContext.imageSmoothingEnabled = false;
    mirrorContext.clearRect(0, 0, mirrorCanvas.width, mirrorCanvas.height);
    mirrorContext.drawImage(frameImage, 0, 0);
  });

  if (window.simplyMidnightApi) {
    window.simplyMidnightApi.onMirrorFrame((payload) => {
      if (!payload || !payload.dataUrl) {
        return;
      }
      frameImage.src = payload.dataUrl;
    });
  }
} else {
const captureButton = document.querySelector("#captureButton");
const mirrorButton = document.querySelector("#mirrorButton");
const alwaysOnTop = document.querySelector("#alwaysOnTop");
const profileSelect = document.querySelector("#profileSelect");
const profileMeta = document.querySelector("#profileMeta");
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
let mirrorEnabled = false;
let lastMirrorPushAt = 0;

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
      profile: profileSelect.value,
      mirrorEnabled,
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
  if (saved.profile != null) profileSelect.value = saved.profile;
  if (saved.mirrorEnabled != null) mirrorEnabled = Boolean(saved.mirrorEnabled);
  if (saved.cropX != null) cropX.value = saved.cropX;
  if (saved.cropY != null) cropY.value = saved.cropY;
  if (saved.cropW != null) cropW.value = saved.cropW;
  if (saved.cropH != null) cropH.value = saved.cropH;
  if (saved.scale != null) scaleInput.value = saved.scale;
  if (saved.alwaysOnTop != null) alwaysOnTop.checked = saved.alwaysOnTop;
}

function populateProfiles() {
  const fragment = document.createDocumentFragment();
  for (const key of getOverlayProfileKeys()) {
    const profile = getOverlayProfile(key);
    const option = document.createElement("option");
    option.value = profile.key;
    option.textContent = profile.label;
    fragment.appendChild(option);
  }
  profileSelect.replaceChildren(fragment);
}

function applyProfilePreset({ keepPosition = true } = {}) {
  const profile = getOverlayProfile(profileSelect.value);
  if (!keepPosition) {
    cropX.value = "0";
    cropY.value = "0";
  }
  cropW.value = String(profile.cropW);
  cropH.value = String(profile.cropH);
  scaleInput.value = String(profile.scale);
  profileMeta.textContent = `${profile.description} | ${profile.cropW}x${profile.cropH} @ ${profile.scale}x`;
  updateMirrorButton();
  updateMirrorBounds();
  writeSettings();
}

async function updateMirrorBounds() {
  if (!window.simplyMidnightApi || !mirrorEnabled) {
    return;
  }

  const width = Math.floor((Math.max(Number(cropW.value) || 390, 1)) * (Math.max(Number(scaleInput.value) || 1, 0.25)));
  const height = Math.floor((Math.max(Number(cropH.value) || 132, 1)) * (Math.max(Number(scaleInput.value) || 1, 0.25)));
  await window.simplyMidnightApi.setMirrorBounds(width, height);
}

function updateMirrorButton() {
  mirrorButton.textContent = mirrorEnabled ? "Close Mirror" : "Open Mirror";
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

  if (mirrorEnabled && window.simplyMidnightApi) {
    const now = performance.now();
    if ((now - lastMirrorPushAt) >= 100) {
      lastMirrorPushAt = now;
      window.simplyMidnightApi.sendMirrorFrame({
        dataUrl: canvas.toDataURL("image/png"),
        width: canvas.width,
        height: canvas.height
      });
    }
  }

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
mirrorButton.addEventListener("click", async () => {
  mirrorEnabled = !mirrorEnabled;
  updateMirrorButton();
  writeSettings();
  if (window.simplyMidnightApi) {
    await window.simplyMidnightApi.setMirrorEnabled(mirrorEnabled);
    if (mirrorEnabled) {
      await updateMirrorBounds();
    }
  }
});

alwaysOnTop.addEventListener("change", async () => {
  writeSettings();
  if (window.simplyMidnightApi) {
    await window.simplyMidnightApi.setAlwaysOnTop(alwaysOnTop.checked);
  }
});

[profileSelect].forEach((element) => {
  element.addEventListener("change", () => {
    applyProfilePreset();
  });
});

[cropX, cropY, cropW, cropH, scaleInput].forEach((element) => {
  element.addEventListener("input", () => {
    updateMirrorBounds();
    writeSettings();
  });
});

populateProfiles();
applyStoredSettings();
applyProfilePreset();
updateMirrorButton();

if (window.simplyMidnightApi) {
  window.simplyMidnightApi.setAlwaysOnTop(alwaysOnTop.checked);
  window.simplyMidnightApi.getMeta().then((meta) => {
    const profile = getOverlayProfile(profileSelect.value);
    status.textContent = `Ready | overlay v${meta.version} | ${profile.label}`;
  });
  if (mirrorEnabled) {
    window.simplyMidnightApi.setMirrorEnabled(true).then(() => updateMirrorBounds());
  }
}
}
