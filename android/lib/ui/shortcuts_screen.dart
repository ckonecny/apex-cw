// Settings → App shortcuts (issue #151): which launcher shortcuts the app
// publishes and in which order. Launchers show only the first four or five,
// so the user picks.
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/app_shortcuts.dart';
import 'widgets/app_ui.dart';

class ShortcutsScreen extends StatefulWidget {
  const ShortcutsScreen({super.key});

  @override
  State<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

class _ShortcutsScreenState extends State<ShortcutsScreen> {
  /// Most launchers (Launcher3, Pixel) cut the menu after this many.
  static const _shown = 4;

  late final List<String> _order = [...AppShortcuts.order.value];
  late final Set<String> _off = {...AppShortcuts.off.value};

  void _save() {
    setState(() {});
    AppShortcuts.setChoice(_order, _off);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final onIds = [for (final id in _order) if (!_off.contains(id)) id];
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('sc_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          buildDefaultDragHandles: false,
          header: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(Strings.t('sc_hint'),
                style: TextStyle(fontSize: 13, color: c.textMuted)),
          ),
          itemCount: _order.length,
          onReorderItem: (from, to) {
            _order.insert(to, _order.removeAt(from));
            _save();
          },
          itemBuilder: (context, i) {
            final id = _order[i];
            final s = AppShortcuts.byId(id)!;
            final on = !_off.contains(id);
            final hidden = on && onIds.indexOf(id) >= _shown;
            return Card(
              key: ValueKey(id),
              color: c.surface,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                child: Row(children: [
                  Icon(s.icon, color: on ? c.accent : c.textFaint),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.label(), style: TextStyle(fontSize: 14,
                            color: on ? c.textPrimary : c.textMuted)),
                        if (hidden)
                          Text(Strings.t('sc_hidden'), style: TextStyle(
                              fontSize: 11, color: c.warning)),
                      ],
                    ),
                  ),
                  Switch(
                    value: on,
                    onChanged: (v) {
                      v ? _off.remove(id) : _off.add(id);
                      _save();
                    },
                    activeThumbColor: c.accent,
                    inactiveTrackColor: c.border,
                    inactiveThumbColor: c.textMuted,
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle, color: c.textMuted),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
