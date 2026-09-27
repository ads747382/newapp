import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/api.dart';
import '../../widgets/common.dart';

class PrintableFormsScreen extends StatelessWidget {
  const PrintableFormsScreen({super.key});

  Future<Uint8List> _build(Api api, {bool rulesOnly = false, int copies = 1}) async {
    final d = await api.get('forms/admission');
    final hostel = Map<String, dynamic>.from(d['hostel'] as Map);
    final rules = Map<String, dynamic>.from(d['rules'] as Map);
    final doc = pw.Document();
    for (var copy = 0; copy < copies; copy++) {
      if (!rulesOnly) {
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Text('${hostel['name']}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            if ('${hostel['contact'] ?? ''}'.isNotEmpty) pw.Text('${hostel['contact']}'),
            pw.SizedBox(height: 14),
            pw.Text('ADMISSION FORM', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            _line('Full name'), _line('Father / husband name'), _line('CNIC / national ID'), _line('Phone'), _line('Alternate phone'), _line('Email'),
            _line('Date of birth'), _line('Gender'), _line('Home city'), _line('Permanent address', tall: true),
            pw.SizedBox(height: 10), pw.Text('Study / Work', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _line('Occupation'), _line('Institution / employer'), _line('Course / designation'), _line('Institution / employer address', tall: true),
            pw.SizedBox(height: 10), pw.Text('Father / Guardian', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _line('Name'), _line('Phone'), _line('CNIC'), _line('Occupation'), _line('Address', tall: true),
            pw.SizedBox(height: 10), pw.Text('Medical / Documents', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Blood group: __________   AC sensitivity: __________   Allergies / health notes: ______________________________'),
            pw.SizedBox(height: 8),
            pw.Text('Documents:  □ Photo   □ CNIC   □ Police verification   □ Medical   □ Admission form'),
            pw.SizedBox(height: 12), pw.Text('Office use', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Resident code: __________   Room/Bed: __________   Admission date: __________   Rent: __________   Deposit: __________'),
          ],
        ));
      }
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) {
          var n = 0;
          return [
            pw.Text('${hostel['name']} — Rules & Regulations', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            for (final e in rules.entries) ...[
              pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              for (final r in (e.value as List)) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text('${++n}. $r')),
              pw.SizedBox(height: 6),
            ],
            if (!rulesOnly) ...[
              pw.SizedBox(height: 14),
              pw.Text('Declaration', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('I have read and understood the hostel rules and agree to follow them.'),
              pw.SizedBox(height: 26),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Resident signature: ______________'), pw.Text('Parent signature: ______________')]),
              pw.SizedBox(height: 22), pw.Text('Hostel manager: ______________    Date: ______________'),
            ],
          ];
        },
      ));
    }
    return doc.save();
  }

  static pw.Widget _line(String label, {bool tall = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Container(height: tall ? 38 : 24, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: .6))), child: pw.Align(alignment: pw.Alignment.bottomLeft, child: pw.Text('$label:'))),
  );

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Printable forms')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Admission form'), subtitle: const Text('Personal details + rules + declaration'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PdfScreen(title: 'Admission form', build: () => _build(api))))),
        Card(child: ListTile(leading: const Icon(Icons.copy_all_outlined), title: const Text('Admission form — 5 copies'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PdfScreen(title: 'Admission form — 5 copies', build: () => _build(api, copies: 5))))),
        Card(child: ListTile(leading: const Icon(Icons.rule_outlined), title: const Text('Rules only'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PdfScreen(title: 'Rules & regulations', build: () => _build(api, rulesOnly: true))))),
      ]),
    );
  }
}

class _PdfScreen extends StatelessWidget {
  const _PdfScreen({required this.title, required this.build});
  final String title;
  final Future<Uint8List> Function() build;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: PdfPreview(build: (_) => build(), canChangeOrientation: false, canChangePageFormat: false));
}
