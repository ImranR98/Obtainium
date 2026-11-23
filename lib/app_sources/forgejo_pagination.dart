import 'dart:convert';

import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/services/http_service.dart';

typedef ForgejoPageRequest = Future<Response> Function(Uri uri);

Future<List<dynamic>> fetchAllForgejoPages(
  Uri baseUri,
  ForgejoPageRequest request, {
  int pageSize = 50,
  int maxPages = 10,
}) async {
  final results = <dynamic>[];
  for (var page = 1; page <= maxPages; page++) {
    final queryParameters = Map<String, String>.from(baseUri.queryParameters)
      ..remove('per_page')
      ..['limit'] = '$pageSize'
      ..['page'] = '$page';
    final res = await request(
      baseUri.replace(queryParameters: queryParameters),
    );
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      throw NoReleasesError();
    }
    results.addAll(decoded);
    if (decoded.length < pageSize) break;
  }
  return results;
}
