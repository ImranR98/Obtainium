import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class GitHubStars implements MassAppSource {
  @override
  late String name = 'GitHub Starred Repos';

  @override
  late List<String> requiredArgs = ['Username'];

  Future<List<String>> getOnePageOfUserStarredUrls(
      String username, int page) async {
    Response res = await get(Uri.parse(
        'https://api.github.com/users/$username/starred?per_page=100&page=$page'));
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List<dynamic>)
          .map((e) => e['html_url'] as String)
          .toList();
    } else {
      if (res.headers['x-ratelimit-remaining'] == '0') {
        throw RateLimitError(
            (int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') /
                    60000000)
                .round());
      }

      throw 'Unable to find user\'s starred repos';
    }
  }

  @override
  Future<List<String>> getUrls(List<String> args) async {
    if (args.length != requiredArgs.length) {
      throw 'Wrong number of arguments provided';
    }
    List<String> urls = [];
    var page = 1;
    while (true) {
      var pageUrls = await getOnePageOfUserStarredUrls(args[0], page++);
      urls.addAll(pageUrls);
      if (pageUrls.length < 100) {
        break;
      }
    }
    return urls;
  }
}
