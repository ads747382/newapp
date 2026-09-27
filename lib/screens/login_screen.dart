import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/fields.dart';
import '../widgets/hostel_picker.dart';

const kBrandBrown = Color(0xFF3C1507);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _residentMode = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.read<Session>();
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = _residentMode ? 'Enter your resident ID and password.' : 'Enter your username and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_residentMode) {
        await s.loginResident(_user.text, _pass.text);
      } else {
        await s.loginStaff(_user.text, _pass.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kBrandBrown,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
                        ),
                        child: ClipOval(child: Image.asset('assets/icon/logo.png', fit: BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _residentMode ? 'Resident sign in' : 'Staff sign in',
                      textAlign: TextAlign.center,
                      style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(_residentMode ? 'Use your resident portal account.' : 'Use your hostel staff account.', textAlign: TextAlign.center, style: t.bodyMedium),
                    const SizedBox(height: 24),
                    if (s.hostel == null) ...[
                      Text('Choose your hostel', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      HostelList(onSelected: s.selectHostel),
                      const SizedBox(height: 16),
                    ] else ...[
                      _HostelCard(
                        name: s.hostel!.name,
                        onChange: _busy
                            ? null
                            : () async {
                                final h = await pickHostel(context, selected: s.hostel);
                                if (h != null && context.mounted) {
                                  setState(() => _error = null);
                                  await context.read<Session>().selectHostel(h);
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      if (s.notice != null && _error == null)
                        _Banner(
                          text: s.notice!,
                          action: s.hasSavedLogin ? TextButton(onPressed: s.retrySaved, child: const Text('Retry')) : null,
                        ),
                      if (_error != null) _Banner(text: _error!, error: true),
                      AppTextField(controller: _user, label: _residentMode ? 'Resident ID' : 'Username', autofill: const [AutofillHints.username]),
                      PasswordInput(controller: _pass, label: 'Password', autofill: const [AutofillHints.password]),
                      const SizedBox(height: 4),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Sign in'),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _busy ? null : () => setState(() { _residentMode = !_residentMode; _error = null; _user.clear(); _pass.clear(); }),
                        icon: Icon(_residentMode ? Icons.admin_panel_settings_outlined : Icons.person_outline),
                        label: Text(_residentMode ? 'Staff sign in instead' : 'Resident sign in'),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(_residentMode ? 'Forgot your password? Ask hostel staff to reset it.' : 'Forgot your password? Ask a Super Admin to reset it.', textAlign: TextAlign.center, style: t.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HostelCard extends StatelessWidget {
  const _HostelCard({required this.name, this.onChange});

  final String name;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.apartment_rounded, color: kPrimary),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Signing in to this hostel'),
        trailing: TextButton(onPressed: onChange, child: const Text('Change')),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.error = false, this.action});

  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = error ? kBad : kWarn;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.info_outline, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: c)),
          ),
          ?action,
        ],
      ),
    );
  }
}
