import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AboutEasterEggOverlay extends StatefulWidget {
  const AboutEasterEggOverlay({super.key, required this.active, this.now});

  final bool active;

  final DateTime Function()? now;

  @override
  State<AboutEasterEggOverlay> createState() => _AboutEasterEggOverlayState();
}

class _AboutEasterEggOverlayState extends State<AboutEasterEggOverlay>
    with SingleTickerProviderStateMixin {
  static const int _maxParticles = 140;
  static const Duration _spawnInterval = Duration(milliseconds: 220);
  static const double _gravityPxPerSec2 = 1500;
  static const double _maxStepSeconds = 1 / 30;

  static const List<String> _funCharacters = <String>[
    '🎉',
    '🎈',
    '🎁',
    '⭐',
    '🌟',
    '✨',
    '🍕',
    '🍩',
    '🍔',
    '🎮',
    '🎲',
    '🚀',
    '💎',
    '🦄',
    '🐱',
    '🐶',
    '🐼',
    '🍓',
    '🍦',
    '🌈',
    '🐧',
    '🐳',
    '🦊',
    '🍿',
    '🥳',
    '👾',
    '🪐',
    '🐙',
    '🦋',
    '🍀',
    '🎂',
    '☕',
    '📦',
    '🛸',
  ];
  static const List<String> _prideCharacters = <String>['🏳️‍🌈'];

  final List<_Particle> _particles = <_Particle>[];
  final Map<int, _Particle> _draggingByPointer = <int, _Particle>{};
  final Map<int, Offset> _pointerLastPosition = <int, Offset>{};
  final Map<int, Offset> _pointerVelocity = <int, Offset>{};
  final Map<String, TextPainter> _painterCache = <String, TextPainter>{};

  late final Ticker _ticker;
  late final List<String> _characterPool;
  final math.Random _random = math.Random();

  Duration _lastTickElapsed = Duration.zero;
  Duration _lastSpawnElapsed = Duration.zero;
  Size _size = Size.zero;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    final now = (widget.now ?? DateTime.now)();
    _characterPool = _isPridePeriod(now) ? _prideCharacters : _funCharacters;
    _ticker = createTicker(_onTick);
    if (widget.active) {
      unawaited(_ticker.start());
    }
  }

  @override
  void didUpdateWidget(covariant AboutEasterEggOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _lastTickElapsed = Duration.zero;
      _lastSpawnElapsed = Duration.zero;
      if (!_ticker.isActive) {
        unawaited(_ticker.start());
      }
    } else if (!widget.active && oldWidget.active) {
      _stopAndReset();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final painter in _painterCache.values) {
      painter.dispose();
    }
    _painterCache.clear();
    super.dispose();
  }

  void _stopAndReset() {
    _ticker.stop();
    _particles.clear();
    _draggingByPointer.clear();
    _pointerLastPosition.clear();
    _pointerVelocity.clear();
  }

  bool _isPridePeriod(DateTime now) {
    return now.month == DateTime.june;
  }

  void _onTick(Duration elapsed) {
    if (_size.isEmpty) {
      return;
    }

    double dt;
    if (_lastTickElapsed == Duration.zero) {
      dt = 0;
      _lastSpawnElapsed = elapsed;
    } else {
      dt = (elapsed - _lastTickElapsed).inMicroseconds / 1e6;
    }
    _lastTickElapsed = elapsed;
    if (dt > _maxStepSeconds) {
      dt = _maxStepSeconds;
    }

    if (_particles.length < _maxParticles && elapsed - _lastSpawnElapsed >= _spawnInterval) {
      _spawnParticle();
      _lastSpawnElapsed = elapsed;
    }

    for (final entry in _draggingByPointer.entries) {
      entry.value.velocity = _pointerVelocity[entry.key] ?? Offset.zero;
    }

    _integrate(dt);
    _resolveCollisions();
    _decayPointerVelocities();

    if (mounted) {
      setState(() {});
    }
  }

  void _integrate(double dt) {
    for (final p in _particles) {
      if (_draggingByPointer.values.contains(p)) {
        continue;
      }
      if (p.resting) {
        continue;
      }

      p.velocity = Offset(p.velocity.dx, p.velocity.dy + _gravityPxPerSec2 * dt);
      p.position += p.velocity * dt;
      p.rotation += p.angularVelocity * dt;

      final radius = p.size / 2;

      if (p.position.dx < radius) {
        p.position = Offset(radius, p.position.dy);
        p.velocity = Offset(-p.velocity.dx * 0.5, p.velocity.dy);
      } else if (p.position.dx > _size.width - radius) {
        p.position = Offset(_size.width - radius, p.position.dy);
        p.velocity = Offset(-p.velocity.dx * 0.5, p.velocity.dy);
      }

      if (p.position.dy + radius > _size.height) {
        p.position = Offset(p.position.dx, _size.height - radius);
        p.velocity = Offset(p.velocity.dx * 0.7, -p.velocity.dy * 0.3);
        p.angularVelocity *= 0.6;
        if (p.velocity.distanceSquared < 25 * 25 && p.velocity.dy.abs() < 25) {
          p.velocity = Offset.zero;
          p.angularVelocity = 0;
          p.resting = true;
        }
      }
    }
  }

  void _resolveCollisions() {
    final draggedSet = _draggingByPointer.values.toSet();
    for (int i = 0; i < _particles.length; i++) {
      final a = _particles[i];
      for (int j = i + 1; j < _particles.length; j++) {
        final b = _particles[j];
        final delta = b.position - a.position;
        final distSq = delta.distanceSquared;
        if (distSq < 0.0001) {
          continue;
        }
        final minDist = (a.size + b.size) / 2 * 0.78;
        if (distSq >= minDist * minDist) {
          continue;
        }

        final dist = math.sqrt(distSq);
        final overlap = minDist - dist;
        final dir = delta / dist;
        final aDragged = draggedSet.contains(a);
        final bDragged = draggedSet.contains(b);

        if (aDragged && !bDragged) {
          b.position += dir * overlap;
          b.resting = false;
        } else if (bDragged && !aDragged) {
          a.position -= dir * overlap;
          a.resting = false;
        } else if (!aDragged && !bDragged) {
          a.position -= dir * (overlap / 2);
          b.position += dir * (overlap / 2);

          final relVel = b.velocity - a.velocity;
          final relSpeed = relVel.dx * dir.dx + relVel.dy * dir.dy;
          if (relSpeed < 0) {
            final impulse = relSpeed * 0.6;
            a.velocity = a.velocity + dir * impulse;
            b.velocity = b.velocity - dir * impulse;
          }

          if (a.resting && !b.resting) {
            a.resting = false;
          }
          if (b.resting && !a.resting) {
            b.resting = false;
          }
        }
      }
    }
  }

  void _decayPointerVelocities() {
    for (final id in _pointerVelocity.keys.toList(growable: false)) {
      _pointerVelocity[id] = _pointerVelocity[id]! * 0.85;
    }
  }

  void _spawnParticle() {
    final char = _characterPool[_random.nextInt(_characterPool.length)];
    final size = 36.0 + _random.nextDouble() * 18;
    final radius = size / 2;
    final x = radius + _random.nextDouble() * (_size.width - size).clamp(0, double.infinity);
    final particle = _Particle(
      id: _nextId++,
      position: Offset(x, -radius - _random.nextDouble() * 80),
      velocity: Offset((_random.nextDouble() - 0.5) * 80, 60 + _random.nextDouble() * 60),
      character: char,
      size: size,
      rotation: (_random.nextDouble() - 0.5) * math.pi,
      angularVelocity: (_random.nextDouble() - 0.5) * 4,
    );
    _particles.add(particle);
  }

  _Particle? _findParticleAt(Offset point) {
    // Iterate from top-most first so the visually highest particle wins.
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      final radius = p.size / 2 + 10;
      if ((p.position - point).distanceSquared <= radius * radius) {
        return p;
      }
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.active || _size.isEmpty) {
      return;
    }
    final particle = _findParticleAt(event.localPosition);
    if (particle == null) {
      return;
    }
    _draggingByPointer[event.pointer] = particle;
    _pointerLastPosition[event.pointer] = event.localPosition;
    _pointerVelocity[event.pointer] = Offset.zero;
    particle.resting = false;
    particle.velocity = Offset.zero;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final particle = _draggingByPointer[event.pointer];
    if (particle == null) {
      return;
    }
    final previous = _pointerLastPosition[event.pointer] ?? event.localPosition;
    _pointerLastPosition[event.pointer] = event.localPosition;
    particle.position = event.localPosition;

    // Approximate finger velocity: blend instant velocity with the previous
    // smoothed value so a flick feels natural without being too jittery.
    final delta = event.localPosition - previous;
    const sampleSeconds = 1 / 60;
    final instantVelocity = delta / sampleSeconds;
    final previousVelocity = _pointerVelocity[event.pointer] ?? Offset.zero;
    _pointerVelocity[event.pointer] = instantVelocity * 0.7 + previousVelocity * 0.3;
  }

  void _onPointerUp(PointerUpEvent event) {
    final particle = _draggingByPointer.remove(event.pointer);
    final velocity = _pointerVelocity.remove(event.pointer) ?? Offset.zero;
    _pointerLastPosition.remove(event.pointer);
    if (particle != null) {
      particle.velocity = Offset(
        velocity.dx.clamp(-2200.0, 2200.0),
        velocity.dy.clamp(-2200.0, 2200.0),
      );
      particle.angularVelocity = (velocity.dx / 220).clamp(-8.0, 8.0);
      particle.resting = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _draggingByPointer.remove(event.pointer);
    _pointerLastPosition.remove(event.pointer);
    _pointerVelocity.remove(event.pointer);
  }

  TextPainter _painterFor(String character, double size) {
    final key = '$character|${size.toStringAsFixed(0)}';
    final cached = _painterCache[key];
    if (cached != null) {
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: character,
        style: TextStyle(fontSize: size, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _painterCache[key] = painter;
    return painter;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (newSize != _size) {
          _size = newSize;
        }
        if (!widget.active) {
          return const SizedBox.shrink();
        }
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: CustomPaint(
            size: newSize,
            isComplex: true,
            willChange: true,
            painter: _ParticlePainter(particles: _particles, painterFor: _painterFor),
          ),
        );
      },
    );
  }
}

class _Particle {
  _Particle({
    required this.id,
    required this.position,
    required this.velocity,
    required this.character,
    required this.size,
    required this.rotation,
    required this.angularVelocity,
  });

  final int id;
  Offset position;
  Offset velocity;
  String character;
  double size;
  double rotation;
  double angularVelocity;
  bool resting = false;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.painterFor});

  final List<_Particle> particles;
  final TextPainter Function(String character, double size) painterFor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, size.width, size.height));
    for (final p in particles) {
      final painter = painterFor(p.character, p.size);
      canvas.save();
      canvas.translate(p.position.dx, p.position.dy);
      if (p.rotation != 0) {
        canvas.rotate(p.rotation);
      }
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
