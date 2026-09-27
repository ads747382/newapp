import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fields.dart';
import 'resident_detail_screen.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  String _availability = '';
  String _type = '';
  final _key = GlobalKey<LoadViewState>();

  void _filter(VoidCallback change) {
    setState(change);
    WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms & beds')),
      floatingActionButton: s.can('rooms.manage')
          ? FloatingActionButton.extended(
              heroTag: 'rooms',
              icon: const Icon(Icons.add),
              label: const Text('Room'),
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RoomFormScreen()));
                if (ok == true) _key.currentState?.reload();
              },
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final e in const {'': 'All', 'available': 'Has space', 'empty': 'Empty', 'full': 'Full'}.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(e.value), selected: _availability == e.key, onSelected: (_) => _filter(() => _availability = e.key)),
                  ),
                for (final t in s.options('room_types'))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('${t['label']}'),
                      selected: _type == t['value'],
                      onSelected: (on) => _filter(() => _type = on ? '${t['value']}' : ''),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LoadView(
              key: _key,
              load: () => s.api.get('rooms', query: {'availability': _availability, 'type': _type}),
              builder: (context, d, reload) {
                final totals = d['totals'] as Map;
                final rooms = (d['rooms'] as List).cast<Map>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid([
                      StatTile(
                        label: 'Occupied',
                        value: '${totals['occupied']} / ${totals['beds']}',
                        sub: '${totals['rate']}% · ${totals['rooms']} active rooms',
                      ),
                      StatTile(label: 'Vacant beds', value: '${totals['vacant']}', color: kOk),
                    ]),
                    if (rooms.isEmpty) const EmptyView('No rooms match.'),
                    for (final r in rooms) _RoomCard(room: Map<String, dynamic>.from(r), onChanged: reload),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onChanged});

  final Json room;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final beds = toInt(room['bed_count']);
    final occ = toInt(room['occupied']);
    final full = beds > 0 && occ >= beds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => RoomDetailScreen(id: toInt(room['id']))));
            onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Room ${room['room_number']}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          StatusChip('${room['room_type']}', tone: '${room['room_type']}'),
                          if (room['status'] != 'active') StatusChip(context.read<Session>().label('room_statuses', room['status']), tone: '${room['status']}'),
                        ],
                      ),
                    ),
                    if (room['monthly_rent'] != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text(money(room['monthly_rent']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                if (room['floor'] != null) Text('Floor ${room['floor']}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: beds == 0 ? 0 : occ / beds,
                          minHeight: 8,
                          color: full ? kBad : kPrimary,
                          backgroundColor: kMuted.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$occ / $beds beds',
                      style: TextStyle(color: full ? kBad : null, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoomDetailScreen extends StatelessWidget {
  const RoomDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final key = GlobalKey<LoadViewState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room'),
        actions: [
          if (context.read<Session>().canPurge)
            IconButton(
              tooltip: 'Delete room permanently',
              icon: const Icon(Icons.delete_forever_outlined, color: kBad),
              onPressed: () async {
                final reason = await askText(context, 'Delete this room permanently?', label: 'Reason', ok: 'Delete', danger: true);
                if (reason == null || !context.mounted) return;
                final res = await runTask(context, () => api.post('rooms/$id/delete', {'reason': reason}), success: 'Room deleted with its beds and history.');
                if (res != null && context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: LoadView(
        key: key,
        load: () => api.get('rooms/$id'),
        builder: (context, d, reload) {
          final room = Map<String, dynamic>.from(d['room'] as Map);
          final beds = (d['beds'] as List).cast<Map>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Room ${room['room_number']}',
                trailing: d['can_manage'] == true
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RoomFormScreen(room: room)));
                          if (ok == true) reload();
                        },
                      )
                    : null,
                child: InfoRows([
                  ('Type', '${room['room_type']}'),
                  ('Floor', orDash(room['floor'])),
                  ('Capacity', '${room['capacity']} beds'),
                  ('Status', context.read<Session>().label('room_statuses', room['status'])),
                  if (room['monthly_rent'] != null) ('Rent per bed', money(room['monthly_rent'])),
                  if (room['notes'] != null) ('Notes', '${room['notes']}'),
                ]),
              ),
              SectionCard(
                title: 'Beds',
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    for (final b in beds)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (b['resident_id'] == null ? kOk : kPrimary).withValues(alpha: 0.12),
                          child: Text(
                            '${b['label']}',
                            style: TextStyle(color: b['resident_id'] == null ? kOk : kPrimary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(b['resident_id'] == null ? 'Vacant' : '${b['resident_name']}'),
                        subtitle: b['resident_id'] == null ? null : Text('${b['resident_code']} · since ${fmtDate(b['since'])}'),
                        trailing: b['resident_id'] == null ? null : const Icon(Icons.chevron_right),
                        onTap: b['resident_id'] == null
                            ? null
                            : () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => ResidentDetailScreen(id: toInt(b['resident_id']))));
                                reload();
                              },
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

class RoomFormScreen extends StatefulWidget {
  const RoomFormScreen({super.key, this.room});

  final Json? room;

  @override
  State<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends State<RoomFormScreen> {
  late final _number = TextEditingController(text: '${widget.room?['room_number'] ?? ''}');
  late final _floor = TextEditingController(text: '${widget.room?['floor'] ?? ''}');
  late final _capacity = TextEditingController(text: '${widget.room?['capacity'] ?? 2}');
  late final _rent = TextEditingController(
    text: widget.room?['monthly_rent'] == null ? '' : money(widget.room!['monthly_rent'], symbol: false).replaceAll(',', ''),
  );
  late final _notes = TextEditingController(text: '${widget.room?['notes'] ?? ''}');
  late String _type = '${widget.room?['room_type'] ?? 'Normal'}';
  late String _status = '${widget.room?['status'] ?? 'active'}';
  Map<String, String> _errors = {};

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final editing = widget.room != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit room ${widget.room!['room_number']}' : 'Add room')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(controller: _number, label: 'Room number', required: true, maxLength: 20, error: _errors['room_number']),
          AppTextField(controller: _floor, label: 'Floor', maxLength: 20, error: _errors['floor']),
          ChoiceInput(
            label: 'Room type',
            value: _type,
            required: true,
            choices: [for (final o in s.options('room_types')) Choice('${o['value']}', '${o['label']}')],
            onChanged: (v) => setState(() => _type = v ?? _type),
            error: _errors['room_type'],
          ),
          AppTextField(
            controller: _capacity,
            label: 'Beds (capacity)',
            required: true,
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 2,
            helper: 'Beds are labelled A, B, C… Occupied beds can’t be removed.',
            error: _errors['capacity'],
          ),
          AmountInput(controller: _rent, label: 'Monthly rent per bed', required: true, error: _errors['monthly_rent']),
          ChoiceInput(
            label: 'Status',
            value: _status,
            required: true,
            choices: [for (final o in s.options('room_statuses')) Choice('${o['value']}', '${o['label']}')],
            onChanged: (v) => setState(() => _status = v ?? _status),
            error: _errors['status'],
          ),
          AppTextField(controller: _notes, label: 'Notes', maxLines: 3, maxLength: 2000, error: _errors['notes']),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              try {
                final res = await s.api.post(editing ? 'rooms/${widget.room!['id']}' : 'rooms', {
                  'room_number': _number.text.trim(),
                  'floor': _floor.text.trim(),
                  'room_type': _type,
                  'capacity': _capacity.text.trim(),
                  'monthly_rent': _rent.text.trim(),
                  'status': _status,
                  'notes': _notes.text.trim(),
                });
                if (context.mounted) showMessage(context, '${res['message']}');
                nav.pop(true);
              } on ApiException catch (e) {
                setState(() => _errors = e.errors);
                if (e.errors.isEmpty && context.mounted) showMessage(context, e.message, error: true);
              }
            },
            child: const Text('Save room'),
          ),
        ],
      ),
    );
  }
}
