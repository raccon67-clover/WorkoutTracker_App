import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../validators.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';
import '../main.dart' show kBackground, kSurface, kAccent;
import 'home_page.dart';

class OnboardingPage extends StatefulWidget {
  final String uid;
  final String name;

  const OnboardingPage({
    super.key,
    required this.uid,
    required this.name,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int totalPages = 6;

  final PageController _pageController = PageController();

  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _feetController = TextEditingController();
  final TextEditingController _inchesController = TextEditingController();

  int _currentPage = 0;
  bool _saving = false;
  String? _saveError;

  String? _gender;
  String? _fitnessGoal;
  String? _fitnessLevel;

  bool _metricWeight = true;
  bool _metricHeight = true;

  int? _age;
  double? _weight;
  double? _heightCm;
  int? _heightFeet;
  int? _heightInches;

  @override
  void dispose() {
    _pageController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    super.dispose();
  }

  String? get _ageError {
    if (_age == null) return 'Select your age';
    return Validators.age(_ageController.text);
  }

  String? get _weightError {
    if (_weight == null) return 'Select your weight';

    return Validators.weight(
      _weight,
      metric: _metricWeight,
    );
  }

  String? get _heightError {
    if (_metricHeight) {
      if (_heightCm == null) return 'Select your height';

      return Validators.heightCm(_heightCm);
    }

    if (_heightFeet == null) return 'Select your height';

    return Validators.heightFeetInches(
      _feetController.text,
      _inchesController.text,
    );
  }

  bool get _canContinue {
    switch (_currentPage) {
      case 0:
        return _ageError == null;
      case 1:
        return _gender != null;
      case 2:
        return _weightError == null;
      case 3:
        return _heightError == null;
      case 4:
        return _fitnessGoal != null;
      case 5:
        return _fitnessLevel != null;
      default:
        return false;
    }
  }

  double get _weightKg {
    if (_weight == null) {
      throw StateError('Weight has not been selected.');
    }

    return _metricWeight ? _weight! : _weight! * 0.453592;
  }

  double get _finalHeightCm {
    if (_metricHeight) {
      if (_heightCm == null) {
        throw StateError('Height has not been selected.');
      }

      return _heightCm!;
    }

    final feet = _heightFeet ?? 0;
    final inches = _heightInches ?? 0;

    return ((feet * 12) + inches) * 2.54;
  }

  void _next() {
    if (!_canContinue || _saving) return;

    if (_currentPage < totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _finish();
  }

  void _back() {
    if (_saving || _currentPage == 0) return;

    _pageController.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_saving || !_canContinue) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final profile = UserProfile(
        uid: widget.uid,
        name: widget.name,
        age: _age!,
        gender: _gender,
        weight: _weightKg,
        height: _finalHeightCm,
        fitnessGoal: _fitnessGoal,
        fitnessLevel: _fitnessLevel,
        onboardingCompleted: true,
      );

      await DatabaseService.instance.upsertUserProfile(
        profile,
        requireCloud: true,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Onboarding save failed: $e');

      if (!mounted) return;

      setState(() {
        _saving = false;
        _saveError =
            'We could not save your profile. Check your connection and try again.';
      });
    }
  }

  void _selectGender(String value) {
    setState(() {
      _gender = value;
    });
  }

  void _selectGoal(String value) {
    setState(() {
      _fitnessGoal = value;
    });
  }

  void _selectLevel(String value) {
    setState(() {
      _fitnessLevel = value;
    });
  }

  void _setWeightUnit(bool metric) {
    if (_metricWeight == metric) return;

    setState(() {
      _metricWeight = metric;
      _weight = null;
      _weightController.clear();
    });
  }

  void _setHeightUnit(bool metric) {
    if (_metricHeight == metric) return;

    setState(() {
      _metricHeight = metric;
      _heightCm = null;
      _heightFeet = null;
      _heightInches = null;
      _heightController.clear();
      _feetController.clear();
      _inchesController.clear();
    });
  }

  void _setAge(int value) {
    setState(() {
      _age = value;
      _ageController.text = value.toString();
    });
  }

  void _setWeight(double value) {
    setState(() {
      _weight = value;
      _weightController.text = _formatNumber(value);
    });
  }

  void _setHeightCm(double value) {
    setState(() {
      _heightCm = value;
      _heightController.text = _formatNumber(value);
    });
  }

  void _setHeightFeet(int value) {
    setState(() {
      _heightFeet = value;
      _feetController.text = value.toString();
    });
  }

  void _setHeightInches(int value) {
    setState(() {
      _heightInches = value;
      _inchesController.text = value.toString();
    });
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  Future<void> _editAge() async {
    final value = await _showNumberInput(
      title: 'Enter your age',
      initialText: _age?.toString() ?? '',
      suffix: 'years',
      decimal: false,
      min: Limits.minAge,
      max: Limits.maxAge,
      icon: Icons.cake_outlined,
    );

    if (value == null) return;

    final age = int.tryParse(value);

    if (age == null) return;

    final error = Validators.age(age.toString());

    if (error != null) {
      _showInputError(error);
      return;
    }

    _setAge(age);
  }

  Future<void> _editWeight() async {
    final value = await _showNumberInput(
      title: 'Enter your weight',
      initialText: _weight == null ? '' : _formatNumber(_weight!),
      suffix: _metricWeight ? 'kg' : 'lbs',
      decimal: true,
      min: _metricWeight ? 20 : 44,
      max: _metricWeight ? 300 : 660,
      step: _metricWeight ? 0.5 : 1,
      icon: Icons.monitor_weight_outlined,
    );

    if (value == null) return;

    final weight = double.tryParse(value);

    if (weight == null) return;

    final error = Validators.weight(
      weight,
      metric: _metricWeight,
    );

    if (error != null) {
      _showInputError(error);
      return;
    }

    _setWeight(weight);
  }

  Future<void> _editHeightCm() async {
    final value = await _showNumberInput(
      title: 'Enter your height',
      initialText: _heightCm == null ? '' : _formatNumber(_heightCm!),
      suffix: 'cm',
      decimal: false,
      min: 100,
      max: 250,
      icon: Icons.height_rounded,
    );

    if (value == null) return;

    final height = double.tryParse(value);

    if (height == null) return;

    final error = Validators.heightCm(height);

    if (error != null) {
      _showInputError(error);
      return;
    }

    _setHeightCm(height);
  }

  Future<void> _editFeet() async {
    final value = await _showNumberInput(
      title: 'Enter feet',
      initialText: _heightFeet?.toString() ?? '',
      suffix: 'ft',
      decimal: false,
      min: 3,
      max: 8,
      icon: Icons.height_rounded,
    );

    if (value == null) return;

    final feet = int.tryParse(value);

    if (feet == null) return;

    _setHeightFeet(feet);

    _validateImperialHeight();
  }

  Future<void> _editInches() async {
    final value = await _showNumberInput(
      title: 'Enter inches',
      initialText: _heightInches?.toString() ?? '',
      suffix: 'in',
      decimal: false,
      min: 0,
      max: 11,
      icon: Icons.straighten_rounded,
    );

    if (value == null) return;

    final inches = int.tryParse(value);

    if (inches == null) return;

    _setHeightInches(inches);

    _validateImperialHeight();
  }

  void _validateImperialHeight() {
    if (_heightFeet == null) return;

    _feetController.text = _heightFeet.toString();
    _inchesController.text = (_heightInches ?? 0).toString();

    setState(() {});
  }

  Future<String?> _showNumberInput({
    required String title,
    required String initialText,
    required String suffix,
    required bool decimal,
    required num min,
    required num max,
    IconData icon = Icons.edit_outlined,
    num step = 1,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _NumberInputDialog(
        title: title,
        icon: icon,
        initialText: initialText,
        suffix: suffix,
        decimal: decimal,
        min: min,
        max: max,
        step: step,
      ),
    );
  }

  void _showInputError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildPage({
    required IconData icon,
    required String eyebrow,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: kAccent.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              icon,
              color: kAccent,
              size: 31,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              color: kAccent.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 30),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_currentPage + 1) / totalPages;

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: _currentPage == 0
                        ? null
                        : IconButton(
                            onPressed: _back,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                            ),
                            color: Colors.white,
                          ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'YOUR SETUP',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              '${_currentPage + 1} OF $totalPages',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: kSurface,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(
                              kAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildPage(
                    icon: Icons.cake_outlined,
                    eyebrow: 'A little about you',
                    title: 'How old are you?',
                    subtitle:
                        'This helps us keep your profile and recommendations relevant.',
                    child: _AgePicker(
                      value: _age,
                      onChanged: _setAge,
                      onTapValue: _editAge,
                    ),
                  ),
                  _buildPage(
                    icon: Icons.person_outline_rounded,
                    eyebrow: 'Personalize your experience',
                    title: 'How do you identify?',
                    subtitle:
                        'Choose the option you are most comfortable using in your profile.',
                    child: _ChoiceList(
                      options: const [
                        _ChoiceData(
                          'Male',
                          Icons.male_rounded,
                        ),
                        _ChoiceData(
                          'Female',
                          Icons.female_rounded,
                        ),
                        _ChoiceData(
                          'Prefer not to say',
                          Icons.person_outline,
                        ),
                      ],
                      selected: _gender,
                      onSelected: _selectGender,
                    ),
                  ),
                  _buildPage(
                    icon: Icons.monitor_weight_outlined,
                    eyebrow: 'Your starting point',
                    title: "What's your weight?",
                    subtitle:
                        'You can update your body weight later from your profile.',
                    child: Column(
                      children: [
                        _UnitToggle(
                          metric: _metricWeight,
                          firstLabel: 'kg',
                          secondLabel: 'lbs',
                          onChanged: _setWeightUnit,
                        ),
                        const SizedBox(height: 22),
                        _WeightPicker(
                          value: _weight,
                          metric: _metricWeight,
                          onChanged: _setWeight,
                          onTapValue: _editWeight,
                        ),
                      ],
                    ),
                  ),
                  _buildPage(
                    icon: Icons.height_rounded,
                    eyebrow: 'One more measurement',
                    title: "What's your height?",
                    subtitle:
                        'Used for your profile and body-metric calculations.',
                    child: Column(
                      children: [
                        _UnitToggle(
                          metric: _metricHeight,
                          firstLabel: 'cm',
                          secondLabel: 'ft / in',
                          onChanged: _setHeightUnit,
                        ),
                        const SizedBox(height: 22),
                        if (_metricHeight)
                          _HeightCmPicker(
                            value: _heightCm,
                            onChanged: _setHeightCm,
                            onTapValue: _editHeightCm,
                          )
                        else
                          _ImperialHeightPicker(
                            feet: _heightFeet,
                            inches: _heightInches,
                            onFeetChanged: _setHeightFeet,
                            onInchesChanged: _setHeightInches,
                            onFeetTap: _editFeet,
                            onInchesTap: _editInches,
                          ),
                      ],
                    ),
                  ),
                  _buildPage(
                    icon: Icons.flag_outlined,
                    eyebrow: 'Set your direction',
                    title: "What's your main goal?",
                    subtitle:
                        'Your goal helps shape the information shown throughout the app.',
                    child: _ChoiceList(
                      options: const [
                        _ChoiceData(
                          'Lose Weight',
                          Icons.local_fire_department_outlined,
                        ),
                        _ChoiceData(
                          'Build Muscle',
                          Icons.fitness_center_rounded,
                        ),
                        _ChoiceData(
                          'Stay Fit',
                          Icons.favorite_border_rounded,
                        ),
                        _ChoiceData(
                          'Improve Endurance',
                          Icons.directions_run_rounded,
                        ),
                      ],
                      selected: _fitnessGoal,
                      onSelected: _selectGoal,
                    ),
                  ),
                  _buildPage(
                    icon: Icons.trending_up_rounded,
                    eyebrow: 'Meet yourself where you are',
                    title: "What's your fitness level?",
                    subtitle:
                        'There is no wrong answer. You can change this later.',
                    child: _ChoiceList(
                      options: const [
                        _ChoiceData(
                          'Beginner',
                          Icons.looks_one_rounded,
                        ),
                        _ChoiceData(
                          'Intermediate',
                          Icons.looks_two_rounded,
                        ),
                        _ChoiceData(
                          'Advanced',
                          Icons.looks_3_rounded,
                        ),
                      ],
                      selected: _fitnessLevel,
                      onSelected: _selectLevel,
                    ),
                  ),
                ],
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  _saveError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving || !_canContinue ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    disabledBackgroundColor: kSurface,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey[600],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
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
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentPage == totalPages - 1
                                  ? 'Finish setup'
                                  : 'Continue',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _currentPage == totalPages - 1
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 19,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgePicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  final VoidCallback onTapValue;

  const _AgePicker({
    required this.value,
    required this.onChanged,
    required this.onTapValue,
  });

  @override
  Widget build(BuildContext context) {
    return _WheelNumberPicker(
      min: 13,
      max: 100,
      value: value,
      suffix: 'years',
      onChanged: onChanged,
      onTapValue: onTapValue,
    );
  }
}

class _WeightPicker extends StatelessWidget {
  final double? value;
  final bool metric;
  final ValueChanged<double> onChanged;
  final VoidCallback onTapValue;

  const _WeightPicker({
    required this.value,
    required this.metric,
    required this.onChanged,
    required this.onTapValue,
  });

  @override
  Widget build(BuildContext context) {
    return _DecimalWheelPicker(
      min: metric ? 20 : 44,
      max: metric ? 300 : 660,
      step: metric ? 0.5 : 1,
      value: value,
      suffix: metric ? 'kg' : 'lbs',
      onChanged: onChanged,
      onTapValue: onTapValue,
    );
  }
}

class _HeightCmPicker extends StatelessWidget {
  final double? value;
  final ValueChanged<double> onChanged;
  final VoidCallback onTapValue;

  const _HeightCmPicker({
    required this.value,
    required this.onChanged,
    required this.onTapValue,
  });

  @override
  Widget build(BuildContext context) {
    return _DecimalWheelPicker(
      min: 100,
      max: 250,
      step: 1,
      value: value,
      suffix: 'cm',
      onChanged: onChanged,
      onTapValue: onTapValue,
    );
  }
}

class _WheelNumberPicker extends StatefulWidget {
  final int min;
  final int max;
  final int? value;
  final String suffix;
  final ValueChanged<int> onChanged;
  final VoidCallback onTapValue;

  const _WheelNumberPicker({
    required this.min,
    required this.max,
    required this.value,
    required this.suffix,
    required this.onChanged,
    required this.onTapValue,
  });

  @override
  State<_WheelNumberPicker> createState() => _WheelNumberPickerState();
}

class _WheelNumberPickerState extends State<_WheelNumberPicker> {
  late FixedExtentScrollController _controller;
  bool _syncing = false;

  int _indexForValue(int value) {
    return (value - widget.min + 1).clamp(
      1,
      widget.max - widget.min + 1,
    );
  }

  @override
  void initState() {
    super.initState();

    _controller = FixedExtentScrollController(
      initialItem: widget.value == null
          ? 0
          : _indexForValue(widget.value!),
    );
  }

  @override
  void didUpdateWidget(covariant _WheelNumberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _controller.dispose();

      _controller = FixedExtentScrollController(
        initialItem: widget.value == null
            ? 0
            : _indexForValue(widget.value!),
      );

      return;
    }

    if (oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;

        final target = widget.value == null
            ? 0
            : _indexForValue(widget.value!);

        if (_controller.selectedItem != target) {
          // Ignore the in-between values the wheel passes through while it
          // animates to the typed value, otherwise they overwrite it.
          _syncing = true;
          _controller
              .animateToItem(
                target,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              )
              .whenComplete(() => _syncing = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedValue = widget.value;

    return _PickerShell(
      label: 'Scroll to choose',
      helper: 'Tap the wheel to type a value instead',
      onTap: widget.onTapValue,
      child: SizedBox(
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 84,
              child: IgnorePointer(
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: kAccent.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ),
            ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: 52,
              diameterRatio: 1.5,
              perspective: 0.003,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                if (_syncing || index == 0) return;

                widget.onChanged(widget.min + index - 1);
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: widget.max - widget.min + 2,
                builder: (context, index) {
                  if (index == 0) {
                    return Center(
                      child: Text(
                        '—',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  final number = widget.min + index - 1;
                  final selected = number == selectedValue;

                  return Center(
                    child: Text(
                      number.toString(),
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.grey[600],
                        fontSize: selected ? 36 : 22,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            IgnorePointer(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: Text(
                    widget.suffix,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecimalWheelPicker extends StatefulWidget {
  final double min;
  final double max;
  final double step;
  final double? value;
  final String suffix;
  final ValueChanged<double> onChanged;
  final VoidCallback onTapValue;

  const _DecimalWheelPicker({
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.suffix,
    required this.onChanged,
    required this.onTapValue,
  });

  @override
  State<_DecimalWheelPicker> createState() => _DecimalWheelPickerState();
}

class _DecimalWheelPickerState extends State<_DecimalWheelPicker> {
  late FixedExtentScrollController _controller;
  bool _syncing = false;

  int get _valueCount =>
      ((widget.max - widget.min) / widget.step).round() + 1;

  double _valueAt(int index) {
    return widget.min + ((index - 1) * widget.step);
  }

  int _indexForValue(double value) {
    return ((value - widget.min) / widget.step)
            .round()
            .clamp(0, _valueCount - 1) +
        1;
  }

  @override
  void initState() {
    super.initState();

    _controller = FixedExtentScrollController(
      initialItem: widget.value == null
          ? 0
          : _indexForValue(widget.value!),
    );
  }

  @override
  void didUpdateWidget(covariant _DecimalWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step) {
      _controller.dispose();

      _controller = FixedExtentScrollController(
        initialItem: widget.value == null
            ? 0
            : _indexForValue(widget.value!),
      );

      return;
    }

    if (oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;

        final target = widget.value == null
            ? 0
            : _indexForValue(widget.value!);

        if (_controller.selectedItem != target) {
          // Ignore the in-between values the wheel passes through while it
          // animates to the typed value, otherwise they overwrite it.
          _syncing = true;
          _controller
              .animateToItem(
                target,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              )
              .whenComplete(() => _syncing = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final selectedValue = widget.value;

    return _PickerShell(
      label: 'Scroll to choose',
      helper: 'Tap the wheel to type a value instead',
      onTap: widget.onTapValue,
      child: SizedBox(
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 84,
              child: IgnorePointer(
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: kAccent.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ),
            ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: 52,
              diameterRatio: 1.5,
              perspective: 0.003,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                if (_syncing || index == 0) return;

                widget.onChanged(_valueAt(index));
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: _valueCount + 1,
                builder: (context, index) {
                  if (index == 0) {
                    return Center(
                      child: Text(
                        '—',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  final number = _valueAt(index);
                  final selected = selectedValue != null &&
                      (number - selectedValue).abs() < 0.001;

                  return Center(
                    child: Text(
                      _format(number),
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.grey[600],
                        fontSize: selected ? 36 : 22,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            IgnorePointer(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: Text(
                    widget.suffix,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImperialHeightPicker extends StatelessWidget {
  final int? feet;
  final int? inches;
  final ValueChanged<int> onFeetChanged;
  final ValueChanged<int> onInchesChanged;
  final VoidCallback onFeetTap;
  final VoidCallback onInchesTap;

  const _ImperialHeightPicker({
    required this.feet,
    required this.inches,
    required this.onFeetChanged,
    required this.onInchesChanged,
    required this.onFeetTap,
    required this.onInchesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SmallWheelPicker(
            min: 3,
            max: 8,
            value: feet,
            suffix: 'ft',
            onChanged: onFeetChanged,
            onTapValue: onFeetTap,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _SmallWheelPicker(
            min: 0,
            max: 11,
            value: inches,
            suffix: 'in',
            onChanged: onInchesChanged,
            onTapValue: onInchesTap,
          ),
        ),
      ],
    );
  }
}

class _SmallWheelPicker extends StatefulWidget {
  final int min;
  final int max;
  final int? value;
  final String suffix;
  final ValueChanged<int> onChanged;
  final VoidCallback onTapValue;

  const _SmallWheelPicker({
    required this.min,
    required this.max,
    required this.value,
    required this.suffix,
    required this.onChanged,
    required this.onTapValue,
  });

  @override
  State<_SmallWheelPicker> createState() => _SmallWheelPickerState();
}

class _SmallWheelPickerState extends State<_SmallWheelPicker> {
  late FixedExtentScrollController _controller;
  bool _syncing = false;

  int _indexForValue(int value) {
    return (value - widget.min + 1).clamp(
      1,
      widget.max - widget.min + 1,
    );
  }

  @override
  void initState() {
    super.initState();

    _controller = FixedExtentScrollController(
      initialItem: widget.value == null
          ? 0
          : _indexForValue(widget.value!),
    );
  }

  @override
  void didUpdateWidget(covariant _SmallWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _controller.dispose();

      _controller = FixedExtentScrollController(
        initialItem: widget.value == null
            ? 0
            : _indexForValue(widget.value!),
      );

      return;
    }

    if (oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;

        final target = widget.value == null
            ? 0
            : _indexForValue(widget.value!);

        if (_controller.selectedItem != target) {
          // Ignore the in-between values the wheel passes through while it
          // animates to the typed value, otherwise they overwrite it.
          _syncing = true;
          _controller
              .animateToItem(
                target,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              )
              .whenComplete(() => _syncing = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedValue = widget.value;

    return GestureDetector(
      onTap: widget.onTapValue,
      child: Container(
        padding: const EdgeInsets.only(
          top: 12,
          bottom: 14,
        ),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey[800]!,
          ),
        ),
        child: Column(
          children: [
            Text(
              widget.suffix.toUpperCase(),
              style: TextStyle(
                color: kAccent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 69,
                    child: IgnorePointer(
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: kAccent.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ListWheelScrollView.useDelegate(
                    controller: _controller,
                    itemExtent: 48,
                    diameterRatio: 1.5,
                    perspective: 0.003,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (index) {
                      if (_syncing || index == 0) return;

                      widget.onChanged(widget.min + index - 1);
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: widget.max - widget.min + 2,
                      builder: (context, index) {
                        if (index == 0) {
                          return Center(
                            child: Text(
                              '—',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }

                        final number = widget.min + index - 1;
                        final selected = number == selectedValue;

                        return Center(
                          child: Text(
                            number.toString(),
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : Colors.grey[600],
                              fontSize: selected ? 32 : 20,
                              fontWeight: selected
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Tap to type',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerShell extends StatelessWidget {
  final String label;
  final String helper;
  final VoidCallback onTap;
  final Widget child;

  const _PickerShell({
    required this.label,
    required this.helper,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.grey[800]!,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: kAccent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            child,
            const SizedBox(height: 4),
            Text(
              helper,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  final bool metric;
  final String firstLabel;
  final String secondLabel;
  final ValueChanged<bool> onChanged;

  const _UnitToggle({
    required this.metric,
    required this.firstLabel,
    required this.secondLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _button(firstLabel, true),
          _button(secondLabel, false),
        ],
      ),
    );
  }

  Widget _button(String label, bool first) {
    final selected = metric == first;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(first),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? kAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey[500],
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceData {
  final String label;
  final IconData icon;

  const _ChoiceData(
    this.label,
    this.icon,
  );
}

class _ChoiceList extends StatelessWidget {
  final List<_ChoiceData> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _ChoiceList({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options) ...[
          _choice(option),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _choice(_ChoiceData option) {
    final isSelected = selected == option.label;

    return GestureDetector(
      onTap: () => onSelected(option.label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? kAccent.withValues(alpha: 0.15)
              : kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? kAccent : Colors.grey[800]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? kAccent.withValues(alpha: 0.18)
                    : Colors.grey[900],
                shape: BoxShape.circle,
              ),
              child: Icon(
                option.icon,
                color: isSelected
                    ? kAccent
                    : Colors.grey[400],
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: isSelected ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(
                Icons.check_circle_rounded,
                color: kAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number-entry popup used when the person taps a wheel to type a value.
///
/// Owns its own TextEditingController so it is only disposed once the dialog
/// has fully left the tree.
class _NumberInputDialog extends StatefulWidget {
  final String title;
  final IconData icon;
  final String initialText;
  final String suffix;
  final bool decimal;
  final num min;
  final num max;
  final num step;

  const _NumberInputDialog({
    required this.title,
    required this.icon,
    required this.initialText,
    required this.suffix,
    required this.decimal,
    required this.min,
    required this.max,
    required this.step,
  });

  @override
  State<_NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<_NumberInputDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  num? _parse(String text) {
    return widget.decimal ? double.tryParse(text) : int.tryParse(text);
  }

  void _nudge(int direction) {
    final current = _parse(_controller.text.trim());
    num next = current == null ? widget.min : current + widget.step * direction;
    next = next.clamp(widget.min, widget.max);

    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _controller.text = _format(next);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    final value = _parse(text);

    if (value == null) {
      setState(() => _error = 'Enter a valid number.');
      return;
    }

    if (value < widget.min || value > widget.max) {
      setState(() {
        _error = 'Enter a value from ${_format(widget.min)} '
            'to ${_format(widget.max)}.';
      });
      return;
    }

    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _error != null;

    return Dialog(
      backgroundColor: kSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, color: kAccent, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Between ${_format(widget.min)} and '
              '${_format(widget.max)} ${widget.suffix}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _nudge(-1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    decoration: BoxDecoration(
                      color: kBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: hasError
                            ? Colors.redAccent
                            : kAccent.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          cursorColor: kAccent,
                          keyboardType: TextInputType.numberWithOptions(
                            decimal: widget.decimal,
                          ),
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            if (widget.decimal)
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d{0,3}(\.\d{0,2})?'),
                              )
                            else
                              FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: const InputDecoration(
                            filled: false,
                            isCollapsed: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                            hintText: '0',
                            hintStyle: TextStyle(color: Colors.grey),
                          ),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => _submit(),
                        ),
                        Text(
                          widget.suffix.toUpperCase(),
                          style: TextStyle(
                            color: kAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: () => _nudge(1),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: hasError
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[300],
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: BorderSide(color: Colors.grey[800]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Cancel',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBackground,
      shape: CircleBorder(
        side: BorderSide(color: Colors.grey[800]!),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}