import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../widgets/fields.dart';
import '../../widgets/lists.dart';
import 'dashboard_screen.dart';
import 'resident_form_screen.dart';

class ResidentsScreen extends StatefulWidget {
  const ResidentsScreen({super.key, this.initialView = 'current', this.initialSource});

  final String initialView;
  final String? initialSource;

  @override
  State<ResidentsScreen> createState() => _ResidentsScreenState();
}

class _ResidentsScreenState extends State<ResidentsScreen> {
  late String _view = widget.initialView;
  String _q = '';
  late Map<String, String?> _filters = {'sort': 'name', if (widget.initialSource != null) 'source': widget.initialSource};
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;

  static const _views = {'current': 'Current', 'admissions': 'Admissions', 'archived': 'Archived', 'all': 'All'};

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _generation++);

  int get _filterCount => _filters.entries.where((e) => e.key != 'sort' && e.value != null).length;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Residents'),
        actions: [
          IconButton(
            icon: Badge(isLabelVisible: _filterCount > 0, label: Text('$_filterCount'), child: const Icon(Icons.tune)),
            onPressed: _openFilters,
          ),
        ],
      ),
      floatingActionButton: s.can('residents.create')
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Admission'),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ResidentFormScreen()));
                _reload();
              },
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SearchBar(
              controller: _search,
              hintText: 'Name, phone, CNIC, room or code',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              trailing: [
                if (_q.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _q = '');
                    },
                  ),
              ],
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _q = v.trim()));
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final e in _views.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(e.value), selected: _view == e.key, onSelected: (_) => setState(() => _view = e.key)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedList(
              key: ValueKey('$_view|$_q|$_filters|$_generation'),
              load: (page) => s.api.get('residents', query: {'view': _view, 'q': _q, 'page': page, ..._filters}),
              header: (d) => Align(
                alignment: Alignment.centerLeft,
                child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${d['total']} found')),
              ),
              itemBuilder: (r) => ResidentTile(r, onChanged: _reload),
              empty: 'No residents match.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    final s = context.read<Session>();
    final f = Map<String, String?>.from(_filters);
    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          List<Choice> opts(String name) => [for (final o in s.options(name)) Choice('${o['value']}', '${o['label']}')];
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filter residents', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 16),
                ChoiceInput(
                  label: 'Admission status',
                  value: f['admission'],
                  allowEmpty: true,
                  choices: opts('admission_statuses'),
                  onChanged: (v) => set(() => f['admission'] = v),
                ),
                ChoiceInput(
                  label: 'Verification',
                  value: f['verification'],
                  allowEmpty: true,
                  choices: opts('verification_statuses'),
                  onChanged: (v) => set(() => f['verification'] = v),
                ),
                ChoiceInput(
                  label: 'Applied',
                  value: f['source'],
                  allowEmpty: true,
                  choices: const [Choice('online', 'Online form'), Choice('office', 'At the office')],
                  onChanged: (v) => set(() => f['source'] = v),
                ),
                ChoiceInput(
                  label: 'Bed',
                  value: f['bed'],
                  allowEmpty: true,
                  choices: const [Choice('assigned', 'Has a bed'), Choice('unassigned', 'No bed')],
                  onChanged: (v) => set(() => f['bed'] = v),
                ),
                if (s.can('accounts.view'))
                  ChoiceInput(
                    label: 'Payment',
                    value: f['payment'],
                    allowEmpty: true,
                    choices: const [Choice('outstanding', 'Owes money'), Choice('advance', 'Has advance'), Choice('clear', 'Clear')],
                    onChanged: (v) => set(() => f['payment'] = v),
                  ),
                ChoiceInput(
                  label: 'Sort by',
                  value: f['sort'] ?? 'name',
                  choices: [
                    const Choice('name', 'Name'),
                    const Choice('newest', 'Newest first'),
                    const Choice('room', 'Room'),
                    if (s.can('accounts.view')) const Choice('balance', 'Highest balance'),
                  ],
                  onChanged: (v) => set(() => f['sort'] = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: () => Navigator.pop(c, <String, String?>{'sort': 'name'}), child: const Text('Clear')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(onPressed: () => Navigator.pop(c, f), child: const Text('Apply')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result != null) setState(() => _filters = result..removeWhere((k, v) => v == null));
  }
}
