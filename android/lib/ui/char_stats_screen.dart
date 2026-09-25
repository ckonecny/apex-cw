// Per-character view of Adaptive Copy's unlock progress — every active Koch
// character must individually clear the occurrences floor and error-rate
// threshold before the next character unlocks (see
// AdaptiveCopyEngine.shouldUnlockNextChar, adaptive_copy_engine.dart). At
// higher Koch levels a uniform draw over many active characters spreads
// occurrences thin, so it's easy to assume "it's stuck" when really one
// early character just hasn't come up enough times yet — this screen makes
// that visible instead of requiring a manual SharedPreferences pull (see
// docs/ADAPTIVE-COPY.md, "Also investigated this session, not a bug",
// 2026-09-23).
import '../content/training_profile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/char_stats.dart';
import '../content/cw_content.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/char_color.dart';

class CharStatsScreen extends StatefulWidget {
  const CharStatsScreen({super.key});

  @override
  State<CharStatsScreen> createState() => _CharStatsScreenState();
}

class _CharStatsScreenState extends State<CharStatsScreen> {
  bool _loading = true;
  List<String> _active = [];
  final CharStatsStore _store = CharStatsStore();
  int _unlockOccurrences = 20;
  double _highThreshold = 0.90;
  int _outputCase = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await _store.load(p);
    final kochLevel = (await TrainingProfile.open(TrainingProfile.hear)).getInt('kochLevel') ?? 5;
    final kochSeq = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
    final customKochChars = (p.getString('customKochChars') ?? '').isNotEmpty
        ? p.getString('customKochChars')!
        : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
    final licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
    final sequence = kochSequenceChars(kochSeq, customKochChars, licwCarouselStart: licwCarouselStart);
    final active = kochActiveChars(kochLevel, sequence);
    if (!mounted) return;
    setState(() {
      _active = active;
      _unlockOccurrences = p.getInt('adaptiveUnlockOccurrences') ?? 20;
      _highThreshold = ((p.getInt('adaptiveHighThresholdPct') ?? 90).clamp(50, 99)) / 100;
      _outputCase = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(Strings.t('char_stats_title'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : _buildBody(c),
    );
  }

  Widget _buildBody(AppColors c) {
    if (_active.isEmpty) {
      return Center(
        child: Text(Strings.t('char_stats_empty'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textMuted)),
      );
    }
    final rows = _active.map((ch) {
      final s = _store.stats[ch] ?? CharStat();
      final attemptsOk = s.attempts >= _unlockOccurrences;
      final emaOk = (1 - s.emaErrorRate) >= _highThreshold;
      return (ch: ch, stat: s, ready: attemptsOk && emaOk);
    }).toList();
    // Not-ready characters first (least attempts first within that group) —
    // whatever's actually blocking the unlock surfaces at the top instead of
    // being buried among characters that are already long since mastered.
    rows.sort((a, b) {
      if (a.ready != b.ready) return a.ready ? 1 : -1;
      return a.stat.attempts.compareTo(b.stat.attempts);
    });
    final readyCount = rows.where((r) => r.ready).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(Strings.t('char_stats_desc'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textFaint)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.borderAlt),
          ),
          child: Text(
              Strings.t('char_stats_ready_summary')
                  .replaceFirst('{ready}', '$readyCount')
                  .replaceFirst('{total}', '${rows.length}'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
        ),
        const SizedBox(height: 16),
        for (final r in rows)
          _CharStatRow(
            ch: r.ch,
            stat: r.stat,
            unlockOccurrences: _unlockOccurrences,
            highThreshold: _highThreshold,
            ready: r.ready,
            outputCase: _outputCase,
          ),
      ],
    );
  }
}

class _CharStatRow extends StatelessWidget {
  final String ch;
  final CharStat stat;
  final int unlockOccurrences;
  final double highThreshold;
  final bool ready;
  final int outputCase;
  const _CharStatRow({
    required this.ch,
    required this.stat,
    required this.unlockOccurrences,
    required this.highThreshold,
    required this.ready,
    required this.outputCase,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hitRate = 1 - stat.emaErrorRate;
    final attemptsFrac = (stat.attempts / unlockOccurrences).clamp(0.0, 1.0);
    final display = outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();
    final chColor = charTypeColor(ch, c);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ready ? c.accent.withOpacity(0.4) : c.borderAlt),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: chColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(display,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                  fontWeight: FontWeight.bold, color: chColor)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                Strings.t('char_stats_attempts')
                    .replaceFirst('{n}', '${stat.attempts}')
                    .replaceFirst('{floor}', '$unlockOccurrences'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: attemptsFrac,
                minHeight: 5,
                backgroundColor: c.border,
                color: attemptsFrac >= 1 ? c.accent : c.info,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(hitRate * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 13, fontWeight: FontWeight.bold,
                  color: hitRate >= highThreshold ? c.accent : c.textMuted)),
          const SizedBox(height: 4),
          Icon(ready ? Icons.check_circle : Icons.hourglass_bottom,
              size: 16, color: ready ? c.accent : c.textFaint),
        ]),
      ]),
    );
  }
}
