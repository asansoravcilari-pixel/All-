import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spectre_core/spectre_core.dart';

import '../data/client.dart';
import '../data/room_state.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../data/api.dart';
import 'lobby_screen.dart';
import 'social.dart';
import 'table_stage.dart';

// v39 masa sayfasının renkleri
const _btnBg = Color(0xFF0B2843);
const _btnBorder = Color(0xFF426D8D);
const _btnInk = Color(0xFFCAEFFC);
const _hudBg = Color(0xDA020B16);
const _hudBorder = Color(0xFF204560);
const _hudSmall = Color(0xFF9BDBF4);
const _line = Color(0xFF255478);

/// Masa ekranı — v39 yapısı (yukarıdan aşağı):
/// üst bilgi çubuğu · araç düğmeleri · 12 koltuklu kare masa · masa sohbeti · mesaj satırı · bağlantı durumu.
/// Geniş ekranda aynı sütun ortada; solda oyuncular, sağda sohbet.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.room});
  final RoomState room;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final _toasts = <_Notice>[];
  StreamSubscription<String>? _errSub;
  StreamSubscription<String>? _noticeSub;
  bool _chatExpanded = false;
  int _noticeId = 0;

  RoomState get t => widget.room;

  @override
  void initState() {
    super.initState();
    t.addFxListener(_onFx);
    final c = ClientScope.read(context);
    _errSub = c.errors.listen((m) => _push(m, 'warn'));
    _noticeSub = c.notices.listen((m) => _push(m, 'info'));
  }

  @override
  void dispose() {
    t.removeFxListener(_onFx);
    _errSub?.cancel();
    _noticeSub?.cancel();
    super.dispose();
  }

  void _onFx(RoomFx e) {
    final me = ClientScope.read(context).me;
    final mySeat = me == null ? null : t.seatOf(me.id);
    switch (e) {
      case FxNotice(:final text, :final kind):
        _push(text, kind);
      case FxMatch(:final a, :final b, :final success):
        if (success && (a == mySeat || b == mySeat)) HapticFeedback.mediumImpact();
      default:
        break;
    }
  }

  void _push(String text, String kind) {
    if (!mounted) return;
    final n = _Notice(_noticeId++, text, kind);
    setState(() {
      _toasts.add(n);
      if (_toasts.length > 3) _toasts.removeAt(0);
    });
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (mounted) setState(() => _toasts.remove(n));
    });
  }

  // ---------------------------------------------------------------------------
  // Eylemler
  // ---------------------------------------------------------------------------

  void _onSeatTap(int index) {
    final c = ClientScope.read(context);
    final seat = t.seats[index];
    if (seat.player == null) {
      if (c.me != null && t.seatOf(c.me!.id) == null) c.sit(seat: index);
      return;
    }
    _sheet(_PlayerSheet(
      seat: seat,
      client: c,
      onGift: () => _openGifts(toSeat: index),
      onMessage: () => showDmThread(context, c, seat.player!.userId),
    ));
  }

  void _sheet(Widget child) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => child,
      );

  void _openGifts({int? toSeat, bool group = false}) =>
      _sheet(_GiftSheet(room: t, client: ClientScope.read(context), initialTarget: toSeat, group: group));

  void _openTables() {
    final c = ClientScope.read(context);
    c.refreshRooms();
    _sheet(SheetFrame(
      title: c.t('tools.tables', 'Aktif masa seçimi'),
      subtitle: c.config.popup('tables'),
      child: ListenableBuilder(
        listenable: c,
        builder: (ctx, _) => ListView(shrinkWrap: true, children: [
          for (final r in c.rooms)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.table_restaurant_rounded, color: r.id == t.roomId ? SpectreColors.accent : SpectreColors.muted),
              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${r.countInGamePlayers}/${r.capacity} koltuk · ${r.inGamePlayers} aktif${r.locked ? ' · kilitli' : ''}'),
              trailing: r.id == t.roomId
                  ? const StatusBadgeLite('Buradasın')
                  : TextButton(
                      onPressed: r.locked || r.isFull
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              Navigator.of(context).pushReplacement(spectreRoute(TableScreen(room: c.openRoom(r.id))));
                            },
                      child: const Text('Geç'),
                    ),
            ),
        ]),
      ),
    ));
  }

  Future<void> _bonus() async {
    final c = ClientScope.read(context);
    try {
      final n = await c.claimDaily();
      _push('Günlük bonus: +$n 🪙', 'gift');
    } catch (e) {
      _push('$e', 'warn');
    }
  }

  void _openInbox() => _sheet(NotificationsSheet(client: ClientScope.read(context)));

  void _openDms() => _sheet(DmInboxSheet(client: ClientScope.read(context)));

  void _exitMenu() {
    final c = ClientScope.read(context);
    final seated = c.me != null && t.seatOf(c.me!.id) != null;
    _sheet(SheetFrame(
      title: c.t('tools.exit', 'Çıkış menüsü'),
      subtitle: c.config.popup('exit'),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (seated)
          ListTile(
            leading: const Icon(Icons.event_seat_outlined),
            title: const Text('Masadan kalk (izlemeye devam et)'),
            onTap: () {
              Navigator.pop(context);
              c.standUp();
            },
          ),
        ListTile(
          leading: const Icon(Icons.swap_horiz_rounded),
          title: const Text('Masa değiştir'),
          onTap: () {
            Navigator.pop(context);
            _openTables();
          },
        ),
        if (c.config.support)
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('Destek'),
            onTap: () {
              Navigator.pop(context);
              _sheet(SupportSheet(client: c));
            },
          ),
        ListTile(
          leading: const Icon(Icons.home_rounded),
          title: const Text('Lobiye dön'),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).maybePop();
          },
        ),
      ]),
    ));
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = ClientScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final three = width >= 1200;
    final two = width >= 900;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // Masa değiştirirken (yeni masa zaten açıldıysa) eski ekran kapanınca yeni masadan kalkılmasın.
        if (didPop && c.room?.roomId == t.roomId) c.closeRoom();
      },
      child: ListenableBuilder(
        listenable: t,
        builder: (context, _) {
          final meId = c.me?.id ?? '';
          final seated = t.seatOf(meId) != null;

          final hud = _Hud(room: t, client: c, onCoins: () => Navigator.of(context).push(spectreRoute(const MarketScreen())));
          final tools = _ToolRow(
            client: c,
            unread: c.me?.unreadNotices ?? 0,
            onTables: _openTables,
            onBonus: c.me?.canClaimDaily == true ? _bonus : null,
            onMarket: () => Navigator.of(context).push(spectreRoute(const MarketScreen())),
            onProfile: c.me == null ? null : () => _sheet(ProfileSheet(client: c)),
            onInbox: _openInbox,
            onExit: _exitMenu,
          );
          final stage = Center(
            child: !t.loaded
                ? const CircularProgressIndicator()
                : TableStage(
                    table: t,
                    meId: meId,
                    onSeatTap: _onSeatTap,
                    light: c.lightMode,
                    anim: c.config.animations,
                    status: _RoundCentre(room: t, client: c, seated: seated, statusOnly: true),
                    centre: _RoundCentre(room: t, client: c, seated: seated),
                  ),
          );
          final chat = _ChatWrap(
            room: t,
            client: c,
            onTapUser: (id) {
              final seat = t.seatOf(id);
              if (seat != null) _onSeatTap(seat);
            },
            expanded: _chatExpanded,
            onToggle: two ? null : () => setState(() => _chatExpanded = !_chatExpanded),
          );
          final composer = _Composer(
            client: c,
            seated: seated,
            onGift: () => _openGifts(),
            onGroupGift: () => _openGifts(group: true),
            onMessages: _openDms,
          );
          final link = _LinkLine(state: c.link, room: t, client: c);
          final toasts = Positioned(
            top: 4,
            left: 12,
            right: 12,
            child: IgnorePointer(
              child: Column(children: [for (final n in _toasts) _NoticeToast(key: ValueKey(n.id), notice: n)]),
            ),
          );

          Widget body;
          if (two) {
            final centre = Column(children: [
              hud,
              tools,
              Expanded(child: Stack(children: [Positioned.fill(child: Padding(padding: const EdgeInsets.all(10), child: stage)), toasts])),
            ]);
            final right = Column(children: [
              Expanded(child: chat),
              composer,
              link,
            ]);
            body = Row(children: [
              if (three)
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                    child: _InfoPanel(room: t, client: c, onSeatTap: _onSeatTap),
                  ),
                ),
              Expanded(child: centre),
              Container(
                width: three ? 380 : 340,
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: _line))),
                child: right,
              ),
            ]);
          } else {
            // Telefon: v39 ile aynı dikey yapı
            final screenH = MediaQuery.sizeOf(context).height;
            body = Column(children: [
              hud,
              tools,
              AnimatedContainer(
                duration: SpectreMotion.normal,
                curve: SpectreMotion.curve,
                height: _chatExpanded ? screenH * 0.30 : null,
                constraints: BoxConstraints(maxHeight: screenH * 0.54),
                child: Stack(children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: stage),
                  toasts,
                ]),
              ),
              Expanded(child: chat),
              composer,
              link,
            ]);
          }
          return Scaffold(
            resizeToAvoidBottomInset: true,
            body: SpectreBackground(animate: !c.lightMode, child: SafeArea(child: body)),
          );
        },
      ),
    );
  }
}


