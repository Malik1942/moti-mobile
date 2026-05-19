import Foundation

// MARK: - Secrets stub
//
// This file is COMMITTED to git so CI builds (e.g. Xcode Cloud) compile
// cleanly — without it, the Xcode project references a missing source file.
// The committed version contains ONLY nil placeholders.
//
// Local development:
//   1. Edit this file locally with your dev values (DO NOT commit those edits).
//   2. Run once, per clone:
//        git update-index --skip-worktree Moti/Secrets.swift
//      Git will then treat your local edits as if the file were unchanged.
//      Reverse with:
//        git update-index --no-skip-worktree Moti/Secrets.swift
//
// Production / distribution:
//   - Leave every value nil. The Smart Capture API key lives in the iOS
//     Keychain via Settings → Smart Capture API → Save.
//   - For proxy mode, set proxyBaseURL + proxySharedSecret here only if you
//     intend to ship them embedded in the binary (the shared secret will be
//     extractable; the underlying Gemini key never leaves your Worker).

enum DevSecrets {

    // ─── Direct mode (development only) ──────────────────────────────────────
    //
    // Optional Gemini API key. If set, the app talks to Gemini directly.
    // Unsafe to ship: any user who installs the app can extract this string
    // from the binary. Use proxy mode (below) for distribution.
    static let geminiAPIKey: String? = nil

    // ─── Proxy mode (recommended for distribution) ───────────────────────────
    //
    // When BOTH of these are set, Smart Capture routes through your MotiProxy
    // Cloudflare Worker instead of calling Gemini directly. Your real Gemini
    // key lives only on the Worker. The shared secret authenticates this app
    // to your Worker — leaking it grants quota-limited proxy access, not
    // access to your Gemini key.
    //
    // See MotiProxy/README.md for the deploy walkthrough.
    static let proxyBaseURL:      String? = nil   // e.g. "https://moti-proxy.<your-cf-subdomain>.workers.dev"
    static let proxySharedSecret: String? = nil   // the same value passed to `wrangler secret put APP_SHARED_SECRET`
}
