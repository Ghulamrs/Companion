<?php

/**
 * Copy to /var/www/secure/companion-config.php on the server and fill in.
 *
 *   sudo install -o root -g apache -m 640 /dev/stdin \
 *        /var/www/secure/companion-config.php
 *
 * It lives outside the document root and is mode 640 root:apache, matching
 * config.php beside it: Apache can read it, the web cannot, and a misplaced
 * rewrite can never serve it as text.
 *
 * This file is the reason the app ships without a key. Never commit a filled-in
 * copy — this repository is public.
 */

return [
    // The real Anthropic key. Never leaves the server.
    'api_key' => 'sk-ant-REPLACE-ME',

    // What the app must present as `Authorization: Bearer <token>`.
    // Generate with: openssl rand -hex 32
    //
    // It is a list so a token can be rotated without downtime: add the new one,
    // move the installs across, then delete the old one.
    'proxy_tokens' => [
        'REPLACE-ME',
    ],

    // Anything not named here is refused. Whoever holds a token could otherwise
    // choose the most expensive model on offer.
    'allowed_models' => [
        'claude-sonnet-5',
        'claude-opus-5',
        'claude-haiku-4-5-20251001',
    ],

    // Ceiling on max_tokens per request. The app asks for 1024.
    'max_tokens_cap' => 4096,

    // Overridden only by the test harness, which points it at a local stub.
    'api_base' => 'https://api.anthropic.com',
];
