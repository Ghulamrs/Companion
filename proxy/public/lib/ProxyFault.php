<?php
declare(strict_types=1);

/**
 * A refusal, carrying the status and the Messages-API error type it should be
 * reported as.
 *
 * Refusals are thrown rather than returned so that validation reads as a list
 * of conditions rather than a ladder of early exits, and so there is exactly
 * one place that knows how to write an error to the wire.
 */
final class ProxyFault extends RuntimeException
{
    public function __construct(
        public readonly int $status,
        public readonly string $type,
        string $message,
        /** Detail for the server log only. Never sent to the client. */
        public readonly ?string $logNote = null,
    ) {
        parent::__construct($message);
    }
}
