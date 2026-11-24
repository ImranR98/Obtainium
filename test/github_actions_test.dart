import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obtainium/app_sources/github_actions.dart';

GitHubActionsApi fakeApi({
    required List<Map<String, dynamic>> runs,
    required List<Map<String, dynamic>> artifacts,
    List<String>? requested,
}) => GitHubActionsApi(
    'https://api.github.com/repos/example/fixture',
    (url) async {
        requested?.add(url);
        final uri = Uri.parse(url);
        if (uri.path.endsWith('/actions/workflows/42/runs')) {
            return http.Response(jsonEncode({'workflow_runs': runs}), 200);
        }
        if (uri.path.endsWith('/actions/artifacts')) {
            final exactName = uri.queryParameters['name'];
            final matches = exactName == null
                    ? artifacts
                    : artifacts.where((a) => a['name'] == exactName).toList();
            return http.Response(jsonEncode({
                'artifacts': matches,
                'total_count': matches.length,
            }), 200);
        }
        throw StateError('Unexpected GitHub API request: $url');
    },
);

Map<String, dynamic> fakeRun(int id, int number, String event) => {
    'id': id,
    'run_number': number,
    'run_attempt': 1,
    'conclusion': 'success',
    'event': event,
    'run_started_at': '2026-11-${number == 2 ? '24' : '23'}T12:00:00Z',
};

Map<String, dynamic> fakeArtifact(int id, int runId, String name) => {
    'id': id,
    'name': name,
    'expired': false,
    'created_at': '2026-11-${runId == 202 ? '24' : '23'}T12:05:00Z',
    'workflow_run': {'id': runId},
};

void main() {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('exact names and literal fragments match independently', () {
        expect(actionsArtifactNameMatches('fixture-fixed-apk', 'fixture-fixed-apk'), isTrue);
        expect(actionsArtifactNameMatches('fixture-fixed-apk', 'fixture-fixed-apks'), isFalse);

        final pattern = actionsLiteralFilenamePattern(['fixture.', 'v2', '.apk']);
        expect(actionsFileMatches(pattern, 'fixture.-release-v2.apk'), isTrue);
        expect(actionsFileMatches(pattern, 'fixtureX-release-v2.apk'), isFalse);
        expect(actionsFileMatches(pattern, 'v2-fixture..apk'), isFalse);
        expect(actionsUploadNameMatches('fixture-changing-2',
                useText: true, exactName: '', pattern: 'fixture-changing-'), isTrue);
        expect(actionsUploadNameMatches('fixture-changing-2',
                useText: false, exactName: 'fixture-changing-1', pattern: ''), isFalse);
        expect(actionsUploadNameMatches('anything',
                useText: true, exactName: '', pattern: ''), isFalse);
    });

    test('malformed stored regex throws a localized application error', () {
        expect(() => actionsFileMatches('(', 'app.apk'),
                throwsA(isA<GitHubActionsInvalidPatternError>()));
        expect(() => actionsUploadNameMatches('any',
                useText: true, exactName: '', pattern: '['),
                throwsA(isA<GitHubActionsInvalidPatternError>()));
    });

    test('trigger selection defaults exclude PR and chained workflow runs', () {
        expect(githubActionsSelectedEvents({}), contains('workflow_dispatch'));
        expect(githubActionsSelectedEvents({}), isNot(contains('workflow_run')));
        expect(githubActionsRunIsEligible(fakeRun(201, 1, 'workflow_dispatch'),
                githubActionsSelectedEvents({})), isTrue);
        expect(githubActionsRunIsEligible(fakeRun(202, 2, 'pull_request'),
                githubActionsSelectedEvents({})), isFalse);
        expect(githubActionsRunIsEligible({
            ...fakeRun(202, 2, 'push'), 'conclusion': 'failure'
        }, githubActionsSelectedEvents({})), isFalse);
        expect(githubActionsRunIsEligible(fakeRun(202, 2, 'workflow_run'),
                githubActionsSelectedEvents({'githubActionsEvents': 'workflow_run'})), isTrue);
    });

    test('nightly.link fallback is only for eligible 401/403 download failures', () {
        const url = 'https://api.github.com/repos/x/y/actions/artifacts/123/zip';
        expect(actionsShouldFallbackToNightly(url, 401, {}), isTrue);
        expect(actionsShouldFallbackToNightly(url, 403, {}), isTrue);
        expect(actionsShouldFallbackToNightly(url, 429, {}), isFalse);
        expect(actionsShouldFallbackToNightly(url, 403,
                {'x-ratelimit-remaining': '0'}), isFalse);
        expect(actionsShouldFallbackToNightly(url, 403,
                {'retry-after': '60'}), isFalse);
        expect(actionsShouldFallbackToNightly(
                'https://nightly.link/x/y/actions/artifacts/123.zip', 403, {}), isFalse);
    });

    test('newest changing artifact is selected and repository artifacts are batched', () async {
        final requests = <String>[];
        final api = fakeApi(
            requested: requests,
            runs: [fakeRun(201, 1, 'workflow_dispatch'),
                    fakeRun(202, 2, 'workflow_dispatch')],
            artifacts: [fakeArtifact(302, 202, 'fixture-changing-2'),
                    fakeArtifact(301, 201, 'fixture-changing-1'),
                    {...fakeArtifact(309, 202, 'fixture-changing-expired'), 'expired': true}],
        );
        final result = await api.latestBuild(
            workflow: '42', branch: 'main', artifactName: '',
            uploadUseText: true, uploadPattern: 'fixture-changing-',
            allowedEvents: githubActionsDefaultEvents,
        );
        expect(result, isNotNull);
        expect(result!.version, '2.1');
        expect(result.artifacts.single['name'], 'fixture-changing-2');
        expect(requests.where((u) => Uri.parse(u).path.endsWith('/actions/artifacts')),
                hasLength(1));
    });

    test('exact upload name falls back to an earlier matching run', () async {
        final requests = <String>[];
        final api = fakeApi(
            requested: requests,
            runs: [fakeRun(201, 1, 'workflow_dispatch'),
                    fakeRun(202, 2, 'workflow_dispatch')],
            artifacts: [fakeArtifact(302, 202, 'fixture-changing-2'),
                    fakeArtifact(301, 201, 'fixture-fixed-apk')],
        );
        final result = await api.latestBuild(
            workflow: '42', branch: 'main', artifactName: 'fixture-fixed-apk',
            uploadUseText: false, uploadPattern: '',
            allowedEvents: githubActionsDefaultEvents,
        );
        expect(result, isNotNull);
        expect(result!.version, '1.1');
        expect(result.artifacts.single['name'], 'fixture-fixed-apk');
        expect(requests.any((u) => Uri.parse(u).queryParameters['name'] ==
                'fixture-fixed-apk'), isTrue);
    });

    test('ambiguous upload pattern matches multiple choices', () {
        final names = ['fixture-choice-a', 'fixture-choice-b', 'unrelated'];
        final matches = names.where((name) => actionsUploadNameMatches(name,
                useText: true, exactName: '', pattern: 'fixture-choice-'));
        expect(matches, hasLength(2));
    });
}
