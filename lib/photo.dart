import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// সর্বোচ্চ ছবির সাইজ (বাইট) — ১০০ KB।
const maxPhotoBytes = 100 * 1024;

/// ছবি তুলে/বাছাই করে ১০০ KB-র নিচে নামা পর্যন্ত কোয়ালিটি ও মাপ কমিয়ে
/// কম্প্রেস করে রাখে। মোবাইলে অ্যাপের নিজস্ব ফোল্ডারে ফাইল হিসেবে,
/// ওয়েবে base64 data URI হিসেবে ডাটাবেসেই। বাতিল করলে null।
Future<String?> pickCompressedPhoto(ImageSource source) async {
  final original = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1280,
    maxHeight: 1280,
    preferredCameraDevice: CameraDevice.rear,
  );
  if (original == null) return null;
  final picked = await compute(_shrink, await original.readAsBytes());

  if (kIsWeb) {
    return 'data:image/jpeg;base64,${base64Encode(picked)}';
  }

  return _saveBytes(picked);
}

Future<String> _saveBytes(List<int> bytes) async {
  final dir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'photos'),
  );
  await dir.create(recursive: true);
  final dest = p.join(
    dir.path,
    'c_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await File(dest).writeAsBytes(bytes);
  return dest;
}

/// সার্ভারে পাঠানোর জন্য ছবি data URI-তে (ছবি না থাকলে বা ফাইল হারালে খালি)।
Future<String> photoToData(String photo) async {
  if (photo.isEmpty || photo.startsWith('data:')) return photo;
  try {
    final f = File(photo);
    if (!await f.exists()) return '';
    return 'data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}';
  } catch (_) {
    return '';
  }
}

/// সার্ভার থেকে আসা data URI লোকাল ফাইলে রাখে (ওয়েবে data URI-ই থাকে)।
Future<String> photoFromData(String data) async {
  if (kIsWeb || !data.startsWith('data:')) return data;
  try {
    return await _saveBytes(
      base64Decode(data.substring(data.indexOf(',') + 1)),
    );
  } catch (_) {
    return '';
  }
}

/// সেভ করা ছবির ImageProvider (ফাইল পাথ বা data URI)।
ImageProvider photoProvider(String photo) {
  if (photo.startsWith('data:')) {
    return MemoryImage(base64Decode(photo.substring(photo.indexOf(',') + 1)));
  }
  return FileImage(File(photo));
}

Future<void> deletePhoto(String path) async {
  if (kIsWeb || path.startsWith('data:')) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// JPEG [maxPhotoBytes]-এর নিচে না নামা পর্যন্ত আগে কোয়ালিটি, তারপর মাপ কমায়।
Uint8List _shrink(Uint8List src) {
  var image = img.bakeOrientation(img.decodeImage(src)!);
  const longSide = 640;
  if (image.width > longSide || image.height > longSide) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? longSide : null,
      height: image.height > image.width ? longSide : null,
    );
  }
  while (true) {
    for (var q = 85; q >= 35; q -= 10) {
      final out = img.encodeJpg(image, quality: q);
      if (out.length <= maxPhotoBytes) return out;
    }
    image = img.copyResize(
      image,
      width: (image.width * 0.8).round(),
      interpolation: img.Interpolation.average,
    );
  }
}
