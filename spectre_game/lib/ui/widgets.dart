import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'theme.dart';

/// Buzlu cam yüzey.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
    this.blur = 16,
    this.tint,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (tint ?? SpectreColors.panelHi).withOpacity(0.62),
                (tint ?? SpectreColors.panel).withOpacity(0.42),
              ],
            ),
            border: border ? Border.all(color: SpectreColors.line) : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Basıldığında yaylanarak küçülen, parlayan düğme.
class PressButton extends StatefulWidget {
  const PressButton({
    super.key,
    required this.onTap,
    required this.child,
    this.color = SpectreColors.accent,
    this.filled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.radius = 16,
    this.glow = true,
    this.tooltip,
  });

  final VoidCallback? onTap;
  final Widget child;
  final Color color;
  final bool filled;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool glow;
  final String? tooltip;

  @override
  State<PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<PressButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final c = widget.color;
    Widget btn = AnimatedScale(
      scale: _down ? 0.93 : (_hover ? 1.03 : 1),
      duration: SpectreMotion.fast,
      curve: SpectreMotion.curve,
      child: AnimatedContainer(
        duration: SpectreMotion.normal,
        curve: SpectreMotion.curve,
        padding: widget.padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: widget.filled && enabled
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(c, Colors.white, 0.18)!, c, Color.lerp(c, Colors.black, 0.22)!],
                  stops: const [0, 0.55, 1],
                )
              : null,
          color: widget.filled ? (enabled ? null : Colors.white10) : Colors.white.withOpacity(_hover ? 0.08 : 0.04),
          border: Border.all(
              color: widget.filled ? Colors.white.withOpacity(0.25) : c.withOpacity(enabled ? 0.55 : 0.2)),
          boxShadow: widget.glow && enabled
              ? [
                  BoxShadow(
                    color: c.withOpacity(_down ? 0.25 : (_hover ? 0.55 : 0.38)),
                    blurRadius: _down ? 8 : 22,
                    spreadRadius: -2,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: widget.filled ? const Color(0xFF021220) : (enabled ? c : SpectreColors.muted),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
          child: IconTheme.merge(
            data: IconThemeData(
                color: widget.filled ? const Color(0xFF021220) : (enabled ? c : SpectreColors.muted),
                size: 20),
            child: widget.child,
          ),
        ),
      ),
    );
    btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        child: Opacity(opacity: enabled ? 1 : 0.55, child: btn),
      ),
    );
    if (widget.tooltip != null) btn = Tooltip(message: widget.tooltip!, child: btn);
    return Semantics(button: true, enabled: enabled, child: btn);
  }
}

/// Oyuncu avatarı: degrade dolgu, baş harfler, VIP halkası ve durum noktası.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.player,
    this.size = 56,
    this.presence,
    this.highlight,
  });

  final Player player;
  final double size;
  final PresenceState? presence;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final c = player.color;
    final ring = highlight ?? (player.isVip ? SpectreColors.gold : Colors.white.withOpacity(0.35));
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: SpectreMotion.normal,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: [ring, ring.withOpacity(0.4), ring]),
              boxShadow: [
                BoxShadow(
                  color: (highlight ?? c).withOpacity(highlight != null ? 0.75 : 0.35),
                  blurRadius: highlight != null ? 22 : 12,
                  spreadRadius: highlight != null ? 2 : -2,
                ),
              ],
            ),
            padding: EdgeInsets.all(size * 0.05),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  colors: [Color.lerp(c, Colors.white, 0.35)!, c, Color.lerp(c, Colors.black, 0.55)!],
                  stops: const [0, 0.55, 1],
                ),
              ),
              child: Center(
                child: Text(
                  player.initials,
                  style: TextStyle(
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
                  ),
                ),
              ),
            ),
          ),
          if (presence != null)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.02,
              child: _PresenceDot(state: presence!, size: size * 0.24),
            ),
          if (player.isVip && size >= 36)
            Positioned(
              top: -size * 0.12,
              left: 0,
              right: 0,
              child: Center(child: Text('👑', style: TextStyle(fontSize: size * 0.26))),
            ),
        ],
      ),
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.state, required this.size});
  final PresenceState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = presenceColor(state);
    return AnimatedContainer(
      duration: SpectreMotion.normal,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: SpectreColors.bg, width: 2),
        boxShadow: [BoxShadow(color: c.withOpacity(0.7), blurRadius: 6)],
      ),
    );
  }
}

