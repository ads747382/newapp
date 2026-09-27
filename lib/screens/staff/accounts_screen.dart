import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/lists.dart';
import 'electricity_screen.dart';
import 'ledger_entry_screen.dart';
import 'rent_screen.dart';
import 'money_board_screen.dart';

/// All ledger entries for a month, with quick actions.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _type;
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final canManage = s.can('accounts.manage');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(tooltip: 'Money board', icon: const Icon(Icons.dashboard_customize_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoneyBoardScreen()))),
          IconButton(
            tooltip: 'Electricity bills',
            icon: const Icon(Icons.bolt),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ElectricityScreen()));
              setState(() => _gen++);
            },
          ),
          if (canManage)
            IconButton(
              tooltip: 'Post monthly rent',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const RentScreen()));
                setState(() => _gen++);
              },
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'acc',
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record'),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const LedgerEntryScreen()));
                setState(() => _gen++);
              },
            )
          : null,
      body: Column(
        children: [
          MonthBar(month: _month, onChanged: (m) => setState(() => _month = m)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ChoiceInput(
              label: 'Entry type',
              value: _type,
              allowEmpty: true,
              choices: [for (final t in s.options('ledger_types')) Choice('${t['value']}', '${t['label']}')],
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
          Expanded(
            child: PagedList(
              key: ValueKey('$_month|$_type|$_gen'),
              load: (page) => s.api.get('ledger', query: {'from': firstOfMonth(_month), 'to': lastOfMonth(_month), 'type': _type, 'page': page}),
              header: (d) {
                final t = d['totals'] as Map;
                return StatGrid([
                  StatTile(label: 'Charged', value: money(t['debit']), sub: '${d['total']} entries'),
                  StatTile(label: 'Received & credited', value: money(t['credit'])),
                ]);
              },
              itemBuilder: (e) => LedgerTile(e, showResident: true),
              empty: 'No entries this month.',
            ),
          ),
        ],
      ),
    );
  }
}

/// ‹ September 2026 › selector.
class MonthBar extends StatelessWidget {
  const MonthBar({super.key, required this.month, required this.onChanged});

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => onChanged(DateTime(month.year, month.month - 1))),
        Expanded(
          child: Text(fmtMonth(isoMonth(month)), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => onChanged(DateTime(month.year, month.month + 1))),
      ],
    );
  }
}
