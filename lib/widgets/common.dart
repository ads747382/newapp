import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';

Api apiOf(BuildContext context) => context.read<Session>().api;

void showMessage(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? kBad : null, behavior: SnackBarBehavior.floating));
}

/// Runs an action with a blocking progress indicator. Returns the result, or null after showing the error.
Future<T?> runTask<T>(BuildContext context, Future<T> Function() task, {String? success}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    final result = await task();
    nav.pop();
    if (success != null && context.mounted) showMessage(context, success);
    return result;
  } on ApiException catch (e) {
    nav.pop();
    if (context.mounted) showMessage(context, e.errors.isNotEmpty ? e.errors.values.join('\n') : e.message, error: true);
    return null;
  } catch (e) {
    nav.pop();
    if (context.mounted) showMessage(context, 'Something went wrong: $e', error: true);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kBad) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Asks for a reason (void, reject, archive…). Returns null when cancelled.
Future<String?> askText(BuildContext context, String title, {String label = 'Reason', String ok = 'Save', bool required = true, bool danger = false}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 255,
            maxLines: 2,
            decoration: InputDecoration(labelText: label),
            onChanged: (_) => set(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: kBad) : null,
              onPressed: required && ctrl.text.trim().isEmpty ? null : () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(ok),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> openExternal(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('launchUrl failed: $e');
  }
  if (!ok && context.mounted) showMessage(context, 'No app found to open this.', error: true);
}

Future<void> callPhone(BuildContext context, String phone) => openExternal(context, Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')));

/// Pakistani local numbers (03xx…) become 92xx… for WhatsApp.
Future<void> openWhatsApp(BuildContext context, String? phone, String text) {
  var digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) digits = '92${digits.substring(1)}';
  final path = digits.length >= 11 ? digits : '';
  return openExternal(context, Uri.parse('https://wa.me/$path?text=${Uri.encodeComponent(text)}'));
}

/// Downloads a protected file to the app's temporary folder and opens it.
Future<void> downloadAndOpen(BuildContext context, String route, String filename, {Map<String, Object?>? query}) async {
  final api = apiOf(context);
  final path = await runTask(context, () async {
    final bytes = await api.bytes(route, query: query);
    final dir = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  });
  if (path == null) return;
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done && context.mounted) {
    showMessage(context, 'No app on this phone can open this file (${result.message}).', error: true);
  }
}

/* ---------- Loading pattern ---------- */

typedef Loader = Future<Json> Function();

/// Loads JSON, shows spinner / error with retry, supports pull-to-refresh.
class LoadView extends StatefulWidget {
  const LoadView({super.key, required this.load, required this.builder, this.scroll = true});

  final Loader load;
  final Widget Function(BuildContext context, Json data, Future<void> Function() reload) builder;

  /// Wrap the result in a scroll view with pull-to-refresh.
  final bool scroll;

  @override
  State<LoadView> createState() => LoadViewState();
}

class LoadViewState extends State<LoadView> {
  Json? _data;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return ErrorView(message: _error!.message, onRetry: reload);
    }
    final child = widget.builder(context, _data!, reload);
    if (!widget.scroll) return child;
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(padding: EdgeInsets.fromLTRB(16, 12, 16, listBottomPadding(context)), children: [child]),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: kMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: kMuted),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted),
          ),
        ],
      ),
    );
  }
}

/* ---------- Display pieces ---------- */

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone});

  final String label;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final c = toneFor(tone ?? label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});

  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 2, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title!.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.6))),
                  ?trailing,
                ],
              ),
            ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

/// Label/value rows.
class InfoRows extends StatelessWidget {
  const InfoRows(this.rows, {super.key});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final line = Theme.of(context).dividerColor;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: i == rows.length - 1
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: line, width: 0.5)),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(rows[i].$1, style: t.bodyMedium?.copyWith(color: kMuted)),
                ),
                Expanded(
                  flex: 6,
                  child: SelectableText(
                    rows[i].$2,
                    textAlign: TextAlign.right,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.color, this.icon, this.onTap});

  final String label;
  final String value;
  final String? sub;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: color ?? kMuted), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(
                      label,
                      style: t.bodySmall?.copyWith(color: kMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: t.bodySmall?.copyWith(color: kMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-column grid of stat tiles.
class StatGrid extends StatelessWidget {
  const StatGrid(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 600 ? 4 : 2;
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final ch in children) SizedBox(width: w, child: ch)],
          );
        },
      ),
    );
  }
}

/// Resident photo loaded with the sign-in token, falling back to initials.
class ResidentAvatar extends StatelessWidget {
  const ResidentAvatar({super.key, required this.id, required this.name, this.hasPhoto = false, this.radius = 22});

  final int id;
  final String name;
  final bool hasPhoto;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initials(name),
        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: radius * 0.7, fontWeight: FontWeight.w600),
      ),
    );
    if (!hasPhoto) return fallback;
    final api = apiOf(context);
    return ClipOval(
      child: Image.network(
        api.uri('residents/$id/photo').toString(),
        headers: api.authHeaders,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

String? fieldError(Map<String, String> errors, String key) => errors[key];


/// Space under the last list item so it can scroll clear of the floating nav bar and a
/// floating action button (padding.bottom already includes the nav bar inside the tabs).
double listBottomPadding(BuildContext context) => MediaQuery.paddingOf(context).bottom + 88;
