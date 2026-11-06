import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Masa temaları (renk aileleri). Hepsi SPECTRE'nin kendi paleti.
class TableTheme {
  const TableTheme(this.name, this.primary, this.secondary, this.floor);
  final String name;
  final Color primary;
  final Color secondary;
  final Color floor;

  static const all = [
    TableTheme('Electric', SpectreColors.accent, Color(0xFF3A5BFF), Color(0xFF0B2236)),
    TableTheme('Aurora', Color(0xFF7CF5C4), Color(0xFF2FB7FF), Color(0xFF082A2A)),
    TableTheme('Velvet', SpectreColors.pink, Color(0xFF8B5CFF), Color(0xFF26102A)),
    TableTheme('Gold', SpectreColors.gold, Color(0xFFFF8F6B), Color(0xFF2A1E0B)),
  ];
}

/// Masa zemini: katmanlı ışık halkaları, 12 koltuk işareti ve dönen ışık süpürmesi.
class TableFloorPainter extends CustomPainter {
  TableFloorPainter({
    required this.theme,
    required this.time,
    required this.seatCount,
    required this.activeSeat,
    required this.targetSeat,
    required this.light,
  });

  final TableTheme theme;
  final double time; // saniye
  final int seatCount;
  final int? activeSeat;
  final int? targetSeat;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Dış hale
    canvas.drawCircle(
      c,
      r * 0.98,
      Paint()
        ..shader = RadialGradient(
          colors: [theme.primary.withOpacity(0.20), theme.primary.withOpacity(0)],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Platform
    final plat = Rect.fromCircle(center: c, radius: r * 0.62);
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.35),
          colors: [
            Color.lerp(theme.floor, Colors.white, 0.10)!,
            theme.floor,
            Color.lerp(theme.floor, Colors.black, 0.6)!,
          ],
          stops: const [0, 0.6, 1],
        ).createShader(plat),
    );

    // İç doku: ince eş merkezli çizgiler
    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 5; i++) {
      rings.color = Colors.white.withOpacity(0.025 + i * 0.006);
      canvas.drawCircle(c, r * 0.62 * i / 6, rings);
    }

    // Dönen ışık süpürmesi
    if (!light) {
      final sweep = SweepGradient(
        transform: GradientRotation(time * 0.6),
        colors: [
          theme.primary.withOpacity(0),
          theme.primary.withOpacity(0.18),
          theme.primary.withOpacity(0),
          theme.secondary.withOpacity(0.12),
          theme.primary.withOpacity(0),
        ],
        stops: const [0, 0.12, 0.3, 0.62, 0.85],
      );
      canvas.drawCircle(c, r * 0.62, Paint()..shader = sweep.createShader(plat));
    }

    // Parlak kenar
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.018
        ..shader = SweepGradient(
          transform: GradientRotation(-time * 0.25),
          colors: [theme.primary, theme.secondary, theme.primary.withOpacity(0.4), theme.primary],
        ).createShader(plat),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = theme.primary.withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Koltuk işaretleri + aktif/hedef ışın
    for (var i = 0; i < seatCount; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / seatCount;
      final dir = Offset(math.cos(a), math.sin(a));
      final p1 = c + dir * r * 0.56;
      final p2 = c + dir * r * 0.66;
      final isActive = i == activeSeat;
      final isTarget = i == targetSeat;
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = isActive || isTarget ? 4 : 2
          ..color = isTarget
              ? SpectreColors.pink
              : isActive
                  ? theme.primary
                  : Colors.white.withOpacity(0.18),
      );
      if (isTarget) {
        final beam = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo((c + Offset.fromDirection(a - 0.12, r * 0.6)).dx,
              (c + Offset.fromDirection(a - 0.12, r * 0.6)).dy)
          ..lineTo((c + Offset.fromDirection(a + 0.12, r * 0.6)).dx,
              (c + Offset.fromDirection(a + 0.12, r * 0.6)).dy)
          ..close();
        final pulse = 0.5 + 0.5 * math.sin(time * 6);
        canvas.drawPath(
          beam,
          Paint()
            ..shader = RadialGradient(colors: [
              SpectreColors.pink.withOpacity(0.0),
              SpectreColors.pink.withOpacity(0.18 + 0.12 * pulse),
            ]).createShader(Rect.fromCircle(center: c, radius: r * 0.6)),
        );
      }
    }

    // Merkez kaidesi
    canvas.drawCircle(
      c,
      r * 0.11,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withOpacity(0.18),
          theme.primary.withOpacity(0.08),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 0.11)),
    );
  }

  @override
  bool shouldRepaint(TableFloorPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.activeSeat != activeSeat ||
      oldDelegate.targetSeat != targetSeat || oldDelegate.theme != theme || oldDelegate.light != light;
}

