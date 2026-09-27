import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/pickers.dart';
import 'resident_detail_screen.dart';

class _Contact {
  _Contact([Map? c])
    : name = TextEditingController(text: '${c?['name'] ?? ''}'),
      relation = TextEditingController(text: '${c?['relation'] ?? ''}'),
      phone = TextEditingController(text: '${c?['phone'] ?? ''}'),
      altPhone = TextEditingController(text: '${c?['alt_phone'] ?? ''}'),
      cnic = TextEditingController(text: '${c?['cnic'] ?? ''}'),
      occupation = TextEditingController(text: '${c?['occupation'] ?? ''}'),
      address = TextEditingController(text: '${c?['address'] ?? ''}');

  final TextEditingController name, relation, phone, altPhone, cnic, occupation, address;

  Map<String, String> toJson() => {
    'name': name.text.trim(),
    'relation': relation.text.trim(),
    'phone': phone.text.trim(),
    'alt_phone': altPhone.text.trim(),
    'cnic': cnic.text.trim(),
    'occupation': occupation.text.trim(),
    'address': address.text.trim(),
  };
}

/// New admission or edit. [existing] is the resident detail response.
class ResidentFormScreen extends StatefulWidget {
  const ResidentFormScreen({super.key, this.existing});

  final Json? existing;

  @override
  State<ResidentFormScreen> createState() => _ResidentFormScreenState();
}

class _ResidentFormScreenState extends State<ResidentFormScreen> {
  static const _textFields = [
    'full_name',
    'father_name',
    'cnic',
    'phone',
    'alt_phone',
    'email',
    'city',
    'permanent_address',
    'organization',
    'designation_or_course',
    'organization_address',
    'rent_override',
    'security_deposit_amount',
    'notes',
  ];

  late final Json _r = Map<String, dynamic>.from((widget.existing?['resident'] as Map?) ?? {});
  late final Map<String, TextEditingController> _c = {for (final k in _textFields) k: TextEditingController(text: _initial(k))};
  late String? _gender = _r['gender'] as String?;
  late String? _occupation = _r['occupation'] as String?;
  late String? _dob = _r['date_of_birth'] as String?;
  late String? _admission = (_r['admission_date'] as String?) ?? (widget.existing == null ? today() : null);
  late String? _leave = _r['expected_leave_date'] as String?;
  late final _Contact _father = _Contact(_firstContact('father'));
  UploadFile? _photo;
  final _tracker = DirtyTracker();
  final _depositNow = TextEditingController();
  final _depositRef = TextEditingController();
  final _upfront = TextEditingController();
  final _upfrontRef = TextEditingController();
  bool _depositReceivedNow = false;
  bool _upfrontReceivedNow = false;
  String _depositMethod = 'cash';
  String _upfrontMethod = 'cash';
  Map<String, String> _errors = {};
  bool _busy = false;

  bool get _editing => widget.existing != null;

  String _initial(String k) {
    final v = _r[k];
    if (v == null) return '';
    if (k == 'rent_override' || k == 'security_deposit_amount') {
      final d = toDouble(v);
      return d == 0 && k == 'security_deposit_amount' ? '' : d.toStringAsFixed(d.truncateToDouble() == d ? 0 : 2);
    }
    return '$v';
  }

  Map? _firstContact(String type) {
    final list = (widget.existing?['contacts'] as Map?)?[type] as List?;
    return (list == null || list.isEmpty) ? null : list.first as Map;
  }

  @override
  void initState() {
    super.initState();
    _tracker.start(_values());
  }

  List<Object?> _values() => [
    for (final c in _c.values) c.text,
    _gender,
    _occupation,
    _dob,
    _admission,
    _leave,
    _photo?.filename,
    _father.toJson().values.join('|'),
    _depositReceivedNow, _depositNow.text, _depositMethod, _depositRef.text,
    _upfrontReceivedNow, _upfront.text, _upfrontMethod, _upfrontRef.text,
  ];

