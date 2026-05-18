# MotiProxy

A Cloudflare Worker that proxies Smart Capture requests from the Moti iOS app
to Google Gemini. Holds the real Gemini API key server-side so it never ships
in the app binary.

```
iOS app  ──POST──▶  moti-proxy.workers.dev  ──POST──▶  generativelanguage.googleapis.com
            │                                 │
            └─ APP_SHARED_SECRET              └─ GEMINI_API_KEY (server-only)
```

## What the Worker does

- Accepts `POST /v1/models/<model>:generateContent`
- Authenticates the iOS app via `Authorization: Bearer <APP_SHARED_SECRET>` (constant-time compared)
- Allowlists a small set of models (`gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-2.5-pro`)
- Caps request body at 32 KB
- Optional per-IP rate limit (30 req/min) when a KV namespace is bound
- Forwards the body to Gemini with the real API key as a query parameter
- Returns Gemini's response verbatim

## One-time setup

1. **Install Node + Wrangler CLI** (Cloudflare's tool)
   ```bash
   # If you don't have Node yet:  brew install node
   cd MotiProxy
   npm install
   ```

2. **Sign in to Cloudflare**
   ```bash
   npx wrangler login
   ```
   Free Cloudflare account works fine. Free tier covers 100k requests/day.

3. **Set the two secrets**
   ```bash
   # Your real Gemini API key — get it at https://aistudio.google.com/app/apikey
   npx wrangler secret put GEMINI_API_KEY
   # Paste the key when prompted.

   # A long random string the iOS app will send. Generate with:
   openssl rand -hex 32
   # Then:
   npx wrangler secret put APP_SHARED_SECRET
   # Paste the random string.
   ```

4. **Deploy**
   ```bash
   npx wrangler deploy
   ```
   Note the deployed URL printed at the end — looks like:
   ```
   https://moti-proxy.<your-cloudflare-subdomain>.workers.dev
   ```

5. **Wire the iOS app** — open `Moti/Secrets.swift` and set:
   ```swift
   static let proxyBaseURL: String?      = "https://moti-proxy.<your-cloudflare-subdomain>.workers.dev"
   static let proxySharedSecret: String? = "<the same APP_SHARED_SECRET you set above>"
   static let geminiAPIKey: String?      = nil   // proxy supersedes direct
   ```
   Rebuild the iOS app. Smart Capture in LLM mode will now route through your proxy.

## Local development

Run the Worker locally without deploying:

```bash
cp .dev.vars.example .dev.vars
# Edit .dev.vars with your real Gemini key + a dev shared secret
npm run dev
```

Wrangler serves it at `http://localhost:8787`. Point the iOS app at that URL via
`Secrets.swift` during dev.

## Optional: enable rate limiting

```bash
npx wrangler kv namespace create RATE_LIMIT
```

Copy the printed `id` into `wrangler.toml`, uncomment the `[[kv_namespaces]]`
block, and re-deploy. The Worker will then enforce 30 req/min per IP.

## Rotating the shared secret

If the iOS-side shared secret ever leaks (e.g., someone disassembles the app):

```bash
openssl rand -hex 32                              # new value
npx wrangler secret put APP_SHARED_SECRET         # paste it
# Update Moti/Secrets.swift with the same value
# Rebuild the iOS app, push a release
```

Old clients with the old secret stop working the moment you `secret put` —
Cloudflare swaps it atomically.

## What this does NOT protect against

- A determined attacker who reverse-engineers the iOS binary will find the
  shared secret and can call your proxy. The Gemini key stays safe, but they
  can use your quota. Mitigations:
    - Rate limit (already configurable above)
    - Rotate the shared secret periodically
    - Add Apple App Attest for cryptographic device verification (v2 work)

- Cost runaway. Set a Gemini API budget cap in Google Cloud Console.