/// SPECTRE şişesi: tamamen vektörel, cam efektli.
/// Ucu (boyun) [rotation] = 0 iken yukarı bakar.
class BottlePainter extends CustomPainter {
  BottlePainter({required this.tint, required this.glow});
  final Color tint;
  final double glow; // 0..1 (dönerken parlar)

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Gölge
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + w * 0.06, h * 0.56), width: w * 0.62, height: h * 0.82),
      Paint()
        ..color = Colors.black.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final body = Path()
      ..moveTo(cx - w * 0.07, h * 0.02) // ağız
      ..lineTo(cx + w * 0.07, h * 0.02)
      ..lineTo(cx + w * 0.075, h * 0.30)
      ..cubicTo(cx + w * 0.09, h * 0.40, cx + w * 0.28, h * 0.42, cx + w * 0.28, h * 0.55)
      ..lineTo(cx + w * 0.28, h * 0.92)
      ..quadraticBezierTo(cx + w * 0.28, h * 0.99, cx + w * 0.20, h * 0.99)
      ..lineTo(cx - w * 0.20, h * 0.99)
      ..quadraticBezierTo(cx - w * 0.28, h * 0.99, cx - w * 0.28, h * 0.92)
      ..lineTo(cx - w * 0.28, h * 0.55)
      ..cubicTo(cx - w * 0.28, h * 0.42, cx - w * 0.09, h * 0.40, cx - w * 0.075, h * 0.30)
      ..close();

    if (glow > 0) {
      canvas.drawPath(
        body,
        Paint()
          ..color = tint.withOpacity(0.55 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * glow + 2),
      );
    }

    final rect = Offset.zero & size;
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(tint, Colors.black, 0.55)!,
            Color.lerp(tint, Colors.black, 0.15)!,
            Color.lerp(tint, Colors.white, 0.25)!,
            Color.lerp(tint, Colors.black, 0.35)!,
          ],
          stops: const [0, 0.35, 0.55, 1],
        ).createShader(rect),
    );

    // Sıvı seviyesi
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      Rect.fromLTRB(0, h * 0.62, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withOpacity(0.35), Color.lerp(tint, Colors.black, 0.6)!.withOpacity(0.8)],
        ).createShader(rect),
    );
    canvas.restore();

    // Etiket
    final label = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, h * 0.74), width: w * 0.46, height: h * 0.16),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(label, Paint()..color = Colors.white.withOpacity(0.88));
    final tp = TextPainter(
      text: TextSpan(
        text: 'S',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w900,
          fontSize: h * 0.11,
          color: Color.lerp(tint, Colors.black, 0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, h * 0.74 - tp.height / 2));

    // Cam parlaması
    final shine = Path()
      ..moveTo(cx - w * 0.17, h * 0.52)
      ..quadraticBezierTo(cx - w * 0.21, h * 0.62, cx - w * 0.2, h * 0.9)
      ..lineTo(cx - w * 0.14, h * 0.9)
      ..quadraticBezierTo(cx - w * 0.15, h * 0.62, cx - w * 0.11, h * 0.5)
      ..close();
    canvas.drawPath(shine, Paint()..color = Colors.white.withOpacity(0.28));
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.04, h * 0.06, w * 0.025, h * 0.22),
      Paint()..color = Colors.white.withOpacity(0.3),
    );

    // Kapak halkası
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w * 0.085, 0, w * 0.17, h * 0.05),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = SpectreColors.gold,
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(BottlePainter oldDelegate) => oldDelegate.tint != tint || oldDelegate.glow != glow;
}

