<?php
// Shared bootstrap: config, database, session, CSRF, auth and JSON helpers.
declare(strict_types=1);

const APP_DIR = __DIR__;
const APP_VERSION = '1.0.0';

function config(?string $key = null) {
    static $cfg = null;
    if ($cfg === null) {
        $file = APP_DIR . '/config.php';
        if (!is_file($file)) {
            if (basename($_SERVER['SCRIPT_NAME'] ?? '') !== 'install.php') {
                header('Location: install.php');
                exit;
            }
            $cfg = [];
        } else {
            $cfg = require $file;
        }
        $cfg += [
            'app_name'       => 'SMS Gateway',
            'timezone'       => 'UTC',
            'require_https'  => true,
            'max_pending'    => 20,
            'daily_limit'    => 100,
            'max_message'    => 160,
            'country_code'   => '',
        ];
    }
    return $key === null ? $cfg : ($cfg[$key] ?? null);
}

function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $c = config();
        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $c['db_host'] ?? 'localhost', (int)($c['db_port'] ?? 3306), $c['db_name'] ?? '');
        $pdo = new PDO($dsn, $c['db_user'] ?? '', $c['db_pass'] ?? '', [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
        $pdo->exec("SET time_zone = '+00:00'");
    }
    return $pdo;
}

function is_https(): bool {
    return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || (($_SERVER['SERVER_PORT'] ?? '') === '443')
        || (strtolower($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
}

function e(?string $s): string {
    return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}

/** Format a UTC datetime from the database in the configured timezone. */
function local_time(?string $utc, string $format = 'd M Y, h:i A'): string {
    if (!$utc) return '';
    $d = new DateTime($utc, new DateTimeZone('UTC'));
    $d->setTimezone(new DateTimeZone((string)config('timezone')));
    return $d->format($format);
}

// ---------- Session / auth ----------
function start_session(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    session_name('smsgw');
    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'secure'   => is_https(),
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_start();
}

function csrf_token(): string {
    start_session();
    if (empty($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(32));
    return $_SESSION['csrf'];
}

function csrf_field(): string {
    return '<input type="hidden" name="csrf" value="' . e(csrf_token()) . '">';
}

function csrf_check(): void {
    if (!hash_equals(csrf_token(), (string)($_POST['csrf'] ?? ''))) {
        http_response_code(400);
        exit('Invalid form token. Go back, reload the page and try again.');
    }
}

function current_admin(): ?array {
    start_session();
    return isset($_SESSION['admin_id']) ? ['id' => (int)$_SESSION['admin_id'], 'username' => (string)$_SESSION['admin_user']] : null;
}

function require_admin(): array {
    $a = current_admin();
    if (!$a) {
        header('Location: login.php');
        exit;
    }
    return $a;
}

// ---------- JSON API ----------
function api_ok(array $data = []): void {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => true] + $data, JSON_UNESCAPED_UNICODE);
    exit;
}

function api_error(string $message, int $code = 400): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

function json_body(): array {
    $d = json_decode((string)file_get_contents('php://input'), true);
    return is_array($d) ? $d : [];
}

/** The device key from "Authorization: Bearer ..." or the X-Device-Key fallback (some hosts strip Authorization). */
function bearer_key(): string {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($h === '' && function_exists('getallheaders')) {
        foreach (getallheaders() as $k => $v) if (strcasecmp($k, 'Authorization') === 0) $h = (string)$v;
    }
    if (preg_match('/^Bearer\s+(\S+)$/', $h, $m)) return $m[1];
    return (string)($_SERVER['HTTP_X_DEVICE_KEY'] ?? '');
}

function new_key(): string {
    return rtrim(strtr(base64_encode(random_bytes(36)), '+/', '-_'), '=');
}

// ---------- Layout ----------
function page_header(string $title, ?array $admin = null): void {
    $app = e((string)config('app_name'));
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">';
    echo '<title>' . e($title) . ' · ' . $app . '</title><link rel="stylesheet" href="assets/style.css"></head><body>';
    echo '<header class="top"><a class="brand" href="sms.php">' . $app . '</a>';
    if ($admin) echo '<nav><span class="muted">' . e($admin['username']) . '</span> <a href="logout.php">Log out</a></nav>';
    echo '</header><main class="wrap">';
}

function page_footer(): void {
    echo '<footer class="muted">SMS Gateway v' . APP_VERSION . '</footer></main></body></html>';
}

date_default_timezone_set('UTC'); // database stores UTC; local_time() converts for display
