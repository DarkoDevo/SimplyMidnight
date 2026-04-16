import "./style.css";
import { getOverlayProfile, getOverlayProfileKeys } from "./profiles";

const app = document.querySelector("#app");

const captureButton = document.querySelector("#captureButton");
const mirrorButton = document.querySelector("#mirrorButton");
const alwaysOnTop = document.querySelector("#alwaysOnTop");
const profileSelect = document.querySelector("#profileSelect");
const profileMeta = document.querySelector("#profileMeta");
const sourceSelect = document.querySelector("#sourceSelect");
const refreshSourcesButton = document.querySelector("#refreshSourcesButton");
const identifyScreensButton = document.querySelector("#identifyScreensButton");
const autoLocateButton = document.querySelector("#autoLocateButton");
const sourceMeta = document.querySelector("#sourceMeta");
const cropX = document.querySelector("#cropX");
const cropY = document.querySelector("#cropY");
const cropW = document.querySelector("#cropW");
const cropH = document.querySelector("#cropH");
const scaleInput = document.querySelector("#scale");
const hideControlOnCapture = document.querySelector("#hideControlOnCapture");
const status = document.querySelector("#status");
const video = document.querySelector("#sourceVideo");
const canvas = document.querySelector("#previewCanvas");
const context = canvas.getContext("2d");

let activeStream = null;
let frameHandle = null;
let mirrorEnabled = false;
let lastMirrorPushAt = 0;
let captureSources = [];
const frameIntervalMs = 33;
const locateCanvas = document.createElement("canvas");
const locateContext = locateCanvas.getContext("2d", { willReadFrequently: true });

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
      sourceId: sourceSelect.value,
      mirrorEnabled,
      cropX: cropX.value,
      cropY: cropY.value,
      cropW: cropW.value,
      cropH: cropH.value,
      scale: scaleInput.value,
      hideControlOnCapture: hideControlOnCapture.checked,
      alwaysOnTop: alwaysOnTop.checked
    })
  );
}

