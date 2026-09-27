import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/lists.dart';
import 'electricity_screen.dart';
import 'expenses_screen.dart';
import 'ledger_entry_screen.dart';
import 'rent_screen.dart';
import 'resident_detail_screen.dart';
import 'residents_screen.dart';
import 'resident_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _key = GlobalKey<LoadViewState>();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.hostelName),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => _key.currentState?.reload())],
      ),
      body: LoadView(
        key: _key,
        load: () => s.api.get('dashboard'),
        builder: (context, d, reload) {
          final occ = d['occupancy'] as Map;
          final res = d['residents'] as Map;
          final fin = d['finance'] as Map?;
          final profit = d['profit'] as Map?;
          final pipeline = (d['pipeline'] as List).cast<Map>();
          final user = s.user?['name'] ?? '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(greeting: 'Hello, ${'$user'.split(' ').first}', date: fmtDate(d['date']), hostel: s.hostelName, actions: _quickActions(context, s)),
              const SizedBox(height: 12),
              if (toInt(d['online_waiting']) > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: kInfo.withValues(alpha: 0.10),
                    child: ListTile(
                      leading: const Icon(Icons.public, color: kInfo),
                      title: Text('${d['online_waiting']} new online application${toInt(d['online_waiting']) == 1 ? '' : 's'}'),
                      subtitle: const Text('Sent from the website form — review and approve'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ResidentsScreen(initialView: 'admissions', initialSource: 'online'),
                          ),
                        );
                        reload();
                      },
                    ),
                  ),
                ),
              if (fin != null && fin['rent_posted_this_month'] != true && toInt(occ['occupied']) > 0 && s.can('accounts.manage'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: kWarn.withValues(alpha: 0.1),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber, color: kWarn),
                      title: const Text("This month's rent hasn't been posted yet."),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const RentScreen()));
                        reload();
                      },
                    ),
                  ),
                ),
              StatGrid([
                StatTile(
                  label: 'Beds occupied',
                  value: '${occ['occupied']} / ${occ['beds']}',
                  sub: '${occ['rate']}% across ${occ['rooms']} rooms',
                  icon: Icons.bed_outlined,
                ),
                StatTile(label: 'Vacant beds', value: '${occ['vacant']}', sub: 'ready to assign', icon: Icons.hotel_outlined, color: kOk),
                StatTile(label: 'Residents', value: '${res['admitted']}', sub: '${res['in_pipeline']} in admission', icon: Icons.people_outline),
                StatTile(label: 'To verify', value: '${res['unverified']}', sub: 'verification pending', icon: Icons.fact_check_outlined, color: kWarn),
                if (fin != null) ...[
                  StatTile(
                    label: 'Outstanding',
                    value: money(fin['outstanding']),
                    sub: '${fin['debtors']} residents owe',
                    icon: Icons.trending_up,
                    color: kBad,
                  ),
                  StatTile(
                    label: 'Collected this month',
                    value: money(fin['month_collected']),
                    sub: 'of ${money(fin['month_billed'])} rent billed',
                    icon: Icons.payments_outlined,
                    color: kOk,
                  ),
                  StatTile(label: 'Deposits held', value: money(fin['deposits']), sub: 'refundable', icon: Icons.savings_outlined),
                  StatTile(label: 'Advances', value: money(fin['advances']), sub: 'credit with residents', icon: Icons.account_balance_outlined, color: kInfo),
                ],
                if (profit != null)
                  StatTile(
                    label: toDouble(profit['net']) < 0 ? 'Loss this month' : 'Profit this month',
                    value: money(toDouble(profit['net']).abs()),
                    sub: 'in ${money(profit['income'])} · out ${money(profit['expenses'])}',
                    icon: Icons.insights_outlined,
                    color: toDouble(profit['net']) < 0 ? kBad : kOk,
                  ),
              ]),
              if (pipeline.isNotEmpty)
                SectionCard(
                  title: 'Admissions in progress',
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(children: [for (final r in pipeline) ResidentTile(Map<String, dynamic>.from(r), onChanged: reload)]),
                ),
              if (fin != null && (fin['top_due'] as List).isNotEmpty)
                SectionCard(
                  title: 'Highest dues',
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [for (final r in (fin['top_due'] as List).cast<Map>()) ResidentTile(Map<String, dynamic>.from(r), onChanged: reload)],
                  ),
                ),
              if (fin != null && (fin['recent_payments'] as List).isNotEmpty)
                SectionCard(
                  title: 'Recent payments',
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [for (final e in (fin['recent_payments'] as List).cast<Map>()) LedgerTile(Map<String, dynamic>.from(e), showResident: true)],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<_QuickAction> _quickActions(BuildContext context, Session s) {
    Future<void> open(Widget w) async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
      _key.currentState?.reload();
    }

    return [
      if (s.can('residents.create')) _QuickAction(Icons.person_add_alt, 'Admission', () => open(const ResidentFormScreen())),
      if (s.can('accounts.manage')) _QuickAction(Icons.payments_outlined, 'Payment', () => open(const LedgerEntryScreen(type: 'payment'))),
      if (s.can('accounts.manage')) _QuickAction(Icons.calendar_month_outlined, 'Post rent', () => open(const RentScreen())),
      if (s.can('accounts.view')) _QuickAction(Icons.bolt, 'Electricity', () => open(const ElectricityScreen())),
      if (s.can('expenses.manage')) _QuickAction(Icons.receipt_long_outlined, 'Expense', () => open(const ExpenseFormScreen())),
    ];
  }
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Teal greeting card with one-tap actions.
class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.date, required this.hostel, required this.actions});

  final String greeting;
  final String date;
  final String hostel;
  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [kBlue, Color(0xFF5E5CE6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipOval(child: Image.asset('assets/icon/logo.png', width: 44, height: 44, fit: BoxFit.cover)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$hostel · $date',
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (final a in actions)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: a.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                              child: Icon(a.icon, color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              a.label,
                              style: t.labelSmall?.copyWith(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A resident row used on the dashboard, lists and reports.
class ResidentTile extends StatelessWidget {
  const ResidentTile(this.r, {super.key, this.onChanged});

  final Map<String, dynamic> r;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final balance = r['balance'];
    final room = r['room_number'] != null ? 'Room ${r['room_number']}/${r['bed_label']}' : null;
    final archived = r['is_archived'] == true;
    return ListTile(
      leading: ResidentAvatar(id: toInt(r['id']), name: '${r['name']}', hasPhoto: r['has_photo'] == true),
      title: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text([r['code'], ?room].join(' · ')),
          StatusChip(archived ? 'Archived' : s.label('admission_statuses', r['admission_status']), tone: archived ? 'archived' : '${r['admission_status']}'),
          if (r['source'] == 'online') const StatusChip('Online', tone: 'approved'),
        ],
      ),
      trailing: balance == null
          ? const Icon(Icons.chevron_right)
          : Text(
              toDouble(balance) == 0 ? 'Clear' : money(toDouble(balance).abs()),
              style: TextStyle(fontWeight: FontWeight.w700, color: toDouble(balance) > 0 ? kBad : (toDouble(balance) < 0 ? kInfo : kOk)),
            ),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ResidentDetailScreen(id: toInt(r['id']))));
        onChanged?.call();
      },
    );
  }
}