/// Koltuğun etrafında süre halkası.
class TimerRingPainter extends CustomPainter {
  TimerRingPainter({required this.progress, required this.color});
  final double progress; // 0..1 (kalan)
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.1),
    );
    final c = progress < 0.25 ? SpectreColors.red : color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.5
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(TimerRingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Kare masa zemini: merkezde yumuşak ışık, hedefe doğru ışın.
class SquareFloorPainter extends CustomPainter {
  SquareFloorPainter({required this.theme, required this.center, required this.target, required this.time});
  final TableTheme theme;
  final Offset center;
  final Offset? target;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    // --- Masa tablası: koltukların ortasında metal çerçeveli koyu cam ---
    final board = RRect.fromRectAndRadius(
      Rect.fromLTRB(size.width * 0.235, size.height * 0.255, size.width * 0.765, size.height * 0.695),
      Radius.circular(size.width * 0.05),
    );
    final bRect = board.outerRect;
    // gölge
    canvas.drawRRect(
      board.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    // cam yüzey
    canvas.drawRRect(
      board,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFF0D2236), theme.primary, 0.06)!,
            const Color(0xFF07131F),
            const Color(0xFF050D16),
          ],
        ).createShader(bRect),
    );
    // çapraz parlama
    canvas.save();
    canvas.clipRRect(board);
    canvas.drawRect(
      bRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0), Colors.white.withOpacity(0.025)],
          stops: const [0, 0.45, 1],
        ).createShader(bRect),
    );
    // ince yatay çizgiler (fırçalanmış metal dokusu)
    final lines = Paint()
      ..color = Colors.white.withOpacity(0.018)
      ..strokeWidth = 1;
    for (var y = bRect.top + 6; y < bRect.bottom; y += 6) {
      canvas.drawLine(Offset(bRect.left, y), Offset(bRect.right, y), lines);
    }
    canvas.restore();
    // metalik çerçeve
    canvas.drawRRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF6FF), Color(0xFF7FA9C8), Color(0xFF2E5371), Color(0xFFBFDDF2), Color(0xFF5E86A6)],
          stops: [0, 0.25, 0.5, 0.75, 1],
        ).createShader(bRect),
    );
    // iç ince çizgi
    canvas.drawRRect(
      board.deflate(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.primary.withOpacity(0.22),
    );

    final r = size.shortestSide * 0.42;
    // Merkez ışığı (v39: radial-gradient #0a1e2a 8% → saydam 56%)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          Color.lerp(const Color(0xFF0A1E2A), theme.primary, 0.12)!.withOpacity(0.95),
          theme.primary.withOpacity(0.05),
          Colors.transparent,
        ], stops: const [0.08, 0.6, 1]).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    final t = target;
    if (t != null) {
      final dir = (t - center);
      final len = dir.distance;
      final n = Offset(-dir.dy, dir.dx) / len;
      final w = size.shortestSide * 0.06;
      final beam = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(t.dx + n.dx * w, t.dy + n.dy * w)
        ..lineTo(t.dx - n.dx * w, t.dy - n.dy * w)
        ..close();
      final glow = 0.5 + 0.5 * math.sin(time * 6);
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(colors: [
            SpectreColors.pink.withOpacity(0),
            SpectreColors.pink.withOpacity(0.18 + 0.12 * glow),
          ]).createShader(Rect.fromPoints(center, t)),
      );
    }
  }

  @override
  bool shouldRepaint(SquareFloorPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.target != target || oldDelegate.center != center || oldDelegate.theme != theme;
}

/// Köşeleri yuvarlatılmış koltuk çevresinde süre çerçevesi.
class RoundedTimerPainter extends CustomPainter {
  RoundedTimerPainter({required this.progress, required this.color, required this.radius});
  final double progress;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).inflate(3), Radius.circular(radius + 3));
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final c = progress < 0.25 ? SpectreColors.red : color;
    // üst ortadan başlasın
    final start = metric.length * 0.125;
    final len = metric.length * progress.clamp(0.0, 1.0);
    final seg = Path();
    if (start + len <= metric.length) {
      seg.addPath(metric.extractPath(start, start + len), Offset.zero);
    } else {
      seg
        ..addPath(metric.extractPath(start, metric.length), Offset.zero)
        ..addPath(metric.extractPath(0, start + len - metric.length), Offset.zero);
    }
    canvas.drawPath(
      seg,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(RoundedTimerPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}
