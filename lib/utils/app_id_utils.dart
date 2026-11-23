bool isValidAppId(String appId) {
  if (appId.isEmpty || appId.length > 255) return false;
  if (appId.contains('/') || appId.contains('\\') || appId.contains('\x00')) {
    return false;
  }
  return appId != '.' && appId != '..';
}
