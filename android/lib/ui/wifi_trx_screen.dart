import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/paddle_widgets.dart';
import '../content/training_profile.dart';
import '../l10n/strings.dart';
import '../net/mopp.dart';
import 'widgets/training_settings_sheet.dart';
import '../net/mopp_client.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';

/// WiFi Trx: send/receive Morse over UDP (MOPP) to a server such as
/// cq.morserino.info, like the firmware's WiFi Trx mode. Uses the system
/// WLAN/mobile data, so no SSID/password handling.
class WifiTrxScreen extends StatefulWidget {
  const WifiTrxScreen({super.key});

  @override
  State<WifiTrxScreen> createState() => _WifiTrxScreenState();
}

class _Seg {
  final bool rx;
  String text;
  _Seg(this.rx, this.text);
}

class _Svc {
  final String id;
  String name, host;
  _Svc(this.id, this.name, this.host);
  Map<String, String> toJson() => {'id': id, 'name': name, 'host': host};
}

class _WifiTrxScreenState extends State<WifiTrxScreen> {
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');

  final _client  = MoppClient();
  final _encoder = MoppEncoder();
  StreamSubscription? _symSub, _genSub, _rxSub;

  List<_Svc> _services = [];
  String _svcId = '';
  _Svc get _svc => _services.firstWhere((s) => s.id == _svcId);
  final _textCtl   = TextEditingController();
  final _scroll    = ScrollController();

  bool _ready = false;
  bool _connected = false;
  bool _connecting = false;
  String _status = '';
  int _wpm = 20;
  int _keyerMode = 0;
  int _outputCase = 0;
  final List<_Seg> _log = [];
  bool _touchDit = false, _touchDah = false;

