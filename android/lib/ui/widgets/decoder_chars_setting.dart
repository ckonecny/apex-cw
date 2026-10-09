// "Decoder Chars" setting (issue #52), shared by the CW Decoder and the CW
// Keyer settings. Saves itself (global pref, not part of a training profile)
// and reports the new set; the screen pushes it into its decoder.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../keyer/decoder_chars.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'setting_rows.dart';

class DecoderCharsSetting extends StatefulWidget {
  final ValueChanged<DecoderChars>? onChanged;
  const DecoderCharsSetting({super.key, this.onChanged});

  @override
  State<DecoderCharsSetting> createState() => _DecoderCharsSettingState();
}

class _DecoderCharsSettingState extends State<DecoderCharsSetting> {
  DecoderChars _set = DecoderChars.standard;

  @override
  void initState() {
    super.initState();
    loadDecoderChars().then((v) {
      if (mounted) setState(() => _set = v);
    });
  }

  Future<void> _choose(int i) async {
    final v = DecoderChars.values[i];
    setState(() => _set = v);
    final p = await SharedPreferences.getInstance();
    await p.setInt(decoderCharsKey, i);
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentRow(
        label: Strings.t('dec_chars'),
        options: [
          Strings.t('dec_chars_standard'),
          'ITU',
          'Fr/Es/Pt',
          'Sv/Fi',
          'Da/No',
        ],
        selected: _set.index,
        onChanged: _choose,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(Strings.t('dec_chars_desc'),
            style: TextStyle(fontSize: 11, color: c.textFaint)),
      ),
    ]);
  }
}