  Future<void> _save() async {
    final s = context.read<Session>();
    setState(() {
      _busy = true;
      _errors = {};
    });
    final body = <String, Object?>{
      for (final k in _textFields) k: _c[k]!.text.trim(),
      'gender': _gender ?? '',
      'occupation': _occupation ?? '',
      'date_of_birth': _dob ?? '',
      'admission_date': _admission ?? '',
      'expected_leave_date': _leave ?? '',
      'contacts': {
        'father': [_father.toJson()],
      },
      if (!_editing && _depositReceivedNow) 'deposit_received_now': true,
      if (!_editing && _depositReceivedNow) 'deposit_amount_now': _depositNow.text.trim(),
      if (!_editing && _depositReceivedNow) 'deposit_method': _depositMethod,
      if (!_editing && _depositReceivedNow) 'deposit_reference': _depositRef.text.trim(),
      if (!_editing && _upfrontReceivedNow) 'upfront_received_now': true,
      if (!_editing && _upfrontReceivedNow) 'upfront_amount': _upfront.text.trim(),
      if (!_editing && _upfrontReceivedNow) 'upfront_method': _upfrontMethod,
      if (!_editing && _upfrontReceivedNow) 'upfront_reference': _upfrontRef.text.trim(),
    };
    if (!s.can('accounts.view')) {
      body.remove('rent_override');
      body.remove('security_deposit_amount');
    }
    try {
      final res = await s.api.post(_editing ? 'residents/${_r['id']}' : 'residents', body);
      final id = toInt(res['id']);
      if (_photo != null) {
        try {
          await s.api.upload('residents/$id/photo', files: [_photo!]);
        } on ApiException catch (e) {
          if (mounted) showMessage(context, 'Saved, but the photo was not uploaded: ${e.message}', error: true);
        }
      }
      if (!mounted) return;
      _tracker.start(_values());
      showMessage(context, '${res['message']}');
      if (_editing) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResidentDetailScreen(id: id)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.errors);
      showMessage(context, e.errors.isEmpty ? e.message : 'Please fix the highlighted fields.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _e(String key) => _errors[key];

  List<Choice> _opts(String name) => [for (final o in context.read<Session>().options(name)) Choice('${o['value']}', '${o['label']}')];

  Widget _contactFields(String type, int index, _Contact c, {bool relation = true, bool full = true}) {
    String? err(String f) => _errors['contacts.$type.$index.$f'];
    return Column(
      children: [
        AppTextField(controller: c.name, label: 'Name', maxLength: 120, error: err('name'), capitalization: TextCapitalization.words),
        if (relation) AppTextField(controller: c.relation, label: 'Relation', maxLength: 60, error: err('relation')),
        AppTextField(controller: c.phone, label: 'Phone', keyboard: TextInputType.phone, maxLength: 20, error: err('phone'), hint: '0300-1234567'),
        AppTextField(controller: c.altPhone, label: 'Alternate phone', keyboard: TextInputType.phone, maxLength: 20, error: err('alt_phone')),
        if (full) ...[
          AppTextField(controller: c.cnic, label: 'CNIC', keyboard: TextInputType.number, maxLength: 15, error: err('cnic'), hint: '35202-1234567-1'),
          AppTextField(controller: c.occupation, label: 'Occupation', maxLength: 120, error: err('occupation')),
        ],
        AppTextField(controller: c.address, label: 'Address', maxLength: 255, error: err('address')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return UnsavedGuard(
      isDirty: () => !_busy && _tracker.isDirty(_values()),
      child: Scaffold(
        appBar: AppBar(title: Text(_editing ? 'Edit ${_r['name']}' : 'New admission')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_errors.isNotEmpty)
              Card(
                color: kBad.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_errors.values.toSet().join('\n'), style: const TextStyle(color: kBad)),
                ),
              ),
            const FormHeading('Personal information', sub: 'Name and phone are required.'),
            if (!_editing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: _photo == null ? null : MemoryImage(_photo!.bytes),
                      child: _photo == null ? const Icon(Icons.person, size: 32) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(_photo == null ? 'Add photo' : 'Change photo'),
                        onPressed: () async {
                          final f = await pickUploads(context, field: 'photo', allowFiles: false, imagesOnly: true, title: 'Profile photo', maxWidth: 1200);
                          if (f.isNotEmpty) setState(() => _photo = f.first);
                        },
                      ),
                    ),
                    if (_photo != null) IconButton(tooltip: 'Remove photo', icon: const Icon(Icons.close), onPressed: () => setState(() => _photo = null)),
                  ],
                ),
              ),
            AppTextField(
              controller: _c['full_name']!,
              label: 'Full name',
              required: true,
              maxLength: 120,
              error: _e('full_name'),
              capitalization: TextCapitalization.words,
            ),
            AppTextField(
              controller: _c['father_name']!,
              label: 'Father / husband name',
              maxLength: 120,
              error: _e('father_name'),
              capitalization: TextCapitalization.words,
            ),
            ChoiceInput(
              label: 'Gender',
              value: _gender,
              allowEmpty: true,
              choices: _opts('genders'),
              onChanged: (v) => setState(() => _gender = v),
              error: _e('gender'),
            ),
            DateInput(label: 'Date of birth', value: _dob, last: DateTime.now(), onChanged: (v) => setState(() => _dob = v), error: _e('date_of_birth')),
            AppTextField(
              controller: _c['cnic']!,
              label: 'CNIC / national ID',
              keyboard: TextInputType.number,
              maxLength: 15,
              hint: '35202-1234567-1',
              error: _e('cnic'),
            ),
            AppTextField(
              controller: _c['phone']!,
              label: 'Phone',
              required: true,
              keyboard: TextInputType.phone,
              maxLength: 20,
              hint: '0300-1234567',
              error: _e('phone'),
            ),
            AppTextField(controller: _c['alt_phone']!, label: 'Alternate phone', keyboard: TextInputType.phone, maxLength: 20, error: _e('alt_phone')),
            AppTextField(controller: _c['email']!, label: 'Email', keyboard: TextInputType.emailAddress, maxLength: 160, error: _e('email')),
            AppTextField(controller: _c['city']!, label: 'Home city', maxLength: 80, error: _e('city')),
            AppTextField(controller: _c['permanent_address']!, label: 'Permanent address', maxLines: 2, maxLength: 255, error: _e('permanent_address')),
            const FormHeading('Occupation'),
            ChoiceInput(
              label: 'Occupation',
              value: _occupation,
              allowEmpty: true,
              choices: _opts('occupations'),
              onChanged: (v) => setState(() => _occupation = v),
              error: _e('occupation'),
            ),
            AppTextField(controller: _c['organization']!, label: 'Institution / employer', maxLength: 160, error: _e('organization')),
            AppTextField(controller: _c['designation_or_course']!, label: 'Course or designation', maxLength: 120, error: _e('designation_or_course')),
            AppTextField(controller: _c['organization_address']!, label: 'Institution / employer address', maxLength: 255, error: _e('organization_address')),
            const FormHeading('Admission and rent'),
            DateInput(label: 'Admission date', value: _admission, onChanged: (v) => setState(() => _admission = v), error: _e('admission_date')),
            DateInput(label: 'Expected leaving date', value: _leave, onChanged: (v) => setState(() => _leave = v), error: _e('expected_leave_date')),
            if (s.can('accounts.view')) ...[
              AmountInput(
                controller: _c['security_deposit_amount']!,
                label: 'Security deposit agreed',
                error: _e('security_deposit_amount'),
                helper: 'Record receiving it from the Account tab.',
              ),
              AmountInput(
                controller: _c['rent_override']!,
                label: 'Custom monthly rent',
                error: _e('rent_override'),
                helper: 'Leave blank to use the room rent.',
              ),
              if (!_editing && s.can('accounts.manage')) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Deposit received now'),
                  subtitle: const Text('Record the security deposit in the ledger with this admission.'),
                  value: _depositReceivedNow,
                  onChanged: (v) => setState(() => _depositReceivedNow = v),
                ),
                if (_depositReceivedNow) ...[
                  AmountInput(controller: _depositNow, label: 'Deposit amount received', helper: 'Leave blank to receive the outstanding agreed deposit.'),
                  ChoiceInput(label: 'Deposit method', value: _depositMethod, choices: _opts('payment_methods'), onChanged: (v) => setState(() => _depositMethod = v ?? 'cash')),
                  if (_depositMethod != 'cash') AppTextField(controller: _depositRef, label: 'Deposit reference', maxLength: 80),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Upfront payment received'),
                  subtitle: const Text('Record rent/advance received at admission.'),
                  value: _upfrontReceivedNow,
                  onChanged: (v) => setState(() => _upfrontReceivedNow = v),
                ),
                if (_upfrontReceivedNow) ...[
                  AmountInput(controller: _upfront, label: 'Upfront amount'),
                  ChoiceInput(label: 'Payment method', value: _upfrontMethod, choices: _opts('payment_methods'), onChanged: (v) => setState(() => _upfrontMethod = v ?? 'cash')),
                  if (_upfrontMethod != 'cash') AppTextField(controller: _upfrontRef, label: 'Payment reference', maxLength: 80),
                ],
              ],
            ],
            const FormHeading('Father'),
            _contactFields('father', 0, _father, relation: false),
            const FormHeading('Notes'),
            AppTextField(controller: _c['notes']!, label: 'Internal notes', maxLines: 3, maxLength: 2000, error: _e('notes')),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : (_editing ? 'Save changes' : 'Save admission'))),
          ],
        ),
      ),
    );
  }
}
