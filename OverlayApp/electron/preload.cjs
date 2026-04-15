const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("simplyMidnightApi", {
  listCaptureSources() {
    return ipcRenderer.invoke("overlay:list-capture-sources");
  },
  setSelectedCaptureSource(sourceId) {
    return ipcRenderer.invoke("overlay:set-selected-source", sourceId);
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
