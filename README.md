# Hostel app (Android)

Flutter app for the Makkah Hostels admin website (staff only).

Version 1.3: Apple-style interface (SF-like type, system colours, grouped cards, dark mode), multi-meter utility bills, account statements and WhatsApp sharing with secure PDF links.

- **Staff** sign in with their website username and password and see only what their role allows: dashboard, residents and admissions, profile photos, status changes, rooms and beds, documents (camera / gallery / PDF), medical notes, ledger and receipts (share on WhatsApp), monthly rent posting, expenses with bill photos, reports, hostel settings and rules, portal logins for residents.

Server: `https://ai.seojasoos.com/hostel`, set in `lib/core/config.dart` (not shown or editable in the app).
The app talks to `https://ai.seojasoos.com/hostel/api/index.php`.

## Multiple hostels

At sign-in the app shows a list of hostels; staff pick one, then sign in with that hostel's account.
The list comes from `https://makkahhostel.com/hostels.json`, with copies on ai.seojasoos.com as fallback (set in `lib/core/config.dart`), so a new
hostel needs **no app update**: upload a copy of `server/hostels.json` to the web root and add a line:

```json
{ "name": "Hostel 3", "subtitle": "City", "url": "https://ai.seojasoos.com/hostel3" }
```

- When a hostel's folder moves to another allowed domain (same path, e.g. `/hostel2`), phones follow it automatically and keep their login.
- Only `https://` addresses on hosts in `kAllowedHostelHosts` are accepted; other entries are ignored.
- Each hostel folder is its own website install (version 1.4+, Mobile app switched on) with its own staff accounts.
- Logins are saved per hostel. **More → Change hostel** switches without signing out of the other one.
- The last downloaded list is kept on the phone, so the app still works offline.

## In-app updates

1. Build on GitHub (below). Each run gets a higher build number (run number + 100).
2. On the website: **Admin → Mobile app → Upload and publish** the `app-release.apk`.
3. Phones show "Update available" when the app opens (or More → Check for updates), download the file, check it, and open Android's installer. The user taps **Install**; Android asks once to allow installs from this app.

Updates only install over an app signed with the **same key**, so set up your signing key (below) before handing out the app.

## Build the APK on GitHub

1. Create a new GitHub repository and upload everything in this folder (including the hidden `.github` folder).
2. Open the **Actions** tab. The **Build Android APK** workflow runs on every push to `main` (or click **Run workflow**).
3. When it finishes (about 10 minutes), open the run and download **hostel-app-apk-build-N**.
   - `app-release.apk` works on every phone.
   - `app-arm64-v8a-release.apk` is smaller and works on almost all phones from the last 7 years.
4. Push a tag like `v1.0.0` to also get the APK attached to a GitHub Release.

### Your own signing key (recommended)

Without it, the APK is signed with a debug key: fine for installing directly, but every build machine has a different debug key, so phones may refuse to *update* over an older install. Create one key once and keep it safe:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hostel
base64 -w0 release.jks > release.jks.b64
```

In the repository: **Settings → Secrets and variables → Actions** add
`ANDROID_KEYSTORE_BASE64` (contents of `release.jks.b64`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`hostel`), `ANDROID_KEY_PASSWORD`.
Never commit the `.jks` file.

## Build on your computer

```bash
flutter pub get
flutter build apk --release
```

## Server requirements

The website must be version **1.4** or newer with the database updated (Admin → System update), and **Admin → Hostel settings → Mobile app** must be on (it is on by default).

## Change the app name, icon or package

- Name on the home screen: `android:label` in `android/app/src/main/AndroidManifest.xml`.
- Default server: `lib/core/config.dart`.
- Logo and icon: replace `assets/icon/logo.png` and `assets/icon/app_icon.png` (1024×1024), copy `logo.png` over `app_icon_foreground.png`, then run `dart run flutter_launcher_icons`.
- Package id: `applicationId` in `android/app/build.gradle.kts` (change it only before the first release).

## Tests

`flutter test` runs unit tests and screen tests that render the main screens at a small phone size,
with large text and in dark mode, using recorded server responses (`test/fixtures/api.json`).

## GitHub Actions Android build

The repository includes `.github/workflows/build-apk.yml`.

- Push to `main` or `master`: analyze, test, and build APKs automatically.
- Run manually: **GitHub → Actions → Build Android APK → Run workflow**.
- Download: open the completed workflow run and download the `makkah-hostel-apk-*` artifact.
- Push a tag such as `v1.7.0`: APKs are also attached to a GitHub Release.
- Release signing is optional. If no keystore secrets are configured, the APK is signed with the debug key for sideload/testing.

Optional signing secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
Never commit a GitHub token, keystore, `key.properties`, or other secrets to this repository.
