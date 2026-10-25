import 'package:buildmatch/core/utils/input_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clean', () {
    test('trims and collapses whitespace', () {
      expect(InputSanitizer.clean('  Gulf   Build \t LLC  '), 'Gulf Build LLC');
    });

    test('replaces control characters in single-line text', () {
      expect(InputSanitizer.clean('Bad\u0007Title\nHere'), 'Bad Title Here');
      expect(InputSanitizer.clean('null\u0000byte'), 'null byte');
    });

    test('returns empty string for null', () {
      expect(InputSanitizer.clean(null), '');
    });

    test('cleanOrNull returns null for blank input', () {
      expect(InputSanitizer.cleanOrNull('   '), isNull);
      expect(InputSanitizer.cleanOrNull(' x '), 'x');
    });

    test('cleanEmail lower-cases', () {
      expect(InputSanitizer.cleanEmail('  You@Company.AE '), 'you@company.ae');
    });
  });

  group('cleanMultiline', () {
    test('keeps newlines, normalises CRLF, strips other control chars', () {
      expect(InputSanitizer.cleanMultiline('Line 1\r\nLine\u0001 2  \r\n'), 'Line 1\nLine 2');
    });

    test('collapses more than one blank line', () {
      expect(InputSanitizer.cleanMultiline('a\n\n\n\nb'), 'a\n\nb');
    });
  });

  group('validateText', () {
    test('required / min / max', () {
      expect(InputSanitizer.validateText('', field: 'Title', max: 10), 'Title is required.');
      expect(InputSanitizer.validateText('ab', field: 'Title', min: 3, max: 10), contains('at least 3'));
      expect(InputSanitizer.validateText('a' * 11, field: 'Title', max: 10), contains('at most 10'));
      expect(InputSanitizer.validateText('Marina tower', field: 'Title', max: 150), isNull);
    });

    test('optional field may be empty', () {
      expect(InputSanitizer.validateText('  ', field: 'Notes', required: false, max: 10), isNull);
    });

    test('length is measured after cleaning', () {
      expect(InputSanitizer.validateText('   abc   ', field: 'X', min: 3, max: 3), isNull);
    });

    test('rejects script and SQL injection patterns', () {
      for (final bad in [
        '<script>alert(1)</script>',
        'javascript:alert(1)',
        '<img src=x onerror="x">',
        "'; DROP TABLE rfqs; --",
        "x' OR '1'='1",
        'a /* comment */ b',
        '1 UNION SELECT password FROM users',
      ]) {
        expect(InputSanitizer.validateText(bad, field: 'Title', max: 200), contains('not allowed'), reason: bad);
      }
    });

    test('allows ordinary punctuation used in construction data', () {
      for (final ok in [
        "O'Neil Trading",
        'Rebar B500B (8–32mm)',
        'UB 305×165×40, S355',
        'Plaster sand – Zone 2 / washed',
        'Cement 42.5N; 50kg bags',
        'A&B Contracting LLC',
      ]) {
        expect(InputSanitizer.validateText(ok, field: 'Name', max: 200), isNull, reason: ok);
      }
    });
  });

  group('validateEmail', () {
    test('accepts valid emails', () {
      expect(InputSanitizer.validateEmail('you@company.ae'), isNull);
      expect(InputSanitizer.validateEmail(' First.Last+rfq@sub.domain.com '), isNull);
    });

    test('rejects invalid emails', () {
      for (final bad in ['', 'plain', 'a@b', '@x.com', 'a@.com', 'a b@c.com', 'a@b..com']) {
        expect(InputSanitizer.validateEmail(bad), isNotNull, reason: bad);
      }
    });
  });

  group('passwords', () {
    test('sign-up password rules', () {
      expect(InputSanitizer.validatePassword('short1'), contains('at least 8'));
      expect(InputSanitizer.validatePassword('onlyletters'), contains('letter and one number'));
      expect(InputSanitizer.validatePassword('12345678'), contains('letter and one number'));
      expect(InputSanitizer.validatePassword('Secur3pass'), isNull);
      expect(InputSanitizer.validatePassword('a1${'x' * 80}'), contains('at most 72'));
    });

    test('confirm password must match', () {
      expect(InputSanitizer.validateConfirmPassword('abc', 'abd'), 'Passwords do not match.');
      expect(InputSanitizer.validateConfirmPassword('abc', 'abc'), isNull);
    });

    test('login only checks presence', () {
      expect(InputSanitizer.validateLoginPassword(''), isNotNull);
      expect(InputSanitizer.validateLoginPassword('x'), isNull);
    });
  });

  group('numbers', () {
    test('parseNumber handles thousands separators and rejects junk', () {
      expect(InputSanitizer.parseNumber('1,250.50'), 1250.5);
      expect(InputSanitizer.parseNumber(' 18 '), 18);
      expect(InputSanitizer.parseNumber('12abc'), isNull);
      expect(InputSanitizer.parseNumber('1e5'), isNull);
      expect(InputSanitizer.parseNumber(''), isNull);
    });

    test('validateNumber: positive, max, decimals', () {
      expect(InputSanitizer.validateNumber('0', field: 'Qty'), contains('greater than 0'));
      expect(InputSanitizer.validateNumber('-3', field: 'Qty'), contains('greater than 0'));
      expect(InputSanitizer.validateNumber('0', field: 'Stock', allowZero: true), isNull);
      expect(InputSanitizer.validateNumber('abc', field: 'Qty'), contains('must be a number'));
      expect(InputSanitizer.validateNumber('2000000000', field: 'Qty'), contains('too large'));
      expect(InputSanitizer.validateNumber('2.555', field: 'Price', maxDecimals: 2), contains('at most 2 decimals'));
      expect(InputSanitizer.validateNumber('2550', field: 'Price', maxDecimals: 2), isNull);
      expect(InputSanitizer.validateNumber('', field: 'Price', required: false), isNull);
    });

    test('validateInt', () {
      expect(InputSanitizer.validateInt('7', field: 'Lead time', max: 365), isNull);
      expect(InputSanitizer.validateInt('7.5', field: 'Lead time', max: 365), contains('whole number'));
      expect(InputSanitizer.validateInt('400', field: 'Lead time', max: 365), contains('between 0 and 365'));
    });
  });

  group('validateDate', () {
    test('required and not in the past', () {
      final today = DateTime.now();
      expect(InputSanitizer.validateDate(null, field: 'Required by'), 'Required by is required.');
      expect(InputSanitizer.validateDate(today, field: 'Required by'), isNull);
      expect(
        InputSanitizer.validateDate(today.subtract(const Duration(days: 1)), field: 'Required by'),
        contains('past'),
      );
      expect(InputSanitizer.validateDate(null, field: 'Valid until', required: false), isNull);
    });
  });
}
