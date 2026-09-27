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
import 'accounts_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _includeVoid = false;
  int _gen = 0;
  Json? _meta;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: _includeVoid ? 'Hide voided' : 'Show voided',
            icon: Icon(_includeVoid ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _includeVoid = !_includeVoid),
          ),
        ],
      ),
      floatingActionButton: s.can('expenses.manage')
          ? FloatingActionButton.extended(icon: const Icon(Icons.add), label: const Text('Expense'), onPressed: () => _open(null))
          : null,
      body: Column(
        children: [
          MonthBar(month: _month, onChanged: (m) => setState(() => _month = m)),
          Expanded(
            child: PagedList(
              key: ValueKey('$_month|$_includeVoid|$_gen'),
              load: (page) async => _meta = await s.api.get(
                'expenses',
                query: {'from': firstOfMonth(_month), 'to': lastOfMonth(_month), 'void': _includeVoid ? 'include' : null, 'page': page},
              ),
              header: (d) {
                final sum = d['summary'] as Map?;
                return StatGrid([
                  StatTile(label: 'Spent', value: money(d['spent']), sub: '${d['total']} entries', color: kBad),
                  if (sum != null) StatTile(label: 'Received from residents', value: money(sum['income']), color: kOk),
                  if (sum != null)
                    StatTile(
                      label: toDouble(sum['net']) < 0 ? 'Loss' : 'Profit',
                      value: money(toDouble(sum['net']).abs()),
                      color: toDouble(sum['net']) < 0 ? kBad : kOk,
                    ),
                ]);
              },
              itemBuilder: (x) {
                final isVoid = x['is_void'] == true;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (isVoid ? kMuted : kBad).withValues(alpha: 0.12),
                    child: Icon(Icons.receipt_long_outlined, color: isVoid ? kMuted : kBad, size: 20),
                  ),
                  title: Text(
                    '${x['category']}${x['paid_to'] != null ? ' · ${x['paid_to']}' : ''}',
                    style: TextStyle(decoration: isVoid ? TextDecoration.lineThrough : null),
                  ),
                  subtitle: Text(
                    [
                      fmtDate(x['date']),
                      s.label('payment_methods', x['method']),
                      if (x['description'] != null) '${x['description']}',
                      if (isVoid) 'VOID: ${x['void_reason']}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money(x['amount']),
                        style: TextStyle(fontWeight: FontWeight.w700, color: isVoid ? kMuted : null),
                      ),
                      if (x['has_receipt'] == true) const Icon(Icons.attach_file, size: 16, color: kMuted),
                    ],
                  ),
                  onTap: () => _details(x),
                );
              },
              empty: 'No expenses this month.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(Json? expense) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ExpenseFormScreen(expense: expense)));
    if (ok == true) setState(() => _gen++);
  }

  Future<void> _details(Json x) async {
    final api = apiOf(context);
    final isVoid = x['is_void'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InfoRows([
                ('Amount', money(x['amount'])),
                ('Category', '${x['category']}'),
                ('Date', fmtDate(x['date'])),
                ('Paid to', orDash(x['paid_to'])),
                ('Paid by', context.read<Session>().label('payment_methods', x['method'])),
                ('Reference', orDash(x['reference'])),
                ('Description', orDash(x['description'])),
                ('Entered by', orDash(x['by'])),
              ]),
            ),
            if (x['has_receipt'] == true)
              ListTile(leading: const Icon(Icons.attach_file), title: const Text('Open bill'), onTap: () => Navigator.pop(c, 'bill')),
            if (!isVoid && _meta?['can_manage'] == true)
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () => Navigator.pop(c, 'edit')),
            if (context.read<Session>().canPurge)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: kBad),
                title: const Text('Delete permanently', style: TextStyle(color: kBad)),
                onTap: () => Navigator.pop(c, 'purge'),
              ),
            if (!isVoid && _meta?['can_void'] == true)
              ListTile(
                leading: const Icon(Icons.block, color: kBad),
                title: const Text('Void', style: TextStyle(color: kBad)),
                onTap: () => Navigator.pop(c, 'void'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'bill':
        await downloadAndOpen(context, 'expenses/${x['id']}/receipt', 'bill-${x['id']}');
      case 'edit':
        await _open(x);
      case 'purge':
        final reason = await askText(context, 'Delete this expense permanently?', ok: 'Delete', danger: true);
        if (reason == null || !mounted) return;
        final res = await runTask(context, () => api.post('expenses/${x['id']}/delete', {'reason': reason}), success: 'Expense deleted.');
        if (res != null) setState(() => _gen++);
      case 'void':
        final reason = await askText(context, 'Void this expense?', ok: 'Void', danger: true);
        if (reason == null || !mounted) return;
        final res = await runTask(context, () => api.post('expenses/${x['id']}/void', {'reason': reason}), success: 'Expense voided.');
        if (res != null) setState(() => _gen++);
    }
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense});

  final Json? expense;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final Json _x = widget.expense ?? {};
  late String _date = '${_x['date'] ?? today()}';
  late String? _category = _x['category_id']?.toString();
  late String _method = '${_x['method'] ?? 'cash'}';
  late final _amount = TextEditingController(text: _x['amount'] == null ? '' : '${_x['amount']}');
  late final _paidTo = TextEditingController(text: '${_x['paid_to'] ?? ''}');
  late final _reference = TextEditingController(text: '${_x['reference'] ?? ''}');
  late final _description = TextEditingController(text: '${_x['description'] ?? ''}');
  UploadFile? _bill;
  bool _removeBill = false;
  Map<String, String> _errors = {};
  bool _busy = false;

  Future<void> _pickBill() async {
    final f = await pickUploads(context, field: 'receipt', title: 'Bill photo or PDF');
    if (f.isEmpty) return;
    setState(() {
      _bill = f.first;
      _removeBill = false;
    });
  }

  final _tracker = DirtyTracker();

  List<Object?> _values() => [_date, _category, _method, _amount.text, _paidTo.text, _reference.text, _description.text, _bill?.filename, _removeBill];

  @override
  void initState() {
    super.initState();
    _tracker.start(_values());
  }

  Future<void> _save() async {
    final api = apiOf(context);
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final res = await api.upload(
        _x['id'] == null ? 'expenses' : 'expenses/${_x['id']}',
        fields: {
          'expense_date': _date,
          'category_id': _category ?? '',
          'amount': _amount.text.trim(),
          'paid_to': _paidTo.text.trim(),
          'method': _method,
          'reference': _reference.text.trim(),
          'description': _description.text.trim(),
          if (_removeBill) 'remove_receipt': '1',
        },
        files: [?_bill],
      );
      if (!mounted) return;
      _tracker.start(_values());
      showMessage(context, '${res['message']}');
      Navigator.pop(context, true);
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
    final api = apiOf(context);
    final hadBill = _x['has_receipt'] == true && !_removeBill;
    return UnsavedGuard(
      isDirty: () => !_busy && _tracker.isDirty(_values()),
      child: Scaffold(
        appBar: AppBar(title: Text(_x['id'] == null ? 'Add expense' : 'Edit expense')),
        body: LoadView(
          load: () => api.get('expense-categories'),
          builder: (context, d, _) {
            final cats = (d['categories'] as List).cast<Map>().where((c) => c['active'] == true || '${c['id']}' == _category).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateInput(
                  label: 'Date',
                  value: _date,
                  required: true,
                  last: DateTime.now().add(const Duration(days: 1)),
                  onChanged: (v) => setState(() => _date = v ?? today()),
                  error: _errors['expense_date'],
                ),
                ChoiceInput(
                  label: 'Category',
                  value: _category,
                  required: true,
                  choices: [for (final c in cats) Choice('${c['id']}', '${c['name']}')],
                  onChanged: (v) => setState(() => _category = v),
                  error: _errors['category_id'],
                ),
                AmountInput(controller: _amount, label: 'Amount', required: true, error: _errors['amount']),
                AppTextField(controller: _paidTo, label: 'Paid to', hint: 'e.g. LESCO, plumber', maxLength: 120, error: _errors['paid_to']),
                ChoiceInput(
                  label: 'Paid by',
                  value: _method,
                  required: true,
                  choices: [for (final m in s.options('payment_methods')) Choice('${m['value']}', '${m['label']}')],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                  error: _errors['method'],
                ),
                AppTextField(controller: _reference, label: 'Reference / bill no.', maxLength: 80, error: _errors['reference']),
                AppTextField(controller: _description, label: 'Description', maxLength: 255, error: _errors['description']),
                const FormHeading('Bill photo or PDF'),
                if (_bill != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: isImageName(_bill!.filename)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(_bill!.bytes, width: 40, height: 40, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(_bill!.filename),
                    trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _bill = null)),
                  )
                else if (hadBill)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.attach_file),
                    title: const Text('Bill attached'),
                    trailing: TextButton(onPressed: () => setState(() => _removeBill = true), child: const Text('Remove')),
                  ),
                if (_errors['receipt'] != null) Text(_errors['receipt']!, style: const TextStyle(color: kBad)),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_bill == null && !hadBill ? 'Attach bill (gallery, camera or PDF)' : 'Replace bill'),
                  onPressed: _pickBill,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save expense')),
              ],
            );
          },
        ),
      ),
    );
  }
}
