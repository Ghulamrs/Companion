<?php
declare(strict_types=1);

/**
 * Strips the PHP runtime of everything that would hold bytes back.
 *
 * This is its own class because it is a standing hazard rather than a step: any
 * one of these settings, left at its default, turns a live stream into a single
 * delivery at the end of the turn — which in the app looks like a freeze
 * followed by a wall of text.
 */
final class StreamingRuntime
{
    public static function prepare(): void
    {
        // Drop any buffer the runtime installed before a single byte is
        // written. php.ini here sets output_buffering = 4096 for FPM; the CLI
        // reports 0 for the same file because the CLI SAPI overrides it, so
        // reading the CLI value proves nothing about the server.
        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        ini_set('zlib.output_compression', '0');
        ini_set('implicit_flush', '1');
        ob_implicit_flush(true);

        // A PHP notice printed mid-response lands *inside* the SSE body and
        // garbles the stream the app is parsing. Diagnostics go to the log.
        ini_set('display_errors', '0');

        // A streamed turn can outlast any sane request timeout, and the work is
        // bounded by the upstream response rather than by anything here.
        set_time_limit(0);

        // Survive the client's disconnect rather than being killed by it.
        //
        // This reads backwards and is the opposite of what the goal suggests,
        // so it is worth stating plainly: the goal is that cancelling a turn in
        // the app also stops the spending upstream, and MessagesRelay achieves
        // that by aborting its curl transfer once Responder::write reports the
        // client has gone.
        //
        // With ignore_user_abort(false) that code never runs. PHP bails out
        // inside the very echo that failed, so connection_aborted() is still 0
        // the last time anything reads it, and the abandoned request leaves its
        // upstream connection open — measured on this server: the script stops
        // dead while the upstream streams happily to completion, billing for
        // every token of it.
        //
        // With true, PHP sets the flag and keeps running, the write callback
        // sees it on the next chunk, and the transfer is torn down deliberately.
        ignore_user_abort(true);

        header_remove('X-Powered-By');
    }
}
