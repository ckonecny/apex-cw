// Compact stand-in for the weak-character and mix-up cards of the start views
// (issue #109) when they would not fit: one row naming what is ticked, and a
// bottom sheet holding the full tappable chips. Shared by Listen and Send.
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';

/// One tappable row: "Practice focus: E 5 Q · 2 mix-ups ▸".
class BoostSummaryRow extends StatelessWidget {
  final List<String> chars; // ticked weak characters, as displayed
  final int pairs; // ticked mix-up pairs
  final VoidCallback onTap;
  const BoostSummaryRow({super.key, required this.chars, required this.pairs, required this.onTap});

  static const _maxChars = 8;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final parts = <String>[
      if (chars.isNotEmpty)
        chars.take(_maxChars).join(' ') + (chars.length > _maxChars ? ' …' : ''),
      // No-break space: a line break never separates the number from its word.
      if (pairs > 0)
        Strings.t(pairs == 1 ? 'boost_sum_pair_one' : 'boost_sum_pairs')
            .replaceFirst('{n}', '$pairs').replaceAll(' ', '\u00A0'),
    ];
    final text = parts.isEmpty ? Strings.t('boost_sum_none') : parts.join(' · ');
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${Strings.t('boost_sum_title')}: ',
                        style: TextStyle(fontSize: 13, color: c.textMuted)),
                    TextSpan(
                        text: text,
                        style: TextStyle(
                            fontFamily: 'CwMono',
                            fontSize: 13,
                            color: parts.isEmpty ? c.textMuted : c.warning)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: c.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Content of the sheet: the given cards, scrollable, with a "Done" button.
class BoostSheetBody extends StatelessWidget {
  final List<Widget> cards;
  final VoidCallback onDone;
  const BoostSheetBody({super.key, required this.cards, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final w in cards) ...[w, const SizedBox(height: 12)],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: onDone, child: Text(Strings.t('boost_sheet_done'))),
          ),
        ),
      ]),
    );
  }
}

/// Opens the sheet. [cards] is rebuilt on [refresh], which the chips call after
/// each toggle so the ticks update while the sheet stays open.
Future<void> showBoostSheet(BuildContext context,
    {required List<Widget> Function(VoidCallback refresh) cards}) {
  final c = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.background,
    clipBehavior: Clip.antiAlias,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => BoostSheetBody(
        cards: cards(() => setSheet(() {})),
        onDone: () => Navigator.pop(ctx),
      ),
    ),
  );
}
