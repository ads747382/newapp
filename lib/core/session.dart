import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'config.dart';
import 'format.dart';
import 'hostels.dart';

enum SessionState { loading, signedOut, staff, resident }

/// Holds the sign-in token and the signed-in staff member's permissions.
class Session extends ChangeNotifier {
  Session({Api? api}) : api = api ?? Api(baseUrl: kDefaultServerUrl) {
    this.api.onUnauthorized = _expired;
  }

  static const _storage = FlutterSecureStorage();
  // Tokens are stored per hostel, so a token is only ever sent to the server that issued it.
  static const _kLegacyToken = 'token';
  static const _kLegacyType = 'token_type';
  static const _kHostel = 'selected_hostel';
  String get _kToken => 'token@${api.baseUrl}';
  String get _kType => 'token_type@${api.baseUrl}';

  final Api api;

  /// The hostel chosen on the sign-in screen; null until the user picks one.
  Hostel? hostel;
  SessionState state = SessionState.loading;

  /// A message for the sign-in screen (session ended, offline, …).
  String? notice;

  Json? user;
  Json? resident;
  Set<String> permissions = {};
  Json constants = {};

  String hostelName = kAppTitle;
  String hostelContact = '';
  bool portalEnabled = false;

  /// Super Admin while "Permanent delete" is on in Hostel settings.
  bool canPurge = false;
  bool mustChangePassword = false;

  String? _savedToken;
  String? _savedType;

  /// True when a login is stored but the server could not be reached at start-up.
  bool get hasSavedLogin => _savedToken != null;

  bool can(String permission) => permissions.contains(permission);

  Future<void> load() async {
    // The server is chosen from the hostel list; forget any address saved by older test builds.
    await _storage.delete(key: 'server_url');
    hostel = await _readHostel();
    if (hostel == null) {
      // Builds before multi-hostel kept one token for the main server: keep that user signed in.
      final legacy = await _storage.read(key: _kLegacyToken);
      if (legacy != null) {
        final legacyType = await _storage.read(key: _kLegacyType);
        await _storage.delete(key: _kLegacyToken);
        await _storage.delete(key: _kLegacyType);
        // Moved to the new domain later by syncHostels() once the hostel list says so.
        await _useHostel(Hostel(name: kAppTitle, url: kLegacyServerUrl));
        await _storage.write(key: _kToken, value: legacy);
        await _storage.write(key: _kType, value: legacyType ?? 'staff');
      }
    } else {
      api.baseUrl = hostel!.url;
    }
    if (hostel == null) {
      _set(SessionState.signedOut);
    } else {
      await _restoreSaved();
    }
    // In the background: follow a hostel that moved to the new domain.
    syncHostels();
  }

