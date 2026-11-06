import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:spectre_core/spectre_core.dart';

import '../data/room_state.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'stage_painters.dart';

/// Sahne geometrisi — kare düzen (üstte 4, solda 2, sağda 2, altta 4).
class StageGeometry {
  StageGeometry(this.size);
  final Size size;

  /// Koltuk alanı genişliği ve fotoğraf kenarı.
  double get slot => size.width * kSeatWidth;
  double get seatSide => size.width * kSeatFace;
  Offset get center => Offset(kStageCenter.$1 * size.width, kStageCenter.$2 * size.height);

  /// Fotoğrafın sol-üst köşesi (koltuk alanı içinde yatayda ortalı).
  Offset origin(int i) =>
      Offset(kSeatOrigins[i].$1 * size.width + (slot - seatSide) / 2, kSeatOrigins[i].$2 * size.height);

  /// Koltuk fotoğrafının merkezi.
  Offset seat(int i) => origin(i) + Offset(seatSide / 2, seatSide / 2);
}

/// 12 koltuklu kare masa. Ortaya [centre] (tur durumu + düğmeler) yerleşir.
class TableStage extends StatefulWidget {
  const TableStage({
    super.key,
    required this.table,
    required this.meId,
    required this.onSeatTap,
    required this.light,
    this.centre,
    this.status,
    this.anim = const {},
  });

  final RoomState table;
  final String meId;
  final void Function(int seat) onSeatTap;
  final bool light;
  /// Tur düğmeleri (şişenin altında, koltukların önünde).
  final Widget? centre;

  /// Tur durumu yazısı (şişenin üstünde).
  final Widget? status;

  /// Yönetim panelinden animasyon ayarları.
  final Map<String, dynamic> anim;

  @override
  State<TableStage> createState() => _TableStageState();
}

class _TableStageState extends State<TableStage> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  final _fx = GlobalKey<_FxLayerState>();
  final _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.table.addFxListener(_onFx);
  }

  @override
  void didUpdateWidget(TableStage old) {
    super.didUpdateWidget(old);
    if (old.table != widget.table) {
      old.table.removeFxListener(_onFx);
      widget.table.addFxListener(_onFx);
    }
  }

  void _onFx(RoomFx e) => _fx.currentState?.add(e);

  @override
  void dispose() {
    widget.table.removeFxListener(_onFx);
    _clock.dispose();
    super.dispose();
  }

  double _bottleAngle(DateTime now) {
    final r = widget.table.round;
    if (r.phase != RoundPhase.spinning) return r.bottleAngle;
    final t = widget.table.phaseProgress(now);
    final eased = 1 - math.pow(1 - t, 3.6).toDouble();
    final settle = t > 0.92 ? math.sin((t - 0.92) / 0.08 * math.pi) * 0.012 : 0.0;
    return r.fromAngle + (r.bottleAngle - r.fromAngle) * eased - settle;
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final theme = TableTheme.all[(table.room?.theme ?? 0) % TableTheme.all.length];
    return AspectRatio(
      aspectRatio: kStageAspect,
      child: LayoutBuilder(builder: (context, box) {
        final geo = StageGeometry(box.biggest);
        final bottleH = geo.size.height * 0.22;
        // Şişenin altı ile alt koltuk sırası arasındaki boşluk
        final controlsTop = geo.center.dy + bottleH * 0.5 + 2;
        final controlsH = (kSeatOrigins[8].$2 * geo.size.height - controlsTop - 2).clamp(24.0, 80.0);
        final r = table.round;
        final showBeam = r.phase == RoundPhase.deciding || r.phase == RoundPhase.result;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _clock,
                  builder: (_, __) {
                    final now = DateTime.now();
                    final time = now.difference(_start).inMilliseconds / 1000;
                    final spinning = r.phase == RoundPhase.spinning;
                    final myTurn =
                        r.active && r.phase == RoundPhase.idle && table.seats[r.spinnerSeat].player?.userId == widget.meId;
                    final wobble = myTurn && !widget.light && widget.anim['bottleWobble'] != false ? math.sin(time * 5) * 0.05 : 0.0;
                    final glow = spinning
                        ? (1 - table.phaseProgress(now)).clamp(0.2, 1.0)
                        : (myTurn ? 0.35 + 0.25 * math.sin(time * 4) : 0.0);
                    return Stack(children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: SquareFloorPainter(
                            theme: theme,
                            center: geo.center,
                            target: showBeam && r.targetSeat != null && widget.anim['targetBeam'] != false
                                ? geo.seat(r.targetSeat!)
                                : null,
                            time: widget.light || widget.anim['floorGlow'] == false ? 0 : time,
                          ),
                        ),
                      ),
                      Positioned(
                        left: geo.center.dx - bottleH * 0.3,
                        top: geo.center.dy - bottleH / 2,
                        width: bottleH * 0.6,
                        height: bottleH,
                        child: Transform.rotate(
                          angle: _bottleAngle(now) + wobble,
                          child: CustomPaint(painter: BottlePainter(tint: theme.primary, glow: glow.toDouble())),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
            ),
            if (widget.status != null)
              Positioned(
                left: geo.size.width * 0.25,
                right: geo.size.width * 0.25,
                top: geo.center.dy - bottleH * 0.5 - 22,
                height: 20,
                child: IgnorePointer(child: Center(child: widget.status!)),
              ),
            for (final seat in table.seats)
              _SeatSlot(
                key: ValueKey('seat-${seat.index}'),
                geo: geo,
                seat: seat,
                table: table,
                clock: _clock,
                isMe: seat.player?.userId == widget.meId,
                onTap: () => widget.onSeatTap(seat.index),
              ),
            // Düğmeler koltukların önünde çizilir; dar ekranda sığacak kadar küçülür.
            if (widget.centre != null)
              Positioned(
                left: geo.size.width * 0.24,
                right: geo.size.width * 0.24,
                top: controlsTop,
                height: controlsH,
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: widget.centre!)),
              ),
            Positioned.fill(child: IgnorePointer(child: _FxLayer(key: _fx, geo: geo, light: widget.light, anim: widget.anim))),
          ],
        );
      }),
    );
  }
}

