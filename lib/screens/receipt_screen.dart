import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/documents.dart';
import 'staff/meters_screen.dart';

/// Payment receipt for staff (receipts/{id}) or residents (portal/receipts/{id}).
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.route, this.phone, this.entryId, this.residentId});

  final String route;
  final String? phone;

  /// Ledger entry id, so the receipt PDF and the WhatsApp link can be built.
  final int? entryId;
  final int? residentId;

  static String asText(Json r) {
    final b = StringBuffer()
      ..writeln('*${r['hostel']}*')
      ..writeln('Payment receipt ${r['receipt_no']}')
      ..writeln('Date: ${fmtDate(r['date'])}')
      ..writeln('Received from: ${r['resident']['name']} (${r['resident']['code']})')
      ..writeln('Amount: ${money(r['amount'])}')
      ..writeln('For: ${r['type_label']}${r['description'] != null ? ' — ${r['description']}' : ''}');
    if (r['method'] != null) b.writeln('Method: ${r['method']}${r['reference'] != null ? ' (${r['reference']})' : ''}');
    b.writeln('Balance after: ${money(r['balance_after'])}');
    if (r['is_void'] == true) b.writeln('VOID: ${r['void_reason']}');
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: LoadView(
        load: () => api.get(route),
        builder: (context, data, _) {
          final r = Map<String, dynamic>.from(data['receipt'] as Map);
          final t = Theme.of(context).textTheme;
          final balance = toDouble(r['balance_after']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['hostel']}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      if ('${r['contact'] ?? ''}'.isNotEmpty) Text('${r['contact']}', style: t.bodySmall),
                      const Divider(height: 24),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          Text('PAYMENT RECEIPT', style: t.labelLarge?.copyWith(letterSpacing: 1.2)),
                          SelectableText('${r['receipt_no']}', style: t.titleSmall),
                        ],
                      ),
                      Text(fmtDate(r['date']), style: t.bodySmall),
                      if (r['is_void'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: StatusChip('VOID — ${r['void_reason']}', tone: 'void'),
                        ),
                      const SizedBox(height: 16),
                      const Text('Received with thanks from'),
                      Text('${r['resident']['name']}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (r['resident']['father_name'] != null) Text('s/o, d/o ${r['resident']['father_name']}', style: t.bodySmall),
                      const SizedBox(height: 16),
                      Text(
                        money(r['amount']),
                        style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: kPrimary),
                      ),
                      const SizedBox(height: 16),
                      InfoRows([
                        ('For', '${r['type_label']}${r['description'] != null ? ' — ${r['description']}' : ''}'),
                        if (r['period_month'] != null) ('Month', fmtMonth(r['period_month'])),
                        ('Method', orDash(r['method'])),
                        if (r['reference'] != null) ('Reference', '${r['reference']}'),
                        ('Resident ID', '${r['resident']['code']}'),
                        if (r['room'] != null) ('Room / bed', '${r['room']}'),
                        ('Received by', orDash(r['received_by'])),
                        (balance < 0 ? 'Credit after this' : 'Balance after this', money(balance.abs())),
                        ('Deposit held', money(r['deposit_held'])),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (entryId != null)
                DocumentActionBar(
                  doc: ServerDocument(route: 'receipts/$entryId/pdf', filename: 'receipt-${r['receipt_no']}.pdf', title: 'Receipt ${r['receipt_no']}'),
                  onWhatsApp: residentId == null
                      ? null
                      : () => ShareSheet.open(
                          context,
                          type: 'receipt',
                          resident: {'id': residentId, 'name': r['resident']['name'], 'code': r['resident']['code'], 'phone': phone ?? ''},
                          subjectId: entryId,
                        ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 20),
                      label: const Text('Copy text'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: asText(r)));
                        showMessage(context, 'Receipt copied.');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.chat_outlined, size: 20),
                      label: const Text('Text only'),
                      onPressed: () => sendWhatsApp(context, phone, asText(r)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
