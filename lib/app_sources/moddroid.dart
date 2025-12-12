import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Moddroid extends AppSource {
  Moddroid() {
    hosts = ['moddroid.com'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    var match = RegExp(r'moddroid\.com/(apps|games)/([^/]+)/([^/]+)').firstMatch(url);
    if (match != null) return 'https://moddroid.com/${match.group(1)}/${match.group(2)}/${match.group(3)}/';
    throw ObtainiumError('Invalid URL');
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl, Map<String, dynamic> additionalSettings) async {
    try {
      var mainRes = await sourceRequest(standardUrl, additionalSettings);
      if (mainRes.statusCode != 200) throw getObtainiumHttpError(mainRes);
      
      var baseUrl = Uri.parse(standardUrl);
      var intermediateUrl = parse(mainRes.body).querySelectorAll('a')
          .map((e) => e.attributes['href'])
          .where((href) => href != null)
          .map((href) => baseUrl.resolve(href!).toString())
          .firstWhere((url) => RegExp(r'moddroid\.com/(apps|games)/.+/[A-Za-z0-9]+/$').hasMatch(url),
              orElse: () => throw NoReleasesError(note: 'No download page found'));

      var intRes = await sourceRequest(intermediateUrl, additionalSettings);
      if (intRes.statusCode != 200) throw getObtainiumHttpError(intRes);

      var apkUrl = parse(intRes.body).querySelectorAll('a')
          .map((e) => e.attributes['href'])
          .firstWhere((href) => href != null && RegExp(r'cdn\.topmongo\.com/.*\.apk$').hasMatch(href),
              orElse: () => throw NoReleasesError(note: 'No APK link found'));

      var version = RegExp(r'\d+\.\d+(\.\d+)?').firstMatch(apkUrl!)?.group(0) ?? apkUrl.hashCode.abs().toString();
      var name = (parse(mainRes.body).querySelector('title')?.text ?? 'App')
          .replaceAll(' MOD APK', '').replaceAll(RegExp(r' v?[\d\.]+.*'), '').trim();

      return APKDetails(version, [MapEntry(apkUrl, apkUrl)], AppNames(name, name));
    } catch (e) {
      if (e is ObtainiumError) rethrow;
      throw ObtainiumError('Moddroid Error: $e');
    }
  }
}
