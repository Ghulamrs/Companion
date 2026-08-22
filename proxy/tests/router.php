<?php
// Test-only. PHP's built-in server has no .htaccess, so this reproduces the one
// rewrite Apache performs, letting the suite exercise the real /v1/messages
// path rather than the script name behind it.
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

if ($path === '/v1/messages') {
    require __DIR__ . '/../public/proxy.php';
    return true;
}

return false;
