import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/pickers.dart';
import 'resident_form_screen.dart';
import 'meters_screen.dart';
import 'resident_tabs.dart';

class ResidentDetailScreen extends StatefulWidget {
  const ResidentDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<ResidentDetailScreen> createState() => _ResidentDetailScreenState();
}

class _ResidentDetailScreenState extends State<ResidentDetailScreen> {
  Json? _data;
  ApiException? _error;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await apiOf(context).get('residents/${widget.id}');
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
          _version++;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorView(message: _error!.message, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final d = _data!;
    final r = Map<String, dynamic>.from(d['resident'] as Map);
    final archived = r['is_archived'] == true;
    final tabs = <(String, Widget)>[
      ('Profile', ProfileTab(data: d, onChanged: _load, key: ValueKey('p$_version'))),
      if (s.can('rooms.view')) ('Room', RoomTab(residentId: widget.id, onChanged: _load, key: ValueKey('r$_version'))),
      if (s.can('accounts.view')) ('Account', LedgerTab(resident: r, onChanged: _load, key: ValueKey('l$_version'))),
      if (s.can('documents.view')) ('Documents', DocumentsTab(residentId: widget.id, onChanged: _load, key: ValueKey('d$_version'))),
      if (s.can('medical.view')) ('Medical', MedicalTab(residentId: widget.id, archived: archived, key: ValueKey('m$_version'))),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              title: Text('${r['name']}', overflow: TextOverflow.ellipsis),
              actions: [_menu(context, s, d, r)],
            ),
            SliverToBoxAdapter(
              child: _Header(r: r, balance: d['balance'] as Map?, onPhoto: s.can('residents.edit') && !archived ? () => _changePhoto(r) : null),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in tabs) Tab(text: t.$1)],
                ),
                Theme.of(context).colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(children: [for (final t in tabs) t.$2]),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, Session s, Json d, Json r) {
    final archived = r['is_archived'] == true;
    final phone = '${r['phone'] ?? ''}';
    return PopupMenuButton<String>(
      onSelected: (v) => _action(v, d, r),
      itemBuilder: (_) => [
        if (phone.isNotEmpty)
          const PopupMenuItem(
            value: 'call',
            child: ListTile(leading: Icon(Icons.call_outlined), title: Text('Call')),
          ),
        if (phone.isNotEmpty)
          const PopupMenuItem(
            value: 'whatsapp',
            child: ListTile(leading: Icon(Icons.chat_outlined), title: Text('WhatsApp')),
          ),
        if (s.can('residents.edit') && !archived)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit details')),
          ),
        if (s.can('residents.edit') && !archived)
          const PopupMenuItem(
            value: 'status',
            child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Change status')),
          ),
        if (s.can('portal.manage') && d['portal'] != null)
          const PopupMenuItem(
            value: 'portal',
            child: ListTile(leading: Icon(Icons.phone_iphone), title: Text('Portal login')),
          ),
        if (s.can('residents.archive'))
          PopupMenuItem(
            value: archived ? 'restore' : 'archive',
            child: ListTile(leading: const Icon(Icons.archive_outlined), title: Text(archived ? 'Restore' : 'Archive')),
          ),
        if (s.canPurge)
          const PopupMenuItem(
            value: 'purge',
            child: ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: kBad),
              title: Text('Delete permanently', style: TextStyle(color: kBad)),
            ),
          ),
      ],
    );
  }

  Future<void> _action(String action, Json d, Json r) async {
    final api = apiOf(context);
    final id = widget.id;
    switch (action) {
      case 'call':
        await callPhone(context, '${r['phone']}');
      case 'whatsapp':
        await openWhatsApp(context, '${r['phone']}', 'Assalam o Alaikum ${'${r['name']}'.split(' ').first},\n');
      case 'statement':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => StatementScreen(resident: r)));
      case 'remind':
        await ShareSheet.open(context, type: 'reminder', resident: r);
      case 'edit':
        final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ResidentFormScreen(existing: d)));
        if (changed == true) _load();
      case 'status':
        final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => StatusSheet(residentId: id, current: r, next: [for (final x in (d['next_statuses'] as List)) '$x']),
        );
        if (ok == true) _load();
      case 'portal':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => PortalSheet(resident: r, portal: Map<String, dynamic>.from(d['portal'] as Map)),
        );
        _load();
      case 'archive':
        final reason = await askText(context, 'Archive ${r['name']}?', label: 'Reason for archiving', ok: 'Archive', danger: true);
        if (reason == null || !mounted) return;
        final res = await runTask(context, () => api.post('residents/$id/archive', {'action': 'archive', 'reason': reason}), success: 'Resident archived.');
        if (res != null) _load();
      case 'purge':
        final deleted = await showDialog<bool>(
          context: context,
          builder: (_) => PurgeResidentDialog(residentId: id),
        );
        if (deleted == true && mounted) Navigator.pop(context);
      case 'restore':
        if (!await confirm(context, 'Restore ${r['name']}?', 'The resident moves back to the current list.', ok: 'Restore') || !mounted) return;
        final res = await runTask(context, () => api.post('residents/$id/archive', {'action': 'restore'}), success: 'Resident restored.');
        if (res != null) _load();
    }
  }

  Future<void> _changePhoto(Json r) async {
    final files = await pickUploads(context, field: 'photo', allowFiles: false, imagesOnly: true, title: 'Profile photo', maxWidth: 1200);
    if (files.isEmpty || !mounted) return;
    final api = apiOf(context);
    final res = await runTask(context, () => api.upload('residents/${widget.id}/photo', files: files), success: 'Photo updated.');
    if (res != null) {
      PaintingBinding.instance.imageCache.clear();
      _load();
    }
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.color);

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Material(color: color, elevation: overlapsContent ? 1 : 0, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar || old.color != color;
}

