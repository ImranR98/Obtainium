import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class GitHubStars implements MassAppUrlSource {
  @override
  late String name = tr('githubStarredRepos');

  @override
  late List<String> requiredArgs = [tr('uname')];

  Future<Map<String, String>> getOnePageOfUserStarredUrlsWithDescriptions(
      String username, int page) async {
    Response res = await get(Uri.parse(
        'https://${await GitHub().getCredentialPrefixIfAny()}api.github.com/users/$username/starred?per_page=100&page=$page'));
    if (res.statusCode == 200) {
      Map<String, String> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body) as List<dynamic>)) {
        urlsWithDescriptions.addAll({
          e['html_url'] as String: e['description'] != null
              ? e['description'] as String
              : tr('noDescription')
        });
      }
      return urlsWithDescriptions;
    } else {
      var gh = GitHub();
      gh.rateLimitErrorCheck(res);
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<Map<String, String>> getUrlsWithDescriptions(List<String> args) async {
    if (args.length != requiredArgs.length) {
      throw ObtainiumError(tr('wrongArgNum'));
    }
    Map<String, String> urlsWithDescriptions = {};
    var page = 1;
    while (true) {
      var pageUrls =
          await getOnePageOfUserStarredUrlsWithDescriptions(args[0], page++);
      urlsWithDescriptions.addAll(pageUrls);
      if (pageUrls.length < 100) {
        break;
      }
    }
    return urlsWithDescriptions;
  }
}