function applyStoredSettings() {
  const saved = readSettings();
  if (saved.profile != null) profileSelect.value = saved.profile;
  if (saved.sourceId != null) sourceSelect.value = saved.sourceId;
  if (saved.mirrorEnabled != null) mirrorEnabled = Boolean(saved.mirrorEnabled);
  if (saved.cropX != null) cropX.value = saved.cropX;
  if (saved.cropY != null) cropY.value = saved.cropY;
  if (saved.cropW != null) cropW.value = saved.cropW;
  if (saved.cropH != null) cropH.value = saved.cropH;
  if (saved.scale != null) scaleInput.value = saved.scale;
  if (saved.hideControlOnCapture != null) hideControlOnCapture.checked = saved.hideControlOnCapture;
  alwaysOnTop.checked = true;
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

function formatSourceLabel(source) {
  if (!source) {
    return "Unknown source";
  }

  if (source.kind === "screen") {
    const display = source.display;
    if (display && display.bounds) {
      const primaryText = display.primary ? " | primary" : "";
      return `${source.name} | ${display.bounds.width}x${display.bounds.height} @ ${display.bounds.x},${display.bounds.y}${primaryText}`;
    }
    return `${source.name} | monitor`;
  }

  if (source.displayId) {
    return `${source.name} | window on display ${source.displayId}`;
  }

  return `${source.name} | window`;
}

function pickPreferredSource(sources) {
  const saved = readSettings();
  if (saved.sourceId && sources.some((source) => source.id === saved.sourceId)) {
    return saved.sourceId;
  }

  const primaryScreen = sources.find((source) => source.kind === "screen" && source.display && source.display.primary);
  if (primaryScreen) {
    return primaryScreen.id;
  }

  const anyScreen = sources.find((source) => source.kind === "screen");
  if (anyScreen) {
    return anyScreen.id;
  }

  const wowWindow = sources.find((source) => /world of warcraft/i.test(source.name));
  if (wowWindow) {
    return wowWindow.id;
  }

  return sources[0] ? sources[0].id : "";
}

function describeSelectedSource() {
  const selectedSource = captureSources.find((source) => source.id === sourceSelect.value);

  if (!selectedSource) {
    sourceMeta.textContent = "Choose the WoW window or your main monitor before starting capture.";
    return null;
  }

  if (selectedSource.kind === "screen") {
    sourceMeta.textContent = `Selected: ${formatSourceLabel(selectedSource)}. Screen capture includes anything visible on that monitor unless the control window is hidden or moved away.`;
  } else {
    sourceMeta.textContent = `Selected: ${formatSourceLabel(selectedSource)}. Window capture is usually cleaner if WoW is running in Windowed or Windowed (Fullscreen).`;
  }

  return selectedSource;
}

async function refreshCaptureSources() {
  if (!window.simplyMidnightApi || !window.simplyMidnightApi.listCaptureSources) {
    sourceMeta.textContent = "Capture source listing is unavailable in this build.";
    return;
  }

  try {
    const sources = await window.simplyMidnightApi.listCaptureSources();
    captureSources = sources;
    const fragment = document.createDocumentFragment();
    for (const source of sources) {
      const option = document.createElement("option");
      option.value = source.id;
      option.textContent = formatSourceLabel(source);
      fragment.appendChild(option);
    }

    sourceSelect.replaceChildren(fragment);
    sourceSelect.value = pickPreferredSource(sources);

    if (sources.length === 0) {
      const option = document.createElement("option");
      option.value = "";
      option.textContent = "No sources found";
      sourceSelect.replaceChildren(option);
      sourceMeta.textContent = "Electron did not return any capture sources yet. Try Refresh Sources.";
      status.textContent = "No capture sources available";
      writeSettings();
      return;
    }

    describeSelectedSource();

    status.textContent = `Ready | ${sources.length} capture source${sources.length === 1 ? "" : "s"} found`;
    writeSettings();
  } catch (error) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "Source load failed";
    sourceSelect.replaceChildren(option);
    sourceMeta.textContent = `Capture source listing failed: ${error.message}`;
    status.textContent = `Source load failed: ${error.message}`;
    writeSettings();
  }
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

function isMagenta(red, green, blue, alpha) {
  return alpha >= 200 && red >= 220 && green <= 70 && blue >= 220;
}

function isCyan(red, green, blue, alpha) {
  return alpha >= 200 && red <= 70 && green >= 220 && blue >= 220;
}

function locateSignatureBounds(profile) {
  if (!activeStream || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
    return null;
  }

  const sourceWidth = video.videoWidth || 0;
  const sourceHeight = video.videoHeight || 0;
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return null;
  }

  locateCanvas.width = sourceWidth;
  locateCanvas.height = sourceHeight;
  locateContext.drawImage(video, 0, 0, sourceWidth, sourceHeight);
  const imageData = locateContext.getImageData(0, 0, sourceWidth, sourceHeight);
  const pixels = imageData.data;
  const signatureSize = Math.max(Number(profile.signatureSize) || 6, 1);
  const signatureGap = Math.max(Number(profile.signatureGap) || 2, 0);
  const cyanOffset = signatureSize + signatureGap;

  function sample(x, y) {
    if (x < 0 || y < 0 || x >= sourceWidth || y >= sourceHeight) {
      return null;
    }

    const index = ((y * sourceWidth) + x) * 4;
    return {
      red: pixels[index],
      green: pixels[index + 1],
      blue: pixels[index + 2],
      alpha: pixels[index + 3]
    };
  }

  for (let y = 0; y <= sourceHeight - signatureSize; y += 1) {
    for (let x = 0; x <= sourceWidth - (cyanOffset + signatureSize); x += 1) {
      const magentaA = sample(x, y);
      const magentaB = sample(x + Math.max(signatureSize - 1, 0), y + Math.max(signatureSize - 1, 0));
      const cyanA = sample(x + cyanOffset, y);
      const cyanB = sample(x + cyanOffset + Math.max(signatureSize - 1, 0), y + Math.max(signatureSize - 1, 0));

      if (
        magentaA && magentaB && cyanA && cyanB &&
        isMagenta(magentaA.red, magentaA.green, magentaA.blue, magentaA.alpha) &&
        isMagenta(magentaB.red, magentaB.green, magentaB.blue, magentaB.alpha) &&
        isCyan(cyanA.red, cyanA.green, cyanA.blue, cyanA.alpha) &&
        isCyan(cyanB.red, cyanB.green, cyanB.blue, cyanB.alpha)
      ) {
        return {
          x: Math.max(x - (profile.signatureX || 0), 0),
          y: Math.max(y - (profile.signatureY || 0), 0)
        };
      }
    }
  }

  return null;
}

