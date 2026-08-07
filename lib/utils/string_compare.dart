int compareAlphaNumeric(String a, String b) {
  final List<String> aParts = _splitAlphaNumeric(a);
  final List<String> bParts = _splitAlphaNumeric(b);

  for (int i = 0; i < aParts.length && i < bParts.length; i++) {
    final String aPart = aParts[i];
    final String bPart = bParts[i];

    final bool aIsNumber = _isDigit(aPart);
    final bool bIsNumber = _isDigit(bPart);

    if (aIsNumber && bIsNumber) {
      final int? aNumber = int.tryParse(aPart);
      final int? bNumber = int.tryParse(bPart);
      if (aNumber == null || bNumber == null) {
        final int cmp = aPart.compareTo(bPart);
        if (cmp != 0) return cmp;
      } else {
        final int cmp = aNumber.compareTo(bNumber);
        if (cmp != 0) return cmp;
      }
    } else if (!aIsNumber && !bIsNumber) {
      final int cmp = aPart.compareTo(bPart);
      if (cmp != 0) {
        return cmp;
      }
    } else {
      return aIsNumber ? 1 : -1;
    }
  }

  return aParts.length.compareTo(bParts.length);
}

List<String> _splitAlphaNumeric(String s) {
  if (s.isEmpty) return [];
  final List<String> parts = [];
  final StringBuffer sb = StringBuffer();

  bool isNumeric = _isDigit(s[0]);
  sb.write(s[0]);

  for (int i = 1; i < s.length; i++) {
    final bool currentIsNumeric = _isDigit(s[i]);
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

bool _isDigit(String s) {
  if (s.isEmpty) return false;
  return s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
}
