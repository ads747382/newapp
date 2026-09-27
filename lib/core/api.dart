import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error returned by the server (or a network failure) in a form the UI can show.
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code, Map<String, String>? errors}) : errors = errors ?? const {};

  final int status;
  final String message;
  final String? code;

  /// Field name -> message, for showing next to form fields.
  final Map<String, String> errors;

  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

/// A file to upload in a multipart request.
class UploadFile {
  UploadFile({required this.field, required this.filename, required this.bytes});

  final String field;
  final String filename;
  final Uint8List bytes;
}

typedef Json = Map<String, dynamic>;

/// Thin client for /api/index.php. Uses ?route= so it works on hosts without PATH_INFO.
class Api {
  Api({required this.baseUrl, this.token, http.Client? client}) : _client = client ?? http.Client();

  String baseUrl;
  String? token;

  /// Replaceable in tests.
  final http.Client _client;

  /// Called when the server says the token is no longer valid.
  VoidCallback? onUnauthorized;

  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(minutes: 3);

  static String normaliseBase(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    u = u.replaceAll(RegExp(r'/+$'), '');
    if (u.endsWith('/api/index.php')) u = u.substring(0, u.length - '/api/index.php'.length);
    return u;
  }

  Uri uri(String route, [Map<String, Object?>? query]) {
    final q = <String, String>{'route': route};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    return Uri.parse('$baseUrl/api/index.php').replace(queryParameters: q);
  }

  /// Headers for authenticated image loading.
  Map<String, String> get authHeaders => {
    if (token case final t?) 'Authorization': 'Bearer $t',
    // Some cPanel servers drop the Authorization header; the server accepts this too.
    'X-Auth-Token': ?token,
  };

  Map<String, String> get _headers => {'Accept': 'application/json', ...authHeaders};

  Future<Json> get(String route, {Map<String, Object?>? query}) => _send(() => _client.get(uri(route, query), headers: _headers).timeout(_timeout));

  Future<Json> post(String route, [Map<String, Object?> body = const {}]) =>
      _send(() => _client.post(uri(route), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(_timeout));

  Future<Json> upload(String route, {Map<String, String> fields = const {}, List<UploadFile> files = const []}) {
    return _send(() async {
      final req = http.MultipartRequest('POST', uri(route))
        ..headers.addAll(_headers)
        ..fields.addAll(fields);
      for (final f in files) {
        req.files.add(http.MultipartFile.fromBytes(f.field, f.bytes, filename: f.filename));
      }
      final streamed = await _client.send(req).timeout(_uploadTimeout);
      return http.Response.fromStream(streamed);
    });
  }

  /// Download a file (photo, document, bill). Throws ApiException on error.
  Future<Uint8List> bytes(String route, {Map<String, Object?>? query}) async {
    final res = await _raw(() => _client.get(uri(route, query), headers: _headers).timeout(const Duration(minutes: 2)));
    final type = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || type.startsWith('application/json')) {
      throw _errorFrom(res);
    }
    return res.bodyBytes;
  }

  /// Stream a large download to [sink], reporting progress (0–1). Returns bytes written.
  Future<int> download(String route, IOSink sink, {void Function(double progress)? onProgress, int? expectedSize}) async {
    final req = http.Request('GET', uri(route))..headers.addAll(authHeaders);
    late http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 30));
    } on SocketException {
      throw ApiException(0, 'No internet connection. Check your network and try again.');
    } on TimeoutException {
      throw ApiException(0, 'The server is taking too long to respond. Try again.');
    }
    if (res.statusCode != 200 || (res.headers['content-type'] ?? '').startsWith('application/json')) {
      throw _errorFrom(await http.Response.fromStream(res));
    }
    final total = res.contentLength ?? expectedSize ?? 0;
    var received = 0;
    await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.flush();
    return received;
  }

  Future<http.Response> _raw(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on SocketException {
      throw ApiException(0, 'No internet connection. Check your network and try again.');
    } on TimeoutException {
      throw ApiException(0, 'The server is taking too long to respond. Try again.');
    } on HandshakeException {
      throw ApiException(0, 'Secure connection to the hostel server failed. Check the phone’s date and time, then try again.');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Could not reach the server: ${e.message}');
    }
  }

  Future<Json> _send(Future<http.Response> Function() call) async {
    final res = await _raw(call);
    Json? body;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      body = null;
    }
    if (body == null) {
      throw ApiException(
        res.statusCode,
        res.statusCode == 404 ? 'Could not reach the hostel server. Try again later.' : 'Unexpected response from the server (${res.statusCode}).',
      );
    }
    if (res.statusCode >= 400 || body['ok'] != true) {
      throw _errorFrom(res, body);
    }
    return body;
  }

  ApiException _errorFrom(http.Response res, [Json? body]) {
    if (body == null) {
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map<String, dynamic>) body = d;
      } catch (_) {}
    }
    final errors = <String, String>{};
    final raw = body?['errors'];
    if (raw is Map) {
      raw.forEach((k, v) => errors['$k'] = '$v');
    }
    final e = ApiException(
      res.statusCode,
      (body?['error'] as String?) ?? 'Request failed (${res.statusCode}).',
      code: body?['code'] as String?,
      errors: errors,
    );
    if (e.isAuth && token != null) onUnauthorized?.call();
    return e;
  }
}
