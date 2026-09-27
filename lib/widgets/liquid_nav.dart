import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class LiquidNavItem {
  const LiquidNavItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Floating "liquid glass" tab bar: frosted blur, a pill that slides under the
/// selected tab, and a small bounce on the icon when it is picked.
class LiquidNavBar extends StatelessWidget {
  const LiquidNavBar({super.key, required this.items, required this.index, required this.onTap});

  final List<LiquidNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final glass = dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.72);
    final border = dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.85);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: glass,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: border, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final slot = c.maxWidth / items.length;
                  return Stack(
                    children: [
                      // the sliding pill
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        left: slot * index + slot * 0.12,
                        top: 7,
                        width: slot * 0.76,
                        height: 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: dark ? 0.26 : 0.14),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => onTap(i),
                                child: _Tab(item: items[i], selected: i == index, accent: accent),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.accent});

  final LiquidNavItem item;
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : kMuted;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: selected ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: Icon(selected ? item.activeIcon : item.icon, size: 23, color: color),
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(fontFamily: kFont, fontSize: 11, height: 1.1, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
          child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
