import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/lists.dart';
import '../../widgets/pickers.dart';
import 'ledger_entry_screen.dart';

/* ---------- Room ---------- */

class RoomTab extends StatefulWidget {
  const RoomTab({super.key, required this.residentId, required this.onChanged});

  final int residentId;
  final VoidCallback onChanged;

  @override
  State<RoomTab> createState() => _RoomTabState();
}

class _RoomTabState extends State<RoomTab> {
  final _key = GlobalKey<LoadViewState>();

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return LoadView(
      key: _key,
      load: () => api.get('residents/${widget.residentId}/room'),
      builder: (context, d, reload) {
        final cur = d['current'] as Map?;
        final history = (d['history'] as List).cast<Map>();
        final canAssign = d['can_assign'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d['ac_sensitivity'] != null && d['ac_sensitivity'] != 'none')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StatusChip(context.read<Session>().label('ac_sensitivity', d['ac_sensitivity']), tone: '${d['ac_sensitivity']}'),
              ),
            SectionCard(
              title: 'Current bed',
              child: cur == null
                  ? const Text('No bed assigned.')
                  : InfoRows([
                      ('Room', '${cur['room_number']}'),
                      ('Bed', '${cur['bed_label']}'),
                      ('Type', '${cur['room_type']}'),
                      ('Since', fmtDate(cur['start_date'])),
                      if (cur['monthly_rent'] != null) ('Room rent', money(cur['monthly_rent'])),
                    ]),
            ),
            if (canAssign) ...[
              FilledButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: Text(cur == null ? 'Assign a bed' : 'Transfer to another bed'),
                onPressed: () => _assign(reload),
              ),
              if (cur != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(icon: const Icon(Icons.logout), label: const Text('Vacate bed'), onPressed: () => _vacate(reload)),
              ],
              const SizedBox(height: 12),
            ] else if (context.read<Session>().can('assignments.manage'))
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Approve the admission before assigning a bed.', style: TextStyle(color: kMuted)),
              ),
            SectionCard(
              title: 'History',
              padding: const EdgeInsets.only(bottom: 8),
              child: history.isEmpty
                  ? const EmptyView('No beds yet.')
                  : Column(
                      children: [
                        for (final h in history)
                          ListTile(
                            leading: const Icon(Icons.bed_outlined),
                            title: Text('Room ${h['room_number']} · Bed ${h['bed_label']} (${h['room_type']})'),
                            subtitle: Text(
                              [
                                '${fmtDate(h['start_date'])} – ${h['end_date'] == null ? 'now' : fmtDate(h['end_date'])}',
                                if (h['reason'] != null) '${h['reason']}',
                                if (h['by'] != null) 'by ${h['by']}',
                              ].join('\n'),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _assign(Future<void> Function() reload) async {
    final api = apiOf(context);
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AssignSheet(residentId: widget.residentId, api: api),
    );
    if (done == true) {
      await reload();
      widget.onChanged();
    }
  }

  Future<void> _vacate(Future<void> Function() reload) async {
    final api = apiOf(context);
    final reason = await askText(context, 'Vacate bed', label: 'Reason (optional)', ok: 'Vacate', required: false, danger: true);
    if (reason == null || !mounted) return;
    final res = await runTask(
      context,
      () => api.post('residents/${widget.residentId}/room', {'action': 'vacate', 'date': today(), 'reason': reason}),
      success: 'Bed vacated.',
    );
    if (res != null) {
      await reload();
      widget.onChanged();
    }
  }
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.residentId, required this.api});

  final int residentId;
  final Api api;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  int? _bed;
  String _date = today();
  final _reason = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: LoadView(
          scroll: false,
          load: () => widget.api.get('beds/available'),
          builder: (context, d, _) {
            final beds = (d['beds'] as List).cast<Map>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Choose a bed', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Expanded(
                  child: beds.isEmpty
                      ? const EmptyView('No vacant beds. Add a room or vacate a bed first.')
                      : RadioGroup<int>(
                          groupValue: _bed,
                          onChanged: (v) => setState(() => _bed = v),
                          child: ListView(
                            children: [
                              for (final b in beds)
                                RadioListTile<int>(
                                  value: toInt(b['bed_id']),
                                  title: Text('Room ${b['room_number']} · Bed ${b['bed_label']}'),
                                  subtitle: Text(
                                    [
                                      '${b['room_type']}',
                                      if (b['floor'] != null) 'Floor ${b['floor']}',
                                      if (b['monthly_rent'] != null) money(b['monthly_rent']),
                                    ].join(' · '),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                DateInput(label: 'Start date', value: _date, required: true, onChanged: (v) => setState(() => _date = v ?? today())),
                AppTextField(controller: _reason, label: 'Reason / note', maxLength: 255),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: const TextStyle(color: kBad)),
                  ),
                FilledButton(
                  onPressed: _bed == null
                      ? null
                      : () async {
                          final nav = Navigator.of(context);
                          try {
                            await widget.api.post('residents/${widget.residentId}/room', {
                              'action': 'assign',
                              'bed_id': _bed,
                              'date': _date,
                              'reason': _reason.text.trim(),
                            });
                            nav.pop(true);
                          } on ApiException catch (e) {
                            setState(() => _error = e.errors.isNotEmpty ? e.errors.values.join(' ') : e.message);
                          }
                        },
                  child: const Text('Assign bed'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/* ---------- Ledger ---------- */

class LedgerTab extends StatefulWidget {
  const LedgerTab({super.key, required this.resident, required this.onChanged});

  final Json resident;
  final VoidCallback onChanged;

  @override
  State<LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<LedgerTab> {
  bool _showVoid = false;
  final _key = GlobalKey<LoadViewState>();

  int get _id => toInt(widget.resident['id']);

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      floatingActionButton: context.read<Session>().can('accounts.manage')
          ? FloatingActionButton.extended(
              heroTag: 'ledger',
              icon: const Icon(Icons.add),
              label: const Text('Record entry'),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerEntryScreen(resident: widget.resident)));
                await _key.currentState?.reload();
                widget.onChanged();
              },
            )
          : null,
      body: LoadView(
        key: _key,
        load: () => api.get('residents/$_id/ledger', query: {'void': _showVoid ? '1' : null}),
        builder: (context, d, reload) {
          final b = d['balance'] as Map;
          final bal = toDouble(b['balance']);
          final entries = (d['entries'] as List).cast<Map>();
          final canVoid = d['can_void'] == true;
          final canPurge = context.read<Session>().canPurge;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatGrid([
                StatTile(
                  label: bal < -0.009 ? 'Advance credit' : 'Balance due',
                  value: money(bal.abs()),
                  color: bal > 0.009 ? kBad : (bal < -0.009 ? kInfo : kOk),
                ),
                StatTile(label: 'Deposit held', value: money(b['deposit_held'])),
                StatTile(label: 'Monthly rent', value: b['monthly_rent'] == null ? '—' : money(b['monthly_rent'])),
                StatTile(label: 'Total paid & credited', value: money(b['total_credited']), sub: 'charged ${money(b['total_charged'])}'),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show voided entries'),
                value: _showVoid,
                onChanged: (v) {
                  setState(() => _showVoid = v);
                  _key.currentState?.reload();
                },
              ),
              if (canVoid || canPurge)
                Text(canPurge ? 'Long-press an entry to void or delete it.' : 'Long-press an entry to void it.', style: const TextStyle(color: kMuted)),
              const SizedBox(height: 8),
              Card(
                child: entries.isEmpty
                    ? const EmptyView('No entries yet.')
                    : Column(
                        children: [
                          for (final e in entries)
                            LedgerTile(
                              Map<String, dynamic>.from(e),
                              phone: '${widget.resident['phone'] ?? ''}',
                              onLongPress: (canVoid && e['is_void'] != true) || canPurge
                                  ? () => _entryActions(Map<String, dynamic>.from(e), reload, canVoid: canVoid && e['is_void'] != true, canPurge: canPurge)
                                  : null,
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _entryActions(Json e, Future<void> Function() reload, {required bool canVoid, required bool canPurge}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('${e['type_label']} · ${money(toDouble(e['debit']) + toDouble(e['credit']))}'), subtitle: Text(fmtDate(e['date']))),
            if (canVoid)
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Void'),
                subtitle: const Text('Keeps it on record, struck through'),
                onTap: () => Navigator.pop(c, 'void'),
              ),
            if (canPurge)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: kBad),
                title: const Text('Delete permanently', style: TextStyle(color: kBad)),
                subtitle: const Text('For test data. Removes it completely.'),
                onTap: () => Navigator.pop(c, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'void') return _void(e, reload);
    final api = apiOf(context);
    final reason = await askText(context, 'Delete this entry permanently?', label: 'Reason', ok: 'Delete', danger: true);
    if (reason == null || !mounted) return;
    final res = await runTask(context, () => api.post('ledger/${e['id']}/delete', {'reason': reason}), success: 'Entry deleted.');
    if (res != null) {
      await reload();
      widget.onChanged();
    }
  }

  Future<void> _void(Json e, Future<void> Function() reload) async {
    final api = apiOf(context);
    final reason = await askText(context, 'Void ${e['type_label']} of ${money(toDouble(e['debit']) + toDouble(e['credit']))}?', ok: 'Void', danger: true);
    if (reason == null || !mounted) return;
    final res = await runTask(context, () => api.post('ledger/${e['id']}/void', {'reason': reason}), success: 'Entry voided.');
    if (res != null) {
      await reload();
      widget.onChanged();
    }
  }
}

/* ---------- Documents ---------- */

class DocumentsTab extends StatefulWidget {
  const DocumentsTab({super.key, required this.residentId, required this.onChanged});

  final int residentId;
  final VoidCallback onChanged;

  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  final _key = GlobalKey<LoadViewState>();
  Json? _last;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final s = context.read<Session>();
    return Scaffold(
      floatingActionButton: s.can('documents.upload')
          ? FloatingActionButton.extended(
              heroTag: 'docs',
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload'),
              onPressed: () async {
                final types = [
                  for (final t in ((_last?['upload_types'] as List?) ?? const ['admission_form', 'cnic', 'police_verification', 'other'])) '$t',
                ];
                final ok = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => UploadSheet(residentId: widget.residentId, types: types, api: api),
                );
                if (ok == true) {
                  await _key.currentState?.reload();
                  widget.onChanged();
                }
              },
            )
          : null,
      body: LoadView(
        key: _key,
        load: () async => _last = await api.get('residents/${widget.residentId}/documents'),
        builder: (context, d, reload) {
          final docs = (d['documents'] as List).cast<Map>();
          final hidden = toInt(d['hidden_sensitive']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in (d['checklist'] as List).cast<Map>())
                    Chip(
                      avatar: Icon(
                        c['verified'] == true ? Icons.check_circle : (c['uploaded'] == true ? Icons.schedule : Icons.error_outline),
                        size: 18,
                        color: c['verified'] == true ? kOk : (c['uploaded'] == true ? kWarn : kBad),
                      ),
                      label: Text('${c['label']}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('$hidden medical document(s) hidden for your role.', style: const TextStyle(color: kMuted)),
                ),
              Card(
                child: docs.isEmpty
                    ? const EmptyView('No documents uploaded yet.', icon: Icons.folder_open)
                    : Column(
                        children: [
                          for (final doc in docs)
                            ListTile(
                              leading: Icon(doc['mime'] == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                              title: Text('${doc['title']}'),
                              subtitle: Text('${doc['type_label']} · ${humanSize(toInt(doc['size']))} · ${fmtDate(doc['uploaded_at'])}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusChip('${doc['status']}'[0].toUpperCase() + '${doc['status']}'.substring(1), tone: '${doc['status']}'),
                                  _docMenu(Map<String, dynamic>.from(doc), d, reload),
                                ],
                              ),
                              onTap: () => downloadAndOpen(context, 'documents/${doc['id']}/file', '${doc['name']}'),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _docMenu(Json doc, Json d, Future<void> Function() reload) {
    final api = apiOf(context);
    return PopupMenuButton<String>(
      onSelected: (a) async {
        String? reason = '';
        if (a == 'reject' || a == 'delete') {
          reason = await askText(context, a == 'reject' ? 'Reject document' : 'Delete document', ok: a == 'reject' ? 'Reject' : 'Delete', danger: true);
          if (reason == null) return;
        }
        if (!mounted) return;
        final res = await runTask(context, () => api.post('documents/${doc['id']}/action', {'action': a, 'reason': reason}));
        if (res != null) {
          if (mounted) showMessage(context, '${res['message']}');
          await reload();
          widget.onChanged();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', enabled: false, child: Text('Tap the row to open')),
        if (d['can_upload'] == true && doc['status'] != 'verified') const PopupMenuItem(value: 'verify', child: Text('Mark verified')),
        if (d['can_upload'] == true && doc['status'] != 'rejected') const PopupMenuItem(value: 'reject', child: Text('Reject')),
        if (d['can_delete'] == true)
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: kBad)),
          ),
      ],
    );
  }
}

class UploadSheet extends StatefulWidget {
  const UploadSheet({super.key, required this.residentId, required this.types, required this.api});

  final int residentId;
  final List<String> types;
  final Api api;

  @override
  State<UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<UploadSheet> {
  late String _type = widget.types.first;
  String _status = 'received';
  final _title = TextEditingController();
  final _files = <UploadFile>[];
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final picked = await pickUploads(context, field: 'files[]', multiple: true, title: 'Add document');
    if (picked.isEmpty) return;
    setState(() {
      _files.addAll(picked);
      if (_files.length > 10) _files.removeRange(10, _files.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload documents', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ChoiceInput(
              label: 'Document type',
              value: _type,
              required: true,
              choices: [for (final t in widget.types) Choice(t, s.label('doc_types', t))],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            AppTextField(controller: _title, label: 'Title (optional)', maxLength: 160),
            ChoiceInput(
              label: 'Status',
              value: _status,
              choices: const [Choice('received', 'Received'), Choice('verified', 'Verified (checked against original)')],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_files.isEmpty ? 'Choose files (gallery, camera or PDF)' : 'Add more'),
              onPressed: _files.length >= 10 ? null : _add,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _files.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: isImageName(_files[i].filename)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(_files[i].bytes, width: 40, height: 40, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                title: Text(_files[i].filename, overflow: TextOverflow.ellipsis),
                subtitle: Text(humanSize(_files[i].bytes.length)),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _files.removeAt(i))),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(color: kBad)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _files.isEmpty || _busy
                  ? null
                  : () async {
                      final nav = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        final res = await widget.api.upload(
                          'residents/${widget.residentId}/documents',
                          fields: {'doc_type': _type, 'status': _status, 'title': _title.text.trim()},
                          files: _files,
                        );
                        messenger.showSnackBar(SnackBar(content: Text('${res['message']}')));
                        nav.pop(true);
                      } on ApiException catch (e) {
                        setState(() => _error = e.errors.isNotEmpty ? e.errors.values.join('\n') : e.message);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text(_busy ? 'Uploading…' : 'Upload ${_files.isEmpty ? '' : '${_files.length} file${_files.length > 1 ? 's' : ''}'}'),
            ),
            const SizedBox(height: 4),
            const Text(
              'JPG, PNG, WebP or PDF, up to 10 files. Files are stored encrypted.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------- Medical ---------- */

class MedicalTab extends StatefulWidget {
  const MedicalTab({super.key, required this.residentId, required this.archived});

  final int residentId;
  final bool archived;

  @override
  State<MedicalTab> createState() => _MedicalTabState();
}

class _MedicalTabState extends State<MedicalTab> {
  final _key = GlobalKey<LoadViewState>();

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final s = context.read<Session>();
    return LoadView(
      key: _key,
      load: () => api.get('residents/${widget.residentId}/medical'),
      builder: (context, d, reload) {
        final m = Map<String, dynamic>.from(d['medical'] as Map);
        final canEdit = d['can_edit'] == true && !widget.archived;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: kBad.withValues(alpha: 0.06),
              child: const ListTile(
                leading: Icon(Icons.shield_outlined, color: kBad),
                title: Text('Confidential. Stored encrypted and every view is logged.'),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Medical profile',
              child: InfoRows([
                ('Blood group', orDash(m['blood_group'])),
                ('AC sensitivity', s.label('ac_sensitivity', m['ac_sensitivity'])),
                ('AC notes', orDash(m['ac_notes'])),
                ('Health issues', orDash(m['health_issues'])),
                ('Allergies', orDash(m['allergies'])),
                ('Medications', orDash(m['medications'])),
                ('Emergency notes', orDash(m['emergency_notes'])),
                ('Family doctor', [m['doctor_name'], m['doctor_phone']].where((x) => x != null && '$x'.isNotEmpty).join(' · ').ifEmpty('—')),
                (
                  'Last updated',
                  m['updated_at'] == null ? 'Never' : '${fmtDateTime(m['updated_at'])}${m['updated_by'] != null ? ' by ${m['updated_by']}' : ''}',
                ),
              ]),
            ),
            if (canEdit)
              FilledButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit medical information'),
                onPressed: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MedicalForm(residentId: widget.residentId, medical: m),
                    ),
                  );
                  if (ok == true) reload();
                },
              ),
          ],
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class MedicalForm extends StatefulWidget {
  const MedicalForm({super.key, required this.residentId, required this.medical});

  final int residentId;
  final Json medical;

  @override
  State<MedicalForm> createState() => _MedicalFormState();
}

class _MedicalFormState extends State<MedicalForm> {
  late String? _blood = widget.medical['blood_group'] as String?;
  late String _ac = '${widget.medical['ac_sensitivity'] ?? 'none'}';
  late final Map<String, TextEditingController> _c = {
    for (final k in ['health_issues', 'allergies', 'medications', 'ac_notes', 'emergency_notes', 'doctor_name', 'doctor_phone'])
      k: TextEditingController(text: '${widget.medical[k] ?? ''}'),
  };
  Map<String, String> _errors = {};
  final _tracker = DirtyTracker();

  List<Object?> _values() => [_blood, _ac, for (final c in _c.values) c.text];

  @override
  void initState() {
    super.initState();
    _tracker.start(_values());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return UnsavedGuard(
      isDirty: () => _tracker.isDirty(_values()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Medical information')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ChoiceInput(
              label: 'Blood group',
              value: _blood,
              allowEmpty: true,
              choices: [for (final b in (s.constants['blood_groups'] as List? ?? const [])) Choice('$b', '$b')],
              onChanged: (v) => setState(() => _blood = v),
              error: _errors['blood_group'],
            ),
            ChoiceInput(
              label: 'AC sensitivity',
              value: _ac,
              required: true,
              choices: [for (final o in s.options('ac_sensitivity')) Choice('${o['value']}', '${o['label']}')],
              onChanged: (v) => setState(() => _ac = v ?? 'none'),
              error: _errors['ac_sensitivity'],
            ),
            AppTextField(controller: _c['ac_notes']!, label: 'AC notes', maxLines: 2, maxLength: 1000, error: _errors['ac_notes']),
            AppTextField(controller: _c['health_issues']!, label: 'Health issues', maxLines: 4, maxLength: 3000, error: _errors['health_issues']),
            AppTextField(controller: _c['allergies']!, label: 'Allergies', maxLines: 3, maxLength: 2000, error: _errors['allergies']),
            AppTextField(controller: _c['medications']!, label: 'Medications', maxLines: 3, maxLength: 2000, error: _errors['medications']),
            AppTextField(controller: _c['emergency_notes']!, label: 'Emergency notes', maxLines: 4, maxLength: 3000, error: _errors['emergency_notes']),
            AppTextField(controller: _c['doctor_name']!, label: 'Family doctor', maxLength: 120, error: _errors['doctor_name']),
            AppTextField(controller: _c['doctor_phone']!, label: 'Doctor phone', keyboard: TextInputType.phone, maxLength: 20, error: _errors['doctor_phone']),
            FilledButton(
              onPressed: () async {
                final api = apiOf(context);
                final nav = Navigator.of(context);
                try {
                  await api.post('residents/${widget.residentId}/medical', {
                    'blood_group': _blood ?? '',
                    'ac_sensitivity': _ac,
                    for (final e in _c.entries) e.key: e.value.text.trim(),
                  });
                  nav.pop(true);
                } on ApiException catch (e) {
                  setState(() => _errors = e.errors);
                  if (e.errors.isEmpty && context.mounted) showMessage(context, e.message, error: true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
