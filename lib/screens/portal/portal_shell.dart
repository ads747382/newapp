import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';
import '../../widgets/lists.dart';
import '../password_screen.dart';
import '../receipt_screen.dart';
import '../rules_screen.dart';

class PortalShell extends StatefulWidget {
  const PortalShell({super.key});
  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = const [_PortalHome(), _PortalPayments(), _PortalBills(), _PortalAttendance(), _PortalMore()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.electric_bolt_outlined), selectedIcon: Icon(Icons.electric_bolt), label: 'Bills'),
          NavigationDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu_open), label: 'More'),
        ],
      ),
    );
  }
}

class _PortalHome extends StatelessWidget {
  const _PortalHome();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(s.hostelName)),
      body: LoadView(
        load: () => s.api.get('portal/me'),
        builder: (context, d, reload) {
          final r = Map<String, dynamic>.from(d['resident'] as Map);
          final room = d['room'] as Map?;
          final last = d['last_payment'] as Map?;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text('${r['name']}'), subtitle: Text('${r['code']} · ${r['admission_label'] ?? ''}'))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Metric('Balance', money(d['balance'])),
              _Metric('Deposit', money(d['deposit_held'])),
              _Metric('Monthly rent', money(d['monthly_rent'])),
              _Metric('Room / bed', room == null ? '—' : '${room['room_number']} / ${room['bed_label']}'),
            ]),
            if (last != null) Card(child: ListTile(leading: const Icon(Icons.payments_outlined), title: Text('Last payment ${money(last['amount'])}'), subtitle: Text(fmtDate(last['date'])))),
            const SizedBox(height: 8),
            Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final e in (d['recent'] as List? ?? const [])) ListTile(dense: true, title: Text('${e['type_label'] ?? e['entry_type']}'), subtitle: Text('${fmtDate(e['date'] ?? e['entry_date'])} · ${e['description'] ?? ''}'), trailing: Text(money((toDouble(e['debit']) > 0 ? e['debit'] : e['credit'])))),
          ]);
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(width: (MediaQuery.sizeOf(context).width - 48) / 2, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))]))));
}

class _PortalPayments extends StatelessWidget {
  const _PortalPayments();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Payments')), body: LoadView(load: () => apiOf(context).get('portal/payments'), builder: (context, d, reload) {
    final rows = (d['entries'] as List?) ?? (d['payments'] as List?) ?? const [];
    return Column(children: [for (final x in rows) Card(child: ListTile(title: Text('${x['type_label'] ?? x['entry_type'] ?? 'Payment'}'), subtitle: Text('${fmtDate(x['date'] ?? x['entry_date'])} · ${x['description'] ?? ''}'), trailing: Text(money(toDouble(x['credit']) > 0 ? x['credit'] : x['debit']), style: const TextStyle(fontWeight: FontWeight.w700)), onTap: x['id'] == null || toDouble(x['credit']) <= 0 ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(route: 'portal/receipts/${x['id']}'))))))]);
  }));
}

class _PortalBills extends StatelessWidget {
  const _PortalBills();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Electricity bills')), body: LoadView(load: () => apiOf(context).get('portal/bills'), builder: (context, d, reload) {
    final rows = (d['bills'] as List?) ?? const [];
    return Column(children: [for (final x in rows) Card(child: ListTile(leading: const Icon(Icons.electric_bolt), title: Text(fmtMonth(x['month'])), subtitle: Text('${x['units'] ?? ''} units'), trailing: Text(money(x['total'] ?? x['amount'])), onTap: x['id'] == null ? null : () => downloadAndOpen(context, 'portal/bills/${x['id']}/pdf', 'electricity-${x['month']}.pdf')))]);
  }));
}

class _PortalAttendance extends StatelessWidget {
  const _PortalAttendance();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Attendance')), body: LoadView(load: () => apiOf(context).get('portal/attendance'), builder: (context, d, reload) {
    final days = (d['days'] as List?) ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: ListTile(title: Text('Current status: ${('${d['status'] ?? 'in'}').toUpperCase()}'), subtitle: Text(d['last_at'] == null ? 'No movement recorded' : 'Last movement: ${d['last_at']}'), trailing: IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => downloadAndOpen(context, 'portal/attendance/pdf', 'attendance.pdf')))),
      for (final x in days) Card(child: ListTile(title: Text(fmtDate(x['date'])), subtitle: Text('IN ${x['ins']} · OUT ${x['outs']}${x['late'] == true || toInt(x['late']) > 0 ? ' · Late' : ''}'), trailing: Text('${(x['moves'] as List?)?.length ?? 0} moves'))),
    ]);
  }));
}

class _PortalMore extends StatelessWidget {
  const _PortalMore();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(appBar: AppBar(title: const Text('More')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(leading: const Icon(Icons.rule_outlined), title: const Text('Hostel rules'), trailing: const Icon(Icons.chevron_right), onTap: () async {
        final d = await runTask(context, () => s.api.get('portal/rules'));
        if (d != null && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Hostel rules')), body: ListView(padding: const EdgeInsets.all(16), children: [RulesList(rules: Map<String, dynamic>.from(d['rules'] as Map))]))));
      })),
      Card(child: ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Statement PDF'), onTap: () => downloadAndOpen(context, 'portal/statement', 'statement.pdf'))),
      Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Change password'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PasswordScreen())))),
      Card(child: ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: s.logout)),
    ]));
  }
}


class _AttendanceDay extends StatelessWidget {
  const _AttendanceDay({required this.raw});
  final Map<String, dynamic> raw;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    title: Text(fmtDate(raw['date'])),
    subtitle: Text('IN ${raw['ins']} · OUT ${raw['outs']}${raw['late'] == true || toInt(raw['late']) > 0 ? ' · Late' : ''}'),
    trailing: Text('${(raw['moves'] as List?)?.length ?? 0} moves'),
  ));
}
