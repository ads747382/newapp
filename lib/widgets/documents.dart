import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

/// A document on the server that can be printed or shared (bill, receipt, statement…).
class ServerDocument {
  const ServerDocument({required this.route, required this.filename, this.query, this.title});

  final String route;
  final String filename;
  final Map<String, Object?>? query;
  final String? title;
}

/// Downloads once, then prints / shares / opens the same bytes.
class DocumentActions {
  DocumentActions(this.context, this.doc);

  final BuildContext context;
  final ServerDocument doc;
  Uint8List? _bytes;

  Future<Uint8List?> _load() async {
    if (_bytes != null) return _bytes;
    final api = apiOf(context);
    return _bytes = await runTask(context, () => api.bytes(doc.route, query: doc.query));
  }

  /// Android's print dialog, which also offers "Save as PDF".
  Future<void> print_() async {
    final bytes = await _load();
    if (bytes == null) return;
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: doc.filename);
    } catch (e) {
      debugPrint('print failed: $e');
      // No print service on the phone: open the PDF instead, its viewer can print too.
      if (context.mounted) showMessage(context, 'Printing is not available here, opening the PDF instead.');
      await _openBytes(bytes);
    }
  }

  /// Android share sheet: WhatsApp, Gmail, Drive, Files…
  Future<void> share() async {
    final bytes = await _load();
    if (bytes == null) return;
    try {
      await Printing.sharePdf(bytes: bytes, filename: doc.filename);
      return;
    } catch (e) {
      debugPrint('printing.sharePdf failed: $e');
    }
    try {
      final file = await _saveTemp(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], title: doc.title ?? doc.filename));
    } catch (e) {
      debugPrint('share_plus failed: $e');
      if (context.mounted) showMessage(context, 'Could not share the PDF. Please update the app and try again.', error: true);
    }
  }

  /// Saves to the phone and opens it in a PDF viewer.
  Future<void> open() async {
    final bytes = await _load();
    if (bytes == null) return;
    await _openBytes(bytes);
  }

  Future<File> _saveTemp(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final safe = doc.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openBytes(Uint8List bytes) async {
    try {
      final file = await _saveTemp(bytes);
      final res = await OpenFilex.open(file.path, type: 'application/pdf');
      if (res.type != ResultType.done && context.mounted) {
        showMessage(context, 'No PDF app on this phone. Use Share PDF instead.', error: true);
      }
    } catch (e) {
      debugPrint('open pdf failed: $e');
      if (context.mounted) showMessage(context, 'Could not open the PDF on this phone.', error: true);
    }
  }

  /// Sheet with everything you can do with the document.
  static Future<void> show(BuildContext context, ServerDocument doc, {VoidCallback? onWhatsApp, String? whatsAppLabel}) async {
    final actions = DocumentActions(context, doc);
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (doc.title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(doc.title!, style: Theme.of(c).textTheme.titleMedium),
              ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Print'),
              subtitle: const Text('Any printer on the same Wi-Fi, or "Save as PDF"'),
              onTap: () {
                Navigator.pop(c);
                actions.print_();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share PDF'),
              subtitle: const Text('WhatsApp, email, Drive, Files…'),
              onTap: () {
                Navigator.pop(c);
                actions.share();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Open PDF'),
              onTap: () {
                Navigator.pop(c);
                actions.open();
              },
            ),
            if (onWhatsApp != null)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(whatsAppLabel ?? 'Send on WhatsApp with a link'),
                subtitle: const Text('Message with a secure link the resident can open'),
                onTap: () {
                  Navigator.pop(c);
                  onWhatsApp();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Row of buttons for a screen that has one document.
class DocumentActionBar extends StatelessWidget {
  const DocumentActionBar({super.key, required this.doc, this.onWhatsApp});

  final ServerDocument doc;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final a = DocumentActions(context, doc);
    // Two rows so labels never wrap ("Share\nPDF", "Whats\nApp") on narrow phones.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onWhatsApp != null) ...[
          FilledButton.icon(
            icon: const Icon(Icons.chat_outlined, size: 20),
            label: const Text('Send on WhatsApp', maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: onWhatsApp,
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined, size: 20),
                label: const Text('Print', maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: a.print_,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.ios_share, size: 20),
                label: const Text('Share PDF', maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: a.share,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens a link, and never fails silently: if no app can handle it, the text is shared instead.
Future<void> openLinkOrShare(BuildContext context, Uri uri, {String? shareText}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // falls through to the share sheet below
  }
  try {
    await SharePlus.instance.share(ShareParams(text: shareText ?? uri.toString()));
  } catch (e) {
    debugPrint('share text failed: $e');
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open WhatsApp. Is WhatsApp installed? The message was not sent.')));
  }
}

/// WhatsApp with the message ready. Tries WhatsApp directly, then the browser, then the share sheet.
Future<void> sendWhatsApp(BuildContext context, String? phone, String text) async {
  var digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) digits = '92${digits.substring(1)}';
  final encoded = Uri.encodeComponent(text);
  final candidates = [
    if (digits.length >= 11) Uri.parse('whatsapp://send?phone=$digits&text=$encoded'),
    Uri.parse('https://wa.me/${digits.length >= 11 ? digits : ''}?text=$encoded'),
  ];
  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // try the next one
    }
  }
  if (!context.mounted) return;
  await openLinkOrShare(context, candidates.last, shareText: text);
}
