import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_app/core/hostels.dart';

void main() {
  test('accepts both list shapes and normalises urls', () {
    final a = HostelDirectory.parse('[{"name":"A","url":"https://ai.seojasoos.com/hostel/"}]');
    final b = HostelDirectory.parse('{"hostels":[{"name":"B","url":"https://ai.seojasoos.com/hostel1","subtitle":"Jhang"}]}');
    expect(a.single.url, 'https://ai.seojasoos.com/hostel');
    expect(b.single.subtitle, 'Jhang');
  });

  test('rejects anything outside the allow-list', () {
    final list = HostelDirectory.parse('''[
      {"name":"http","url":"http://ai.seojasoos.com/hostel2"},
      {"name":"other host","url":"https://evil.example/hostel"},
      {"name":"lookalike","url":"https://ai.seojasoos.com.evil.example/h"},
      {"name":"userinfo","url":"https://ai.seojasoos.com@evil.example/h"},
      {"name":"port","url":"https://ai.seojasoos.com:8443/h"},
      {"name":"query","url":"https://ai.seojasoos.com/h?x=1"},
      {"name":"dots","url":"https://ai.seojasoos.com/h/../x"},
      {"name":"","url":"https://ai.seojasoos.com/noname"},
      {"name":"ok","url":"https://ai.seojasoos.com/hostel3"},
      {"name":"dup","url":"https://ai.seojasoos.com/hostel3/"}
    ]''');
    expect(list.map((h) => h.name), ['ok']);
  });

  test('bad json gives nothing, built-in list is valid', () {
    expect(HostelDirectory.parse('{"hostels": 5}'), isEmpty);
    expect(HostelDirectory.builtIn, isNotEmpty);
    for (final h in HostelDirectory.builtIn) {
      expect(Hostel.isAllowedUrl(h.url), isTrue);
    }
  });

  test('follows a hostel that moved to the new domain', () {
    const old = Hostel(name: 'H2', url: 'https://ai.seojasoos.com/hostel2');
    final list = HostelDirectory.parse('[{"name":"Makkah Hostel","url":"https://makkahhostel.com/hostel"},'
        '{"name":"Makkah Hostel 2","url":"https://makkahhostel.com/hostel2"}]');
    expect(HostelDirectory.movedTo(old, list)?.url, 'https://makkahhostel.com/hostel2');
    expect(HostelDirectory.movedTo(list.first, list), isNull);
    expect(HostelDirectory.parse('[{"name":"x","url":"https://evil.example/hostel2"}]'), isEmpty);
  });
}
