import 'package:obtainium/providers/settings_provider.dart';

String capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

bool isObtainiumVariant(String id) =>
    id == obtainiumId ||
    id == '$obtainiumId.fdroid' ||
    id == '$obtainiumId.debug';