class StatusBadgeLite extends StatelessWidget {
  const StatusBadgeLite(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: SpectreColors.accent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SpectreColors.accent.withOpacity(0.5)),
        ),
        child: Text(text, style: const TextStyle(color: SpectreColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

// ---------------------------------------------------------------------------
// 1) Üst bilgi çubuğu (4 kutu)
// ---------------------------------------------------------------------------

class _Hud extends StatelessWidget {
  const _Hud({required this.room, required this.client, required this.onCoins});
  final RoomState room;
  final SpectreClient client;
  final VoidCallback onCoins;

  @override
  Widget build(BuildContext context) {
    final r = room.room;
    Widget cell(String value, String label) => Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: _hudBg,
            border: Border.all(color: _hudBorder),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(color: const Color(0x6609496F), borderRadius: BorderRadius.circular(3)),
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: _hudSmall)),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
      child: Row(children: [
        Expanded(child: cell(r?.name ?? '…', '${client.t('hud.round', 'Tur')} ${room.round.roundNo}')),
        const SizedBox(width: 5),
        Expanded(child: cell('${client.me?.hearts ?? 0}', client.t('hud.hearts', 'Kalp'))),
        const SizedBox(width: 5),
        Expanded(child: cell('${r?.countInGamePlayers ?? 0}/${r?.capacity ?? kSeatCount}', client.t('hud.players', 'Oyuncu'))),
        const SizedBox(width: 5),
        Expanded(
          flex: 115,
          child: Material(
            color: _hudBg,
            shape: RoundedRectangleBorder(side: const BorderSide(color: _hudBorder), borderRadius: BorderRadius.circular(5)),
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: onCoins,
              child: Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  const Text('🪙', style: TextStyle(fontSize: 13)),
                  Flexible(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (client.me?.coins ?? 0).toDouble()),
                      duration: SpectreMotion.slow,
                      builder: (_, v, __) => Text('${v.round()}',
                          maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SpectreColors.gold)),
                    ),
                  ),
                  const Text('＋', style: TextStyle(fontSize: 14, color: _btnInk)),
                ]),
              ),
            ),
          ),
        ),
      ].map((w) => w is Expanded && w.flex == 1 ? Expanded(flex: 100, child: w.child) : w).toList()),
    );
  }
}