Color presenceColor(PresenceState s) => switch (s) {
      PresenceState.online => SpectreColors.green,
      PresenceState.away => SpectreColors.amber,
      PresenceState.spinning => SpectreColors.accent,
      PresenceState.waiting => SpectreColors.cyan,
      PresenceState.chosen => SpectreColors.pink,
      PresenceState.muted => SpectreColors.red,
    };

String presenceLabel(PresenceState s) => switch (s) {
      PresenceState.online => 'Çevrimiçi',
      PresenceState.away => 'Uzakta',
      PresenceState.spinning => 'Çeviriyor',
      PresenceState.waiting => 'Bekliyor',
      PresenceState.chosen => 'Seçildi',
      PresenceState.muted => 'Susturuldu',
    };

/// Uygulama geneli hareketli arka plan: yavaş dönen ışık lekeleri.
class SpectreBackground extends StatefulWidget {
  const SpectreBackground({super.key, required this.child, this.animate = true});
  final Widget child;
  final bool animate;

  @override
  State<SpectreBackground> createState() => _SpectreBackgroundState();
}

class _SpectreBackgroundState extends State<SpectreBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(SpectreBackground old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _BgPainter(_c)),
        ),
        widget.child,
      ],
    );
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07152A), SpectreColors.bg, Color(0xFF040810)],
        ).createShader(r),
    );
    final t = anim.value * 2 * math.pi;
    void blob(double ox, double oy, double rad, Color c) {
      final center = Offset(size.width * ox, size.height * oy);
      canvas.drawCircle(
        center,
        rad,
        Paint()
          ..shader = RadialGradient(colors: [c, c.withOpacity(0)])
              .createShader(Rect.fromCircle(center: center, radius: rad)),
      );
    }

    final m = size.shortestSide;
    blob(0.2 + 0.08 * math.sin(t), 0.18 + 0.05 * math.cos(t), m * 0.7,
        SpectreColors.accent.withOpacity(0.16));
    blob(0.85 + 0.06 * math.cos(t * 1.3), 0.75 + 0.06 * math.sin(t), m * 0.65,
        SpectreColors.pink.withOpacity(0.10));
    blob(0.55 + 0.1 * math.sin(t * 0.7), 1.05, m * 0.8, const Color(0xFF3A5BFF).withOpacity(0.10));
  }

  @override
  bool shouldRepaint(_BgPainter old) => false;
}

/// Basit çubuk grafik (bağımlılıksız).
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values, this.color = SpectreColors.accent, this.height = 140, this.labels});
  final List<num> values;
  final Color color;
  final double height;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: SpectreMotion.slow,
        curve: SpectreMotion.curve,
        builder: (_, v, __) => CustomPaint(
          size: Size.infinite,
          painter: _BarPainter(values, color, v),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.color, this.t);
  final List<num> values;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<num>(0, (a, b) => math.max(a, b)).toDouble();
    final grid = Paint()
      ..color = SpectreColors.line
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const gap = 3.0;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = maxV == 0 ? 0.0 : values[i] / maxV * (size.height - 4) * t;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * (w + gap), size.height - h, w, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withOpacity(0.25)],
          ).createShader(rect.outerRect),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.values != values || old.t != t || old.color != color;
}

/// Gösterge kartı.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = SpectreColors.accent,
    this.hint,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: SpectreMotion.normal,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                          child: c),
                    ),
                    child: Text(
                      value,
                      key: ValueKey(value),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hint != null)
                    Text(hint!, style: const TextStyle(color: SpectreColors.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coin göstergesi.
class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.black.withOpacity(0.3),
        border: Border.all(color: SpectreColors.gold.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(end: coins.toDouble()),
            duration: SpectreMotion.slow,
            curve: SpectreMotion.curve,
            builder: (_, v, __) => Text(
              v.round().toString(),
              style: const TextStyle(fontWeight: FontWeight.w800, color: SpectreColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}
