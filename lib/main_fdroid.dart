// F-Droid flavour entry point — enables reproducible builds by setting isFdroidBuild.

import 'main.dart' as m;

void main() async {
  m.isFdroidBuild = true;
  m.main();
}
