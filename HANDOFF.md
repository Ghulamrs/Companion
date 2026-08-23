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
├─ Tools/makeicon.swift                  draws the icon; edit this, not the PNG
└─ Companion/
   ├─ CompanionApp.swift                 @main struct CompanionApp
   ├─ Models/ChatMessage.swift
   ├─ Services/
   │  ├─ KeychainStore.swift             one value at rest, this device only
   │  ├─ DeviceConfiguration.swift       proxy address, proxy token, API key
   │  ├─ ChatTransport.swift             protocol both backends satisfy
   │  ├─ MockTransport.swift             offline canned replies
   │  ├─ ClaudeClient.swift              live Messages API over URLSession
   │  └─ AppEnvironment.swift            picks backend at launch
   ├─ ViewModels/ChatModel.swift         @Observable, @MainActor
   ├─ Views/
   │  ├─ ChatView.swift                  transcript, composer, bubbles
   │  └─ ConnectionView.swift            the only screen that takes a credential
   └─ Assets.xcassets/                   accent colour, and the app icon
```

**Status: verified.** The project was authored in a Linux container with no
Swift toolchain and no Xcode, and for a while had never been compiled. It has
now been built and run.

- Builds clean on Xcode 26.6, iPhone 17 simulator, zero warnings, in the
  Swift 6 language mode (`SWIFT_VERSION = 6.0`), which is complete data-race
  checking rather than warnings.
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

**Read the nav subtitle before running that table.** It has to say
`Mock · offline`, and on a simulator that has been used for proxy testing it
will not: the proxy address lives in the Keychain rather than the app bundle,
so rebuilding and reinstalling leaves it in place and the app comes up as
`Claude · via proxy` instead. The table then measures the
real backend — and `error` stops being a test, because it goes to Claude as a
message and is billed like any other.

Clearing it is the key icon in the nav bar, then the Remove buttons under
*Saved on this device*. `xcrun simctl erase` does it wholesale, along with
everything else that simulator remembers.

Note on testing cancel: the longest canned reply streams in about 3 seconds,
which is too fast to catch by hand or by tooling. Raise `MockTransport.chunkDelay`
to ~400 ms, test, then put it back.

## Design invariants — do not break these

1. **Views never touch networking.** `ChatModel` holds an `any ChatTransport`.
   Adding a backend means adding a conformance, not editing `ChatView`.
2. **No credential is ever compiled into the binary.** Configuration arrives
   either through scheme environment variables, read in `AppEnvironment` —
   `ANTHROPIC_API_KEY` (dev only), `CLAUDE_PROXY_URL` (wins over any key),
   `CLAUDE_PROXY_TOKEN`, `CLAUDE_PROXY_AUTH_HEADER`, `CLAUDE_MODEL` — or from
   the Keychain by way of invariant 3. Never move a credential into source, an
   xcconfig in the repo, or Info.plist.
3. **The device layer is what makes the app usable at all.** Scheme variables
   exist only when Xcode launches the app; tap the icon on the home screen and
   they are gone. `DeviceConfiguration` therefore stores the proxy address, the
   proxy token and (as a development shortcut) an API key in the Keychain, so a
   configured phone keeps working untethered. Precedence is environment first,
   device second — a scheme variable overrides the device rather than the other
   way round, and `ConnectionView` says so when it applies.

   The proxy fields are the shipping answer. The API key field is not: it puts a
   key on the phone to be spent directly, which is the arrangement the proxy
   exists to replace.
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

## The proxy — built, deployed, in service

`proxy/` in this repository, deployed to `/var/www/html/ai/` on the Morningwalk
box, reached at `https://idzeropoint.com/ai`. Its own README carries the detail;
what belongs here is that it exists, it is live, and the app has been verified
against it end to end — `POST /ai/v1/messages` returning 200 with the user agent
`Companion/1 CFNetwork/…`, streamed, on 2026-08-23.

Two properties of that server were hard-won and are easy to undo by accident,
both written up in `proxy/README.md`:

- Apache holds a stream unless `flushpackets=on` is set for the FCGI worker,
  which turns every turn into one lump delivered at the end.
- `ignore_user_abort(true)` — the counter-intuitive setting — is what lets a
  cancelled turn stop the spending rather than silently running to completion.

The Anthropic key lives only in `/var/www/secure/companion-config.php`, mode 640
root:apache, a PHP file returning an array. Never read it, never commit it, and
never `require` a config without capturing output first: a file that is not PHP
gets echoed straight into the response.

## Three backends, and how to tell which one you have

This cost an evening on 2026-08-22, so it is written down. `makeTransport()`
picks one of three, and **all three look like a working app**:

| Configuration                 | Backend                    | Subtitle                |
| ----------------------------- | -------------------------- | ----------------------- |
| proxy address (either source) | relay, key stays on server | `Claude · via proxy`    |
| API key, no proxy             | straight to api.anthropic  | `Claude · <model>`      |
| neither                       | `MockTransport`            | `Mock · offline`        |

The mock answers instantly, streams word by word, and never touches the network.
A convincing reply is therefore **not** evidence of a connection — and a real
reply is not evidence the proxy was used, because the direct path answers just
as well while spending a key off the phone.

The nav subtitle is the only thing in the interface that distinguishes them,
and it is left to do that alone. The title above it was the literal `Claude`
for a while, which the rename to Companion missed; over a mock conversation it
was simply untrue, and over a real one it said `Claude` twice. It now names the
app, taken from `CFBundleName` so a later rename cannot leave it behind again.
Read it before concluding anything. `CompanionApp.init()` also prints every
`configurationWarnings` entry to the console at launch, prefixed
`⚠️ Companion config:`, which is usually the fastest diagnosis available.

## Known rough edges

- `PRODUCT_BUNDLE_IDENTIFIER` is `PQR.Companion` and `DEVELOPMENT_TEAM` is set,
  so the app signs and runs on a physical device. Note that the Keychain service
  names are scoped to the bundle identifier: change it again and a device stops
  finding what it stored under the old one. An install under
  `com.example.Companion` may still be sitting on older Simulators.
- The target uses a file-system synchronized group, so new `.swift` files are
  picked up automatically. Do not add them to a build phase manually.
- The composer `TextField` does not take focus from synthetic taps in the
  Simulator, though the `Form` fields in `ConnectionView` do. Driving a send from
  tooling therefore does not work; type it by hand.

## Deliberately not done

- App Attest auth. It needs iOS 27 + Xcode 27 (both beta) and Anthropic's
  `ClaudeForFoundationModels` package, and cannot run in the Simulator.
  Revisit only if the beta target becomes acceptable.
- Persistence, multi-conversation, attachments, tool use.
