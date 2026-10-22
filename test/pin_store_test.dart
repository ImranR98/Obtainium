import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/pin_store.dart';
import 'package:obtainium/services/pinned_certificates.dart';

PinnedCertificate testCertificate({String asset = 'isrg-root-x1.crt'}) {
  final pem = File('assets/ca-certs/$asset').readAsStringSync();
  return PinnedCertificate(
    pem: pem,
    displayName: 'Test certificate',
    subject: 'CN=Test',
    issuer: 'CN=Test',
    notBefore: DateTime.utc(2020),
    notAfter: DateTime.utc(2040),
    sha256: fingerprintFromPem(pem),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pin_store_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<PinStore> loadedStore() async {
    final store = PinStore.forTesting(() async => tempDir);
    await store.ensureLoaded();
    return store;
  }

  test('defaults expose every built-in host with all certificates', () async {
    final store = await loadedStore();

    expect(store.userSets, isEmpty);
    expect(store.hasBuiltInOverrides, isFalse);
    for (final host in builtInPinnedHosts) {
      final resolved = store.resolve(host.host);
      expect(resolved, isNotNull, reason: host.host);
      expect(resolved!.certificates, hasLength(host.certificates.length));
      expect(resolved.builtIn, isTrue);
    }
    expect(store.resolve('api.github.com')?.builtIn, isTrue);
    expect(store.resolve('not-a-pinned-host.example'), isNull);
  });

  test('user pin sets override built-ins and match subdomains', () async {
    final store = await loadedStore();
    final certificate = testCertificate();
    final set = UserPinSet(
      id: 'user-1',
      label: 'Example',
      hosts: const [PinHostRule(host: 'github.com', includeSubdomains: true)],
      certificates: [certificate],
    );
    await store.addUserSet(set);

    final resolved = store.resolve('api.github.com');
    expect(resolved, isNotNull);
    expect(resolved!.builtIn, isFalse);
    expect(resolved.id, 'user-1');
    expect(resolved.certificates.single.sha256, certificate.sha256);
  });

  test('exact user host rules do not match subdomains', () async {
    final store = await loadedStore();
    final certificate = testCertificate();
    await store.addUserSet(
      UserPinSet(
        id: 'exact',
        label: 'Exact',
        hosts: const [PinHostRule(host: 'example.com')],
        certificates: [certificate],
      ),
    );

    expect(store.resolve('example.com')?.id, 'exact');
    expect(store.resolve('api.example.com'), isNull);
  });

  test('more specific user host rules win over broader rules', () async {
    final store = await loadedStore();
    final broad = testCertificate();
    final specific = testCertificate(asset: 'isrg-root-x2.crt');
    await store.addUserSet(
      UserPinSet(
        id: 'broad',
        label: 'Broad',
        hosts: const [
          PinHostRule(host: 'example.com', includeSubdomains: true),
        ],
        certificates: [broad],
      ),
    );
    await store.addUserSet(
      UserPinSet(
        id: 'specific',
        label: 'Specific',
        hosts: const [PinHostRule(host: 'api.example.com')],
        certificates: [specific],
      ),
    );

    expect(store.resolve('api.example.com')?.id, 'specific');
    expect(store.resolve('www.example.com')?.id, 'broad');
  });

  test(
    'built-in certificates and hosts can be disabled and restored',
    () async {
      final store = await loadedStore();
      final gitlab = builtInPinnedHosts.firstWhere(
        (host) => host.host == 'gitlab.com',
      );
      final removed = gitlab.certificates.first;

      await store.setBuiltInCertEnabled('gitlab.com', removed.sha256, false);
      expect(
        store.resolve('gitlab.com')!.certificates,
        hasLength(gitlab.certificates.length - 1),
      );
      for (final certificate in gitlab.certificates) {
        await store.setBuiltInCertEnabled(
          'gitlab.com',
          certificate.sha256,
          false,
        );
      }
      expect(store.resolve('gitlab.com'), isNull);

      await store.restoreBuiltInHost('gitlab.com');
      expect(
        store.resolve('gitlab.com')!.certificates,
        hasLength(gitlab.certificates.length),
      );

      await store.setBuiltInHostEnabled('github.com', false);
      expect(store.resolve('github.com'), isNull);
      await store.restoreBuiltInHost('github.com');
      expect(store.resolve('github.com'), isNotNull);
    },
  );

  test('restore all clears every built-in override', () async {
    final store = await loadedStore();
    final gitlab = builtInPinnedHosts.firstWhere(
      (host) => host.host == 'gitlab.com',
    );
    await store.setBuiltInHostEnabled('github.com', false);
    await store.setBuiltInCertEnabled(
      'gitlab.com',
      gitlab.certificates.first.sha256,
      false,
    );
    expect(store.hasBuiltInOverrides, isTrue);

    await store.restoreAllBuiltIn();

    expect(store.hasBuiltInOverrides, isFalse);
    expect(
      store.resolve('gitlab.com')!.certificates,
      hasLength(gitlab.certificates.length),
    );
    expect(store.resolve('github.com'), isNotNull);
  });

  test('user sets and built-in overrides survive a reload', () async {
    final store = await loadedStore();
    final certificate = testCertificate();
    await store.addUserSet(
      UserPinSet(
        id: 'persisted',
        label: 'Persisted',
        hosts: const [
          PinHostRule(host: 'example.com', includeSubdomains: true),
        ],
        certificates: [certificate],
      ),
    );
    await store.setBuiltInCertEnabled(
      'gitlab.com',
      builtInPinnedHosts
          .firstWhere((host) => host.host == 'gitlab.com')
          .certificates
          .first
          .sha256,
      false,
    );

    final reloaded = await loadedStore();
    expect(reloaded.userSets, hasLength(1));
    expect(reloaded.userSets.single.id, 'persisted');
    expect(reloaded.userSets.single.certificates.single.pem, certificate.pem);
    expect(
      reloaded.resolve('example.com')?.certificates.single.sha256,
      certificate.sha256,
    );
    expect(
      reloaded.resolve('gitlab.com')!.certificates,
      hasLength(
        builtInPinnedHosts
                .firstWhere((host) => host.host == 'gitlab.com')
                .certificates
                .length -
            1,
      ),
    );
  });

  test('overlapping user sets at the same specificity are rejected', () async {
    final store = await loadedStore();
    final certificate = testCertificate();
    await store.addUserSet(
      UserPinSet(
        id: 'one',
        label: 'One',
        hosts: const [PinHostRule(host: 'example.com')],
        certificates: [certificate],
      ),
    );
    expect(
      () => store.validateUserSet(
        UserPinSet(
          id: 'two',
          label: 'Two',
          hosts: const [PinHostRule(host: 'example.com')],
          certificates: [certificate],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => store.validateUserSet(
        UserPinSet(
          id: 'two',
          label: 'Two',
          hosts: const [PinHostRule(host: 'api.example.com')],
          certificates: [certificate],
        ),
      ),
      returnsNormally,
    );
  });

  test('corrupt stores are backed up and reported', () async {
    final file = File('${tempDir.path}/pinned_certificates.json');
    await file.writeAsString('{not json');
    final store = await loadedStore();

    expect(store.loadError, isNotNull);
    expect(store.userSets, isEmpty);
    expect(
      tempDir.listSync().whereType<File>().any(
        (entry) => entry.path.contains('.corrupt-'),
      ),
      isTrue,
    );
    expect(store.resolve('github.com'), isNotNull);
  });

  test('host normalization accepts hosts and URLs', () {
    expect(normalizePinHost(' example.com '), 'example.com');
    expect(normalizePinHost('https://api.example.com/path'), 'api.example.com');
    expect(normalizePinHost('*.example.com'), 'example.com');
    expect(normalizePinHost('example.com:8443'), 'example.com');
    expect(normalizePinHost(''), isNull);
    expect(normalizePinHost('has spaces'), isNull);
  });

  test('JSON encoding is readable', () async {
    final store = await loadedStore();
    final certificate = testCertificate();
    await store.addUserSet(
      UserPinSet(
        id: 'json',
        label: 'JSON',
        hosts: const [PinHostRule(host: 'example.com')],
        certificates: [certificate],
      ),
    );
    final raw = await File(
      '${tempDir.path}/pinned_certificates.json',
    ).readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    expect((decoded['userSets'] as List), hasLength(1));
  });
}
