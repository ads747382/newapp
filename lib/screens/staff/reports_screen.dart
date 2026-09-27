import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import 'resident_detail_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  static const _icons = {
    'occupancy': Icons.bed_outlined,
    'residents': Icons.people_outline,
    'collection': Icons.payments_outlined,
    'outstanding': Icons.trending_up,
    'advances': Icons.savings_outlined,
    'payments': Icons.receipt_long_outlined,
    'profit_loss': Icons.insights_outlined,
    'expenses': Icons.pie_chart_outline,
  };

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: LoadView(
        load: () => api.get('reports'),
        builder: (context, d, _) => Card(
          child: Column(
            children: [
              for (final r in (d['reports'] as List).cast<Map>())
                ListTile(
                  leading: Icon(_icons[r['type']] ?? Icons.table_chart_outlined),
                  title: Text('${r['label']}'),
                  subtitle: Text(r['uses_range'] == true ? 'For a date range' : 'As of today'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportViewScreen(type: '${r['type']}', title: '${r['label']}', usesRange: r['uses_range'] == true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportViewScreen extends StatefulWidget {
  const ReportViewScreen({super.key, required this.type, required this.title, required this.usesRange});

  final String type;
  final String title;
  final bool usesRange;

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  String _from = '${DateTime.now().year}-01-01';
  String _to = lastOfMonth();

  String _cell(Session s, Object? v, String format) {
    if (v == null || '$v'.isEmpty) return '—';
    return switch (format) {
      'money' => money(v),
      'date' => fmtDate(v),
      'month' => fmtMonth(v),
      'percent' => '$v%',
      'int' => '${toInt(v)}',
      'badge' => s.label('admission_statuses', v) != '$v' ? s.label('admission_statuses', v) : '$v'.replaceAll('_', ' '),
      _ => '$v',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: LoadView(
        key: ValueKey('$_from|$_to'),
        load: () => s.api.get('reports/run', query: {'type': widget.type, if (widget.usesRange) 'from': _from, if (widget.usesRange) 'to': _to}),
        builder: (context, d, _) {
          final columns = (d['columns'] as List).cast<Map>();
          final rows = (d['rows'] as List).cast<Map>();
          final summary = Map<String, dynamic>.from((d['summary'] is Map ? d['summary'] : const {}) as Map);
          final totals = d['totals'] is Map ? Map<String, dynamic>.from(d['totals'] as Map) : <String, dynamic>{};
          final titleCol = columns.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.usesRange)
                Row(
                  children: [
                    Expanded(
                      child: DateInput(label: 'From', value: _from, required: true, onChanged: (v) => setState(() => _from = v ?? _from)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DateInput(label: 'To', value: _to, required: true, onChanged: (v) => setState(() => _to = v ?? _to)),
                    ),
                  ],
                ),
              if (summary.isNotEmpty) StatGrid([for (final e in summary.entries) StatTile(label: e.key, value: '${e.value}')]),
              if (rows.isEmpty) const EmptyView('Nothing to show for this report.'),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: InkWell(
                      onTap: row['_resident_id'] != null || (row['_id'] != null && const ['residents', 'outstanding', 'advances'].contains(widget.type))
                          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResidentDetailScreen(id: toInt(row['_resident_id'] ?? row['_id']))))
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_cell(s, row[titleCol['key']], '${titleCol['format']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            InfoRows([for (final c in columns.skip(1)) ('${c['label']}', _cell(s, row[c['key']], '${c['format']}'))]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (totals.isNotEmpty)
                SectionCard(
                  title: 'Totals',
                  child: InfoRows([
                    for (final c in columns)
                      if (totals.containsKey(c['key'])) ('${c['label']}', _cell(s, totals[c['key']], '${c['format']}')),
                  ]),
                ),
              Text(
                '${rows.length} rows',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}

typedef ReportRow = Json;
