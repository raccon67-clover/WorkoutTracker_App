import 'package:flutter/material.dart';

import '../main.dart' show kBackground, kSurface, kAccent;
import '../models/user_profile.dart';
import '../services/database_service.dart';

class EditProfilePage extends StatefulWidget {
  final UserProfile profile;

  const EditProfilePage({super.key, required this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _injuries;

  String? _gender;
  String? _goal;
  String? _level;
  bool _saving = false;

  // Change these lists so they match your onboarding options.
  static const _genders = ['Male', 'Female', 'Other'];
  static const _goals = [
    'Lose weight',
    'Build muscle',
    'Stay fit',
    'Improve endurance',
  ];
  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.name);
    _age = TextEditingController(text: p.age.toString());
    _height = TextEditingController(
      text: p.height != null ? p.height!.toStringAsFixed(0) : '',
    );
    _injuries = TextEditingController(text: p.injuries ?? '');
    _gender = p.gender;
    _goal = p.fitnessGoal;
    _level = p.fitnessLevel;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _injuries.dispose();
    super.dispose();
  }

  // Keeps the user's current saved value selectable even if it is not
  // in the lists above.
  List<String> _withCurrent(List<String> base, String? current) {
    if (current == null || current.isEmpty || base.contains(current)) {
      return base;
    }
    return [...base, current];
  }

  InputDecoration _dec(String label, {String? suffix}) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  Widget _dropdown(
    String label,
    List<String> options,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: kSurface,
      decoration: _dec(label),
      items: [
        for (final o in _withCurrent(options, value))
          DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final heightText = _height.text.trim();
      final updated = widget.profile.copyWith(
        name: _name.text.trim(),
        age: int.parse(_age.text.trim()),
        gender: _gender,
        height: heightText.isEmpty ? null : double.parse(heightText),
        fitnessGoal: _goal,
        fitnessLevel: _level,
        injuries: _injuries.text.trim(),
        onboardingCompleted: true,
      );

      await DatabaseService.instance.upsertUserProfile(updated);
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        title: const Text('Edit Profile'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _dec('Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: _dec('Age'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 10 || n > 100) return '10 - 100';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _dec('Height', suffix: 'cm'),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final n = double.tryParse(t);
                        if (n == null || n < 80 || n > 260) return '80 - 260';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _dropdown('Gender', _genders, _gender,
                  (v) => setState(() => _gender = v)),
              const SizedBox(height: 14),
              _dropdown('Fitness goal', _goals, _goal,
                  (v) => setState(() => _goal = v)),
              const SizedBox(height: 14),
              _dropdown('Fitness level', _levels, _level,
                  (v) => setState(() => _level = v)),
              const SizedBox(height: 14),
              TextFormField(
                controller: _injuries,
                maxLines: 3,
                decoration: _dec('Injuries or limitations (optional)'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}