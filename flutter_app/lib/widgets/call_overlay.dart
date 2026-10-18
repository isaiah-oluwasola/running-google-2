import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/calls.dart';
import '../theme.dart';

/// Full-screen call UI shown above any screen while a call is active
/// (index.html #call-screen).
class CallOverlay extends StatefulWidget {
  const CallOverlay({super.key});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _statusText(ActiveCall call) {
    switch (call.status) {
      case CallStatus.dialing:
        return call.isVideo ? 'Video calling…' : 'Calling…';
      case CallStatus.ringing:
        return call.isVideo ? 'Incoming video call…' : 'Incoming call…';
      case CallStatus.connecting:
        return 'Connecting…';
      case CallStatus.connected:
        final secs = DateTime.now().difference(call.startedAt ?? DateTime.now()).inSeconds;
        final m = (secs ~/ 60).toString().padLeft(2, '0');
        final s = (secs % 60).toString().padLeft(2, '0');
        return '$m:$s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CallService.instance,
      builder: (context, _) {
        final call = CallService.instance.active;
        if (call == null) return const SizedBox.shrink();
        final service = CallService.instance;
        final showVideo = call.isVideo && call.status == CallStatus.connected;

        return Material(
          color: Colors.black,
          child: Stack(
            children: [
              if (showVideo)
                Positioned.fill(child: RTCVideoView(call.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
              else
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF0B1118),
                    alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AppColors.accentDark,
                        child: Text(call.peerName.isNotEmpty ? call.peerName[0].toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 36, color: AppColors.onAccent)),
                      ),
                      const SizedBox(height: 16),
                      Text(call.peerName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              if (showVideo)
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Text(call.peerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              Positioned(
                top: 100,
                left: 0,
                right: 0,
                child: Text(_statusText(call),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: call.status == CallStatus.connected ? AppColors.accent : Colors.white70, fontSize: 15)),
              ),
              if (call.isVideo && call.localStream != null && !call.cameraOff)
                Positioned(
                  right: 16,
                  bottom: 140,
                  width: 110,
                  height: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: RTCVideoView(call.localRenderer, mirror: call.facingMode == 'user'),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: call.incoming && call.status == CallStatus.ringing
                    ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _roundButton(Icons.call_end, AppColors.danger, 'Decline', service.endCall),
                        _roundButton(Icons.call, AppColors.accent, 'Accept', service.acceptCall, fg: AppColors.onAccent),
                      ])
                    : Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 18,
                        runSpacing: 14,
                        children: [
                          _roundButton(
                            call.speakerOn ? Icons.volume_up : Icons.hearing,
                            Colors.white24,
                            'Speaker',
                            service.toggleSpeaker,
                          ),
                          _roundButton(
                            call.isVideo ? (call.cameraOff ? Icons.videocam_off : Icons.videocam) : Icons.video_call,
                            Colors.white24,
                            call.isVideo ? 'Camera' : 'Turn on video',
                            call.isVideo ? service.toggleCamera : service.upgradeToVideo,
                          ),
                          _roundButton(
                            call.muted ? Icons.mic_off : Icons.mic,
                            Colors.white24,
                            'Mute',
                            service.toggleMute,
                          ),
                          if (call.isVideo)
                            _roundButton(Icons.cameraswitch, Colors.white24, 'Flip', service.switchCamera),
                          _roundButton(Icons.call_end, AppColors.danger, 'End', service.endCall),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _roundButton(IconData icon, Color color, String label, VoidCallback onTap, {Color fg = Colors.white}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(18), child: Icon(icon, color: fg, size: 26)),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]);
  }
}
