import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Bulk import source: fetches all starred repos of a GitHub user.
///
/// Paginates through the GitHub API (100 repos per page) and returns each
/// repo's URL, full name, and description. Rate limits are checked per page.
class GitHubStars implements MassAppUrlSource {
  @override
  String name = tr('githubStarredRepos');

  @override
  List<String> requiredArgs = [tr('uname')];

  final GitHub _gh = GitHub();

  Future<Map<String, List<String>>> getOnePageOfUserStarredUrlsWithDescriptions(
    String username,
    int page,
    SettingsProvider sp,
  ) async {
    var resUrl =
        'https://api.github.com/users/$username/starred?per_page=100&page=$page';
    var sourceConfigSettings = await _gh.getSourceConfigValues({}, sp);
    Response res = await _gh.sourceRequest(resUrl, sourceConfigSettings);
    if (res.statusCode == 200) {
      Map<String, List<String>> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body) as List<dynamic>)) {
        var htmlUrl = e['html_url'] as String;
        if ((sourceConfigSettings['GHReqPrefix'] ?? '').isNotEmpty) {
          htmlUrl = _gh.undoGHProxyMod(htmlUrl, sourceConfigSettings);
        }
        urlsWithDescriptions.addAll({
          htmlUrl: [
            e['full_name'] as String,
            e['description'] != null
                ? e['description'] as String
                : tr('noDescription'),
          ],
        });
      }
      return urlsWithDescriptions;
    } else {
      _gh.rateLimitErrorCheck(res);
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<Map<String, List<String>>> getUrlsWithDescriptions(
    List<String> args,
  ) async {
    if (args.length != requiredArgs.length) {
      throw ObtainiumError(tr('wrongArgNum'));
    }
    var sp = SettingsProvider();
    await sp.initializeSettings();
    Map<String, List<String>> urlsWithDescriptions = {};
    var page = 1;
    while (true) {
      var pageUrls = await getOnePageOfUserStarredUrlsWithDescriptions(
        args[0],
        page++,
        sp,
      );
      urlsWithDescriptions.addAll(pageUrls);
      if (pageUrls.length < 100) {
        break;
      }
    }
    return urlsWithDescriptions;
  }
}
