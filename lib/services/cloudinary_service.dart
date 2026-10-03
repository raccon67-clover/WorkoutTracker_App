import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Uploads images to Cloudinary with an UNSIGNED upload preset.
/// Never put your Cloudinary API secret in the app.
class CloudinaryService {
  CloudinaryService._();
  static final instance = CloudinaryService._();

  // Defaults are your real values, so no --dart-define is needed.
  static const cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'xrzvzq0i',
  );
  static const uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'workout_profile_preset',
  );

  bool get isConfigured =>
      cloudName.isNotEmpty &&
      !cloudName.startsWith('YOUR_') &&
      uploadPreset.isNotEmpty &&
      !uploadPreset.startsWith('YOUR_');

  /// Serves any public image URL through Cloudinary, auto-optimised.
  String deliveryUrl(String sourceUrl) {
    if (!isConfigured || sourceUrl.isEmpty) return sourceUrl;
    final encoded = Uri.encodeFull(sourceUrl);
    return 'https://res.cloudinary.com/$cloudName/image/fetch/f_auto,q_auto/$encoded';
  }

  /// Generic upload. [folder] decides where the image is stored.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  }) async {
    if (!isConfigured) {
      throw StateError('Cloudinary is not configured.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
    )
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );

    final response =
        await request.send().timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      if (decoded is Map && decoded['error'] is Map) {
        message = decoded['error']['message']?.toString();
      }
      throw Exception(message ?? 'Cloudinary upload failed.');
    }

    final url = (decoded is Map) ? decoded['secure_url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw Exception('Cloudinary did not return an image URL.');
    }
    return url;
  }

  /// Used by ProfileAvatarPicker.
  static Future<String> uploadProfileImage(XFile file) async {
    return instance.uploadImage(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      folder: 'workout_tracker/profiles',
    );
  }

  /// Small face-cropped square version of an uploaded image.
  static String avatarUrl(String url, {int size = 300}) {
    const marker = '/upload/';
    final i = url.indexOf(marker);
    if (i == -1) return url;
    return url.replaceFirst(
      marker,
      '${marker}c_fill,g_face,w_$size,h_$size,q_auto,f_auto/',
    );
  }
}