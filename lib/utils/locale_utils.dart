import 'package:obtainium/custom_errors.dart';

String lowerCaseIfEnglish(String str) => isEnglish() ? str.toLowerCase() : str;

String lowerCaseUnlessLang(String str, String lang) =>
    currentLanguageCode == lang ? str : str.toLowerCase();
