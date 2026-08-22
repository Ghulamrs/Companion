<?php
declare(strict_types=1);

/**
 * One request, from method check to relayed answer.
 *
 * The whole shape of the thing is the body of handle(): refuse what should be
 * refused, then relay. Everything else in this directory is one of those two
 * verbs done properly.
 */
final class CompanionProxy
{
    public function __construct(
        private readonly string $configPath,
        private readonly Responder $responder = new Responder(),
    ) {
    }

    public function handle(): void
    {
        try {
            RequestGate::assertPost();

            $config = ProxyConfig::fromFile($this->configPath);
            $body   = (new RequestGate($config))->admit();

            (new MessagesRelay($config, $this->responder))->relay($body);
        } catch (ProxyFault $fault) {
            $this->responder->fail($fault);
        }
    }
}
