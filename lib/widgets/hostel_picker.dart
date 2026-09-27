import 'package:flutter/material.dart';

import '../core/hostels.dart';
import '../core/theme.dart';

/// List of hostels. Shows the saved list at once, then the fresh one from the server.
class HostelList extends StatefulWidget {
  const HostelList({super.key, required this.onSelected, this.selected, this.directory});

  final ValueChanged<Hostel> onSelected;
  final Hostel? selected;
  final HostelDirectory? directory;

  @override
  State<HostelList> createState() => _HostelListState();
}

class _HostelListState extends State<HostelList> {
  late final HostelDirectory _dir = widget.directory ?? HostelDirectory();
  List<Hostel>? _hostels;
  bool _refreshing = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _dir.cached();
    if (mounted) setState(() => _hostels = cached);
    final fresh = await _dir.refresh();
    if (mounted) {
      setState(() {
        _hostels = fresh;
        _refreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _hostels;
    if (list == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: kPrimary.withValues(alpha: 0.12),
                  child: const Icon(Icons.apartment_rounded, color: kPrimary),
                ),
                title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: h.subtitle == null ? null : Text(h.subtitle!),
                trailing: h == widget.selected ? const Icon(Icons.check_circle, color: kOk) : const Icon(Icons.chevron_right),
                onTap: () => widget.onSelected(h),
              ),
            ),
          ),
        if (_refreshing)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
      ],
    );
  }
}

/// Bottom sheet version, used from the sign-in screen and the More tab.
Future<Hostel?> pickHostel(BuildContext context, {Hostel? selected}) {
  return showModalBottomSheet<Hostel>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choose hostel', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              HostelList(selected: selected, onSelected: (h) => Navigator.pop(c, h)),
            ],
          ),
        ),
      ),
    ),
  );
}
