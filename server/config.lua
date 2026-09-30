-- Publish the default even when omitted from server.cfg so clients can only
-- read this setting. Owners opt in with: setr cortex_pause_replace_native 1
SetConvarReplicated('cortex_pause_replace_native',
    GetConvarInt('cortex_pause_replace_native', 0) == 1 and '1' or '0')
