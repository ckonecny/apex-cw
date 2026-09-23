// UDP transport for MOPP, mirroring the firmware's WiFi Trx: one socket bound
// to port 7373 that both listens and sends (m32_v6.ino sendWithWifi() /
// MorseMenu::setupWifi()). The peer is an IP or a host name; empty means
// local broadcast (255.255.255.255), same as the firmware.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'mopp.dart';

class MoppClient {
  static const port = 7373; // MORSERINOPORT

  RawDatagramSocket? _sock;
  InternetAddress? _peer;
  final _rx = StreamController<MoppPacket>.broadcast();

  /// Decoded, valid packets from anyone (firmware accepts any sender too).
  Stream<MoppPacket> get packets => _rx.stream;

  bool get isOpen => _sock != null;
  String? get peerLabel => _peer?.address;

  /// Throws if the peer cannot be resolved.
  Future<void> connect(String host) async {
    await close();
    final h = host.trim();
    if (h.isEmpty) {
      _peer = InternetAddress('255.255.255.255');
    } else {
      final addr = InternetAddress.tryParse(h);
      if (addr != null) {
        _peer = addr;
      } else {
        final found =
            await InternetAddress.lookup(h, type: InternetAddressType.IPv4);
        if (found.isEmpty) throw const SocketException('host not found');
        _peer = found.first;
      }
    }
    RawDatagramSocket s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
          reuseAddress: true);
    } on SocketException {
      // Port 7373 taken: still usable for a server (it replies to our source
      // port), just not for unsolicited peers.
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    s.broadcastEnabled = true;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = s.receive()) != null) {
        if (d!.data.isEmpty) continue; // keepalive
        final p = decodeMopp(d.data);
        if (p != null) _rx.add(p);
      }
    });
    _sock = s;
  }

  void send(Uint8List bytes) {
    final s = _sock, p = _peer;
    if (s == null || p == null) return;
    s.send(bytes, p, port);
  }

  Future<void> close() async {
    _sock?.close();
    _sock = null;
    _peer = null;
  }
}
