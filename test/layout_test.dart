// Renders the main screens with recorded server responses at small phone sizes,
// large text and dark mode. Any overflow ("yellow-black stripes") or exception fails the test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_app/widgets/liquid_nav.dart';
import 'package:hostel_app/core/api.dart';
import 'package:hostel_app/core/format.dart';
import 'package:hostel_app/core/session.dart';
import 'package:hostel_app/core/theme.dart';
import 'package:hostel_app/screens/login_screen.dart';
import 'package:hostel_app/screens/receipt_screen.dart';
import 'package:hostel_app/screens/staff/electricity_screen.dart';
import 'package:hostel_app/screens/staff/expenses_screen.dart';
import 'package:hostel_app/screens/staff/meters_screen.dart';
import 'package:hostel_app/screens/staff/ledger_entry_screen.dart';
import 'package:hostel_app/screens/staff/rent_screen.dart';
import 'package:hostel_app/screens/staff/reports_screen.dart';
import 'package:hostel_app/screens/staff/resident_detail_screen.dart';
import 'package:hostel_app/screens/staff/resident_form_screen.dart';
import 'package:hostel_app/screens/staff/rooms_screen.dart';
import 'package:hostel_app/screens/staff/settings_screen.dart';
import 'package:hostel_app/screens/staff/staff_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

late Map<String, dynamic> fx;

const longName = 'Muhammad Abdul Rehman Siddiqui Qureshi Khan';

http.Client mockClient() => MockClient((req) async {
      final route = req.url.queryParameters['route'] ?? '';
      final rid = fx['resident_id'];
      Object? body;
      if (route == 'me') body = fx['me'];
      if (route == 'dashboard') body = fx['dashboard'];
      if (route == 'residents') body = fx['residents'];
      if (route == 'residents/$rid') body = fx['resident'];
      if (route == 'residents/$rid/room') body = fx['room_tab'];
      if (route == 'residents/$rid/ledger') body = fx['ledger_tab'];
      if (route == 'residents/$rid/documents') body = fx['documents'];
      if (route == 'residents/$rid/medical') body = fx['medical'];
      if (route == 'residents/$rid/purge') body = fx['purge_preview'];
      if (route == 'beds/available') body = fx['beds'];
      if (route == 'rooms') body = fx['rooms'];
      if (route.startsWith('rooms/')) body = fx['room'];
      if (route == 'ledger') body = fx['ledger'];
      if (route.startsWith('receipts/')) body = fx['receipt'];
      if (route == 'rent/preview') body = fx['rent_preview'];
      if (route == 'expenses') body = fx['expenses'];
      if (route == 'expense-categories') body = fx['categories'];
      if (route == 'reports') body = fx['reports'];
      if (route == 'reports/run') body = req.url.queryParameters['type'] == 'occupancy' ? fx['report_occupancy'] : fx['report'];
      if (route == 'settings') body = fx['settings'];
      if (route == 'app/latest') body = fx['app_latest'];
      if (route == 'electricity') body = fx['electricity'];
      if (route == 'electricity/${fx['bill_id']}') body = fx['electricity_bill'];
      if (route == 'meters') body = fx['meters'];
      if (route == 'share') body = fx['share'];
      body ??= {'ok': true};
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

Session signedIn() {
  final s = Session(api: Api(baseUrl: 'https://example.test/hostel', token: 't' * 64, client: mockClient()));
  s.debugSignIn(Map<String, dynamic>.from(fx['me'] as Map));
  return s;
}

class Variant {
  const Variant(this.name, this.size, this.textScale, this.brightness);
  final String name;
  final Size size;
  final double textScale;
  final Brightness brightness;
}

const variants = [
  Variant('small phone', Size(320, 640), 1.0, Brightness.light),
  Variant('large text', Size(360, 740), 1.35, Brightness.light),
  Variant('dark', Size(412, 915), 1.0, Brightness.dark),
];

Future<void> pumpScreen(WidgetTester tester, Variant v, Widget screen, {Session? session}) async {
  tester.view.physicalSize = v.size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<Session>.value(
    value: session ?? signedIn(),
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: v.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(v.textScale)),
        child: child!,
      ),
      home: screen,
    ),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scroll every scrollable to the end so overflow further down is also caught.
Future<void> scrollAll(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final state = tester.state<ScrollableState>(scrollables.at(i));
    if (state.position.axis == Axis.vertical && state.position.maxScrollExtent > 0) {
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pump();
    }
  }
}

