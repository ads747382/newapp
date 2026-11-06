<?php
declare(strict_types=1);
require dirname(__DIR__) . '/app/bootstrap.php';
ensure_local_http_allowed();

function sms_device(): array {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/^Bearer ([A-Za-z0-9_-]{40,100})$/', $h, $m)) api_error('Missing device key', 401);
    $s = db()->prepare('SELECT * FROM sms_devices WHERE api_key_hash=? AND enabled=1 LIMIT 1');
    $s->execute([hash('sha256', $m[1])]);
    $d = $s->fetch();
    if (!$d) api_error('Device key invalid or disabled', 401);
    db()->prepare('UPDATE sms_devices SET last_seen_at=UTC_TIMESTAMP(),last_ip=? WHERE id=?')->execute([substr($_SERVER['REMOTE_ADDR'] ?? '',0,45),$d['id']]);
    return $d;
}
$action = (string)($_GET['action'] ?? '');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') api_error('POST required', 405);

if ($action === 'poll') {
    $d = sms_device();
    $pdo = db();
    $pdo->beginTransaction();
    try {
        // Recover a job if the app crashed after claiming it.
        $pdo->prepare("UPDATE sms_jobs SET status='pending',claimed_at=NULL WHERE device_id=? AND status='claimed' AND claimed_at < UTC_TIMESTAMP() - INTERVAL 5 MINUTE")->execute([$d['id']]);
        $q = $pdo->prepare("SELECT id,recipient,message FROM sms_jobs WHERE device_id=? AND status='pending' AND consent_confirmed=1 ORDER BY id ASC LIMIT 1 FOR UPDATE");
        $q->execute([$d['id']]);
        $job = $q->fetch();
        if (!$job) { $pdo->commit(); api_ok(['job'=>null]); }
        $pdo->prepare("UPDATE sms_jobs SET status='claimed',claimed_at=UTC_TIMESTAMP(),attempts=attempts+1 WHERE id=? AND status='pending'")->execute([$job['id']]);
        $pdo->commit();
        api_ok(['job'=>['id'=>(int)$job['id'],'recipient'=>$job['recipient'],'message'=>$job['message']]]);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        error_log('SMS poll error: '.$e->getMessage());
        api_error('Queue error',500);
    }
}
if ($action === 'heartbeat') {
    sms_device();
    api_ok(['server_time'=>gmdate('c')]);
}
if ($action === 'result') {
    $d = sms_device();
    $b = json_body();
    $id = filter_var($b['job_id'] ?? null, FILTER_VALIDATE_INT);
    $status = (string)($b['status'] ?? '');
    $error = trim((string)($b['error'] ?? ''));
    if (!$id || !in_array($status,['sent','failed'],true)) api_error('Invalid result',422);
    $st = db()->prepare("UPDATE sms_jobs SET status=?,sent_at=IF(?='sent',UTC_TIMESTAMP(),sent_at),error_message=? WHERE id=? AND device_id=? AND status='claimed'");
    $st->execute([$status,$status,$status==='failed'?substr($error,0,500):null,$id,$d['id']]);
    if (!$st->rowCount()) api_error('Job not found or already completed',409);
    api_ok();
}
api_error('Unknown action',404);
