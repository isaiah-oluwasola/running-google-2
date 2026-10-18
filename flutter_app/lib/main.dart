import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF10151D),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF10151D),
    ),
  );
  runApp(const HeyAppApp());
}

class HeyAppApp extends StatelessWidget {
  const HeyAppApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeyApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E13),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF22D47B)),
        useMaterial3: true,
      ),
      home: const HeyAppWebView(),
    );
  }
}

/// Full-screen WebView that serves the bundled HeyApp web app (index.html).
class HeyAppWebView extends StatefulWidget {
  const HeyAppWebView({super.key});

  @override
  State<HeyAppWebView> createState() => _HeyAppWebViewState();
}

class _HeyAppWebViewState extends State<HeyAppWebView> {
  InAppWebViewController? _controller;
  double _progress = 0;

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true, // localStorage is used for theme/session data
    databaseEnabled: true,
    mediaPlaybackRequiresUserGesture: false, // ringtones / call audio
    allowsInlineMediaPlayback: true,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    transparentBackground: false,
  );

  /// Grants camera / microphone to the page only when the user has allowed
  /// them at the OS level (needed for WebRTC audio and video calls).
  Future<PermissionResponse> _onPermissionRequest(
    InAppWebViewController controller,
    PermissionRequest request,
  ) async {
    final wanted = <Permission>[];
    for (final resource in request.resources) {
      if (resource == PermissionResourceType.CAMERA) wanted.add(Permission.camera);
      if (resource == PermissionResourceType.MICROPHONE) wanted.add(Permission.microphone);
    }

    if (wanted.isEmpty) {
      return PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.GRANT,
      );
    }

    final statuses = await wanted.request();
    final allGranted = statuses.values.every((s) => s.isGranted);
    return PermissionResponse(
      resources: request.resources,
      action: allGranted
          ? PermissionResponseAction.GRANT
          : PermissionResponseAction.DENY,
    );
  }

  Future<void> _onBackPressed(bool didPop) async {
    if (didPop) return;
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBackPressed(didPop),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialFile: 'assets/web/index.html',
                initialSettings: _settings,
                onWebViewCreated: (controller) => _controller = controller,
                onProgressChanged: (_, progress) =>
                    setState(() => _progress = progress / 100),
                onPermissionRequest: _onPermissionRequest,
                onGeolocationPermissionsShowPrompt: (controller, origin) async =>
                    GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: false,
                  retain: false,
                ),
              ),
              if (_progress < 1.0)
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 2,
                  color: const Color(0xFF22D47B),
                  backgroundColor: Colors.transparent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
