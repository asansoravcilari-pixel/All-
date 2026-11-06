import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spectre_core/spectre_core.dart';

import '../data/client.dart';
import '../data/room_state.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'table_stage.dart';

/// Masa ekranı. Genişlik ≥ 1200: üç sütun (bilgi | masa | sohbet),
/// ≥ 900: iki sütun (masa | sohbet), daha dar: tek sütun + açılır sohbet.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.room});
  final RoomState room;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final _notices = <_Notice>[];
  StreamSubscription<String>? _errSub;
  bool _chatOpen = false;
  int _noticeId = 0;

  RoomState get t => widget.room;

  @override
  void initState() {
    super.initState();
    t.addFxListener(_onFx);
    _errSub = ClientScope.read(context).errors.listen((m) => _push(m, 'warn'));
  }

  @override
  void dispose() {
    t.removeFxListener(_onFx);
    _errSub?.cancel();
    super.dispose();
  }

  void _onFx(RoomFx e) {
    final me = ClientScope.read(context).me;
    final mySeat = me == null ? null : t.seatOf(me.id);
    switch (e) {
      case FxNotice(:final text, :final kind):
        _push(text, kind);
      case FxMatch(:final a, :final b, :final success):
        if (success && (a == mySeat || b == mySeat)) {
          HapticFeedback.mediumImpact();
          _push('Eşleştiniz! +1 ♥', 'success');
        }
      case FxGift(:final toSeat, :final gift, :final fromSeat):
        final from = t.seats[fromSeat].player?.name ?? '';
        if (toSeat == mySeat) {
          _push('$from sana ${gift.emoji} ${gift.name} gönderdi!', 'gift');
        }
      default:
        break;
    }
  }

  void _push(String text, String kind) {
    if (!mounted) return;
    final n = _Notice(_noticeId++, text, kind);
    setState(() {
      _notices.add(n);
      if (_notices.length > 3) _notices.removeAt(0);
    });
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (mounted) setState(() => _notices.remove(n));
    });
  }

  void _onSeatTap(int index) {
    final c = ClientScope.read(context);
    final seat = t.seats[index];
    if (seat.player == null) {
      if (c.me != null && t.seatOf(c.me!.id) == null) c.sit(seat: index);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlayerSheet(seat: seat, client: c, onGift: () => _openGifts(toSeat: index)),
    );
  }

  void _openGifts({int? toSeat}) {
    final c = ClientScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GiftSheet(room: t, client: c, initialTarget: toSeat),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ClientScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final three = width >= 1200;
    final two = width >= 900;
    final light = c.lightMode;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) c.closeRoom();
      },
      child: ListenableBuilder(
        listenable: t,
        builder: (context, _) {
          final meId = c.me?.id ?? '';
          final seated = t.seatOf(meId) != null;
          final centre = Column(
            children: [
              _TopBar(room: t, client: c),
              _PhaseBanner(room: t, meId: meId),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: !t.loaded
                              ? const CircularProgressIndicator()
                              : TableStage(table: t, meId: meId, onSeatTap: _onSeatTap, light: light),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 12,
                      right: 12,
                      child: IgnorePointer(
                        child: Column(children: [for (final n in _notices) _NoticeToast(key: ValueKey(n.id), notice: n)]),
                      ),
                    ),
                    if (!two)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 6,
                        child: _ChatTicker(room: t, onTap: () => setState(() => _chatOpen = true)),
                      ),
                  ],
                ),
              ),
              _ActionBar(
                room: t,
                client: c,
                seated: seated,
                onGift: () => _openGifts(),
                onChat: () => setState(() => _chatOpen = !_chatOpen),
                showChatButton: !two,
              ),
            ],
          );
          Widget body;
          if (three) {
            body = Row(children: [
              SizedBox(
                width: 300,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                  child: _InfoPanel(room: t, client: c, onSeatTap: _onSeatTap),
                ),
              ),
              Expanded(child: centre),
              SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: _ChatPanel(room: t, client: c),
                ),
              ),
            ]);
          } else if (two) {
            body = Row(children: [
              Expanded(child: centre),
              SizedBox(
                width: 340,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: _ChatPanel(room: t, client: c),
                ),
              ),
            ]);
          } else {
            body = Stack(children: [
              centre,
              AnimatedPositioned(
                duration: SpectreMotion.normal,
                curve: SpectreMotion.curve,
                left: 0,
                right: 0,
                bottom: _chatOpen ? 0 : -540,
                height: 480,
                child: _ChatPanel(room: t, client: c, onClose: () => setState(() => _chatOpen = false)),
              ),
            ]);
          }
          return Scaffold(
            body: SpectreBackground(animate: !light, child: SafeArea(child: body)),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.room, required this.client});
  final RoomState room;
  final SpectreClient client;

  @override
  Widget build(BuildContext context) {
    final r = room.room;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Lobiye dön',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r?.name ?? '…', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text(
                  '${r?.inGamePlayers ?? 0}/${r?.capacity ?? kSeatCount} aktif · Tur ${room.round.roundNo}',
                  style: const TextStyle(color: SpectreColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _LinkDot(state: client.link),
          const SizedBox(width: 8),
          CoinPill(coins: client.me?.coins ?? 0),
        ],
      ),
    );
  }
}

