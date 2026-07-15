// F-Droid flavour entry point — enables reproducible builds.
import 'package:obtainium/app_distribution.dart';

import 'main.dart' as m;

void main() async {
  AppDistribution.fdroid = true;
  m.main();
}
