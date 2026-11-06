import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/game_table.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'stage_painters.dart';

/// Sahne geometrisi: koltuk merkezleri ve boyutları.
class StageGeometry {
  StageGeometry(this.size, this.count);
  final Size size;
  final int count;

  Offset get center => size.center(Offset.zero);
  double get radius => size.shortestSide / 2;
  double get seatSize => (size.shortestSide * 0.135).clamp(40.0, 84.0);

  Offset seat(int i) {
    final a = GameTable.seatAngle(i, count);
    return center + Offset(math.cos(a), math.sin(a)) * radius * 0.80;
  }
}

/// Masanın tamamı: zemin, şişe, koltuklar ve efekt katmanı.
class TableStage extends StatefulWidget {
  const TableStage({
    super.key,
    required this.table,
    required this.meId,
    required this.onSeatTap,
    required this.light,
  });

  final GameTable table;
  final String meId;
  final void Function(int seat) onSeatTap;
  final bool light;

  @override
  State<TableStage> createState() => _TableStageState();
}

class _TableStageState extends State<TableStage> with TickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  final _fx = GlobalKey<_FxLayerState>();
  StreamSubscription<TableEvent>? _sub;
  final _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(TableStage old) {
    super.didUpdateWidget(old);
    if (old.table != widget.table) {
      _sub?.cancel();
      _listen();
    }
  }

  void _listen() {
    _sub = widget.table.events.listen((e) => _fx.currentState?.add(e));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock.dispose();
    super.dispose();
  }

  double _bottleAngle(DateTime now) {
    final r = widget.table.round;
    if (r.phase != RoundPhase.spinning) return r.bottleAngle;
    final t = widget.table.phaseProgress(now);
    // Gerçekçi yavaşlama: hızlı başlangıç, uzun sönümlenme + küçük geri yaylanma.
    final eased = 1 - math.pow(1 - t, 3.6).toDouble();
    final settle = t > 0.92 ? math.sin((t - 0.92) / 0.08 * math.pi) * 0.012 : 0.0;
    return r.fromAngle + (r.bottleAngle - r.fromAngle) * eased - settle;
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final theme = TableTheme.all[table.theme % TableTheme.all.length];
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final geo = StageGeometry(box.biggest, table.seats.length);
        final bottleH = geo.radius * 0.62;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Zemin + şişe: her karede yeniden çizilir, ama yalnız bu katman.
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _clock,
                  builder: (_, __) {
                    final now = DateTime.now();
                    final time = now.difference(_start).inMilliseconds / 1000;
                    final r = table.round;
                    final spinning = r.phase == RoundPhase.spinning;
                    final myTurn = r.phase == RoundPhase.idle &&
                        table.seats[r.spinnerSeat].player?.id == widget.meId;
                    final wobble = myTurn && !widget.light ? math.sin(time * 5) * 0.05 : 0.0;
                    final glow = spinning
                        ? (1 - table.phaseProgress(now)).clamp(0.2, 1.0)
                        : (myTurn ? 0.35 + 0.25 * math.sin(time * 4) : 0.0);
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: TableFloorPainter(
                              theme: theme,
                              time: widget.light ? 0 : time,
                              seatCount: table.seats.length,
                              activeSeat: table.occupied >= 2 ? r.spinnerSeat : null,
                              targetSeat: r.phase == RoundPhase.deciding || r.phase == RoundPhase.result
                                  ? r.targetSeat
                                  : null,
                              light: widget.light,
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
                            child: CustomPaint(
                              painter: BottlePainter(tint: theme.primary, glow: glow.toDouble()),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Koltuklar
            for (final seat in table.seats)
              _SeatSlot(
                key: ValueKey('seat-${seat.index}'),
                geo: geo,
                seat: seat,
                table: table,
                clock: _clock,
                isMe: seat.player?.id == widget.meId,
                onTap: () => widget.onSeatTap(seat.index),
              ),
            // Efektler
            Positioned.fill(
              child: IgnorePointer(
                child: _FxLayer(key: _fx, geo: geo, light: widget.light),
              ),
            ),
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
  final Seat seat;
  final GameTable table;
  final Animation<double> clock;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = geo.seatSize;
    final pos = geo.seat(seat.index);
    final p = seat.player;
    final r = table.round;
    final isSpinner = p != null && table.occupied >= 2 && r.spinnerSeat == seat.index;
    final isTarget = p != null &&
        r.targetSeat == seat.index &&
        (r.phase == RoundPhase.deciding || r.phase == RoundPhase.result);
    final w = s * 1.7;
    // Kararı göster (✓ / ✗)
    bool? decision;
    if (r.phase == RoundPhase.deciding || r.phase == RoundPhase.result) {
      if (isSpinner) decision = r.spinnerAccepted;
      if (isTarget) decision = r.targetAccepted;
    }
    return Positioned(
      left: pos.dx - w / 2,
      top: pos.dy - s / 2,
      width: w,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedSwitcher(
          duration: SpectreMotion.slow,
          switchInCurve: SpectreMotion.spring,
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
          child: p == null
              ? _EmptySeat(key: const ValueKey('empty'), size: s)
              : Column(
                  key: ValueKey(p.id),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: s,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          if (isSpinner && r.phase == RoundPhase.idle)
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: clock,
                                builder: (_, __) => CustomPaint(
                                  painter: TimerRingPainter(
                                    progress: 1 - table.phaseProgress(DateTime.now()),
                                    color: SpectreColors.accent,
                                  ),
                                ),
                              ),
                            ),
                          AnimatedScale(
                            scale: isTarget || isSpinner ? 1.08 : 1,
                            duration: SpectreMotion.slow,
                            curve: SpectreMotion.spring,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: PlayerAvatar(
                                player: p,
                                size: s - 8,
                                presence: seat.presence,
                                highlight: isTarget
                                    ? SpectreColors.pink
                                    : isSpinner
                                        ? SpectreColors.accent
                                        : (isMe ? SpectreColors.cyan : null),
                              ),
                            ),
                          ),
                          if (decision != null)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: _DecisionBadge(accepted: decision),
                            ),
                          if (seat.bubble != null)
                            Positioned(
                              bottom: s * 0.92,
                              child: _Bubble(text: seat.bubble!, key: ValueKey(seat.bubbleAt)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    _NameTag(name: isMe ? '${p.name} (sen)' : p.name, hearts: p.hearts, me: isMe),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size * 0.8,
        height: size * 0.8,
        margin: EdgeInsets.only(bottom: size * 0.3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.03),
          border: Border.all(color: Colors.white.withOpacity(0.14), width: 1.4),
        ),
        child: Icon(Icons.add_rounded, color: Colors.white.withOpacity(0.25), size: size * 0.32),
      ),
    );
  }
}

