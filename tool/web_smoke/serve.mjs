// Serves a built web directory the way Vercel does with cleanUrls: `*.html` URLs
// answer 308 to the extensionless path, and extensionless paths fall back to index.html.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const root = process.argv[2];
const port = Number(process.argv[3] ?? 4173);

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.css': 'text/css',
};

async function isFile(path) {
  return (await stat(path).catch(() => null))?.isFile() ?? false;
}

function cleanUrlRedirect(pathname) {
  if (!pathname.endsWith('.html')) return null;
  const clean = pathname.slice(0, -'.html'.length);
  return clean.endsWith('/index') ? clean.slice(0, -'index'.length) : clean;
}

async function resolveFile(pathname) {
  const local = join(root, normalize(pathname));
  if (pathname.endsWith('/')) return join(local, 'index.html');
  if (await isFile(local)) return local;
  if (await isFile(`${local}.html`)) return `${local}.html`;
  if (!extname(pathname)) return join(root, 'index.html');
  return null;
}

createServer(async (req, res) => {
  const { pathname, search } = new URL(req.url, 'http://localhost');
  const redirect = cleanUrlRedirect(pathname);
  if (redirect !== null) {
    res.writeHead(308, { Location: redirect + search }).end();
    return;
  }
  const file = await resolveFile(decodeURIComponent(pathname));
  if (!file) {
    res.writeHead(404).end('Not found');
    return;
  }
  res.writeHead(200, {
    'Content-Type': contentTypes[extname(file)] ?? 'application/octet-stream',
    'Cache-Control': 'public, max-age=0, must-revalidate',
  });
  res.end(await readFile(file));
}).listen(port, '127.0.0.1');
