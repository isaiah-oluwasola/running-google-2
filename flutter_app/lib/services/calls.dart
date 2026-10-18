import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'backend.dart';

enum CallStatus { dialing, ringing, connecting, connected }

/// One active 1:1 call. Signalling runs over Supabase broadcast on user-<id>
/// channels, exactly like index.html, so web and app users can call each other.
class ActiveCall {
  final String callId;
  final String peerId;
  final String peerName;
  final bool incoming;
  String callType; // 'audio' | 'video'
  CallStatus status;

  MediaStream? localStream;
  RTCPeerConnection? pc;
  RealtimeChannel? peerChannel;
  Map<String, dynamic>? remoteOffer;
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteDescriptionSet = false;

  DateTime? startedAt;
  bool muted = false;
  bool cameraOff = false;
  bool speakerOn = true;
  String facingMode = 'user';
  Timer? ringTimer;
  Timer? ticker;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  ActiveCall({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.incoming,
    required this.callType,
    required this.status,
  });

  bool get isVideo => callType == 'video';
}

class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();

  ActiveCall? active;
  RealtimeChannel? _myChannel;
  String? _myId;
  String? _myName;

  // ----- signalling channel for incoming calls -----

  void listen(String myId, String myName) {
    stopListening();
    _myId = myId;
    _myName = myName;
    _myChannel = Backend.db.channel('user-$myId').onBroadcast(
      event: 'call-signal',
      callback: (payload) => _handleSignal(Map<String, dynamic>.from(payload)),
    );
    _myChannel!.subscribe();
  }

  void stopListening() {
    final ch = _myChannel;
    if (ch != null) Backend.db.removeChannel(ch);
    _myChannel = null;
  }

  Future<RealtimeChannel> _openPeerChannel(String peerId) async {
    final ch = Backend.db.channel('user-$peerId');
    final done = Completer<void>();
    ch.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed && !done.isCompleted) done.complete();
      if (status == RealtimeSubscribeStatus.channelError && !done.isCompleted) {
        done.completeError(error ?? 'channel error');
      }
    });
    await done.future.timeout(const Duration(seconds: 10));
    return ch;
  }

  void _send(RealtimeChannel? ch, Map<String, dynamic> payload) {
    ch?.sendBroadcastMessage(event: 'call-signal', payload: payload);
  }

  Future<void> _oneOff(String peerId, Map<String, dynamic> payload) async {
    try {
      final ch = await _openPeerChannel(peerId);
      _send(ch, payload);
      Future.delayed(const Duration(milliseconds: 1500), () => Backend.db.removeChannel(ch));
    } catch (_) {}
  }

  // ----- outgoing -----

  /// Starts a call. Returns an error message, or null on success.
  Future<String?> startCall({required Profile peer, required bool video}) async {
    if (active != null) return "You're already on a call";
    final myId = _myId;
    final myName = _myName ?? 'User';
    if (myId == null) return 'Not signed in';

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
    final call = ActiveCall(
      callId: callId,
      peerId: peer.id,
      peerName: peer.name,
      incoming: false,
      callType: video ? 'video' : 'audio',
      status: CallStatus.dialing,
    );
    active = call;
    notifyListeners();

    try {
      await _acquireMedia(call, video: video);
      final pc = await _createPeer(call);
      call.pc = pc;
      for (final track in call.localStream!.getTracks()) {
        await pc.addTrack(track, call.localStream!);
      }

      call.peerChannel = await _openPeerChannel(peer.id);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _send(call.peerChannel, {
        'type': 'offer',
        'callId': callId,
        'from': myId,
        'fromName': myName,
        'callType': call.callType,
        'sdp': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (e) {
      await _cleanup();
      return "Couldn't start the call";
    }

    call.ringTimer = Timer(AppConfig.callRingTimeout, () {
      if (active?.callId == callId && active?.status == CallStatus.dialing) {
        _oneOff(peer.id, {'type': 'cancel', 'callId': callId, 'from': myId});
        _cleanup();
      }
    });
    return null;
  }

  // ----- incoming -----

  void _handleSignal(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'offer':
        _onIncomingOffer(data);
        break;
      case 'answer':
        _onAnswer(data);
        break;
      case 'ice':
        _onIce(data);
        break;
      case 'end':
      case 'reject':
      case 'busy':
      case 'cancel':
        if (active?.callId == data['callId']) _cleanup();
        break;
      case 'upgrade-offer':
        _onUpgradeOffer(data);
        break;
      case 'upgrade-answer':
        _onUpgradeAnswer(data);
        break;
    }
  }

  void _onIncomingOffer(Map<String, dynamic> data) {
    final from = data['from'] as String;
    if (active != null) {
      _oneOff(from, {'type': 'busy', 'callId': data['callId'], 'from': _myId});
      return;
    }
    final call = ActiveCall(
      callId: data['callId'] as String,
      peerId: from,
      peerName: (data['fromName'] as String?) ?? 'User',
      incoming: true,
      callType: data['callType'] == 'video' ? 'video' : 'audio',
      status: CallStatus.ringing,
    );
    call.remoteOffer = Map<String, dynamic>.from(data['sdp'] as Map);
    active = call;
    notifyListeners();
    call.ringTimer = Timer(AppConfig.callRingTimeout, () {
      if (active?.callId == call.callId && active?.status == CallStatus.ringing) _cleanup();
    });
  }

  /// Called when the user taps Accept.
  Future<void> acceptCall() async {
    final call = active;
    if (call == null || !call.incoming) return;
    call.ringTimer?.cancel();
    call.status = CallStatus.connecting;
    notifyListeners();
    try {
      await _acquireMedia(call, video: call.isVideo);
      final pc = await _createPeer(call);
      call.pc = pc;
      for (final track in call.localStream!.getTracks()) {
        await pc.addTrack(track, call.localStream!);
      }
      await pc.setRemoteDescription(RTCSessionDescription(call.remoteOffer!['sdp'], call.remoteOffer!['type']));
      call.remoteDescriptionSet = true;
      await _flushIce(call);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      call.peerChannel = await _openPeerChannel(call.peerId);
      _send(call.peerChannel, {
        'type': 'answer',
        'callId': call.callId,
        'from': _myId,
        'sdp': {'sdp': answer.sdp, 'type': answer.type},
      });
      notifyListeners();
    } catch (e) {
      await _oneOff(call.peerId, {'type': 'end', 'callId': call.callId, 'from': _myId});
      await _cleanup();
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    final call = active;
    if (call == null || call.callId != data['callId'] || call.pc == null) return;
    call.ringTimer?.cancel();
    call.status = CallStatus.connecting;
    notifyListeners();
    final sdp = Map<String, dynamic>.from(data['sdp'] as Map);
    try {
      await call.pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
      call.remoteDescriptionSet = true;
      await _flushIce(call);
    } catch (_) {}
  }

  void _onIce(Map<String, dynamic> data) {
    final call = active;
    if (call == null || call.callId != data['callId']) return;
    final c = Map<String, dynamic>.from(data['candidate'] as Map);
    final candidate = RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      c['sdpMLineIndex'] as int?,
    );
    if (call.pc != null && call.remoteDescriptionSet) {
      call.pc!.addCandidate(candidate);
    } else {
      call.pendingIce.add(candidate);
    }
  }

  Future<void> _flushIce(ActiveCall call) async {
    for (final c in call.pendingIce) {
      await call.pc?.addCandidate(c);
    }
    call.pendingIce.clear();
  }

  // ----- actions during/after a call -----

  Future<void> endCall() async {
    final call = active;
    if (call == null) return;
    if (call.status == CallStatus.connected || call.status == CallStatus.connecting) {
      await _oneOff(call.peerId, {'type': 'end', 'callId': call.callId, 'from': _myId});
    } else if (!call.incoming && call.status == CallStatus.dialing) {
      await _oneOff(call.peerId, {'type': 'cancel', 'callId': call.callId, 'from': _myId});
    } else if (call.incoming && call.status == CallStatus.ringing) {
      await _oneOff(call.peerId, {'type': 'reject', 'callId': call.callId, 'from': _myId});
    }
    await _cleanup();
  }

  void toggleMute() {
    final call = active;
    if (call?.localStream == null) return;
    call!.muted = !call.muted;
    for (final t in call.localStream!.getAudioTracks()) {
      t.enabled = !call.muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    final call = active;
    if (call?.localStream == null || !call!.isVideo) return;
    call.cameraOff = !call.cameraOff;
    for (final t in call.localStream!.getVideoTracks()) {
      t.enabled = !call.cameraOff;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    final call = active;
    if (call == null) return;
    call.speakerOn = !call.speakerOn;
    try {
      await Helper.setSpeakerphoneOn(call.speakerOn);
    } catch (_) {}
    notifyListeners();
  }

  /// Turns the camera on mid-call (audio -> video) and renegotiates.
  Future<void> upgradeToVideo() async {
    final call = active;
    if (call == null || call.isVideo || call.pc == null) return;
    try {
      final cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': call.facingMode},
      });
      final track = cam.getVideoTracks().first;
      call.localStream?.addTrack(track);
      await call.pc!.addTrack(track, call.localStream!);
      call.callType = 'video';
      final offer = await call.pc!.createOffer();
      await call.pc!.setLocalDescription(offer);
      _send(call.peerChannel, {
        'type': 'upgrade-offer',
        'callId': call.callId,
        'from': _myId,
        'sdp': {'sdp': offer.sdp, 'type': offer.type},
      });
      notifyListeners();
    } catch (_) {}
  }

  Future<void> switchCamera() async {
    final call = active;
    if (call?.pc == null || !call!.isVideo || call.cameraOff) return;
    final newFacing = call.facingMode == 'user' ? 'environment' : 'user';
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': newFacing},
      });
      final newTrack = stream.getVideoTracks().first;
      final senders = await call.pc!.getSenders();
      for (final s in senders) {
        if (s.track?.kind == 'video') await s.replaceTrack(newTrack);
      }
      final oldTracks = call.localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
      final old = oldTracks.isEmpty ? null : oldTracks.first;
      if (old != null) {
        call.localStream!.removeTrack(old);
        await old.stop();
      }
      call.localStream?.addTrack(newTrack);
      call.facingMode = newFacing;
      call.localRenderer.srcObject = call.localStream;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _onUpgradeOffer(Map<String, dynamic> data) async {
    final call = active;
    if (call?.pc == null || call!.callId != data['callId']) return;
    final sdp = Map<String, dynamic>.from(data['sdp'] as Map);
    try {
      await call.pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
      final answer = await call.pc!.createAnswer();
      await call.pc!.setLocalDescription(answer);
      _send(call.peerChannel, {
        'type': 'upgrade-answer',
        'callId': call.callId,
        'from': _myId,
        'sdp': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (_) {}
  }

  Future<void> _onUpgradeAnswer(Map<String, dynamic> data) async {
    final call = active;
    if (call?.pc == null || call!.callId != data['callId']) return;
    final sdp = Map<String, dynamic>.from(data['sdp'] as Map);
    try {
      await call.pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
    } catch (_) {}
  }

  // ----- media and peer connection helpers -----

  Future<void> _acquireMedia(ActiveCall call, {required bool video}) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) throw Exception('Microphone permission denied');
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        call.callType = 'audio';
      }
    }
    final wantVideo = video && call.callType == 'video';
    try {
      call.localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': wantVideo ? {'facingMode': call.facingMode} : false,
      });
    } catch (_) {
      call.callType = 'audio';
      call.localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    }
    await call.localRenderer.initialize();
    await call.remoteRenderer.initialize();
    call.localRenderer.srcObject = call.isVideo ? call.localStream : null;
  }

  Future<RTCPeerConnection> _createPeer(ActiveCall call) async {
    final pc = await createPeerConnection({'iceServers': AppConfig.iceServers});
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || call.peerChannel == null) return;
      _send(call.peerChannel, {
        'type': 'ice',
        'callId': call.callId,
        'from': _myId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      call.remoteRenderer.srcObject = event.streams[0];
      if (event.streams[0].getVideoTracks().isNotEmpty) {
        call.callType = 'video';
      }
      notifyListeners();
    };
    pc.onConnectionState = (state) {
      if (active != call) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected && call.status != CallStatus.connected) {
        _onConnected(call);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _cleanup();
      }
    };
    return pc;
  }

  void _onConnected(ActiveCall call) {
    call.status = CallStatus.connected;
    call.startedAt = DateTime.now();
    call.ringTimer?.cancel();
    call.ticker?.cancel();
    call.ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  Future<void> _cleanup() async {
    final call = active;
    active = null;
    if (call != null) {
      call.ringTimer?.cancel();
      call.ticker?.cancel();
      for (final t in call.localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await call.localStream?.dispose();
      await call.pc?.close();
      final ch = call.peerChannel;
      if (ch != null) Backend.db.removeChannel(ch);
      await call.localRenderer.dispose();
      await call.remoteRenderer.dispose();
    }
    notifyListeners();
  }
}
