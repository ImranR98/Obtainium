import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/dcl_support.dart';

void main() {
  setUp(() {
    DclSupport.resetCache();
    DclSupport.debugReadFile = null;
    DclSupport.debugProbeExecmem = null;
  });

  tearDown(() {
    DclSupport.resetCache();
    DclSupport.debugReadFile = null;
    DclSupport.debugProbeExecmem = null;
  });

  String? Function(String path) grapheneosFlags(String value) {
    return (path) => path.endsWith('/grapheneos_flags') ? value : null;
  }

  test('detects the DENY_EXECMEM bit in the current attribute', () {
    DclSupport.debugReadFile = grapheneosFlags('1');

    expect(DclSupport.isExecmemRestricted, isTrue);
  });

  test('allows execution when only other flags are set', () {
    DclSupport.debugReadFile = grapheneosFlags('100');

    expect(DclSupport.isExecmemRestricted, isFalse);
  });

  test('parses combined flags', () {
    DclSupport.debugReadFile = grapheneosFlags('101');

    expect(DclSupport.isExecmemRestricted, isTrue);
  });

  test('falls back to the legacy attribute', () {
    DclSupport.debugReadFile = (path) =>
        path.endsWith('/selinux_flags') ? '1' : null;

    expect(DclSupport.isExecmemRestricted, isTrue);
  });

  test('prefers the current attribute over the legacy one', () {
    DclSupport.debugReadFile = (path) {
      if (path.endsWith('/grapheneos_flags')) return '0';
      if (path.endsWith('/selinux_flags')) return '1';
      return null;
    };

    expect(DclSupport.isExecmemRestricted, isFalse);
  });

  test('probes when neither attribute exists', () {
    DclSupport.debugReadFile = (_) => null;
    DclSupport.debugProbeExecmem = () => true;

    expect(DclSupport.isExecmemRestricted, isTrue);
  });

  test('probes when attributes cannot be parsed', () {
    DclSupport.debugReadFile = grapheneosFlags('not-hex');
    DclSupport.debugProbeExecmem = () => false;

    expect(DclSupport.isExecmemRestricted, isFalse);
  });

  test('caches the result until the cache is reset', () {
    var reads = 0;
    DclSupport.debugReadFile = (path) {
      reads++;
      return path.endsWith('/grapheneos_flags') ? '0' : null;
    };

    expect(DclSupport.isExecmemRestricted, isFalse);
    expect(DclSupport.isExecmemRestricted, isFalse);
    expect(reads, 1);

    DclSupport.resetCache();
    expect(DclSupport.isExecmemRestricted, isFalse);
    expect(reads, 2);
  });
}
