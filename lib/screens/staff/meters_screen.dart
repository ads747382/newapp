import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/session.dart' show Session;
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import 'electricity_screen.dart' show fmtNum;
import '../../widgets/documents.dart';

/// Utility meters: add, edit, and choose which rooms are on each one.
class MetersScreen extends StatefulWidget {
  const MetersScreen({super.key});

  @override
  State<MetersScreen> createState() => _MetersScreenState();
}

class _MetersScreenState extends State<MetersScreen> {
  final _key = GlobalKey<LoadViewState>();

  Future<void> _edit([Json? meter]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => MeterFormScreen(meter: meter)));
    if (saved == true) _key.currentState?.reload();
  }

  Future<void> _rooms(Json meter) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => MeterRoomsScreen(meter: meter)));
    if (saved == true) _key.currentState?.reload();
  }

  Future<void> _showActions(Json meter) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('${meter['label']}'), subtitle: Text('No. ${meter['meter_no']}')),
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit meter'), onTap: () => Navigator.pop(c, 'edit')),
            ListTile(leading: const Icon(Icons.meeting_room_outlined), title: const Text('Rooms on this meter'), onTap: () => Navigator.pop(c, 'rooms')),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'edit') {
      await _edit(meter);
    } else {
      await _rooms(meter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final canManage = context.read<Session>().can('accounts.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('Meters')),
      floatingActionButton: canManage ? FloatingActionButton.extended(icon: const Icon(Icons.add), label: const Text('Add meter'), onPressed: _edit) : null,
      body: LoadView(
        key: _key,
        load: () => api.get('meters'),
        builder: (context, d, _) {
          final meters = (d['meters'] as List).cast<Map>();
          final unmapped = (d['unmapped_rooms'] as List).cast<String>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (unmapped.isNotEmpty)
                Card(
                  color: kWarn.withValues(alpha: 0.10),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: kWarn),
                    title: Text('${unmapped.length} room(s) are on no meter'),
                    subtitle: Text('${unmapped.take(8).join(', ')} — residents there can’t be billed. Fix this on the website.'),
                  ),
                ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Meters',
                padding: EdgeInsets.zero,
                child: meters.isEmpty
                    ? const EmptyView('No meters yet. Add them on the website under Accounts to Meters.', icon: Icons.speed)
                    : Column(
                        children: [
                          for (final m in meters)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: kBlue.withValues(alpha: 0.12),
                                child: const Icon(Icons.bolt, color: kBlue, size: 20),
                              ),
                              title: Text('${m['label']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'No. ${m['meter_no']} · ${m['rooms']} rooms · ${m['residents']} residents'
                                '${m['last_reading'] != null ? ' · last reading ${m['last_reading']}' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (m['active'] != true) const StatusChip('Inactive', tone: 'inactive'),
                                  if (m['active'] == true && m['default_rate'] != null)
                                    Text(money(m['default_rate']), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (canManage) const Icon(Icons.chevron_right, size: 20),
                                ],
                              ),
                              onTap: canManage ? () => _showActions(Map<String, dynamic>.from(m)) : null,
                            ),
                        ],
                      ),
              ),
              Text(
                canManage ? 'Tap a meter to edit it or choose its rooms.' : 'Only staff who manage accounts can change meters.',
                style: const TextStyle(color: kMuted),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Resident account statement, with PDF and WhatsApp.
class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key, required this.resident});

  final Json resident;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  int get _id => toInt(widget.resident['id']);

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statement'),
        actions: [
          IconButton(
            tooltip: 'Print, share or save the statement',
            icon: const Icon(Icons.ios_share),
            onPressed: () => DocumentActions.show(
              context,
              ServerDocument(route: 'residents/$_id/statement', filename: 'statement-${widget.resident['code']}.pdf', title: 'Account statement'),
              onWhatsApp: () => ShareSheet.open(context, type: 'reminder', resident: widget.resident),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.send),
        label: const Text('WhatsApp'),
        onPressed: () => ShareSheet.open(context, type: 'reminder', resident: widget.resident),
      ),
      body: LoadView(
        load: () => api.get('residents/$_id/ledger'),
        builder: (context, d, _) {
          final b = d['balance'] as Map;
          final entries = (d['entries'] as List).cast<Map>();
          final bal = toDouble(b['balance']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: (bal > 0.009 ? kBad : kOk).withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${widget.resident['name']}', style: Theme.of(context).textTheme.titleMedium),
                      Text('${widget.resident['code']}', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Text(bal < -0.009 ? 'Advance credit' : 'Balance due', style: Theme.of(context).textTheme.labelSmall),
                      Text(money(bal.abs()), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 34, color: bal > 0.009 ? kBad : kOk)),
                      Text(
                        'Charged ${money(b['total_charged'])} · Paid ${money(b['total_credited'])} · Deposit ${money(b['deposit_held'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'Entries',
                padding: EdgeInsets.zero,
                child: entries.isEmpty
                    ? const EmptyView('Nothing on this account yet.')
                    : Column(
                        children: [
                          for (final e in entries)
                            ListTile(
                              dense: true,
                              title: Text('${e['type_label']}'),
                              subtitle: Text(
                                [
                                  fmtDate(e['date']),
                                  if (e['description'] != null) '${e['description']}',
                                  if (e['receipt_no'] != null) '${e['receipt_no']}',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                toDouble(e['debit']) > 0 ? '+${money(e['debit'])}' : '-${money(e['credit'])}',
                                style: TextStyle(fontWeight: FontWeight.w600, color: toDouble(e['debit']) > 0 ? kBad : kOk),
                              ),
                              onTap: e['receipt_no'] != null && e['is_void'] != true
                                  ? () => ShareSheet.open(context, type: 'receipt', resident: widget.resident, subjectId: toInt(e['id']))
                                  : null,
                            ),
                        ],
                      ),
              ),
              const Text(
                'Tap a receipt to send it on WhatsApp.',
                style: TextStyle(color: kMuted),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Creates a secure link on the server, shows the message, then opens WhatsApp.
class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.type, required this.resident, this.subjectId});

  final String type; // bill | receipt | reminder
  final Json resident;
  final int? subjectId;

  static Future<void> open(BuildContext context, {required String type, required Json resident, int? subjectId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareSheet(type: type, resident: resident, subjectId: subjectId),
    );
  }

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  int _days = 30;
  Json? _link;
  bool _busy = false;
  String? _error;

  String get _title => switch (widget.type) {
    'bill' => 'Send the bill',
    'receipt' => 'Send the receipt',
    _ => 'Send a payment reminder',
  };

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await apiOf(context)
          .post('share', {'type': widget.type, 'resident_id': widget.resident['id'], 'subject_id': widget.subjectId ?? widget.resident['id'], 'days': _days});
      if (mounted) setState(() => _link = res);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final link = _link;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_title, style: t.titleLarge),
              Text('${widget.resident['name']} · ${widget.resident['phone'] ?? 'no number on file'}', style: t.bodySmall),
              const SizedBox(height: 16),
              if (link == null) ...[
                Text('Link valid for', style: t.labelSmall),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 days')),
                    ButtonSegment(value: 30, label: Text('30 days')),
                    ButtonSegment(value: 90, label: Text('90 days')),
                  ],
                  selected: {_days},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _days = v.first),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: const TextStyle(color: kBad)),
                  ),
                FilledButton(onPressed: _busy ? null : _create, child: Text(_busy ? 'Preparing…' : 'Prepare message')),
                const SizedBox(height: 8),
                const Text(
                  'The link opens only this document, with no password, and expires by itself.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
              ] else ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? kCardDark2 : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(kRadiusControl),
                  ),
                  child: SingleChildScrollView(child: SelectableText('${link['message']}', style: t.bodySmall)),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Open WhatsApp'),
                  onPressed: () {
                    openExternal(context, Uri.parse('${link['whatsapp_url']}'));
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '${link['message']}'));
                          showMessage(context, 'Message copied.');
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open PDF'),
                        onPressed: () => openLinkOrShare(context, Uri.parse('${link['url']}'), shareText: '${link['url']}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Link expires ${fmtDate(link['expires_at'])}', textAlign: TextAlign.center, style: t.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Used by screens that only have a resident id.
Future<Json?> loadResidentSummary(BuildContext context, int id) async {
  try {
    final d = await apiOf(context).get('residents/$id');
    return Map<String, dynamic>.from(d['resident'] as Map);
  } on ApiException {
    return null;
  }
}

bool canShare(BuildContext context) => context.read<Session>().can('accounts.view');

/// Add or edit one meter.
class MeterFormScreen extends StatefulWidget {
  const MeterFormScreen({super.key, this.meter});

  final Json? meter;

  @override
  State<MeterFormScreen> createState() => _MeterFormScreenState();
}

class _MeterFormScreenState extends State<MeterFormScreen> {
  late final Json _m = widget.meter ?? {};
  late final _label = TextEditingController(text: '${_m['label'] ?? ''}');
  late final _number = TextEditingController(text: '${_m['meter_no'] ?? ''}');
  late final _unit = TextEditingController(text: '${_m['unit_label'] ?? 'units'}');
  late final _rate = TextEditingController(text: _m['default_rate'] == null ? '' : fmtNum(_m['default_rate']));
  late String _type = '${_m['type'] ?? 'electricity'}';
  late bool _active = _m['active'] != false;
  Map<String, String> _errors = {};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final editing = widget.meter != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit meter' : 'Add meter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(controller: _label, label: 'Name', required: true, maxLength: 60, hint: 'e.g. Ground floor meter', error: _errors['label']),
          AppTextField(
            controller: _number,
            label: 'Meter number',
            required: true,
            maxLength: 40,
            helper: 'Printed on every bill so residents can check it.',
            error: _errors['meter_no'],
          ),
          ChoiceInput(
            label: 'Utility',
            value: _type,
            required: true,
            choices: const [Choice('electricity', 'Electricity'), Choice('water', 'Water'), Choice('gas', 'Gas')],
            onChanged: (v) => setState(() => _type = v ?? _type),
            error: _errors['meter_type'],
          ),
          AppTextField(controller: _unit, label: 'Unit name', maxLength: 20, hint: 'units', error: _errors['unit_label']),
          AmountInput(controller: _rate, label: 'Usual rate per unit', error: _errors['default_rate'], helper: 'Filled in when you create a bill.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: const Text('Inactive meters stay in the history but take no new bills.'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    setState(() {
                      _busy = true;
                      _errors = {};
                    });
                    try {
                      final res = await apiOf(context).post(editing ? 'meters/${_m['id']}' : 'meters', {
                        'label': _label.text.trim(),
                        'meter_no': _number.text.trim(),
                        'meter_type': _type,
                        'unit_label': _unit.text.trim(),
                        'default_rate': _rate.text.trim(),
                        'is_active': _active ? '1' : '0',
                      });
                      if (context.mounted) showMessage(context, '${res['message']}');
                      nav.pop(true);
                    } on ApiException catch (e) {
                      setState(() {
                        _busy = false;
                        _errors = e.errors;
                      });
                      if (e.errors.isEmpty && context.mounted) showMessage(context, e.message, error: true);
                    }
                  },
            child: Text(_busy ? 'Saving…' : (editing ? 'Save meter' : 'Add meter')),
          ),
        ],
      ),
    );
  }
}