class _Header extends StatelessWidget {
  const _Header({required this.r, this.balance, this.onPhoto});

  final Json r;
  final Map? balance;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final bal = balance == null ? null : toDouble(balance!['balance']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onPhoto,
            child: Stack(
              children: [
                ResidentAvatar(id: toInt(r['id']), name: '${r['name']}', hasPhoto: r['has_photo'] == true, radius: 28),
                if (onPhoto != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text([r['code'], if (r['room_number'] != null) 'Room ${r['room_number']}/${r['bed_label']}'].join(' · ')),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (r['is_archived'] == true) const StatusChip('Archived', tone: 'archived'),
                    StatusChip(s.label('admission_statuses', r['admission_status']), tone: '${r['admission_status']}'),
                    StatusChip(
                      'Verification: ${s.label('verification_statuses', r['verification_status']).toLowerCase()}',
                      tone: '${r['verification_status']}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (bal != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(bal > 0.009 ? 'Due' : (bal < -0.009 ? 'Credit' : 'Balance'), style: Theme.of(context).textTheme.bodySmall),
                Text(
                  bal.abs() < 0.01 ? 'Clear' : money(bal.abs()),
                  style: TextStyle(fontWeight: FontWeight.w800, color: bal > 0.009 ? kBad : (bal < -0.009 ? kInfo : kOk)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.data, required this.onChanged});

  final Json data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final r = data['resident'] as Map;
    final contacts = data['contacts'] as Map;
    final checklist = (data['checklist'] as List).cast<Map>();
    final medical = data['medical'] as Map?;
    final balance = data['balance'] as Map?;
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          if (r['is_archived'] == true && r['archived_reason'] != null)
            SectionCard(
              child: Text('Archived: ${r['archived_reason']}', style: const TextStyle(color: kMuted)),
            ),
          if (medical != null && (medical['ac_sensitivity'] != 'none' || medical['has_allergies'] == true))
            Card(
              color: kBad.withValues(alpha: 0.08),
              child: ListTile(
                leading: const Icon(Icons.health_and_safety_outlined, color: kBad),
                title: Text(
                  [
                    if (medical['ac_sensitivity'] != 'none') s.label('ac_sensitivity', medical['ac_sensitivity']),
                    if (medical['has_allergies'] == true) 'Has allergies',
                    if (medical['blood_group'] != null) 'Blood ${medical['blood_group']}',
                  ].join(' · '),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Personal',
            child: InfoRows([
              ('Father / husband', orDash(r['father_name'])),
              ('Gender', s.label('genders', r['gender'])),
              ('Date of birth', fmtDate(r['date_of_birth'])),
              ('CNIC', orDash(r['cnic'])),
              ('Phone', orDash(r['phone'])),
              ('Alternate phone', orDash(r['alt_phone'])),
              ('Email', orDash(r['email'])),
              ('City', orDash(r['city'])),
              ('Address', orDash(r['permanent_address'])),
            ]),
          ),
          SectionCard(
            title: 'Occupation and admission',
            child: InfoRows([
              ('Occupation', s.label('occupations', r['occupation'])),
              ('Institution / employer', orDash(r['organization'])),
              ('Course / designation', orDash(r['designation_or_course'])),
              ('Institution address', orDash(r['organization_address'])),
              ('Admission date', fmtDate(r['admission_date'])),
              ('Expected to leave', fmtDate(r['expected_leave_date'])),
              if (balance != null) ('Monthly rent', balance['monthly_rent'] == null ? '—' : money(balance['monthly_rent'])),
              if (r['security_deposit_amount'] != null) ('Deposit agreed', money(r['security_deposit_amount'])),
              if (balance != null) ('Deposit held', money(balance['deposit_held'])),
            ]),
          ),
          SectionCard(
            title: 'Family and emergency',
            child: contacts.isEmpty
                ? const Text('No contacts recorded.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final type in ['father', 'guardian', 'emergency'])
                        for (final c in ((contacts[type] as List?) ?? const []).cast<Map>())
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${c['name']}'),
                            subtitle: Text(
                              [
                                s.label('contact_types', type) + (c['relation'] != null ? ' · ${c['relation']}' : ''),
                                if (c['phone'] != null) '${c['phone']}',
                                if (c['cnic'] != null) 'CNIC ${c['cnic']}',
                                if (c['address'] != null) '${c['address']}',
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: c['phone'] != null
                                ? IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => callPhone(context, '${c['phone']}'))
                                : null,
                          ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Documents checklist',
            child: Column(
              children: [
                for (final c in checklist)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      c['verified'] == true ? Icons.check_circle : (c['uploaded'] == true ? Icons.schedule : Icons.error_outline),
                      color: c['verified'] == true ? kOk : (c['uploaded'] == true ? kWarn : kBad),
                    ),
                    title: Text('${c['label']}'),
                    trailing: Text(c['verified'] == true ? 'Verified' : (c['uploaded'] == true ? 'Received' : 'Missing')),
                  ),
              ],
            ),
          ),
          if ('${r['notes'] ?? ''}'.isNotEmpty) SectionCard(title: 'Internal notes', child: Text('${r['notes']}')),
          Text('Added ${fmtDateTime(r['created_at'])}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Admission and verification status change.
class StatusSheet extends StatefulWidget {
  const StatusSheet({super.key, required this.residentId, required this.current, required this.next});

  final int residentId;
  final Json current;
  final List<String> next;

  @override
  State<StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<StatusSheet> {
  late String _admission = '${widget.current['admission_status']}';
  late String _verification = '${widget.current['verification_status']}';
  final _note = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final current = '${widget.current['admission_status']}';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Change status', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ChoiceInput(
            label: 'Admission',
            value: _admission,
            choices: [
              Choice(current, '${s.label('admission_statuses', current)} (current)'),
              for (final n in widget.next) Choice(n, s.label('admission_statuses', n)),
            ],
            onChanged: (v) => setState(() => _admission = v ?? current),
            helper: 'Admission completes automatically when a bed is assigned to an approved resident.',
          ),
          ChoiceInput(
            label: 'Verification',
            value: _verification,
            choices: [for (final o in s.options('verification_statuses')) Choice('${o['value']}', '${o['label']}')],
            onChanged: (v) => setState(() => _verification = v ?? _verification),
          ),
          AppTextField(controller: _note, label: 'Note (optional)', maxLength: 255),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: kBad)),
            ),
          FilledButton(
            onPressed: () async {
              final api = apiOf(context);
              final nav = Navigator.of(context);
              try {
                await api.post('residents/${widget.residentId}/status', {
                  'admission_status': _admission == current ? '' : _admission,
                  'verification_status': _verification,
                  'note': _note.text.trim(),
                });
                nav.pop(true);
              } on ApiException catch (e) {
                setState(() => _error = e.message);
              }
            },
            child: const Text('Save status'),
          ),
        ],
      ),
    );
  }
}

/// Create/reset/turn off the resident's portal login. The temporary password is shown once.
class PortalSheet extends StatefulWidget {
  const PortalSheet({super.key, required this.resident, required this.portal});

  final Json resident;
  final Json portal;

  @override
  State<PortalSheet> createState() => _PortalSheetState();
}

class _PortalSheetState extends State<PortalSheet> {
  late Json _portal = widget.portal;
  Json? _issued;

  Future<void> _do(String action) async {
    final api = apiOf(context);
    final id = widget.resident['id'];
    if (action == 'issue' && _portal['has_login'] == true) {
      if (!await confirm(context, 'Reset password?', 'The old password stops working and the resident is signed out of the app.', ok: 'Reset')) return;
    }
    if (!mounted) return;
    final res = await runTask(context, () => api.post('residents/$id/portal', {'action': action}));
    if (res == null || !mounted) return;
    setState(() {
      if (action == 'issue') {
        _issued = res;
        _portal = {..._portal, 'has_login': true, 'active': true, 'must_change_password': true};
      } else {
        _portal = {..._portal, 'active': action == 'enable'};
        showMessage(context, '${res['message']}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _portal;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Resident portal', style: t.titleLarge),
            const SizedBox(height: 8),
            if (p['enabled'] != true)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'The portal is switched off on the website (Admin to Resident portal). Logins you create work once it is on.',
                  style: TextStyle(color: kWarn),
                ),
              ),
            if (p['eligible'] != true)
              const Text('Only approved or admitted residents can have a login.', style: TextStyle(color: kBad))
            else ...[
              InfoRows([
                ('Resident ID', '${p['login_id']}'),
                (
                  'Login',
                  p['has_login'] != true ? 'Not created' : (p['active'] != true ? 'Off' : (p['must_change_password'] == true ? 'Not used yet' : 'Active')),
                ),
                ('Last sign-in', p['last_login_at'] == null ? 'Never' : fmtDateTime(p['last_login_at'])),
              ]),
              if (_issued != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: kWarn.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Share now. This password is shown only once.', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${_issued!['password']}',
                          style: t.headlineSmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: '${_issued!['share_message']}'));
                                  showMessage(context, 'Message copied.');
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.send),
                                label: const Text('WhatsApp'),
                                onPressed: () => openWhatsApp(context, '${widget.resident['phone'] ?? ''}', '${_issued!['share_message']}'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: () => _do('issue'), child: Text(p['has_login'] == true ? 'Reset password' : 'Create login')),
              if (p['has_login'] == true) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _do(p['active'] == true ? 'disable' : 'enable'),
                  child: Text(p['active'] == true ? 'Turn login off' : 'Turn login on'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Super Admin: shows what will be removed and asks for the Resident ID before deleting everything.
class PurgeResidentDialog extends StatefulWidget {
  const PurgeResidentDialog({super.key, required this.residentId});

  final int residentId;

  @override
  State<PurgeResidentDialog> createState() => _PurgeResidentDialogState();
}

class _PurgeResidentDialogState extends State<PurgeResidentDialog> {
  final _code = TextEditingController();
  final _reason = TextEditingController();
  Json? _preview;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    apiOf(context)
        .get('residents/${widget.residentId}/purge')
        .then(
          (d) {
            if (mounted) setState(() => _preview = d);
          },
          onError: (Object e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final c = p == null ? null : p['counts'] as Map;
    final code = '${p?['resident_code'] ?? ''}';
    final ready = p != null && _code.text.trim().toUpperCase() == code.toUpperCase() && _reason.text.trim().isNotEmpty;
    return AlertDialog(
      icon: const Icon(Icons.delete_forever_outlined, color: kBad, size: 36),
      title: const Text('Delete permanently?'),
      content: SingleChildScrollView(
        child: p == null
            ? (_error != null
                  ? Text(_error!, style: const TextStyle(color: kBad))
                  : const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${p['name']} ($code) and everything linked will be removed:'),
                  const SizedBox(height: 8),
                  Text(
                    '• ${c!['ledger_entries']} ledger entries (${c['receipts']} receipts)\n'
                    '• ${c['documents']} documents and the photo\n'
                    '• ${c['contacts']} contacts, ${c['room_history']} room records'
                    '${toInt(c['medical']) > 0 ? '\n• Medical profile' : ''}${toInt(c['portal_login']) > 0 ? '\n• Portal login' : ''}',
                  ),
                  const SizedBox(height: 8),
                  const Text('This cannot be undone. The server takes a backup first.', style: TextStyle(color: kBad)),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _code,
                    label: 'Type $code to confirm',
                    capitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                  ),
                  AppTextField(controller: _reason, label: 'Reason', hint: 'e.g. Test entry', maxLength: 255, onChanged: (_) => setState(() {})),
                  if (_error != null) Text(_error!, style: const TextStyle(color: kBad)),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kBad),
          onPressed: !ready || _busy
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    final res = await apiOf(context)
                        .post('residents/${widget.residentId}/purge', {'confirm_code': _code.text.trim(), 'reason': _reason.text.trim()});
                    messenger.showSnackBar(SnackBar(content: Text('${res['message']}')));
                    nav.pop(true);
                  } on ApiException catch (e) {
                    setState(() {
                      _busy = false;
                      _error = e.message;
                    });
                  }
                },
          child: Text(_busy ? 'Deleting…' : 'Delete'),
        ),
      ],
    );
  }
}
