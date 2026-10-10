import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';

/// One-time tip for new users in Send (#58): keying feels much better with a
/// real Morse key on an adapter than on the touch paddles. Shown until it is
/// closed once; tapping it opens the matching section of the online manual.
class KeyAdapterHint extends StatefulWidget {
  const KeyAdapterHint({super.key});
  @override
  State<KeyAdapterHint> createState() => _KeyAdapterHintState();
}

class _KeyAdapterHintState extends State<KeyAdapterHint> {
  static const _prefKey = 'keyAdapterHintSeen';
  bool _show = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted && !(p.getBool(_prefKey) ?? false)) setState(() => _show = true);
    });
  }

  Future<void> _dismiss() async {
    setState(() => _show = false);
    (await SharedPreferences.getInstance()).setBool(_prefKey, true);
  }

  Future<void> _openManual() async {
    final de = Strings.lang.value == 0;
    final url = 'https://ckonecny.github.io/apex-cw/'
        '${de ? 'manual-de.html#echte-morsetaste-oder-handtaste' : 'manual-en.html#a-real-morse-key-or-straight-key'}';
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.t('link_open_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        Expanded(child: InkWell(
          onTap: _openManual,
          child: Row(children: [
            Icon(Icons.lightbulb_outline, size: 14, color: c.info),
            const SizedBox(width: 6),
            Expanded(child: Text(Strings.t('key_adapter_hint'),
                style: TextStyle(fontSize: 11, color: c.textMuted))),
          ]),
        )),
        InkWell(
          onTap: _dismiss,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.close, size: 14, color: c.textFaint),
          ),
        ),
      ]),
    );
  }
}
