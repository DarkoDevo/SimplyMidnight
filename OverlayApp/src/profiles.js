export const overlayProfiles = {
  debug_hud: {
    key: "debug_hud",
    label: "Debug HUD",
    description: "Full in-game HUD with labels, bars, and flags.",
    cropW: 390,
    cropH: 132,
    scale: 2,
    signatureX: 4,
    signatureY: 4,
    signatureSize: 8,
    signatureGap: 2,
    locatePadX: 0,
    locatePadY: 0
  },
  ggl_legacy_5slot: {
    key: "ggl_legacy_5slot",
    label: "GGL Legacy 5 Slot",
    description: "Lean five-slot strip sized for legacy GGLoader icon reading.",
    cropW: 304,
    cropH: 56,
    scale: 3,
    signatureX: 4,
    signatureY: 4,
    signatureSize: 6,
    signatureGap: 2,
    locatePadX: 0,
    locatePadY: 0
  },
  overlay_compact: {
    key: "overlay_compact",
    label: "Overlay Compact",
    description: "Compact overlay with icons, bars, and a few state cells.",
    cropW: 256,
    cropH: 92,
    scale: 2.5,
    signatureX: 4,
    signatureY: 4,
    signatureSize: 6,
    signatureGap: 2,
    locatePadX: 0,
    locatePadY: 0
  }
};

export function getOverlayProfile(key) {
  return overlayProfiles[key] || overlayProfiles.debug_hud;
}

export function getOverlayProfileKeys() {
  return Object.keys(overlayProfiles);
}
