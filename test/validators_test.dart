import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/validators.dart';

void main() {
  group('Validators.age', () {
    test('accepts the allowed range', () {
      expect(Validators.age('13'), isNull);
      expect(Validators.age('100'), isNull);
    });

    test('rejects out-of-range and invalid values', () {
      expect(Validators.age(''), isNotNull);
      expect(Validators.age('12'), isNotNull);
      expect(Validators.age('101'), isNotNull);
      expect(Validators.age('abc'), isNotNull);
    });
  });

  group('Validators.weight', () {
    test('metric range', () {
      expect(Validators.weight(70, metric: true), isNull);
      expect(Validators.weight(19, metric: true), isNotNull);
      expect(Validators.weight(301, metric: true), isNotNull);
    });

    test('imperial values are converted before checking', () {
      expect(Validators.weight(154, metric: false), isNull);
      expect(Validators.weight(10, metric: false), isNotNull);
      expect(Validators.weight(700, metric: false), isNotNull);
    });
  });

  group('Validators.height', () {
    test('cm range', () {
      expect(Validators.heightCm(175), isNull);
      expect(Validators.heightCm(99), isNotNull);
      expect(Validators.heightCm(251), isNotNull);
    });

    test('feet and inches', () {
      expect(Validators.heightFeetInches('5', '9'), isNull);
      expect(Validators.heightFeetInches('2', '0'), isNotNull);
      expect(Validators.heightFeetInches('5', '12'), isNotNull);
    });
  });

  group('Validators.name', () {
    test('accepts normal names', () {
      expect(Validators.name("Anne-Marie O'Neil"), isNull);
    });

    test('rejects empty and numeric names', () {
      expect(Validators.name(''), isNotNull);
      expect(Validators.name('A'), isNotNull);
      expect(Validators.name('1234'), isNotNull);
    });
  });
}
