<?php
// Admin dashboard: devices, queue messages, live report.
declare(strict_types=1);
require __DIR__ . '/app/bootstrap.php';
$admin = require_admin();

const STATUSES = ['pending' => 'Pending', 'claimed' => 'Sending', 'sent' => 'Sent', 'failed' => 'Failed', 'cancelled' => 'Cancelled'];
const MAX_LINES = 50;

/** Normalize to +<country><number>. "0300 1234567" becomes +923001234567 when country_code is 92. */
function normalize_number(string $raw): string {
    $n = preg_replace('/[^0-9+]/', '', $raw);
    $cc = preg_replace('/\D/', '', (string)(config('country_code') ?? ''));
    if (str_starts_with($n, '00')) $n = '+' . substr($n, 2);
    elseif ($n !== '' && $n[0] !== '+') {
        if ($cc !== '' && str_starts_with($n, '0')) $n = '+' . $cc . substr($n, 1);
        elseif ($cc !== '' && str_starts_with($n, $cc)) $n = '+' . $n;
    }
    return preg_match('/^\+[1-9]\d{7,14}$/', $n) ? $n : '';
}

$statusFilter = isset(STATUSES[$_GET['status'] ?? '']) ? (string)$_GET['status'] : '';
$deviceFilter = (int)($_GET['device'] ?? 0);
$where = ['1=1']; $args = [];
if ($statusFilter) { $where[] = 'j.status=?'; $args[] = $statusFilter; }
if ($deviceFilter) { $where[] = 'j.device_id=?'; $args[] = $deviceFilter; }
$whereSql = implode(' AND ', $where);

// ---------- CSV export ----------
if (($_GET['export'] ?? '') === 'csv') {
    $st = db()->prepare("SELECT j.id, d.device_name, j.recipient, j.message, j.status, j.attempts, j.created_at, j.sent_at, j.error_message FROM sms_jobs j JOIN sms_devices d ON d.id=j.device_id WHERE $whereSql ORDER BY j.id DESC");
    $st->execute($args);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="sms-report-' . gmdate('Y-m-d') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['ID', 'Phone', 'Recipient', 'Message', 'Status', 'Attempts', 'Queued', 'Sent', 'Error']);
    while ($r = $st->fetch()) {
        fputcsv($out, [$r['id'], $r['device_name'], $r['recipient'], $r['message'], STATUSES[$r['status']] ?? $r['status'], $r['attempts'], local_time($r['created_at']), local_time($r['sent_at']), $r['error_message']]);
    }
    exit;
}

// ---------- Actions ----------
$notice = ''; $newKey = ''; $skipped = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string)($_POST['action'] ?? '');
    $deviceId = (int)($_POST['device_id'] ?? 0);

    if ($action === 'add_device') {
        $name = trim((string)($_POST['device_name'] ?? ''));
        if ($name === '' || mb_strlen($name) > 120) {
            $notice = 'Enter a device name (1–120 characters).';
        } else {
            $newKey = new_key();
            db()->prepare('INSERT INTO sms_devices(device_name, api_key_hash, created_at) VALUES(?,?,UTC_TIMESTAMP())')
                ->execute([$name, hash('sha256', $newKey)]);
            $notice = 'Device added. Copy the key now — it is shown only once.';
        }
    } elseif ($action === 'toggle_device') {
        db()->prepare('UPDATE sms_devices SET enabled=IF(enabled=1,0,1) WHERE id=?')->execute([$deviceId]);
        $notice = 'Device updated.';
    } elseif ($action === 'delete_device') {
        db()->prepare('DELETE FROM sms_devices WHERE id=?')->execute([$deviceId]);
        $notice = 'Device and its messages deleted.';
    } elseif ($action === 'queue') {
        $message = trim(str_replace("\r", '', (string)($_POST['message'] ?? '')));
        $lines = array_values(array_filter(array_map('trim', explode("\n", str_replace("\r", '', (string)($_POST['recipients'] ?? '')))), 'strlen'));
        $dev = db()->prepare('SELECT id FROM sms_devices WHERE id=? AND enabled=1');
        $dev->execute([$deviceId]);
        $pending = db()->prepare("SELECT COUNT(*) FROM sms_jobs WHERE device_id=? AND status IN ('pending','claimed')");
        $pending->execute([$deviceId]);
        $room = (int)config('max_pending') - (int)$pending->fetchColumn();

        if (!isset($_POST['consent_confirmed'])) $notice = 'Please confirm the recipients agreed to receive messages.';
        elseif (!$dev->fetch()) $notice = 'Select an enabled device.';
        elseif ($message === '' || mb_strlen($message) > (int)config('max_message')) $notice = 'Message must be 1–' . (int)config('max_message') . ' characters.';
        elseif (!$lines) $notice = 'Enter at least one number.';
        elseif (count($lines) > MAX_LINES) $notice = 'Maximum ' . MAX_LINES . ' numbers at once.';
        elseif ($room <= 0) $notice = 'Queue is full (' . (int)config('max_pending') . ' waiting). Let the phone send them first.';
        else {
            $ins = db()->prepare("INSERT INTO sms_jobs(device_id, recipient, message, consent_confirmed, status, created_by, created_at) VALUES(?,?,?,1,'pending',?,UTC_TIMESTAMP())");
            $seen = []; $ok = 0;
            foreach ($lines as $line) {
                $n = normalize_number($line);
                if ($n === '') { $skipped[] = "$line — invalid number"; continue; }
                if (isset($seen[$n])) { $skipped[] = "$line — duplicate"; continue; }
                if ($ok >= $room) { $skipped[] = "$line — queue full"; continue; }
                $seen[$n] = true;
                $ins->execute([$deviceId, $n, $message, $admin['id']]);
                $ok++;
            }
            $notice = "$ok message(s) queued." . ($skipped ? ' ' . count($skipped) . ' skipped (see below).' : '');
        }
    } elseif ($action === 'retry_failed') {
        $n = db()->exec("UPDATE sms_jobs SET status='pending', attempts=0, claimed_at=NULL, error_message=NULL WHERE status='failed'");
        $notice = "$n failed message(s) queued again.";
    } elseif ($action === 'cancel_pending') {
        $n = db()->exec("UPDATE sms_jobs SET status='cancelled' WHERE status='pending'");
        $notice = "$n pending message(s) cancelled.";
    }
}

