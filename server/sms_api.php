<?php
// Device API used by the Android app.
// POST sms_api.php?action=heartbeat|poll|result
// Header: Authorization: Bearer <device-key>   (fallback: X-Device-Key: <device-key>)
declare(strict_types=1);
require __DIR__ . '/app/bootstrap.php';

if (config('require_https') && !is_https()) api_error('HTTPS required', 403);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') api_error('POST required', 405);

function sms_device(): array {
    $key = bearer_key();
    if (!preg_match('/^[A-Za-z0-9_-]{40,100}$/', $key)) api_error('Missing device key', 401);
    $s = db()->prepare('SELECT * FROM sms_devices WHERE api_key_hash=? LIMIT 1');
    $s->execute([hash('sha256', $key)]);
    $d = $s->fetch();
    if (!$d) api_error('Device key invalid', 401);
    if ((int)$d['enabled'] !== 1) api_error('Device disabled', 403);
    db()->prepare('UPDATE sms_devices SET last_seen_at=UTC_TIMESTAMP(), last_ip=? WHERE id=?')
        ->execute([substr($_SERVER['REMOTE_ADDR'] ?? '', 0, 45), $d['id']]);
    return $d;
}

$action = (string)($_GET['action'] ?? '');

if ($action === 'heartbeat') {
    sms_device();
    api_ok(['server_time' => gmdate('c')]);
}

if ($action === 'poll') {
    $d = sms_device();
    $id = (int)$d['id'];
    $q = db()->prepare("SELECT COUNT(*) FROM sms_jobs WHERE device_id=? AND sent_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY");
    $q->execute([$id]);
    if ((int)$q->fetchColumn() >= (int)config('daily_limit')) api_ok(['job' => null, 'reason' => 'daily_limit']);

    $pdo = db();
    $pdo->beginTransaction();
    try {
        // Jobs claimed >5 min ago without a result: give up after 3 attempts, otherwise retry.
        $pdo->prepare("UPDATE sms_jobs SET status='failed', error_message='No result from phone after 3 attempts' WHERE device_id=? AND status='claimed' AND claimed_at < UTC_TIMESTAMP() - INTERVAL 5 MINUTE AND attempts >= 3")->execute([$id]);
        $pdo->prepare("UPDATE sms_jobs SET status='pending', claimed_at=NULL WHERE device_id=? AND status='claimed' AND claimed_at < UTC_TIMESTAMP() - INTERVAL 5 MINUTE")->execute([$id]);
        $q = $pdo->prepare("SELECT id, recipient, message FROM sms_jobs WHERE device_id=? AND status='pending' AND consent_confirmed=1 ORDER BY id ASC LIMIT 1 FOR UPDATE");
        $q->execute([$id]);
        $job = $q->fetch();
        if (!$job) { $pdo->commit(); api_ok(['job' => null]); }
        $pdo->prepare("UPDATE sms_jobs SET status='claimed', claimed_at=UTC_TIMESTAMP(), attempts=attempts+1 WHERE id=?")->execute([$job['id']]);
        $pdo->commit();
        api_ok(['job' => ['id' => (int)$job['id'], 'recipient' => $job['recipient'], 'message' => $job['message']]]);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        error_log('SMS poll error: ' . $e->getMessage());
        api_error('Queue error', 500);
    }
}

if ($action === 'result') {
    $d = sms_device();
    $b = json_body();
    $jobId = filter_var($b['job_id'] ?? null, FILTER_VALIDATE_INT);
    $status = (string)($b['status'] ?? '');
    $error = substr(trim((string)($b['error'] ?? '')), 0, 500);
    if (!$jobId || !in_array($status, ['sent', 'failed'], true)) api_error('Invalid result', 422);
    if ($status === 'sent') {
        $st = db()->prepare("UPDATE sms_jobs SET status='sent', sent_at=UTC_TIMESTAMP(), error_message=NULL WHERE id=? AND device_id=? AND status='claimed'");
        $st->execute([$jobId, $d['id']]);
    } else {
        $st = db()->prepare("UPDATE sms_jobs SET status='failed', error_message=? WHERE id=? AND device_id=? AND status='claimed'");
        $st->execute([$error ?: 'Unknown error', $jobId, $d['id']]);
    }
    if (!$st->rowCount()) api_error('Job not found or already completed', 409);
    api_ok();
}

api_error('Unknown action', 404);
