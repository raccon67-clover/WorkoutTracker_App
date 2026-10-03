import 'dart:async';
import 'package:flutter/material.dart';
import '../data/exercise_catalog.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import '../services/exercise_library_service.dart';

class ExerciseLibraryPage extends StatefulWidget {
  final ValueChanged<List<CatalogExercise>>? onAddToLog;
  const ExerciseLibraryPage({super.key, this.onAddToLog});

  @override
  State<ExerciseLibraryPage> createState() => _ExerciseLibraryPageState();
}

class _ExerciseLibraryPageState extends State<ExerciseLibraryPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<RemoteExercise> _remote = [];
  List<CatalogExercise> _local = [];
  bool _loading = true;
  String _query = '';
  final Set<CatalogExercise> _selected = {};
  static const _templates = <_WorkoutTemplate>[
    _WorkoutTemplate('Beginner Full Body', ['Bodyweight Squat', 'Push-Up', 'Glute Bridge', 'Plank', 'Jumping Jacks']),
    _WorkoutTemplate('Upper Body Basics', ['Push-Up', 'Dumbbell Row', 'Bicep Curl', 'Pike Push-Up', 'Plank']),
    _WorkoutTemplate('Lower Body Basics', ['Bodyweight Squat', 'Walking Lunge', 'Glute Bridge', 'Calf Raise', 'Wall Sit']),
    _WorkoutTemplate('Quick No-Equipment', ['Jumping Jacks', 'Bodyweight Squat', 'Push-Up', 'Mountain Climber', 'Plank']),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _controller.addListener(_onSearchChanged);
  }

  Future<void> _load() async {
    try {
      final data = await ExerciseLibraryService.instance.load();
      if (!mounted) return;
      setState(() { _remote = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Online exercise library unavailable. Showing built-in exercises.')),
      );
    }
    _filter();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _filter);
  }

  void _filter() {
    final q = _controller.text.trim();
    _query = q;
    final local = ExerciseCatalog.search(query: q);
    final remote = _remote.where((e) {
      if (q.isEmpty) return true;
      final hay = '${e.name} ${e.bodyPart} ${e.equipment} ${e.primaryMuscles.join(' ')}'.toLowerCase();
      return hay.contains(q.toLowerCase());
    }).take(30).toList();
    if (mounted) setState(() { _local = local.take(30).toList(); });
    if (mounted && _remote.isNotEmpty) setState(() {});
    _filteredRemote = remote;
  }

  List<RemoteExercise> _filteredRemote = [];

  CatalogExercise? _catalogFor(RemoteExercise r) {
    final exact = ExerciseCatalog.byName(r.name);
    if (exact != null) return exact;
    final matches = ExerciseCatalog.search(query: r.name);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onSearchChanged);
    _controller.dispose();
    super.dispose();
  }

  void _toggle(CatalogExercise c) {
    setState(() {
      if (!_selected.add(c)) _selected.remove(c);
    });
  }

  void _addSelected() {
    if (_selected.isEmpty) return;
    final selected = _selected.toList();
    if (widget.onAddToLog != null) {
      widget.onAddToLog!(selected);
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, selected);
  }

  void _openDetails(RemoteExercise? remote, CatalogExercise c) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseInfoPage(catalog: c, remote: remote)));
  }

  @override
  Widget build(BuildContext context) {
    final showRemote = _filteredRemote.where((r) => _catalogFor(r) != null).toList();
    final matchingTemplates = _templates.where((t) {
      if (_query.isEmpty) return true;
      final hay = '${t.name} ${t.exerciseNames.join(' ')}'.toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Exercise Library'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton.icon(onPressed: _addSelected, icon: const Icon(Icons.add), label: Text('${_selected.length} to log')),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search exercises, muscles, equipment...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty ? null : IconButton(onPressed: _controller.clear, icon: const Icon(Icons.clear)),
            ),
          ),
        ),
        if (_selected.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: Text('${_selected.length} exercise${_selected.length == 1 ? '' : 's'} selected', style: const TextStyle(fontWeight: FontWeight.w700))),
              ElevatedButton(onPressed: _addSelected, child: const Text('Add to Log')),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kAccent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                  children: [
                    if (matchingTemplates.isNotEmpty) ...[
                      _heading('Workouts'),
                      ...matchingTemplates.map(_templateCard),
                    ],
                    if (showRemote.isNotEmpty) ...[
                      _heading('Exercise Guide'),
                      ...showRemote.map((r) {
                        final c = _catalogFor(r)!;
                        return _remoteCard(r, c);
                      }),
                    ],
                    if (_local.isNotEmpty) ...[
                      _heading(_remote.isNotEmpty ? 'More exercises' : 'Exercises'),
                      ..._local.map((c) => _localCard(c)),
                    ],
                    if (showRemote.isEmpty && _local.isEmpty)
                      const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No exercises found.', style: TextStyle(color: Colors.grey)))),
                    const SizedBox(height: 20),
                    const Text('Exercise data by RepDB (repdb.co)', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
    child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
  );

  Widget _templateCard(_WorkoutTemplate t) {
    final exercises = t.exerciseNames
        .map(ExerciseCatalog.byName)
        .whereType<CatalogExercise>()
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: kAccent.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.fitness_center_rounded, color: kAccent)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${exercises.length} exercises · ${t.exerciseNames.join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ])),
        IconButton(onPressed: exercises.isEmpty ? null : () { setState(() { _selected.addAll(exercises); }); }, icon: const Icon(Icons.add_circle_outline, color: Colors.white70)),
      ]),
    );
  }

  Widget _remoteCard(RemoteExercise r, CatalogExercise c) {
    final image = ExerciseLibraryService.instance.imageUrl(r.imageStart);
    return _exerciseTile(
      c,
      title: r.name,
      subtitle: '${_title(r.bodyPart)} · ${_title(r.difficulty)} · ${_title(r.equipment)}',
      imageUrl: image,
      onInfo: () => _openDetails(r, c),
    );
  }

  Widget _localCard(CatalogExercise c) {
    final slug = c.name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-').replaceAll(RegExp(r'^-|-$'), '');
    return _exerciseTile(c, title: c.name, subtitle: c.subtitle, imageUrl: 'https://exercise-dataset.com/images/flat/$slug-start.webp', onInfo: () => _openDetails(null, c));
  }

  Widget _exerciseTile(CatalogExercise c, {required String title, required String subtitle, required String imageUrl, required VoidCallback onInfo}) {
    final selected = _selected.contains(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(imageUrl, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: Colors.black26, child: const Icon(Icons.fitness_center, color: Colors.grey))),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: onInfo, icon: const Icon(Icons.info_outline, color: Colors.white70)),
          IconButton(onPressed: () => _toggle(c), icon: Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: selected ? kAccent : Colors.white70)),
        ]),
      ),
    );
  }

  String _title(String value) => value.replaceAll('_', ' ').split(' ').map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
}