class _SeatSlot extends StatelessWidget {
  const _SeatSlot({
    super.key,
    required this.geo,
    required this.seat,
    required this.table,
    required this.clock,
    required this.isMe,
    required this.onTap,
  });

  final StageGeometry geo;
  final SeatView seat;
  final RoomState table;
  final Animation<double> clock;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final side = geo.seatSide;
    final o = geo.origin(seat.index);
    final p = seat.player;
    final r = table.round;
    final isSpinner = p != null && r.active && r.spinnerSeat == seat.index;
    final isTarget =
        p != null && r.targetSeat == seat.index && (r.phase == RoundPhase.deciding || r.phase == RoundPhase.result);
    final bubble = table.bubbleFor(seat.index);
    bool? decision;
    if (r.phase == RoundPhase.deciding || r.phase == RoundPhase.result) {
      if (isSpinner) decision = r.spinnerAccepted;
      if (isTarget) decision = r.targetAccepted;
    }
    final ring = isTarget
        ? SpectreColors.pink
        : isSpinner
            ? SpectreColors.accent
            : isMe
                ? SpectreColors.cyan
                : (p != null ? const Color(0xFF8AD7EF) : const Color(0xFF284F73));
    final radius = BorderRadius.circular(side * 0.11);
    final slot = geo.slot;
    return Positioned(
      left: o.dx - (slot - side) / 2,
      top: o.dy,
      width: slot,
      child: Semantics(
        button: true,
        label: p == null ? 'Boş koltuk ${seat.index + 1}' : '${p.name}, koltuk ${seat.index + 1}',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(
              dimension: side,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: AnimatedScale(
                    scale: isTarget || isSpinner ? 1.06 : 1,
                    duration: SpectreMotion.slow,
                    curve: SpectreMotion.spring,
                    child: AnimatedOpacity(
                      opacity: p != null && !seat.connected ? 0.45 : 1,
                      duration: SpectreMotion.normal,
                      child: AnimatedContainer(
                        duration: SpectreMotion.normal,
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          color: const Color(0xFF0B2942),
                          border: Border.all(color: ring, width: p != null ? 1.6 : 1),
                          boxShadow: [
                            BoxShadow(
                              color: (p != null ? ring : const Color(0xFF16496A)).withOpacity(isTarget || isSpinner ? 0.7 : 0.35),
                              blurRadius: isTarget || isSpinner ? 18 : 9,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: radius,
                          child: AnimatedSwitcher(
                            duration: SpectreMotion.slow,
                            switchInCurve: SpectreMotion.spring,
                            transitionBuilder: (c, a) =>
                                ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                            child: p == null
                                ? _EmptySeatFace(key: const ValueKey('empty'), side: side)
                                : _SeatFace(key: ValueKey(p.userId), player: p, side: side),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isSpinner && r.phase == RoundPhase.idle)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: clock,
                        builder: (_, __) => CustomPaint(
                          painter: RoundedTimerPainter(
                            progress: 1 - table.phaseProgress(DateTime.now()),
                            color: SpectreColors.accent,
                            radius: side * 0.11,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (p != null)
                  Positioned(right: -3, bottom: -3, child: _PresenceDot(state: seat.presence, connected: seat.connected)),
                if (p != null && p.vip) Positioned(left: -4, top: -6, child: Text('👑', style: TextStyle(fontSize: side * 0.2))),
                if (decision != null) Positioned(right: -6, top: -6, child: _DecisionBadge(accepted: decision)),
                if (bubble != null)
                  Positioned(
                    left: -side * 0.3,
                    right: -side * 0.3,
                    bottom: side * 0.82,
                    child: Center(child: _Bubble(text: bubble, key: ValueKey(bubble))),
                  ),
              ]),
            ),
            const SizedBox(height: 2),
            Text(
              p == null ? '' : (isMe ? '${p.name} (sen)' : p.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (slot * 0.11).clamp(9.0, 13.0),
                fontWeight: FontWeight.w700,
                color: isMe ? SpectreColors.cyan : const Color(0xFFEEFAFF),
                shadows: const [Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1))],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SeatFace extends StatelessWidget {
  const _SeatFace({super.key, required this.player, required this.side});
  final SeatPlayer player;
  final double side;

  @override
  Widget build(BuildContext context) {
    final c = Color(player.color);
    final initials = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(c, Colors.white, 0.25)!, c, Color.lerp(c, Colors.black, 0.55)!],
        ),
      ),
      child: Center(
        child: Text(
          initialsOf(player.name),
          style: TextStyle(
            fontSize: side * 0.34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
          ),
        ),
      ),
    );
    if (player.avatarUrl.isEmpty) return SizedBox.expand(child: initials);
    return SizedBox.expand(
      child: Image.network(player.avatarUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => initials),
    );
  }
}

class _EmptySeatFace extends StatelessWidget {
  const _EmptySeatFace({super.key, required this.side});
  final double side;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0E3150), Color(0xFF0A2238)],
            ),
          ),
          child: Icon(Icons.event_seat_rounded, size: side * 0.42, color: const Color(0xFF2C5B82)),
        ),
      );
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.state, required this.connected});
  final Presence state;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final c = connected ? presenceColor(state) : SpectreColors.amber;
    return AnimatedContainer(
      duration: SpectreMotion.normal,
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: SpectreColors.bg, width: 2),
        boxShadow: [BoxShadow(color: c.withOpacity(0.7), blurRadius: 5)],
      ),
    );
  }
}

