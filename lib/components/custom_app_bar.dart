import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // Material 3 Expressive large top app bar: shows an oversized title that
    // collapses to a standard bar as the user scrolls. A back button appears
    // automatically when this page is pushed onto the navigator (Add / Import),
    // and is absent for the root shell tabs (which have no route to pop).
    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: true,
      title: Text(title),
    );
  }
}
