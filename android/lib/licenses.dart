// Licence texts shown on Flutter's licence page (Settings → Info →
// Licences), next to the ones Flutter collects from the packages itself.
// The app is GPL-3.0 because it ports code and data tables from the
// Morserino-32 firmware (DECISIONS.md "Licence: GPL-3.0").
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const appLegalese = 'Copyright (C) 2026 Christian Konecny, OE1CKO\n'
    'GNU General Public License v3.0 or later\n\n'
    'Based on the Morserino-32 firmware, '
    'Copyright (C) 2018-2025 Willi Kraml, OE1WKL (GPL-3.0).\n'
    'Zork is a trademark of its owners; this app is not affiliated with '
    'or endorsed by them, nor by Infocom, Activision or Microsoft.';

void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    Future<LicenseEntry> file(List<String> packages, String asset,
            {String? preamble}) async =>
        LicenseEntryWithLineBreaks(packages, [
          ?preamble,
          await rootBundle.loadString(asset),
        ].join('\n\n'));

    yield await file(['Next CW Trainer', 'Morserino-32'],
        'assets/licenses/GPL-3.0.txt',
        preamble: 'Next CW Trainer: Copyright (C) 2026 Christian Konecny, '
            'OE1CKO.\nMorserino-32 firmware (algorithms, word lists, '
            'abbreviations, call sign prefixes, QSO texts): Copyright (C) '
            '2018-2025 Willi Kraml, OE1WKL.\nBoth under the GNU General '
            'Public License v3.0 or later. Source code: '
            'https://github.com/ckonecny/next_cw_trainer');
    yield await file(['Zork I–III'], 'assets/zork/LICENSE',
        preamble: 'Zork I–III by Marc Blank, Dave Lebling, Bruce Daniels '
            'and Tim Anderson (Infocom). Zork is a trademark of its owners; '
            'this app is not affiliated with or endorsed by them.');
    yield await file(['Anonymous Pro (font)'],
        'assets/fonts/OFL-AnonymousPro.txt');
    yield await file(['Space Grotesk (font)'],
        'assets/fonts/OFL-SpaceGrotesk.txt');
  });
}
