// Text adventure: choose Zork I, II or III, continue, open a save or start
// over. The card and titles avoid the trademark (DECISIONS.md "Text
// adventure"): the works are named only here and in the credits.
import 'package:flutter/material.dart';

import '../adventure/adventure_store.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'adventure_screen.dart';
import 'adventure_sheets.dart';
import 'widgets/app_ui.dart';

class AdventureSelectScreen extends StatefulWidget {
  const AdventureSelectScreen({super.key});

  @override
  State<AdventureSelectScreen> createState() => _AdventureSelectScreenState();
}

class _AdventureSelectScreenState extends State<AdventureSelectScreen> {
  final Map<String, SaveInfo?> _auto = {};
  final Map<String, int> _slotCount = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    for (final g in adventureGames) {
      final st = AdventureStore(g.id);
      _auto[g.id] = await st.autoInfo();
      _slotCount[g.id] = (await st.slots()).length;
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _open(AdventureGame g, {bool newGame = false, String? loadId}) async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AdventureScreen(game: g, newGame: newGame, loadId: loadId)));
    _reload();
  }

  Future<void> _newGame(AdventureGame g) async {
    if (_auto[g.id] != null) {
      final ok = await confirmRestart(context);
      if (ok != true || !mounted) return;
    }
    _open(g, newGame: true);
  }

  Future<void> _saves(AdventureGame g) async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => AdventureSavesScreen(store: AdventureStore(g.id), pickOnly: true,
            title: Strings.t('adv_saves'))));
    if (id != null && mounted) _open(g, loadId: id);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('adv_title')),
          leading: IconButton(icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => Navigator.pop(context)),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(Strings.t('adv_hint'),
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
                  const SizedBox(height: 16),
                  AppCaption(Strings.t('adv_choose')),
                  const SizedBox(height: 8),
                  for (final g in adventureGames) _gameCard(c, g),
                  const SizedBox(height: 12),
                  Text(Strings.t('adv_credits'),
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
                ],
              ),
      ),
    );
  }

  Widget _gameCard(AppColors c, AdventureGame g) {
    final a = _auto[g.id];
    final slots = _slotCount[g.id] ?? 0;
    final meta = a == null
        ? Strings.t('adv_not_started')
        : Strings.t('adv_meta')
            .replaceAll('{s}', '${a.score}')
            .replaceAll('{m}', '${a.moves}')
            .replaceAll('{r}', a.room);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      borderColor: a != null ? c.accent.withOpacity(0.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(g.title, style: TextStyle(fontFamily: 'CwMono', fontSize: 15,
            fontWeight: FontWeight.bold, color: c.textPrimary)),
        const SizedBox(height: 4),
        Text(meta, style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 3, child: AppButton(
              label: Strings.t(a == null ? 'adv_start' : 'adv_continue'),
              color: c.accent, height: 44,
              onTap: () => a == null ? _open(g, newGame: true) : _open(g))),
          if (a != null || slots > 0) ...[
            const SizedBox(width: 8),
            Expanded(flex: 3, child: AppButton(label: Strings.t('adv_saves'), color: c.info,
                height: 44, onTap: () => _saves(g))),
          ],
          if (a != null) ...[
            const SizedBox(width: 8),
            Expanded(flex: 2, child: AppButton(label: Strings.t('adv_new'), color: c.textMuted,
                primary: false, height: 44, onTap: () => _newGame(g))),
          ],
        ]),
      ]),
    );
  }
}
