<?php
declare(strict_types=1);

/**
 * Writes the response, and knows how to write exactly one thing at a time.
 *
 * The status line cannot be sent until the upstream's is known, but the body
 * must not wait for anything. Holding both facts in one place is what keeps the
 * streaming path from emitting headers twice, or too early.
 */
final class Responder
{
    private bool $started = false;

    public function __construct(
        private int $status = 502,
        private string $contentType = 'application/json',
    ) {
    }

    public function willReturn(int $status, string $contentType): void
    {
        $this->status = $status;
        $this->contentType = $contentType;
    }

    public function begin(): void
    {
        if ($this->started || headers_sent()) {
            return;
        }
        $this->started = true;
        http_response_code($this->status);
        header('content-type: ' . $this->contentType);
        header('cache-control: no-store');
        // Understood by nginx and by several CDNs; harmless where it is not.
        header('x-accel-buffering: no');
    }

    /** @return bool false once the client has hung up. */
    public function write(string $chunk): bool
    {
        $this->begin();
        echo $chunk;
        flush();
        return connection_aborted() === 0;
    }

    /**
     * Answers in the same shape the Messages API uses for its own failures, so
     * the client needs exactly one error path. `ClaudeClient` decodes this.
     */
    public function fail(ProxyFault $fault): void
    {
        if ($fault->logNote !== null) {
            error_log('companion-proxy: ' . $fault->logNote);
        }

        // Mid-stream there is no envelope left to send: the status line went out
        // long ago. The client sees a short stream, which is the truth.
        if ($this->started || headers_sent()) {
            return;
        }

        $this->willReturn($fault->status, 'application/json');
        $this->begin();
        echo json_encode(
            ['error' => ['type' => $fault->type, 'message' => $fault->getMessage()]],
            JSON_UNESCAPED_SLASHES
        );
    }
}