  // Received words are played one after another with their own WPM.
  final Queue<MoppPacket> _playQueue = Queue();
  bool _playing = false;
  Timer? _playGuard;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _symSub = _symbolStream.receiveBroadcastStream().listen((s) => _onSymbol(s as String));
    _genSub = _genEvents.receiveBroadcastStream().listen((e) {
      if (e is Map && e['type'] == 'done') _playDone();
    });
    _rxSub = _client.packets.listen(_onPacket);
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _wpm        = p.getInt('wpm') ?? 20;
    _keyerMode  = p.getInt('keyerMode') ?? 0;
    _outputCase = (p.getInt('outputCase') ?? 0).clamp(0, 1);
    _wpm = (p.getInt('trxWpm') ?? _wpm).clamp(5, 60);
    try {
      final raw = p.getString('trxServices');
      if (raw != null) {
        _services = [for (final m in jsonDecode(raw) as List)
          _Svc(m['id'] as String, m['name'] as String, m['host'] as String)];
      }
    } catch (_) {}
    if (_services.isEmpty) {
      final h = p.getString('trxServer') ?? 'cq.morserino.info';
      _services = [_Svc('s0', h.isEmpty ? 'Broadcast' : h, h)];
    }
    _svcId = p.getString('trxServiceId') ?? _services.first.id;
    if (!_services.any((s) => s.id == _svcId)) _svcId = _services.first.id;
    await _loadLog();
    // The native engine is a shared singleton: push this screen's own config
    // (same set as the keyer screen) instead of assuming it is still valid.
    final pitch = p.getInt('pitch') ?? 600;
    final soft  = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setVolume', 0.7);
    await _toneChannel.invokeMethod('setEnvelopeMs', (soft + 1).toDouble());
    await _keyerChannel.invokeMethod('setWpm', _wpm);
    await _keyerChannel.invokeMethod('setMode', _keyerMode);
    await _keyerChannel.invokeMethod('setCurtisBTiming', {
      'dit': (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
      'dah': (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
    });
    await _keyerChannel.invokeMethod('setAcs', (p.getInt('acs') ?? 0).clamp(0, 3));
    await _keyerChannel.invokeMethod('setInterWordSpace', (p.getInt('profile.trx.interWordSpace') ?? TrainingProfile.defaultInterWord(TrainingProfile.trx)).clamp(6, 105));
    await _keyerChannel.invokeMethod('start');
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _playGuard?.cancel();
    _symSub?.cancel();
    _genSub?.cancel();
    _rxSub?.cancel();
    _client.close();
    _genChannel.invokeMethod('stop');   // also restarts the keyer …
    _keyerChannel.invokeMethod('stop'); // … which we then stop, like KeyerScreen
    _textCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Connection ──────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final host = _svc.host.trim();
    setState(() { _connecting = true; _status = 'Resolving…'; });
    try {
      await _client.connect(host);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
        _status = 'Connected to ${_client.peerLabel}:${MoppClient.port}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _connecting = false; _status = 'Failed: $e'; });
    }
  }

  Future<void> _disconnect() async {
    _encoder.reset();
    _playQueue.clear();
    await _client.close();
    if (mounted) setState(() { _connected = false; _status = 'Disconnected'; });
  }

  // ── Transmit ────────────────────────────────────────────────────────────

  // The keyer stream: '·' '—' elements, ' ' after a character, '  ' after a
  // word gap. Maps 1:1 onto the firmware's cwForTx(0..3) calls.
  void _onSymbol(String s) {
    if (!_connected) { _encoder.reset(); return; }
    Uint8List? pkt;
    switch (s) {
      case '·':  _encoder.element(1, _wpm); break;
      case '—':  _encoder.element(2, _wpm); break;
      case ' ':  if (_encoder.hasPending) _encoder.element(0, _wpm); break;
      case '  ': if (_encoder.hasPending) pkt = _encoder.element(3, _wpm); break;
    }
    if (pkt != null) _sendPacket(pkt);
  }

  void _sendPacket(Uint8List pkt) {
    _client.send(pkt);
    final p = decodeMopp(pkt);
    if (p != null) _append(false, p.text);
  }

  void _sendText(String text) {
    if (!_connected || text.trim().isEmpty) return;
    for (final pkt in MoppEncoder().encodeText(text, _wpm)) {
      _sendPacket(pkt);
    }
  }

  // ── Receive ─────────────────────────────────────────────────────────────

  void _onPacket(MoppPacket p) {
    if (!_connected) return;
    final t = p.text;
    _append(true, t);
    if (t.toLowerCase().startsWith(':bye')) {
      setState(() { _connected = false; _status = 'Server closed the connection (:bye)'; });
      _client.close();
      return;
    }
    _playQueue.add(p);
    _playNext();
  }

  void _playNext() {
    if (_playing || _playQueue.isEmpty) return;
    final p = _playQueue.removeFirst();
    _playing = true;
    // Generator config is shared state — push what playback needs each time.
    _genChannel.invokeMethod('setWpm', p.wpm);
    _genChannel.invokeMethod('setInterCharSpace', 3);
    _genChannel.invokeMethod('playPatterns', p.patterns);
    // Safety net if the engine never reports done (e.g. it was busy).
    final dits = p.patterns.fold<int>(0, (a, s) => a +
        s.split('').fold<int>(0, (b, c) => b + (c == '.' ? 2 : 4)) + 2);
    _playGuard?.cancel();
    _playGuard = Timer(
        Duration(milliseconds: (1200 * dits / p.wpm).round() + 1500), _playDone);
  }

  void _playDone() {
    _playGuard?.cancel();
    _playing = false;
    _playNext();
  }

  // ── Log ─────────────────────────────────────────────────────────────────

  void _append(bool rx, String text) {
    if (!mounted) return;
    setState(() {
      if (_log.isNotEmpty && _log.last.rx == rx) {
        _log.last.text += ' $text';
      } else {
        _log.add(_Seg(rx, text));
      }
      if (_log.length > 200) _log.removeAt(0);
    });
    _saveLog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _saveServices() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('trxServices', jsonEncode([for (final s in _services) s.toJson()]));
    await p.setString('trxServiceId', _svcId);
  }

  Future<void> _loadLog() async {
    final p = await SharedPreferences.getInstance();
    _log.clear();
    try {
      final raw = p.getString('trxLog_$_svcId');
      if (raw != null) {
        for (final m in jsonDecode(raw) as List) {
          _log.add(_Seg(m['rx'] as bool, m['t'] as String));
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLog() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('trxLog_$_svcId',
        jsonEncode([for (final s in _log) {'rx': s.rx, 't': s.text}]));
  }

  Future<void> _selectService(String id) async {
    _svcId = id;
    await _saveServices();
    await _loadLog();
    if (mounted) setState(() {});
  }

  Future<void> _editService({required bool add}) async {
    final svc = add ? null : _svc;
    final nameCtl = TextEditingController(text: svc?.name ?? '');
    final hostCtl = TextEditingController(text: svc?.host ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(add ? 'Add service' : 'Edit service'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Name')),
          TextField(
            controller: hostCtl,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Server (name or IP, empty = broadcast)'),
          ),
        ]),
        actions: [
          if (!add && _services.length > 1)
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('Delete')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    final host = hostCtl.text.trim();
    final name = nameCtl.text.trim().isEmpty
        ? (host.isEmpty ? 'Broadcast' : host) : nameCtl.text.trim();
    // Controllers are not disposed here: the dialog's exit animation still
    // uses them, and disposing early trips a framework assertion.
    if (res == null) return;
    final p = await SharedPreferences.getInstance();
    if (res == 'delete') {
      final id = _svcId;
      _services.removeWhere((s) => s.id == id);
      await p.remove('trxLog_$id');
      await _selectService(_services.first.id);
    } else if (add) {
      final id = 's${DateTime.now().millisecondsSinceEpoch}';
      _services.add(_Svc(id, name, host));
      await _selectService(id);
    } else {
      svc!..name = name..host = host;
      await _saveServices();
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmClearLog() async {
    if (_log.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear log?'),
        content: Text('Delete the saved text of "${_svc.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _log.clear());
    _saveLog();
  }

  Future<void> _setWpm(int w) async {
    setState(() => _wpm = w);
    (await SharedPreferences.getInstance()).setInt('trxWpm', w);
    _keyerChannel.invokeMethod('setWpm', w);
  }

  // ── Touch paddles ───────────────────────────────────────────────────────

  void _setTouchInputs({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  String _case(String s) => _outputCase == 1 ? s.toUpperCase() : s.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text('WiFi Trx',
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            tooltip: Strings.t('settings_title'),
            onPressed: () async {
              await showTrainingSettingsSheet(context,
                  profile: TrainingProfile.trx,
                  sections: const [TrainingSection.wordSpacing]);
              final p = await SharedPreferences.getInstance();
              await _keyerChannel.invokeMethod('setInterWordSpace',
                  (p.getInt('profile.trx.interWordSpace') ?? 7).clamp(6, 105));
            },
          ),
        ],
      ),
      body: _ready ? _body(c) : Center(child: CircularProgressIndicator(color: c.accent)),
    );
  }

  Widget _body(AppColors c) {
    final mono = TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            key: ValueKey(_svcId),
            initialValue: _svcId,
            isExpanded: true,
            isDense: true,
            dropdownColor: c.surface,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.accent),
            decoration: InputDecoration(
              isDense: true, filled: true, fillColor: c.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.border)),
            ),
            items: [for (final s in _services)
              DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
            onChanged: (_connected || _connecting) ? null : (v) => _selectService(v!),
          )),
          IconButton(
            icon: Icon(Icons.edit, size: 20, color: c.textMuted),
            onPressed: (_connected || _connecting) ? null : () => _editService(add: false),
          ),
          IconButton(
            icon: Icon(Icons.add, size: 22, color: c.textMuted),
            onPressed: (_connected || _connecting) ? null : () => _editService(add: true),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _connecting ? null : (_connected ? _disconnect : _connect),
            child: Text(_connected ? 'Disconnect' : 'Connect'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Icon(_connected ? Icons.wifi : Icons.wifi_off, size: 16,
              color: _connected ? c.accent : c.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(
              _status.isEmpty ? 'Not connected' : _status,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('$_wpm WPM', style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.accent)),
          Expanded(child: Slider(
            value: _wpm.toDouble(), min: 5, max: 60, divisions: 55,
            onChanged: (v) => setState(() => _wpm = v.round()),
            onChangeEnd: (v) => _setWpm(v.round()),
          )),
        ]),
      ),
      Expanded(
        child: GestureDetector(
          onLongPress: _confirmClearLog,
          child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: _log.isEmpty
              ? Center(child: Text('· · ·', style: mono.copyWith(color: c.textFaint)))
              : ListView(controller: _scroll, children: [
                  for (final s in _log)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: s.rx ? 'RX  ' : 'TX  ',
                            style: mono.copyWith(fontSize: 11,
                                color: s.rx ? c.info : c.warning)),
                        TextSpan(text: _case(s.text),
                            style: mono.copyWith(fontSize: 18,
                                color: s.rx ? c.textPrimary : c.accent)),
                      ])),
                    ),
                ]),
        )),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _textCtl,
            enabled: _connected,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) { _sendText(_textCtl.text); _textCtl.clear(); },
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textPrimary),
            decoration: InputDecoration(
              isDense: true, filled: true, fillColor: c.surface,
              hintText: 'Send text…',
              hintStyle: TextStyle(fontFamily: 'CwMono', color: c.textDisabled),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.border)),
            ),
          )),
          IconButton(
            icon: Icon(Icons.send, color: _connected ? c.accent : c.textDisabled),
            onPressed: _connected
                ? () { _sendText(_textCtl.text); _textCtl.clear(); }
                : null,
          ),
        ]),
      ),
      const SizedBox(height: 8),
      if (_keyerMode == 4)
        StraightKeyPaddle(
            onDown: () => _setTouchInputs(dit: true),
            onUp: () => _setTouchInputs(dit: false))
      else
        IambicPaddles(
          onDitDown: () => _setTouchInputs(dit: true),
          onDitUp:   () => _setTouchInputs(dit: false),
          onDahDown: () => _setTouchInputs(dah: true),
          onDahUp:   () => _setTouchInputs(dah: false),
        ),
      const SizedBox(height: 16),
    ]);
  }
}