void main() {
  setUpAll(() {
    fx = jsonDecode(File('test/fixtures/api.json').readAsStringSync()) as Map<String, dynamic>;
    // Long names are the usual cause of overflow.
    (fx['resident']['resident'] as Map)['name'] = longName;
    (fx['residents']['items'] as List).first['name'] = longName;
    PackageInfo.setMockInitialValues(appName: 'Hostel', packageName: 'com.seojasoos.hostel_app', version: '1.0.0', buildNumber: '5', buildSignature: '');
  });

  for (final v in variants) {
    group(v.name, () {
      testWidgets('sign-in screen', (tester) async {
        await pumpScreen(tester, v, const LoginScreen(), session: Session(api: Api(baseUrl: 'x', client: mockClient()))..state = SessionState.signedOut);
        expect(find.text('Staff sign in'), findsOneWidget);
        expect(find.text('Resident'), findsNothing);
        expect(find.textContaining('http'), findsNothing);
      });

      testWidgets('staff tabs', (tester) async {
        await pumpScreen(tester, v, const StaffShell());
        expect(find.text('Admission'), findsOneWidget);
        if (toInt(fx['dashboard']['online_waiting']) > 0) expect(find.textContaining('new online application'), findsOneWidget);
        await scrollAll(tester);
        for (final tab in ['Residents', 'Rooms', 'Accounts', 'More']) {
          await tester.tap(find.descendant(of: find.byType(LiquidNavBar), matching: find.text(tab)));
          await settle(tester);
          if (tab == 'More') expect(find.text('Permanent delete is on'), findsOneWidget);
          await scrollAll(tester);
        }
        expect(find.text('Check for updates'), findsOneWidget);
      });

      testWidgets('add buttons sit above the floating nav bar', (tester) async {
        // Phone with a 3-button system bar, where the bug showed most.
        tester.view.padding = const FakeViewPadding(bottom: 96);
        tester.view.viewPadding = const FakeViewPadding(bottom: 96);
        addTearDown(tester.view.reset);
        await pumpScreen(tester, v, const StaffShell());
        final navTop = tester.getRect(find.byType(LiquidNavBar)).top;
        for (final tab in ['Residents', 'Rooms']) {
          await tester.tap(find.descendant(of: find.byType(LiquidNavBar), matching: find.text(tab)));
          await settle(tester);
          final fab = find.byType(FloatingActionButton).hitTestable();
          expect(fab, findsOneWidget, reason: '$tab: add button must be tappable');
          expect(tester.getRect(fab).bottom, lessThanOrEqualTo(navTop), reason: '$tab: add button hidden behind nav bar');
        }
      });

      testWidgets('resident profile, all tabs', (tester) async {
        await pumpScreen(tester, v, ResidentDetailScreen(id: fx['resident_id'] as int));
        expect(find.text(longName), findsWidgets);
        for (final tab in ['Profile', 'Room', 'Account', 'Documents', 'Medical']) {
          await tester.tap(find.widgetWithText(Tab, tab));
          await settle(tester);
          await scrollAll(tester);
        }
        await tester.tap(find.byType(PopupMenuButton<String>));
        await settle(tester);
        expect(find.text('Delete permanently'), findsOneWidget);
        await tester.tap(find.text('Delete permanently'));
        await settle(tester);
        expect(find.textContaining('ledger entries'), findsOneWidget);
      });

      testWidgets('forms', (tester) async {
        await pumpScreen(tester, v, const ResidentFormScreen());
        await scrollAll(tester);
        expect(find.text('Emergency contacts'), findsNothing);
        expect(find.text('Local guardian'), findsNothing);
        await pumpScreen(tester, v, const LedgerEntryScreen());
        await scrollAll(tester);
        await pumpScreen(tester, v, const ExpenseFormScreen());
        await scrollAll(tester);
        await pumpScreen(tester, v, const RoomFormScreen());
        await scrollAll(tester);
      });

      testWidgets('rules and payment details page', (tester) async {
        await pumpScreen(tester, v, const HostelSettingsScreen());
        expect(find.text('HOW RESIDENTS PAY'), findsOneWidget);
        expect(find.textContaining('portal/apply.php'), findsOneWidget);
        final rules = (fx['settings']['rules_text'] as Map).values.expand((e) => e as List).length;
        await scrollAll(tester);
        expect(find.text('$rules.'), findsOneWidget, reason: 'last rule is reachable');
      });

      testWidgets('electricity bills', (tester) async {
        await pumpScreen(tester, v, const ElectricityScreen());
        await scrollAll(tester);
        expect(find.textContaining('units'), findsWidgets);
        await pumpScreen(tester, v, ElectricityBillScreen(id: fx['bill_id'] as int));
        await scrollAll(tester);
        expect(find.textContaining('No. '), findsWidgets);
        expect(find.textContaining('Post bill to'), findsOneWidget);
        await pumpScreen(tester, v, NewElectricityBillScreen(defaults: Map<String, dynamic>.from(fx['electricity']['defaults'] as Map)));
        await scrollAll(tester);
      });

      testWidgets('meters and statement', (tester) async {
        await pumpScreen(tester, v, const MetersScreen());
        await scrollAll(tester);
        expect(find.textContaining('MAIN-1'), findsWidgets);
        final resident = Map<String, dynamic>.from(fx['resident']['resident'] as Map);
        await pumpScreen(tester, v, StatementScreen(resident: resident));
        await scrollAll(tester);
        expect(find.text('WhatsApp'), findsOneWidget);
      });

      testWidgets('whatsapp share sheet', (tester) async {
        final resident = Map<String, dynamic>.from(fx['resident']['resident'] as Map);
        await pumpScreen(tester, v, Scaffold(body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ShareSheet.open(context, type: 'reminder', resident: resident),
            child: const Text('go'),
          ),
        )));
        await tester.tap(find.text('go'));
        await settle(tester);
        expect(find.text('Send a payment reminder'), findsOneWidget);
        await tester.tap(find.text('Prepare message'));
        await settle(tester);
        expect(find.text('Open WhatsApp'), findsOneWidget);
      });

      testWidgets('accounts, expenses, reports, rent, room, receipt', (tester) async {
        await pumpScreen(tester, v, const ExpensesScreen());
        await scrollAll(tester);
        await pumpScreen(tester, v, const ReportsScreen());
        await pumpScreen(tester, v, const ReportViewScreen(type: 'payments', title: 'Payments', usesRange: true));
        await scrollAll(tester);
        await pumpScreen(tester, v, const ReportViewScreen(type: 'occupancy', title: 'Occupancy', usesRange: false));
        await scrollAll(tester);
        await pumpScreen(tester, v, const RentScreen());
        await scrollAll(tester);
        await pumpScreen(tester, v, RoomDetailScreen(id: (fx['room']['room'] as Map)['id'] as int));
        await scrollAll(tester);
        if (fx['receipt'] != null) {
          await pumpScreen(tester, v, const ReceiptScreen(route: 'receipts/1'));
          await scrollAll(tester);
        }
      });
    });
  }
}