class _DecisionBadge extends StatelessWidget {
  const _DecisionBadge({required this.accepted});
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SpectreMotion.slow,
      curve: SpectreMotion.spring,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accepted ? SpectreColors.green : SpectreColors.red,
          border: Border.all(color: SpectreColors.bg, width: 2),
        ),
        child: Icon(accepted ? Icons.favorite : Icons.close, size: 12, color: Colors.white),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SpectreMotion.normal,
      curve: SpectreMotion.spring,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF0A1726), fontSize: 10.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Efekt katmanı
// ---------------------------------------------------------------------------

class _Fx {
  _Fx(this.controller, this.builder);
  final AnimationController controller;
  final Widget Function(double t) builder;
}

class _FxLayer extends StatefulWidget {
  const _FxLayer({super.key, required this.geo, required this.light, this.anim = const {}});
  final StageGeometry geo;
  final bool light;
  final Map<String, dynamic> anim;

  @override
  State<_FxLayer> createState() => _FxLayerState();
}

class _FxLayerState extends State<_FxLayer> with TickerProviderStateMixin {
  final List<_Fx> _items = [];
  final _rnd = math.Random();

  void add(RoomFx e) {
    if (!mounted) return;
    final g = widget.geo;
    switch (e) {
      case FxGift(:final fromSeat, :final toSeat, :final gift):
        final ms = ((widget.anim['giftFlightMs'] as num?) ?? 1300).toInt().clamp(300, 5000);
        _spawn(Duration(milliseconds: ms), (t) => _flying(g.seat(fromSeat), g.seat(toSeat), gift.emoji, t));
      case FxReaction(:final seat, :final emoji):
        final dx = (_rnd.nextDouble() - 0.5) * 30;
        _spawn(const Duration(milliseconds: 1600), (t) => _floatUp(g.seat(seat) + Offset(dx, 0), emoji, t));
      case FxMatch(:final a, :final b, :final success):
        if (success) {
          final n = widget.light ? 6 : ((widget.anim['burstCount'] as num?) ?? 16).toInt().clamp(0, 60);
          for (var i = 0; i < n; i++) {
            final ang = _rnd.nextDouble() * 2 * math.pi;
            final dist = 40 + _rnd.nextDouble() * 70;
            _spawn(Duration(milliseconds: 900 + _rnd.nextInt(600)),
                (t) => _burst(g.center, ang, dist, i.isEven ? '💖' : '✨', t));
          }
          _spawn(const Duration(milliseconds: 1400), (t) => _pulse(g.seat(a), g.seatSide, SpectreColors.pink, t));
          _spawn(const Duration(milliseconds: 1400), (t) => _pulse(g.seat(b), g.seatSide, SpectreColors.pink, t));
          final matchEmoji = '${widget.anim['matchEmoji'] ?? '💞'}';
          _spawn(const Duration(milliseconds: 1600), (t) => _centreIcon(g.center, matchEmoji, t, grow: true));
        } else {
          // Red: ortada kırık kalp, iki koltukta kırmızı sönen çerçeve
          final rejectEmoji = '${widget.anim['rejectEmoji'] ?? '💔'}';
          _spawn(const Duration(milliseconds: 1400), (t) => _centreIcon(g.center, rejectEmoji, t, shake: true));
          _spawn(const Duration(milliseconds: 1000), (t) => _pulse(g.seat(a), g.seatSide, SpectreColors.red, t));
          _spawn(const Duration(milliseconds: 1000), (t) => _pulse(g.seat(b), g.seatSide, SpectreColors.red, t));
        }
      case FxSeat(:final seat, :final joined):
        if (joined) _spawn(const Duration(milliseconds: 900), (t) => _pulse(g.seat(seat), g.seatSide, SpectreColors.accent, t));
      case FxNotice():
        break;
    }
  }

