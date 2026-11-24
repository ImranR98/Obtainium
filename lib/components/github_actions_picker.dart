import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/github_actions.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/services/github_actions_archive_service.dart';
import 'package:obtainium/services/http_service.dart';

Future<List<ActionsArchiveEntry>> _scanActionsZip((String, String) args) =>
        inspectActionsArtifact(File(args.$1), Directory(args.$2));

class GitHubActionsPickerButton extends StatelessWidget {
    const GitHubActionsPickerButton({
        super.key,
        required this.source,
        required this.url,
        required this.settings,
        required this.onSelected,
    });
    final GitHub source;
    final String url;
    final Map<String, dynamic> settings;
    final ValueChanged<Map<String, dynamic>> onSelected;

    @override
    Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.account_tree_outlined),
        label: Text(tr('githubActionsChooseArtifact')),
        onPressed: () async {
            try {
                final selected = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => _GitHubActionsPicker(
                        source: source,
                        url: source.standardizeUrl(url),
                        settings: settings,
                    ),
                );
                if (selected != null && context.mounted) onSelected(selected);
            } catch (err) {
                if (context.mounted) showError(err, context);
            }
        },
    );
}

class _GitHubActionsPicker extends StatefulWidget {
    const _GitHubActionsPicker({
        required this.source,
        required this.url,
        required this.settings,
    });
    final GitHub source;
    final String url;
    final Map<String, dynamic> settings;

    @override
    State<_GitHubActionsPicker> createState() => _GitHubActionsPickerState();
}

class _GitHubActionsPickerState extends State<_GitHubActionsPicker> {
    GitHubActionsApi? _api;
    List<String> _branches = [];
    List<Map<String, dynamic>> _workflows = [];
    List<Map<String, dynamic>> _runs = [];
    List<GitHubActionsBuild> _builds = [];
    List<GitHubActionsBuild> _candidateBuilds = [];
    bool _uploadAmbiguous = false;
    final Map<int, List<ActionsArchiveEntry>> _archiveFiles = {};
    Set<String> _events = {};
    String? _branch;
    String? _workflow;
    String? _artifactName;
    Object? _error;
    bool _loadingSetup = true;
    bool _loadingRuns = false;
    bool _uploadUseRegex = false;
    bool _zipUseRegex = false;
    bool _apkUseRegex = false;
    bool _uploadUseText = false;
    ActionsApkLocation _location = ActionsApkLocation.anywhere;
    int? _loadingArchive;
    String _archiveStage = '';
    double? _archiveProgress;
    int _archiveBytes = 0;
    int _requestSequence = 0;
    int _searchEpoch = 0;
    int? _selectedRunId;
    bool _userPickedRun = false;
    bool _searchingMore = false;
    Timer? _uploadSearchDebounce;
    Future<void> Function()? _cancelArchive;

    final _uploadParts = TextEditingController();
    final _uploadRegex = TextEditingController();
    final _zipParts = TextEditingController();
    final _zipRegex = TextEditingController();
    final _apkParts = TextEditingController();
    final _apkRegex = TextEditingController();

    @override
    void initState() {
        super.initState();
        _events = githubActionsSelectedEvents(widget.settings);
        final oldRegex = widget.settings['githubActionsUseRegex'] == true;
        _uploadUseRegex = widget.settings['githubActionsUploadUseRegex'] as bool? ?? oldRegex;
        _zipUseRegex = widget.settings['githubActionsZipUseRegex'] as bool? ?? oldRegex;
        _apkUseRegex = widget.settings['githubActionsApkUseRegex'] as bool? ?? oldRegex;
        _uploadUseText = widget.settings['githubActionsUploadUseText'] == true;
        _uploadParts.text = widget.settings['githubActionsUploadMatchParts']?.toString() ?? '';
        _uploadRegex.text = widget.settings['githubActionsUploadPattern']?.toString() ?? '';
        _location = ActionsFileSelection.fromSettings(widget.settings).location;
        _zipParts.text = widget.settings['githubActionsZipMatchParts']?.toString() ?? '';
        _zipRegex.text = widget.settings['githubActionsZipPattern']?.toString() ?? '';
        _apkParts.text = widget.settings['githubActionsApkMatchParts']?.toString() ?? '';
        _apkRegex.text = widget.settings['githubActionsApkPattern']?.toString() ?? '';
        unawaited(_loadSetup());
    }

