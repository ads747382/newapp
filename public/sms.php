<?php
declare(strict_types=1);
require dirname(__DIR__) . '/app/bootstrap.php';
require_admin();

$notice = '';
$newKey = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string)($_POST['action'] ?? '');
    if ($action === 'add_device') {
        $name = trim((string)($_POST['device_name'] ?? ''));
        if ($name === '' || mb_strlen($name) > 120) {
            $notice = 'Please enter a device name (1–120 characters).';
        } else {
            $plain = rtrim(strtr(base64_encode(random_bytes(36)), '+/', '-_'), '=');
            $uuid = sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
                random_int(0,65535), random_int(0,65535), random_int(0,65535),
                random_int(0,4095) | 0x4000, random_int(0,16383) | 0x8000,
                random_int(0,65535), random_int(0,65535), random_int(0,65535));
            $st = db()->prepare('INSERT INTO sms_devices(device_uuid,device_name,api_key_hash,created_at) VALUES(?,?,?,UTC_TIMESTAMP())');
            $st->execute([$uuid, $name, hash('sha256', $plain)]);
            $newKey = $plain;
            $notice = 'Device created. Copy the key now; it will not be shown again.';
        }
    } elseif ($action === 'toggle_device') {
        $id = (int)($_POST['device_id'] ?? 0);
        db()->prepare('UPDATE sms_devices SET enabled = IF(enabled=1,0,1) WHERE id=?')->execute([$id]);
        $notice = 'Device setting updated.';
    } elseif ($action === 'queue_sms') {
        $deviceId = (int)($_POST['device_id'] ?? 0);
        $recipient = trim((string)($_POST['recipient'] ?? ''));
        $message = trim((string)($_POST['message'] ?? ''));
        $consent = isset($_POST['consent_confirmed']) ? 1 : 0;
        if (!$consent) {
            $notice = 'Please confirm recipient consent before queueing.';
        } elseif (!preg_match('/^\+[1-9][0-9]{7,14}$/', $recipient)) {
            $notice = 'Use international number format, e.g. +923001234567.';
        } elseif ($message === '' || mb_strlen($message) > 500) {
            $notice = 'Message must contain 1–500 characters.';
        } else {
            $dev = db()->prepare('SELECT id FROM sms_devices WHERE id=? AND enabled=1');
            $dev->execute([$deviceId]);
            if (!$dev->fetch()) {
                $notice = 'Select an enabled Android device.';
            } else {
                $q = db()->prepare("SELECT COUNT(*) FROM sms_jobs WHERE device_id=? AND status IN ('pending','claimed')");
                $q->execute([$deviceId]);
                $pending = (int)$q->fetchColumn();
                $q = db()->prepare("SELECT COUNT(*) FROM sms_jobs WHERE device_id=? AND created_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY");
                $q->execute([$deviceId]);
                $daily = (int)$q->fetchColumn();
                if ($pending >= 5) {
                    $notice = 'Queue limit reached (5 pending jobs). Wait for the phone to process them.';
                } elseif ($daily >= 30) {
                    $notice = 'Personal-use daily limit reached (30 messages per device).';
                } else {
                    $st = db()->prepare("INSERT INTO sms_jobs(device_id,recipient,message,consent_confirmed,status,created_by,created_at,idempotency_key) VALUES(?,?,?,1,'pending',?,UTC_TIMESTAMP(),?)");
                    $st->execute([$deviceId, $recipient, $message, (int)$_SESSION['admin_id'], sprintf('%s-%s', bin2hex(random_bytes(8)), bin2hex(random_bytes(8)))]);
                    $notice = 'SMS queued. The phone will pick it up when online.';
                }
            }
        }
    }
}
$devices = db()->query('SELECT id,device_name,enabled,last_seen_at FROM sms_devices ORDER BY id DESC')->fetchAll();
$jobs = db()->query('SELECT j.id,j.recipient,j.message,j.status,j.created_at,j.sent_at,j.error_message,d.device_name FROM sms_jobs j JOIN sms_devices d ON d.id=j.device_id ORDER BY j.id DESC LIMIT 50')->fetchAll();
?>
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Personal SMS Gateway</title><link rel="stylesheet" href="assets/style.css">
<style>
.sms-wrap{max-width:1100px;margin:28px auto;padding:0 16px}.sms-card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:18px;margin:16px 0}.sms-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px} .sms-card input,.sms-card select,.sms-card textarea{width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;margin:6px 0 12px;box-sizing:border-box}.sms-card button{padding:10px 16px;border:0;border-radius:8px;background:#155eef;color:white;cursor:pointer}.sms-notice{padding:12px;background:#eff6ff;border-radius:8px;margin:12px 0}.sms-key{overflow-wrap:anywhere;background:#fff7ed;padding:12px;border:1px solid #fed7aa}.sms-table{width:100%;border-collapse:collapse}.sms-table th,.sms-table td{padding:9px;border-bottom:1px solid #e5e7eb;text-align:left;font-size:14px;vertical-align:top}.muted{color:#64748b;font-size:13px}
</style></head><body><main class="sms-wrap">
<h1>Personal SMS Gateway</h1><p class="muted">Send one consent-confirmed personal SMS through a registered Android phone and its SIM.</p>
<?php if($notice): ?><div class="sms-notice"><?=e($notice)?></div><?php endif; ?>
<?php if($newKey): ?><div class="sms-card"><h3>Copy this device key now</h3><div class="sms-key"><code><?=e($newKey)?></code></div><p class="muted">It is shown only once. Store it privately in the Android app.</p></div><?php endif; ?>
<div class="sms-grid">
<section class="sms-card"><h2>Add Android device</h2><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf_token())?>"><input type="hidden" name="action" value="add_device"><label>Device name</label><input name="device_name" maxlength="120" required placeholder="My Android Phone"><button type="submit">Create device key</button></form></section>
<section class="sms-card"><h2>Queue a personal SMS</h2><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf_token())?>"><input type="hidden" name="action" value="queue_sms"><label>Android device</label><select name="device_id" required><option value="">Select device</option><?php foreach($devices as $d): if((int)$d['enabled']!==1)continue; ?><option value="<?=$d['id']?>"><?=e($d['device_name'])?></option><?php endforeach; ?></select><label>Recipient number</label><input name="recipient" required placeholder="+923001234567" maxlength="24"><label>Message (single SMS segment only)</label><textarea name="message" rows="3" maxlength="500" required></textarea><label><input type="checkbox" name="consent_confirmed" value="1" required style="width:auto"> I confirm this recipient agreed to receive this message.</label><p class="muted">Personal-use limit: 5 pending and 30 messages per device per day. Longer/multipart SMS is not supported in this starter.</p><button type="submit">Queue SMS</button></form></section>
</div>
<section class="sms-card"><h2>Registered phones</h2><table class="sms-table"><tr><th>Phone</th><th>Enabled</th><th>Last seen (UTC)</th><th>Action</th></tr><?php foreach($devices as $d): ?><tr><td><?=e($d['device_name'])?></td><td><?=$d['enabled']?'Yes':'No'?></td><td><?=e($d['last_seen_at']??'Never')?></td><td><form method="post"><input type="hidden" name="csrf" value="<?=e(csrf_token())?>"><input type="hidden" name="action" value="toggle_device"><input type="hidden" name="device_id" value="<?=$d['id']?>"><button type="submit"><?=$d['enabled']?'Disable':'Enable'?></button></form></td></tr><?php endforeach; ?></table></section>
<section class="sms-card"><h2>Recent SMS jobs</h2><table class="sms-table"><tr><th>ID</th><th>Phone</th><th>Recipient</th><th>Message</th><th>Status</th><th>Created / sent</th><th>Error</th></tr><?php foreach($jobs as $j): ?><tr><td><?=$j['id']?></td><td><?=e($j['device_name'])?></td><td><?=e($j['recipient'])?></td><td><?=e($j['message'])?></td><td><?=e($j['status'])?></td><td><?=e($j['created_at'])?><br><?=e($j['sent_at']??'')?></td><td><?=e($j['error_message']??'')?></td></tr><?php endforeach; ?></table></section>
<p><a href="index.php">Back to PCMonitor dashboard</a></p>
</main></body></html>
