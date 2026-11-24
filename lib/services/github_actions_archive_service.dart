import 'dart:io';

import 'package:archive/archive.dart' hide ZipFile;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:obtainium/app_sources/github_actions.dart';

enum ActionsApkLocation { anywhere, direct, nested }

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

const _actionsInstallableExtensions = <String>{
    '.apk', '.xapk', '.apkm', '.apks',
};

bool actionsIsInstallableFile(String name) => _actionsInstallableExtensions
        .any(name.toLowerCase().endsWith);

/// Separate ZIP names from APK names, and apply the same rules to the preview
/// and actual extraction. The outer GitHub upload is never a filename target.
class ActionsFileSelection {
    const ActionsFileSelection({this.location = ActionsApkLocation.anywhere,
            this.apkPattern = '', this.zipPattern = ''});

    final ActionsApkLocation location;
    final String apkPattern;
    final String zipPattern;

    factory ActionsFileSelection.fromSettings(Map<String, dynamic> settings) =>
            ActionsFileSelection(
                location: ActionsApkLocation.values.firstWhere(
                    (v) => v.name == settings['githubActionsApkLocation'],
                    orElse: () => ActionsApkLocation.anywhere,
                ),
                apkPattern: settings['githubActionsApkPattern']?.toString() ?? '',
                zipPattern: settings['githubActionsZipPattern']?.toString() ?? '',
            );

    bool allowsZip(String path) => path.toLowerCase().endsWith('.zip') &&
            location != ActionsApkLocation.direct &&
            (location != ActionsApkLocation.nested ||
                    actionsFileMatches(zipPattern, _basename(path)));

    bool matchesApk(String path, {String? parentZip}) =>
            actionsIsInstallableFile(path) &&
            (parentZip == null
                    ? location != ActionsApkLocation.nested
                    : allowsZip(parentZip)) &&
            actionsFileMatches(apkPattern, _basename(path));

    bool matchesEntry(ActionsArchiveEntry entry) => entry.isOuterZip
            ? allowsZip(entry.path)
            : matchesApk(entry.path, parentZip: entry.parentZip);
}

/// The parent ZIP is explicit, not inferred from a fabricated path suffix.
class ActionsArchiveEntry {
    const ActionsArchiveEntry(this.path, {this.parentZip});
    final String path;
    final String? parentZip;
    bool get isOuterZip => parentZip == null && path.toLowerCase().endsWith('.zip');
    bool get isInstallable => actionsIsInstallableFile(path);
}

/// Filter direct APKs and extract only eligible ZIPs. Filter their contents
/// independently. Snapshot outer files so there is no recursive ZIP expansion.
Future<void> prepareActionsArchive(
    Directory contents, {
    required ActionsFileSelection selection,
    Future<void> Function(File, Directory)? extract,
}) async {
    final files = contents.listSync(recursive: true, followLinks: false)
            .whereType<File>().toList();
    for (final file in files) {
        if (actionsIsInstallableFile(file.path)) {
            if (!selection.matchesApk(file.path)) await file.delete();
        } else if (selection.allowsZip(file.path)) {
            // Unique directory prevents collisions with paths already in the upload.
            final destination = await file.parent.createTemp('actions-zip-');
            if (extract != null) {
                await extract(file, destination);
            } else {
                await ZipFile.extractToDirectory(
                    zipFile: file, destinationDir: destination);
            }
            for (final inner in destination.listSync(recursive: true, followLinks: false)
                    .whereType<File>()) {
                if (actionsIsInstallableFile(inner.path) &&
                        !selection.matchesApk(inner.path, parentZip: file.path)) {
                    await inner.delete();
                }
            }
        }
    }
}

/// Inspects ZIP directory entries without extracting APK payloads. For each
/// nested ZIP, only that nested ZIP is streamed to a temporary file so its
/// filename index can be read. APK bytes are never unpacked during setup.
Future<List<ActionsArchiveEntry>> inspectActionsArtifact(
        File outerZip, Directory scratchDirectory) async {
    final entries = <ActionsArchiveEntry>[];
    final input = InputFileStream(outerZip.path);
    try {
        final archive = ZipDecoder().decodeStream(input);
        var zipNumber = 0;
        for (final entry in archive) {
            if (!entry.isFile || entry.isSymbolicLink) continue;
            final name = entry.name.replaceAll('\\', '/');
            entries.add(ActionsArchiveEntry(name));
            if (!name.toLowerCase().endsWith('.zip')) continue;
            final nestedZip = File('${scratchDirectory.path}/nested-${zipNumber++}.zip');
            final output = OutputFileStream(nestedZip.path);
            try {
                // Streams this nested ZIP to disk; no large readBytes()/bodyBytes.
                entry.writeContent(output);
            } finally {
                output.closeSync();
            }
            final nestedInput = InputFileStream(nestedZip.path);
            try {
                final innerArchive = ZipDecoder().decodeStream(nestedInput);
                for (final inside in innerArchive) {
                    if (!inside.isFile || inside.isSymbolicLink) continue;
                    entries.add(ActionsArchiveEntry(
                            inside.name.replaceAll('\\', '/'), parentZip: name));
                }
            } finally {
                nestedInput.closeSync();
                await nestedZip.delete();
            }
        }
    } finally {
        input.closeSync();
    }
    entries.sort((a, b) {
        final group = (a.parentZip ?? a.path).compareTo(b.parentZip ?? b.path);
        if (group != 0) return group;
        if (a.parentZip == null && b.parentZip != null) return -1;
        if (a.parentZip != null && b.parentZip == null) return 1;
        return a.path.compareTo(b.path);
    });
    return entries;
}
