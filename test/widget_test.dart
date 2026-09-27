import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_app/core/api.dart';
import 'package:hostel_app/core/format.dart';

void main() {
  test('server address is normalised', () {
    expect(Api.normaliseBase('ai.seojasoos.com/hostel/'), 'https://ai.seojasoos.com/hostel');
    expect(Api.normaliseBase('https://x.com/hostel/api/index.php'), 'https://x.com/hostel');
  });

  test('routes use ?route= so PATH_INFO is not needed', () {
    final api = Api(baseUrl: 'https://ai.seojasoos.com/hostel');
    final u = api.uri('residents/5/ledger', {'page': 2, 'q': null});
    expect(u.toString(), 'https://ai.seojasoos.com/hostel/api/index.php?route=residents%2F5%2Fledger&page=2');
  });

  test('money and initials format', () {
    currencySymbol = 'Rs';
    expect(money(15000), 'Rs 15,000');
    expect(money(-250.5), '-Rs 250.5');
    expect(initials('Bilal Ahmed Khan'), 'BK');
  });
}
