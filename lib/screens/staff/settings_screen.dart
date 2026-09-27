import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../rules_screen.dart';
import 'electricity_screen.dart';

/// Hostel name, contact and printed rules. Everyone can read; settings.manage can edit.
class HostelSettingsScreen extends StatefulWidget {
  const HostelSettingsScreen({super.key});

  @override
  State<HostelSettingsScreen> createState() => _HostelSettingsScreenState();
}

class _HostelSettingsScreenState extends State<HostelSettingsScreen> {
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hostel & rules')),
      body: LoadView(
        key: ValueKey(_gen),
        load: () => api.get('settings'),
        builder: (context, d, _) {
          final st = Map<String, dynamic>.from(d['settings'] as Map);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '${st['hostel_name']}',
                trailing: d['can_edit'] == true
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _SettingsForm(settings: st)));
                          if (ok == true) {
                            if (context.mounted) await context.read<Session>().refreshStaff();
                            setState(() => _gen++);
                          }
                        },
                      )
                    : null,
                child: InfoRows([
                  ('Address', '${st['hostel_address'] ?? ''}'.isEmpty ? '—' : '${st['hostel_address']}'),
                  ('Phone', '${st['hostel_phone'] ?? ''}'.isEmpty ? '—' : '${st['hostel_phone']}'),
                ]),
              ),
              if ((d['payment_details'] as List?)?.isNotEmpty ?? false)
                PaymentDetailsCard(details: (d['payment_details'] as List).cast<Map>(), instructions: '${d['payment_instructions'] ?? ''}'),
              if (st['apply_url'] != null)
                SectionCard(
                  title: 'Online admission form',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        st['apply_enabled'] == true ? 'Open — students can apply from the website.' : 'Closed — the page asks visitors to contact the office.',
                      ),
                      const SizedBox(height: 8),
                      SelectableText('${st['apply_url']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy link'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: '${st['apply_url']}'));
                            showMessage(context, 'Link copied. Share it on WhatsApp.');
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              RulesList(rules: Map<String, dynamic>.from(d['rules_text'] as Map)),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.settings});

  final Json settings;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final Json _rules = Map<String, dynamic>.from(widget.settings['rules'] as Map);
  late final Json _payment = Map<String, dynamic>.from((widget.settings['payment'] as Map?) ?? {});
  late final Map<String, TextEditingController> _c = {
    'hostel_name': TextEditingController(text: '${widget.settings['hostel_name']}'),
    'hostel_address': TextEditingController(text: '${widget.settings['hostel_address'] ?? ''}'),
    'hostel_phone': TextEditingController(text: '${widget.settings['hostel_phone'] ?? ''}'),
    for (final k in ['gate_close', 'visiting_hours', 'quiet_hours', 'rent_due_day', 'late_fee', 'notice_days'])
      'rule_$k': TextEditingController(text: '${_rules[k] ?? ''}'),
    'rule_extra': TextEditingController(text: ((widget.settings['extra_rules'] as List?) ?? const []).join('\n')),
    for (final k in [
      'pay_bank_name',
      'pay_bank_title',
      'pay_bank_account',
      'pay_bank_iban',
      'pay_jazzcash_number',
      'pay_jazzcash_title',
      'pay_easypaisa_number',
      'pay_easypaisa_title',
      'pay_instructions',
    ])
      k: TextEditingController(text: '${_payment[k] ?? ''}'),
  };
  Map<String, String> _errors = {};

  @override
  Widget build(BuildContext context) {
    AppTextField f(String k, String label, {bool req = false, int max = 60, TextInputType? kb, int lines = 1, String? helper}) => AppTextField(
      controller: _c[k]!,
      label: label,
      required: req,
      maxLength: max,
      keyboard: kb,
      maxLines: lines,
      helper: helper,
      error: _errors[k],
      formatters: kb == TextInputType.number ? [FilteringTextInputFormatter.digitsOnly] : null,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Edit hostel settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FormHeading('Hostel', sub: 'Shown in the app, website, receipts and printed forms.'),
          f('hostel_name', 'Hostel name', req: true, max: 100),
          f('hostel_phone', 'Phone', max: 20, kb: TextInputType.phone),
          f('hostel_address', 'Address', max: 160),
          const FormHeading('Printed rules'),
          f('rule_gate_close', 'Gate closing time', req: true, max: 30),
          f('rule_visiting_hours', 'Visiting hours', req: true),
          f('rule_quiet_hours', 'Quiet hours', req: true),
          f('rule_rent_due_day', 'Rent due by (day of month, 1–28)', req: true, max: 2, kb: TextInputType.number),
          f('rule_late_fee', 'Late fee', max: 30, helper: 'e.g. Rs 500. Blank prints “a late fee may be charged”.'),
          f('rule_notice_days', 'Notice before leaving (days)', req: true, max: 3, kb: TextInputType.number),
          f('rule_extra', 'Extra rules (one per line, up to 12)', max: 3000, lines: 6),
          const FormHeading('Payment details', sub: 'Printed on electricity bills and shown to residents.'),
          f('pay_bank_name', 'Bank name', max: 60),
          f('pay_bank_title', 'Bank account title', max: 80),
          f('pay_bank_account', 'Bank account number', max: 40),
          f('pay_bank_iban', 'IBAN', max: 34),
          f('pay_jazzcash_number', 'JazzCash number', max: 20, kb: TextInputType.phone),
          f('pay_jazzcash_title', 'JazzCash account name', max: 80),
          f('pay_easypaisa_number', 'Easypaisa number', max: 20, kb: TextInputType.phone),
          f('pay_easypaisa_title', 'Easypaisa account name', max: 80),
          f('pay_instructions', 'Payment instructions', max: 300, lines: 2),
          FilledButton(
            onPressed: () async {
              final api = apiOf(context);
              final nav = Navigator.of(context);
              try {
                await api.post('settings', {for (final e in _c.entries) e.key: e.value.text.trim()});
                if (context.mounted) showMessage(context, 'Hostel settings saved.');
                nav.pop(true);
              } on ApiException catch (e) {
                setState(() => _errors = e.errors);
                if (e.errors.isEmpty && context.mounted) showMessage(context, e.message, error: true);
              }
            },
            child: const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}
