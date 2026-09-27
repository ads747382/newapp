import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/common.dart';
import 'api.dart';
import 'format.dart';

/// Checks the server for a newer app build, downloads it, verifies it and opens Android's installer.
class Updater {
  Updater._();

  static bool _promptedThisRun = false;

  static Future<PackageInfo> current() => PackageInfo.fromPlatform();

  /// Returns the release if it is newer than the installed build.
  static Future<Json?> checkForUpdate(Api api) async {
    final info = await current();
    final build = int.tryParse(info.buildNumber) ?? 0;
    final res = await api.get('app/latest');
    if (res['available'] != true) return null;
    final rel = Map<String, dynamic>.from(res['release'] as Map);
    return toInt(rel['version_code']) > build ? rel : null;
  }

  /// Called when the app opens. Shows the dialog once per run, silently ignores network errors.
  static Future<void> checkOnStart(BuildContext context, Api api) async {
    if (_promptedThisRun) return;
    try {
      final rel = await checkForUpdate(api);
      if (rel == null || !context.mounted) return;
      _promptedThisRun = true;
      await showUpdateDialog(context, api, rel);
    } catch (_) {
      // Checked again next time the app opens.
    }
  }

  /// Manual check from the More screen.
  static Future<void> checkManually(BuildContext context, Api api) async {
    final rel = await runTask(context, () => checkForUpdate(api));
    if (!context.mounted) return;
    if (rel == null) {
      showMessage(context, 'You have the latest version.');
      return;
    }
    await showUpdateDialog(context, api, rel);
  }

  static Future<void> showUpdateDialog(BuildContext context, Api api, Json rel) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(api: api, release: rel),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.api, required this.release});

  final Api api;
  final Json release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;
  String? _readyPath;

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    final rel = widget.release;
    File? file;
    try {
      final dir = await getTemporaryDirectory();
      // Remove older downloads.
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.apk'))) {
        f.deleteSync();
      }
      file = File('${dir.path}/hostel-app-${rel['version_code']}.apk');
      final sink = file.openWrite();
      try {
        await widget.api.download(
          'app/download/${rel['id']}',
          sink,
          expectedSize: toInt(rel['size']),
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        );
      } finally {
        await sink.close();
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != '${rel['sha256']}') {
        throw ApiException(0, 'The download was damaged. Please try again.');
      }
      if (!mounted) return;
      setState(() => _readyPath = file!.path);
      await _install();
    } on ApiException catch (e) {
      if (file != null && file.existsSync()) file.deleteSync();
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (file != null && file.existsSync()) file.deleteSync();
      if (mounted) setState(() => _error = 'Download failed: $e');
    }
  }

  Future<void> _install() async {
    final result = await OpenFilex.open(_readyPath!, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done && mounted) {
      setState(
        () => _error = 'Could not open the installer (${result.message}). Allow "Install unknown apps" for this app in phone settings, then tap Install again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.release;
    final downloading = _progress != null && _readyPath == null && _error == null;
    return AlertDialog(
      icon: const Icon(Icons.system_update, size: 36),
      title: Text('Update available: ${rel['version_name']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ('${rel['notes'] ?? ''}'.isNotEmpty) Text('${rel['notes']}'),
          const SizedBox(height: 8),
          Text('Size: ${humanSize(toInt(rel['size']))}', style: Theme.of(context).textTheme.bodySmall),
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text('Downloading… ${((_progress ?? 0) * 100).round()}%'),
          ],
          if (_readyPath != null && _error == null) ...[
            const SizedBox(height: 12),
            const Text('Tap Install on the next screen. Your data stays on the server; you stay signed in.'),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
        ],
      ),
      actions: [
        if (!downloading) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
        if (_readyPath != null)
          FilledButton(onPressed: _install, child: const Text('Install'))
        else
          FilledButton(onPressed: downloading ? null : _download, child: Text(_error != null ? 'Try again' : 'Update now')),
      ],
    );
  }
}
