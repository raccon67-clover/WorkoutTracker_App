import 'package:flutter/material.dart';
import '../data/exercise_catalog.dart';
import '../services/database_service.dart';
import '../widgets/pill.dart';
import '../main.dart' show kBackground, kSurface, kAccent;


class ExercisePickerPage extends StatefulWidget {

  final Set<String> alreadyAdded;

  const ExercisePickerPage({super.key, this.alreadyAdded = const {}});

  @override
  State<ExercisePickerPage> createState() => _ExercisePickerPageState();
}

class _ExercisePickerPageState extends State<ExercisePickerPage> {
  static const _equipmentKey = 'log_equipment_filter';

  final _searchController = TextEditingController();
  final _focus = FocusNode();

  Set<Equipment> _equipment = {};
  Muscle? _muscle;
  final List<CatalogExercise> _selected = [];
  List<CatalogExercise> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadEquipment();
    _loadRecent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focus.dispose();
    super.dispose();
  }


  Future<void> _loadEquipment() async {
    try {
      final raw = await DatabaseService.instance.getSetting(_equipmentKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final names = raw.split(',');
      setState(() {
        _equipment =
            Equipment.values.where((e) => names.contains(e.name)).toSet();
      });
    } catch (_) {}
  }

  Future<void> _saveEquipment() async {
    try {
      await DatabaseService.instance.setSetting(
        _equipmentKey,
        _equipment.map((e) => e.name).join(','),
      );
    } catch (_) {}
  }

  Future<void> _loadRecent() async {
    try {
      final names = await DatabaseService.instance.getRecentExerciseNames();
      final found = <CatalogExercise>[];
      for (final n in names) {
        final c = ExerciseCatalog.byName(n);
        if (c != null) found.add(c);
      }
      if (mounted) setState(() => _recent = found);
    } catch (_) {}
  }


  bool _isAdded(CatalogExercise e) =>
      widget.alreadyAdded.contains(e.name.toLowerCase());

  bool _isSelected(CatalogExercise e) => _selected.any((s) => s.name == e.name);

  void _toggle(CatalogExercise e) {
    if (_isAdded(e)) return;
    setState(() {
      if (_isSelected(e)) {
        _selected.removeWhere((s) => s.name == e.name);
      } else {
        _selected.add(e);
      }
    });
  }


  static const Map<String, Set<Equipment>> _presets = {
    'Full gym': {
      Equipment.barbell,
      Equipment.dumbbell,
      Equipment.machine,
      Equipment.cable,
      Equipment.cardioMachine,
      Equipment.pullUpBar,
      Equipment.bodyweight,
    },
    'Home': {
      Equipment.dumbbell,
      Equipment.bodyweight,
      Equipment.bands,
      Equipment.kettlebell,
      Equipment.pullUpBar,
    },
    'No equipment': {Equipment.bodyweight},
  };

  bool _samePreset(Set<Equipment> p) =>
      p.length == _equipment.length && p.containsAll(_equipment);

  void _openEquipmentSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void change(VoidCallback fn) {
              setState(fn);
              setSheet(() {});
              _saveEquipment();
            }

            Widget group(String title, List<Equipment> items) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 8),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: items
                        .map(
                          (e) => Pill(
                            label: e.label,
                            icon: e.icon,
                            selected: _equipment.contains(e),
                            onTap: () => change(() {
                              if (_equipment.contains(e)) {
                                _equipment.remove(e);
                              } else {
                                _equipment.add(e);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'What do you have?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_equipment.isNotEmpty)
                            TextButton(
                              onPressed: () => change(() => _equipment.clear()),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Only exercises you can do with this equipment are shown. '
                        'Nothing selected shows everything.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presets.entries
                            .map(
                              (p) => Pill(
                                label: p.key,
                                selected: _samePreset(p.value),
                                onTap: () => change(() {
                                  _equipment = Set<Equipment>.from(p.value);
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      group(
                        'GYM',
                        Equipment.values.where((e) => e.isGym).toList(),
                      ),
                      group(
                        'HOME & OTHER',
                        Equipment.values.where((e) => !e.isGym).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  List<Object> _buildItems() {
    final query = _searchController.text;
    final hasQuery = ExerciseCatalog.normalize(query).isNotEmpty;
    final pool = ExerciseCatalog.search(
      query: query,
      equipment: _equipment,
      muscle: _muscle,
    );

    if (hasQuery) {
      if (pool.isEmpty) return [];
      return <Object>[
        '${pool.length} result${pool.length == 1 ? '' : 's'}',
        ...pool,
      ];
    }

    final items = <Object>[];
    if (_muscle == null && _recent.isNotEmpty) {
      items.add('Recent');
      items.addAll(_recent);
    }
    for (final m in Muscle.values) {
      final group = pool.where((e) => e.muscle == m).toList();
      if (group.isEmpty) continue;
      items.add(m.label);
      items.addAll(group);
    }
    return items;
  }


  Widget _highlightedName(CatalogExercise e, bool dim) {
    final query = _searchController.text;
    final mask = ExerciseCatalog.highlightMask(query, e.name);
    final anyHit = mask.contains(true);
    final base = dim ? Colors.grey[600]! : Colors.white70;
    final strong = dim ? Colors.grey[600]! : Colors.white;

    if (!anyHit) {
      return Text(
        e.name,
        style: TextStyle(
          color: dim ? Colors.grey[600] : Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final spans = <TextSpan>[];
    var i = 0;
    while (i < e.name.length) {
      final on = mask[i];
      var j = i;
      while (j < e.name.length && mask[j] == on) {
        j++;
      }
      spans.add(
        TextSpan(
          text: e.name.substring(i, j),
          style: TextStyle(
            color: on ? strong : base,
            fontWeight: on ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
      );
      i = j;
    }
    return RichText(
      text: TextSpan(style: const TextStyle(fontSize: 15), children: spans),
    );
  }

  Widget _row(CatalogExercise e) {
    final added = _isAdded(e);
    final selected = _isSelected(e);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: added ? null : () => _toggle(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  e.equipment.icon,
                  size: 20,
                  color: added ? Colors.grey[700] : kAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightedName(e, added),
                    const SizedBox(height: 2),
                    Text(
                      e.subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (added)
                Text(
                  'Added',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                )
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? kAccent : Colors.transparent,
                    border: Border.all(
                      color: selected ? kAccent : Colors.grey[700]!,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _empty() {
    final filtersOn = _equipment.isNotEmpty || _muscle != null;
    final q = _searchController.text.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: Colors.grey[700]),
            const SizedBox(height: 12),
            Text(
              q.isEmpty ? 'No exercises here' : 'No exercises match "$q"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtersOn
                  ? 'Your equipment or muscle filter might be hiding it.'
                  : 'Try a muscle (chest), a piece of equipment (dumbbell) or a shorter name.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            if (filtersOn) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  setState(() {
                    _equipment.clear();
                    _muscle = null;
                  });
                  _saveEquipment();
                },
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Pill(
            label: _equipment.isEmpty
                ? 'Equipment'
                : 'Equipment · ${_equipment.length}',
            icon: Icons.tune_rounded,
            selected: _equipment.isNotEmpty,
            onTap: _openEquipmentSheet,
          ),
          const SizedBox(width: 14),
          Pill(
            label: 'All',
            selected: _muscle == null,
            onTap: () => setState(() => _muscle = null),
          ),
          ...Muscle.values.map(
            (m) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Pill(
                label: m.label,
                selected: _muscle == m,
                onTap: () => setState(() => _muscle = _muscle == m ? null : m),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add exercises'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search exercises, muscles or equipment',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: kSurface,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _focus.requestFocus();
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kAccent, width: 1.5),
                ),
              ),
            ),
          ),
          _filterBar(),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? _empty()
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      if (item is String) return _header(item);
                      return _row(item as CatalogExercise);
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: kBackground,
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(
                      _selected.length == 1
                          ? 'Add 1 exercise'
                          : 'Add ${_selected.length} exercises',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
