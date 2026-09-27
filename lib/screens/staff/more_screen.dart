import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/updater.dart';
import '../../core/format.dart';
import '../../widgets/common.dart';
import '../../widgets/hostel_picker.dart';
import '../password_screen.dart';
import 'expenses_screen.dart';
import 'reports_screen.dart';
import 'residents_screen.dart';
import 'settings_screen.dart';
import 'attendance_screen.dart';
import 'admin_tools_screen.dart';
import 'printable_forms_screen.dart';
import 'system_update_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final u = s.user ?? {};
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPadding(context)),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(radius: 24, child: Text(initials('${u['name'] ?? '?'}'))),
              title: Text('${u['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${u['role'] ?? ''} · ${u['username'] ?? ''}'),
            ),
          ),
          if (s.canPurge)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: kBad.withValues(alpha: 0.08),
                child: const ListTile(
                  leading: Icon(Icons.warning_amber, color: kBad),
                  title: Text('Permanent delete is on'),
                  subtitle: Text('Turn it off on the website (Hostel settings) before real use.'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                if (s.can('residents.view'))
                  ListTile(
                    leading: const Icon(Icons.assignment_ind_outlined),
                    title: const Text('Admissions in progress'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const ResidentsScreen(initialView: 'admissions')),
                  ),
                if (s.can('expenses.view'))
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Expenses'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const ExpensesScreen()),
                  ),
                if (s.can('reports.view'))
                  ListTile(
                    leading: const Icon(Icons.bar_chart_outlined),
                    title: const Text('Reports'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const ReportsScreen()),
                  ),
                if (s.can('attendance.view'))
                  ListTile(
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: const Text('Attendance'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const AttendanceScreen()),
                  ),
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: const Text('Hostel & rules'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => go(const HostelSettingsScreen()),
                ),
                if (s.can('users.manage') || s.can('roles.manage') || s.can('audit.view') || s.can('backups.manage'))
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Administration'),
                    subtitle: const Text('Users, roles, audit and backups'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const AdminToolsScreen()),
                  ),
                if (s.can('residents.view'))
                  ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('Printable forms'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const PrintableFormsScreen()),
                  ),
                if (s.can('backups.manage'))
                  ListTile(
                    leading: const Icon(Icons.system_update_alt),
                    title: const Text('System update'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => go(const SystemUpdateScreen()),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.apartment_rounded),
                  title: const Text('Change hostel'),
                  subtitle: Text(s.hostel?.name ?? s.hostelName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final h = await pickHostel(context, selected: s.hostel);
                    if (h == null || h == s.hostel || !context.mounted) return;
                    // Stays signed in here; switches to the other hostel's saved login, or its sign-in screen.
                    await context.read<Session>().selectHostel(h);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => go(const PasswordScreen()),
                ),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const Text('Check for updates'),
                    subtitle: Text(snap.hasData ? 'Version ${snap.data!.version} (build ${snap.data!.buildNumber})' : 'Version …'),
                    onTap: () => Updater.checkManually(context, s.api),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: kBad),
                  title: const Text('Sign out', style: TextStyle(color: kBad)),
                  onTap: () async {
                    if (await confirm(context, 'Sign out?', 'You will need your password to sign in again.', ok: 'Sign out')) {
                      await s.logout();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Administration tools now use the same role permissions as the website.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
        ],
      ),
    );
  }
}
