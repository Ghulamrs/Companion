# HANDOFF — Companion (iOS)

Context transferred from a chat session. Read this first; it is the only
record of decisions made so far.

## Working agreement

- The project lives at `/Users/g.r.akhtar/Documents/Claude/Companion`.
- Anything outside that path: ask first, at the moment it comes up.
  Do not batch permission requests or assume prior approval carries forward.

> Superseded, kept for context: this project was originally to be built in
> `Claude API/`, with `Companion/` as a scratch directory. That split is gone —
> `Companion/` is now the project itself, and `Claude API/` is empty.

## What exists

A SwiftUI chat app targeting **iOS 26**, originally delivered as a zip named
`ClaudeChat` and since renamed throughout to `Companion`.

```
Companion/
├─ Companion.xcodeproj/
│  ├─ project.pbxproj                    hand-written, objectVersion 77
│  └─ xcuserdata/…/xcschemes/Companion.xcscheme   not shared, not committed
└─ Companion/
   ├─ CompanionApp.swift                 @main struct CompanionApp
   ├─ Models/ChatMessage.swift
   ├─ Services/
   │  ├─ APIKeyStore.swift               key at rest in the Keychain
   │  ├─ ChatTransport.swift             protocol both backends satisfy
   │  ├─ MockTransport.swift             offline canned replies
   │  ├─ ClaudeClient.swift              live Messages API over URLSession
   │  └─ AppEnvironment.swift            picks backend at launch
   ├─ ViewModels/ChatModel.swift         @Observable, @MainActor
   ├─ Views/
   │  ├─ ChatView.swift                  transcript, composer, bubbles
   │  └─ APIKeyView.swift                the only screen that takes a credential
   └─ Assets.xcassets/
```

**Status: verified.** The project was authored in a Linux container with no
Swift toolchain and no Xcode, and for a while had never been compiled. It has
now been built and run.

- Builds clean on Xcode 26.6, iPhone 17 simulator, zero warnings.
- All three mock behaviours below were exercised in the Simulator and pass.

## Verify after any structural change

```bash
cd "/Users/g.r.akhtar/Documents/Claude/Companion"
xcodebuild -project Companion.xcodeproj -scheme Companion \
           -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Adjust the device name to whatever `xcrun simctl list devices available` shows.
Build outside the checkout (`-derivedDataPath` elsewhere) — codesign objects to
the provenance xattr on files under `~/Documents`.

Then boot it and confirm the mock path works end to end:

| Input            | Expected                                        |
| ---------------- | ----------------------------------------------- |
| `hello`          | Word-by-word streaming, auto-scroll to bottom   |
| `error`          | Alert fires, empty placeholder bubble removed   |
| send, then ■     | Turn cancels mid-stream, no orphaned bubble     |

Nav subtitle should read `Mock · offline`.

Note on testing cancel: the longest canned reply streams in about 3 seconds,
which is too fast to catch by hand or by tooling. Raise `MockTransport.chunkDelay`
to ~400 ms, test, then put it back.

## Design invariants — do not break these

1. **Views never touch networking.** `ChatModel` holds an `any ChatTransport`.
   Adding a backend means adding a conformance, not editing `ChatView`.
2. **No credential is ever compiled into the binary.** Configuration arrives
   through scheme environment variables, read in `AppEnvironment`:
   `ANTHROPIC_API_KEY` (dev only), `CLAUDE_PROXY_URL` (wins if both set),
   `CLAUDE_MODEL`. Never move a key into source, xcconfig-in-repo, or Info.plist.
3. **A stored key is a device convenience, not a shipping answer.** `APIKeyStore`
   puts a key in the Keychain so the app survives a cold launch on a phone
   without the key entering the build. It is still one key on one device, and it
   does not replace the proxy for anything anyone else installs. Precedence is
   environment first, Keychain second — so a scheme variable overrides the device
   rather than the other way round, and the key screen says when that applies.
4. **Mock stays first-class.** It is how the UI gets iterated without spending
   tokens. Do not let it rot as the real client evolves.

⚠️ **The scheme is deliberately not shared. Keep it that way.** It lives at
`Companion.xcodeproj/xcuserdata/<user>.xcuserdatad/xcschemes/`, which `.gitignore`
covers. It was shared once, and that was a trap: `.gitignore` covers `xcuserdata/`
but not `xcshareddata/`, so a key pasted into a shared scheme goes straight into
the repo — the exact outcome invariant 2 exists to prevent, and this repo is
public. Re-sharing the scheme re-arms that trap.

The cost is real and worth knowing: a fresh clone gets no scheme, so Xcode
generates one without the three variables declared. Whoever clones has to add
the one they need by hand. That is the trade — a small setup step for each
developer, in exchange for a key that cannot be committed by accident.

## API facts already established

- Endpoint `POST https://api.anthropic.com/v1/messages`.
- Header `anthropic-version: 2023-06-01` is required on every request.
- The Messages API is stateless — full conversation history goes out each turn.
  This is why `ChatModel.send()` passes the whole `messages` array.