class _NameTag extends StatelessWidget {
  const _NameTag({required this.name, required this.hearts, required this.me});
  final String name;
  final int hearts;
  final bool me;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: me ? SpectreColors.cyan.withOpacity(0.6) : SpectreColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          Text('♥$hearts', style: const TextStyle(fontSize: 10, color: SpectreColors.pink)),
        ],
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF0A1726), fontSize: 11, fontWeight: FontWeight.w600),
          ),
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
  const _FxLayer({super.key, required this.geo, required this.light});
  final StageGeometry geo;
  final bool light;

  @override
  State<_FxLayer> createState() => _FxLayerState();
}

class _FxLayerState extends State<_FxLayer> with TickerProviderStateMixin {
  final List<_Fx> _items = [];
  final _rnd = math.Random();

  void add(TableEvent e) {
    if (!mounted) return;
    final g = widget.geo;
    switch (e) {
      case GiftEvent(:final fromSeat, :final toSeat, :final gift):
        _spawn(const Duration(milliseconds: 1300), (t) => _flyingGift(g.seat(fromSeat), g.seat(toSeat), gift.emoji, t));
      case ReactionEvent(:final seat, :final emoji):
        final dx = (_rnd.nextDouble() - 0.5) * 30;
        _spawn(const Duration(milliseconds: 1600), (t) => _floatUp(g.seat(seat) + Offset(dx, 0), emoji, t));
      case MatchEvent(:final a, :final b, :final success):
        if (success) {
          final mid = Offset.lerp(g.seat(a), g.seat(b), 0.5)!;
          final n = widget.light ? 6 : 16;
          for (var i = 0; i < n; i++) {
            final ang = _rnd.nextDouble() * 2 * math.pi;
            final dist = 40 + _rnd.nextDouble() * 70;
            _spawn(Duration(milliseconds: 900 + _rnd.nextInt(600)),
                (t) => _burst(g.center, ang, dist, i.isEven ? '💖' : '✨', t));
          }
          _spawn(const Duration(milliseconds: 1400), (t) => _pulseRing(g.seat(a), SpectreColors.pink, t));
          _spawn(const Duration(milliseconds: 1400), (t) => _pulseRing(g.seat(b), SpectreColors.pink, t));
          _spawn(const Duration(milliseconds: 1800), (t) => _flyingGift(g.seat(a), mid, '💞', t));
        }
      case JoinEvent(:final seat, :final joined):
        if (joined) {
          _spawn(const Duration(milliseconds: 900), (t) => _pulseRing(g.seat(seat), SpectreColors.accent, t));
        }
      case NoticeEvent():
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

  Widget _flyingGift(Offset from, Offset to, String emoji, double t) {
    final e = Curves.easeInOutCubic.transform(t);
    final mid = Offset.lerp(from, to, 0.5)! + const Offset(0, -80);
    // Bezier yay
    final p = from * math.pow(1 - e, 2).toDouble() + mid * (2 * (1 - e) * e) + to * (e * e);
    final scale = 0.6 + math.sin(t * math.pi) * 1.1;
    final op = t > 0.85 ? (1 - t) / 0.15 : 1.0;
    return Positioned(
      left: p.dx - 20,
      top: p.dy - 20,
      child: Opacity(
        opacity: op.clamp(0, 1),
        child: Transform.scale(scale: scale, child: Text(emoji, style: const TextStyle(fontSize: 28))),
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

  Widget _pulseRing(Offset c, Color color, double t) {
    final r = 20 + t * 46;
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      child: Container(
        width: r * 2,
        height: r * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final f in _items)
          AnimatedBuilder(
            animation: f.controller,
            builder: (_, __) => Stack(clipBehavior: Clip.none, children: [f.builder(f.controller.value)]),
          ),
      ],
    );
  }
}
