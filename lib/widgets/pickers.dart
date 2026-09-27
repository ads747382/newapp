import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import 'common.dart';

enum PickSource { camera, gallery, file }

/// One picker for photos, documents and bills: camera, gallery (one or many) or a PDF/image file.
Future<List<UploadFile>> pickUploads(
  BuildContext context, {
  required String field,
  bool multiple = false,
  bool allowFiles = true,
  bool imagesOnly = false,
  String title = 'Add from',
  int maxWidth = 2400,
}) async {
  final source = await showModalBottomSheet<PickSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(title, style: Theme.of(c).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            subtitle: multiple ? const Text('Pick one or more') : null,
            onTap: () => Navigator.pop(c, PickSource.gallery),
          ),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera'), onTap: () => Navigator.pop(c, PickSource.camera)),
          if (allowFiles && !imagesOnly)
            ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('PDF or file'), onTap: () => Navigator.pop(c, PickSource.file)),
        ],
      ),
    ),
  );
  if (source == null) return const [];
  try {
    final picker = ImagePicker();
    switch (source) {
      case PickSource.camera:
        final f = await picker.pickImage(source: ImageSource.camera, maxWidth: maxWidth.toDouble(), imageQuality: 85);
        return f == null ? const [] : [UploadFile(field: field, filename: f.name, bytes: await f.readAsBytes())];
      case PickSource.gallery:
        if (multiple) {
          final list = await picker.pickMultiImage(maxWidth: maxWidth.toDouble(), imageQuality: 85, limit: 10);
          return [for (final f in list) UploadFile(field: field, filename: f.name, bytes: await f.readAsBytes())];
        }
        final f = await picker.pickImage(source: ImageSource.gallery, maxWidth: maxWidth.toDouble(), imageQuality: 85);
        return f == null ? const [] : [UploadFile(field: field, filename: f.name, bytes: await f.readAsBytes())];
      case PickSource.file:
        final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
        final chosen = multiple ? files : files.take(1);
        return [for (final f in chosen) UploadFile(field: field, filename: f.name, bytes: await f.readAsBytes())];
    }
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not open the ${source.name}: $e', error: true);
    return const [];
  }
}

bool isImageName(String name) => RegExp(r'\.(jpe?g|png|webp|heic)$', caseSensitive: false).hasMatch(name);

/// Warns before leaving a form with unsaved changes (system back / app bar back).
class UnsavedGuard extends StatelessWidget {
  const UnsavedGuard({super.key, required this.isDirty, required this.child});

  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (!isDirty() || await confirm(context, 'Discard changes?', 'What you typed on this screen will be lost.', ok: 'Discard', danger: true)) {
          nav.pop(result);
        }
      },
      child: child,
    );
  }
}

/// Snapshot-based dirty check: pass the current values; compares with the first snapshot.
class DirtyTracker {
  String? _initial;

  void start(List<Object?> values) => _initial = values.join('\u0001');

  bool isDirty(List<Object?> values) => _initial != null && _initial != values.join('\u0001');
}
