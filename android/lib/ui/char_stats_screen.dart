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
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/char_stats.dart';
import '../content/cw_content.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart';
import 'widgets/char_stat_sheet.dart';
import '../util/char_color.dart';

class CharStatsScreen extends StatefulWidget {
  // `track`: CharStatsStore.hear or .echo — each training shows its own.
  final String track;
  const CharStatsScreen({super.key, required this.track});

  @override
  State<CharStatsScreen> createState() => _CharStatsScreenState();
}

class _CharStatsScreenState extends State<CharStatsScreen> {
  bool _loading = true;
  List<String> _active = [];
  late final CharStatsStore _store = CharStatsStore(widget.track);
  bool get _isHear => widget.track == CharStatsStore.hear;
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
    final kochLevel = (await TrainingProfile.open(widget.track)).getInt('kochLevel') ?? 5;
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

  // Plays the character like a tap in the Koch overview. Rule 2: the shared
  // native generator/tone keep whatever the last screen set, so wpm, spacing
  // and the sidetone are pushed here from this track's own settings.
  Future<void> _listen(String ch) async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(widget.track);
    final wpm = TrainingProfile.clampWpm(pf.getInt('wpm'));
    final iws = (pf.getInt('interWordSpace') ?? 40).clamp(6, 105);
    const tone = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
    await tone.invokeMethod('setFreq', p.getInt('pitch') ?? 600);
    await tone.invokeMethod('setEnvelopeMs',
        ((p.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
    if (!mounted) return;
    await showCharPlayback(context,
        ch: ch, outputCase: _outputCase,
        play: () => playCharThrice(ch, wpm: wpm, interWordSpace: iws));
  }

  Future<void> _openDetail(String ch, CharStat stat, bool ready) =>
      showCharStatSheet(context,
          ch: ch, stat: stat, isHear: _isHear, ready: ready,
          unlockOccurrences: _unlockOccurrences, highThreshold: _highThreshold,
          outputCase: _outputCase, pairs: _store.pairs,
          onListen: () => _listen(ch));

  // Irreversible, so a short confirmation guards against a stray tap.
  Future<void> _confirmReset() async {
    final c = AppColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('settings_reset_char_stats_confirm_title')),
        content: Text(Strings.t(_isHear
            ? 'settings_reset_char_stats_confirm_body_hear'
            : 'settings_reset_char_stats_confirm_body_echo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(Strings.t('cancel'))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(Strings.t('settings_reset_char_stats'),
                  style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    final p = await SharedPreferences.getInstance();
    await _store.reset(p);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.t('settings_reset_char_stats_done'))));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, Strings.t(_isHear ? 'char_stats_title_hear' : 'char_stats_title_echo')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: c.danger),
            tooltip: Strings.t('settings_reset_char_stats'),
            onPressed: _confirmReset,
          ),
        ],
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
      // Sending: weakest characters first (they also come up more often).
      if (!_isHear) return b.stat.emaErrorRate.compareTo(a.stat.emaErrorRate);
      if (a.ready != b.ready) return a.ready ? 1 : -1;
      return a.stat.attempts.compareTo(b.stat.attempts);
    });
    final readyCount = rows.where((r) => r.ready).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(Strings.t(_isHear ? 'char_stats_desc' : 'char_stats_desc_echo'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textFaint)),
        const SizedBox(height: 8),
        Text(
            Strings.t('char_stats_rule')
                .replaceFirst('{n}', '$_unlockOccurrences')
                .replaceFirst('{x}', '${(_highThreshold * 100).round()}'),
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
            onTap: () => _openDetail(r.ch, r.stat, r.ready),
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
  final VoidCallback onTap;
  const _CharStatRow({
    required this.ch,
    required this.stat,
    required this.unlockOccurrences,
    required this.highThreshold,
    required this.ready,
    required this.outputCase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hitRate = 1 - stat.emaErrorRate;
    final attemptsFrac = (stat.attempts / unlockOccurrences).clamp(0.0, 1.0);
    final display = outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();
    final chColor = charTypeColor(ch, c);
    // Why a hear row still shows the hourglass: spelled out instead of
    // leaving it to the icon.
    final reasons = <String>[
      Strings.t('char_stats_attempts').replaceFirst('{n}', '${stat.attempts}'),
      if (!ready && stat.attempts < unlockOccurrences)
        Strings.t('char_stats_need_more')
            .replaceFirst('{k}', '${unlockOccurrences - stat.attempts}'),
      if (!ready && hitRate < highThreshold)
        Strings.t('char_stats_below')
            .replaceFirst('{x}', '${(highThreshold * 100).round()}'),
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            Text(reasons.join(' · '),
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
          Text(Strings.t('char_stats_current'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 10, color: c.textFaint)),
        ]),
        const SizedBox(width: 8),
        Icon(ready ? Icons.check_circle : Icons.hourglass_bottom,
            size: 18, color: ready ? c.accent : c.textFaint),
      ]),
    ));
  }
}
