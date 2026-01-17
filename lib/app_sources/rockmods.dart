import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class RockMods extends AppSource {
  RockMods() {
    name = 'RockMods';
    hosts = ['rockmods.net'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://${getSourceRegex(hosts)}/[^/]+/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      var res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }
      var html = parse(res.body);

      var nameElement = html.querySelector('h1');
      var appName = nameElement?.text ?? standardUrl.split('/').last;
      var appInfoElements = nameElement?.nextElementSibling?.children;
      var appVersion = ((appInfoElements?.length ?? 0) >= 1)
          ? appInfoElements![0].text
          : null;
      var appAuthor = ((appInfoElements?.length ?? 0) >= 2)
          ? appInfoElements![1].text
          : name;
      var releaseDateString = ((appInfoElements?.length ?? 0) >= 3)
          ? appInfoElements![2].text
          : null;
      if (appVersion == null) {
        throw NoVersionError();
      }

      var slugRegex = RegExp(
        '^https?://bot.${getSourceRegex(hosts)}/[^/]+/download.php\\?slug=[^/]+',
        caseSensitive: false,
      );
      var intermediateRegex = RegExp(
        '^https?://download.${getSourceRegex(hosts)}/[^/]+\$',
        caseSensitive: false,
      );

      var slugs = html
          .querySelectorAll('a')
          .where((e) => slugRegex.hasMatch(e.attributes['href'] ?? ''))
          .map((e) => e.attributes['href']!)
          .toList();

      if (slugs.isEmpty) {
        var intermediatePages = html
            .querySelectorAll('a')
            .where(
              (e) => intermediateRegex.hasMatch(e.attributes['href'] ?? ''),
            )
            .toList();

        if (intermediatePages.isNotEmpty) {
          var intermediateFutures = intermediatePages.map((
            intermediatePage,
          ) async {
            var resIntermediate = await sourceRequest(
              intermediatePage.attributes['href']!,
              additionalSettings,
            );
            if (resIntermediate.statusCode != 200) {
              throw getObtainiumHttpError(resIntermediate);
            }
            return parse(resIntermediate.body);
          }).toList();
          final intermediateResults = await Future.wait(intermediateFutures);
          for (final htmlIntermediate in intermediateResults) {
            slugs.addAll(
              htmlIntermediate
                  .querySelectorAll('a')
                  .where((e) => slugRegex.hasMatch(e.attributes['href'] ?? ''))
                  .map((e) => e.attributes['href']!),
            );
          }
        }
      }

      if (slugs.isEmpty) {
        throw NoReleasesError();
      }

      var slugFutures = slugs.map((slugUrl) async {
        var resSlug = await sourceRequest(slugUrl, additionalSettings);
        if (resSlug.statusCode != 200) {
          throw getObtainiumHttpError(resSlug);
        }
        return MapEntry(slugUrl, parse(resSlug.body));
      }).toList();
      final slugResults = await Future.wait(slugFutures);

      List<MapEntry<String, String>> apkUrls = [];

      for (final entry in slugResults) {
        final slugUrl = entry.key;
        final htmlSlug = entry.value;

        var fnPs = htmlSlug.querySelectorAll('p').where((e) {
          return e.text == 'File Name';
        });

        var apkName =
            (fnPs.isNotEmpty ? fnPs.first.nextElementSibling?.text : null) ??
            ('${slugUrl.split('=').last}.apk');

        var dlLink = htmlSlug
            .querySelector('#download-button')
            ?.attributes['href'];

        if (dlLink != null) {
          apkUrls.add(
            MapEntry(
              apkName.trim(),
              Uri.parse(dlLink.trim()).replace(query: '').toString(),
            ),
          );
        }
      }

      if (apkUrls.isEmpty) {
        throw NoAPKError();
      }

      return APKDetails(
        appVersion.trim(),
        apkUrls,
        AppNames('${name.trim()} (${appAuthor.trim()})', appName.trim()),
        releaseDate: releaseDateString != null
            ? DateFormat('MMMM dd, yyyy').tryParse(releaseDateString.trim())
            : null,
      );
    } catch (e) {
      if (e is ObtainiumError) rethrow;
      throw ObtainiumError('RockMods Error: $e');
    }
  }
}
