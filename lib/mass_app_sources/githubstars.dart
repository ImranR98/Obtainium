import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class GitHubStars implements MassAppUrlSource {
  @override
  late String name = 'GitHub Starred Repos';

  @override
  late List<String> requiredArgs = ['Username'];

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
              : 'No description'
        });
      }
      return urlsWithDescriptions;
    } else {
      if (res.headers['x-ratelimit-remaining'] == '0') {
        throw RateLimitError(
            (int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') /
                    60000000)
                .round());
      }

      throw ObtainiumError('Unable to find user\'s starred repos');
    }
  }

  @override
  Future<Map<String, String>> getUrlsWithDescriptions(List<String> args) async {
    if (args.length != requiredArgs.length) {
      throw ObtainiumError('Wrong number of arguments provided');
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
