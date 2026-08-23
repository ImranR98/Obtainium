import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hsluv/hsluv.dart';

final _random = Random();

Color generateRandomLightColor() {
  final randomSeed = _random.nextInt(120);
  final goldenAngle = 180 * (3 - sqrt(5));
  final double hue = randomSeed * goldenAngle;
  final List<double> rgbValuesDbl = Hsluv.hpluvToRgb([hue, 100, 70]);
  final List<int> rgbValues = rgbValuesDbl
      .map((rgb) => (rgb * 255).toInt())
      .toList();
  return Color.fromARGB(255, rgbValues[0], rgbValues[1], rgbValues[2]);
}
