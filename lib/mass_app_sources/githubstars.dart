import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/providers/source_provider.dart';

class GitHubStars implements MassAppSource {
  @override
  late String name = 'GitHub Starred Repos';

  @override
  late List<String> requiredArgs = ['Username'];

  @override
  Future<List<String>> getUrls(List<String> args) async {
    if (args.length != requiredArgs.length) {
      throw 'Wrong number of arguments provided';
    }
    Response res = await get(Uri.parse(
        'https://api.github.com/users/${args[0]}/starred?per_page=100')); //TODO: Make requests for more pages until you run out
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List<dynamic>)
          .map((e) => e['html_url'] as String)
          .toList();
    } else {
      if (res.headers['x-ratelimit-remaining'] == '0') {
        throw 'Rate limit reached - try again in ${(int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') / 60000000).toString()} minutes';
      }

      throw 'Unable to find user\'s starred repos';
    }
  }
}
