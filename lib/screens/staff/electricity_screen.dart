import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/documents.dart';
import '../../widgets/pickers.dart';
import 'meters_screen.dart';

String elecStatusLabel(String s) => switch (s) {
  'posted' => 'Posted',
  'draft' => 'Draft',
  _ => 'Void',
};
String elecStatusTone(String s) => switch (s) {
  'posted' => 'active',
  'draft' => 'pending',
  _ => 'rejected',
};

/// Electricity bills from the main meter.
class ElectricityScreen extends StatefulWidget {
  const ElectricityScreen({super.key});

  @override
  State<ElectricityScreen> createState() => _ElectricityScreenState();
}

class _ElectricityScreenState extends State<ElectricityScreen> {
  final _key = GlobalKey<LoadViewState>();
  Json? _data;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utility bills'),
        actions: [
          IconButton(
            tooltip: 'Meters',
            icon: const Icon(Icons.speed_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MetersScreen())),
          ),
        ],
      ),
      floatingActionButton: _data?['can_manage'] == true
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.bolt),
              label: const Text('New bill'),
              onPressed: () async {
                final id = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(builder: (_) => NewElectricityBillScreen(defaults: Map<String, dynamic>.from(_data!['defaults'] as Map))),
                );
                await _key.currentState?.reload();
                if (id != null && context.mounted) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ElectricityBillScreen(id: id)));
                  _key.currentState?.reload();
                }
              },
            )
          : null,
      body: LoadView(
        key: _key,
        load: () async {
          final d = await api.get('electricity');
          if (mounted) setState(() => _data = d);
          return d;
        },
        builder: (context, d, reload) {
          final bills = (d['bills'] as List).cast<Map>();
          final history = (d['history'] as List).cast<Map>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (history.length >= 2)
                SectionCard(
                  title: 'Units per month',
                  child: UnitsChart(history: history),
                ),
              if (bills.isEmpty) const EmptyView('No electricity bills yet. Tap “New bill” to enter the meter reading.', icon: Icons.bolt),
              for (final b in bills)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: toneFor(elecStatusTone('${b['status']}')).withValues(alpha: 0.12),
                        child: Icon(Icons.bolt, color: toneFor(elecStatusTone('${b['status']}'))),
                      ),
                      title: Text(fmtMonth(b['month']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${fmtNum(b['units'])} units · ${money(b['rate'])}/unit · ${b['beds']} beds'),
                          StatusChip(elecStatusLabel('${b['status']}'), tone: elecStatusTone('${b['status']}')),
                        ],
                      ),
                      trailing: Text(money(b['billed_total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ElectricityBillScreen(id: toInt(b['id']))));
                        reload();
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String fmtNum(Object? v) {
  final d = toDouble(v);
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
}

/// Simple bar chart of monthly units.
class UnitsChart extends StatelessWidget {
  const UnitsChart({super.key, required this.history});

  final List<Map> history;

  @override
  Widget build(BuildContext context) {
    final maxUnits = history.map((h) => toDouble(h['units'])).fold<double>(1, (a, b) => b > a ? b : a);
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in history)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(child: Text(fmtNum(h['units']), style: Theme.of(context).textTheme.labelSmall)),
                    const SizedBox(height: 2),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: (toDouble(h['units']) / maxUnits).clamp(0.02, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(child: Text(fmtMonth(h['month']).split(' ').first, style: Theme.of(context).textTheme.labelSmall)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NewElectricityBillScreen extends StatefulWidget {
  const NewElectricityBillScreen({super.key, required this.defaults, this.meters = const []});

  final Json defaults;
  final List<Map> meters;

  @override
  State<NewElectricityBillScreen> createState() => _NewElectricityBillScreenState();
}

class _NewElectricityBillScreenState extends State<NewElectricityBillScreen> {
  late int? _meterId = widget.meters.isNotEmpty ? toInt(widget.meters.first['id']) : null;
  String _month = isoMonth(DateTime.now());
  String _readingDate = today();
  String? _dueDate = isoDate(DateTime.now().add(const Duration(days: 10)));
  late final _prev = TextEditingController(text: widget.defaults['prev_reading'] == null ? '' : fmtNum(widget.defaults['prev_reading']));
  final _curr = TextEditingController();
  late final _rate = TextEditingController(text: widget.defaults['rate'] == null ? '' : fmtNum(widget.defaults['rate']));
  final _extra = TextEditingController();
  final _extraLabel = TextEditingController();
  final _notes = TextEditingController();
  Map<String, String> _errors = {};
  bool _busy = false;

  double get _units => (double.tryParse(_curr.text) ?? 0) - (double.tryParse(_prev.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    final beds = toInt(widget.defaults['occupied_beds']);
    final rate = double.tryParse(_rate.text) ?? 0;
    final extra = double.tryParse(_extra.text) ?? 0;
    final total = _units > 0 ? _units * rate + extra : 0.0;
    return UnsavedGuard(
      isDirty: () => !_busy && _curr.text.isNotEmpty,
      child: Scaffold(
        appBar: AppBar(title: const Text('New utility bill')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.meters.length > 1)
              ChoiceInput(
                label: 'Meter',
                value: _meterId?.toString(),
                required: true,
                choices: [for (final m in widget.meters) Choice('${m['id']}', '${m['label']} (${m['meter_no']})')],
                onChanged: (v) => setState(() {
                  _meterId = v == null ? null : int.tryParse(v);
                  final m = widget.meters.firstWhere((x) => '${x['id']}' == v, orElse: () => const {});
                  if (m['default_rate'] != null) _rate.text = fmtNum(m['default_rate']);
                }),
                error: _errors['meter_id'],
                helper: 'Only residents whose room is on this meter are billed.',
              ),
            MonthInput(label: 'Bill month', value: _month, onChanged: (v) => setState(() => _month = v), error: _errors['bill_month']),
            DateInput(
              label: 'Reading date',
              value: _readingDate,
              required: true,
              last: DateTime.now(),
              onChanged: (v) => setState(() => _readingDate = v ?? today()),
              error: _errors['reading_date'],
            ),
            AppTextField(
              controller: _prev,
              label: 'Previous reading',
              required: true,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              helper: widget.defaults['prev_reading'] != null
                  ? 'From the last bill. Change it only if the meter was replaced.'
                  : 'First bill: reading at the start of the period.',
              error: _errors['prev_reading'],
              onChanged: (_) => setState(() {}),
            ),
            AppTextField(
              controller: _curr,
              label: 'Current reading',
              required: true,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              error: _errors['curr_reading'],
              onChanged: (_) => setState(() {}),
            ),
            AmountInput(
              controller: _rate,
              label: 'Rate per unit',
              required: true,
              error: _errors['rate'],
              helper: 'You can give any resident a different rate on the next screen.',
            ),
            AmountInput(
              controller: _extra,
              label: 'Extra charges (optional)',
              error: _errors['extra_charges'],
              helper: 'e.g. taxes, meter rent — split equally.',
            ),
            AppTextField(controller: _extraLabel, label: 'Extra charges label', maxLength: 80, hint: 'e.g. Taxes'),
            DateInput(label: 'Pay by', value: _dueDate, onChanged: (v) => setState(() => _dueDate = v), error: _errors['due_date']),
            AppTextField(controller: _notes, label: 'Notes', maxLines: 2, maxLength: 500),
            Card(
              color: kPrimary.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _units > 0 ? '${fmtNum(_units)} units · meter total ${money(total)}' : 'Enter both readings to see the units.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_units > 0 && beds > 0) Text('About ${money(total / beds)} per bed across $beds occupied beds.'),
                  ],
                ),
              ),
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
                        final res = await apiOf(context).post('electricity', {
                          if (_meterId != null) 'meter_id': _meterId,
                          'bill_month': _month,
                          'reading_date': _readingDate,
                          'prev_reading': _prev.text.trim(),
                          'curr_reading': _curr.text.trim(),
                          'rate': _rate.text.trim(),
                          'extra_charges': _extra.text.trim(),
                          'extra_label': _extraLabel.text.trim(),
                          'due_date': _dueDate ?? '',
                          'notes': _notes.text.trim(),
                        });
                        nav.pop(toInt(res['id']));
                      } on ApiException catch (e) {
                        setState(() {
                          _busy = false;
                          _errors = e.errors;
                        });
                        if (e.errors.isEmpty && context.mounted) showMessage(context, e.message, error: true);
                      }
                    },
              child: Text(_busy ? 'Creating…' : 'Create draft bill'),
            ),
          ],
        ),
      ),
    );
  }
}

class ElectricityBillScreen extends StatefulWidget {
  const ElectricityBillScreen({super.key, required this.id});

  final int id;

  @override
  State<ElectricityBillScreen> createState() => _ElectricityBillScreenState();
}

class _ElectricityBillScreenState extends State<ElectricityBillScreen> {
  final _key = GlobalKey<LoadViewState>();

  Future<void> _action(String action, {String? confirmText, bool askReason = false, String? reasonTitle}) async {
    final api = apiOf(context);
    String reason = '';
    if (askReason) {
      final r = await askText(context, reasonTitle ?? 'Reason', ok: 'Confirm', danger: true);
      if (r == null) return;
      reason = r;
    } else if (confirmText != null) {
      if (!await confirm(context, 'Are you sure?', confirmText)) return;
    }
    if (!mounted) return;
    final res = await runTask(context, () => api.post('electricity/${widget.id}/action', {'action': action, 'reason': reason}));
    if (res == null || !mounted) return;
    showMessage(context, '${res['message']}');
    if (action == 'delete') {
      Navigator.pop(context);
    } else {
      _key.currentState?.reload();
    }
  }

  Future<void> _editShare(Json share, Json bill) async {
    final rate = TextEditingController(text: fmtNum(share['rate']));
    var included = share['excluded'] != true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${share['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include on this bill'),
                subtitle: const Text('If off, their units are shared among the others.'),
                value: included,
                onChanged: (v) => set(() => included = v),
              ),
              if (included)
                AmountInput(
                  controller: rate,
                  label: 'Rate per unit for this resident',
                  helper: 'Bill rate is ${money(bill['rate'])}. Leave it the same for the normal rate.',
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final api = apiOf(context);
    final res = await runTask(
      context,
      () => api.post('electricity/${widget.id}/share', {'share_id': share['id'], 'rate': rate.text.trim(), 'included': included ? '1' : '0'}),
    );
    if (res != null) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Electricity bill'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'PDF',
            onSelected: (t) => DocumentActions.show(
              context,
              ServerDocument(
                route: 'electricity/${widget.id}/pdf',
                filename: 'electricity-$t.pdf',
                query: {'type': t},
                title: t == 'summary' ? 'Office summary' : 'All residents’ bills',
              ),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'slips', child: Text('All residents’ bills (PDF)')),
              PopupMenuItem(value: 'summary', child: Text('Office summary (PDF)')),
            ],
          ),
        ],
      ),
      body: LoadView(
        key: _key,
        load: () => api.get('electricity/${widget.id}'),
        builder: (context, d, reload) {
          final b = Map<String, dynamic>.from(d['bill'] as Map);
          final shares = (d['shares'] as List).cast<Map>();
          final canManage = d['can_manage'] == true;
          final status = '${b['status']}';
          final included = shares.where((s) => s['excluded'] != true).length;
          final diff = toDouble(b['billed_total']) - toDouble(b['meter_total']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmtMonth(b['month']), style: Theme.of(context).textTheme.titleLarge),
                        Text('${b['meter_label'] ?? 'Meter'} · No. ${b['meter_no'] ?? '—'} · ${b['bill_no']}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StatusChip(elecStatusLabel(status), tone: elecStatusTone(status)),
                ],
              ),
              const SizedBox(height: 8),
              if (status == 'void') Text('Void: ${b['void_reason']}', style: const TextStyle(color: kBad)),
              if (status == 'draft')
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Draft — not added to any account yet. Check the shares, then post.', style: TextStyle(color: kWarn)),
                ),
              StatGrid([
                StatTile(label: 'Units used', value: fmtNum(b['units']), sub: '${fmtNum(b['prev_reading'])} to ${fmtNum(b['curr_reading'])}', icon: Icons.bolt),
                StatTile(
                  label: 'Rate per unit',
                  value: money(b['rate']),
                  sub: toDouble(b['extra_charges']) > 0 ? '+ ${money(b['extra_charges'])} ${b['extra_label'] ?? 'extra'}' : 'no extra charges',
                ),
                StatTile(label: 'Meter total', value: money(b['meter_total'])),
                StatTile(
                  label: 'Billed to residents',
                  value: money(b['billed_total']),
                  sub:
                      '$included ${included == 1 ? 'resident' : 'residents'}${diff.abs() >= 0.01 ? ' · ${diff > 0 ? '+' : '-'}${money(diff.abs())} custom rates' : ''}',
                  color: kPrimary,
                ),
              ]),
              if (b['due_date'] != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Pay by ${fmtDate(b['due_date'])}')),
              SectionCard(
                title: 'Shares',
                trailing: canManage ? TextButton(onPressed: () => _action('sync'), child: const Text('Refresh')) : null,
                padding: const EdgeInsets.only(bottom: 8),
                child: shares.isEmpty
                    ? const EmptyView('Nobody is in a bed right now.')
                    : Column(
                        children: [
                          for (final s in shares)
                            ListTile(
                              enabled: s['excluded'] != true,
                              title: Text('${s['name']}'),
                              subtitle: Text(
                                s['excluded'] == true
                                    ? '${s['room']} · not billed'
                                    : '${s['room']} · ${fmtNum(s['units'])} units × ${money(s['rate'])}${s['custom_rate'] == true ? ' (custom)' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(s['excluded'] == true ? '—' : money(s['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  if (s['excluded'] != true)
                                    IconButton(
                                      tooltip: 'Print, share or send the bill',
                                      icon: const Icon(Icons.more_horiz, size: 22),
                                      onPressed: () => downloadAndOpen(
                                        context,
                                        'electricity/${widget.id}/pdf',
                                        'electricity-${s['code']}.pdf',
                                        query: {'type': 'slips', 'resident': s['resident_id']},
                                      ),
                                    ),
                                ],
                              ),
                              onTap: canManage ? () => _editShare(Map<String, dynamic>.from(s), b) : null,
                            ),
                        ],
                      ),
              ),
              if (canManage) const Text('Tap a resident to set their own rate or leave them out.', style: TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              if (canManage) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text(included == 1 ? 'Post bill to 1 account' : 'Post bill to $included accounts'),
                  onPressed: included == 0 ? null : () => _action('post', confirmText: 'Add these electricity charges to $included resident accounts?'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _action('delete', confirmText: 'Delete this draft bill?'),
                  child: const Text('Delete draft'),
                ),
              ],
              if (status == 'posted' && d['can_void'] == true)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kBad),
                  icon: const Icon(Icons.block),
                  label: const Text('Void bill'),
                  onPressed: () => _action('void', askReason: true, reasonTitle: 'Void this bill and its charges?'),
                ),
              if ((d['payment_details'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                PaymentDetailsCard(details: (d['payment_details'] as List).cast<Map>()),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// JazzCash / Easypaisa / bank details from Hostel settings.
class PaymentDetailsCard extends StatelessWidget {
  const PaymentDetailsCard({super.key, required this.details, this.instructions});

  final List<Map> details;
  final String? instructions;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'How residents pay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(m['method'] == 'bank_transfer' ? Icons.account_balance_outlined : Icons.phone_android, color: kPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['label']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        for (final l in (m['lines'] as List)) SelectableText('$l'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (instructions != null) Text(instructions!, style: const TextStyle(color: kMuted)),
        ],
      ),
    );
  }
}

/// Keeps the Session import used (permission checks happen server-side for these screens).
bool canUseElectricity(BuildContext context) => context.read<Session>().can('accounts.view');
