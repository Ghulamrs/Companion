<?php
declare(strict_types=1);

/**
 * Everything that can refuse a request before a byte is spent upstream.
 *
 * The limits are not paperwork. Whoever holds a proxy token can choose the
 * model and the token budget, so an allowlist and a cap are what stand between
 * a leaked token and an unbounded bill.
 */
final class RequestGate
{
    private const MAX_BODY_BYTES = 262144;   // 256 KB of history is plenty

    public function __construct(private readonly ProxyConfig $config)
    {
    }

    /**
     * Checked before the configuration is even read, so a stray GET gets an
     * honest 405 rather than a 500 about a config it was never going to use.
     */
    public static function assertPost(): void
    {
        if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
            header('allow: POST');
            throw new ProxyFault(405, 'invalid_request_error', 'This endpoint accepts POST only.');
        }
    }

    /** @return string the raw body, once it is known to be worth forwarding. */
    public function admit(): string
    {
        $this->authorize();
        $body = $this->readBody();
        $this->validate($body);

        return $body;
    }

    private function authorize(): void
    {
        // mod_rewrite re-exposes the header under a REDIRECT_ prefix, so both
        // names have to be read or the rewritten route arrives unauthenticated.
        $header = $_SERVER['HTTP_AUTHORIZATION']
            ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
            ?? '';

        $presented = preg_match('/^Bearer\s+(.+)$/i', trim($header), $match) === 1
            ? $match[1]
            : '';

        // Every configured token is compared, and each comparison is constant
        // time, so neither the number of tokens nor the point of mismatch is
        // observable from outside.
        $authorized = false;
        foreach ($this->config->proxyTokens as $token) {
            if (hash_equals($token, $presented)) {
                $authorized = true;
            }
        }

        if (!$authorized) {
            header('www-authenticate: Bearer');
            throw new ProxyFault(
                401,
                'authentication_error',
                'Invalid or missing proxy credentials.',
                'rejected a caller from ' . ($_SERVER['REMOTE_ADDR'] ?? 'unknown')
            );
        }
    }

    private function readBody(): string
    {
        // The declared length is checked first so an oversized body can be
        // refused without reading it, and again after, because the header is
        // the client's claim rather than a fact.
        if ((int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > self::MAX_BODY_BYTES) {
            throw new ProxyFault(413, 'invalid_request_error', 'Request body is too large.');
        }

        $raw = file_get_contents('php://input', false, null, 0, self::MAX_BODY_BYTES + 1);

        if ($raw === false) {
            throw new ProxyFault(400, 'invalid_request_error', 'Could not read the request body.');
        }
        if (strlen($raw) > self::MAX_BODY_BYTES) {
            throw new ProxyFault(413, 'invalid_request_error', 'Request body is too large.');
        }

        return $raw;
    }

    private function validate(string $raw): void
    {
        $payload = json_decode($raw, true);
        if (!is_array($payload)) {
            throw new ProxyFault(400, 'invalid_request_error', 'Request body is not valid JSON.');
        }

        $model = $payload['model'] ?? null;
        if (!is_string($model) || $model === '') {
            throw new ProxyFault(400, 'invalid_request_error', 'Request is missing "model".');
        }
        if ($this->config->allowedModels !== []
            && !in_array($model, $this->config->allowedModels, true)
        ) {
            throw new ProxyFault(
                400,
                'invalid_request_error',
                "Model \"{$model}\" is not allowed by this proxy."
            );
        }

        if (!is_array($payload['messages'] ?? null)) {
            throw new ProxyFault(400, 'invalid_request_error', 'Request is missing "messages".');
        }

        $requested = $payload['max_tokens'] ?? null;
        if (!is_int($requested) || $requested < 1) {
            throw new ProxyFault(
                400,
                'invalid_request_error',
                'Request is missing a valid "max_tokens".'
            );
        }
        if ($requested > $this->config->maxTokensCap) {
            // Refused rather than quietly clamped: a truncated answer with no
            // explanation is a worse outcome than a clear rejection.
            throw new ProxyFault(
                400,
                'invalid_request_error',
                "max_tokens exceeds this proxy's limit of {$this->config->maxTokensCap}."
            );
        }
    }
}
