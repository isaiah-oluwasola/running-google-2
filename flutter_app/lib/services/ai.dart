import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

class AiService {
  AiService._();

  /// Generates an image from a text prompt (FLUX via the HeyApp image worker).
  static Future<Uint8List> generateImage(String prompt) async {
    final res = await http.post(
      Uri.parse(AppConfig.imageEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppConfig.imageApiToken}',
      },
      body: jsonEncode({'prompt': prompt, 'model': AppConfig.imageModel}),
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List?;
    final b64 = (list != null && list.isNotEmpty) ? list[0]['b64_json'] as String? : null;
    if (b64 == null) throw Exception('No image data received');
    return base64Decode(b64);
  }

  /// Free translate endpoint used by the web app (Google gtx client).
  static Future<String> translate(String text, String targetLang) async {
    final uri = Uri.parse(AppConfig.translateEndpoint).replace(queryParameters: {
      'client': 'gtx',
      'sl': 'auto',
      'tl': targetLang,
      'dt': 't',
      'q': text,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    final segments = (data.isNotEmpty ? data[0] as List? : null) ?? [];
    final out = segments.map((s) => (s as List).isNotEmpty ? (s[0] as String? ?? '') : '').join();
    return out.isEmpty ? text : out;
  }
}