    @override
    void dispose() {
        _uploadSearchDebounce?.cancel();
        final cancel = _cancelArchive;
        _cancelArchive = null;
        cancel?.call();
        _uploadParts.dispose();
        _uploadRegex.dispose();
        _zipParts.dispose();
        _zipRegex.dispose();
        _apkParts.dispose();
        _apkRegex.dispose();
        super.dispose();
    }

    String get _uploadPattern => _uploadUseRegex
            ? _uploadRegex.text.trim()
            : actionsLiteralFilenamePattern(_uploadParts.text.split('\n'));
    String get _zipPattern => _zipUseRegex
            ? _zipRegex.text.trim()
            : actionsLiteralFilenamePattern(_zipParts.text.split('\n'));
    String get _apkPattern => _apkUseRegex
            ? _apkRegex.text.trim()
            : actionsLiteralFilenamePattern(_apkParts.text.split('\n'));

    bool _validRegex(String text) {
        if (text.isEmpty) return true;
        try { RegExp(text); return true; } catch (_) { return false; }
    }

    bool get _validPatterns => _validRegex(_apkPattern) &&
            (_location != ActionsApkLocation.nested || _validRegex(_zipPattern)) &&
            (!_uploadUseText || _validRegex(_uploadPattern));

    bool get _uploadReady => _uploadUseText
            ? _uploadPattern.isNotEmpty && _validRegex(_uploadPattern)
            : _artifactName != null;

    List<Map<String, dynamic>> _matchingUploads(GitHubActionsBuild build) {
        if (!_uploadReady) return [];
        return build.artifacts.where((artifact) => actionsUploadNameMatches(
            artifact['name']?.toString() ?? '',
            useText: _uploadUseText,
            exactName: _artifactName ?? '',
            pattern: _uploadPattern,
        )).toList();
    }

    /// Reevaluate names using cached metadata; never downloads ZIP/APK files.
    void _updateUploadPreview() {
        final selected = <GitHubActionsBuild>[];
        var ambiguous = false;
        for (final build in _candidateBuilds) {
            final count = _matchingUploads(build).length;
            // Update checking stops at the newest unique match. An ambiguous older
            // run must not invalidate a newer, unambiguous update.
            if (count > 1 && selected.isEmpty) {
                ambiguous = true;
                break;
            }
            if (count == 1 && selected.length < 3) selected.add(build);
        }
        _builds = selected;
        _uploadAmbiguous = ambiguous;
        if (!_userPickedRun || !_candidateBuilds.any((b) => b.run['id'] == _selectedRunId)) {
            final preferred = selected.isNotEmpty ? selected.first :
                    _candidateBuilds.firstOrNull;
            _selectedRunId = (preferred?.run['id'] as num?)?.toInt();
        }
    }

    /// Exact-name selection uses names from the newest examined run with uploads.
    List<Map<String, dynamic>> get _availableUploads {
        for (final build in _candidateBuilds) {
            if (build.artifacts.isNotEmpty) return build.artifacts;
        }
        return [];
    }

    GitHubActionsBuild? get _selectedRun {
        for (final build in _candidateBuilds) {
            if (build.run['id'] == _selectedRunId) return build;
        }
        return _candidateBuilds.firstOrNull;
    }

    String _runMatchLabel(GitHubActionsBuild build) {
        final count = _matchingUploads(build).length;
        if (count > 1) return tr('githubActionsRunAmbiguous');
        return count == 1 ? tr('githubActionsRunMatched') :
                tr('githubActionsRunUnmatched');
    }

    /// Keep typing responsive. Fetch more metadata only after editing stops.
    void _onUploadRuleChanged() {
        _uploadSearchDebounce?.cancel();
        final epoch = ++_searchEpoch;
        setState(() {
            _searchingMore = false;
            _updateUploadPreview();
        });
        final seq = _requestSequence;
        _uploadSearchDebounce = Timer(const Duration(milliseconds: 350), () {
            unawaited(_searchMore(seq, epoch));
        });
    }

