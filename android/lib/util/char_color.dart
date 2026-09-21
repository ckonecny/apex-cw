// Distinguishes letters/digits/other (punctuation, prosigns) by color so
// copied text is easier to scan at a glance. Three colors, reusing the
// existing theme tokens rather than adding new ones.
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

final _digit = RegExp(r'^[0-9]$');
final _letter = RegExp(r'^[A-Za-z]$');

Color charTypeColor(String ch, AppColors c) {
  if (_digit.hasMatch(ch)) return c.info;
  if (_letter.hasMatch(ch)) return c.accent;
  return c.accentPurple;   // punctuation, prosign tokens
}
