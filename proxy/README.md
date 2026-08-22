# The proxy

The app cannot ship with an Anthropic key in it: a key inside a binary is
extractable, and whoever extracts it bills your account. This is the relay that
holds the key instead — the app authenticates to *this*, and this authenticates
to Anthropic.

```
Companion  ──Authorization: Bearer <proxy token>──▶  /ai/v1/messages
                                                          │  x-api-key
                                                          ▼
                                                  api.anthropic.com
```

A leaked proxy token costs you a revocation. A leaked API key costs you a bill.
That asymmetry is the whole point.

## What it is

One PHP file, deployed to Apache on the existing `idzeropoint.com` box. It
lives in `/var/www/html/ai/`, a directory of its own — the Morningwalk
endpoints in the document root beside it are never touched.

| File                          | Role                                          |
| ----------------------------- | --------------------------------------------- |
| `public/proxy.php`            | Wiring only: autoload, prepare, handle        |
| `public/.htaccess`            | Maps `/ai/v1/messages` onto it                |
| `public/lib/StreamingRuntime` | Strips PHP of everything that holds bytes back |
| `public/lib/CompanionProxy`   | The request, method check to relayed answer   |
| `public/lib/RequestGate`      | Everything that can refuse it before spending |
| `public/lib/ProxyConfig`      | The key, the tokens, and the limits           |
| `public/lib/MessagesRelay`    | The forward leg, streaming as it lands        |
| `public/lib/Responder`        | The reply, written once and in the right order |
| `public/lib/ProxyFault`       | A refusal, with the status it reports as      |
| `apache/companion-ai.conf`    | Flushing, scoped to this directory alone      |
| `config.sample.php`           | Template for the server-side config. Never filled in here |
| `deploy.sh`                   | rsync + ownership + SELinux labels            |
| `tests/`                      | Full suite, no API key, no tokens spent       |

One class per role, one role per file, no namespaces and no composer: this is a
small deploy onto a shared Apache host, and a dependency manager would be the
largest thing in it. `lib/` carries its own `.htaccess` denying access — the
files emit nothing when fetched, but a directory of source under the document
root is a standing invitation.

**The route needs one Apache file.** The `.htaccess` alone is enough to *reach*
the proxy — both vhosts already grant `AllowOverride All` — but not to stream
from it. `mod_proxy_fcgi` defaults to `flushpackets=off`, so Apache holds PHP's
output until roughly 8 KB or the end of the request, which for SSE is the whole
turn. `apache/companion-ai.conf` fixes that through a second worker name
pointing at the same php-fpm socket, so the setting applies here and nowhere
else on the server.

## Deploy

```bash
./deploy.sh
```

Then create the config **once**, on the server, outside the document root:

```bash
ssh morningwalk
openssl rand -hex 32                     # this is your proxy token — keep a copy
sudoedit /var/www/secure/companion-config.php   # paste config.sample.php, fill it in
sudo chown root:apache /var/www/secure/companion-config.php
sudo chmod 640 /var/www/secure/companion-config.php
```

`640 root:apache` matches `config.php` beside it: Apache can read it, the web
cannot, and no rewrite mistake can ever serve it as text.

## Point the app at it

In the Xcode scheme (Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Environment
Variables):

```
CLAUDE_PROXY_URL    https://idzeropoint.com/ai
CLAUDE_PROXY_TOKEN  <the token you generated>
```

Leave `CLAUDE_PROXY_AUTH_HEADER` unset — this proxy wants the default
`Authorization: Bearer`. Clear `ANTHROPIC_API_KEY` while you are in there; the
proxy wins over it anyway, and `AppEnvironment.configurationWarnings` will say
so at launch rather than leaving you guessing which backend you reached. The nav
subtitle reads `Claude · via proxy` when it is live.

## Test

```bash
python3 proxy/tests/test_proxy.py
```

Starts a stub upstream and a PHP server and drives the proxy over real HTTP. No
key, no network, no spend. The check worth understanding is the timing one: a
proxy that buffers passes every other assertion in the file and still makes the
app look frozen for an entire turn, so the suite asserts that bytes arrive
*spread over time*, not merely that they all arrive.

One check cannot run locally. PHP's built-in server never sets
`connection_aborted()` — it kills the script instead — so the suite skips the
cancellation check rather than pretending. Prove that one on the real SAPI with
`tests/abort_probe.php`; it is a diagnostic, deployed temporarily and deleted.

## What it refuses

- Anything but POST.
- A missing or wrong bearer token, compared in constant time against every
  configured token so neither timing nor count leaks.
- A model outside the allowlist, and a `max_tokens` above the cap. Both exist
  because a token holder could otherwise pick the priciest model on offer and
  ask it for everything it has.
- Bodies over 256 KB.

Refusals use the Messages API's own `{"error":{"type","message"}}` envelope, so
`ClaudeClient` needs exactly one error path for its own failures and Anthropic's.

## Two things it does on purpose

**It never buffers.** Every output buffer is torn down before a byte is written,
compression is refused, and `display_errors` is off so a stray PHP notice can
never land inside the SSE body and garble the stream.

**It hangs up when you do.** When the app's stop button cancels a turn, the
write callback returns `-1`, which aborts the upstream transfer. Cancelling
stops the spending rather than just hiding the result.

## Rotating the token

`proxy_tokens` is a list so this needs no downtime: add the new token, move the
installs across, delete the old one.