// ---------- Data ----------
$devices = db()->query("SELECT d.*, TIMESTAMPDIFF(SECOND, d.last_seen_at, UTC_TIMESTAMP()) seen_ago,
    (SELECT COUNT(*) FROM sms_jobs j WHERE j.device_id=d.id AND j.sent_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY) sent_24h
    FROM sms_devices d ORDER BY d.id DESC")->fetchAll();
$counts = array_fill_keys(array_keys(STATUSES), 0);
foreach (db()->query('SELECT status, COUNT(*) c FROM sms_jobs GROUP BY status')->fetchAll() as $r) $counts[$r['status']] = (int)$r['c'];
$total = array_sum($counts);

$per = 50;
$page = max(1, (int)($_GET['page'] ?? 1));
$cnt = db()->prepare("SELECT COUNT(*) FROM sms_jobs j WHERE $whereSql");
$cnt->execute($args);
$pages = max(1, (int)ceil((int)$cnt->fetchColumn() / $per));
$js = db()->prepare("SELECT j.*, d.device_name FROM sms_jobs j JOIN sms_devices d ON d.id=j.device_id WHERE $whereSql ORDER BY j.id DESC LIMIT $per OFFSET " . (($page - 1) * $per));
$js->execute($args);
$jobs = $js->fetchAll();

$link = function (array $over) use ($statusFilter, $deviceFilter): string {
    $p = array_filter(array_merge(['status' => $statusFilter, 'device' => $deviceFilter ?: ''], $over), fn($x) => $x !== '' && $x !== null);
    return 'sms.php' . ($p ? '?' . http_build_query($p) : '');
};

// ---------- Live part (refreshed every 15 s) ----------
ob_start(); ?>
<div class="stats">
  <a class="stat" href="<?=e($link(['status' => '']))?>"><b><?=$total?></b><span>Total</span></a>
  <?php foreach (STATUSES as $k => $label): ?><a class="stat s-<?=$k?>" href="<?=e($link(['status' => $k]))?>"><b><?=$counts[$k]?></b><span><?=$label?></span></a><?php endforeach; ?>
</div>

<section class="card">
  <h2>Phones</h2>
  <div class="scroll"><table>
    <tr><th>Name</th><th>Status</th><th>Sent (24h)</th><th>Last seen</th><th></th></tr>
    <?php foreach ($devices as $d): $online = $d['seen_ago'] !== null && (int)$d['seen_ago'] < 90; ?>
    <tr>
      <td><b><?=e($d['device_name'])?></b></td>
      <td><?php if (!(int)$d['enabled']): ?><span class="tag t-failed">Disabled</span><?php else: ?><span class="tag <?=$online ? 't-sent' : 't-cancelled'?>"><?=$online ? 'Online' : 'Offline'?></span><?php endif; ?></td>
      <td><?=(int)$d['sent_24h']?> / <?=(int)config('daily_limit')?></td>
      <td><?=e($d['last_seen_at'] ? local_time($d['last_seen_at']) : 'Never')?></td>
      <td class="actions">
        <form method="post"><?=csrf_field()?><input type="hidden" name="action" value="toggle_device"><input type="hidden" name="device_id" value="<?=$d['id']?>"><button class="btn-sm btn-ghost"><?=(int)$d['enabled'] ? 'Disable' : 'Enable'?></button></form>
        <form method="post" onsubmit="return confirm('Delete this device and all its messages?')"><?=csrf_field()?><input type="hidden" name="action" value="delete_device"><input type="hidden" name="device_id" value="<?=$d['id']?>"><button class="btn-sm btn-danger">Delete</button></form>
      </td>
    </tr>
    <?php endforeach; if (!$devices): ?><tr><td colspan="5" class="muted">No phones yet. Add one below.</td></tr><?php endif; ?>
  </table></div>
</section>

<section class="card">
  <div class="head">
    <h2>Messages<?=$statusFilter ? ' · ' . STATUSES[$statusFilter] : ''?></h2>
    <div class="actions">
      <a class="btn-sm btn-ghost" href="<?=e($link(['export' => 'csv']))?>">Export CSV</a>
      <form method="post"><?=csrf_field()?><input type="hidden" name="action" value="retry_failed"><button class="btn-sm btn-ghost">Retry failed</button></form>
      <form method="post" onsubmit="return confirm('Cancel all pending messages?')"><?=csrf_field()?><input type="hidden" name="action" value="cancel_pending"><button class="btn-sm btn-danger">Cancel pending</button></form>
    </div>
  </div>
  <div class="scroll"><table>
    <tr><th>#</th><th>Phone</th><th>Recipient</th><th>Message</th><th>Status</th><th>Queued</th><th>Sent</th><th>Error</th></tr>
    <?php foreach ($jobs as $j): ?>
    <tr>
      <td><?=$j['id']?></td><td><?=e($j['device_name'])?></td><td><?=e($j['recipient'])?></td>
      <td class="wrapcell"><?=e($j['message'])?></td>
      <td><span class="tag t-<?=e($j['status'])?>"><?=e(STATUSES[$j['status']] ?? $j['status'])?></span></td>
      <td><?=e(local_time($j['created_at']))?></td><td><?=e(local_time($j['sent_at']))?></td>
      <td class="wrapcell err"><?=e($j['error_message'])?></td>
    </tr>
    <?php endforeach; if (!$jobs): ?><tr><td colspan="8" class="muted">No messages.</td></tr><?php endif; ?>
  </table></div>
  <?php if ($pages > 1): ?><p class="pager"><?php for ($p = 1; $p <= $pages; $p++): ?><a class="<?=$p === $page ? 'on' : ''?>" href="<?=e($link(['page' => $p]))?>"><?=$p?></a><?php endfor; ?></p><?php endif; ?>
</section>
<?php
$live = ob_get_clean();
if (($_GET['partial'] ?? '') === '1') { header('Content-Type: text/html; charset=utf-8'); echo $live; exit; }

page_header('Dashboard', $admin);
if ($notice): ?><p class="notice"><?=e($notice)?></p><?php endif; ?>
<?php if ($skipped): ?><div class="card err"><b>Skipped:</b><br><?=implode('<br>', array_map('e', $skipped))?></div><?php endif; ?>
<?php if ($newKey): ?>
<section class="card keybox">
  <h2>Device key — copy it now</h2>
  <code class="key"><?=e($newKey)?></code>
  <p class="muted">Shown only once. In the Android app enter this key and the server URL <code><?=e((is_https() ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'your-site.com') . rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/'), '/') . '/')?></code></p>
</section>
<?php endif; ?>

<div id="live"><?=$live?></div>

<div class="grid">
  <section class="card">
    <h2>Send SMS</h2>
    <form method="post">
      <?=csrf_field()?><input type="hidden" name="action" value="queue">
      <label>Phone (sends from its SIM)
        <select name="device_id" required><?php foreach ($devices as $d): if (!(int)$d['enabled']) continue; ?><option value="<?=$d['id']?>"><?=e($d['device_name'])?></option><?php endforeach; ?></select>
      </label>
      <label>Recipients — one number per line (max <?=MAX_LINES?>)
        <textarea name="recipients" rows="5" required placeholder="+923001234567&#10;03331234567"></textarea>
      </label>
      <label>Message <span class="muted" id="cnt"></span>
        <textarea name="message" id="msg" rows="3" maxlength="<?=(int)config('max_message')?>" required></textarea>
      </label>
      <label class="check"><input type="checkbox" name="consent_confirmed" value="1" required> These recipients agreed to receive messages from me.</label>
      <button type="submit">Queue SMS</button>
      <p class="muted">Limits per phone: <?=(int)config('max_pending')?> waiting, <?=(int)config('daily_limit')?> per 24 hours, one SMS segment (<?=(int)config('max_message')?> characters).</p>
    </form>
  </section>
  <section class="card">
    <h2>Add phone</h2>
    <form method="post">
      <?=csrf_field()?><input type="hidden" name="action" value="add_device">
      <label>Name<input name="device_name" maxlength="120" required placeholder="Office Android"></label>
      <button type="submit">Create device key</button>
    </form>
    <p class="muted">Install the Android app, then paste the server URL and this key into it.</p>
  </section>
</div>
<script>
(function () {
  var msg = document.getElementById('msg'), cnt = document.getElementById('cnt');
  function upd() { cnt.textContent = '(' + msg.value.length + '/' + msg.maxLength + ')'; }
  msg.addEventListener('input', upd); upd();
  var url = location.pathname + (location.search ? location.search + '&' : '?') + 'partial=1';
  setInterval(function () {
    var live = document.getElementById('live');
    if (document.hidden || live.contains(document.activeElement)) return;
    fetch(url, {credentials: 'same-origin'}).then(function (r) { return r.ok ? r.text() : null; })
      .then(function (h) { if (h && h.indexOf('class="stats"') !== -1) live.innerHTML = h; }).catch(function () {});
  }, 15000);
})();
</script>
<?php page_footer();
