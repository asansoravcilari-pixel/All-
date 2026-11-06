import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backend.dart';
import '../data/game_table.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'table_stage.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.table});
  final GameTable table;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final _notices = <_Notice>[];
  StreamSubscription<TableEvent>? _sub;
  bool _chatOpen = false;
  int _noticeId = 0;

  GameTable get t => widget.table;

  @override
  void initState() {
    super.initState();
    _sub = t.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(TableEvent e) {
    final me = BackendScope.read(context).me;
    final mySeat = t.seatOf(me.id);
    switch (e) {
      case NoticeEvent(:final text, :final kind):
        _push(text, kind);
      case MatchEvent(:final a, :final b, :final success):
        if (success && (a == mySeat || b == mySeat)) {
          HapticFeedback.mediumImpact();
          _push('Eşleştiniz! +1 ♥', NoticeKind.success);
        }
      case GiftEvent(:final toSeat, :final gift):
        if (toSeat == mySeat) _push('Sana ${gift.emoji} ${gift.name} geldi!', NoticeKind.gift);
      default:
        break;
    }
  }

  void _push(String text, NoticeKind kind) {
    if (!mounted) return;
    final n = _Notice(_noticeId++, text, kind);
    setState(() {
      _notices.add(n);
      if (_notices.length > 3) _notices.removeAt(0);
    });
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _notices.remove(n));
    });
  }

  void _onSeatTap(int index) {
    final be = BackendScope.read(context);
    final seat = t.seats[index];
    if (seat.player == null) {
      if (t.seatOf(be.me.id) == null) {
        t.humanId = be.me.id;
        t.join(be.me, preferredSeat: index);
      }
      return;
    }
    _showPlayer(seat);
  }

  void _showPlayer(Seat seat) {
    final p = seat.player!;
    final be = BackendScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PlayerSheet(player: p, seat: seat, table: t, backend: be),
    );
  }

  void _openGifts({int? toSeat}) {
    final be = BackendScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _GiftSheet(table: t, backend: be, initialTarget: toSeat),
    );
  }

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final light = be.settings.lightMode;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final mySeat = t.seatOf(be.me.id);
        final stage = Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: TableStage(
              table: t,
              meId: be.me.id,
              onSeatTap: _onSeatTap,
              light: light,
            ),
          ),
        );
        final body = Column(
          children: [
            _TopBar(table: t, backend: be),
            _PhaseBanner(table: t, meId: be.me.id),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: stage),
                  // Bildirimler
                  Positioned(
                    top: 4,
                    left: 12,
                    right: 12,
                    child: Column(
                      children: [
                        for (final n in _notices) _NoticeToast(key: ValueKey(n.id), notice: n),
                      ],
                    ),
                  ),
                  if (!wide)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 6,
                      child: _ChatTicker(table: t, onTap: () => setState(() => _chatOpen = true)),
                    ),
                ],
              ),
            ),
            _ActionBar(
              table: t,
              backend: be,
              seated: mySeat != null,
              onGift: () => _openGifts(),
              onChat: () => setState(() => _chatOpen = !_chatOpen),
              wide: wide,
            ),
          ],
        );
        return Scaffold(
          body: SpectreBackground(
            animate: !light,
            child: SafeArea(
              child: wide
                  ? Row(
                      children: [
                        Expanded(child: body),
                        SizedBox(
                          width: 360,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                            child: _ChatPanel(table: t, backend: be),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        body,
                        // Mobil sohbet çekmecesi
                        AnimatedPositioned(
                          duration: SpectreMotion.normal,
                          curve: SpectreMotion.curve,
                          left: 0,
                          right: 0,
                          bottom: _chatOpen ? 0 : -520,
                          height: 480,
                          child: _ChatPanel(
                            table: t,
                            backend: be,
                            onClose: () => setState(() => _chatOpen = false),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.table, required this.backend});
  final GameTable table;
  final SpectreBackend backend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Lobiye dön',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              backend.leaveTable();
              Navigator.of(context).maybePop();
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(table.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text(
                  '${table.occupied}/${table.seats.length} oyuncu · Tur ${table.round.roundNo}',
                  style: const TextStyle(color: SpectreColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          CoinPill(coins: backend.me.coins),
        ],
      ),
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.table, required this.meId});
  final GameTable table;
  final String meId;

  @override
  Widget build(BuildContext context) {
    final r = table.round;
    final spinner = table.seats[r.spinnerSeat].player;
    final target = r.targetSeat == null ? null : table.seats[r.targetSeat!].player;
    String text;
    Color color = SpectreColors.accent;
    if (table.occupied < 2) {
      text = 'Oyuncular bekleniyor…';
      color = SpectreColors.muted;
    } else {
      switch (r.phase) {
        case RoundPhase.idle:
          text = spinner?.id == meId ? 'Sıra sende — şişeyi çevir!' : 'Sıra: ${spinner?.name ?? '-'}';
        case RoundPhase.spinning:
          text = '${spinner?.name ?? ''} çeviriyor…';
        case RoundPhase.deciding:
          text = '${spinner?.name} ↔ ${target?.name} karar veriyor';
          color = SpectreColors.pink;
        case RoundPhase.result:
          final ok = (r.spinnerAccepted ?? false) && (r.targetAccepted ?? false);
          text = ok ? '💞 Eşleşme!' : 'Pas geçildi';
          color = ok ? SpectreColors.green : SpectreColors.muted;
      }
    }
    return AnimatedSwitcher(
      duration: SpectreMotion.normal,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(a), child: c),
      ),
      child: Container(
        key: ValueKey(text),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.45)),
        ),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.table,
    required this.backend,
    required this.seated,
    required this.onGift,
    required this.onChat,
    required this.wide,
  });
  final GameTable table;
  final SpectreBackend backend;
  final bool seated;
  final VoidCallback onGift;
  final VoidCallback onChat;
  final bool wide;

  static const _reactions = ['❤️', '😂', '😮', '👏', '🔥'];

  @override
  Widget build(BuildContext context) {
    final me = backend.me;
    final r = table.round;
    final mySeat = table.seatOf(me.id);
    final myTurn = mySeat != null && r.phase == RoundPhase.idle && r.spinnerSeat == mySeat && table.occupied >= 2;
    final involved = mySeat != null &&
        r.phase == RoundPhase.deciding &&
        ((r.spinnerSeat == mySeat && r.spinnerAccepted == null) ||
            (r.targetSeat == mySeat && r.targetAccepted == null));

    Widget main;
    if (!seated) {
      main = PressButton(
        key: const ValueKey('sit'),
        onTap: table.isFull
            ? null
            : () {
                table.humanId = me.id;
                table.join(me);
              },
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_seat_rounded),
          SizedBox(width: 8),
          Text('Masaya otur'),
        ]),
      );
    } else if (involved) {
      main = Row(
        key: const ValueKey('decide'),
        mainAxisSize: MainAxisSize.min,
        children: [
          PressButton(
            color: SpectreColors.red,
            onTap: () => table.decide(me.id, false, DateTime.now()),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.close_rounded),
              SizedBox(width: 6),
              Text('Pas'),
            ]),
          ),
          const SizedBox(width: 12),
          _CountdownChip(table: table),
          const SizedBox(width: 12),
          PressButton(
            color: SpectreColors.pink,
            onTap: () => table.decide(me.id, true, DateTime.now()),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.favorite_rounded),
              SizedBox(width: 6),
              Text('Kabul'),
            ]),
          ),
        ],
      );
    } else {
      main = _SpinButton(
        key: const ValueKey('spin'),
        enabled: myTurn,
        onTap: () {
          HapticFeedback.heavyImpact();
          table.spin(me.id, DateTime.now());
        },
      );
    }

    return GlassPanel(
      radius: 0,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seated)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final e in _reactions)
                    _ReactionChip(emoji: e, onTap: () => table.react(me.id, e)),
                ],
              ),
            ),
          Row(
            children: [
              _RoundIcon(icon: Icons.card_giftcard_rounded, label: 'Hediye', onTap: seated ? onGift : null, color: SpectreColors.gold),
              const Spacer(),
              AnimatedSwitcher(
                duration: SpectreMotion.normal,
                switchInCurve: SpectreMotion.spring,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: main,
              ),
              const Spacer(),
              if (!wide)
                _RoundIcon(icon: Icons.chat_bubble_rounded, label: 'Sohbet', onTap: onChat)
              else
                _RoundIcon(
                  icon: Icons.logout_rounded,
                  label: 'Kalk',
                  onTap: seated ? () => table.leave(me.id) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpinButton extends StatefulWidget {
  const _SpinButton({super.key, required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
        scale: widget.enabled ? 1 + _pulse.value * 0.05 : 1,
        child: child,
      ),
      child: PressButton(
        onTap: widget.enabled ? widget.onTap : null,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        radius: 30,
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.autorenew_rounded),
          SizedBox(width: 8),
          Text('ÇEVİR', style: TextStyle(fontSize: 16, letterSpacing: 1.5)),
        ]),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.table});
  final GameTable table;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 200), (i) => i),
      builder: (_, __) {
        final left = table.remaining(DateTime.now()).inMilliseconds / 1000;
        return Text(
          left.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: left < 2 ? SpectreColors.red : SpectreColors.ink,
          ),
        );
      },
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap, this.color = SpectreColors.accent});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PressButton(
      onTap: onTap,
      filled: false,
      color: color,
      glow: false,
      tooltip: label,
      padding: const EdgeInsets.all(12),
      child: Icon(icon),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PressButton(
        onTap: onTap,
        filled: false,
        glow: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        radius: 20,
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bildirimler
// ---------------------------------------------------------------------------

class _Notice {
  _Notice(this.id, this.text, this.kind);
  final int id;
  final String text;
  final NoticeKind kind;
}

class _NoticeToast extends StatelessWidget {
  const _NoticeToast({super.key, required this.notice});
  final _Notice notice;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (notice.kind) {
      NoticeKind.info => (Icons.info_outline_rounded, SpectreColors.accent),
      NoticeKind.success => (Icons.favorite_rounded, SpectreColors.pink),
      NoticeKind.warn => (Icons.campaign_rounded, SpectreColors.amber),
      NoticeKind.gift => (Icons.card_giftcard_rounded, SpectreColors.gold),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SpectreMotion.slow,
      curve: SpectreMotion.spring,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, -20 * (1 - v)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GlassPanel(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          tint: color.withOpacity(0.25),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(notice.text,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sohbet
// ---------------------------------------------------------------------------

class _ChatTicker extends StatelessWidget {
  const _ChatTicker({required this.table, required this.onTap});
  final GameTable table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final last = table.chat.length <= 2 ? table.chat : table.chat.sublist(table.chat.length - 2);
    if (last.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in last)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _ChatLine(m: m, compact: true),
            ),
        ],
      ),
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.m, this.compact = false});
  final ChatMessage m;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (m.system) {
      return Text(m.text,
          maxLines: compact ? 1 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: const TextStyle(color: SpectreColors.muted, fontSize: 12, fontStyle: FontStyle.italic));
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '${m.from!.name}: ',
            style: TextStyle(color: m.from!.color, fontWeight: FontWeight.w800, fontSize: 13)),
        TextSpan(text: m.text, style: const TextStyle(fontSize: 13)),
      ]),
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.table, required this.backend, this.onClose});
  final GameTable table;
  final SpectreBackend backend;
  final VoidCallback? onClose;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctl.text;
    final be = widget.backend;
    final lower = text.toLowerCase();
    if (be.settings.blockedWords.any((w) => w.isNotEmpty && lower.contains(w.toLowerCase()))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mesaj topluluk kurallarına uymuyor.')));
      return;
    }
    widget.table.say(be.me, text);
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.table.chat;
    final seated = widget.table.seatOf(widget.backend.me.id) != null;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.forum_rounded, color: SpectreColors.accent, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Masa sohbeti', style: TextStyle(fontWeight: FontWeight.w800))),
                if (widget.onClose != null)
                  IconButton(onPressed: widget.onClose, icon: const Icon(Icons.keyboard_arrow_down_rounded)),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[msgs.length - 1 - i];
                return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: _ChatLine(m: m));
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    enabled: seated && widget.table.rules.chatEnabled,
                    maxLength: 160,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: !widget.table.rules.chatEnabled
                          ? 'Sohbet kapalı'
                          : seated
                              ? 'Mesaj yaz…'
                              : 'Yazmak için masaya otur',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PressButton(
                  onTap: seated ? _send : null,
                  padding: const EdgeInsets.all(11),
                  radius: 12,
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alt sayfalar
// ---------------------------------------------------------------------------

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GlassPanel(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet({required this.player, required this.seat, required this.table, required this.backend});
  final Player player;
  final Seat seat;
  final GameTable table;
  final SpectreBackend backend;

  @override
  Widget build(BuildContext context) {
    final isMe = player.id == backend.me.id;
    final p = player;
    Widget stat(String l, String v) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(l, style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
          ]),
        );
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(player: p, size: 84, presence: seat.presence),
          const SizedBox(height: 10),
          Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            Chip(label: Text('Seviye ${p.level}')),
            if (p.age > 0) Chip(label: Text('${p.age} yaş')),
            Chip(
              avatar: CircleAvatar(backgroundColor: presenceColor(seat.presence), radius: 5),
              label: Text(presenceLabel(seat.presence)),
            ),
            if (p.isVip) const Chip(label: Text('👑 VIP')),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            stat('Kalp', '${p.hearts}'),
            stat('Gönderilen', '${p.giftsSent}'),
            stat('Alınan', '${p.giftsReceived}'),
            stat('Çevirme', '${p.spins}'),
          ]),
          const SizedBox(height: 18),
          if (!isMe)
            Row(children: [
              Expanded(
                child: PressButton(
                  color: SpectreColors.gold,
                  onTap: () {
                    Navigator.pop(context);
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => _GiftSheet(table: table, backend: backend, initialTarget: seat.index),
                    );
                  },
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.card_giftcard_rounded),
                    SizedBox(width: 8),
                    Text('Hediye gönder'),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              PressButton(
                filled: false,
                color: SpectreColors.red,
                glow: false,
                tooltip: 'Şikâyet et',
                onTap: () {
                  backend.security.insert(0, SecurityEvent(NoticeKind.warn, 'Şikâyet: ${p.name} (${table.name})'));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Şikâyetin yöneticilere iletildi.')));
                },
                child: const Icon(Icons.flag_rounded),
              ),
            ])
          else
            PressButton(
              filled: false,
              onTap: () {
                table.leave(p.id);
                Navigator.pop(context);
              },
              child: const Text('Masadan kalk'),
            ),
        ],
      ),
    );
  }
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({required this.table, required this.backend, this.initialTarget});
  final GameTable table;
  final SpectreBackend backend;
  final int? initialTarget;

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  int? _target;
  String _cat = 'Tümü';

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
  }

  @override
  Widget build(BuildContext context) {
    final be = widget.backend;
    final t = widget.table;
    final others = t.seats.where((s) => s.player != null && s.player!.id != be.me.id).toList();
    _target ??= others.isNotEmpty ? others.first.index : null;
    final cats = ['Tümü', ...{for (final g in be.gifts) g.category}];
    final gifts = be.gifts.where((g) => g.enabled && (_cat == 'Tümü' || g.category == _cat)).toList();
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Hediye gönder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            ListenableBuilder(listenable: be, builder: (_, __) => CoinPill(coins: be.me.coins)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in others)
                  GestureDetector(
                    onTap: () => setState(() => _target = s.index),
                    child: AnimatedContainer(
                      duration: SpectreMotion.fast,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _target == s.index ? SpectreColors.gold : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(children: [
                        PlayerAvatar(player: s.player!, size: 44),
                        Text(s.player!.name, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _cat == c,
                      onSelected: (_) => setState(() => _cat = c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 230,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
              ),
              itemCount: gifts.length,
              itemBuilder: (_, i) {
                final g = gifts[i];
                final afford = be.me.coins >= g.price;
                return PressButton(
                  filled: false,
                  glow: false,
                  color: afford ? SpectreColors.gold : SpectreColors.muted,
                  padding: const EdgeInsets.all(6),
                  onTap: _target == null
                      ? null
                      : () {
                          final err = be.sendGift(t, _target!, g);
                          if (err != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                          } else {
                            Navigator.pop(context);
                          }
                        },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(g.emoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 4),
                      Text(g.name, style: const TextStyle(fontSize: 11, color: SpectreColors.ink)),
                      Text('🪙 ${g.price}', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
