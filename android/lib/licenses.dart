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

const _soloud = '''SoLoud audio engine
Copyright (c) 2013-2018 Jari Komppa

zlib/libpng license. This software is provided 'as-is', without any express
or implied warranty. In no event will the authors be held liable for any
damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software in a
product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source distribution.

SoLoud's bundled decoders (dr_libs, stb_vorbis, ...) are public domain or
MIT-0.''';

void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    Future<LicenseEntry> file(List<String> packages, String asset,
            {String? preamble}) async =>
        LicenseEntryWithLineBreaks(packages, [
          ?preamble,
          await rootBundle.loadString(asset),
        ].join('\n\n'));

    yield await file(['APEX CW', 'Morserino-32'],
        'assets/licenses/GPL-3.0.txt',
        preamble: 'APEX CW: Copyright (C) 2026 Christian Konecny, '
            'OE1CKO.\nMorserino-32 firmware (algorithms, word lists, '
            'abbreviations, call sign prefixes, QSO texts): Copyright (C) '
            '2018-2025 Willi Kraml, OE1WKL.\nBoth under the GNU General '
            'Public License v3.0 or later. Source code: '
            'https://github.com/ckonecny/apex-cw');
    yield await file(['Zork I–III'], 'assets/zork/LICENSE',
        preamble: 'Zork I–III by Marc Blank, Dave Lebling, Bruce Daniels '
            'and Tim Anderson (Infocom). Zork is a trademark of its owners; '
            'this app is not affiliated with or endorsed by them.');
    // Bundled inside flutter_soloud; its package LICENSE only covers the
    // Dart wrapper. zlib asks for (doesn't require) an acknowledgement.
    yield const LicenseEntryWithLineBreaks(['SoLoud (audio engine)'], _soloud);
    yield await file(['Anonymous Pro (font)'],
        'assets/fonts/OFL-AnonymousPro.txt');
    yield await file(['DM Sans (font)'],
        'assets/fonts/OFL-DMSans.txt');
    yield await file(['FrequencyWords (word lists)'],
        'assets/words/CC-BY-SA-4.0.txt');
  });
}
