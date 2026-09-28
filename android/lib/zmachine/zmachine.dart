// Z-machine version 3 interpreter for the text adventures (Zork I–III).
//
// Pure Dart, no audio and no UI: the host calls [ZMachine.start] and then
// [ZMachine.input] once per command; both return the text the game printed
// until it waits for the next command. Follows the Z-Machine Standards
// Document 1.1 for version 3 only (the only version the three story files
// use). In-game SAVE hands a [ZSnapshot] to [ZMachine.onSave]; in-game
// RESTORE pauses in [ZState.waitingForRestore] until the host answers with
// [ZMachine.completeRestore]. The host can also take and load snapshots
// itself whenever the game waits for input (autosave, save slots, undo).
import 'dart:math';
import 'dart:typed_data';

enum ZState { running, waitingForInput, waitingForRestore, quit }

class ZMachineError implements Exception {
  final String message;
  ZMachineError(this.message);
  @override
  String toString() => 'ZMachineError: $message';
}

/// The v3 status line: current room (global 0), score (1), moves (2).
class ZStatus {
  final int roomObject;
  final String room;
  final int score;
  final int moves;
  const ZStatus(this.roomObject, this.room, this.score, this.moves);
}

class _Frame {
  final int returnPc;
  final int storeVar; // -1: discard (only the main routine's frame)
  final List<int> locals;
  final int stackBase;
  _Frame(this.returnPc, this.storeVar, this.locals, this.stackBase);
}

/// Complete machine state. [kind] says how to resume after loading:
/// [atRead] waits for input again (taken by the host between commands),
/// [afterSave] continues the game's SAVE instruction with "success".
class ZSnapshot {
  static const atRead = 0, afterSave = 1;
  static const _magic = 0x4E43575A; // "NCWZ"
  static const _formatVersion = 1;

  final int release;
  final String serial;
  final int checksum;
  final int kind;
  final int pc;
  final int textBuf, parseBuf;
  final Uint8List dynamicMem;
  final List<int> stack;
  final List<_Frame> _frames;

  ZSnapshot._(this.release, this.serial, this.checksum, this.kind, this.pc,
      this.textBuf, this.parseBuf, this.dynamicMem, this.stack, this._frames);

  Uint8List toBytes() {
    final b = BytesBuilder();
    void u8(int v) => b.addByte(v & 0xFF);
    void u16(int v) { u8(v >> 8); u8(v); }
    void u32(int v) { u16(v >> 16); u16(v); }
    u32(_magic);
    u8(_formatVersion);
    u16(release);
    b.add(serial.padRight(6).codeUnits.take(6).toList());
    u16(checksum);
    u8(kind);
    u32(pc);
    u16(textBuf);
    u16(parseBuf);
    u32(dynamicMem.length);
    b.add(dynamicMem);
    u32(stack.length);
    for (final v in stack) {
      u16(v);
    }
    u16(_frames.length);
    for (final f in _frames) {
      u32(f.returnPc);
      u16(f.storeVar & 0xFFFF);
      u32(f.stackBase);
      u8(f.locals.length);
      for (final l in f.locals) {
        u16(l);
      }
    }
    return b.toBytes();
  }

  static ZSnapshot fromBytes(Uint8List d) {
    var p = 0;
    int u8() => d[p++];
    int u16() { final v = (d[p] << 8) | d[p + 1]; p += 2; return v; }
    int u32() { final v = (u16() << 16) | u16(); return v; }
    if (d.length < 32 || u32() != _magic) throw ZMachineError('not a snapshot');
    if (u8() != _formatVersion) throw ZMachineError('unknown snapshot version');
    final release = u16();
    final serial = String.fromCharCodes(d.sublist(p, p + 6));
    p += 6;
    final checksum = u16();
    final kind = u8();
    final pc = u32();
    final textBuf = u16();
    final parseBuf = u16();
    final dynLen = u32();
    final dyn = Uint8List.fromList(d.sublist(p, p + dynLen));
    p += dynLen;
    final stack = List<int>.generate(u32(), (_) => u16());
    final frames = List<_Frame>.generate(u16(), (_) {
      final ret = u32();
      final sv = u16();
      final base = u32();
      final locals = List<int>.generate(u8(), (_) => u16());
      return _Frame(ret, sv == 0xFFFF ? -1 : sv, locals, base);
    });
    return ZSnapshot._(release, serial, checksum, kind, pc, textBuf, parseBuf,
        dyn, stack, frames);
  }
}

