-- Import this into the EXISTING PCMonitor database in phpMyAdmin.
-- Do not add CREATE DATABASE or USE statements here.

CREATE TABLE IF NOT EXISTS sms_devices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    device_uuid CHAR(36) NOT NULL UNIQUE,
    device_name VARCHAR(120) NOT NULL,
    api_key_hash CHAR(64) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at DATETIME NULL,
    last_ip VARCHAR(45) NULL,
    INDEX idx_sms_device_key (api_key_hash),
    INDEX idx_sms_device_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sms_jobs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    device_id BIGINT UNSIGNED NOT NULL,
    recipient VARCHAR(24) NOT NULL,
    message VARCHAR(500) NOT NULL,
    consent_confirmed TINYINT(1) NOT NULL DEFAULT 0,
    status ENUM('pending','claimed','sent','failed') NOT NULL DEFAULT 'pending',
    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at DATETIME NULL,
    sent_at DATETIME NULL,
    delivered_at DATETIME NULL,
    error_message VARCHAR(500) NULL,
    idempotency_key CHAR(36) NOT NULL,
    INDEX idx_sms_queue (device_id, status, created_at),
    INDEX idx_sms_created (created_at),
    UNIQUE KEY uq_sms_idempotency (idempotency_key),
    CONSTRAINT fk_sms_job_device FOREIGN KEY (device_id)
        REFERENCES sms_devices(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
