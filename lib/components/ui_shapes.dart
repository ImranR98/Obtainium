// Squircle border shapes and positional tile radius helpers.

import 'package:flutter/material.dart';

/// Corner radius for the outer corners of a connected tile run.
const double connectedTileBigRadius = 24;

/// Corner radius for the inner (joined) corners of a connected tile run.
const double connectedTileSmallRadius = 6;

/// Produces connected-tile radii: first tile gets top radius, last gets
/// bottom radius, joined inner edges stay small. M3 Expressive "split list" look.
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

/// The connected-tile positional radius expressed as a squircle border, for use
/// as a [Material.shape] / [Card.shape].
RoundedSuperellipseBorder positionalTileShape({
  required bool isFirst,
  required bool isLast,
}) => RoundedSuperellipseBorder(
  borderRadius: positionalTileRadius(isFirst: isFirst, isLast: isLast),
);
