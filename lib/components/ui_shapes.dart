import 'package:flutter/material.dart';

/// Corner radius for the outer corners of a connected tile run.
const double connectedTileBigRadius = 24;

/// Corner radius for the inner (joined) corners of a connected tile run.
const double connectedTileSmallRadius = 6;

/// The vertical border radius for one tile within a connected run: the first
/// tile gets a large top radius and the last tile gets a large bottom radius,
/// while the joined inner edges stay small. This produces the Material 3
/// Expressive "split list" look used across settings, forms and the app list.
BorderRadius positionalTileRadius({
  required bool isFirst,
  required bool isLast,
}) {
  return BorderRadius.vertical(
    top: Radius.circular(
      isFirst ? connectedTileBigRadius : connectedTileSmallRadius,
    ),
    bottom: Radius.circular(
      isLast ? connectedTileBigRadius : connectedTileSmallRadius,
    ),
  );
}
