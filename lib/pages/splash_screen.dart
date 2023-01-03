import 'package:another_flutter_splash_screen/another_flutter_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/pages/home.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SettingsProvider settingsProvider = context.watch<SettingsProvider>();

    return FlutterSplashScreen.fadeIn(
      // backgroundColor: Colors.white,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: settingsProvider.theme == ThemeSettings.light
            ? [
                const Color(0xffECE3F7),
                const Color(0xffEDE1F7),
              ]
            : [
                const Color(0xff131c08),
                const Color(0xff121e08),
              ],
      ),
      duration: const Duration(milliseconds: 2000),
      fadeInAnimationDuration: const Duration(milliseconds: 1500),
      animationCurve: Curves.easeIn,
      fadeInChildWidget: SizedBox(
        height: 300,
        width: 300,
        child: Image.asset("assets/graphics/icon.png"),
      ),
      defaultNextScreen: const HomePage(),
    );
  }
}
