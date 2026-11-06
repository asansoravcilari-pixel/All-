{{flutter_js}}
{{flutter_build_config}}

// Motor dosyaları (CanvasKit / Skwasm) dış CDN yerine kendi sunucumuzdan yüklenir.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