  /// Checks the hostel list; if the selected hostel now lives on another domain, moves the
  /// saved login there (same database, so the token stays valid) and refreshes the name.
  Future<void> syncHostels([HostelDirectory? directory]) async {
    final current = hostel;
    if (current == null) return;
    final list = await (directory ?? HostelDirectory()).refresh();
    if (hostel != current) return; // user switched meanwhile
    final same = list.where((h) => h == current).firstOrNull;
    if (same != null) {
      if (same.name != current.name || same.subtitle != current.subtitle) {
        await _useHostel(same);
        notifyListeners();
      }
      return;
    }
    final moved = HostelDirectory.movedTo(current, list);
    if (moved == null) return;
    String? token;
    String? type;
    try {
      token = await _storage.read(key: _kToken);
      type = await _storage.read(key: _kType);
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kType);
    } catch (_) {}
    final wasIn = state == SessionState.staff;
    await _useHostel(moved);
    if (token != null) {
      try {
        await _storage.write(key: _kToken, value: token);
        await _storage.write(key: _kType, value: type ?? 'staff');
      } catch (_) {}
    }
    if (wasIn) {
      // Same session, new address; next request goes to the new domain.
      notifyListeners();
    } else if (token != null && state == SessionState.signedOut) {
      await _restoreSaved();
    } else {
      notifyListeners();
    }
  }

  /// Switch to another hostel. The login for the previous hostel stays saved for that hostel.
  Future<void> selectHostel(Hostel h) async {
    if (!Hostel.isAllowedUrl(h.url)) return;
    if (h == hostel && state == SessionState.staff) return;
    _set(SessionState.loading);
    api.token = null;
    _savedToken = null;
    notice = null;
    _reset();
    hostelName = h.name;
    hostelContact = '';
    PaintingBinding.instance.imageCache.clear();
    await _useHostel(h);
    await _restoreSaved();
  }

  Future<void> _useHostel(Hostel h) async {
    hostel = h;
    hostelName = h.name;
    api.baseUrl = h.url;
    try {
      await _storage.write(key: _kHostel, value: jsonEncode(h.toJson()));
    } catch (_) {}
  }

  Future<Hostel?> _readHostel() async {
    try {
      final raw = await _storage.read(key: _kHostel);
      if (raw == null) return null;
      return Hostel.tryParse(jsonDecode(raw)); // re-checked against the allow-list
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreSaved() async {
    String? token;
    String? type;
    try {
      token = await _storage.read(key: _kToken);
      type = await _storage.read(key: _kType);
    } catch (_) {}
    if (token == null) {
      _set(SessionState.signedOut);
      return;
    }
    await _restore(token, type ?? 'staff');
  }

  Future<void> _restore(String token, String type) async {
    // type is always 'staff' now; kept for tokens saved by older builds.
    api.token = token;
    try {
      if (type == 'resident') {
        _applyResident(await api.get('portal/me'));
      } else {
        _applyStaff(await api.get('me'));
      }
      _savedToken = null;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _clearToken();
        notice = e.message;
      } else {
        // Offline at start-up: keep the stored login so the user can retry.
        api.token = null;
        _savedToken = token;
        _savedType = type;
        notice = e.message;
      }
      _set(SessionState.signedOut);
    }
  }

  Future<void> retrySaved() async {
    final token = _savedToken;
    if (token == null) return;
    notice = null;
    _set(SessionState.loading);
    await _restore(token, _savedType ?? 'staff');
  }

  Future<Json> ping() => api.get('ping');

  Future<void> loginStaff(String username, String password) async {
    if (hostel == null) throw ApiException(0, 'Choose your hostel first.');
    final res = await api.post('auth/login', {'username': username.trim(), 'password': password, 'device': 'Android app'});
    await _saveToken(res['token'] as String, 'staff');
    _applyStaff(res);
  }


  Future<void> loginResident(String loginId, String password) async {
    if (hostel == null) throw ApiException(0, 'Choose your hostel first.');
    final res = await api.post('portal/login', {'login_id': loginId.trim(), 'password': password, 'device': 'Android app'});
    await _saveToken(res['token'] as String, 'resident');
    _applyResident(res);
  }

  Future<void> refreshResident() async {
    if (state != SessionState.resident) return;
    _applyResident(await api.get('portal/me'));
  }

  /// Quietly reload permissions (e.g. when the app comes back to the foreground).
  Future<void> refreshQuietly() async {
    try {
      await refreshStaff();
    } on ApiException {
      // A 401 signs out through onUnauthorized; other errors are ignored until the next refresh.
    }
  }

  /// Used by widget tests to sign in without storage or network.
  @visibleForTesting
  void debugSignIn(Json me) => _applyStaff(me);

  Future<void> refreshStaff() async {
    if (state == SessionState.staff) {
      _applyStaff(await api.get('me'));
    } else if (state == SessionState.resident) {
      _applyResident(await api.get('portal/me'));
    }
  }

  Future<void> passwordChanged() async {
    mustChangePassword = false;
    if (state == SessionState.resident) {
      await refreshResident();
    } else {
      await refreshStaff();
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post(state == SessionState.resident ? 'portal/logout' : 'auth/logout');
    } catch (_) {
      // Signing out on the phone is enough if the server can't be reached.
    }
    await _clearToken();
    _reset();
    _set(SessionState.signedOut);
  }

  void _expired() {
    if (state == SessionState.signedOut || state == SessionState.loading) return;
    notice = 'Your session ended. Please sign in again.';
    _clearToken();
    _reset();
    _set(SessionState.signedOut);
  }

  void _applyStaff(Json me) {
    user = Map<String, dynamic>.from(me['user'] as Map);
    permissions = {for (final p in (me['permissions'] as List)) '$p'};
    constants = Map<String, dynamic>.from(me['constants'] as Map);
    final hostel = me['hostel'] as Map;
    hostelName = '${hostel['name']}';
    hostelContact = '${hostel['contact'] ?? ''}';
    portalEnabled = hostel['portal_enabled'] == true;
    canPurge = me['can_purge'] == true;
    currencySymbol = '${constants['currency'] ?? 'Rs'}';
    mustChangePassword = user!['must_change_password'] == true;
    notice = null;
    _set(SessionState.staff);
  }


  void _applyResident(Json me) {
    resident = Map<String, dynamic>.from(me['resident'] as Map);
    user = null;
    resident = null;
    permissions = {};
    constants = {'currency': me['currency'] ?? 'Rs'};
    final h = me['hostel'];
    if (h is Map) {
      hostelName = '${h['name'] ?? hostelName}';
      hostelContact = '${h['contact'] ?? ''}';
    }
    currencySymbol = '${me['currency'] ?? 'Rs'}';
    mustChangePassword = resident!['must_change_password'] == true;
    portalEnabled = true;
    canPurge = false;
    notice = null;
    _set(SessionState.resident);
  }

  Future<void> _saveToken(String token, String type) async {
    api.token = token;
    _savedToken = null;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kType, value: type);
  }

  Future<void> _clearToken() async {
    api.token = null;
    _savedToken = null;
    try {
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kType);
    } catch (_) {}
  }

  void _reset() {
    user = null;
    resident = null;
    permissions = {};
    constants = {};
    mustChangePassword = false;
    canPurge = false;
  }

  void _set(SessionState s) {
    state = s;
    notifyListeners();
  }

  /* ---------- Labels from the server's constants ---------- */

  List<Json> options(String name) => ((constants[name] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  String label(String name, Object? value) {
    if (value == null || '$value'.isEmpty) return '—';
    for (final o in options(name)) {
      if ('${o['value']}' == '$value') return '${o['label']}';
    }
    return '$value'.replaceAll('_', ' ');
  }
}
