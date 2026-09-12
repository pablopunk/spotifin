#!/usr/bin/env python3

import hashlib
import json
from pathlib import Path


BUILD_DIRECTORY = Path(__file__).resolve().parent.parent / "build" / "web"
OUTPUT = BUILD_DIRECTORY / "spotifin_service_worker.js"
EXCLUDED = {
    ".last_build_id",
    "flutter_service_worker.js",
    "spotifin_service_worker.js",
}


def shell_files() -> list[str]:
    return sorted(
        path.relative_to(BUILD_DIRECTORY).as_posix()
        for path in BUILD_DIRECTORY.rglob("*")
        if path.is_file()
        and path.relative_to(BUILD_DIRECTORY).as_posix() not in EXCLUDED
        and not path.name.endswith(".map")
        and not path.name.endswith(".symbols")
        and not path.name.startswith("skwasm")
    )


def version_for(files: list[str]) -> str:
    digest = hashlib.sha256()
    for name in files:
        digest.update(name.encode())
        digest.update((BUILD_DIRECTORY / name).read_bytes())
    return digest.hexdigest()[:16]


def worker_source(files: list[str], version: str) -> str:
    resources = json.dumps(files, separators=(",", ":"))
    return f"""'use strict';

const VERSION = {json.dumps(version)};
const CACHE = `spotifin-shell-${{VERSION}}`;
const CACHE_PREFIX = 'spotifin-shell-';
const RESOURCES = {resources};

self.addEventListener('install', (event) => {{
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(RESOURCES)));
}});

self.addEventListener('activate', (event) => {{
  event.waitUntil((async () => {{
    const names = await caches.keys();
    await Promise.all(names
      .filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE)
      .map((name) => caches.delete(name)));
    await self.clients.claim();
  }})());
}});

self.addEventListener('fetch', (event) => {{
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (event.request.mode === 'navigate') {{
    event.respondWith(caches.open(CACHE).then((cache) =>
      cache.match('index.html').then((cached) => cached || fetch(event.request))));
    return;
  }}
  const path = decodeURIComponent(url.pathname)
    .slice(new URL(self.registration.scope).pathname.length);
  if (!RESOURCES.includes(path)) return;
  event.respondWith(caches.open(CACHE).then((cache) =>
    cache.match(path).then((cached) => cached || fetch(event.request))));
}});
"""


def main() -> None:
    files = shell_files()
    if "index.html" not in files or "main.dart.js" not in files:
        raise RuntimeError("Flutter web output is incomplete")
    OUTPUT.write_text(worker_source(files, version_for(files)))
    old_worker = BUILD_DIRECTORY / "flutter_service_worker.js"
    old_worker.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
