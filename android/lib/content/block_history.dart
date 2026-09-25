// Quote der letzten Blöcke pro Training (Hören / Geben) für die Trendanzeige
// auf der Ergebnis-Seite. docs/training/P8-extras.md, Punkt Trend.
import 'package:shared_preferences/shared_preferences.dart';

const _window = 5;
const _keep = 20;
const _flatBand = 3; // Prozentpunkte, darunter gilt der Trend als gleich

class BlockTrend {
  final int percent; // Mittel der letzten 5 Blöcke
  final int direction; // 1 = besser, -1 = schlechter, 0 = gleich
  const BlockTrend(this.percent, this.direction);
  String get arrow => direction > 0 ? '▲' : direction < 0 ? '▼' : '►';
}

/// Trend aus Blockquoten (0..1), älteste zuerst. Null unter 6 Blöcken.
BlockTrend? trendOf(List<double> rates) {
  if (rates.length <= _window) return null;
  double avg(Iterable<double> l) => l.fold(0.0, (a, b) => a + b) / l.length;
  final recent = avg(rates.sublist(rates.length - _window));
  final before = rates.sublist(0, rates.length - _window);
  final prev = avg(before.length > _window ? before.sublist(before.length - _window) : before);
  final diff = (recent - prev) * 100;
  final dir = diff >= _flatBand ? 1 : diff <= -_flatBand ? -1 : 0;
  return BlockTrend((recent * 100).round(), dir);
}

class BlockHistory {
  final String track; // 'hear' | 'echo'
  const BlockHistory(this.track);
  String get _key => 'blockHistory.$track';

  Future<List<double>> load(SharedPreferences p) async =>
      (p.getStringList(_key) ?? const []).map(double.tryParse).whereType<double>().toList();

  /// Hängt die Quote des eben beendeten Blocks an und liefert den Trend.
  Future<BlockTrend?> record(SharedPreferences p, double rate) async {
    final rates = await load(p)..add(rate.clamp(0.0, 1.0));
    final kept = rates.length > _keep ? rates.sublist(rates.length - _keep) : rates;
    await p.setStringList(_key, kept.map((r) => r.toStringAsFixed(4)).toList());
    return trendOf(kept);
  }
}
