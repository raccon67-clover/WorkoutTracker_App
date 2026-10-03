import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cloudinary_service.dart';

class RemoteExercise {
  final String id;
  final String name;
  final String description;
  final List<String> instructions;
  final List<String> tips;
  final String difficulty;
  final String equipment;
  final String bodyPart;
  final List<String> primaryMuscles;
  final String? imageStart;
  final String? imagePeak;

  const RemoteExercise({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    required this.tips,
    required this.difficulty,
    required this.equipment,
    required this.bodyPart,
    required this.primaryMuscles,
    this.imageStart,
    this.imagePeak,
  });

  factory RemoteExercise.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    final flat = images?['flat'] as Map<String, dynamic>?;
    return RemoteExercise(
      id: '${j['id'] ?? ''}',
      name: '${j['name_en'] ?? ''}',
      description: '${j['description_en'] ?? ''}',
      instructions: List<String>.from(j['instructions_en'] ?? const []),
      tips: List<String>.from(j['tips_en'] ?? const []),
      difficulty: '${j['difficulty'] ?? 'beginner'}',
      equipment: '${j['equipment'] ?? 'Bodyweight'}',
      bodyPart: '${j['body_part'] ?? ''}',
      primaryMuscles: List<String>.from(j['primary_muscles'] ?? const []),
      imageStart: flat?['start']?.toString() ?? flat?['main']?.toString(),
      imagePeak: flat?['peak']?.toString(),
    );
  }
}

class ExerciseLibraryService {
  ExerciseLibraryService._();
  static final instance = ExerciseLibraryService._();

  static const _jsonUrl = 'https://exercise-dataset.com/exercises.json';
  static const _imageBase = 'https://exercise-dataset.com/';

  List<RemoteExercise>? _cache;
  Future<List<RemoteExercise>>? _loading;

  Future<List<RemoteExercise>> load() {
    if (_cache != null) return Future.value(_cache!);
    return _loading ??= _fetch();
  }

  Future<List<RemoteExercise>> _fetch() async {
    try {
      final response = await http.get(Uri.parse(_jsonUrl));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = root['exercises'] as List<dynamic>;
      _cache = raw
          .whereType<Map<String, dynamic>>()
          .map(RemoteExercise.fromJson)
          .where((e) => e.name.isNotEmpty)
          .toList();
      return _cache!;
    } finally {
      _loading = null;
    }
  }

  String imageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    final source = path.startsWith('http') ? path : '$_imageBase$path';
    return CloudinaryService.instance.deliveryUrl(source);
  }
}
