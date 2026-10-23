# Toolchain Checks Reference

Where each version lives and how to compare it. All paths are relative to the repo root unless
noted; Flutter SDK paths are inside the `.flutter` submodule.

## Repo-side values

| Value | File | How to find it |
| --- | --- | --- |
| Gradle wrapper | `android/gradle/wrapper/gradle-wrapper.properties` | `distributionUrl=...gradle-<version>-all.zip` |
| AGP | `android/settings.gradle.kts` | `id("com.android.application") version "<version>"` |
| Kotlin (KGP) | `android/settings.gradle.kts` | `id("org.jetbrains.kotlin.android") version "<version>"` |
| compileSdk | `android/app/build.gradle.kts` | `compileSdk { version = release(<n>) { minorApiLevel = <m> } }` or `compileSdk = ...` |
| minSdk / targetSdk | `android/app/build.gradle.kts` | `minSdk = ...`, `targetSdk = ...` |
| NDK | `android/app/build.gradle.kts` | `ndkVersion = "<version>"` |
| Java source/target | `android/app/build.gradle.kts` | `sourceCompatibility` / `targetCompatibility` |
| Kotlin jvmTarget | `android/app/build.gradle.kts` | `kotlin { compilerOptions { jvmTarget.set(...) } }` |
| Flutter engine flags | `android/gradle.properties` | `android.builtInKotlin`, `android.newDsl` (added by the Flutter migrator) |
| Desugaring lib | `android/app/build.gradle.kts` | `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:<version>")` |
| JDK runtime | system | `java -version` |
| CI JDK | `.github/workflows/release.yml` | `actions/setup-java` `java-version` |
| Docker JDK/SDK | `docker/Dockerfile` | `JAVA_HOME=...temurin-<n>`, `sdkmanager ...` |
| Flutter submodule | `.flutter` + `bin/cache/flutter.version.json` | `frameworkVersion`, `frameworkRevision`, `dartSdkVersion` |

Note: `android/gradlew`, `android/gradlew.bat`, and `android/gradle/wrapper/gradle-wrapper.jar`
are gitignored; only `gradle-wrapper.properties` is tracked.

## Flutter SDK-side values

| Value | File | Field |
| --- | --- | --- |
| Template Gradle | `.flutter/packages/flutter_tools/lib/src/android/gradle_utils.dart` | `templateDefaultGradleVersion` |
| Max known Gradle | same | `maxKnownAndSupportedGradleVersion` |
| Template AGP | same | `templateAndroidGradlePluginVersion` |
| Max known AGP | same | `maxKnownAndSupportedAgpVersion` |
| Template Kotlin | same | `templateKotlinGradlePluginVersion` |
| Max known KGP | same | `maxKnownAndSupportedKgpVersion` |
| Default compileSdk / minSdk / targetSdk / NDK | same | `compileSdkVersionInt`, `minSdkVersionInt`, `targetSdkVersion`, `ndkVersion` |
| Gradle-plugin `FlutterExtension` defaults | `.flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt` | `compileSdkVersion`, `minSdkVersion`, `targetSdkVersion`, `ndkVersion` |
| Templates used by `flutter create` | `.flutter/packages/flutter_tools/templates/app*/android*.tmpl/` | `settings.gradle.kts.tmpl`, `gradle/wrapper/gradle-wrapper.properties.tmpl`, `app/build.gradle.kts.tmpl` |

The canonical check is `./.flutter/bin/flutter analyze --suggestions`; these files explain the
numbers when the suggestion output is ambiguous.

## Java compatibility (Flutter 3.47.8 SDK)

- `errorJavaMinVersionAndroid` / `warnJavaMinVersionAndroid` = **17.0.0** — Flutter errors below
  Java 17.
- AGP ↔ Java (`_javaAgpCompatList`): AGP **8.0 through the max known (9.2)** requires Java
  **≥ 17** (default 17).
- Gradle ↔ Java minimums (`_javaGradleCompatList`): Java 25–26 needs Gradle ≥ 9.1.0; Java
  24 ≥ 8.14; Java 23 ≥ 8.10; Java 22 ≥ 8.7; Java 21 ≥ 8.4; Java 17 ≥ 7.3. Java 26+ is "newer
  than known" (`oneMajorVersionHigherJavaVersion = '26'`).
- Practical reading for this repo: the compile target stays 17; a runtime JDK of 21 (CI) or 25
  (local) is fine with Gradle 9.x + AGP 9.x. No JDK downgrade is ever needed for these
  versions — only a bump if a future AGP/Gradle raises the floor.

## Deliberate repo deviations (do not "fix" without asking)

As of Flutter 3.47.8 the repo is intentionally ahead of the template:

| Value | Repo | Flutter 3.47.8 template / max known | Why it stays |
| --- | --- | --- | --- |
| Gradle wrapper | 9.4.1 | 9.3.1 / max known 9.3.1 | Ahead; builds fine |
| AGP | 9.2.1 | 9.1.0 / max known 9.2 | `build.gradle.kts` comment: versioned compileSdk requires AGP 9.1+ |
| Kotlin | 2.4.10 | 2.4.0 / max known 2.4.0 | Ahead; builds fine |
| compileSdk | 37 (`release(37) { minorApiLevel = 0 }`) | 36 | Keeps the SDK installed as `android-37.0`, which F-Droid's build server and CI runners expect |
| minSdk | 26 | 24 | Product decision (support floor) |
| NDK | 28.2.13676358 | 28.2.13676358 | Matches |
| targetSdk | `flutter.targetSdkVersion` (36) | 36 | Matches |

Above-max-known values can trigger "newer than known" warnings from Flutter tooling but are not
errors. A future Flutter may raise its known-supported maxima; only then does an ahead value
become a question — and even then, prefer keeping it if the build and
`flutter analyze --suggestions` are clean.

Also intentional: pub dependencies pinned by git commit SHA with TODO notes (do not update them
as part of a routine package pass unless the upstream PR/fork situation changed — check the
notes in `pubspec.yaml`), and the `.flutter` submodule pinning Flutter locally while CI uses
the floating `stable` channel.

## Migration history worth knowing

- `11161084` — "Upgrade Android toolchain for JDK 25 support": Gradle 8.14 → 9.1.0, AGP
  8.11.1 → 9.0.1, Kotlin 2.2.20 → 2.4.10; migrated `kotlinOptions` → `compilerOptions` DSL.
- `f3afcfdc` — "Migrate to Flutter built-in Kotlin and material_ui (#3258)": Flutter warns that
  plugins applying KGP will fail in a future release and 3.50 forces built-in Kotlin; enabled
  `android.builtInKotlin=true`, forked/patch plugins, and moved to the standalone `material_ui`
  package with `dart fix --code=migrate_design_widgets`.
- `6056e248` — "Update packages+Flutter, increment version": the maintainer's historical
  combined pattern (submodule pointer + pubspec.lock + constraint bumps + version bump). This
  skill splits that into two commits and never performs the version bump.