    /// Search the next ten runs at a time until three unique matches are found,
    /// or the first hundred eligible successful runs have been examined.
    Future<void> _searchMore(int seq, int epoch) async {
        if (_api == null || !_validPatterns || _loadingRuns ||
                (_uploadReady ? (_builds.length >= 3 || _uploadAmbiguous) :
                        _availableUploads.isNotEmpty)) {
            return;
        }
        final maxRuns = _runs.where((run) =>
                githubActionsRunIsEligible(run, _events)).take(100).length;
        if (_candidateBuilds.length >= maxRuns) return;
        setState(() => _searchingMore = true);
        try {
            while (_candidateBuilds.length < maxRuns &&
                    (_uploadReady ? (_builds.length < 3 && !_uploadAmbiguous) :
                            _availableUploads.isEmpty)) {
                final next = await _api!.recentBuildsFromRuns(_runs,
                        allowedEvents: _events, start: _candidateBuilds.length,
                        count: 10);
                if (!mounted || seq != _requestSequence || epoch != _searchEpoch) return;
                if (next.isEmpty) break;
                setState(() {
                    _candidateBuilds.addAll(next);
                    _updateUploadPreview();
                });
            }
        } catch (error) {
            if (mounted && seq == _requestSequence && epoch == _searchEpoch) {
                setState(() => _error = error);
            }
        } finally {
            if (mounted && seq == _requestSequence && epoch == _searchEpoch) {
                setState(() => _searchingMore = false);
            }
        }
    }

    ActionsFileSelection get _selection => ActionsFileSelection(
            location: _location, apkPattern: _apkPattern, zipPattern: _zipPattern);

    // Allow an existing exact-name selection to be preserved when newer
    // runs no longer publish it. Fresh selections still require a match.
    bool get _unchangedSavedExactName => !_uploadUseText &&
            widget.settings['githubActionsUploadUseText'] != true &&
            _artifactName != null && _artifactName!.isNotEmpty &&
            _artifactName == widget.settings['githubActionsArtifactName'];

    bool get _validSelection =>
            _branch != null && _workflow != null && _uploadReady &&
            !_uploadAmbiguous &&
            (_builds.isNotEmpty || _unchangedSavedExactName) && _validPatterns;

    Future<void> _loadSetup() async {
        try {
            final api = await widget.source.actionsApi(widget.url, widget.settings);
            final response = await Future.wait<dynamic>([
                api.defaultBranch(), api.branches(), api.workflows(),
            ]);
            if (!mounted) return;
            final branches = (response[1] as List<Map<String, dynamic>>)
                    .map((e) => e['name']?.toString() ?? '')
                    .where((e) => e.isNotEmpty).toList();
            final workflows = (response[2] as List<Map<String, dynamic>>)
                    .where((e) => e['state'] == 'active').toList();
            final previousBranch = widget.settings['githubActionsBranch']?.toString();
            final previousWorkflow = widget.settings['githubActionsWorkflow']?.toString();
            setState(() {
                _api = api;
                _branches = branches;
                _workflows = workflows;
                _branch = branches.contains(previousBranch)
                        ? previousBranch
                        : branches.contains(response[0]) ? response[0] as String
                                : branches.firstOrNull;
                _workflow = workflows.any((e) => e['id'].toString() == previousWorkflow)
                        ? previousWorkflow : null;
                _loadingSetup = false;
            });
            if (_branch != null && _workflow != null) unawaited(_loadRuns());
        } catch (e) {
            if (mounted) setState(() { _error = e; _loadingSetup = false; });
        }
    }

    Future<void> _loadRuns() async {
        final seq = ++_requestSequence;
        ++_searchEpoch;
        _uploadSearchDebounce?.cancel();
        final branch = _branch, workflow = _workflow;
        final previousArtifact = _artifactName;
        setState(() {
            _loadingRuns = true;
            _searchingMore = false;
            _runs = [];
            _builds = [];
            _candidateBuilds = [];
            _selectedRunId = null;
            _userPickedRun = false;
            _uploadAmbiguous = false;
            _artifactName = null;
            _error = null;
        });
        if (_api == null || branch == null || workflow == null) {
            if (mounted) setState(() => _loadingRuns = false);
            return;
        }
        try {
            final runs = await _api!.workflowRuns(workflow: workflow, branch: branch);
            if (!mounted || seq != _requestSequence) return;
            _runs = runs;
            await _refreshBuilds(seq, preferredName: previousArtifact);
        } catch (e) {
            if (mounted && seq == _requestSequence) {
                setState(() { _error = e; _loadingRuns = false; });
            }
        }
    }

