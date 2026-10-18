/// Backend configuration. Same Supabase project and Firebase project as index.html.
class AppConfig {
  static const supabaseUrl = 'https://pgjxbcsircqtkmzdafhy.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBnanhiY3NpcmNxdGttemRhZmh5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYxMTE2MTEsImV4cCI6MjEwMTY4NzYxMX0.6M-ArErI354xaMhcKXUyBbolUhfQfMmEWg_dzMpNwmI';

  static const translateEndpoint = 'https://translate.googleapis.com/translate_a/single';

  static const imageEndpoint = 'https://sahi-api.tunixcompanyyoung-f0f.workers.dev';
  static const imageModel = '@cf/black-forest-labs/flux-1-schnell';
  // Supplied at build time so the secret is not hard-coded in source:
  //   flutter build apk --dart-define=IMAGE_API_TOKEN=...
  static const imageApiToken = String.fromEnvironment('IMAGE_API_TOKEN');

  // Required only for Sign in with Apple on Android (Apple web flow).
  static const appleServiceId = String.fromEnvironment('APPLE_SERVICE_ID');
  static const appleRedirectUri = String.fromEnvironment('APPLE_REDIRECT_URI');

  static const List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  static const callRingTimeout = Duration(seconds: 35);
}

const translateLanguages = <List<String>>[
  ['', 'Off'], ['en', 'English'], ['es', 'Spanish'], ['fr', 'French'], ['de', 'German'],
  ['pt', 'Portuguese'], ['ar', 'Arabic'], ['hi', 'Hindi'], ['zh-CN', 'Chinese'], ['ja', 'Japanese'],
  ['ko', 'Korean'], ['ru', 'Russian'], ['it', 'Italian'], ['tr', 'Turkish'], ['sw', 'Swahili'],
  ['yo', 'Yoruba'], ['ig', 'Igbo'], ['ha', 'Hausa'],
];
