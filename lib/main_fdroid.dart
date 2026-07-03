// F-Droid flavour entry point — enables reproducible builds by setting isFdroidBuild.

import 'main.dart' as m;

void main() {
  m.isFdroidBuild = true;
  m.main();
}
