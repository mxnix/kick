import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class KickSmoothScrollController extends ScrollController {
  KickSmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    super.onAttach,
    super.onDetach,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _KickSmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class KickSmoothSingleChildScrollView extends StatefulWidget {
  const KickSmoothSingleChildScrollView({
    super.key,
    required this.child,
    this.padding,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  State<KickSmoothSingleChildScrollView> createState() => _KickSmoothSingleChildScrollViewState();
}

class _KickSmoothSingleChildScrollViewState extends State<KickSmoothSingleChildScrollView> {
  late final KickSmoothScrollController _controller = KickSmoothScrollController(
    debugLabel: 'kick-smooth-single-child-scroll-view',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        padding: widget.padding,
        physics: widget.physics,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        child: widget.child,
      ),
    );
  }
}

class KickSmoothListView extends StatefulWidget {
  const KickSmoothListView({
    super.key,
    required this.children,
    this.padding,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  State<KickSmoothListView> createState() => _KickSmoothListViewState();
}

class _KickSmoothListViewState extends State<KickSmoothListView> {
  late final KickSmoothScrollController _controller = KickSmoothScrollController(
    debugLabel: 'kick-smooth-list-view',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      interactive: true,
      child: ListView(
        controller: _controller,
        padding: widget.padding,
        physics: widget.physics,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        children: widget.children,
      ),
    );
  }
}

class KickSmoothCustomScrollView extends StatefulWidget {
  const KickSmoothCustomScrollView({
    super.key,
    required this.slivers,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> slivers;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  State<KickSmoothCustomScrollView> createState() => _KickSmoothCustomScrollViewState();
}

class _KickSmoothCustomScrollViewState extends State<KickSmoothCustomScrollView> {
  late final KickSmoothScrollController _controller = KickSmoothScrollController(
    debugLabel: 'kick-smooth-custom-scroll-view',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      interactive: true,
      child: CustomScrollView(
        controller: _controller,
        physics: widget.physics,
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        slivers: widget.slivers,
      ),
    );
  }
}

class _KickSmoothScrollPosition extends ScrollPositionWithSingleContext {
  _KickSmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double? _pointerScrollTarget;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      _pointerScrollTarget = null;
      goBallistic(0);
      return;
    }

    final targetPixels = math.min(
      math.max((_pointerScrollTarget ?? pixels) + delta, minScrollExtent),
      maxScrollExtent,
    );
    if (targetPixels == pixels && targetPixels == _pointerScrollTarget) {
      return;
    }

    _pointerScrollTarget = targetPixels;
    updateUserScrollDirection(-delta > 0.0 ? ScrollDirection.forward : ScrollDirection.reverse);
    unawaited(
      animateTo(
        targetPixels,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        if ((_pointerScrollTarget ?? targetPixels) == targetPixels) {
          _pointerScrollTarget = null;
        }
      }),
    );
  }

  @override
  void applyUserOffset(double delta) {
    _pointerScrollTarget = null;
    super.applyUserOffset(delta);
  }

  @override
  void jumpTo(double value) {
    _pointerScrollTarget = null;
    super.jumpTo(value);
  }
}
