import 'package:flutter/foundation.dart';

/// সার্ভারের ঠিকানা। আসল ফোনে/প্রোডাকশনে বিল্ডের সময় দিন:
///   flutter run --dart-define=API_URL=https://your-server.example.com
const _env = String.fromEnvironment('API_URL');

/// রিলিজ বিল্ডের ডিফল্ট সার্ভার।
const _prodUrl = 'https://baki-khata-api-silk.vercel.app';

String get apiBase {
  if (_env.isNotEmpty) return _env;
  if (kReleaseMode) return _prodUrl;
  // অ্যান্ড্রয়েড এমুলেটরে কম্পিউটারের localhost হলো 10.0.2.2।
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8080';
  }
  return 'http://localhost:8080';
}