class ZMachine {
  final Uint8List story;
  late Uint8List mem;
  final List<int> _stack = [];
  final List<_Frame> _frames = [];
  int _pc = 0;
  ZState state = ZState.running;
  Random _rng;
  final StringBuffer _out = StringBuffer();
  final List<List<int>> _stream3 = []; // [table address, count]
  int _textBuf = 0, _parseBuf = 0;
  int _restoreBranchPc = 0;
  late final Map<int, int> _dict; // encoded word (32 bit) -> entry address
  late final Set<int> _separators;

  /// In-game SAVE. Store the snapshot and return true on success.
  bool Function(ZSnapshot snapshot)? onSave;

  ZMachine(Uint8List storyFile, {Random? random})
      : story = Uint8List.fromList(storyFile),
        _rng = random ?? Random() {
    if (story.isEmpty || story[0] != 3) {
      throw ZMachineError('only version 3 story files are supported');
    }
    mem = Uint8List.fromList(story);
    _buildDictionary();
  }

  // ---- header ----
  int get release => _rw(0x02);
  String get serial => String.fromCharCodes(story.sublist(0x12, 0x18));
  int get checksum => _rw(0x1C);
  int get _dynamicSize => (story[0x0E] << 8) | story[0x0F];
  int get _objTable => _rw(0x0A);
  int get _globals => _rw(0x0C);
  int get _abbrevs => _rw(0x18);
  int get _dictAddr => _rw(0x08);

  // ---- public API ----

  /// Starts (or restarts) the game; returns the opening text.
  String start() {
    _reset(keepFlags2: false);
    return _run();
  }

  /// Feeds one command line; returns the game's answer.
  String input(String line) {
    if (state != ZState.waitingForInput) {
      throw ZMachineError('not waiting for input');
    }
    final text = line.toLowerCase().runes
        .where((c) => c >= 32 && c <= 126)
        .toList();
    final max = mem[_textBuf] - 1;
    final n = min(text.length, max);
    for (var i = 0; i < n; i++) {
      mem[_textBuf + 1 + i] = text[i];
    }
    mem[_textBuf + 1 + n] = 0;
    _tokenise(_textBuf, _parseBuf);
    state = ZState.running;
    return _run();
  }

  /// Answers an in-game RESTORE: a snapshot to load, or null for "failed".
  String completeRestore(ZSnapshot? snap) {
    if (state != ZState.waitingForRestore) {
      throw ZMachineError('not waiting for restore');
    }
    if (snap == null || !matches(snap)) {
      _pc = _restoreBranchPc;
      state = ZState.running;
      _branch(false);
      return _run();
    }
    return load(snap);
  }

  bool matches(ZSnapshot s) =>
      s.release == release && s.serial == serial && s.checksum == checksum &&
      s.dynamicMem.length == _dynamicSize;

  /// Current state for the host; only valid while waiting for input.
  ZSnapshot snapshot() {
    if (state != ZState.waitingForInput) {
      throw ZMachineError('snapshots are taken between commands');
    }
    return _snapshot(ZSnapshot.atRead, _pc);
  }

  /// Loads a snapshot; returns any text printed on the way (the game's
  /// "Ok." after an in-game SAVE snapshot, nothing for host snapshots).
  String load(ZSnapshot s) {
    if (!matches(s)) throw ZMachineError('snapshot belongs to another story');
    final flags2 = mem[0x11];
    mem = Uint8List.fromList(story);
    mem.setRange(0, s.dynamicMem.length, s.dynamicMem);
    mem[0x11] = flags2;
    _initHeader();
    _stack
      ..clear()
      ..addAll(s.stack);
    _frames
      ..clear()
      ..addAll(s._frames.map((f) =>
          _Frame(f.returnPc, f.storeVar, List<int>.of(f.locals), f.stackBase)));
    _stream3.clear();
    _pc = s.pc;
    if (s.kind == ZSnapshot.atRead) {
      _textBuf = s.textBuf;
      _parseBuf = s.parseBuf;
      state = ZState.waitingForInput;
      return '';
    }
    state = ZState.running;
    _branch(true);
    return _run();
  }

