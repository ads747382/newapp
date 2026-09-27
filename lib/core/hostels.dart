import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'config.dart';

/// One hostel website the app can sign in to.
@immutable
class Hostel {
  const Hostel({required this.name, required this.url, this.subtitle});

  final String name;

  /// Base address, e.g. https://ai.seojasoos.com/hostel1 (no trailing slash).
  final String url;
  final String? subtitle;

  /// Returns null when the entry is missing a field or points somewhere not allowed.
  static Hostel? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = '${raw['name'] ?? ''}'.trim();
    final url = Api.normaliseBase('${raw['url'] ?? ''}');
    if (name.isEmpty || name.length > 80 || !isAllowedUrl(url)) return null;
    final sub = '${raw['subtitle'] ?? raw['city'] ?? ''}'.trim();
    return Hostel(name: name, url: url, subtitle: sub.isEmpty || sub.length > 120 ? null : sub);
  }

  /// https only, on an allowed host, no user-info / port / query tricks.
  static bool isAllowedUrl(String url) {
    // Checked on the raw text: Uri.parse quietly resolves "..", "\\" and similar tricks.
    if (url.contains('..') || url.contains('\\') || url.contains('%') || RegExp(r'\s').hasMatch(url)) return false;
    final u = Uri.tryParse(url);
    if (u == null) return false;
    return u.scheme == 'https' &&
        kAllowedHostelHosts.contains(u.host.toLowerCase()) &&
        u.userInfo.isEmpty &&
        !u.hasPort &&
        !u.hasQuery &&
        !u.hasFragment &&
        !u.path.contains('..');
  }

  Map<String, Object?> toJson() => {'name': name, 'url': url, 'subtitle': ?subtitle};

  @override
  bool operator ==(Object other) => other is Hostel && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Downloads the hostel list, keeps the last good copy for offline starts.
class HostelDirectory {
  HostelDirectory({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;
  static const _kCache = 'hostel_list_cache';

  static List<Hostel> get builtIn => [for (final h in kBuiltInHostels) Hostel(name: h.name, url: Api.normaliseBase(h.url))];

  /// Accepts either `[{...}, ...]` or `{"hostels": [{...}, ...]}`. Bad entries are skipped.
  static List<Hostel> parse(String body) {
    final data = jsonDecode(body);
    final list = data is Map ? data['hostels'] : data;
    if (list is! List) return const [];
    final out = <Hostel>[];
    for (final raw in list) {
      final h = Hostel.tryParse(raw);
      if (h != null && !out.contains(h)) out.add(h);
    }
    return out;
  }

  /// Last list we saw (or the built-in one): instant, works offline.
  Future<List<Hostel>> cached() async {
    try {
      final body = await _storage.read(key: _kCache);
      if (body != null) {
        final list = parse(body);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {
      // Storage not available (tests) or corrupt cache: fall back below.
    }
    return builtIn;
  }

  /// Fresh list from the server; falls back to [cached] on any problem.
  Future<List<Hostel>> refresh() async {
    for (final url in kHostelDirectoryUrls) {
      try {
        final res = await _client
            .get(Uri.parse(url), headers: {'Accept': 'application/json', 'Cache-Control': 'no-cache'})
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200 || res.bodyBytes.length > 256 * 1024) continue;
        final list = parse(utf8.decode(res.bodyBytes));
        if (list.isEmpty) continue;
        try {
          await _storage.write(key: _kCache, value: jsonEncode([for (final h in list) h.toJson()]));
        } catch (_) {}
        return list;
      } catch (e) {
        debugPrint('hostel list $url: $e');
      }
    }
    return cached();
  }

  /// When a hostel moves to another allowed domain, the list shows the same folder on the new
  /// host (e.g. ai.seojasoos.com/hostel2 -> makkahhostel.com/hostel2). Returns the new entry.
  static Hostel? movedTo(Hostel current, List<Hostel> list) {
    if (list.contains(current)) return null;
    final path = Uri.parse(current.url).path;
    for (final h in list) {
      if (Uri.parse(h.url).path == path) return h;
    }
    return null;
  }
}
