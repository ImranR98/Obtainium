import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/app_sources/html.dart';

class Moddroid extends AppSource {
  Moddroid() {
    hosts = ['moddroid.com'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp pattern = RegExp(
        r'https?://(?:www\.)?moddroid\.com/(apps|games)/([^/]+)/([^/]+)/?.*');
    var match = pattern.firstMatch(url);
    
    if (match != null) {
      String type = match.group(1)!;
      String category = match.group(2)!;
      String appName = match.group(3)!;
      return 'https://moddroid.com/$type/$category/$appName/';
    }
    
    throw ObtainiumError('Invalid Moddroid URL format');
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      Response mainPageRes = await sourceRequest(standardUrl, additionalSettings);
      if (mainPageRes.statusCode != 200) {
        throw getObtainiumHttpError(mainPageRes);
      }
      
      var mainHtml = parse(mainPageRes.body);
      
      var allLinks = mainHtml.querySelectorAll('a');
      String? intermediateUrl;
      
      for (var link in allLinks) {
        var href = link.attributes['href'];
        if (href != null) {
          var absoluteUrl = ensureAbsoluteUrl(href, Uri.parse(standardUrl));
          
          if (absoluteUrl.startsWith(standardUrl) && 
              absoluteUrl.length > standardUrl.length &&
              RegExp(r'/[A-Za-z0-9]+/$').hasMatch(absoluteUrl) &&
              !absoluteUrl.contains('dl.lingmod.top')) {
            intermediateUrl = absoluteUrl;
            break;
          }
        }
      }
      
      if (intermediateUrl == null) {
        throw NoReleasesError(note: 'Could not find download page');
      }
      
      Response intermediateRes = await sourceRequest(intermediateUrl, additionalSettings);
      if (intermediateRes.statusCode != 200) {
        throw getObtainiumHttpError(intermediateRes);
      }
      
      var intermediateHtml = parse(intermediateRes.body);
      
      String? apkUrl;
      for (var link in intermediateHtml.querySelectorAll('a')) {
        var href = link.attributes['href'];
        if (href != null && 
            href.contains('cdn.topmongo.com') && 
            href.endsWith('.apk')) {
          apkUrl = href;
          break;
        }
      }
      
      if (apkUrl == null) {
        throw NoReleasesError(note: 'Could not find APK download link');
      }
      
      String? version;
      var title = mainHtml.querySelector('title')?.text ?? '';
      var versionMatch = RegExp(r'v?(\d+[\d\.\-_]+\d+)').firstMatch(title);
      if (versionMatch != null) {
        version = versionMatch.group(1);
      }
      
      version ??= RegExp(r'[\d\.]+').firstMatch(apkUrl)?.group(0);
      version ??= apkUrl.hashCode.abs().toString();
      
      var appNameMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(mainPageRes.body);
      String appName = 'Moddroid App';
      if (appNameMatch != null) {
        appName = appNameMatch.group(1)!
            .replaceAll(' MOD APK', '')
            .replaceAll(RegExp(r' v?[\d\.]+.*'), '')
            .trim();
      }
      
      var uri = Uri.parse(apkUrl);
      var fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'app.apk';
      
      return APKDetails(
        version,
        [MapEntry('${apkUrl.hashCode}-$fileName', apkUrl)],
        AppNames(appName, appName),
      );
      
    } catch (e) {
      if (e is ObtainiumError) {
        rethrow;
      }
      throw ObtainiumError('Failed to get Moddroid app details: $e');
    }
  }
}
