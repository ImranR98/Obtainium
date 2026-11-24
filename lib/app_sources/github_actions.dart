import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/services/http_service.dart';

/// GitHub upload labels are distinct from the filenames inside a download.
bool actionsArtifactNameMatches(String selected, String name) =>
        selected == name;

/// Plain-text filename portions, one per line, matched literally in order.
String actionsLiteralFilenamePattern(Iterable<String> fragments) => fragments
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(RegExp.escape)
        .join('.*');

final Map<String, RegExp> _compiledPatternCache = {};

RegExp _compilePattern(String pattern) {
    final cached = _compiledPatternCache[pattern];
    if (cached != null) return cached;
    late final RegExp compiled;
    try {
        compiled = RegExp(pattern);
    } on FormatException {
        throw GitHubActionsInvalidPatternError();
    }
    if (_compiledPatternCache.length >= 64) {
        _compiledPatternCache.clear();
    }
    _compiledPatternCache[pattern] = compiled;
    return compiled;
}

bool actionsFileMatches(String pattern, String filename) =>
        pattern.isEmpty || _compilePattern(pattern).hasMatch(filename);

bool actionsShouldFallbackToNightly(
    String url,
    int statusCode,
    Map<String, String> headers,
) {
    if (statusCode != 401 && statusCode != 403) return false;
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == 'nightly.link') return false;
    if (headers['x-ratelimit-remaining'] == '0') return false;
    if (headers.containsKey('retry-after')) return false;
    return true;
}

/// Exact upload-label selection OR an explicit nonempty upload-name pattern.
bool actionsUploadNameMatches(String name, {
    required bool useText,
    required String exactName,
    required String pattern,
}) => useText
        ? pattern.isNotEmpty && actionsFileMatches(pattern, name)
        : exactName.isNotEmpty && actionsArtifactNameMatches(exactName, name);

const githubActionsDefaultEvents = <String>{
    'push', 'schedule', 'workflow_dispatch', 'repository_dispatch',
};
const githubActionsOptionalEvents = <String>{
    'pull_request', 'pull_request_target', 'merge_group', 'workflow_run',
};

Set<String> githubActionsSelectedEvents(Map<String, dynamic> settings) {
    final value = settings['githubActionsEvents']?.toString();
    return value == null
            ? {...githubActionsDefaultEvents}
            : value.split(',').where((s) => s.isNotEmpty).toSet();
}

bool githubActionsRunIsEligible(Map<String, dynamic> run,
        Set<String> allowedEvents) =>
        run['conclusion'] == 'success' &&
        allowedEvents.contains(run['event']?.toString() ?? '');

class GitHubActionsInvalidPatternError extends ObtainiumError {
    GitHubActionsInvalidPatternError() : super('');
    @override
    String get message => tr('githubActionsInvalidPattern');
}

class GitHubActionsRateLimitError extends RateLimitError {
    GitHubActionsRateLimitError(super.remainingMinutes);
    @override
    String toString() => '${super.toString()} ${tr('githubActionsRateLimitHint')}';
}

class GitHubActionsBuild {
    const GitHubActionsBuild(this.run, this.artifacts);
    final Map<String, dynamic> run;
    final List<Map<String, dynamic>> artifacts;
    String get version => '${run['run_number']}.${run['run_attempt'] ?? 1}';
    DateTime? get date => DateTime.tryParse(
            (run['run_started_at'] ?? run['created_at'] ?? '').toString());
}

class GitHubActionsApi {
    GitHubActionsApi(this.repoApiUrl, this.request);
    final String repoApiUrl;
    final Future<Response> Function(String) request;
    bool usedAnonymousFallback = false;
    // One repository-wide artifact request returns up to 100 uploads, each with
    // its workflow_run.id. Avoid one HTTP request per workflow run.
    static const int _maxRepositoryArtifactPages = 10;
    final Map<int, List<Map<String, dynamic>>> _artifactCache = {};
    int _artifactPagesLoaded = 0;
    bool _allArtifactsLoaded = false;
    bool _artifactOrderValid = true;
    bool _artifactQueryInitialized = false;
    String? _artifactNameQuery;
    DateTime? _lastArtifactCreation;

    Future<dynamic> _get(String url) async {
        final res = await request(url);
        if (res.statusCode != 200) throw getObtainiumHttpError(res);
        return jsonDecode(res.body);
    }

    Future<List<Map<String, dynamic>>> _paged(String path, {
        Map<String, String> query = const {},
        String? listKey,
        int maxPages = 10,
    }) async {
        final items = <Map<String, dynamic>>[];
        for (var page = 1; page <= maxPages; page++) {
            final url = Uri.parse('$repoApiUrl$path').replace(queryParameters: {
                ...query, 'per_page': '100', 'page': '$page',
            });
            final response = await _get(url.toString());
            final list = listKey == null ? response : response[listKey];
            if (list is! List) throw NoReleasesError();
            items.addAll(list.whereType<Map<String, dynamic>>());
            if (list.length < 100) break;
        }
        return items;
    }

    Future<String> defaultBranch() async {
        final repo = await _get(repoApiUrl);
        return repo['default_branch']?.toString() ?? 'main';
    }

    Future<List<Map<String, dynamic>>> branches() => _paged('/branches');
    Future<List<Map<String, dynamic>>> workflows() =>
            _paged('/actions/workflows', listKey: 'workflows');