// ---------------------------------------------------------------------------
// 2) Araç düğmeleri
// ---------------------------------------------------------------------------

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.client,
    required this.unread,
    required this.onTables,
    required this.onBonus,
    required this.onMarket,
    required this.onProfile,
    required this.onInbox,
    required this.onExit,
  });
  final SpectreClient client;
  final int unread;
  final VoidCallback onTables;
  final VoidCallback? onBonus;
  final VoidCallback onMarket;
  final VoidCallback? onProfile;
  final VoidCallback onInbox;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Row(children: [
        _ToolButton(icon: Icons.table_restaurant_rounded, label: client.t('tools.tables', 'Aktif masa seçimi'), onTap: onTables),
        _ToolButton(
            icon: Icons.stars_rounded, label: client.t('tools.bonus', 'Günlük bonus'), onTap: onBonus, highlight: onBonus != null),
        _ToolButton(icon: Icons.storefront_rounded, label: client.t('tools.market', 'Market'), onTap: onMarket),
        _ToolButton(icon: Icons.person_rounded, label: client.t('tools.profile', 'Profil'), onTap: onProfile),
        _ToolButton(
            icon: Icons.notifications_rounded, label: client.t('tools.notifications', 'Bildirimler'), onTap: onInbox, badge: unread),
        const Spacer(),
        _ToolButton(icon: Icons.logout_rounded, label: client.t('tools.exit', 'Çıkış menüsü'), onTap: onExit, gap: false),
      ]),
    );
  }
}