    Future<void> _refreshBuilds(int seq, {String? preferredName}) async {
        if (_api == null) return;
        ++_searchEpoch;
        _uploadSearchDebounce?.cancel();
        setState(() {
            _loadingRuns = true;
            _searchingMore = false;
            _candidateBuilds = [];
            _builds = [];
            _userPickedRun = false;
            _selectedRunId = null;
            _error = null;
        });
        try {
            final builds = await _api!.recentBuildsFromRuns(
                    _runs, allowedEvents: _events, count: 10);
            if (!mounted || seq != _requestSequence) return;
            final firstWithUploads = builds.where((b) => b.artifacts.isNotEmpty).firstOrNull;
            final names = firstWithUploads == null ? <String>[] :
                    firstWithUploads.artifacts.map((e) => e['name']?.toString() ?? '').toList();
            final previous = preferredName ??
                    widget.settings['githubActionsArtifactName']?.toString();
            setState(() {
                _candidateBuilds = builds;
                // A saved exact name must not change just because the latest
                // workflow run published different uploads. Only a deliberate
                // dropdown choice replaces it.
                _artifactName ??= (previous != null && previous.isNotEmpty)
                        ? previous : (names.length == 1 ? names.single : null);
                _updateUploadPreview();
                _loadingRuns = false;
            });
            unawaited(_searchMore(seq, _searchEpoch));
        } catch (e) {
            if (mounted && seq == _requestSequence) {
                setState(() { _error = e; _loadingRuns = false; });
            }
        }
    }

    void _toggleEvent(String event, bool selected) {
        setState(() {
            if (selected) { _events.add(event); } else { _events.remove(event); }
        });
        if (_runs.isNotEmpty) unawaited(_refreshBuilds(++_requestSequence));
    }

    void _setArchiveProgress(String stage, int received, int? total) {
        if (!mounted) return;
        // Limit rebuilds to percentage changes, or roughly 256 KiB with unknown length.
        if (_archiveStage == stage && received > _archiveBytes &&
                (total == null
                        ? received - _archiveBytes < 262144
                        : (received * 100 ~/ total) == (_archiveBytes * 100 ~/ total))) {
            return;
        }
        setState(() {
            _archiveStage = stage;
            _archiveBytes = received;
            _archiveProgress = total == null || total <= 0 ? null
                    : (received / total).clamp(0.0, 1.0);
        });
    }

    Future<void> _viewFiles(Map<String, dynamic> artifact) async {
        final id = (artifact['id'] as num).toInt();
        if (_archiveFiles.containsKey(id) || _loadingArchive != null) return;
        setState(() {
            _loadingArchive = id;
            _archiveStage = tr('githubActionsDownloading');
            _archiveProgress = null;
            _archiveBytes = 0;
            _error = null;
        });
        Directory? directory;
        IOSink? sink;
        StreamSubscription<List<int>>? subscription;
        var cancelled = false;
        try {
            directory = await Directory.systemTemp.createTemp('obtainium-actions-');
            final file = File('${directory.path}/artifact.zip');
            final api = _api!;
            var url = await widget.source.actionsArtifactUrl(
                    widget.url, widget.settings, api, id);

            Future<MapEntry<Uri, http.StreamedResponse>> openStream(String requestedUrl,
                    {bool anonymous = false}) async {
                final modified = await widget.source.generalReqPrefetchModifier(
                        requestedUrl, widget.settings);
                final settings = Map<String, dynamic>.from(widget.settings)
                    ..['url'] = modified
                    ..['skipAuth'] = anonymous;
                final headers = await widget.source.getRequestHeaders(
                        settings, modified, forAPKDownload: true);
                return HttpService().requestStream('GET', headers, settings)
                        .timeout(const Duration(seconds: 40));
            }

            // GitHub redirects authenticated ZIP requests to a signed URL. The
            // shared HTTP service strips credentials on cross-origin redirects.
            _cancelArchive = () async {
                cancelled = true;
                await subscription?.cancel();
            };
            var pair = await openStream(url);
            var response = pair.value;
            if (cancelled || !mounted) {
                await cancelStreamedResponse(response);
                return;
            }
            if (actionsShouldFallbackToNightly(
                    url, response.statusCode, response.headers)) {
                await cancelStreamedResponse(response);
                url = GitHub.nightlyActionsArtifactUrl(widget.url, id);
                pair = await openStream(url, anonymous: true);
                response = pair.value;
                if (cancelled || !mounted) {
                    await cancelStreamedResponse(response);
                    return;
                }
            }
            if (response.statusCode != 200) {
                await cancelStreamedResponse(response);
                throw Exception(tr('githubActionsArchiveFailed'));
            }

            // Stream to disk, never buffer the whole artifact in RAM.
            sink = file.openWrite();
            final contentLength = response.contentLength;
            final int? total = contentLength != null && contentLength > 0
                    ? contentLength : null;
            final done = Completer<void>();
            var received = 0;
            subscription = response.stream.timeout(const Duration(seconds: 45)).listen(
                (data) {
                    sink!.add(data);
                    received += data.length;
                    _setArchiveProgress(tr('githubActionsDownloading'), received, total);
                },
                onError: (Object error, StackTrace trace) {
                    if (!done.isCompleted) done.completeError(error, trace);
                },
                onDone: () { if (!done.isCompleted) done.complete(); },
                cancelOnError: true,
            );
            _cancelArchive = () async {
                cancelled = true;
                await subscription?.cancel();
                if (!done.isCompleted) done.completeError(StateError('Cancelled'));
            };
            await done.future;
            await sink.flush();
            await sink.close();
            sink = null;
            if (cancelled) return;
            if (mounted) setState(() => _cancelArchive = null);
            _setArchiveProgress(tr('githubActionsScanning'), received, null);
            final outerPath = file.path;
            final scratchPath = directory.path;
            // Parse ZIP directory entries off the UI isolate. No APK extraction.
            final paths = await compute(_scanActionsZip, (outerPath, scratchPath));
            if (mounted && !cancelled) setState(() => _archiveFiles[id] = paths);
        } catch (err) {
            if (mounted && !cancelled) setState(() => _error = err);
        } finally {
            await subscription?.cancel();
            if (sink != null) { try { await sink.close(); } catch (_) {} }
            if (directory?.existsSync() == true) {
                await directory!.delete(recursive: true);
            }
            if (mounted) {
                setState(() {
                    _loadingArchive = null; _cancelArchive = null;
                    _archiveProgress = null;
                });
            }
        }
    }

