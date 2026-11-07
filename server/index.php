<?php
require __DIR__ . '/app/bootstrap.php';
header('Location: ' . (current_admin() ? 'sms.php' : 'login.php'));
