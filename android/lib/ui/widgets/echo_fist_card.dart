import 'package:flutter/material.dart';
import '../../keyer/fist_analyzer.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'app_ui.dart';
import 'fist_panel.dart';

/// Geben result (#166): the timing index of the block. [full] shows the bars
/// right on the page (when there is room), else one row; tap opens the bars.
class EchoFistCard extends StatelessWidget {
  const EchoFistCard(
      {super.key, required this.report, required this.skipped, this.full = false});

  final FistReport report;

  /// Words left out of the index because of a missing or extra element.
  final int skipped;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final index = report.index!;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: full
            ? _Details(report: report, skipped: skipped)
            : InkWell(
                onTap: () => _open(context),
                child: Row(children: [
                  Expanded(
                    child: Text(Strings.t('echo_fist_title'),
                        style: TextStyle(
                            color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Text('$index / 100',
                      style: TextStyle(
                          color: index >= 80 ? c.accent : c.warning,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, color: c.textMuted),
                ]),
              ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _Details(report: report, skipped: skipped),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.report, required this.skipped});

  final FistReport report;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hints = FistHints.once(report);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${Strings.t('echo_fist_title')}  ${report.index} / 100',
            style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        FistBars(report: report),
        const SizedBox(height: 8),
        if (hints.isEmpty)
          Text(Strings.t('fist_h_ok'), style: TextStyle(color: c.accent, fontSize: 13))
        else
          for (final h in hints)
            Text(Strings.t(h.key), style: TextStyle(color: c.warning, fontSize: 13)),
        const SizedBox(height: 8),
        Text(Strings.t('fist_rhythm_note').replaceAll('{wpm}', report.wpm.round().toString()),
            style: TextStyle(color: c.textFaint, fontSize: 12)),
        if (skipped > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(Strings.t('echo_fist_skipped').replaceAll('{n}', '$skipped'),
                style: TextStyle(color: c.textFaint, fontSize: 12)),
          ),
      ],
    );
  }
}