class ExerciseInfoPage extends StatelessWidget {
  final CatalogExercise catalog;
  final RemoteExercise? remote;
  const ExerciseInfoPage({super.key, required this.catalog, required this.remote});

  @override
  Widget build(BuildContext context) {
    final localImage = 'https://exercise-dataset.com/images/flat/${catalog.name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-')}-start.webp';
    final image = remote == null ? ExerciseLibraryService.instance.imageUrl(localImage) : ExerciseLibraryService.instance.imageUrl(remote!.imageStart);
    final instructions = remote?.instructions ?? _fallbackInstructions(catalog);
    final tips = remote?.tips ?? const <String>[];
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: Text(catalog.name)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        ClipRRect(borderRadius: BorderRadius.circular(20), child: AspectRatio(aspectRatio: 1.2, child: Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: kSurface, child: const Icon(Icons.fitness_center, size: 70, color: Colors.grey))))),
        const SizedBox(height: 18),
        Text(catalog.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(catalog.subtitle, style: TextStyle(color: Colors.grey[500])),
        if (remote?.description.isNotEmpty == true) ...[const SizedBox(height: 14), Text(remote!.description, style: TextStyle(color: Colors.grey[300], height: 1.45))],
        const SizedBox(height: 22),
        const Text('HOW TO DO IT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .7)),
        const SizedBox(height: 10),
        ...List.generate(instructions.length, (i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(radius: 13, backgroundColor: kAccent, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white))), const SizedBox(width: 12), Expanded(child: Text(instructions[i], style: TextStyle(color: Colors.grey[300], height: 1.4)))]))),
        if (tips.isNotEmpty) ...[const SizedBox(height: 10), const Text('FORM TIPS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .7)), const SizedBox(height: 10), ...tips.map((t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  ', style: TextStyle(color: kAccent)), Expanded(child: Text(t, style: TextStyle(color: Colors.grey[300])))])))],
        const SizedBox(height: 26),
        ElevatedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.check), label: const Text('Got it')),
        const SizedBox(height: 14),
        const Text('Exercise data by RepDB (repdb.co)', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
      ]),
    );
  }

  List<String> _fallbackInstructions(CatalogExercise c) {
    switch (c.name) {
      case 'Push-Up': case 'Pushups':
        return ['Start in a comfortable plank position with hands under or slightly wider than your shoulders.', 'Keep your body aligned and lower yourself in a controlled way.', 'Press through your hands to return to the starting position.'];
      case 'Squat': case 'Bodyweight Squat':
        return ['Stand with your feet in a comfortable stance.', 'Bend your hips and knees while keeping your torso controlled.', 'Press through your feet to return to standing.'];
      case 'Plank':
        return ['Set up on your forearms or hands with your body aligned.', 'Brace your core and keep your hips controlled.', 'Hold the position while breathing steadily.'];
      default:
        return ['Use a controlled range of motion and a comfortable pace.', 'Keep your body stable and avoid forcing a painful movement.', 'Stop if something feels painful or unusual and ask a qualified adult or professional for guidance.'];
    }
  }
}


class _WorkoutTemplate {
  final String name;
  final List<String> exerciseNames;
  const _WorkoutTemplate(this.name, this.exerciseNames);
}
