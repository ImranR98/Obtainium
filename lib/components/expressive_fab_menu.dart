import 'package:flutter/material.dart';

/// A Material 3 Expressive FAB that, when tapped, expands vertically to reveal
/// small action buttons.  Each action slides + fades in with a gentle spring
/// feel, and the FAB rotates 45° (to a close icon).  Tapping the FAB again (or
/// any action) closes the menu.
class ExpressiveFabMenu extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final List<ExpressiveFabMenuAction> actions;

  const ExpressiveFabMenu({
    super.key,
    this.icon = Icons.add,
    this.tooltip,
    required this.actions,
  });

  @override
  State<ExpressiveFabMenu> createState() => _ExpressiveFabMenuState();
}

class ExpressiveFabMenuAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const ExpressiveFabMenuAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
}

class _ExpressiveFabMenuState extends State<ExpressiveFabMenu>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
  }

  void _toggle() {
    if (_open) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() {
      _open = !_open;
    });
  }

  void _close() {
    if (_open) {
      _controller.reverse();
      setState(() => _open = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = 8.0;
    final smallFabSize = 40.0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop tap‑to‑dismiss when open.
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
        // Action buttons — positioned above the main FAB.
        ...widget.actions.asMap().entries.map((entry) {
          final index = entry.key;
          final action = entry.value;
          final offset = index + 1;
          return Positioned(
            bottom: (smallFabSize + spacing) * offset,
            right: 0,
            child: FadeTransition(
              opacity: _controller,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutBack,
                )),
                child: FloatingActionButton.small(
                  heroTag: 'fab_action_${index}_${action.tooltip}',
                  onPressed: () {
                    _close();
                    action.onPressed();
                  },
                  tooltip: action.tooltip,
                  child: Icon(action.icon),
                ),
              ),
            ),
          );
        }),
        // Main FAB.
        AnimatedRotation(
          turns: _open ? 0.125 : 0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton(
            onPressed: _toggle,
            tooltip: widget.tooltip,
            child: Icon(widget.icon),
          ),
        ),
      ],
    );
  }
}