- Streaming is SSE. `ClaudeClient` reads `URLSession.bytes(for:)` line by line
  and keeps `delta.text` from each `content_block_delta` event.
- Default model string in use: `claude-sonnet-5`.
- There is no official Anthropic Swift SDK for the Messages API. Official SDKs
  are Python, TypeScript, C#, Go, Java, PHP, Ruby. Do not go looking for one.

## Next task: the proxy

The app cannot ship with a key in it. Build a relay that:

- accepts a standard Messages API request body,
- attaches `x-api-key` server-side from its own environment,
- forwards to `https://api.anthropic.com/v1/messages`,
- streams the SSE response back without buffering it,
- authorizes its own callers somehow (the app can send a header; decide what).

Cloudflare Workers or a Vercel function are both fine. Roughly twenty lines.

**The app side of that last bullet is done.** `AppEnvironment` reads
`CLAUDE_PROXY_TOKEN` and sends it as `Authorization: Bearer <token>`, or under a
name of your choosing via `CLAUDE_PROXY_AUTH_HEADER` for gateways that want
their own (Cloudflare Access and `CF-Access-Client-Secret`, for instance). With
no token set the app sends no credential, so proxies that authorize by mutual
TLS or network boundary still work.

Both paths were verified against a local server that logged its request
headers: the default produced `Authorization: Bearer …`, and the override
produced the named header carrying the raw token with no `Authorization` sent
at all.

Note what the token is *not*: it is scoped to your proxy, never the Anthropic
key, which the proxy holds server-side and the app never sees. A leaked proxy
token costs a revocation; a leaked Anthropic key costs a bill.

Point `CLAUDE_PROXY_URL` at it and relaunch — `AppEnvironment` prefers the
proxy over a raw key automatically, so no app code changes.

`AppEnvironment.configurationWarnings` is the startup guard for all of this: it
reports orphaned modifiers, an unparseable proxy URL, a key that the proxy makes
irrelevant, a cleartext proxy URL that ATS will block, and a key that does not
look like a key. It is a pure property, so it can be checked without launching
anything. It never quotes a credential's value — naming the variable is enough
to fix the problem, and a warning that echoes a key just moves the key somewhere
new.

## Known rough edges

- `PRODUCT_BUNDLE_IDENTIFIER` is `com.example.Companion`. Change before
  running on a physical device.
- `SWIFT_VERSION = 5.0` for an easy first build. The code is annotated for
  Swift 6 (`@MainActor` on `ChatModel`, `Sendable` on transports) — bump it
  and fix fallout when convenient, not before the build is green.
- The target uses a file-system synchronized group, so new `.swift` files are
  picked up automatically. Do not add them to a build phase manually.
- `Assets.xcassets/AppIcon.appiconset` is empty, so the app shows a blank icon
  on the home screen.
- `ClaudeClient.send()` — the non-streaming path — is fully written and called
  by nothing. `ChatTransport` only requires `stream`. It has never run.
- The nav bar title is the hardcoded string "Claude", naming the assistant
  rather than the app. It was left alone by the rename on purpose.

## Deliberately not done

- App Attest auth. It needs iOS 27 + Xcode 27 (both beta) and Anthropic's
  `ClaudeForFoundationModels` package, and cannot run in the Simulator.
  Revisit only if the beta target becomes acceptable.
- Persistence, multi-conversation, attachments, tool use.
