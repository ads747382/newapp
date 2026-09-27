import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/pickers.dart';
import '../receipt_screen.dart';

const _hints = {
  'rent': 'Rent for one month. Usually posted in bulk from "Post monthly rent".',
  'charge': 'Electricity, mess, laundry, damages or other extras. Adds to balance due.',
  'discount': 'Reduces what the resident owes. Give the reason in the description.',
  'payment': 'Money received against dues. A receipt is issued.',
  'advance': 'Money received ahead of dues; kept as credit. A receipt is issued.',
  'refund': 'Paying back unused credit to the resident.',
  'deposit_received': 'Refundable security deposit, kept separate from rent. A receipt is issued.',
  'deposit_refund': 'Returning the security deposit when the resident leaves.',
  'deposit_applied': 'Use the held deposit to settle outstanding dues.',
};

/// Record rent, charges, payments, deposits… for one resident.
class LedgerEntryScreen extends StatefulWidget {
  const LedgerEntryScreen({super.key, this.resident, this.type = 'payment'});

  final Json? resident;
  final String type;

  @override
  State<LedgerEntryScreen> createState() => _LedgerEntryScreenState();
}

class _LedgerEntryScreenState extends State<LedgerEntryScreen> {
  late Json? _resident = widget.resident;
  late String _type = widget.type;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _description = TextEditingController();
  String _date = today();
  String _month = isoMonth(DateTime.now());
  String? _method = 'cash';
  Map<String, String> _errors = {};
  bool _busy = false;

  bool get _moneyIn => const ['payment', 'advance', 'deposit_received'].contains(_type);
  bool get _needsMethod => _moneyIn || _type == 'refund' || _type == 'deposit_refund';
  bool get _needsReason => const ['discount', 'charge', 'refund', 'deposit_refund'].contains(_type);

  Future<void> _save() async {
    final api = apiOf(context);
    if (_resident == null) {
      setState(() => _errors = {'resident_id': 'Choose a resident.'});
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final res = await api.post('ledger', {
        'resident_id': _resident!['id'],
        'entry_type': _type,
        'amount': _amount.text.trim(),
        'entry_date': _date,
        'period_month': _type == 'rent' ? _month : '',
        'method': _needsMethod ? (_method ?? '') : '',
        'reference': _reference.text.trim(),
        'description': _description.text.trim(),
      });
      if (!mounted) return;
      _amount.clear();
      _reference.clear();
      _description.clear();
      showMessage(context, '${res['message']}');
      if (res['has_receipt'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(
              route: 'receipts/${res['id']}',
              phone: '${_resident!['phone'] ?? ''}',
              entryId: toInt(res['id']),
              residentId: toInt(_resident!['id']),
            ),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.errors);
      if (e.errors.isEmpty) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final types = s.options('ledger_types');
    final r = _resident;
    return UnsavedGuard(
      isDirty: () => !_busy && (_amount.text.isNotEmpty || _reference.text.isNotEmpty || _description.text.isNotEmpty),
      child: Scaffold(
        appBar: AppBar(title: const Text('Record entry')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: r == null
                    ? const Icon(Icons.person_search)
                    : ResidentAvatar(id: toInt(r['id']), name: '${r['name']}', hasPhoto: r['has_photo'] == true),
                title: Text(r == null ? 'Choose resident *' : '${r['name']}'),
                subtitle: Text(
                  r == null ? (_errors['resident_id'] ?? 'Search by name, phone or room') : '${r['code']}',
                  style: TextStyle(color: _errors['resident_id'] != null && r == null ? kBad : null),
                ),
                trailing: widget.resident == null ? const Icon(Icons.search) : null,
                onTap: widget.resident == null
                    ? () async {
                        final picked = await showModalBottomSheet<Json>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => ResidentPicker(api: s.api),
                        );
                        if (picked != null) setState(() => _resident = picked);
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            ChoiceInput(
              label: 'Entry type',
              value: _type,
              required: true,
              choices: [for (final t in types) Choice('${t['value']}', '${t['label']}')],
              onChanged: (v) => setState(() => _type = v ?? _type),
              helper: _hints[_type],
              error: _errors['entry_type'],
            ),
            AmountInput(controller: _amount, label: 'Amount', required: true, error: _errors['amount']),
            DateInput(
              label: 'Date',
              value: _date,
              required: true,
              last: DateTime.now().add(const Duration(days: 1)),
              onChanged: (v) => setState(() => _date = v ?? today()),
              error: _errors['entry_date'],
            ),
            if (_type == 'rent') MonthInput(label: 'Rent month', value: _month, onChanged: (v) => setState(() => _month = v), error: _errors['period_month']),
            if (_needsMethod)
              ChoiceInput(
                label: _moneyIn ? 'Received by' : 'Paid by',
                value: _method,
                required: _moneyIn,
                choices: [for (final m in s.options('payment_methods')) Choice('${m['value']}', '${m['label']}')],
                onChanged: (v) => setState(() => _method = v),
                error: _errors['method'],
              ),
            if (_needsMethod)
              AppTextField(controller: _reference, label: 'Reference', hint: 'Transaction ID, cheque no.', maxLength: 80, error: _errors['reference']),
            AppTextField(controller: _description, label: 'Description', required: _needsReason, maxLength: 255, error: _errors['description']),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save entry')),
          ],
        ),
      ),
    );
  }
}

/// Search residents and return the chosen summary.
class ResidentPicker extends StatefulWidget {
  const ResidentPicker({super.key, required this.api});

  final Api api;

  @override
  State<ResidentPicker> createState() => _ResidentPickerState();
}

class _ResidentPickerState extends State<ResidentPicker> {
  List<Json> _items = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final d = await widget.api.get('residents', query: {'q': q, 'view': 'all', 'sort': 'name'});
      if (!mounted) return;
      setState(() {
        _items = (d['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name, phone, CNIC, room or code'),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => _search(v.trim()));
              },
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(color: kBad)),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final r in _items)
                    ListTile(
                      leading: ResidentAvatar(id: toInt(r['id']), name: '${r['name']}', hasPhoto: r['has_photo'] == true),
                      title: Text('${r['name']}'),
                      subtitle: Text(
                        [r['code'], if (r['room_number'] != null) 'Room ${r['room_number']}', if (r['is_archived'] == true) 'Archived'].join(' · '),
                      ),
                      trailing: r['balance'] == null ? null : Text(money(r['balance'])),
                      onTap: () => Navigator.pop(context, r),
                    ),
                  if (!_loading && _items.isEmpty) const EmptyView('No residents found.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
