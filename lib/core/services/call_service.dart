import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../navigation/nav_service.dart';
import '../network/socket_service.dart';
import '../storage/secure_storage.dart';
import 'push/call_wake.dart';
import '../../shared/screens/call_screen.dart';
import '../config/app_flavor.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// In-app voice calls between a household and its collector, over WebRTC.
///
/// Audio goes phone-to-phone; the BinLink socket only relays the signaling
/// (`call:invite` → `call:incoming` → `call:accept` → offer/answer/ICE via
/// `call:signal` → `call:end`). Free: no calling provider, no per-minute cost.
/// One call at a time; a second incoming call while busy is declined.
class CallService extends ChangeNotifier {
  CallService._();
  static final instance = CallService._();

  static const _connectTimeout = Duration(seconds: 30);

  bool _listening = false;

  CallPhase phase = CallPhase.idle;
  String? callId;
  String? bookingId;
  String peerName = '';
  String? peerPhone;
  bool isCaller = false;
  bool muted = false;
  bool speaker = false;
  DateTime? connectedAt;

  /// Why the last call ended: hangup, declined, no_answer, failed, offline…
  String? endReason;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': ['stun:stun.l.google.com:19302']},
  ];
  final _pendingCandidates = <RTCIceCandidate>[];
  bool _remoteSet = false;
  Timer? _connectTimer;
  final _ringer = AudioPlayer();

  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;

  /// This device's signed-in user id — used to verify an incoming call is
  /// actually addressed to us (payload.toId) before ringing.
  String? _myUserId;

  /// Registers the socket listeners once (call at app start).
  void init() {
    if (_listening) return;
    _listening = true;
    _loadMyId();
    SocketService.on('call:incoming', _onIncoming);
    SocketService.on('call:accepted', _onAccepted);
    SocketService.on('call:signal', _onSignal);
    SocketService.on('call:ended', _onEnded);
  }

  Future<void> _loadMyId() async {
    try {
      final u = await SecureStorage.getUser();
      _myUserId = u?['id'] as String?;
    } catch (_) {}
  }

  // ── Outgoing ──────────────────────────────────────────────────────────────

  /// Starts a call to the other party on [bookingId] and opens the call screen.
  /// Returns an error message, or null when the call screen opened.
  Future<String?> start({required String bookingId, required String peerName, String? peerPhone}) async {
    if (busy) return 'You are already on a call.';
    await SocketService.ensureConnected();
    final res = await _emitAck('call:invite', {'bookingId': bookingId});
    if (res == null) return 'Could not reach ${FlavorConfig.appName}. Check your connection.';
    if (res['ok'] != true) return (res['error'] as String?) ?? 'Could not start the call.';

    _reset();
    this.bookingId = bookingId;
    this.peerName = peerName;
    this.peerPhone = peerPhone;
    callId = res['callId'] as String?;
    isCaller = true;
    _setIce(res['iceServers']);
    phase = CallPhase.outgoing;
    notifyListeners();
    _openScreen();
    return null;
  }

  Future<void> _onAccepted(dynamic data) async {
    if (data is! Map || data['callId'] != callId || !isCaller) return;
    phase = CallPhase.connecting;
    notifyListeners();
    _armConnectTimer();
    try {
      await _createPeer();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
      await _pc!.setLocalDescription(offer);
      _signal({'type': 'offer', 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('[Call] offer failed: $e');
      hangUp(reason: _micDenied(e) ? 'mic_denied' : 'failed');
    }
  }

  // ── Incoming ──────────────────────────────────────────────────────────────

  void _onIncoming(dynamic data) {
    if (data is! Map) return;
    final id = data['callId'] as String?;
    if (id == null || id == callId) return; // re-delivery of the call we already show
    // Only ring if the call is addressed to THIS user. Stops a caller (or a
    // device signed into the other role) from ringing itself.
    final toId = data['toId'] as String?;
    if (toId != null && _myUserId != null && toId != _myUserId) return;
    // We are the caller placing a call — never ring ourselves for it.
    if (isCaller && busy) return;
    if (busy) {
      SocketService.emit('call:reject', {'callId': id});
      return;
    }
    _reset();
    // The in-app ring is taking over — clear any full-screen wake notification.
    CallWake.clearCall();
    callId = id;
    bookingId = data['bookingId'] as String?;
    peerName = (data['fromName'] as String?) ?? 'BinLink Eco';
    isCaller = false;
    _setIce(data['iceServers']);
    phase = CallPhase.incoming;
    notifyListeners();
    _ring(true);
    _openScreen();
  }

  Future<void> accept() async {
    if (phase != CallPhase.incoming) return;
    _ring(false);
    phase = CallPhase.connecting;
    notifyListeners();
    try {
      // Ask for the microphone before telling the caller we picked up.
      await _createPeer();
    } catch (e) {
      debugPrint('[Call] mic failed: $e');
      hangUp(reason: _micDenied(e) ? 'mic_denied' : 'failed');
      return;
    }
    final res = await _emitAck('call:accept', {'callId': callId});
    if (res == null || res['ok'] != true) {
      _finish('ended');
      return;
    }
    _armConnectTimer();
  }

  void decline() {
    if (phase != CallPhase.incoming) return;
    SocketService.emit('call:reject', {'callId': callId});
    _finish('declined_by_me');
  }

  // ── Signaling ─────────────────────────────────────────────────────────────

  Future<void> _onSignal(dynamic payload) async {
    if (payload is! Map || payload['callId'] != callId || _pc == null) return;
    final data = payload['data'];
    if (data is! Map) return;
    try {
      switch (data['type']) {
        case 'offer':
          await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'offer'));
          await _flushCandidates();
          final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
          await _pc!.setLocalDescription(answer);
          _signal({'type': 'answer', 'sdp': answer.sdp});
        case 'answer':
          await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'answer'));
          await _flushCandidates();
        case 'ice':
          final c = RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            (data['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (_remoteSet) {
            await _pc!.addCandidate(c);
          } else {
            _pendingCandidates.add(c);
          }
      }
    } catch (e) {
      debugPrint('[Call] signal ${data['type']} failed: $e');
    }
  }

  Future<void> _flushCandidates() async {
    _remoteSet = true;
    for (final c in _pendingCandidates) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  void _signal(Map<String, dynamic> data) =>
      SocketService.emit('call:signal', {'callId': callId, 'data': data});

  Future<void> _createPeer() async {
    _local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _pc = await createPeerConnection({'iceServers': _iceServers, 'sdpSemantics': 'unified-plan'});
    for (final t in _local!.getAudioTracks()) {
      await _pc!.addTrack(t, _local!);
    }
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _signal({'type': 'ice', 'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    _pc!.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _connectTimer?.cancel();
          if (phase != CallPhase.active) {
            phase = CallPhase.active;
            connectedAt = DateTime.now();
            Helper.setSpeakerphoneOn(speaker).catchError((_) {});
            notifyListeners();
          }
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          hangUp(reason: 'failed');
        default:
          break;
      }
    };
  }

  void _armConnectTimer() {
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectTimeout, () {
      if (phase == CallPhase.connecting) hangUp(reason: 'failed');
    });
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    notifyListeners();
    try {
      await Helper.setSpeakerphoneOn(speaker);
    } catch (_) {}
  }

  void hangUp({String reason = 'hangup'}) {
    if (!busy) return;
    if (callId != null) SocketService.emit('call:end', {'callId': callId});
    _finish(reason);
  }

  void _onEnded(dynamic data) {
    if (data is! Map || data['callId'] != callId) return;
    _finish((data['reason'] as String?) ?? 'hangup');
  }

  void _finish(String reason) {
    if (phase == CallPhase.ended || phase == CallPhase.idle) return;
    endReason = reason;
    phase = CallPhase.ended;
    CallWake.clearCall();
    _teardown();
    notifyListeners();
  }

  /// Called by the call screen once it has shown the "call ended" state.
  void dismiss() {
    if (phase == CallPhase.ended) {
      phase = CallPhase.idle;
      callId = null;
      notifyListeners();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _teardown() {
    _ring(false);
    _connectTimer?.cancel();
    try {
      _local?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _local?.dispose().catchError((_) {});
    _pc?.close().catchError((_) {});
    _local = null;
    _pc = null;
    _pendingCandidates.clear();
    _remoteSet = false;
  }

  void _reset() {
    _teardown();
    muted = false;
    speaker = false;
    connectedAt = null;
    endReason = null;
    peerPhone = null;
  }

  void _setIce(dynamic servers) {
    if (servers is List && servers.isNotEmpty) {
      _iceServers = servers.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
  }

  bool _micDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('permission') || s.contains('notallowed') || s.contains('denied');
  }

  Future<void> _ring(bool on) async {
    try {
      if (on) {
        await _ringer.setReleaseMode(ReleaseMode.loop);
        await _ringer.play(AssetSource('sounds/call_ringtone.wav'), volume: 1.0);
      } else {
        await _ringer.stop();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _emitAck(String event, Map<String, dynamic> data) {
    final done = Completer<Map<String, dynamic>?>();
    SocketService.emit(event, data, (res) {
      if (done.isCompleted) return;
      done.complete(res is Map ? Map<String, dynamic>.from(res) : null);
    });
    return done.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  void _openScreen() {
    final nav = NavService.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const CallScreen()));
  }
}