function autoLocateProfileCrop() {
  const profile = getOverlayProfile(profileSelect.value);
  const match = locateSignatureBounds(profile);
  if (!match) {
    status.textContent = "Auto locate failed: signature pixels not found in the current capture";
    return false;
  }

  cropX.value = String(match.x);
  cropY.value = String(match.y);
  cropW.value = String(profile.cropW);
  cropH.value = String(profile.cropH);
  status.textContent = `Auto locate matched at ${match.x}, ${match.y}`;
  updateMirrorBounds();
  writeSettings();
  return true;
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
    clearTimeout(frameHandle);
    frameHandle = null;
  }
}

function drawFrame() {
  if (!activeStream || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
    frameHandle = window.setTimeout(drawFrame, frameIntervalMs);
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

  frameHandle = window.setTimeout(drawFrame, frameIntervalMs);
}

async function startCapture() {
  if (activeStream) {
    activeStream.getTracks().forEach((track) => track.stop());
    activeStream = null;
    stopLoop();
  }

  const sourceId = sourceSelect.value;
  if (!sourceId) {
    status.textContent = "Capture failed: choose a source first";
    return;
  }

  try {
    const selectedSource = captureSources.find((source) => source.id === sourceId);

    if (
      hideControlOnCapture.checked &&
      selectedSource &&
      selectedSource.kind === "screen" &&
      window.simplyMidnightApi &&
      window.simplyMidnightApi.prepareCleanCapture
    ) {
      status.textContent = "Preparing clean screen capture...";
      await window.simplyMidnightApi.prepareCleanCapture();
    }

    if (window.simplyMidnightApi && window.simplyMidnightApi.setSelectedCaptureSource) {
      await window.simplyMidnightApi.setSelectedCaptureSource(sourceId);
    }

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
refreshSourcesButton.addEventListener("click", async () => {
  await refreshCaptureSources();
});
identifyScreensButton.addEventListener("click", async () => {
  if (window.simplyMidnightApi && window.simplyMidnightApi.identifyDisplays) {
    await window.simplyMidnightApi.identifyDisplays();
  }
});
autoLocateButton.addEventListener("click", () => {
  autoLocateProfileCrop();
});
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
  alwaysOnTop.checked = true;
  writeSettings();
  if (window.simplyMidnightApi) {
    await window.simplyMidnightApi.setAlwaysOnTop(true);
  }
});

hideControlOnCapture.addEventListener("change", () => {
  writeSettings();
});

profileSelect.addEventListener("change", () => {
  applyProfilePreset();
});

sourceSelect.addEventListener("change", () => {
  describeSelectedSource();
  writeSettings();
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
  refreshCaptureSources();
  alwaysOnTop.checked = true;
  window.simplyMidnightApi.setAlwaysOnTop(true);
  window.simplyMidnightApi.getMeta().then((meta) => {
    const profile = getOverlayProfile(profileSelect.value);
    status.textContent = `Ready | overlay v${meta.version} | ${profile.label}`;
  });
  if (mirrorEnabled) {
    window.simplyMidnightApi.setMirrorEnabled(true).then(() => updateMirrorBounds());
  }
}