  ZStatus get status {
    final room = _readGlobal(0);
    return ZStatus(room, room == 0 ? '' : objectName(room),
        _s16(_readGlobal(1)), _readGlobal(2));
  }

  // ---- objects (public for the map) ----

  int get objectCount {
    // The property tables start right after the last object entry.
    final first = _objAddr(1);
    final lowestProps = _rw(first + 7);
    return (lowestProps - first) ~/ 9;
  }

  int parentOf(int o) => mem[_objAddr(o) + 4];
  int siblingOf(int o) => mem[_objAddr(o) + 5];
  int childOf(int o) => mem[_objAddr(o) + 6];

  String objectName(int o) {
    final p = _rw(_objAddr(o) + 7);
    return mem[p] == 0 ? '' : _decode(p + 1);
  }

  bool hasAttr(int o, int attr) => _testAttr(o, attr);

  /// Raw property bytes of [o], or null if it doesn't have [prop].
  Uint8List? property(int o, int prop) {
    final a = _propAddr(o, prop);
    if (a == 0) return null;
    return Uint8List.fromList(mem.sublist(a, a + _propLen(a)));
  }

  // ---- internals ----

  void _reset({required bool keepFlags2}) {
    final flags2 = mem[0x11];
    mem = Uint8List.fromList(story);
    if (keepFlags2) mem[0x11] = flags2 & 0x03;
    _initHeader();
    _stack.clear();
    _frames
      ..clear()
      ..add(_Frame(0, -1, const [], 0));
    _stream3.clear();
    _pc = _rw(0x06);
    state = ZState.running;
  }

  void _initHeader() {
    // Flags 1: status line available, no split screen, fixed font default.
    mem[0x01] &= ~(0x10 | 0x20 | 0x40);
    mem[0x32] = 1; // standard revision 1.1
    mem[0x33] = 1;
  }

  String _run() {
    while (state == ZState.running) {
      _step();
    }
    final s = _out.toString();
    _out.clear();
    return s;
  }

  int _rw(int a) => (mem[a] << 8) | mem[a + 1];
  // Stores outside dynamic memory are dropped. Zork II's PICK-ONE on the
  // FANTASIES table (the Wizard's "Fantasize") has no counter word and
  // writes into static memory; Infocom's paging interpreters lost such
  // writes, while keeping them here corrupts code and crashes the game.
  void _ww(int a, int v) {
    if (a + 1 >= _dynamicSize) return;
    mem[a] = (v >> 8) & 0xFF;
    mem[a + 1] = v & 0xFF;
  }

  void _wb(int a, int v) {
    if (a >= _dynamicSize) return;
    mem[a] = v & 0xFF;
  }

  static int _s16(int v) => (v & 0x8000) != 0 ? (v & 0xFFFF) - 0x10000 : v & 0xFFFF;

  int _readGlobal(int g) => _rw(_globals + 2 * g);

  int _readVar(int v) {
    if (v == 0) {
      if (_stack.length <= _frames.last.stackBase) throw ZMachineError('stack underflow');
      return _stack.removeLast();
    }
    if (v < 16) return _frames.last.locals[v - 1];
    return _readGlobal(v - 16);
  }

  void _writeVar(int v, int value) {
    value &= 0xFFFF;
    if (v == 0) {
      _stack.add(value);
    } else if (v < 16) {
      _frames.last.locals[v - 1] = value;
    } else {
      _ww(_globals + 2 * (v - 16), value);
    }
  }

  // Indirect variable references (inc, dec, store, load, pull …) touch the
  // top of the stack in place instead of pushing/popping (§6.3.4).
  int _peekVar(int v) {
    if (v == 0) {
      if (_stack.length <= _frames.last.stackBase) throw ZMachineError('stack underflow');
      return _stack.last;
    }
    return _readVar(v);
  }

  void _pokeVar(int v, int value) {
    if (v == 0) {
      if (_stack.length <= _frames.last.stackBase) throw ZMachineError('stack underflow');
      _stack[_stack.length - 1] = value & 0xFFFF;
    } else {
      _writeVar(v, value);
    }
  }

