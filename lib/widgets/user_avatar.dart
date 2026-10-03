import 'package:flutter/material.dart';

import '../main.dart' show kAccent;
import '../services/cloudinary_service.dart';

/// Round profile picture with initials fallback.
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;

  const UserAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.size = 52,
  });

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _fallback() => Container(
        color: kAccent,
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.36,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasPhoto = url != null && url.isNotEmpty;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                CloudinaryService.avatarUrl(url, size: (size * 3).round()),
                key: ValueKey(url),
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _fallback(),
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }
}