class _ToolButton extends StatefulWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.badge = 0, this.highlight = false, this.gap = true});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;
  final bool highlight;
  final bool gap;

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Padding(
      padding: EdgeInsets.only(right: widget.gap ? 4 : 0),
      child: Tooltip(
        message: widget.label,
        child: Semantics(
          button: true,
          label: widget.label,
          child: GestureDetector(
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapCancel: () => setState(() => _down = false),
            onTapUp: enabled
                ? (_) {
                    setState(() => _down = false);
                    HapticFeedback.selectionClick();
                    widget.onTap!();
                  }
                : null,
            child: AnimatedScale(
              scale: _down ? 0.9 : 1,
              duration: SpectreMotion.fast,
              child: Stack(clipBehavior: Clip.none, children: [
                AnimatedContainer(
                  duration: SpectreMotion.normal,
                  width: 40,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _btnBg,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: widget.highlight ? SpectreColors.gold : _btnBorder),
                    boxShadow: widget.highlight ? [BoxShadow(color: SpectreColors.gold.withOpacity(0.35), blurRadius: 10)] : null,
                  ),
                  child: Icon(widget.icon, size: 20, color: enabled ? (widget.highlight ? SpectreColors.gold : _btnInk) : _btnBorder),
                ),
                if (widget.badge > 0) Positioned(right: -5, top: -5, child: CountBadge(count: widget.badge)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3) Masanın ortası: tur durumu + düğmeler
// ---------------------------------------------------------------------------

class _RoundCentre extends StatelessWidget {
  const _RoundCentre({required this.room, required this.client, required this.seated, this.statusOnly = false});
  final RoomState room;
  final SpectreClient client;
  final bool seated;

  /// true: yalnız durum yazısı; false: yalnız düğmeler.
  final bool statusOnly;

  @override
  Widget build(BuildContext context) {
    final meId = client.me?.id ?? '';
    final r = room.round;
    final mySeat = room.seatOf(meId);
    final spinner = room.seats[r.spinnerSeat].player;
    final target = r.targetSeat == null ? null : room.seats[r.targetSeat!].player;
    final myTurn = mySeat != null && r.active && r.phase == RoundPhase.idle && r.spinnerSeat == mySeat;
    final involved = mySeat != null &&
        r.phase == RoundPhase.deciding &&
        ((r.spinnerSeat == mySeat && r.spinnerAccepted == null) || (r.targetSeat == mySeat && r.targetAccepted == null));

    String status;
    Color color = _hudSmall;
    final c = client;
    if (!r.active) {
      status = room.occupied == 0 ? c.t('table.empty', 'Masa boş') : c.t('table.waiting', 'İkinci oyuncu bekleniyor');
    } else {
      switch (r.phase) {
        case RoundPhase.idle:
          status = myTurn ? c.t('table.yourTurn', 'Sıra sende') : 'Sıra: ${spinner?.name ?? '-'}';
          if (myTurn) color = SpectreColors.accent;
        case RoundPhase.spinning:
          status = '${spinner?.name ?? ''} çeviriyor…';
        case RoundPhase.deciding:
          status = '${spinner?.name} ve ${target?.name}';
          color = SpectreColors.pink;
        case RoundPhase.result:
          final ok = (r.spinnerAccepted ?? false) && (r.targetAccepted ?? false);
          status = ok ? '💞 ${c.t('table.match', 'Eşleşme!')}' : c.t('table.pass', 'Pas geçildi');
          color = ok ? SpectreColors.green : _hudSmall;
      }
    }

    Widget? control;
    if (!seated) {
      control = _CentreButton(
        label: c.t('table.sit', 'Otur'),
        icon: Icons.event_seat_rounded,
        onTap: room.isFull || (room.room?.locked ?? false) ? null : () => client.sit(),
      );
    } else if (involved) {
      control = Row(mainAxisSize: MainAxisSize.min, children: [
        _CentreButton(
            label: c.t('table.reject', 'Pas'), icon: Icons.close_rounded, color: SpectreColors.red, onTap: () => client.decide(false)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _Countdown(room: room)),
        _CentreButton(
            label: c.t('table.accept', 'Kabul'), icon: Icons.favorite_rounded, color: SpectreColors.pink, onTap: () => client.decide(true)),
      ]);
    } else if (myTurn) {
      control = _CentreButton(
        label: c.t('table.spin', 'ÇEVİR'),
        icon: Icons.autorenew_rounded,
        pulse: true,
        onTap: () {
          HapticFeedback.heavyImpact();
          client.spin();
        },
      );
    }

    if (!statusOnly) {
      return AnimatedSwitcher(
        duration: SpectreMotion.normal,
        switchInCurve: SpectreMotion.spring,
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
        child: control == null
            ? const SizedBox(key: ValueKey('none'), width: 1, height: 1)
            : KeyedSubtree(key: ValueKey('${r.phase}|$myTurn|$involved|$seated'), child: control),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedSwitcher(
        duration: SpectreMotion.normal,
        child: Text(status,
            key: ValueKey(status),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
      ),
    ]);
  }
}

class _CentreButton extends StatefulWidget {
  const _CentreButton({required this.label, required this.icon, required this.onTap, this.color = SpectreColors.accent, this.pulse = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool pulse;

  @override
  State<_CentreButton> createState() => _CentreButtonState();
}

class _CentreButtonState extends State<_CentreButton> with SingleTickerProviderStateMixin {
  late final AnimationController _p = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _p.repeat(reverse: true);
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _p,
      builder: (_, child) => Transform.scale(scale: 1 + _p.value * 0.06, child: child),
      child: PressButton(
        onTap: widget.onTap,
        color: widget.color,
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, size: 18),
          const SizedBox(width: 6),
          Text(widget.label, style: const TextStyle(letterSpacing: 0.8)),
        ]),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.room});
  final RoomState room;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(milliseconds: 200), (i) => i),
      builder: (_, __) {
        final left = room.remaining(DateTime.now()).inMilliseconds / 1000;
        return Text(left.ceil().toString(),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: left < 2 ? SpectreColors.red : SpectreColors.ink));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 4) Masa sohbeti
// ---------------------------------------------------------------------------

class _ChatWrap extends StatelessWidget {
  const _ChatWrap({required this.room, required this.client, required this.onTapUser, required this.expanded, required this.onToggle});
  final RoomState room;
  final SpectreClient client;
  final void Function(String userId) onTapUser;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final msgs = room.chat;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
        child: Row(children: [
          Text(client.t('chat.title', 'Masa Sohbeti'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _hudSmall, letterSpacing: 0.4)),
          const Spacer(),
          if (client.config.translate)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: client.showTranslations ? 'Çevirileri gizle' : 'Çevirileri göster',
              onPressed: () => client.setShowTranslations(!client.showTranslations),
              icon: Icon(Icons.translate_rounded,
                  size: 19, color: client.showTranslations ? SpectreColors.cyan : SpectreColors.muted),
            ),
          if (onToggle != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: expanded ? 'Sohbeti daralt' : 'Sohbeti genişlet',
              onPressed: onToggle,
              icon: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: SpectreMotion.normal,
                child: const Icon(Icons.keyboard_arrow_up_rounded, color: _btnInk),
              ),
            ),
        ]),
      ),
      Expanded(
        child: msgs.isEmpty
            ? const Center(child: Text('Henüz mesaj yok', style: TextStyle(color: SpectreColors.muted, fontSize: 12)))
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[msgs.length - 1 - i];
                  return ChatLineView(
                    key: ValueKey(m.id.isEmpty ? '${m.at.millisecondsSinceEpoch}-$i' : m.id),
                    m: m,
                    lang: client.me?.lang ?? 'tr',
                    onTapUser: onTapUser,
                    client: client,
                  );
                },
              ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 5) Mesaj satırı
