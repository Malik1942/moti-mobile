// MotiProxy — Cloudflare Worker that forwards Smart Capture requests to Google
// Gemini, holding the real API key server-side so it never ships in the iOS app.
//
// Request flow:
//   iOS app  ──POST──▶  this Worker  ──POST──▶  generativelanguage.googleapis.com
//             │                       │
//             └─ shared secret        └─ real GEMINI_API_KEY (env binding)
//
// The Worker also enforces:
//   - shared-secret auth (Authorization: Bearer ...) — first line of defense
//   - allowlisted Gemini models — prevents callers from pivoting to other models
//   - body size cap                                  — caps prompt-injection blast radius
//   - per-IP rate limit via KV counter (if KV is bound) — graceful degradation if abused

interface Env {
    /** Real Gemini API key. Set via: wrangler secret put GEMINI_API_KEY */
    GEMINI_API_KEY: string;
    /**
     * Shared secret the iOS app sends in `Authorization: Bearer <secret>`.
     * Generate with: openssl rand -hex 32
     * Set via: wrangler secret put APP_SHARED_SECRET
     */
    APP_SHARED_SECRET: string;
    /**
     * Optional KV namespace for per-IP rate limiting. Bind in wrangler.toml with:
     *     [[kv_namespaces]] binding = "RATE_LIMIT" id = "<your-kv-id>"
     * If unbound, rate limiting is skipped (fine for early stage).
     */
    RATE_LIMIT?: KVNamespace;
}

const ALLOWED_MODELS = new Set([
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.5-pro",
]);

const MAX_BODY_BYTES = 32 * 1024;   // 32 KB — generous for Smart Capture prompts
const RATE_LIMIT_PER_MINUTE = 30;   // requests per IP per minute

export default {
    async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
        // CORS preflight — iOS doesn't need this, but a future web/desktop client might.
        if (request.method === "OPTIONS") {
            return new Response(null, {
                status: 204,
                headers: corsHeaders(),
            });
        }

        if (request.method !== "POST") {
            return json({ error: "Method not allowed" }, 405);
        }

        const url = new URL(request.url);
        // Path shape: /v1/models/{model}:generateContent
        const match = url.pathname.match(/^\/v1\/models\/([^:]+):generateContent$/);
        if (!match) {
            return json({ error: "Not found" }, 404);
        }
        const model = match[1];
        if (!ALLOWED_MODELS.has(model)) {
            return json({ error: `Model ${model} is not allowed` }, 400);
        }

        // ─── Auth ────────────────────────────────────────────────────────────
        const auth = request.headers.get("authorization") ?? "";
        const presented = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length).trim() : "";
        if (!env.APP_SHARED_SECRET || !timingSafeEqual(presented, env.APP_SHARED_SECRET)) {
            return json({ error: "Unauthorized" }, 401);
        }

        // ─── Rate limit (optional, only if KV bound) ─────────────────────────
        if (env.RATE_LIMIT) {
            const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
            const minute = Math.floor(Date.now() / 60_000);
            const key = `rl:${ip}:${minute}`;
            const existing = parseInt((await env.RATE_LIMIT.get(key)) ?? "0", 10) || 0;
            if (existing >= RATE_LIMIT_PER_MINUTE) {
                return json({ error: "Rate limit exceeded" }, 429);
            }
            // Fire-and-forget increment; expire after 90s so the key doesn't linger.
            await env.RATE_LIMIT.put(key, String(existing + 1), { expirationTtl: 90 });
        }

        // ─── Body size cap & parse ───────────────────────────────────────────
        const raw = await request.arrayBuffer();
        if (raw.byteLength > MAX_BODY_BYTES) {
            return json({ error: "Request body too large" }, 413);
        }
        let body: unknown;
        try {
            body = JSON.parse(new TextDecoder().decode(raw));
        } catch {
            return json({ error: "Invalid JSON" }, 400);
        }
        if (!isPlainObject(body)) {
            return json({ error: "Body must be a JSON object" }, 400);
        }

        // Minimal shape validation — fail fast on garbage.
        if (!("contents" in body) || !("generationConfig" in body)) {
            return json({ error: "Missing required fields: contents, generationConfig" }, 400);
        }

        // ─── Forward to Gemini ───────────────────────────────────────────────
        const upstreamURL =
            `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent` +
            `?key=${encodeURIComponent(env.GEMINI_API_KEY)}`;

        const upstream = await fetch(upstreamURL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });

        // Pass status + body through. We strip Google-specific headers and add CORS.
        const respBody = await upstream.arrayBuffer();
        return new Response(respBody, {
            status: upstream.status,
            headers: {
                "Content-Type": upstream.headers.get("content-type") ?? "application/json",
                ...corsHeaders(),
            },
        });
    },
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function json(payload: unknown, status: number): Response {
    return new Response(JSON.stringify(payload), {
        status,
        headers: { "Content-Type": "application/json", ...corsHeaders() },
    });
}

function corsHeaders(): Record<string, string> {
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
    };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Constant-time string comparison. Prevents timing attacks against the shared secret. */
function timingSafeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    let mismatch = 0;
    for (let i = 0; i < a.length; i++) {
        mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return mismatch === 0;
}
