/******************************************************************************
 * Minimal static file server for the built PocketHost dashboard.
 *
 * The dashboard is a prerendered SvelteKit app (adapter-static), so all it
 * needs is a file server with a SPA fallback to 404.html / index.html.
 ******************************************************************************/
import { createServer } from 'node:http'
import { createReadStream, existsSync, statSync } from 'node:fs'
import { extname, join, normalize, resolve, sep } from 'node:path'

const ROOT = resolve(process.env.DASHBOARD_ROOT || '/app/packages/dashboard/build')
const PORT = Number(process.env.DASHBOARD_PORT || 8080)
const HOST = process.env.DASHBOARD_HOST || '0.0.0.0'

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.xml': 'application/xml',
  '.webmanifest': 'application/manifest+json',
  '.wasm': 'application/wasm',
}

const send = (res, path, status = 200) => {
  res.writeHead(status, {
    'Content-Type': MIME[extname(path).toLowerCase()] || 'application/octet-stream',
    'Cache-Control': path.endsWith('.html') ? 'no-cache' : 'public, max-age=3600',
  })
  createReadStream(path).pipe(res)
}

const server = createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405).end('Method Not Allowed')
    return
  }

  const urlPath = decodeURIComponent((req.url || '/').split('?')[0])
  const relative = normalize(urlPath).replace(/^(\.\.[/\\])+/, '').replace(/^\/+/, '')

  const candidates = [join(ROOT, relative), join(ROOT, relative, 'index.html')]
  for (const candidate of candidates) {
    if (!candidate.startsWith(ROOT + sep) && candidate !== ROOT) continue
    if (existsSync(candidate) && statSync(candidate).isFile()) {
      send(res, candidate)
      return
    }
  }

  const notFound = join(ROOT, '404.html')
  const fallback = existsSync(notFound) ? notFound : join(ROOT, 'index.html')
  send(res, fallback, 404)
})

server.listen(PORT, HOST, () => {
  console.log(`[dashboard] serving ${ROOT} on http://${HOST}:${PORT}`)
})
