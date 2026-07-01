import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // M3 Expressive large app bar (pinned, does not collapse on scroll).
    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: true,
      title: Text(title),
    );
  }
}
