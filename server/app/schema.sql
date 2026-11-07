-- SMS Gateway schema (MySQL 5.7+ / MariaDB 10.3+). install.php runs this for you.

CREATE TABLE IF NOT EXISTS sms_admins (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(60) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL,
    last_login_at DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sms_devices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    device_name VARCHAR(120) NOT NULL,
    api_key_hash CHAR(64) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL,
    last_seen_at DATETIME NULL,
    last_ip VARCHAR(45) NULL,
    INDEX idx_sms_device_key (api_key_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sms_jobs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    device_id BIGINT UNSIGNED NOT NULL,
    recipient VARCHAR(24) NOT NULL,
    message VARCHAR(500) NOT NULL,
    consent_confirmed TINYINT(1) NOT NULL DEFAULT 0,
    status ENUM('pending','claimed','sent','failed','cancelled') NOT NULL DEFAULT 'pending',
    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_by BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL,
    claimed_at DATETIME NULL,
    sent_at DATETIME NULL,
    error_message VARCHAR(500) NULL,
    INDEX idx_sms_queue (device_id, status, id),
    INDEX idx_sms_created (created_at),
    CONSTRAINT fk_sms_job_device FOREIGN KEY (device_id) REFERENCES sms_devices(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