class _LinkDot extends StatelessWidget {
  const _LinkDot({required this.state});
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final (c, label) = switch (state) {
      LinkState.online => (SpectreColors.green, 'Bağlı'),
      LinkState.connecting => (SpectreColors.amber, 'Bağlanıyor…'),
      LinkState.offline => (SpectreColors.red, 'Bağlantı yok'),
    };
    return Tooltip(
      message: label,
      child: AnimatedContainer(
        duration: SpectreMotion.normal,
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c, boxShadow: [BoxShadow(color: c, blurRadius: 6)]),
      ),
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.room, required this.meId});
  final RoomState room;
  final String meId;

  @override
  Widget build(BuildContext context) {
    final r = room.round;
    final spinner = room.seats[r.spinnerSeat].player;
    final target = r.targetSeat == null ? null : room.seats[r.targetSeat!].player;
    String text;
    Color color = SpectreColors.accent;
    if (!r.active) {
      text = room.occupied == 0 ? 'Masa boş — ilk oturan sen ol' : 'İkinci oyuncu bekleniyor…';
      color = SpectreColors.muted;
    } else {
      switch (r.phase) {
        case RoundPhase.idle:
          text = spinner?.userId == meId ? 'Sıra sende — şişeyi çevir!' : 'Sıra: ${spinner?.name ?? '-'}';
        case RoundPhase.spinning:
          text = '${spinner?.name ?? ''} çeviriyor…';
        case RoundPhase.deciding:
          text = '${spinner?.name} ve ${target?.name} karar veriyor';
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
    required this.room,
    required this.client,
    required this.seated,
    required this.onGift,
    required this.onChat,
    required this.showChatButton,
  });
  final RoomState room;
  final SpectreClient client;
  final bool seated;
  final VoidCallback onGift;
  final VoidCallback onChat;
  final bool showChatButton;

  static const _reactions = ['❤️', '😂', '😮', '👏', '🔥'];

  @override
  Widget build(BuildContext context) {
    final meId = client.me?.id ?? '';
    final r = room.round;
    final mySeat = room.seatOf(meId);
    final myTurn = mySeat != null && r.active && r.phase == RoundPhase.idle && r.spinnerSeat == mySeat;
    final involved = mySeat != null &&
        r.phase == RoundPhase.deciding &&
        ((r.spinnerSeat == mySeat && r.spinnerAccepted == null) || (r.targetSeat == mySeat && r.targetAccepted == null));

    Widget main;
    if (!seated) {
      main = PressButton(
        key: const ValueKey('sit'),
        onTap: room.isFull || (room.room?.locked ?? false) ? null : () => client.sit(),
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
            onTap: () => client.decide(false),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.close_rounded),
              SizedBox(width: 6),
              Text('Pas'),
            ]),
          ),
          const SizedBox(width: 12),
          _CountdownChip(room: room),
          const SizedBox(width: 12),
          PressButton(
            color: SpectreColors.pink,
            onTap: () => client.decide(true),
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
          client.spin();
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
                children: [for (final e in _reactions) _ReactionChip(emoji: e, onTap: () => client.react(e))],
              ),
            ),
          Row(
            children: [
              _RoundIcon(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Hediye',
                  onTap: seated && client.gifts.isNotEmpty ? onGift : null,
                  color: SpectreColors.gold),
              const Spacer(),
              AnimatedSwitcher(
                duration: SpectreMotion.normal,
                switchInCurve: SpectreMotion.spring,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: main,
              ),
              const Spacer(),
              if (showChatButton)
                _RoundIcon(icon: Icons.chat_bubble_rounded, label: 'Sohbet', onTap: onChat)
              else
                _RoundIcon(icon: Icons.logout_rounded, label: 'Kalk', onTap: seated ? client.standUp : null),
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
      builder: (_, child) => Transform.scale(scale: widget.enabled ? 1 + _pulse.value * 0.05 : 1, child: child),
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
  const _CountdownChip({required this.room});
  final RoomState room;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 200), (i) => i),
      builder: (_, __) {
        final left = room.remaining(DateTime.now()).inMilliseconds / 1000;
        return Text(
          left.ceil().toString(),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: left < 2 ? SpectreColors.red : SpectreColors.ink),
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
  Widget build(BuildContext context) => PressButton(
        onTap: onTap,
        filled: false,
        color: color,
        glow: false,
        tooltip: label,
        padding: const EdgeInsets.all(12),
        child: Icon(icon),
      );
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
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

// ---------------------------------------------------------------------------
// Sol panel (masaüstü)
// ---------------------------------------------------------------------------

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.room, required this.client, required this.onSeatTap});
  final RoomState room;
  final SpectreClient client;
  final void Function(int) onSeatTap;

  @override
  Widget build(BuildContext context) {
    final me = client.me;
    final r = room.room;
    final occupied = room.seats.where((s) => s.player != null).toList();
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (me != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                PlayerAvatar(player: me.asSeatPlayer(), size: 48),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('Seviye ${me.level} · ♥ ${me.hearts}',
                        style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(children: [
              const Icon(Icons.table_restaurant_rounded, size: 18, color: SpectreColors.accent),
              const SizedBox(width: 8),
              const Expanded(child: Text('Masadakiler', style: TextStyle(fontWeight: FontWeight.w800))),
              Text('${r?.countInGamePlayers ?? 0}/${r?.capacity ?? kSeatCount}',
                  style: const TextStyle(color: SpectreColors.muted)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (r?.countInGamePlayers ?? 0) / (r?.capacity ?? kSeatCount),
                minHeight: 6,
                backgroundColor: Colors.white10,
              ),
            ),
          ),
          Expanded(
            child: occupied.isEmpty
                ? const Center(child: Text('Henüz kimse yok', style: TextStyle(color: SpectreColors.muted)))
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final s in occupied)
                        ListTile(
                          dense: true,
                          onTap: () => onSeatTap(s.index),
                          leading: Opacity(
                            opacity: s.connected ? 1 : 0.45,
                            child: PlayerAvatar(player: s.player!, size: 34, presence: s.presence),
                          ),
                          title: Text(s.player!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            'Koltuk ${s.index + 1} · ${presenceLabel(s.presence)}',
                            style: TextStyle(color: presenceColor(s.presence), fontSize: 11),
                          ),
                          trailing: Text('♥${s.player!.hearts}', style: const TextStyle(color: SpectreColors.pink)),
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
// Bildirimler
// ---------------------------------------------------------------------------

class _Notice {
  _Notice(this.id, this.text, this.kind);
  final int id;
  final String text;
  final String kind;
}

class _NoticeToast extends StatelessWidget {
  const _NoticeToast({super.key, required this.notice});
  final _Notice notice;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (notice.kind) {
      'success' => (Icons.favorite_rounded, SpectreColors.pink),
      'warn' => (Icons.campaign_rounded, SpectreColors.amber),
      'gift' => (Icons.card_giftcard_rounded, SpectreColors.gold),
      _ => (Icons.info_outline_rounded, SpectreColors.accent),
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(notice.text,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sohbet
// ---------------------------------------------------------------------------

class _ChatTicker extends StatelessWidget {
  const _ChatTicker({required this.room, required this.onTap});
  final RoomState room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chat = room.chat;
    final last = chat.length <= 2 ? chat : chat.sublist(chat.length - 2);
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
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(12)),
              child: _ChatLineView(m: m, compact: true),
            ),
        ],
      ),
    );
  }
}

class _ChatLineView extends StatelessWidget {
  const _ChatLineView({required this.m, this.compact = false});
  final ChatLine m;
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
        TextSpan(text: '${m.name}: ', style: TextStyle(color: Color(m.color), fontWeight: FontWeight.w800, fontSize: 13)),
        TextSpan(text: m.text, style: const TextStyle(fontSize: 13)),
      ]),
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.room, required this.client, this.onClose});
  final RoomState room;
  final SpectreClient client;
  final VoidCallback? onClose;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    widget.client.say(text);
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.room.chat;
    final seated = widget.client.me != null && widget.room.seatOf(widget.client.me!.id) != null;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(children: [
              const Icon(Icons.forum_rounded, color: SpectreColors.accent, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Masa sohbeti', style: TextStyle(fontWeight: FontWeight.w800))),
              if (widget.onClose != null)
                IconButton(onPressed: widget.onClose, icon: const Icon(Icons.keyboard_arrow_down_rounded)),
            ]),
          ),
          const Divider(),
          Expanded(
            child: msgs.isEmpty
                ? const Center(child: Text('Henüz mesaj yok', style: TextStyle(color: SpectreColors.muted)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _ChatLineView(m: msgs[msgs.length - 1 - i]),
                    ),
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  enabled: seated,
                  maxLength: 200,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(counterText: '', hintText: seated ? 'Mesaj yaz…' : 'Yazmak için masaya otur'),
                ),
              ),
              const SizedBox(width: 8),
              PressButton(
                onTap: seated ? _send : null,
                padding: const EdgeInsets.all(11),
                radius: 12,
                child: const Icon(Icons.send_rounded),
              ),
            ]),
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
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassPanel(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              ),
              child,
            ]),
          ),
        ),
      ),
    );
  }
}

