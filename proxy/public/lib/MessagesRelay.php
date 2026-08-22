<?php
declare(strict_types=1);

/** Forwards one request to Anthropic and streams the answer back as it lands. */
final class MessagesRelay
{
    private const ANTHROPIC_VERSION = '2023-06-01';

    private int $status = 0;
    private string $contentType = 'application/json';

    public function __construct(
        private readonly ProxyConfig $config,
        private readonly Responder $responder,
    ) {
    }

    public function relay(string $body): void
    {
        // The validated body is forwarded byte for byte rather than re-encoded,
        // so parameters this proxy has never heard of keep working.
        $curl = curl_init($this->config->apiBase . '/v1/messages');
        curl_setopt_array($curl, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_HTTPHEADER     => [
                'content-type: application/json',
                // Set here, not copied from the caller: the wire format this
                // proxy was written against is not the caller's to choose.
                'anthropic-version: ' . self::ANTHROPIC_VERSION,
                'x-api-key: ' . $this->config->apiKey,
                'accept-encoding: identity',
            ],
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CONNECTTIMEOUT => 10,
            // No overall timeout: a long answer is not a stuck one.
            CURLOPT_TIMEOUT        => 0,
            CURLOPT_HEADERFUNCTION => $this->captureHeader(...),
            CURLOPT_WRITEFUNCTION  => $this->passThrough(...),
        ]);

        $ok    = curl_exec($curl);
        $errno = curl_errno($curl);
        // No curl_close(): it has done nothing since PHP 8.0 and is deprecated
        // in 8.5, where calling it prints a notice into the response body.

        // CURLE_ABORTED_BY_CALLBACK means the client hung up, which is normal.
        if ($ok === false && $errno !== CURLE_ABORTED_BY_CALLBACK) {
            throw new ProxyFault(
                502,
                'api_error',
                'The proxy could not reach the Claude API.',
                'upstream request failed, curl errno ' . $errno
            );
        }

        // An upstream that answered with headers and no body still deserves a
        // response rather than a blank one.
        $this->responder->begin();
    }

    private function captureHeader(\CurlHandle $curl, string $line): int
    {
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $line, $match) === 1) {
            $this->status = (int) $match[1];
        } elseif (stripos($line, 'content-type:') === 0) {
            $this->contentType = trim(substr($line, strlen('content-type:')));
        }

        if ($this->status > 0) {
            $this->responder->willReturn($this->status, $this->contentType);
        }

        return strlen($line);
    }

    private function passThrough(\CurlHandle $curl, string $chunk): int
    {
        // Returning anything other than the chunk length aborts the transfer,
        // which is how a cancelled turn stops costing money upstream.
        return $this->responder->write($chunk) ? strlen($chunk) : -1;
    }
}
