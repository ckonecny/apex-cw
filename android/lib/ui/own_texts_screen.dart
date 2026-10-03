// Own texts (issue #8): the library. Paste a text from the clipboard (or share
// one in from another app, #24), open, rename or delete one. The player is own_text_player_screen.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../owntexts/own_text_store.dart';
import '../owntexts/text_passage.dart';
import '../theme/app_colors.dart';
import 'own_text_player_screen.dart';
import 'widgets/app_ui.dart';

class OwnTextsScreen extends StatefulWidget {
  const OwnTextsScreen({super.key, this.sharedText});

  /// Text shared in from another app: offered for import on open.
  final String? sharedText;

  @override
  State<OwnTextsScreen> createState() => _OwnTextsScreenState();
}

class _OwnTextsScreenState extends State<OwnTextsScreen> {
  final _store = OwnTextStore();
  List<OwnTextInfo>? _texts;

  @override
  void initState() {
    super.initState();
    _reload();
    final shared = widget.sharedText;
    if (shared != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _import(shared, Strings.t('ot_clip_empty_share')));
    }
  }

  Future<void> _reload() async {
    final l = await _store.list();
    if (mounted) setState(() => _texts = l);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await _import(data?.text, Strings.t('ot_clip_empty'));
  }

  /// Checks [raw] (pasted or shared), asks for a title and adds it.
  Future<void> _import(String? raw, String emptyMsg) async {
    final text = raw?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      _snack(emptyMsg);
      return;
    }
    if (text.length > maxTextChars) {
      _snack(Strings.t('ot_too_long')
          .replaceAll('{n}', '${text.length}')
          .replaceAll('{max}', '$maxTextChars'));
      return;
    }
    final passage = TextPassage.parse(text);
    if (!passage.hasAudio) {
      _snack(Strings.t('ot_no_morse'));
      return;
    }
    final title = await _askTitle(
      Strings.t('ot_add_title'),
      _defaultTitle(text),
      info: Strings.t('ot_add_info').replaceAll('{n}', '${passage.words.length}'),
      ok: Strings.t('ot_add'),
    );
    if (title == null) return;
    await _store.add(title, text, passage.words.length);
    await _reload();
  }

  static String _defaultTitle(String text) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ');
    return one.length <= 32 ? one : '${one.substring(0, 32).trimRight()}…';
  }

  Future<String?> _askTitle(String heading, String initial,
      {String? info, required String ok}) {
    final ctrl = TextEditingController(text: initial);
    final c = AppColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(heading, style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (info != null) ...[
            Text(info, style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(labelText: Strings.t('ot_title_label')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.t('cancel'))),
          TextButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: Text(ok),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(OwnTextInfo i) async {
    final t = await _askTitle(Strings.t('ot_rename'), i.title, ok: Strings.t('ot_save'));
    if (t == null) return;
    await _store.rename(i.id, t);
    await _reload();
  }

  Future<void> _delete(OwnTextInfo i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('ot_delete_q')),
        content: Text(i.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Strings.t('ot_delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(i.id);
    await _reload();
  }

  Future<void> _open(OwnTextInfo i) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => OwnTextPlayerScreen(info: i, store: _store)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final texts = _texts;
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('ot_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AppButton(
              label: Strings.t('ot_paste'),
              icon: Icons.content_paste,
              color: c.accent,
              onTap: _paste,
            ),
            const SizedBox(height: 12),
            if (texts == null)
              const SizedBox.shrink()
            else if (texts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(Strings.t('ot_empty'),
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
              )
            else
              for (final i in texts) ...[
                _card(c, i),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _card(AppColors c, OwnTextInfo i) {
    final progress = i.pos > 0
        ? ' · ${Strings.t('ot_progress').replaceAll('{p}', '${i.percent}')}'
        : '';
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 15, color: c.textPrimary)),
              const SizedBox(height: 3),
              Text('${Strings.t('ot_words').replaceAll('{n}', '${i.words}')}$progress',
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
            ])),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: c.textMuted),
              onSelected: (v) => v == 'rename' ? _rename(i) : _delete(i),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(Strings.t('ot_rename'))),
                PopupMenuItem(value: 'delete', child: Text(Strings.t('ot_delete'))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
