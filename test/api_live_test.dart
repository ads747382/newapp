// Runs only when HOSTEL_TEST_SERVER is set (local integration check; skipped on CI).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_app/core/api.dart';

void main() {
  final server = Platform.environment['HOSTEL_TEST_SERVER'];
  test('live API flow used by the app screens', () async {
    final api = Api(baseUrl: server!);
    final ping = await api.get('ping');
    expect(ping['database_ready'], true);

    final login = await api.post('auth/login', {'username': 'admin', 'password': 'Str0ng!Passw0rd#2026', 'device': 'test'});
    api.token = login['token'] as String;
    expect((login['constants'] as Map)['ledger_types'], isA<List>());

    final dash = await api.get('dashboard');
    expect(dash['occupancy'], isA<Map>());

    final list = await api.get('residents', query: {'view': 'all', 'page': 1, 'sort': 'name'});
    final rid = (list['items'] as List).first['id'];
    final detail = await api.get('residents/$rid');
    for (final k in ['resident', 'contacts', 'checklist', 'next_statuses', 'balance', 'medical', 'portal']) {
      expect(detail.containsKey(k), true, reason: k);
    }

    // Validation errors come back as a field map the form can show.
    try {
      await api.post('residents', {'full_name': '', 'contacts': {'emergency': []}});
      fail('should fail');
    } on ApiException catch (e) {
      expect(e.status, 422);
      expect(e.errors.containsKey('full_name'), true);
      expect(e.errors.containsKey('contacts.emergency'), true);
    }

    final created = await api.post('residents', {
      'full_name': 'App Test User', 'phone': '0333-1231234', 'gender': '', 'occupation': 'student',
      'rent_override': '', 'security_deposit_amount': '5000', 'admission_date': '2026-09-10',
      'contacts': {
        'father': [{'name': '', 'phone': ''}],
        'guardian': [{'name': '', 'phone': ''}],
        'emergency': [{'name': 'Brother', 'relation': 'Brother', 'phone': '0300-1112222', 'address': ''}],
      },
    });
    final newId = created['id'];

    // Multipart photo + documents, same as the app.
    final png = File('/home/claude/test/fp-1.png').readAsBytesSync();
    await api.upload('residents/$newId/photo', files: [UploadFile(field: 'photo', filename: 'p.png', bytes: png)]);
    final photo = await api.bytes('residents/$newId/photo');
    expect(photo.length, greaterThan(100));
    final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
    final up = await api.upload('residents/$newId/documents',
        fields: {'doc_type': 'cnic', 'status': 'received', 'title': ''},
        files: [UploadFile(field: 'files[]', filename: 'a.pdf', bytes: pdf), UploadFile(field: 'files[]', filename: 'b.png', bytes: png)]);
    expect(up['uploaded'], 2);

    await api.post('residents/$newId/status', {'admission_status': 'under_verification', 'verification_status': 'verified', 'note': ''});
    await api.post('residents/$newId/status', {'admission_status': 'approved', 'verification_status': 'verified', 'note': ''});
    final beds = await api.get('beds/available');
    final bed = (beds['beds'] as List).first['bed_id'];
    await api.post('residents/$newId/room', {'action': 'assign', 'bed_id': bed, 'date': '2026-09-10', 'reason': ''});

    final pay = await api.post('ledger', {
      'resident_id': newId, 'entry_type': 'payment', 'amount': '1500.50', 'entry_date': '2026-09-11',
      'period_month': '', 'method': 'cash', 'reference': '', 'description': '',
    });
    expect(pay['has_receipt'], true);
    final receipt = await api.get('receipts/${pay['id']}');
    expect((receipt['receipt'] as Map)['amount'], 1500.5);
    final ledger = await api.get('residents/$newId/ledger', query: {'void': null});
    expect((ledger['entries'] as List).length, 1);

    final cats = await api.get('expense-categories');
    final cat = (cats['categories'] as List).first['id'];
    final exp = await api.upload('expenses', fields: {
      'expense_date': '2026-09-11', 'category_id': '$cat', 'amount': '999', 'paid_to': 'Test', 'method': 'cash',
      'reference': '', 'description': '',
    }, files: [UploadFile(field: 'receipt', filename: 'bill.png', bytes: png)]);
    final edited = await api.upload('expenses/${exp['id']}', fields: {
      'expense_date': '2026-09-11', 'category_id': '$cat', 'amount': '1000', 'paid_to': 'Test', 'method': 'cash',
      'reference': '', 'description': 'edited', 'remove_receipt': '1',
    });
    expect(edited['message'], 'Expense updated.');

    final rooms = await api.get('rooms', query: {'availability': '', 'type': ''});
    expect(rooms['rooms'], isA<List>());
    final room = await api.post('rooms', {'room_number': 'T-${DateTime.now().millisecondsSinceEpoch % 100000}', 'floor': '', 'room_type': 'Normal', 'capacity': '3', 'monthly_rent': '9000', 'status': 'active', 'notes': ''});
    expect(room['id'], isNotNull);

    final rep = await api.get('reports/run', query: {'type': 'collection', 'from': '2026-01-01', 'to': '2026-12-31'});
    expect(rep['columns'], isA<List>());

    final settings = await api.get('settings');
    expect(settings['rules_text'], isA<Map>());
    await api.post('settings', {
      'hostel_name': 'Al-Noor Boys Hostel', 'hostel_address': '', 'hostel_phone': '',
      'rule_gate_close': '10:00 PM', 'rule_visiting_hours': '4 to 7', 'rule_quiet_hours': '11 to 7',
      'rule_rent_due_day': '10', 'rule_late_fee': '', 'rule_notice_days': '30', 'rule_extra': '',
    });

    final portal = await api.post('residents/$newId/portal', {'action': 'issue'});
    final res = Api(baseUrl: server);
    final rl = await res.post('portal/login', {'login_id': portal['login_id'], 'password': portal['password'], 'device': 'test'});
    res.token = rl['token'] as String;
    expect((rl['resident'] as Map)['must_change_password'], true);
    await res.post('portal/password', {'current_password': portal['password'], 'new_password': 'AppTest2026pass'});
    final me = await res.get('portal/me');
    expect(me['balance'], isA<num>());
    final pays = await res.get('portal/payments', query: {'page': 1});
    expect((pays['items'] as List).length, 1);
    final rules = await res.get('portal/rules');
    expect(rules['rules'], isA<Map>());

    // Download document bytes like the app does; JSON errors throw.
    final docs = await api.get('residents/$newId/documents');
    final docId = (docs['documents'] as List).first['id'];
    expect((await api.bytes('documents/$docId/file')).isNotEmpty, true);
    await expectLater(api.bytes('documents/999999/file'), throwsA(isA<ApiException>()));

    await api.post('auth/logout');
    await expectLater(api.get('me'), throwsA(predicate((e) => e is ApiException && e.status == 401)));
  }, tags: const ['integration'], skip: server == null ? 'set HOSTEL_TEST_SERVER to run' : false, timeout: const Timeout(Duration(minutes: 2)));
}
