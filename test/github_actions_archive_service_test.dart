import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/github_actions_archive_service.dart';

List<int> zipOf(Map<String, List<int>> contents) {
    final archive = Archive();
    for (final item in contents.entries) {
        archive.addFile(ArchiveFile(item.key, item.value.length, item.value));
    }
    return ZipEncoder().encode(archive);
}

void main() {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('installable extensions are matched case-insensitively', () {
        for (final ext in ['apk', 'apks', 'apkm', 'xapk']) {
            expect(actionsIsInstallableFile('builds/app.$ext'), isTrue);
            expect(actionsIsInstallableFile('APP.${ext.toUpperCase()}'), isTrue);
        }
        expect(actionsIsInstallableFile('builds/choice.zip'), isFalse);
        expect(actionsIsInstallableFile('notes.txt'), isFalse);
    });

    test('APK filename filtering does not match directories or ZIP names', () {
        const selection = ActionsFileSelection(apkPattern: r'^app-v.*\.apk$');
        expect(selection.matchesApk('directory/app-v12.apk'), isTrue);
        expect(selection.matchesApk('app-v12.xapk'), isFalse);
        expect(selection.matchesApk('app-v12.apk/something.apk'), isFalse);
        expect(selection.matchesApk('app-release.apk'), isFalse);
    });

    test('direct and nested selections keep separate APK and ZIP rules', () {
        const direct = ActionsFileSelection(location: ActionsApkLocation.direct);
        const nested = ActionsFileSelection(
            location: ActionsApkLocation.nested,
            zipPattern: 'choice-a', apkPattern: 'universal',
        );
        const rootApk = ActionsArchiveEntry('root.apk');
        const goodZip = ActionsArchiveEntry('builds/choice-a.zip');
        const badZip = ActionsArchiveEntry('builds/choice-b.zip');
        const goodInner = ActionsArchiveEntry('universal.apk',
                parentZip: 'builds/choice-a.zip');
        const wrongInner = ActionsArchiveEntry('universal.apk',
                parentZip: 'builds/choice-b.zip');
        expect(direct.matchesEntry(rootApk), isTrue);
        expect(direct.matchesEntry(goodZip), isFalse);
        expect(direct.matchesEntry(goodInner), isFalse);
        expect(nested.matchesEntry(rootApk), isFalse);
        expect(nested.matchesEntry(goodZip), isTrue);
        expect(nested.matchesEntry(badZip), isFalse);
        expect(nested.matchesEntry(goodInner), isTrue);
        expect(nested.matchesEntry(wrongInner), isFalse);
    });

    test('real artifact ZIP inspection identifies and filters nested APKs', () async {
        final temp = await Directory.systemTemp.createTemp('actions-inspection-test-');
        addTearDown(() => temp.delete(recursive: true));
        final innerA = zipOf({'universal.apk': [1], 'other.apk': [2]});
        final innerB = zipOf({'universal.apk': [3]});
        final outer = File('${temp.path}/artifact.zip');
        await outer.writeAsBytes(zipOf({
            'direct.apk': [4],
            'builds/choice-a.zip': innerA,
            'builds/choice-b.zip': innerB,
            'readme.txt': [5],
        }));

        final entries = await inspectActionsArtifact(outer, temp);
        expect(entries.where((e) => e.isInstallable), hasLength(4));
        const selected = ActionsFileSelection(
            location: ActionsApkLocation.nested,
            zipPattern: 'choice-a', apkPattern: 'universal',
        );
        final matching = entries.where((e) =>
                e.isInstallable && selected.matchesEntry(e)).toList();
        expect(matching, hasLength(1));
        expect(matching.single.path, 'universal.apk');
        expect(matching.single.parentZip, 'builds/choice-a.zip');
        expect(temp.listSync().whereType<File>().map((e) => e.path)
                .where((p) => p.contains('nested-')), isEmpty);
    });

    test('archive preparation extracts only matching ZIP and removes wrong APKs', () async {
        final temp = await Directory.systemTemp.createTemp('actions-prepare-test-');
        addTearDown(() => temp.delete(recursive: true));
        final direct = File('${temp.path}/direct.apk');
        await direct.writeAsBytes([1]);
        final a = File('${temp.path}/builds/choice-a.zip');
        final b = File('${temp.path}/builds/choice-b.zip');
        await a.create(recursive: true);
        await b.create(recursive: true);
        await a.writeAsBytes([2]);
        await b.writeAsBytes([3]);
        final extracted = <String>[];
        const selection = ActionsFileSelection(
            location: ActionsApkLocation.nested,
            zipPattern: 'choice-a', apkPattern: 'universal',
        );

        await prepareActionsArchive(temp, selection: selection,
                extract: (zip, destination) async {
            extracted.add(zip.path);
            await File('${destination.path}/universal.apk').writeAsBytes([4]);
            await File('${destination.path}/other.apk').writeAsBytes([5]);
        });

        expect(await direct.exists(), isFalse);
        expect(extracted, hasLength(1));
        expect(extracted.single.endsWith('choice-a.zip'), isTrue);
        final extractedFiles = temp.listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.contains('actions-zip-'))
                .map((f) => f.path.split(Platform.pathSeparator).last)
                .toList();
        expect(extractedFiles, ['universal.apk']);
    });
}