// ---------------------------------------------------------------------------

class _Composer extends StatefulWidget {
  const _Composer({
    required this.client,
    required this.seated,
    required this.onGift,
    required this.onGroupGift,
    required this.onMessages,
  });
  final SpectreClient client;
  final bool seated;
  final VoidCallback onGift;
  final VoidCallback onGroupGift;
  final VoidCallback onMessages;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _ctl = TextEditingController();

  List<String> get _reactions {
    final r = '${widget.client.config.animations['reactions'] ?? ''}'.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    return r.isEmpty ? const ['❤️', '😂', '😮', '👏', '🔥', '😍'] : r;
  }

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

  Future<void> _react() async {
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final e = await showMenu<String>(
      context: context,
      color: SpectreColors.panel,
      position: RelativeRect.fromLTRB(pos.dx + 40, pos.dy - 60, pos.dx + 40, pos.dy),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final r in _reactions)
              InkWell(
                onTap: () => Navigator.pop(context, r),
                child: Padding(padding: const EdgeInsets.all(6), child: Text(r, style: const TextStyle(fontSize: 22))),
              ),
          ]),
        ),
      ],
    );
    if (e != null) widget.client.react(e);
  }

  @override
  Widget build(BuildContext context) {
    final seated = widget.seated;
    final hasGifts = widget.client.gifts.isNotEmpty;
    final c = widget.client;
    Widget btn(IconData i, String label, VoidCallback? f, {Color? color, int badge = 0}) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: label,
            child: Stack(clipBehavior: Clip.none, children: [
              Material(
              color: _btnBg,
              shape: RoundedRectangleBorder(side: const BorderSide(color: _btnBorder), borderRadius: BorderRadius.circular(5)),
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: f,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(i, size: 19, color: f == null ? _btnBorder : (color ?? _btnInk)),
                ),
              ),
            ),
              if (badge > 0) Positioned(right: -5, top: -5, child: CountBadge(count: badge)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctl,
            enabled: seated,
            maxLength: 200,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              counterText: '',
              hintText: seated ? c.t('chat.placeholder', 'Mesaj yaz') : c.t('chat.sitToWrite', 'Yazmak için masaya otur'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: _btnBorder)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: _btnBorder)),
            ),
          ),
        ),
        btn(Icons.emoji_emotions_rounded, c.t('composer.react', 'Tepki'), seated ? _react : null),
        btn(Icons.card_giftcard_rounded, c.t('composer.gift', 'Oyuncuya hediye'), seated && hasGifts ? widget.onGift : null,
            color: SpectreColors.gold),
        btn(
            c.me?.isLocked('groupGift') == true ? Icons.lock_rounded : Icons.volunteer_activism_rounded,
            c.t('composer.groupGift', 'Toplu hediye'),
            !(seated && hasGifts)
                ? null
                : c.me?.isLocked('groupGift') == true
                    ? () => showLocked(context, c, 'groupGift')
                    : widget.onGroupGift,
            color: SpectreColors.gold),
        btn(Icons.mail_rounded, c.t('composer.messages', 'Mesaj kutusu'), widget.onMessages, badge: c.me?.unreadDms ?? 0),
        btn(Icons.send_rounded, 'Gönder', seated ? _send : null, color: SpectreColors.accent),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 6) Bağlantı durumu
