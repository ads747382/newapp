<?php
declare(strict_types=1);
require __DIR__ . '/app/bootstrap.php';
start_session();
if (current_admin()) { header('Location: sms.php'); exit; }

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $fails = (int)($_SESSION['login_fails'] ?? 0);
    $lockedUntil = (int)($_SESSION['login_locked_until'] ?? 0);
    if ($lockedUntil > time()) {
        $error = 'Too many attempts. Try again in ' . ($lockedUntil - time()) . ' seconds.';
    } else {
        $u = trim((string)($_POST['username'] ?? ''));
        $p = (string)($_POST['password'] ?? '');
        $st = db()->prepare('SELECT id, username, password_hash FROM sms_admins WHERE username=? LIMIT 1');
        $st->execute([$u]);
        $row = $st->fetch();
        if ($row && password_verify($p, $row['password_hash'])) {
            session_regenerate_id(true);
            $_SESSION = ['admin_id' => (int)$row['id'], 'admin_user' => $row['username']];
            if (password_needs_rehash($row['password_hash'], PASSWORD_DEFAULT)) {
                db()->prepare('UPDATE sms_admins SET password_hash=? WHERE id=?')->execute([password_hash($p, PASSWORD_DEFAULT), $row['id']]);
            }
            db()->prepare('UPDATE sms_admins SET last_login_at=UTC_TIMESTAMP() WHERE id=?')->execute([$row['id']]);
            header('Location: sms.php');
            exit;
        }
        usleep(600000);
        $fails++;
        $_SESSION['login_fails'] = $fails;
        if ($fails >= 5) { $_SESSION['login_locked_until'] = time() + 300; $_SESSION['login_fails'] = 0; }
        $error = 'Wrong username or password.';
    }
}

page_header('Log in'); ?>
<section class="card narrow">
  <h1>Log in</h1>
  <?php if ($error): ?><p class="alert"><?=e($error)?></p><?php endif; ?>
  <form method="post">
    <?=csrf_field()?>
    <label>Username<input name="username" required autocomplete="username" autofocus></label>
    <label>Password<input type="password" name="password" required autocomplete="current-password"></label>
    <button type="submit">Log in</button>
  </form>
</section>
<?php page_footer();
