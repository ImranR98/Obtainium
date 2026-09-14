import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Settings inherited from the delegated GitHub implementation that are
/// meaningless for ForgeJo and must never be shown or forwarded.
const List<String> _githubOnlySettingKeys = ['GHReqPrefix', 'checkRepoRename'];

class Codeberg extends AppSource {
  static const String _defaultHost = 'codeberg.org';
  static const String _tokenKey = 'forgejo-creds';
  static const String _tokenHelpUrl =
      'https://forgejo.org/docs/latest/user/api-usage/#authentication';

  final GitHub _gh = GitHub(hostChanged: true);
  Codeberg() {
    name = 'Forgejo (Codeberg)';
    hosts = [_defaultHost];
    canSearch = true;
    includeAdditionalOptsInMainSearch = true;
  }

  /// The ForgeJo access token, stored like GitHub's PAT: globally in
  /// Source-specific settings for codeberg.org, or per-app for overridden
  /// hosts (where the add-app form appends source config items). The label
  /// names Codeberg when the instance is codeberg.org itself.
  @override
  List<GeneratedFormItem> get sourceConfigSettingFormItems => [
    _tokenFormItem(
      isDefaultHost: _isDefaultHost(hosts.isNotEmpty ? hosts[0] : null),
    ),
  ];

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems =>
      _gh.additionalSourceAppSpecificSettingFormItems;

  GeneratedFormTextField _tokenFormItem({
    required bool isDefaultHost,
    String value = '',
  }) => GeneratedFormTextField(
    _tokenKey,
    label: tr(isDefaultHost ? 'codebergTokenLabel' : 'forgejoTokenLabel'),
    password: true,
    required: false,
    value: value,
    helpUrl: _tokenHelpUrl,
  );

  static bool _isDefaultHost(String? host) =>
      host == _defaultHost || host == 'www.$_defaultHost';

  /// Origin of the ForgeJo instance used for a search. Accepts scheme-less
  /// hosts and discards any path/query from the configured URL.
  static Uri searchUriFor(
    String? configuredUrl, {
    String fallbackHost = _defaultHost,
  }) {
    var raw = configuredUrl?.trim() ?? '';
    if (raw.isEmpty) raw = fallbackHost;
    if (!raw.toLowerCase().startsWith('http://') &&
        !raw.toLowerCase().startsWith('https://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ObtainiumError(tr('invalidInput'));
    }
    return uri;
  }

  static String? _tryHost(String url) {
    try {
      return searchUriFor(url).host;
    } catch (_) {
      return null;
    }
  }

  /// Removes GitHub-only settings and resolves the effective token into
  /// GitHub's [github-creds] key so the delegated header logic sends it.
  ///
  /// [getSourceConfigValues] scopes the token by host: codeberg.org uses the
  /// per-app value (if any) and falls back to the global setting, while
  /// overridden hosts only ever see their per-app token.
  Future<Map<String, dynamic>> _requestSettings(
    Map<String, dynamic> settings,
  ) async {
    final cleaned = Map<String, dynamic>.from(settings)
      ..removeWhere((key, _) => _githubOnlySettingKeys.contains(key));
    final settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfig = await getSourceConfigValues(cleaned, settingsProvider);
    var token = sourceConfig[_tokenKey];
    if (token == null || token.isEmpty) {
      // Tokens saved by older versions used GitHub's key directly.
      token = cleaned['github-creds'] as String?;
    }
    if (token != null && token.isNotEmpty) {
      cleaned['github-creds'] = token;
    }
    return cleaned;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async => _gh.getRequestHeaders(
    await _requestSettings(additionalSettings),
    url,
    forAPKDownload: forAPKDownload,
  );

  @override
  List<GeneratedFormItem> get searchQuerySettingFormItems =>
      searchQuerySettingItemsForUrl(hosts.isNotEmpty ? hosts[0] : _defaultHost);

  @override
  List<GeneratedFormItem> searchQuerySettingItemsForUrl(
    String url, {
    SettingsProvider? settingsProvider,
  }) {
    final isDefaultHost = _isDefaultHost(_tryHost(url));
    final savedToken =
        (settingsProvider ?? SettingsProvider()).getSettingString(_tokenKey) ??
        '';
    return [
      _tokenFormItem(
        isDefaultHost: isDefaultHost,
        value: isDefaultHost ? savedToken : '',
      ),
      ..._gh.searchQuerySettingFormItems,
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'(www\.)?',
      pathPattern: r'/[^/]+/[^/]+',
    );
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  @override
  App postProcessApp(App app) {
    if (!app.additionalSettings.keys.any(_githubOnlySettingKeys.contains)) {
      return app;
    }
    return app.copyWith(
      additionalSettings: Map<String, dynamic>.from(app.additionalSettings)
        ..removeWhere((key, _) => _githubOnlySettingKeys.contains(key)),
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      return await _gh.fetchReleaseDetailsWithTagFallback(
        standardUrl,
        await _requestSettings(additionalSettings),
        (bool useTagUrl) async {
          final standardUri = Uri.parse(standardUrl);
          final apiPath =
              '/api/v1/repos${standardUri.path}/${useTagUrl ? 'tags' : 'releases'}';
          return standardUri
              .replace(path: apiPath, queryParameters: {'per_page': '100'})
              .toString();
        },
        null,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final origin = searchUriFor(
      querySettings['url'] as String?,
      fallbackHost: hosts.isNotEmpty ? hosts[0] : _defaultHost,
    );
    final isDefaultHost = _isDefaultHost(origin.host);
    final fieldProvided = querySettings.containsKey(_tokenKey);
    final settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final savedToken = settingsProvider.getSettingString(_tokenKey);
    final enteredToken = (querySettings[_tokenKey] as String?) ?? '';
    final token = isDefaultHost
        ? (fieldProvided ? enteredToken : (savedToken ?? ''))
        : enteredToken;
    // Tokens entered for codeberg.org are persisted; other instances are
    // transient so the codeberg.org token is never reused for a custom host.
    if (isDefaultHost && fieldProvided && enteredToken != (savedToken ?? '')) {
      settingsProvider.setSettingString(_tokenKey, enteredToken);
    }
    final requestSettings = <String, dynamic>{};
    if (token.isNotEmpty) {
      requestSettings['github-creds'] = token;
    }
    return _gh.searchCommon(
      query,
      '${origin.origin}/api/v1/repos/search?q=${Uri.encodeQueryComponent(query)}&limit=100',
      'data',
      querySettings: querySettings,
      additionalSettings: requestSettings,
    );
  }
}
