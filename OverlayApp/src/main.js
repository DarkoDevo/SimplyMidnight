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
const sourceMeta = document.querySelector("#sourceMeta");
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
      sourceId: sourceSelect.value,
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
  if (saved.sourceId != null) sourceSelect.value = saved.sourceId;
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

async function refreshCaptureSources() {
  if (!window.simplyMidnightApi || !window.simplyMidnightApi.listCaptureSources) {
    sourceMeta.textContent = "Capture source listing is unavailable in this build.";
    return;
  }

  try {
    const sources = await window.simplyMidnightApi.listCaptureSources();
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

    const selectedSource = sources.find((source) => source.id === sourceSelect.value);
    sourceMeta.textContent = selectedSource
      ? `Selected: ${formatSourceLabel(selectedSource)}`
      : "Choose the WoW window or your main monitor before starting capture.";

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

  const sourceId = sourceSelect.value;
  if (!sourceId) {
    status.textContent = "Capture failed: choose a source first";
    return;
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        mandatory: {
          chromeMediaSource: "desktop",
          chromeMediaSourceId: sourceId,
          maxFrameRate: 30,
          minWidth: 320,
          minHeight: 180,
          maxWidth: 7680,
          maxHeight: 4320
        }
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

profileSelect.addEventListener("change", () => {
  applyProfilePreset();
});

sourceSelect.addEventListener("change", () => {
  const label = sourceSelect.options[sourceSelect.selectedIndex]?.textContent;
  sourceMeta.textContent = label ? `Selected: ${label}` : "Choose the WoW window or your main monitor before starting capture.";
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
  window.simplyMidnightApi.setAlwaysOnTop(alwaysOnTop.checked);
  window.simplyMidnightApi.getMeta().then((meta) => {
    const profile = getOverlayProfile(profileSelect.value);
    status.textContent = `Ready | overlay v${meta.version} | ${profile.label}`;
  });
  if (mirrorEnabled) {
    window.simplyMidnightApi.setMirrorEnabled(true).then(() => updateMirrorBounds());
  }
}
