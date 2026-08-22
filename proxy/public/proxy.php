<?php
declare(strict_types=1);

/**
 * Companion proxy — relays the Messages API without ever letting the key reach
 * the client.
 *
 * The app posts to <CLAUDE_PROXY_URL>/v1/messages carrying a bearer token that
 * is scoped to this proxy. The token is checked here, the real Anthropic key is
 * attached from a file outside the document root, and the SSE response is
 * streamed straight back.
 *
 * Two properties matter more than anything else in lib/:
 *
 *   1. The Anthropic key is never sent to the client, never logged, and never
 *      quoted in an error. A leaked proxy token costs a revocation; a leaked
 *      key costs a bill.
 *   2. Nothing is buffered. The app renders text as it arrives, so a proxy that
 *      accumulates the stream and releases it at the end would look like a hang
 *      for the whole turn.
 *
 * This file is only the wiring. One class per role, each in lib/:
 *
 *   StreamingRuntime  strips PHP of everything that would hold bytes back
 *   CompanionProxy    the request, from method check to relayed answer
 *   RequestGate       everything that can refuse it before spending anything
 *   ProxyConfig       the key, the tokens that may use it, and the limits
 *   MessagesRelay     the forward leg, streaming as it lands
 *   Responder         the reply, written once and in the right order
 *   ProxyFault        a refusal, with the status it should be reported as
 */

spl_autoload_register(static function (string $class): void {
    // No namespaces and no composer: this is a two-file deploy onto a shared
    // Apache host, and a dependency manager would be the largest thing in it.
    $file = __DIR__ . '/lib/' . $class . '.php';
    if (is_file($file)) {
        require $file;
    }
});

StreamingRuntime::prepare();

(new CompanionProxy(
    getenv('COMPANION_CONFIG') ?: '/var/www/secure/companion-config.php'
))->handle();
