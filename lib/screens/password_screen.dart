import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';

/// Change password for staff or residents. When [forced], it is the only screen until the password is changed.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, this.forced = false});

  final bool forced;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  Map<String, String> _errors = {};
  bool _busy = false;

  Future<void> _save() async {
    final s = context.read<Session>();
    if (_new.text != _confirm.text) {
      setState(() => _errors = {'confirm_password': 'The passwords do not match.'});
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await s.api.post(s.state == SessionState.resident ? 'portal/password' : 'me/password', {'current_password': _current.text, 'new_password': _new.text});
      await s.passwordChanged();
      if (!mounted) return;
      showMessage(context, 'Password saved.');
      if (!widget.forced) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors = e.errors.isEmpty ? {'current_password': e.message} : e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forced ? 'Choose your password' : 'Change password'),
        automaticallyImplyLeading: !widget.forced,
        actions: [if (widget.forced) TextButton(onPressed: s.logout, child: const Text('Sign out'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.forced)
            const Padding(padding: EdgeInsets.only(bottom: 16), child: Text('You signed in with a temporary password. Choose your own password to continue.')),
          PasswordInput(controller: _current, label: widget.forced ? 'Temporary password' : 'Current password', error: _errors['current_password']),
          PasswordInput(
            controller: _new,
            label: 'New password',
            error: _errors['new_password'],
            helper: 'At least 10 characters with letters and numbers.',
            autofill: const [AutofillHints.newPassword],
          ),
          PasswordInput(controller: _confirm, label: 'Confirm new password', error: _errors['confirm_password']),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save password')),
          const SizedBox(height: 12),
          const Text('Your other signed-in phones will be signed out.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
