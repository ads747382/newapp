import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../screens/receipt_screen.dart';
import 'common.dart';

/// One ledger line. Taps open the receipt when there is one.
class LedgerTile extends StatelessWidget {
  const LedgerTile(this.e, {super.key, this.portal = false, this.phone, this.onLongPress, this.showResident = false});

  final Json e;
  final bool portal;
  final String? phone;
  final VoidCallback? onLongPress;
  final bool showResident;

  @override
  Widget build(BuildContext context) {
    final debit = toDouble(e['debit']);
    final credit = toDouble(e['credit']);
    final isVoid = e['is_void'] == true;
    final deposit = e['account'] == 'deposit';
    final amount = debit > 0 ? debit : credit;
    final color = isVoid ? kMuted : (deposit ? kInfo : (debit > 0 ? kBad : kOk));
    final sign = deposit ? '' : (debit > 0 ? '+' : '-');
    final subtitle = [
      if (showResident && e['resident_name'] != null) '${e['resident_name']}',
      fmtDate(e['date']),
      if (e['period_month'] != null) fmtMonth(e['period_month']),
      if (e['description'] != null) '${e['description']}',
      if (e['receipt_no'] != null) '${e['receipt_no']}',
      if (isVoid) 'VOID: ${e['void_reason'] ?? ''}',
    ].join(' · ');
    final hasReceipt = e['receipt_no'] != null && !isVoid;
    return ListTile(
      onTap: hasReceipt
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiptScreen(
                  route: portal ? 'portal/receipts/${e['id']}' : 'receipts/${e['id']}',
                  phone: phone,
                  entryId: toInt(e['id']),
                  residentId: e['resident_id'] != null ? toInt(e['resident_id']) : null,
                ),
              ),
            )
          : null,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(deposit ? Icons.savings_outlined : (debit > 0 ? Icons.north_east : Icons.south_west), color: color, size: 20),
      ),
      title: Text('${e['type_label']}', style: TextStyle(decoration: isVoid ? TextDecoration.lineThrough : null)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$sign${money(amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          if (hasReceipt) const Icon(Icons.receipt_outlined, size: 16, color: kMuted),
        ],
      ),
    );
  }
}

/// Infinite list for paged API responses ({items, page, pages}).
class PagedList extends StatefulWidget {
  const PagedList({super.key, required this.load, required this.itemBuilder, this.header, this.empty = 'Nothing here yet.'});

  final Future<Json> Function(int page) load;
  final Widget Function(Json item) itemBuilder;
  final Widget Function(Json first)? header;
  final String empty;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final _items = <Json>[];
  Json? _first;
  int _page = 0;
  int _pages = 1;
  bool _loading = false;
  ApiException? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _more();
    });
    refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    _page = 0;
    _pages = 1;
    _items.clear();
    _first = null;
    await _more(reset: true);
  }

  Future<void> _more({bool reset = false}) async {
    if (_loading || (!reset && _page >= _pages)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load(_page + 1);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _first ??= d;
        _page = toInt(d['page']);
        _pages = toInt(d['pages']);
        _items.addAll((d['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_first == null && _error != null) return ErrorView(message: _error!.message, onRetry: refresh);
    if (_first == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: listBottomPadding(context)),
        itemCount: _items.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [if (widget.header != null) widget.header!(_first!), if (_items.isEmpty) EmptyView(widget.empty)]),
            );
          }
          if (i == _items.length + 1) {
            if (_error != null) return ErrorView(message: _error!.message, onRetry: _more);
            return _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return widget.itemBuilder(_items[i - 1]);
        },
      ),
    );
  }
}