class _PlayerSheet extends StatefulWidget {
  const _PlayerSheet({required this.seat, required this.client, required this.onGift});
  final SeatView seat;
  final SpectreClient client;
  final VoidCallback onGift;

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    final p = widget.seat.player!;
    widget.client.api.get('/user/api/v1/user/${p.userId}').then((v) {
      if (mounted) setState(() => _profile = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.seat.player!;
    final isMe = p.userId == widget.client.me?.id;
    final online = _profile?['isOnline'] == true;
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(player: p, size: 84, presence: widget.seat.presence),
          const SizedBox(height: 10),
          Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            Chip(label: Text('Seviye ${p.level}')),
            Chip(label: Text('♥ ${p.hearts}')),
            Chip(label: Text('Koltuk ${widget.seat.index + 1}')),
            Chip(
              avatar: CircleAvatar(backgroundColor: online ? SpectreColors.green : SpectreColors.muted, radius: 5),
              label: Text(_profile == null ? '…' : (online ? 'Çevrimiçi' : 'Çevrimdışı')),
            ),
            if (p.vip) const Chip(label: Text('👑 VIP')),
          ]),
          const SizedBox(height: 18),
          if (!isMe)
            SizedBox(
              width: double.infinity,
              child: PressButton(
                color: SpectreColors.gold,
                onTap: widget.client.gifts.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onGift();
                      },
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.card_giftcard_rounded),
                  SizedBox(width: 8),
                  Text('Hediye gönder'),
                ]),
              ),
            )
          else
            PressButton(
              filled: false,
              onTap: () {
                widget.client.standUp();
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
  const _GiftSheet({required this.room, required this.client, this.initialTarget});
  final RoomState room;
  final SpectreClient client;
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
    final c = widget.client;
    final meId = c.me?.id;
    final others = widget.room.seats.where((s) => s.player != null && s.player!.userId != meId).toList();
    _target ??= others.isNotEmpty ? others.first.index : null;
    final cats = ['Tümü', ...{for (final g in c.gifts) g.category}];
    final gifts = c.gifts.where((g) => _cat == 'Tümü' || g.category == _cat).toList();
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Hediye gönder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            ListenableBuilder(listenable: c, builder: (_, __) => CoinPill(coins: c.me?.coins ?? 0)),
          ]),
          const SizedBox(height: 12),
          if (others.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Masada hediye gönderilecek kimse yok'))
          else
            SizedBox(
              height: 78,
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
                          border: Border.all(color: _target == s.index ? SpectreColors.gold : Colors.transparent, width: 2),
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
                for (final cat in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(cat), selected: _cat == cat, onSelected: (_) => setState(() => _cat = cat)),
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
                final afford = (c.me?.coins ?? 0) >= g.price;
                return PressButton(
                  filled: false,
                  glow: false,
                  color: afford ? SpectreColors.gold : SpectreColors.muted,
                  padding: const EdgeInsets.all(6),
                  onTap: _target == null || !afford
                      ? null
                      : () {
                          c.sendGift(_target!, g);
                          Navigator.pop(context);
                        },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(g.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    Text(g.name, style: const TextStyle(fontSize: 11, color: SpectreColors.ink)),
                    Text('🪙 ${g.price}', style: const TextStyle(fontSize: 11)),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