    bool _fileIsSelected(ActionsArchiveEntry entry) =>
            _validPatterns && _selection.matchesEntry(entry);

    Widget _filePreview(List<ActionsArchiveEntry> entries) {
        final count = entries.where((entry) =>
                entry.isInstallable && _fileIsSelected(entry)).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final entry in entries)
                Padding(
                    padding: EdgeInsetsDirectional.only(
                        start: entry.parentZip == null ? 0 : 24, top: 3, bottom: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(_fileIsSelected(entry) ? Icons.check_circle_outline
                                : Icons.remove_circle_outline,
                                color: _fileIsSelected(entry) ? Colors.green : Colors.grey,
                                size: 18),
                        const SizedBox(width: 8),
                        if (entry.isOuterZip) ...[
                            const Icon(Icons.folder_open_outlined, size: 18),
                            const SizedBox(width: 4),
                        ],
                        Expanded(child: Text(entry.path, softWrap: true)),
                    ]),
                ),
            if (_validPatterns)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(count == 1 ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                                color: count == 1 ? Colors.green : null, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(count == 0
                                ? tr('githubActionsNoFileMatches')
                                : count == 1
                                        ? tr('githubActionsOneFileMatch')
                                        : tr('githubActionsMultipleMatches',
                                                args: [count.toString()]), softWrap: true)),
                    ]),
                ),
        ]);
    }

    Widget _runPreview(GitHubActionsBuild build) {
        final matching = _matchingUploads(build);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            if (matching.isEmpty)
                Text(tr('githubActionsUploadMissing')),
            for (final item in matching) ...[
                Text(item['name']?.toString() ?? '', softWrap: true),
                if (!_archiveFiles.containsKey((item['id'] as num).toInt()) &&
                        _loadingArchive != (item['id'] as num).toInt())
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.info_outline, size: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(child: Text(tr('githubActionsFilesNotInspected'),
                                    softWrap: true,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant))),
                        ]),
                    ),
                TextButton.icon(
                    onPressed: _loadingArchive == null
                            ? () => unawaited(_viewFiles(item)) : null,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(_archiveFiles.containsKey((item['id'] as num).toInt())
                            ? tr('githubActionsFilesLoaded') : tr('githubActionsViewFiles')),
                ),
                if (_loadingArchive == (item['id'] as num).toInt()) ...[
                    Text(_archiveStage),
                    if (_archiveBytes > 0)
                        Text('${(_archiveBytes / 1048576).toStringAsFixed(1)} MiB'),
                    LinearProgressIndicator(value: _archiveProgress),
                    TextButton(onPressed: _cancelArchive == null ? null
                                    : () => unawaited(_cancelArchive!()),
                            child: Text(tr('cancel'))),
                ],
                if (_archiveFiles[(item['id'] as num).toInt()] != null)
                    _filePreview(_archiveFiles[(item['id'] as num).toInt()]!),
            ],
        ]);
    }

    @override
    Widget build(BuildContext context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        title: Text(tr('githubActionsChooseArtifact')),
        content: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(context).height * 0.68,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_loadingSetup || _loadingRuns || _searchingMore)
                        const LinearProgressIndicator(),
                    if (_error != null) Text(_error.toString()),
                    if (!_loadingSetup) ...[
                        const SizedBox(height: 8),
                        Text(tr('githubActionsWorkflowSelection'),
                                style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(tr('githubActionsBranch')),
                        DropdownButtonFormField<String>(
                            key: ValueKey('branch-$_branch'), initialValue: _branch,
                            isExpanded: true,
                            items: _branches.map((branch) => DropdownMenuItem(
                                    value: branch, child: Text(branch, softWrap: true))).toList(),
                            onChanged: (name) { setState(() => _branch = name); unawaited(_loadRuns()); },
                        ),
                        const SizedBox(height: 12),
                        Text(tr('githubActionsWorkflow')),
                        DropdownButtonFormField<String>(
                            key: ValueKey('workflow-$_workflow'), initialValue: _workflow,
                            isExpanded: true,
                            itemHeight: null,
                            selectedItemBuilder: (context) => _workflows.map((workflow) =>
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(workflow['name']?.toString() ?? '',
                                                maxLines: 1, softWrap: false,
                                                overflow: TextOverflow.ellipsis),
                                    )).toList(),
                            items: _workflows.map((workflow) => DropdownMenuItem(
                                value: workflow['id'].toString(),
                                child: Text(workflow['name']?.toString() ?? '',
                                        softWrap: true),
                            )).toList(),
                            onChanged: (name) { setState(() => _workflow = name); unawaited(_loadRuns()); },
                        ),
                        const SizedBox(height: 12),
                        Text(tr('githubActionsEvents')),
                        Wrap(spacing: 4, children: [
                            ...githubActionsDefaultEvents, ...githubActionsOptionalEvents,
                        ].map((event) => FilterChip(
                            label: Text(event), selected: _events.contains(event),
                            onSelected: (selected) => _toggleEvent(event, selected),
                        )).toList()),
                        const SizedBox(height: 12),
                        Text(tr('githubActionsUploadSelection'),
                                style: Theme.of(context).textTheme.titleMedium),
                        RadioGroup<bool>(
                            groupValue: _uploadUseText,
                            onChanged: (value) {
                                if (value != null) {
                                    _uploadUseText = value;
                                    _onUploadRuleChanged();
                                }
                            },
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    RadioListTile<bool>(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(tr('githubActionsUploadExact')),
                                        value: false,
                                    ),
                                    RadioListTile<bool>(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(tr('githubActionsUploadText')),
                                        value: true,
                                    ),
                                ],
                            ),
                        ),
                        if (!_uploadUseText) ...[
                            Text(tr('githubActionsArtifact')),
                            DropdownButtonFormField<String>(
                                key: ValueKey('artifact-$_branch-$_workflow-$_artifactName'),
                                hint: Text(tr('githubActionsChooseUpload')),
                                initialValue: _availableUploads.any((a) =>
                                        a['name'] == _artifactName) ? _artifactName : null,
                                isExpanded: true,
                                items: _availableUploads.map((a) => DropdownMenuItem<String>(
                                    value: a['name']?.toString(),
                                    child: Text(a['name']?.toString() ?? '', softWrap: true),
                                )).toList(),
                                onChanged: (name) {
                                    _artifactName = name;
                                    _onUploadRuleChanged();
                                },
                            ),
                            Text(tr('githubActionsUploadHelp'), softWrap: true),
                            if (_artifactName != null &&
                                    !_availableUploads.any((a) => a['name'] == _artifactName)) ...[
                                const SizedBox(height: 8),
                                Card(child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                            Text(tr('githubActionsSavedExactNotListed'), softWrap: true),
                                            const SizedBox(height: 6),
                                            SelectableText(_artifactName!),
                                        ],
                                    ),
                                )),
                            ],
                        ] else ...[
                            Row(children: [
                                Expanded(child: Text(tr(_uploadUseRegex
                                        ? 'githubActionsUploadRegex' : 'githubActionsUploadParts'))),
                                Text(tr('githubActionsUseRegex')),
                                Switch(value: _uploadUseRegex, onChanged: (enabled) {
                                    if (enabled && !_uploadUseRegex && _uploadRegex.text.isEmpty) {
                                        _uploadRegex.text = _uploadPattern;
                                    }
                                    _uploadUseRegex = enabled;
                                    _onUploadRuleChanged();
                                }),
                            ]),
                            TextField(
                                controller: _uploadUseRegex ? _uploadRegex : _uploadParts,
                                minLines: 1, maxLines: _uploadUseRegex ? 1 : 4,
                                onChanged: (_) => _onUploadRuleChanged(),
                            ),
                            Text(tr(_uploadUseRegex ? 'githubActionsUploadRegexHelp'
                                    : 'githubActionsUploadPartsHelp'), softWrap: true),
                            if (_uploadPattern.isEmpty)
                                Text(tr('githubActionsUploadPatternRequired')),
                            if (!_validRegex(_uploadPattern))
                                Text(tr('githubActionsInvalidPattern')),
                        ],
                        // This ONE run selector controls both the visible upload names
                        // (in text mode) and the file-inspection section below.
                        if (_candidateBuilds.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(tr('githubActionsRunChoice')),
                            DropdownButtonFormField<int>(
                                key: ValueKey('selected-run-$_branch-$_workflow-$_selectedRunId'),
                                initialValue: _selectedRunId,
                                isExpanded: true,
                                items: _candidateBuilds.map((build) {
                                    final id = (build.run['id'] as num).toInt();
                                    return DropdownMenuItem<int>(
                                        value: id,
                                        child: Text('${tr('githubActionsRun')} ${build.version} '
                                                '— ${_runMatchLabel(build)}',
                                                overflow: TextOverflow.ellipsis),
                                    );
                                }).toList(),
                                onChanged: (id) => setState(() {
                                    _selectedRunId = id;
                                    _userPickedRun = true;
                                }),
                            ),
                            Text(tr('githubActionsRunChoiceHelp'), softWrap: true),
                            if (!_loadingRuns && !_searchingMore && _uploadReady &&
                                    !_uploadAmbiguous && _builds.isNotEmpty &&
                                    _builds.length < 3) ...[
                                const SizedBox(height: 8),
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Icon(Icons.warning_amber_rounded, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text([
                                        _builds.length == 1
                                                ? tr('githubActionsOneMatchingRun')
                                                : tr('githubActionsTwoMatchingRuns'),
                                        if (!_uploadUseText) tr('githubActionsExactMatchWarning'),
                                    ].join(' '), softWrap: true)),
                                ]),
                            ],
                        ],
                        if (_uploadUseText && _selectedRun != null) ...[
                            const SizedBox(height: 8),
                            Text(tr('githubActionsUploadNamesRecent')),
                            Card(child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                        for (final artifact in _selectedRun!.artifacts)
                                            Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 3),
                                                child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                        Icon(_matchingUploads(_selectedRun!)
                                                                        .contains(artifact)
                                                                ? Icons.check_circle_outline
                                                                : Icons.remove_circle_outline,
                                                                color: _matchingUploads(_selectedRun!)
                                                                                .contains(artifact)
                                                                        ? Colors.green : Colors.grey,
                                                                size: 18),
                                                        const SizedBox(width: 8),
                                                        Expanded(child: Text(
                                                                artifact['name']?.toString() ?? '',
                                                                softWrap: true)),
                                                    ],
                                                ),
                                            ),
                                    ],
                                ),
                            )),
                        ],
                        if (_uploadAmbiguous)
                            Text(tr('githubActionsMultipleUploads')),
                        if (!_loadingRuns && !_searchingMore &&
                                _candidateBuilds.isNotEmpty && _uploadReady &&
                                _builds.isEmpty && !_uploadAmbiguous)
                            Text(tr('githubActionsNoMatchingUploads')),
                        const SizedBox(height: 12),
                        Text(tr('githubActionsFileSelection'),
                                style: Theme.of(context).textTheme.titleMedium),
                        Text(tr('githubActionsFileSelectionHelp'), softWrap: true),
                        const SizedBox(height: 8),
                        Text(tr('githubActionsApkLocation')),
                        DropdownButtonFormField<ActionsApkLocation>(
                            initialValue: _location, isExpanded: true,
                            items: [
                                DropdownMenuItem(value: ActionsApkLocation.anywhere,
                                        child: Text(tr('githubActionsApkAnywhere'))),
                                DropdownMenuItem(value: ActionsApkLocation.direct,
                                        child: Text(tr('githubActionsApkDirect'))),
                                DropdownMenuItem(value: ActionsApkLocation.nested,
                                        child: Text(tr('githubActionsApkNested'))),
                            ],
                            onChanged: (value) {
                                if (value != null) setState(() => _location = value);
                            },
                        ),
                        if (_location == ActionsApkLocation.nested) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                                Expanded(child: Text(tr(_zipUseRegex
                                        ? 'githubActionsZipRegex' : 'githubActionsZipParts'))),
                                Text(tr('githubActionsUseRegex')),
                                Switch(value: _zipUseRegex, onChanged: (enabled) {
                                    if (enabled && !_zipUseRegex && _zipRegex.text.isEmpty) {
                                        _zipRegex.text = _zipPattern;
                                    }
                                    setState(() => _zipUseRegex = enabled);
                                }),
                            ]),
                            TextField(
                                controller: _zipUseRegex ? _zipRegex : _zipParts,
                                minLines: 1, maxLines: _zipUseRegex ? 1 : 4,
                                onChanged: (_) => setState(() {}),
                            ),
                            Text(tr(_zipUseRegex ? 'githubActionsZipRegexHelp'
                                    : 'githubActionsZipHelp'), softWrap: true),
                        ],
                        const SizedBox(height: 16),
                        Row(children: [
                            Expanded(child: Text(tr(_apkUseRegex
                                    ? 'githubActionsApkRegex' : 'githubActionsApkMatchParts'))),
                            Text(tr('githubActionsUseRegex')),
                            Switch(value: _apkUseRegex, onChanged: (enabled) {
                                if (enabled && !_apkUseRegex && _apkRegex.text.isEmpty) {
                                    _apkRegex.text = _apkPattern;
                                }
                                setState(() => _apkUseRegex = enabled);
                            }),
                        ]),
                        TextField(
                            controller: _apkUseRegex ? _apkRegex : _apkParts,
                            minLines: 1, maxLines: _apkUseRegex ? 1 : 3,
                            onChanged: (_) => setState(() {}),
                        ),
                        Text(tr(_apkUseRegex ? 'githubActionsApkRegexHelp'
                                : 'githubActionsApkHelp'), softWrap: true),
                        if (!_validPatterns)
                            Text(tr('githubActionsInvalidPattern')),
                        const SizedBox(height: 16),
                        Text(tr('githubActionsInspectFiles'),
                                style: Theme.of(context).textTheme.titleMedium),
                        Text(tr('githubActionsPreviewHelp'), softWrap: true),
                        if (!_loadingRuns && !_searchingMore && _branch != null &&
                                _workflow != null && _error == null && _candidateBuilds.isEmpty)
                            Text(tr('githubActionsEmptyPreview'), softWrap: true),
                        if (_selectedRun != null) _runPreview(_selectedRun!),
                    ],
                ]),
            ),
        ),
        actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('cancel'))),
            FilledButton(
                onPressed: (_loadingSetup || _loadingRuns || !_validSelection)
                        ? null : () => Navigator.of(context).pop({
                    'githubActionsEnabled': true,
                    'githubActionsBranch': _branch,
                    'githubActionsWorkflow': _workflow,
                    'githubActionsArtifactName': _artifactName,
                    'githubActionsUploadUseText': _uploadUseText,
                    'githubActionsUploadMatchParts': _uploadParts.text,
                    'githubActionsUploadPattern': _uploadPattern,
                    'githubActionsEvents': _events.join(','),
                    'githubActionsApkLocation': _location.name,
                    'githubActionsZipMatchParts': _zipParts.text,
                    'githubActionsZipPattern': _zipPattern,
                    'githubActionsApkMatchParts': _apkParts.text,
                    'githubActionsUploadUseRegex': _uploadUseRegex,
                    'githubActionsZipUseRegex': _zipUseRegex,
                    'githubActionsApkUseRegex': _apkUseRegex,
                    'githubActionsApkPattern': _apkPattern,
                }),
                child: Text(tr('continue')),
            ),
        ],
    );
}