  void _spawn(Duration d, Widget Function(double t) b) {
    final c = AnimationController(vsync: this, duration: d);
    final fx = _Fx(c, b);
    setState(() => _items.add(fx));
    c.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _items.remove(fx));
      c.dispose();
    });
  }

  Widget _flying(Offset from, Offset to, String emoji, double t) {
    final e = Curves.easeInOutCubic.transform(t);
    final mid = Offset.lerp(from, to, 0.5)! + const Offset(0, -70);
    final p = from * math.pow(1 - e, 2).toDouble() + mid * (2 * (1 - e) * e) + to * (e * e);
    final scale = 0.6 + math.sin(t * math.pi) * 1.1;
    final op = t > 0.85 ? (1 - t) / 0.15 : 1.0;
    return Positioned(
      left: p.dx - 18,
      top: p.dy - 18,
      child: Opacity(
        opacity: op.clamp(0, 1),
        child: Transform.scale(scale: scale, child: Text(emoji, style: const TextStyle(fontSize: 26))),
      ),
    );
  }

  Widget _floatUp(Offset at, String emoji, double t) {
    final e = Curves.easeOut.transform(t);
    return Positioned(
      left: at.dx - 14 + math.sin(t * 8) * 6,
      top: at.dy - 30 - e * 70,
      child: Opacity(
        opacity: (1 - t).clamp(0, 1),
        child: Transform.scale(scale: 0.8 + e * 0.6, child: Text(emoji, style: const TextStyle(fontSize: 24))),
      ),
    );
  }

  Widget _burst(Offset c, double ang, double dist, String s, double t) {
    final e = Curves.easeOutCubic.transform(t);
    final p = c + Offset.fromDirection(ang, dist * e) + Offset(0, t * t * 30);
    return Positioned(
      left: p.dx - 10,
      top: p.dy - 10,
      child: Opacity(opacity: (1 - t).clamp(0, 1), child: Text(s, style: const TextStyle(fontSize: 18))),
    );
  }

  Widget _centreIcon(Offset c, String s, double t, {bool grow = false, bool shake = false}) {
    final appear = Curves.easeOutBack.transform((t / 0.35).clamp(0.0, 1.0));
    final fade = t > 0.7 ? (1 - t) / 0.3 : 1.0;
    final dx = shake ? math.sin(t * 40) * 6 * (1 - t) : 0.0;
    final scale = appear * (grow ? 1 + t * 0.5 : 1);
    return Positioned(
      left: c.dx - 28 + dx,
      top: c.dy - 28 - (grow ? t * 20 : 0),
      child: Opacity(
        opacity: fade.clamp(0, 1),
        child: Transform.scale(scale: scale, child: Text(s, style: const TextStyle(fontSize: 48))),
      ),
    );
  }

  Widget _pulse(Offset c, double side, Color color, double t) {
    final half = side / 2 + t * 22;
    return Positioned(
      left: c.dx - half,
      top: c.dy - half,
      child: Container(
        width: half * 2,
        height: half * 2,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(side * 0.14 + t * 10),
          border: Border.all(color: color.withOpacity((1 - t) * 0.8), width: 3 * (1 - t) + 0.5),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final f in _items) {
      f.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      for (final f in _items)
        AnimatedBuilder(
          animation: f.controller,
          builder: (_, __) => Stack(clipBehavior: Clip.none, children: [f.builder(f.controller.value)]),
        ),
    ]);
  }
}
