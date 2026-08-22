<?php
/**
 * Temporary probe. Answers one question the local suite cannot: under Apache
 * with php-fpm, does PHP notice that the client hung up?
 *
 * proxy.php aborts its upstream curl transfer when connection_aborted() turns
 * non-zero, and that is what stops a cancelled turn from billing for tokens
 * nobody will read. PHP's built-in development server never sets the flag, so
 * the mechanism has to be checked on the real SAPI.
 *
 * Deploy beside proxy.php, then from anywhere:
 *
 *     curl -N https://host/companion/abort_probe.php   # ^C after a second
 *
 * Then read /tmp/companion-abort-probe.log on the server. A line reading
 * aborted=1 means the mechanism works. Delete this file afterwards: it is a
 * diagnostic, not part of the proxy.
 */
while (ob_get_level() > 0) {
    ob_end_clean();
}
ignore_user_abort(false);
header('content-type: text/event-stream');
header('cache-control: no-store');

$log = '/tmp/companion-abort-probe.log';
file_put_contents($log, "start " . date('c') . "\n");

for ($i = 0; $i < 25; $i++) {
    echo "data: tick{$i}\n\n";
    flush();
    file_put_contents($log, "i={$i} aborted=" . connection_aborted() . "\n", FILE_APPEND);
    if (connection_aborted() !== 0) {
        file_put_contents($log, "detected the hang-up at i={$i}\n", FILE_APPEND);
        break;
    }
    usleep(200000);
}
file_put_contents($log, "ended\n", FILE_APPEND);
