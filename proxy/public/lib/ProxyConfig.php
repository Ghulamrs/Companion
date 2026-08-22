<?php
declare(strict_types=1);

/**
 * The server-side configuration: the key, the tokens that may use it, and the
 * limits imposed on whoever holds one.
 *
 * Validating in the constructor means the rest of the code can read a property
 * without asking whether it is present or of the right type. Every failure here
 * reports the same bland message outwards and the specific cause to the log: a
 * misconfigured proxy should not describe its own internals to the internet.
 */
final class ProxyConfig
{
    private const GENERIC = 'The proxy is not configured.';

    /** @param list<string> $proxyTokens @param list<string> $allowedModels */
    private function __construct(
        public readonly string $apiKey,
        public readonly array $proxyTokens,
        public readonly array $allowedModels,
        public readonly int $maxTokensCap,
        public readonly string $apiBase,
    ) {
    }

    public static function fromFile(string $path): self
    {
        if (!is_readable($path)) {
            throw new ProxyFault(500, 'api_error', self::GENERIC, "config not readable at {$path}");
        }

        // Captured, because require() on a file that is not PHP echoes the
        // file. An env-style KEY=value config would otherwise be printed into
        // the response body — handing the caller the very secrets this file
        // exists to keep from them. Observed for real, not imagined.
        ob_start();
        $raw   = require $path;
        $stray = ob_get_clean();

        if ($stray !== '') {
            throw new ProxyFault(
                500,
                'api_error',
                self::GENERIC,
                'config produced output instead of returning an array; it is probably not a PHP file'
            );
        }

        if (!is_array($raw)) {
            throw new ProxyFault(500, 'api_error', self::GENERIC, 'config did not return an array');
        }

        $apiKey = $raw['api_key'] ?? null;
        if (!is_string($apiKey) || $apiKey === '') {
            throw new ProxyFault(500, 'api_error', self::GENERIC, 'config is missing api_key');
        }

        $tokens = array_values(array_filter(
            is_array($raw['proxy_tokens'] ?? null) ? $raw['proxy_tokens'] : [],
            static fn ($token): bool => is_string($token) && $token !== ''
        ));
        if ($tokens === []) {
            throw new ProxyFault(500, 'api_error', self::GENERIC, 'config is missing proxy_tokens');
        }

        $models = array_values(array_filter(
            is_array($raw['allowed_models'] ?? null) ? $raw['allowed_models'] : [],
            'is_string'
        ));

        return new self(
            apiKey: $apiKey,
            proxyTokens: $tokens,
            allowedModels: $models,
            maxTokensCap: (int) ($raw['max_tokens_cap'] ?? 4096),
            apiBase: rtrim((string) ($raw['api_base'] ?? 'https://api.anthropic.com'), '/'),
        );
    }
}