    Future<List<Map<String, dynamic>>> workflowRuns({
        required String workflow,
        required String branch,
    }) async {
        final runs = await _paged(
            '/actions/workflows/${Uri.encodeComponent(workflow)}/runs',
            query: {'branch': branch, 'status': 'success'},
            listKey: 'workflow_runs', maxPages: 1,
        );
        runs.sort((a, b) {
            DateTime date(Map<String, dynamic> run) => DateTime.tryParse(
                    (run['run_started_at'] ?? run['created_at'] ?? '').toString()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            final byDate = date(b).compareTo(date(a));
            if (byDate != 0) return byDate;
            final byNumber = ((b['run_number'] as num?) ?? 0)
                    .compareTo((a['run_number'] as num?) ?? 0);
            if (byNumber != 0) return byNumber;
            return ((b['run_attempt'] as num?) ?? 1)
                    .compareTo((a['run_attempt'] as num?) ?? 1);
        });
        return runs;
    }

    Future<void> _loadArtifactPage({String? exactName}) async {
        if (!_artifactQueryInitialized) {
            _artifactQueryInitialized = true;
            _artifactNameQuery = exactName;
        } else if (_artifactNameQuery != exactName) {
            throw StateError('Cannot change the artifact query on one API client');
        }
        if (_allArtifactsLoaded) return;
        if (_artifactPagesLoaded >= _maxRepositoryArtifactPages) {
            throw ObtainiumError(tr('githubActionsArtifactSearchLimit'));
        }

        final nextPage = _artifactPagesLoaded + 1;
        final uri = Uri.parse('$repoApiUrl/actions/artifacts').replace(
            queryParameters: {
                'per_page': '100',
                'page': '$nextPage',
                'name': ?exactName,
            },
        );
        final result = await _get(uri.toString());
        if (result is! Map || result['artifacts'] is! List) {
            throw NoReleasesError();
        }
        final items = result['artifacts'] as List;
        for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final created = DateTime.tryParse((item['created_at'] ?? '').toString());
            // GitHub returns newest artifacts first. Verify the order before using
            // creation times to conclude all uploads for a run have been seen.
            if (created == null ||
                    (_lastArtifactCreation != null &&
                            created.isAfter(_lastArtifactCreation!))) {
                _artifactOrderValid = false;
            }
            if (created != null) _lastArtifactCreation = created;
            if (item['expired'] == true || item['id'] is! num) continue;
            final workflowRun = item['workflow_run'];
            if (workflowRun is! Map || workflowRun['id'] is! num) continue;
            final runId = (workflowRun['id'] as num).toInt();
            _artifactCache.putIfAbsent(runId, () => []).add(item);
        }
        _artifactPagesLoaded = nextPage;
        final total = (result['total_count'] as num?)?.toInt();
        _allArtifactsLoaded = items.length < 100 ||
                (total != null && _artifactPagesLoaded * 100 >= total);
    }

    /// Fetch repository artifact pages only until all uploads for this group of
    /// runs are covered. Artifacts are created after their workflow runs start;
    /// once the last received artifact predates the oldest run in the group,
    /// older pages cannot contain uploads from that group.
    Future<void> _ensureArtifactsForRuns(
        List<Map<String, dynamic>> runs, {
        String? exactName,
    }) async {
        if (runs.isEmpty) return;
        final dates = runs.map((run) => DateTime.tryParse(
                (run['run_started_at'] ?? run['created_at'] ?? '').toString()))
                .whereType<DateTime>().toList();
        DateTime? oldestRunStart;
        if (dates.length == runs.length) {
            oldestRunStart = dates.reduce((a, b) => a.isBefore(b) ? a : b);
        }
        while (!_allArtifactsLoaded &&
                (oldestRunStart == null || !_artifactOrderValid ||
                        _lastArtifactCreation == null ||
                        !_lastArtifactCreation!.isBefore(oldestRunStart))) {
            await _loadArtifactPage(exactName: exactName);
        }
    }

    /// Inspect the next ten eligible runs, retaining nonmatches for the picker.
    /// The uploads are obtained from repository-wide pages, not per-run calls.
    Future<List<GitHubActionsBuild>> recentBuildsFromRuns(
            List<Map<String, dynamic>> runs, {
        required Set<String> allowedEvents,
        int start = 0,
        int count = 10,
        String? exactName,
    }) async {
        final eligible = runs.where((r) =>
                githubActionsRunIsEligible(r, allowedEvents)).take(100).toList();
        final window = eligible.skip(start).take(count).toList();
        await _ensureArtifactsForRuns(window, exactName: exactName);
        return window.map((run) {
            final id = run['id'];
            final artifacts = id is num
                    ? _artifactCache[id.toInt()] ?? <Map<String, dynamic>>[]
                    : <Map<String, dynamic>>[];
            return GitHubActionsBuild(run, artifacts);
        }).toList();
    }

    /// Find the newest successful run with a unique matching upload.
    /// Exact names are filtered server-side; text/regex matches are local.
    Future<GitHubActionsBuild?> latestBuild({
        required String workflow,
        required String branch,
        required String artifactName,
        required bool uploadUseText,
        required String uploadPattern,
        required Set<String> allowedEvents,
    }) async {
        final runs = await workflowRuns(workflow: workflow, branch: branch);
        final eligible = runs.where((r) =>
                githubActionsRunIsEligible(r, allowedEvents)).take(100).toList();
        final exactName = uploadUseText ? null : artifactName;
        for (var start = 0; start < eligible.length; start += 10) {
            final window = await recentBuildsFromRuns(eligible,
                    allowedEvents: allowedEvents, start: start, count: 10,
                    exactName: exactName);
            for (final build in window) {
                final matches = build.artifacts.where((item) => actionsUploadNameMatches(
                    item['name']?.toString() ?? '',
                    useText: uploadUseText,
                    exactName: artifactName,
                    pattern: uploadPattern,
                )).toList();
                if (matches.length > 1) {
                    throw ObtainiumError(tr('githubActionsMultipleUploads'));
                }
                if (matches.length == 1) return GitHubActionsBuild(build.run, matches);
            }
        }
        return null;
    }
}
