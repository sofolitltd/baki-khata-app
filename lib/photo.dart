import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ছবি তুলে/বাছাই করে ৪৮০px আর ৭০% JPEG কোয়ালিটিতে কম্প্রেস করে রাখে
/// (সাধারণত ২০–৬০ KB)। মোবাইলে অ্যাপের নিজস্ব ফোল্ডারে ফাইল হিসেবে,
/// ওয়েবে base64 data URI হিসেবে ডাটাবেসেই। বাতিল করলে null।
Future<String?> pickCompressedPhoto(ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 480,
    maxHeight: 480,
    imageQuality: 70,
    preferredCameraDevice: CameraDevice.rear,
  );
  if (picked == null) return null;

  if (kIsWeb) {
    final bytes = await picked.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  final dir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'photos'),
  );
  await dir.create(recursive: true);
  final dest = p.join(
    dir.path,
    'c_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await File(picked.path).copy(dest);
  return dest;
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
