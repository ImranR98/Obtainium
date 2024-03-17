import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/source_provider.dart';

class VLC extends AppSource {
  VLC() {
    hosts = ['videolan.org'];
  }
  get dwUrlBase => 'https://get.${hosts[0]}/vlc-android/';

  @override
  Future<Map<String, String>?> getRequestHeaders(
      Map<String, dynamic> additionalSettings,
      {bool forAPKDownload = false}) async {
    return {
      "User-Agent":
          "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
    };
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    return 'https://${hosts[0]}';
  }

  Future<String?> getLatestVersion(
      String standardUrl, Map<String, dynamic> additionalSettings) async {
    Response res = await sourceRequest(dwUrlBase, additionalSettings);
    if (res.statusCode == 200) {
      var dwLinks = parse(res.data)
          .querySelectorAll('a')
          .where((element) => element.attributes['href'] != 'last/')
          .map((e) => e.attributes['href']?.split('/')[0])
          .toList();
      String? version = dwLinks.isNotEmpty ? dwLinks.last : null;
      if (version == null) {
        throw NoVersionError();
      }
      return version;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res =
        await dio.get('https://www.videolan.org/vlc/download-android.html');
    if (res.statusCode == 200) {
      var dwUrlBase = 'get.videolan.org/vlc-android';
      var dwLinks = parse(res.data)
          .querySelectorAll('a')
          .where((element) =>
              element.attributes['href']?.contains(dwUrlBase) ?? false)
          .toList();
      String? version = dwLinks.isNotEmpty
          ? dwLinks.first.attributes['href']
              ?.split('/')
              .where((s) => s.isNotEmpty)
              .last
          : null;
      if (version == null) {
        throw NoVersionError();
      }
      String? targetUrl = 'https://$dwUrlBase/$version/';
      var apkUrls = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
          .map((e) => '${targetUrl}VLC-Android-$version-$e.apk')
          .toList();
      return APKDetails(
          version, getApkUrlsFromUrls(apkUrls), AppNames('VideoLAN', 'VLC'));
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl, String standardUrl,
      Map<String, dynamic> additionalSettings) async {
    Response res = await sourceRequest(apkUrl, additionalSettings);
    if (res.statusCode == 200) {
      String? apkUrl =
          parse(res.data).querySelector('#alt_link')?.attributes['href'];
      if (apkUrl == null) {
        throw NoAPKError();
      }
      return apkUrl;
    } else if (res.statusCode == 500 &&
        res.data.toLowerCase().indexOf('mirror') > 0) {
      var html = parse(res.data);
      var err = '';
      html.body?.nodes.forEach((element) {
        if (element.text != null) {
          err += '${element.text}\n';
        }
      });
      err = err.trim();
      if (err.isEmpty) {
        err = tr('err');
      }
      throw ObtainiumError(err);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
