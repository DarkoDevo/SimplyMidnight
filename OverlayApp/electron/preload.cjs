const { contextBridge, ipcRenderer } = require("electron");
const viewModeArg = process.argv.find((arg) => typeof arg === "string" && arg.indexOf("--sm-view=") === 0);
const viewMode = viewModeArg ? viewModeArg.split("=")[1] : "control";

contextBridge.exposeInMainWorld("simplyMidnightApi", {
  getViewMode() {
    return viewMode;
  },
  listCaptureSources() {
    return ipcRenderer.invoke("overlay:list-capture-sources");
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
