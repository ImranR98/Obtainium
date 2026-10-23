import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/pages/app.dart';

void main() {
  bool shouldProbe({
    bool checkUpdateOnDetailPage = true,
    bool hasDownload = false,
    bool updating = false,
    bool areDownloadsRunning = false,
  }) => shouldProbeDownloadSize(
    checkUpdateOnDetailPage: checkUpdateOnDetailPage,
    hasDownload: hasDownload,
    updating: updating,
    areDownloadsRunning: areDownloadsRunning,
  );

  test('probes only when the detail-page setting is enabled', () {
    expect(shouldProbe(), isTrue);
    expect(shouldProbe(checkUpdateOnDetailPage: false), isFalse);
  });

  test('skips the probe while work is already in progress', () {
    expect(shouldProbe(hasDownload: true), isFalse);
    expect(shouldProbe(updating: true), isFalse);
    expect(shouldProbe(areDownloadsRunning: true), isFalse);
  });
}
