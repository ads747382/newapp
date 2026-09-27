import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'screens/password_screen.dart';
import 'screens/staff/staff_shell.dart';
import 'screens/portal/portal_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(ChangeNotifierProvider(create: (_) => Session()..load(), child: const HostelApp()));
}

class HostelApp extends StatelessWidget {
  const HostelApp({super.key});

  @override
  Widget build(BuildContext context) {
    final title = context.select<Session, String>((s) => s.hostelName);
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const Gate(),
    );
  }
}

/// Chooses the first screen from the sign-in state.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final Widget child = switch (s.state) {
      SessionState.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      SessionState.signedOut => const LoginScreen(),
      _ when s.mustChangePassword => const PasswordScreen(forced: true),
      SessionState.staff => const StaffShell(),
      SessionState.resident => const PortalShell(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey('${s.state}-${s.mustChangePassword}'), child: child),
    );
  }
}
