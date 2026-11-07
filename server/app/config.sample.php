<?php
// Copy this file to config.php (same folder) and fill in your values,
// or let install.php create it for you.
return [
    // MySQL / MariaDB (cPanel -> MySQL Databases)
    'db_host' => 'localhost',
    'db_port' => 3306,
    'db_name' => 'your_database',
    'db_user' => 'your_db_user',
    'db_pass' => 'your_db_password',

    'app_name'      => 'SMS Gateway',
    'timezone'      => 'Asia/Karachi',   // used only for displaying times
    'require_https' => true,             // the Android app only talks to HTTPS servers
    'country_code'  => '92',             // turns local numbers like 03001234567 into +923001234567 ('' to disable)

    // Safety limits per device (personal SIMs get blocked for bulk sending)
    'max_pending' => 20,    // messages waiting in the queue at once
    'daily_limit' => 100,   // messages per rolling 24 hours
    'max_message' => 160,   // characters; the app sends one SMS segment only
];
