import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// Hostel rules grouped and numbered, as printed on the admission form.
/// Not scrollable itself: place it inside a page that scrolls.
class RulesList extends StatelessWidget {
  const RulesList({super.key, required this.rules});

  final Map<String, dynamic> rules;

  @override
  Widget build(BuildContext context) {
    var n = 0;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in rules.entries)
          SectionCard(
            title: entry.key,
            child: Column(
              children: [
                for (final rule in (entry.value as List))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text('${++n}.', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Expanded(child: Text('$rule', softWrap: true)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
