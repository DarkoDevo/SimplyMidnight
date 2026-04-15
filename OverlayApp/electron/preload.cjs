const { contextBridge, ipcRenderer, desktopCapturer } = require("electron");

contextBridge.exposeInMainWorld("simplyMidnightApi", {
  async listCaptureSources() {
    const sources = await desktopCapturer.getSources({
      types: ["window", "screen"],
      thumbnailSize: {
        width: 320,
        height: 180
      }
    });

    return sources.map((source) => ({
      id: source.id,
      name: source.name,
      displayId: source.display_id || "",
      thumbnailDataUrl: source.thumbnail && !source.thumbnail.isEmpty() ? source.thumbnail.toDataURL() : null
    }));
  },
  setAlwaysOnTop(value) {
    return ipcRenderer.invoke("overlay:set-always-on-top", value);
  },
  setMirrorEnabled(value) {
    return ipcRenderer.invoke("overlay:set-mirror-enabled", value);
  },
  setMirrorBounds(width, height) {
    return ipcRenderer.invoke("overlay:set-mirror-bounds", { width, height });
  },
  sendMirrorFrame(frame) {
    return ipcRenderer.invoke("overlay:send-mirror-frame", frame);
  },
  onMirrorFrame(callback) {
    if (typeof callback !== "function") {
      return () => {};
    }

    const listener = (_, payload) => callback(payload);
    ipcRenderer.on("overlay:mirror-frame", listener);
    return () => ipcRenderer.removeListener("overlay:mirror-frame", listener);
  },
  getMeta() {
    return ipcRenderer.invoke("overlay:get-meta");
  }
});
