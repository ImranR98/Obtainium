import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) {
  try {
    Uri.parse(ambiguousUrl).origin;
    return ambiguousUrl;
  } catch (err) {
    // is relative
  }
  var currPathSegments = referenceAbsoluteUrl.path
      .split('/')
      .where((element) => element.trim().isNotEmpty)
      .toList();
  if (ambiguousUrl.startsWith('/') || currPathSegments.isEmpty) {
    return '${referenceAbsoluteUrl.origin}/$ambiguousUrl';
  } else if (ambiguousUrl.split('/').length == 1) {
    return '${referenceAbsoluteUrl.origin}/${currPathSegments.join('/')}/$ambiguousUrl';
  } else {
    return '${referenceAbsoluteUrl.origin}/${currPathSegments.sublist(0, currPathSegments.length - 1).join('/')}/$ambiguousUrl';
  }
}

int compareAlphaNumeric(String a, String b) {
  List<String> aParts = _splitAlphaNumeric(a);
  List<String> bParts = _splitAlphaNumeric(b);

  for (int i = 0; i < aParts.length && i < bParts.length; i++) {
    String aPart = aParts[i];
    String bPart = bParts[i];

    bool aIsNumber = _isNumeric(aPart);
    bool bIsNumber = _isNumeric(bPart);

    if (aIsNumber && bIsNumber) {
      int aNumber = int.parse(aPart);
      int bNumber = int.parse(bPart);
      int cmp = aNumber.compareTo(bNumber);
      if (cmp != 0) {
        return cmp;
      }
    } else if (!aIsNumber && !bIsNumber) {
      int cmp = aPart.compareTo(bPart);
      if (cmp != 0) {
        return cmp;
      }
    } else {
      // Alphanumeric strings come before numeric strings
      return aIsNumber ? 1 : -1;
    }
  }

  return aParts.length.compareTo(bParts.length);
}

List<String> _splitAlphaNumeric(String s) {
  List<String> parts = [];
  StringBuffer sb = StringBuffer();

  bool isNumeric = _isNumeric(s[0]);
  sb.write(s[0]);

  for (int i = 1; i < s.length; i++) {
    bool currentIsNumeric = _isNumeric(s[i]);
    if (currentIsNumeric == isNumeric) {
      sb.write(s[i]);
    } else {
      parts.add(sb.toString());
      sb.clear();
      sb.write(s[i]);
      isNumeric = currentIsNumeric;
    }
  }

  parts.add(sb.toString());

  return parts;
}

bool _isNumeric(String s) {
  return s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
}

class HTML extends AppSource {
  HTML() {
    overrideEligible = true;
  }

  @override
  // TODO: implement requestHeaders choice, hardcoded for now
  Map<String, String>? get requestHeaders => {
        "User-Agent":
            "Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
      };

  @override
  String sourceSpecificStandardizeURL(String url) {
    return url;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var uri = Uri.parse(standardUrl);
    Response res = await sourceRequest(standardUrl);
    if (res.statusCode == 200) {
      List<String> links = parse(res.body)
          .querySelectorAll('a')
          .map((element) => element.attributes['href'] ?? '')
          .where((element) =>
              Uri.parse(element).path.toLowerCase().endsWith('.apk'))
          .toList();
      links.sort(
          (a, b) => compareAlphaNumeric(a.split('/').last, b.split('/').last));
      if (additionalSettings['apkFilterRegEx'] != null) {
        var reg = RegExp(additionalSettings['apkFilterRegEx']);
        links = links.where((element) => reg.hasMatch(element)).toList();
      }
      if (links.isEmpty) {
        throw NoReleasesError();
      }
      var rel = links.last;
      var apkName = rel.split('/').last;
      var version = apkName.substring(0, apkName.length - 4);
      List<String> apkUrls =
          [rel].map((e) => ensureAbsoluteUrl(e, uri)).toList();
      return APKDetails(
          version, getApkUrlsFromUrls(apkUrls), AppNames(uri.host, tr('app')));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