  void _store(int value) => _writeVar(mem[_pc++], value);

  void _branch(bool cond) {
    final b = mem[_pc++];
    var offset = b & 0x3F;
    if ((b & 0x40) == 0) {
      offset = (offset << 8) | mem[_pc++];
      if ((offset & 0x2000) != 0) offset -= 0x4000;
    }
    if (((b & 0x80) != 0) != cond) return;
    if (offset == 0) {
      _return(0);
    } else if (offset == 1) {
      _return(1);
    } else {
      _pc += offset - 2;
    }
  }

  void _call(int packed, List<int> args, int storeVar) {
    if (packed == 0) {
      _writeVar(storeVar, 0);
      return;
    }
    var a = packed * 2;
    final n = mem[a++];
    final locals = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      locals[i] = _rw(a);
      a += 2;
    }
    for (var i = 0; i < args.length && i < n; i++) {
      locals[i] = args[i] & 0xFFFF;
    }
    _frames.add(_Frame(_pc, storeVar, locals, _stack.length));
    _pc = a;
  }

  void _return(int value) {
    if (_frames.length <= 1) throw ZMachineError('return from main routine');
    final f = _frames.removeLast();
    _stack.length = f.stackBase;
    _pc = f.returnPc;
    if (f.storeVar >= 0) _writeVar(f.storeVar, value);
  }

  int _operand(int type) {
    switch (type) {
      case 0:
        final v = _rw(_pc);
        _pc += 2;
        return v;
      case 1:
        return mem[_pc++];
      case 2:
        return _readVar(mem[_pc++]);
    }
    throw ZMachineError('bad operand type');
  }

  void _step() {
    final start = _pc;
    final op = mem[_pc++];
    if (op < 0x80) {
      final a = _operand((op & 0x40) != 0 ? 2 : 1);
      final b = _operand((op & 0x20) != 0 ? 2 : 1);
      _op2(op & 0x1F, [a, b], start);
    } else if (op < 0xC0) {
      final type = (op >> 4) & 3;
      if (type == 3) {
        _op0(op & 0x0F, start);
      } else {
        _op1(op & 0x0F, _operand(type), start);
      }
    } else {
      final types = mem[_pc++];
      final ops = <int>[];
      for (var shift = 6; shift >= 0; shift -= 2) {
        final t = (types >> shift) & 3;
        if (t == 3) break;
        ops.add(_operand(t));
      }
      if ((op & 0x20) == 0) {
        _op2(op & 0x1F, ops, start);
      } else {
        _opVar(op & 0x1F, ops, start);
      }
    }
  }

  Never _bad(String kind, int n, int at) =>
      throw ZMachineError('illegal $kind opcode $n at \$${at.toRadixString(16)}');

  void _op2(int n, List<int> o, int at) {
    final a = o.isNotEmpty ? o[0] : 0;
    final b = o.length > 1 ? o[1] : 0;
    switch (n) {
      case 1: // je
        var eq = false;
        for (var i = 1; i < o.length; i++) {
          if (o[i] == a) eq = true;
        }
        _branch(eq);
      case 2: _branch(_s16(a) < _s16(b)); // jl
      case 3: _branch(_s16(a) > _s16(b)); // jg
      case 4: // dec_chk
        final v = _s16(_peekVar(a)) - 1;
        _pokeVar(a, v);
        _branch(v < _s16(b));
      case 5: // inc_chk
        final v = _s16(_peekVar(a)) + 1;
        _pokeVar(a, v);
        _branch(v > _s16(b));
      case 6: _branch(a != 0 && parentOf(a) == b); // jin
      case 7: _branch((a & b) == b); // test
      case 8: _store(a | b); // or
      case 9: _store(a & b); // and
      case 10: _branch(_testAttr(a, b)); // test_attr
      case 11: _setAttr(a, b, true); // set_attr
      case 12: _setAttr(a, b, false); // clear_attr
      case 13: _pokeVar(a, b); // store
      case 14: _insertObj(a, b); // insert_obj
      case 15: _store(_rw((a + 2 * _s16(b)) & 0xFFFF)); // loadw
      case 16: _store(mem[(a + _s16(b)) & 0xFFFF]); // loadb
      case 17: // get_prop
        final pa = _propAddr(a, b);
        if (pa == 0) {
          _store(_rw(_objTable + 2 * (b - 1)));
        } else {
          _store(_propLen(pa) == 1 ? mem[pa] : _rw(pa));
        }
      case 18: _store(_propAddr(a, b)); // get_prop_addr
      case 19: _store(_nextProp(a, b)); // get_next_prop
      case 20: _store(a + b); // add
      case 21: _store(a - b); // sub
      case 22: _store(_s16(a) * _s16(b)); // mul
      case 23: // div
        if (_s16(b) == 0) throw ZMachineError('division by zero');
        _store(_s16(a) ~/ _s16(b));
      case 24: // mod
        if (_s16(b) == 0) throw ZMachineError('division by zero');
        _store(_s16(a).remainder(_s16(b)));
      default:
        _bad('2OP', n, at);
    }
  }

  void _op1(int n, int a, int at) {
    switch (n) {
      case 0: _branch(a == 0); // jz
      case 1: // get_sibling
        final s = a == 0 ? 0 : siblingOf(a);
        _store(s);
        _branch(s != 0);
      case 2: // get_child
        final c = a == 0 ? 0 : childOf(a);
        _store(c);
        _branch(c != 0);
      case 3: _store(a == 0 ? 0 : parentOf(a)); // get_parent
      case 4: _store(a == 0 ? 0 : _propLen(a)); // get_prop_len
      case 5: _pokeVar(a, _peekVar(a) + 1); // inc
      case 6: _pokeVar(a, _peekVar(a) - 1); // dec
      case 7: _print(_decode(a)); // print_addr
      case 9: _removeObj(a); // remove_obj
      case 10: _print(objectName(a)); // print_obj
      case 11: _return(a); // ret
      case 12: _pc += _s16(a) - 2; // jump
      case 13: _print(_decode(a * 2)); // print_paddr
      case 14: _store(_peekVar(a)); // load
      case 15: _store(~a); // not
      default:
        _bad('1OP', n, at);
    }
  }

  void _op0(int n, int at) {
    switch (n) {
      case 0: _return(1); // rtrue
      case 1: _return(0); // rfalse
      case 2: // print
        _print(_decode(_pc));
        _pc = _zEnd;
      case 3: // print_ret
        _print(_decode(_pc));
        _pc = _zEnd;
        _print('\n');
        _return(1);
      case 4: break; // nop
      case 5: // save
        final ok = onSave?.call(_snapshot(ZSnapshot.afterSave, _pc)) ?? false;
        _branch(ok);
      case 6: // restore
        _restoreBranchPc = _pc;
        state = ZState.waitingForRestore;
      case 7: _reset(keepFlags2: true); // restart
      case 8: _return(_readVar(0)); // ret_popped
      case 9: _readVar(0); // pop
      case 10: state = ZState.quit; // quit
      case 11: _print('\n'); // new_line
      case 12: break; // show_status: the host reads [status] itself
      case 13: _branch(true); // verify
      default:
        _bad('0OP', n, at);
    }
  }

  void _opVar(int n, List<int> o, int at) {
    int arg(int i) => i < o.length ? o[i] : 0;
    switch (n) {
      case 0: // call
        final sv = mem[_pc++];
        _call(arg(0), o.length > 1 ? o.sublist(1) : const [], sv);
      case 1: _ww((arg(0) + 2 * _s16(arg(1))) & 0xFFFF, arg(2)); // storew
      case 2: _wb((arg(0) + _s16(arg(1))) & 0xFFFF, arg(2)); // storeb
      case 3: // put_prop
        final pa = _propAddr(arg(0), arg(1));
        if (pa == 0) throw ZMachineError('put_prop: object ${arg(0)} lacks property ${arg(1)}');
        if (_propLen(pa) == 1) {
          mem[pa] = arg(2) & 0xFF;
        } else {
          _ww(pa, arg(2));
        }
      case 4: // sread
        _textBuf = arg(0);
        _parseBuf = arg(1);
        state = ZState.waitingForInput;
      case 5: _print(_zsciiChar(arg(0))); // print_char
      case 6: _print('${_s16(arg(0))}'); // print_num
      case 7: // random
        final r = _s16(arg(0));
        if (r > 0) {
          _store(_rng.nextInt(r) + 1);
        } else {
          _rng = r < 0 ? Random(-r) : Random();
          _store(0);
        }
      case 8: _writeVar(0, arg(0)); // push
      case 9: // pull
        final v = _readVar(0);
        _pokeVar(arg(0), v);
      case 10: case 11: break; // split_window, set_window: no upper window
      case 19: // output_stream
        final s = _s16(arg(0));
        if (s == 3) {
          if (_stream3.length >= 16) throw ZMachineError('stream 3 nested too deep');
          _stream3.add([arg(1), 0]);
        } else if (s == -3 && _stream3.isNotEmpty) {
          final t = _stream3.removeLast();
          _ww(t[0], t[1]);
        }
      case 20: case 21: break; // input_stream, sound_effect
      default:
        _bad('VAR', n, at);
    }
  }

  // ---- output ----

  void _print(String s) {
    if (_stream3.isNotEmpty) {
      final t = _stream3.last;
      for (final c in s.codeUnits) {
        mem[t[0] + 2 + t[1]] = c == 10 ? 13 : c;
        t[1]++;
      }
      return;
    }
    _out.write(s);
  }

  static String _zsciiChar(int c) {
    if (c == 13) return '\n';
    if (c >= 32 && c <= 126) return String.fromCharCode(c);
    return '';
  }

  // ---- text ----

  static const _a0 = 'abcdefghijklmnopqrstuvwxyz';
  static const _a1 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  // Alphabet 2 from z-char 7 on (6 is the ZSCII escape).
  static const _a2 = '\n0123456789.,!?_#\'"/\\-:()';

  int _zEnd = 0;

  String _decode(int addr, {bool inAbbrev = false}) {
    final zs = <int>[];
    var a = addr;
    while (true) {
      final w = _rw(a);
      a += 2;
      zs..add((w >> 10) & 31)..add((w >> 5) & 31)..add(w & 31);
      if ((w & 0x8000) != 0) break;
    }
    final end = a;
    final sb = StringBuffer();
    var alphabet = 0;
    for (var i = 0; i < zs.length; i++) {
      final z = zs[i];
      if (z == 0) {
        sb.write(' ');
      } else if (z >= 1 && z <= 3) {
        if (inAbbrev) throw ZMachineError('nested abbreviation');
        if (i + 1 >= zs.length) break;
        final idx = 32 * (z - 1) + zs[++i];
        sb.write(_decode(_rw(_abbrevs + 2 * idx) * 2, inAbbrev: true));
      } else if (z == 4 || z == 5) {
        alphabet = z - 3;
        continue;
      } else if (alphabet == 2 && z == 6) {
        if (i + 2 >= zs.length) break;
        sb.write(_zsciiChar((zs[i + 1] << 5) | zs[i + 2]));
        i += 2;
      } else {
        sb.write(alphabet == 0
            ? _a0[z - 6]
            : alphabet == 1
                ? _a1[z - 6]
                : _a2[z - 7]);
      }
      alphabet = 0;
    }
    if (!inAbbrev) _zEnd = end;
    return sb.toString();
  }

  static int _encodeWord(String word) {
    final zs = <int>[];
    for (final c in word.codeUnits) {
      final ch = String.fromCharCode(c);
      final i0 = _a0.indexOf(ch);
      if (i0 >= 0) {
        zs.add(i0 + 6);
        continue;
      }
      final i2 = _a2.indexOf(ch);
      if (i2 > 0) {
        zs..add(5)..add(i2 + 7);
      } else {
        zs..add(5)..add(6)..add(c >> 5)..add(c & 31);
      }
    }
    while (zs.length < 6) {
      zs.add(5);
    }
    final w1 = (zs[0] << 10) | (zs[1] << 5) | zs[2];
    final w2 = (zs[3] << 10) | (zs[4] << 5) | zs[5] | 0x8000;
    return (w1 << 16) | w2;
  }

  void _buildDictionary() {
    final d = _dictAddr;
    final n = mem[d];
    _separators = mem.sublist(d + 1, d + 1 + n).toSet();
    final entryLen = mem[d + 1 + n];
    final count = _s16(_rw(d + 2 + n));
    final first = d + 4 + n;
    _dict = {};
    for (var i = 0; i < count.abs(); i++) {
      final e = first + i * entryLen;
      _dict[(_rw(e) << 16) | _rw(e + 2)] = e;
    }
  }

  void _tokenise(int text, int parse) {
    final maxWords = mem[parse];
    var count = 0;
    var i = text + 1;
    void add(int start, int end) {
      if (count >= maxWords) return;
      final word = String.fromCharCodes(mem.sublist(start, end));
      final e = parse + 2 + count * 4;
      _ww(e, _dict[_encodeWord(word)] ?? 0);
      mem[e + 2] = end - start;
      mem[e + 3] = start - text;
      count++;
    }
    while (mem[i] != 0) {
      final c = mem[i];
      if (c == 32) {
        i++;
      } else if (_separators.contains(c)) {
        add(i, i + 1);
        i++;
      } else {
        final s = i;
        while (mem[i] != 0 && mem[i] != 32 && !_separators.contains(mem[i])) {
          i++;
        }
        add(s, i);
      }
    }
    mem[parse + 1] = count;
  }

  // ---- objects ----

  int _objAddr(int o) {
    if (o < 1 || o > 255) throw ZMachineError('bad object $o');
    return _objTable + 31 * 2 + (o - 1) * 9;
  }

  bool _testAttr(int o, int attr) =>
      (mem[_objAddr(o) + attr ~/ 8] & (0x80 >> (attr % 8))) != 0;

  void _setAttr(int o, int attr, bool on) {
    final a = _objAddr(o) + attr ~/ 8;
    final bit = 0x80 >> (attr % 8);
    mem[a] = on ? mem[a] | bit : mem[a] & ~bit;
  }

  void _removeObj(int o) {
    final oa = _objAddr(o);
    final p = mem[oa + 4];
    if (p == 0) return;
    final pa = _objAddr(p);
    if (mem[pa + 6] == o) {
      mem[pa + 6] = mem[oa + 5];
    } else {
      var s = mem[pa + 6];
      while (s != 0) {
        final sa = _objAddr(s);
        if (mem[sa + 5] == o) {
          mem[sa + 5] = mem[oa + 5];
          break;
        }
        s = mem[sa + 5];
      }
    }
    mem[oa + 4] = 0;
    mem[oa + 5] = 0;
  }

  void _insertObj(int o, int dest) {
    _removeObj(o);
    final oa = _objAddr(o);
    final da = _objAddr(dest);
    mem[oa + 5] = mem[da + 6];
    mem[da + 6] = o;
    mem[oa + 4] = dest;
  }

  int _firstProp(int o) {
    final p = _rw(_objAddr(o) + 7);
    return p + 1 + 2 * mem[p];
  }

  /// Address of the data of property [prop] of [o], 0 if absent.
  int _propAddr(int o, int prop) {
    var a = _firstProp(o);
    while (mem[a] != 0) {
      final num = mem[a] & 31;
      final len = (mem[a] >> 5) + 1;
      if (num == prop) return a + 1;
      if (num < prop) return 0; // properties are stored in descending order
      a += 1 + len;
    }
    return 0;
  }

  int _propLen(int dataAddr) => (mem[dataAddr - 1] >> 5) + 1;

  int _nextProp(int o, int prop) {
    if (prop == 0) return mem[_firstProp(o)] & 31;
    final a = _propAddr(o, prop);
    if (a == 0) throw ZMachineError('get_next_prop: no property $prop on $o');
    return mem[a + _propLen(a)] & 31;
  }

  ZSnapshot _snapshot(int kind, int pc) => ZSnapshot._(
        release, serial, checksum, kind, pc, _textBuf, _parseBuf,
        Uint8List.fromList(mem.sublist(0, _dynamicSize)),
        List<int>.of(_stack),
        _frames
            .map((f) => _Frame(f.returnPc, f.storeVar, List<int>.of(f.locals), f.stackBase))
            .toList(),
      );
}