// ---------------------------------------------------------------------------

class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.state, required this.room, required this.client});
  final LinkState state;
  final RoomState room;
  final SpectreClient client;

  @override
  Widget build(BuildContext context) {
    final (c, text) = switch (state) {
      LinkState.online => (SpectreColors.green, '${client.t('link.online', 'Canlı bağlantı')} · ${room.room?.name ?? ''}'),
      LinkState.connecting => (SpectreColors.amber, 'Bağlanıyor…'),
      LinkState.offline => (SpectreColors.red, client.t('link.offline', 'Canlı oyun bağlantısı yok')),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: c.withOpacity(0.08),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 11, color: c)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Oyuncu listesi (masaüstü sol panel) ve bildirim kartı
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
// Alt sayfalar
// ---------------------------------------------------------------------------

class _PlayerSheet extends StatefulWidget {
  const _PlayerSheet({required this.seat, required this.client, required this.onGift, required this.onMessage});
  final SeatView seat;
  final SpectreClient client;
  final VoidCallback onGift;
  final VoidCallback onMessage;

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    final p = widget.seat.player!;
    widget.client.api.get(ApiConfig.ep('user', {'userId': p.userId})).then((v) {
      if (mounted) setState(() => _profile = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.seat.player!;
    final isMe = p.userId == widget.client.me?.id;
    final online = _profile?['isOnline'] == true;
    return SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquareAvatar(name: p.name, color: p.color, url: p.avatarUrl, size: 92, online: _profile == null ? null : online),
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
            Row(children: [
              Expanded(
                child: PressButton(
                  color: SpectreColors.gold,
                  onTap: widget.client.gifts.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context);
                          widget.onGift();
                        },
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.card_giftcard_rounded),
                    const SizedBox(width: 8),
                    Flexible(child: Text(widget.client.t('composer.gift', 'Hediye gönder'), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PressButton(
                  onTap: widget.client.me?.guest == true
                      ? null
                      : widget.client.me?.isLocked('dm') == true
                          ? () => showLocked(context, widget.client, 'dm')
                          : () {
                              Navigator.pop(context);
                              widget.onMessage();
                            },
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(widget.client.me?.isLocked('dm') == true ? Icons.lock_rounded : Icons.mail_rounded),
                    const SizedBox(width: 8),
                    const Text('Mesaj gönder'),
                  ]),
                ),
              ),
            ])
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
  const _GiftSheet({required this.room, required this.client, this.initialTarget, this.group = false});
  final RoomState room;
  final SpectreClient client;
  final int? initialTarget;

  /// Toplu hediye: masadaki herkese.
  final bool group;

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
    return SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.group ? '${c.t('composer.groupGift', 'Toplu hediye')} (${others.length})' : c.t('composer.gift', 'Hediye gönder'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if (c.config.popup(widget.group ? 'groupGift' : 'gift').isNotEmpty)
                  Text(c.config.popup(widget.group ? 'groupGift' : 'gift'),
                      style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
              ]),
            ),
            ListenableBuilder(listenable: c, builder: (_, __) => CoinPill(coins: c.me?.coins ?? 0)),
          ]),
          const SizedBox(height: 12),
          if (others.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Masada hediye gönderilecek kimse yok'))
          else if (!widget.group)
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
                final owned = c.me?.inventory[g.id] ?? 0;
                final cost = widget.group ? g.price * others.length : (owned > 0 ? 0 : g.price);
                final afford = others.isNotEmpty && (c.me?.coins ?? 0) >= cost;
                return PressButton(
                  filled: false,
                  glow: false,
                  color: afford ? SpectreColors.gold : SpectreColors.muted,
                  padding: const EdgeInsets.all(6),
                  onTap: !afford || (!widget.group && _target == null)
                      ? null
                      : () {
                          if (widget.group) {
                            c.sendGiftAll(g);
                          } else {
                            c.sendGift(_target!, g);
                          }
                          Navigator.pop(context);
                        },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(g.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    Text(g.name, style: const TextStyle(fontSize: 11, color: SpectreColors.ink)),
                    Text(!widget.group && owned > 0 ? '🎁 ×$owned' : '🪙 $cost',
                        style: TextStyle(fontSize: 11, color: !widget.group && owned > 0 ? SpectreColors.green : null)),
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
