import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // Material 3 Expressive large top app bar: shows an oversized title that
    // collapses to a standard bar as the user scrolls.
    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: false,
      title: Text(title),
    );
  }
}
