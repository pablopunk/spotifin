{{flutter_js}}
{{flutter_build_config}}

if (navigator.storage?.persist) {
  navigator.storage.persist().catch(() => false);
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('spotifin_service_worker.js').catch(() => {});
}

_flutter.loader.load();
