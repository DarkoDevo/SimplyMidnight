import "./style.css";

const mirrorCanvas = document.querySelector("#mirrorCanvas");
const mirrorVersion = document.querySelector("#mirrorVersion");
const mirrorContext = mirrorCanvas.getContext("2d");
const frameImage = new Image();

frameImage.addEventListener("load", () => {
  mirrorCanvas.width = frameImage.width;
  mirrorCanvas.height = frameImage.height;
  mirrorContext.imageSmoothingEnabled = false;
  mirrorContext.clearRect(0, 0, mirrorCanvas.width, mirrorCanvas.height);
  mirrorContext.drawImage(frameImage, 0, 0);
});

if (window.simplyMidnightApi) {
  window.simplyMidnightApi.getMeta().then((meta) => {
    if (mirrorVersion) {
      mirrorVersion.textContent = `v${meta.version}`;
    }
  });

  window.simplyMidnightApi.onMirrorFrame((payload) => {
    if (!payload || !payload.dataUrl) {
      return;
    }

    frameImage.src = payload.dataUrl;
  });
}
