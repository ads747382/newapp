import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../widgets/liquid_nav.dart';
import '../../core/updater.dart';
import 'accounts_screen.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';
import 'residents_screen.dart';
import 'rooms_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selected, this.permission, this.builder);

  final String label;
  final IconData icon;
  final IconData selected;
  final String? permission;
  final Widget Function() builder;
}

/// Bottom navigation for staff. Tabs appear only when the role has the permission.
class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Updater.checkOnStart(context, context.read<Session>().api);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Role or permission changes made on the website show up without signing in again.
      context.read<Session>().refreshQuietly();
      Updater.checkOnStart(context, context.read<Session>().api);
    }
  }

  static final _all = <_Tab>[
    _Tab('Home', Icons.dashboard_outlined, Icons.dashboard, 'dashboard.view', () => const DashboardScreen()),
    _Tab('Residents', Icons.people_outline, Icons.people, 'residents.view', () => const ResidentsScreen()),
    _Tab('Rooms', Icons.bed_outlined, Icons.bed, 'rooms.view', () => const RoomsScreen()),
    _Tab('Accounts', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'accounts.view', () => const AccountsScreen()),
    _Tab('More', Icons.menu, Icons.menu_open, null, () => const MoreScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final tabs = _all.where((t) => t.permission == null || s.can(t.permission!)).toList();
    if (_index >= tabs.length) _index = 0;
    return Scaffold(
      body: Builder(
        builder: (context) {
          // extendBody adds the floating nav bar's height to padding.bottom only. Floating
          // action buttons ("Room", "Resident"…) are placed by viewPadding, so without this they
          // sat underneath the nav bar. Give the tabs the same clearance in both.
          final mq = MediaQuery.of(context);
          final bottom = math.max(mq.padding.bottom, mq.viewPadding.bottom);
          return MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(bottom: bottom),
              viewPadding: mq.viewPadding.copyWith(bottom: bottom),
            ),
            child: IndexedStack(index: _index, children: [for (final t in tabs) t.builder()]),
          );
        },
      ),
      extendBody: true,
      bottomNavigationBar: LiquidNavBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        items: [for (final t in tabs) LiquidNavItem(t.icon, t.selected, t.label)],
      ),
    );
  }
}
