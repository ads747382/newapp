# Web ↔ Flutter parity status

Reference web: 15-updated package (APP 1.11.x / schema 11 codebase)
Flutter base: 1.7.0+9

## Added in this parity pass
- Resident portal sign-in/session restored in Flutter.
- Resident portal: home/balance, payments/receipts, electricity bills/PDF, attendance/PDF, statement, rules, password, logout.
- Staff attendance: daily board, resident history, manual check-in/out, resident/summary PDFs.
- Admission: deposit-received-now and upfront-payment fields using the same server helper as web.
- Money Board API + Flutter screen with due/deposit/charge/total-to-collect and rent state.
- Admin API + Flutter UI for Users, Roles/permissions, Audit log, Backups.
- System update API + Flutter UI (same installer; optional backup first).
- Printable admission/rules forms generated/printable from Flutter.
- Web API additions preserve existing permission checks.

## Validation completed
- PHP syntax lint: all 193 PHP files in the extracted web package passed `php -l`.
- Flutter SDK is not installed in this environment, so `flutter analyze`, widget tests, and Android build have NOT been run.

## Remaining before claiming full web parity
1. Accounts reminders page + reminder log/WhatsApp reminder workflow.
2. Agreed one-time charge management and quick mark-received/rent-top-up convenience flows where web has dedicated screens.
3. Admin integrations/webhooks/cron controls.
4. Admin email-alert configuration and test-mail flow.
5. Attendance biometric device administration, enrollment management UI, and bulk attendance UI.
6. Resident portal administration/settings page parity (global portal controls beyond per-resident portal action already exposed elsewhere).
7. Mobile app release upload/activation administration (Flutter already checks/downloads published releases).
8. Document and resident-photo crop/rotate UI (server crop routes exist; native crop UI still missing).
9. Final UI-by-UI visual spacing/text parity review on a real Android device.
10. `flutter pub get`, `flutter analyze`, `flutter test`, and signed/unsigned Android build verification.

Do not call this 100% matched until the remaining list is closed and Flutter validation passes.