/// Tick the rooms that run on a meter.
class MeterRoomsScreen extends StatefulWidget {
  const MeterRoomsScreen({super.key, required this.meter});

  final Json meter;

  @override
  State<MeterRoomsScreen> createState() => _MeterRoomsScreenState();
}

class _MeterRoomsScreenState extends State<MeterRoomsScreen> {
  Set<int>? _picked;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(title: Text('Rooms on ${widget.meter['label']}')),
      body: LoadView(
        load: () => api.get('meters/${widget.meter['id']}/rooms'),
        builder: (context, d, _) {
          final rooms = (d['rooms'] as List).cast<Map>();
          _picked ??= {
            for (final r in rooms)
              if (r['on_this_meter'] == true) toInt(r['id']),
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A room can be on only one ${widget.meter['label']} type of meter. Ticking it here moves it off any other meter.',
                style: const TextStyle(color: kMuted),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Rooms',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final r in rooms)
                      CheckboxListTile(
                        value: _picked!.contains(toInt(r['id'])),
                        onChanged: (v) => setState(() => v == true ? _picked!.add(toInt(r['id'])) : _picked!.remove(toInt(r['id']))),
                        title: Text('Room ${r['room_number']}'),
                        subtitle: Text(['${r['room_type']}', if (r['on_meter'] != null && r['on_this_meter'] != true) 'now on ${r['on_meter']}'].join(' · ')),
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        setState(() => _busy = true);
                        final res = await runTask(context, () => api.post('meters/${widget.meter['id']}/rooms', {'rooms': _picked!.toList()}));
                        if (res != null) {
                          if (context.mounted) showMessage(context, '${res['message']}');
                          nav.pop(true);
                        } else {
                          setState(() => _busy = false);
                        }
                      },
                child: Text(_busy ? 'Saving…' : 'Save rooms (${_picked!.length} selected)'),
              ),
            ],
          );
        },
      ),
    );
  }
}
