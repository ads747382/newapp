import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _date = today();

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'Summary PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => downloadAndOpen(context, 'attendance/summary/pdf', 'attendance-$_date.pdf', query: {'from': _date, 'to': _date}),
          ),
        ],
      ),
      body: LoadView(
        load: () => s.api.get('attendance/today', query: {'date': _date}),
        builder: (context, d, reload) {
          final counts = (d['counts'] as Map?) ?? const {};
          final rows = (d['items'] as List?) ?? const [];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(fmtDate(_date)),
                subtitle: Text('In ${counts['in'] ?? 0} · Out ${counts['out'] ?? 0} · Late ${counts['late'] ?? 0} · Moves ${counts['moves'] ?? 0}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_calendar_outlined),
                  onPressed: () async {
                    final initial = DateTime.tryParse(_date) ?? DateTime.now();
                    final x = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: initial);
                    if (x != null) {
                      setState(() => _date = '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}');
                      await reload();
                    }
                  },
                ),
              ),
            ),
            if ('${d['gate_close'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Gate close: ${d['gate_close']}', textAlign: TextAlign.center)),
            for (final raw in rows)
              _AttendanceResident(row: Map<String, dynamic>.from(raw as Map), canManage: s.can('attendance.manage'), reload: reload),
          ]);
        },
      ),
    );
  }
}

class _AttendanceResident extends StatelessWidget {
  const _AttendanceResident({required this.row, required this.canManage, required this.reload});
  final Json row;
  final bool canManage;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final status = '${row['status'] ?? 'in'}';
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(status == 'out' ? Icons.logout : Icons.login)),
        title: Text('${row['name']}'),
        subtitle: Text('${row['code']} · ${row['room_number'] ?? '—'} / ${row['bed_label'] ?? '—'}${row['last_at'] == null ? '' : '\nLast: ${row['last_at']}'}'),
        isThreeLine: row['last_at'] != null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (toInt(row['late']) > 0) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.schedule, size: 18)),
          Text(status.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
          const Icon(Icons.chevron_right),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResidentAttendanceScreen(id: toInt(row['id']), name: '${row['name']}', canManage: canManage))).then((_) => reload()),
      ),
    );
  }
}

class ResidentAttendanceScreen extends StatefulWidget {
  const ResidentAttendanceScreen({super.key, required this.id, required this.name, required this.canManage});
  final int id;
  final String name;
  final bool canManage;
  @override
  State<ResidentAttendanceScreen> createState() => _ResidentAttendanceScreenState();
}

class _ResidentAttendanceScreenState extends State<ResidentAttendanceScreen> {
  final key = GlobalKey<LoadViewState>();

  Future<void> _mark(BuildContext context, String direction) async {
    final note = await askText(context, '${direction == 'in' ? 'Check in' : 'Check out'} ${widget.name}', label: 'Note (optional)', required: false, ok: 'Save');
    if (note == null) return;
    final r = await runTask(context, () => apiOf(context).post('residents/${widget.id}/attendance', {'direction': direction, 'note': note}));
    if (r != null) key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.name} · Attendance'), actions: [IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => downloadAndOpen(context, 'residents/${widget.id}/attendance/pdf', 'attendance-${widget.id}.pdf'))]),
    floatingActionButton: widget.canManage ? FloatingActionButton.extended(onPressed: () => _mark(context, 'out'), icon: const Icon(Icons.sync_alt), label: const Text('Mark movement')) : null,
    body: LoadView(
      key: key,
      load: () => apiOf(context).get('residents/${widget.id}/attendance'),
      builder: (context, d, reload) {
        final days = (d['days'] as List?) ?? const [];
        final status = '${d['status'] ?? 'in'}';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(child: ListTile(title: Text('Current: ${status.toUpperCase()}'), subtitle: Text(d['last_at'] == null ? 'No movement recorded' : 'Last: ${d['last_at']}'), trailing: widget.canManage ? FilledButton(onPressed: () => _mark(context, status == 'in' ? 'out' : 'in'), child: Text(status == 'in' ? 'Check out' : 'Check in')) : null)),
          if ('${d['biometric_id'] ?? ''}'.isNotEmpty) Card(child: ListTile(leading: const Icon(Icons.fingerprint), title: const Text('Biometric ID'), subtitle: Text('${d['biometric_id']}'))),
          for (final raw in days)
            Card(child: ExpansionTile(title: Text(fmtDate((raw as Map)['date'])), subtitle: Text('IN ${raw['ins']} · OUT ${raw['outs']}${toInt(raw['late']) > 0 ? ' · Late' : ''}'), children: [for (final m in (raw['moves'] as List? ?? const [])) ListTile(dense: true, leading: Icon('${m['direction']}' == 'in' ? Icons.login : Icons.logout), title: Text('${m['direction']}'.toUpperCase()), subtitle: Text('${m['at']}${'${m['note'] ?? ''}'.isEmpty ? '' : ' · ${m['note']}'}'), trailing: m['is_void'] == true ? const Text('VOID') : null)])),
        ]);
      },
    ),
  );
}
