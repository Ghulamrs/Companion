# Companion

A SwiftUI chat app for the Claude Messages API, targeting iOS 27 and
building in the Swift 6 language mode.

It ships with an **offline mock backend**, so it builds and runs in the
Simulator with no API key and no network. Wire in the real API when the UI
feels right.

## Run it now (no key)

```
open Companion.xcodeproj
```

Pick any iPhone simulator and press ⌘R. That's it.

Or from the terminal:

```
xcodebuild -project Companion.xcodeproj \
           -scheme Companion \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           build
```

Things to try in the mock:

| Type this        | What it proves                              |
| ---------------- | ------------------------------------------- |
| `hello`          | Streaming append + scroll-to-bottom         |
| `error`          | Error alert path and placeholder cleanup    |
| anything, then ■ | Cancelling a turn mid-stream                |

The nav subtitle always names the active backend, so you can never be confused
about which one you are hitting.

## Go live

Environment variables, set in the scheme, decide the backend. Nothing is
compiled into the binary.

**Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Arguments ▸ Environment Variables**

The scheme is deliberately **not shared**, so it is not in the repo and a key
pasted into it cannot be committed. The cost is that a fresh clone has no scheme
of its own — Xcode generates one on first open, without these variables. Add the
one you need by hand, then relaunch:

| Variable                   | Effect                                                        |
| -------------------------- | ------------------------------------------------------------- |
| `ANTHROPIC_API_KEY`        | Calls api.anthropic.com directly. **Dev only.**                |
| `CLAUDE_PROXY_URL`         | Routes through your backend. Ship this.                        |
| `CLAUDE_PROXY_TOKEN`       | How the app proves itself to *your* proxy. Not an Anthropic key. |
| `CLAUDE_PROXY_AUTH_HEADER` | Header the token rides in. Default `Authorization`.            |
| `CLAUDE_MODEL`             | Overrides the default `claude-sonnet-5`.                       |

`CLAUDE_PROXY_URL` wins if both are set.

With `CLAUDE_PROXY_TOKEN` set and no header override, the app sends
`Authorization: Bearer <token>`. Set `CLAUDE_PROXY_AUTH_HEADER` to send the raw
token under another name instead — `CF-Access-Client-Secret`, say. Leave the
token unset if your proxy authorizes callers some other way (mutual TLS, an
identity-aware gateway, a network boundary); the app will simply send no
credential rather than refuse to start.

Only `CLAUDE_PROXY_URL` and `ANTHROPIC_API_KEY` select a backend; the others are
modifiers. A modifier set without the thing it modifies used to be ignored in
silence — a token with no URL, a header name with no token. The app now says so
at launch, in a banner and on the Xcode console, so a misconfigured run looks
misconfigured instead of looking fine and talking to the wrong backend.

## Running on your own phone

Scheme environment variables only apply to launches Xcode performs. Tap the app's
icon on a device afterwards and they are gone, so the app drops to the mock.

For a build that works on a cold launch, tap the **key** button in the top left
and enter the key there. It goes into the Keychain on that device: never into the
project, never into the binary, never into this repository, not synced to iCloud,
and not carried onto another phone by a backup. The transport rebuilds as soon as
you save, so the subtitle changes without a relaunch.

The environment still wins. A key in the scheme overrides a stored one, so your
desk setup keeps working without clearing the device first — and the key screen
says so when that is happening.

Device checklist, in the order that wastes the least time:

- The deployment target is **iOS 27**, so the phone must run iOS 27 or later.
- Change `PRODUCT_BUNDLE_IDENTIFIER` off `com.example.` to something yours.
- Set a signing team. A free Apple ID works, but the build expires after 7 days.
- Enable Developer Mode on the phone: Settings ▸ Privacy & Security.

This is a development convenience, not a shipping design. It puts your key on one
phone you control. For anything another person installs, stand up the proxy and
keep the key server-side.

## Before you ship

A key bundled into an app is extractable from the binary, and whoever extracts
it makes requests billed to your account. Two safe options:

1. **Proxy.** Stand up an endpoint that accepts a Messages API request, attaches
   the `x-api-key` header server-side, and forwards to `https://api.anthropic.com`.
   Point `CLAUDE_PROXY_URL` at it. Roughly twenty lines of server code.
2. **App Attest.** Anthropic's `ClaudeForFoundationModels` Swift package issues
   each verified install a short-lived token, so the app ships no key and you run
   no backend. It requires iOS 27 and Xcode 27, both in beta, and a physical
   device — App Attest cannot run in the Simulator.

## Layout

```
Companion/
├─ CompanionApp.swift          @main
├─ Models/
│  └─ ChatMessage.swift         UI-facing message type
├─ Services/
│  ├─ ChatTransport.swift       protocol both backends satisfy
│  ├─ MockTransport.swift       offline canned replies
│  ├─ ClaudeClient.swift        live Messages API over URLSession
│  └─ AppEnvironment.swift      picks the backend at startup
├─ ViewModels/
│  └─ ChatModel.swift           @Observable, owns the transcript
└─ Views/
   └─ ChatView.swift            transcript, composer, bubbles
```

The views never touch networking. `ChatModel` holds an `any ChatTransport`, and
swapping backends is one branch in `AppEnvironment.makeTransport()`.

## Notes on the API

- Every request needs an `anthropic-version` header; this project sends `2023-06-01`.
- The Messages API is stateless, so the full conversation history goes out on
  every turn. That is why `ChatModel.send()` passes the whole `messages` array.
- Streaming responses are server-sent events; `ClaudeClient` reads
  `URLSession.bytes(for:)` line by line and keeps the `text` from each
  `content_block_delta`.

## Adjust before first run

- `PRODUCT_BUNDLE_IDENTIFIER` is `PQR.Companion`. Change it in target build
  settings to one of your own if you plan to run on a device.
