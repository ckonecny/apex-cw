// Links to external CW learning resources. Plain links, opened in the
// browser: nothing of these sites is embedded or copied, and names appear
// as text only (no logos).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';

class _Link {
  final String title, descKey, url;
  const _Link(this.title, this.descKey, this.url);
}

const _links = [
  _Link('Heinz – just me', 'link_heinz_desc',
      'https://www.youtube.com/watch?v=WhjCvgC0iHg&list=PLZjVloEmSdLgGGT_exNDoXzmnV-q0zmET'),
  _Link('LCWO', 'link_lcwo_desc', 'https://lcwo.net/'),
  _Link('VBand', 'link_vband_desc', 'https://hamradio.solutions/vband/'),
  _Link('Morserino-32', 'link_morserino_desc', 'https://www.morserino.info/'),
];

class LinksScreen extends StatelessWidget {
  const LinksScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.t('link_open_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('links_title')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final l in _links) ...[
              Material(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () => _open(context, l.url),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.title, style: TextStyle(
                              fontFamily: 'CwMono', fontSize: 18, color: c.textPrimary)),
                          const SizedBox(height: 4),
                          Text(Strings.t(l.descKey), style: TextStyle(
                              fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
                        ],
                      )),
                      Icon(Icons.open_in_new, color: c.textFaint, size: 20),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(Strings.t('links_note'), style: TextStyle(
                  fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
            ),
          ],
        ),
      ),
    );
  }
}
