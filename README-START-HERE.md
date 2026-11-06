# Personal SMS Gateway — Starter Implementation

This package adds a consent-based, one-phone-at-a-time SMS gateway to the existing PCMonitor PHP/MySQL site.

## What is included
- PHP admin page (`public/sms.php`) that uses the existing PCMonitor admin session.
- PHP device API (`public/sms_api.php`) for Android device registration, polling and status callbacks.
- MySQL migration (`database/sms_migration.sql`).
- Native Android Kotlin project (`android/`) with a foreground service, runtime SMS permission, API polling, and SIM-based SMS sending.
- One SMS job at a time, server-side queue limits, device key authentication, and a recipient-consent confirmation checkbox.

## Important deployment assumption
Your existing site is deployed so the contents of the original `public/` directory are in:
`/home/seojasoo/public_html/pcmoniter/`

Your existing bootstrap is:
`/home/seojasoo/public_html/pcmoniter/app/bootstrap.php`

The new PHP files are designed for that layout and reuse `require_admin()`, `csrf_token()`, `csrf_check()`, `db()`, and `e()` from the existing bootstrap.

## 1) Install the PHP side
1. Back up your current `pcmoniter` folder and database.
2. Upload `public/sms.php` and `public/sms_api.php` into `public_html/pcmoniter/public/` (the same folder that currently contains `login.php` and `setup.php`).
3. Upload `database/sms_migration.sql` somewhere temporary or open it locally.
4. In cPanel → phpMyAdmin, select the existing PCMonitor database (`seojasoo_pcmoniter` in your current setup).
5. Import `sms_migration.sql`. It intentionally does NOT create or select a database.
6. Open `https://seojasoos.com/pcmoniter/sms.php` while logged into the existing PCMonitor admin account. This assumes your existing root `.htaccess` rewrites public routes to the `public/` folder, as in your current deployment.

## 2) Register the Android phone
1. On `sms.php`, use **Add Android device**.
2. Give it a recognizable name (e.g. `My Android Phone`).
3. Copy the generated device key. It is displayed only once.
4. Install the APK you build from the Android project.
5. Open the app, set the server URL to `https://seojasoos.com/pcmoniter/`, paste the device key, and tap **Save & connect**.
6. Grant SMS permission when Android asks.
7. Enable **Allow website jobs to send from this phone**. The app runs a visible foreground notification while enabled.

## 3) Build the Android APK
Requirements on the build computer:
- Android Studio (recommended) or JDK 17 + Android SDK.
- Android Gradle Plugin downloads on first build.
- Android SDK Platform 35.

Open `android/` in Android Studio and let Gradle sync. Then use:
**Build → Build Bundle(s) / APK(s) → Build APK(s)**

Debug APK output:
`android/app/build/outputs/apk/debug/app-debug.apk`

This source package does not contain a compiled APK. It must be built and signed on a machine with Android build tools.

## 4) Send a personal SMS
1. Open `sms.php` in the website admin dashboard.
2. Select the registered Android phone.
3. Enter one recipient number in international format, e.g. `+923001234567`.
4. Enter a message.
5. Tick **I confirm this recipient has agreed to receive this message**.
6. Press **Queue SMS**.
7. Keep the Android phone powered on, connected to the internet, and the SMS service enabled.
8. The phone sends using its selected SIM and reports the result back to the website.

## Safety and platform limitations
- Only message people who have explicitly agreed to receive your messages. The checkbox records the operator's confirmation; it does not independently prove consent.
- This starter is designed for personal, low-volume, one-recipient-at-a-time messaging. It limits queue size and daily sends.
- The Android app requires `SEND_SMS` permission and an active SIM/carrier plan. The carrier may charge SMS fees.
- Android may stop background work due to battery optimization or vendor restrictions. The app uses a foreground service with a persistent notification; do not force-stop it.
- Google Play heavily restricts SMS permissions. This project is intended for private testing/sideloading unless you qualify under Play policy and obtain approval.
- Initial version sends only a single SMS segment. Longer messages are rejected to avoid unexpected multipart sending.
- iPhone does not allow a third-party app to silently send SMS through the SIM. This implementation is Android APK only.
- The website queue does not bypass carrier spam controls, recipient opt-outs, telecom rules, or local law. The `sent` state means Android reported that the SMS send request was accepted by the telephony stack; it is not proof that the recipient handset received it.
- No contacts, call logs, inbox messages, passwords, or keystrokes are collected.

## API routes
Base URL: `https://seojasoos.com/pcmoniter/`
- `POST sms_api.php?action=register` — device key registration (one-time key).
- `POST sms_api.php?action=poll` — claim one pending job.
- `POST sms_api.php?action=heartbeat` — update device presence.
- `POST sms_api.php?action=result` — report sent/failed state.

All device calls use `Authorization: Bearer <device-key>` and HTTPS.

## Troubleshooting
- HTTP 500: inspect cPanel → Metrics → Errors. Confirm PHP PDO MySQL extension is enabled.
- HTTP 401: wrong/revoked device key; create a new device in `sms.php`.
- HTTP 403: HTTPS required or device disabled.
- Database table errors: re-import `sms_migration.sql` into the same database used by PCMonitor.
- SMS permission denied: Android Settings → Apps → Personal SMS Gateway → Permissions → SMS → Allow.
- SMS not sent: verify SIM, balance, network, phone default SMS/SIM selection, and that app notification/service is running.
