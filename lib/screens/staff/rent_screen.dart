import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';

/// Post one month's rent for everyone in a bed. Running it twice is safe.
class RentScreen extends StatefulWidget {
  const RentScreen({super.key});

  @override
  State<RentScreen> createState() => _RentScreenState();
}

class _RentScreenState extends State<RentScreen> {
  String _period = isoMonth(DateTime.now());
  String _date = firstOfMonth();

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Post monthly rent')),
      body: LoadView(
        key: ValueKey(_period),
        load: () => api.get('rent/preview', query: {'period': _period}),
        builder: (context, d, reload) {
          final rows = (d['rows'] as List).cast<Map>();
          final pending = toInt(d['pending_count']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Adds one rent charge per resident currently in a bed. Residents already charged for the month are skipped.'),
              const SizedBox(height: 16),
              MonthInput(
                label: 'Month',
                value: _period,
                onChanged: (v) => setState(() {
                  _period = v;
                  _date = '$v-01';
                }),
              ),
              DateInput(label: 'Posting date', value: _date, required: true, onChanged: (v) => setState(() => _date = v ?? _date)),
              StatGrid([
                StatTile(label: 'To post', value: '$pending residents', color: pending > 0 ? kWarn : kOk),
                StatTile(label: 'Total', value: money(d['pending_total'])),
              ]),
              FilledButton.icon(
                icon: const Icon(Icons.playlist_add_check),
                label: Text(pending > 0 ? 'Post rent for ${fmtMonth(_period)}' : 'Nothing to post'),
                onPressed: pending == 0
                    ? null
                    : () async {
                        if (!await confirm(
                          context,
                          'Post rent?',
                          'Adds ${money(d['pending_total'])} of rent for $pending residents for ${fmtMonth(_period)}.',
                          ok: 'Post',
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        final res = await runTask(context, () => api.post('rent/generate', {'period': _period, 'entry_date': _date}));
                        if (res != null && context.mounted) {
                          showMessage(context, '${res['message']}');
                          reload();
                        }
                      },
              ),
              const SizedBox(height: 16),
              Card(
                child: rows.isEmpty
                    ? const EmptyView('No residents are assigned to beds.')
                    : Column(
                        children: [
                          for (final r in rows)
                            ListTile(
                              title: Text('${r['name']}'),
                              subtitle: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('${r['code']} · Room ${r['room']}'),
                                  StatusChip(
                                    r['posted'] == true ? 'Posted' : (toDouble(r['rent']) > 0 ? 'Pending' : 'No rent'),
                                    tone: r['posted'] == true ? 'active' : 'pending',
                                  ),
                                ],
                              ),
                              trailing: Text(money(r['rent']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
