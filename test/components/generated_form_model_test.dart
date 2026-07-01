import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/components/generated_form_model.dart';

void main() {
  test('GeneratedFormTextField clone works', () {
    final original = GeneratedFormTextField('test', label: 'Test');
    final cloned = original.clone();
    expect(cloned.label, 'Test');
    expect(cloned.key, 'test');
  });
}
