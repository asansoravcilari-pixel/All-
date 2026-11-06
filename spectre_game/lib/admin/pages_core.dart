import 'package:flutter/material.dart';
import 'package:spectre_core/spectre_core.dart';

import '../game/stage_painters.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_client.dart';
import 'admin_common.dart';

SeatPlayer _sp(Json u) => SeatPlayer(
      userId: '${u['id']}',
      name: '${u['displayName'] ?? u['username'] ?? '?'}',
      color: jn(u['color']) == 0 ? 0xFF65C5FF : jn(u['color']),
      level: jn(u['level']),
      vip: u['role'] == 'vip',
      hearts: jn(u['hearts']),
    );

// ---------------------------------------------------------------------------
// Kontrol Merkezi
// ---------------------------------------------------------------------------

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ApiView(
      refresh: const Duration(seconds: 5),
      load: (a) => a.get('/dashboard'),
      builder: (context, d, reload) {
        final rev = [for (final v in (d['revenue14'] as List? ?? const [])) jn(v)];
        final rooms = jl(d['rooms']);
        final audit = jl(d['audit']);
        final pending = jn(d['pendingOrders']);
        return AdminPage(
          title: 'Kontrol Merkezi',
          subtitle: 'Platformun canlı özeti (5 sn’de bir yenilenir)',
          actions: [
            PressButton(
              onTap: () async {
                final t = await askText(context, 'Tüm masalara duyuru', hint: 'Örn. 10 dk sonra etkinlik başlıyor!');
                if (t == null || t.trim().isEmpty || !context.mounted) return;
                await act(context, () => AdminScope.read(context).post('/broadcast', {'text': t.trim()}),
                    ok: 'Duyuru gönderildi');
              },
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.campaign_rounded),
                SizedBox(width: 6),
                Text('Duyuru yap'),
              ]),
            ),
          ],
          children: [
            if (d['maintenance'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: StatusBadge('Bakım modu açık — oyuncular masaya giremez', SpectreColors.amber),
              ),
            ResponsiveGrid(children: [
              StatTile(label: 'Çevrimiçi oyuncu', value: '${jn(d['online'])}', icon: Icons.wifi_rounded),
              StatTile(
                  label: 'Masada oturan',
                  value: '${jn(d['seated'])}',
                  icon: Icons.event_seat_rounded,
                  color: SpectreColors.cyan),
              StatTile(
                  label: 'Aktif masa',
                  value: '${jn(d['activeRooms'])}',
                  icon: Icons.table_restaurant_rounded,
                  color: SpectreColors.cyan),
              StatTile(
                  label: 'Bugünkü gelir',
                  value: tl(jn(d['todayRevenue'])),
                  icon: Icons.payments_rounded,
                  color: SpectreColors.green),
              StatTile(
                  label: 'Onay bekleyen sipariş',
                  value: '$pending',
                  icon: Icons.pending_actions_rounded,
                  color: pending > 0 ? SpectreColors.amber : SpectreColors.muted),
              StatTile(label: 'Kayıtlı oyuncu', value: '${jn(d['users'])}', icon: Icons.badge_rounded, color: SpectreColors.pink),
              StatTile(label: 'Yasaklı hesap', value: '${jn(d['banned'])}', icon: Icons.block_rounded, color: SpectreColors.red),
            ]),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, box) {
              final revenue = SectionCard(
                title: 'Son 14 gün gelir',
                icon: Icons.bar_chart_rounded,
                trailing: Text(tl(rev.fold(0, (a, b) => a + b)), style: const TextStyle(fontWeight: FontWeight.w800)),
                child: rev.every((v) => v == 0)
                    ? const SizedBox(
                        height: 140,
                        child: Center(child: Text('Henüz ödenmiş sipariş yok', style: TextStyle(color: SpectreColors.muted))))
                    : BarChart(values: rev, color: SpectreColors.green),
              );
              final occupancy = SectionCard(
                title: 'Masa doluluğu',
                icon: Icons.donut_large_rounded,
                child: rooms.isEmpty
                    ? const Text('Açık masa yok', style: TextStyle(color: SpectreColors.muted))
                    : Column(children: [
                        for (final r in rooms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              SizedBox(width: 110, child: Text('${r['name']}', overflow: TextOverflow.ellipsis)),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: jn(r['countInGamePlayers']) / kSeatCount,
                                    minHeight: 8,
                                    backgroundColor: Colors.white10,
                                    color: TableTheme.all[jn(r['theme']) % 4].primary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                  width: 48,
                                  child: Text('  ${jn(r['countInGamePlayers'])}/12', style: const TextStyle(fontSize: 12))),
                            ]),
                          ),
                      ]),
              );
              if (box.maxWidth < 900) return Column(children: [revenue, occupancy]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: revenue),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: occupancy),
              ]);
            }),
            SectionCard(
              title: 'Son yönetim işlemleri',
              icon: Icons.history_rounded,
              child: audit.isEmpty
                  ? const Text('Henüz işlem yok', style: TextStyle(color: SpectreColors.muted))
                  : Column(children: [
                      for (final e in audit)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.bolt_rounded, size: 18, color: SpectreColors.accent),
                          title: Text('${e['action']} — ${e['target']}'),
                          subtitle: Text('${e['actor']}'),
                          trailing: Text(ago(jd(e['at']) ?? DateTime.now()),
                              style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Oyuncular
// ---------------------------------------------------------------------------

class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key});

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage> {
  String _q = '';
  String _status = '';
  String _role = '';
  bool _online = false;
  String _sort = 'new';

  @override
  Widget build(BuildContext context) {
    return ApiView(
      key: ValueKey('$_q|$_status|$_role|$_online|$_sort'),
      refresh: const Duration(seconds: 10),
      load: (a) => a.get('/users', {
        if (_q.isNotEmpty) 'q': _q,
        if (_status.isNotEmpty) 'status': _status,
        if (_role.isNotEmpty) 'role': _role,
        if (_online) 'online': '1',
        'sort': _sort,
      }),
      builder: (context, d, reload) {
        final list = jl(d['items']);
        return AdminPage(
          title: 'Oyuncular',
          subtitle: '${jn(d['total'])} hesap',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    initialValue: _q,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Kullanıcı adı, ad veya ID'),
                    onFieldSubmitted: (v) => setState(() => _q = v.trim()),
                  ),
                ),
                DropdownButton<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Tüm durumlar')),
                    DropdownMenuItem(value: 'active', child: Text('Aktif')),
                    DropdownMenuItem(value: 'muted', child: Text('Susturuldu')),
                    DropdownMenuItem(value: 'suspended', child: Text('Askıda')),
                    DropdownMenuItem(value: 'banned', child: Text('Yasaklı')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? ''),
                ),
                DropdownButton<String>(
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Tüm roller')),
                    DropdownMenuItem(value: 'player', child: Text('Oyuncu')),
                    DropdownMenuItem(value: 'vip', child: Text('VIP')),
                    DropdownMenuItem(value: 'moderator', child: Text('Moderatör')),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? ''),
                ),
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(value: 'new', child: Text('En yeni')),
                    DropdownMenuItem(value: 'level', child: Text('Seviye')),
                    DropdownMenuItem(value: 'coins', child: Text('Coin')),
                    DropdownMenuItem(value: 'spent', child: Text('Harcama')),
                    DropdownMenuItem(value: 'hearts', child: Text('Kalp')),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'new'),
                ),
                FilterChip(
                  label: const Text('Yalnız çevrimiçi'),
                  selected: _online,
                  onSelected: (v) => setState(() => _online = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('Oyuncu yok', style: TextStyle(color: SpectreColors.muted))))
                  : Column(children: [
                      for (final u in list)
                        ListTile(
                          onTap: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => AdminScope(
                                  admin: AdminScope.read(context), child: PlayerDetailDialog(userId: '${u['id']}')),
                            );
                            reload();
                          },
                          leading: PlayerAvatar(
                              player: _sp(u), size: 40, presence: u['isOnline'] == true ? Presence.online : null),
                          title: Row(children: [
                            Flexible(
                              child: Text('${u['displayName']}',
                                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 6),
                            Text('@${u['username']}', style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                            const SizedBox(width: 8),
                            if (u['role'] != 'player') StatusBadge(roleLabel('${u['role']}'), SpectreColors.gold),
                            if (u['status'] != 'active') ...[
                              const SizedBox(width: 4),
                              StatusBadge(statusLabel('${u['status']}'), SpectreColors.red),
                            ],
                            if (u['guest'] == true) ...[
                              const SizedBox(width: 4),
                              const StatusBadge('Misafir', SpectreColors.muted),
                            ],
                          ]),
                          subtitle: Text(
                            'Sv ${jn(u['level'])} · 🪙 ${jn(u['coins'])} · ♥ ${jn(u['hearts'])}'
                            '${u['roomName'] != null ? ' · 🟢 ${u['roomName']}' : ''}',
                            style: const TextStyle(color: SpectreColors.muted, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

class PlayerDetailDialog extends StatefulWidget {
  const PlayerDetailDialog({super.key, required this.userId});
  final String userId;

  @override
  State<PlayerDetailDialog> createState() => _PlayerDetailDialogState();
}

class _PlayerDetailDialogState extends State<PlayerDetailDialog> {
  int _gen = 0;

  Future<void> _do(Json body, {String? ok}) async {
    await act(context, () => AdminScope.read(context).post('/users/${widget.userId}/action', body),
        ok: ok, then: () => setState(() => _gen++));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SpectreColors.bg2,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 780),
        child: ApiView(
          key: ValueKey(_gen),
          load: (a) => a.get('/users/${widget.userId}'),
          builder: (context, u, reload) => _body(context, u),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Json u) {
    final status = '${u['status']}';
    final inRoom = u['roomId'] != null;
    Widget action(IconData i, String l, VoidCallback? f, {Color c = SpectreColors.accent}) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: PressButton(
            filled: false,
            glow: false,
            color: c,
            onTap: f,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 18), const SizedBox(width: 6), Text(l)]),
          ),
        );
    Widget mini(String l, String v) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SpectreColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: const TextStyle(color: SpectreColors.muted, fontSize: 11)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        );
    final ledger = jl(u['ledger']);
    final orders = jl(u['orders']);
    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      children: [
        Row(children: [
          PlayerAvatar(player: _sp(u), size: 64, presence: u['isOnline'] == true ? Presence.online : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['displayName']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text('@${u['username']} · ID ${u['id']}', style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusBadge(roleLabel('${u['role']}'), SpectreColors.gold),
                StatusBadge(statusLabel(status), status == 'active' ? SpectreColors.green : SpectreColors.red),
                StatusBadge(u['isOnline'] == true ? 'Çevrimiçi' : 'Çevrimdışı',
                    u['isOnline'] == true ? SpectreColors.green : SpectreColors.muted),
                if (inRoom) StatusBadge('Masada: ${u['roomName']}', SpectreColors.cyan),
              ]),
            ]),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 16),
        ResponsiveGrid(minItemWidth: 120, children: [
          mini('Seviye', '${jn(u['level'])}'),
          mini('Coin', '${jn(u['coins'])}'),
          mini('Kalp', '${jn(u['hearts'])}'),
          mini('Harcama', tl(jn(u['totalSpent']))),
          mini('Hediye (G/A)', '${jn(u['giftsSent'])}/${jn(u['giftsReceived'])}'),
          mini('Kayıt', ago(jd(u['createdAt']) ?? DateTime.now())),
          mini('Son görülme', jd(u['lastSeen']) == null ? '—' : ago(jd(u['lastSeen'])!)),
          mini('Çevirme', '${jn(u['spins'])}'),
        ]),
        const SizedBox(height: 16),
        const Text('Hesap işlemleri', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(children: [
          action(Icons.add_circle_outline_rounded, 'Coin ekle/çıkar', () async {
            final v = await askText(context, 'Coin miktarı (eksi = düş)', number: true);
            final n = int.tryParse(v ?? '');
            if (n == null || n == 0 || !context.mounted) return;
            final memo = await askText(context, 'Açıklama', hint: 'Örn. telafi');
            await _do({'action': 'coins', 'delta': n, 'memo': (memo ?? '').trim().isEmpty ? 'manuel' : memo!.trim()},
                ok: 'Coin güncellendi');
          }, c: SpectreColors.gold),
          action(Icons.chat_bubble_outline_rounded, status == 'muted' ? 'Susturmayı kaldır' : 'Sustur',
              () => _do({'action': 'status', 'status': status == 'muted' ? 'active' : 'muted'}),
              c: SpectreColors.amber),
          action(Icons.logout_rounded, 'Masadan çıkar', inRoom ? () => _do({'action': 'kick'}, ok: 'Masadan çıkarıldı') : null,
              c: SpectreColors.amber),
          action(Icons.pause_circle_outline_rounded, status == 'suspended' ? 'Askıyı kaldır' : 'Askıya al',
              () => _do({'action': 'status', 'status': status == 'suspended' ? 'active' : 'suspended'}),
              c: SpectreColors.red),
          action(Icons.block_rounded, status == 'banned' ? 'Yasağı kaldır' : 'Yasakla', () async {
            if (status == 'banned') return _do({'action': 'status', 'status': 'active'});
            final reason = await askText(context, 'Yasaklama nedeni');
            if (reason == null || !context.mounted) return;
            if (await confirm(context, '${u['displayName']} yasaklansın mı?', ok: 'Yasakla', danger: true)) {
              await _do({'action': 'status', 'status': 'banned', 'reason': reason}, ok: 'Yasaklandı');
            }
          }, c: SpectreColors.red),
          action(Icons.warning_amber_rounded, 'Uyarı gönder', () async {
            final w = await askText(context, 'Uyarı metni (oyuncuya iletilir)');
            if (w != null && w.trim().isNotEmpty) await _do({'action': 'warn', 'text': w.trim()}, ok: 'Uyarı gönderildi');
          }, c: SpectreColors.amber),
          action(Icons.sticky_note_2_outlined, 'İç not', () async {
            final w = await askText(context, 'İç not (oyuncu görmez)');
            if (w != null && w.trim().isNotEmpty) await _do({'action': 'note', 'text': w.trim()});
          }),
          action(Icons.drive_file_rename_outline_rounded, 'Adı değiştir', () async {
            final w = await askText(context, 'Yeni görünen ad', initial: '${u['displayName']}');
            if (w != null && w.trim().isNotEmpty) await _do({'action': 'rename', 'displayName': w.trim()});
          }),
          action(Icons.password_rounded, 'Şifre sıfırla', () async {
            final w = await askText(context, 'Yeni şifre (en az 8 karakter)');
            if (w != null && w.isNotEmpty) await _do({'action': 'resetPassword', 'password': w}, ok: 'Şifre sıfırlandı');
          }),
        ]),
        Row(children: [
          const Text('Rol: '),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: const {'player', 'vip', 'moderator'}.contains(u['role']) ? '${u['role']}' : 'player',
            items: const [
              DropdownMenuItem(value: 'player', child: Text('Oyuncu')),
              DropdownMenuItem(value: 'vip', child: Text('VIP')),
              DropdownMenuItem(value: 'moderator', child: Text('Moderatör')),
            ],
            onChanged: (r) => _do({'action': 'role', 'role': r}),
          ),
        ]),
        if ((u['warnings'] as List? ?? const []).isNotEmpty || (u['notes'] as List? ?? const []).isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Uyarılar & notlar', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final w in (u['warnings'] as List? ?? const [])) Text('⚠️ $w', style: const TextStyle(color: SpectreColors.amber)),
          for (final n in (u['notes'] as List? ?? const [])) Text('📝 $n', style: const TextStyle(color: SpectreColors.muted)),
        ],
        const SizedBox(height: 16),
        const Text('Coin hareketleri', style: TextStyle(fontWeight: FontWeight.w800)),
        if (ledger.isEmpty) const Text('Kayıt yok', style: TextStyle(color: SpectreColors.muted)),
        for (final e in ledger)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${e['memo']}'),
            subtitle: Text(hm(jd(e['at']) ?? DateTime.now())),
            trailing: Text('${jn(e['delta']) >= 0 ? '+' : ''}${jn(e['delta'])}',
                style: TextStyle(color: jn(e['delta']) >= 0 ? SpectreColors.green : SpectreColors.red, fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 8),
        const Text('Siparişler', style: TextStyle(fontWeight: FontWeight.w800)),
        if (orders.isEmpty) const Text('Sipariş yok', style: TextStyle(color: SpectreColors.muted)),
        for (final o in orders)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${o['id']} · ${o['packageName']} · ${tl(jn(o['amountKurus']))}'),
            subtitle: Text('${providerLabel('${o['provider']}')} · ${hm(jd(o['createdAt']) ?? DateTime.now())}'),
            trailing: Text(orderStatusLabel('${o['status']}')),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Canlı Masalar
// ---------------------------------------------------------------------------

class LiveTablesPage extends StatefulWidget {
  const LiveTablesPage({super.key});

  @override
  State<LiveTablesPage> createState() => _LiveTablesPageState();
}

class _LiveTablesPageState extends State<LiveTablesPage> {
  int _gen = 0;

  Future<void> _roomAction(String id, Json body, {String? ok}) async {
    await act(context, () => AdminScope.read(context).post('/rooms/$id/action', body), ok: ok, then: () => setState(() => _gen++));
  }

  @override
  Widget build(BuildContext context) {
    return ApiView(
      key: ValueKey(_gen),
      refresh: const Duration(seconds: 2),
      load: (a) => a.get('/rooms'),
      builder: (context, d, reload) {
        final rooms = jl(d['items']);
        return AdminPage(
          title: 'Canlı Masalar',
          subtitle: 'Masalar ve oyuncular 2 sn’de bir yenilenir',
          actions: [
            PressButton(
              onTap: () async {
                final n = await askText(context, 'Yeni masa adı');
                if (n == null || n.trim().isEmpty || !context.mounted) return;
                await act(context, () => AdminScope.read(context).post('/rooms', {'name': n.trim()}),
                    ok: 'Masa açıldı', then: () => setState(() => _gen++));
              },
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded),
                SizedBox(width: 6),
                Text('Masa aç'),
              ]),
            ),
          ],
          children: [
            if (rooms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                      child: Text('Henüz masa yok. “Masa aç” ile ilk masayı oluşturun.',
                          style: TextStyle(color: SpectreColors.muted))),
                ),
              ),
            ResponsiveGrid(minItemWidth: 380, children: [for (final r in rooms) _roomCard(context, r)]),
          ],
        );
      },
    );
  }

  Widget _roomCard(BuildContext context, Json r) {
    final th = TableTheme.all[jn(r['theme']) % 4];
    final round = RoundView.fromJson((r['round'] as Map?)?.cast<String, dynamic>() ?? const {});
    final seats = [for (final s in jl(r['seats'])) SeatView.fromJson(s)];
    final chat = [for (final c in jl(r['chat'])) ChatLine.fromJson(c)];
    final closed = r['closed'] == true;
    final locked = r['locked'] == true;
    final id = '${r['id']}';
    final phase = !round.active
        ? 'Oyuncu bekleniyor'
        : switch (round.phase) {
            RoundPhase.idle => 'Çevirme bekleniyor',
            RoundPhase.spinning => 'Şişe dönüyor',
            RoundPhase.deciding => 'Karar aşaması',
            RoundPhase.result => 'Sonuç',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: th.primary)),
            const SizedBox(width: 8),
            Expanded(child: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (closed)
              const StatusBadge('Kapalı', SpectreColors.red)
            else if (locked)
              const StatusBadge('Kilitli', SpectreColors.amber)
            else
              const StatusBadge('Canlı', SpectreColors.green),
          ]),
          const SizedBox(height: 6),
          Text(
            '${jn(r['countInGamePlayers'])}/12 koltuk · ${jn(r['inGamePlayers'])} aktif · Tur ${round.roundNo} · $phase · '
            '${jn(r['totalMatches'])} eşleşme · ${jn(r['totalGifts'])} hediye',
            style: const TextStyle(color: SpectreColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: seats.every((s) => s.player == null)
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Masa boş', style: TextStyle(color: SpectreColors.muted, fontSize: 12)))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final s in seats.where((s) => s.player != null))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: '${s.player!.name} · koltuk ${s.index + 1} · ${presenceLabel(s.presence)}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(30),
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    AdminScope(admin: AdminScope.read(context), child: PlayerDetailDialog(userId: s.player!.userId)),
                              ),
                              child: Opacity(
                                opacity: s.connected ? 1 : 0.45,
                                child: PlayerAvatar(
                                  player: s.player!,
                                  size: 36,
                                  presence: s.presence,
                                  highlight: round.active && s.index == round.spinnerSeat
                                      ? SpectreColors.accent
                                      : (s.index == round.targetSeat ? SpectreColors.pink : null),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 96,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: chat.isEmpty
                ? const Text('Sohbet yok', style: TextStyle(color: SpectreColors.muted, fontSize: 11))
                : ListView(reverse: true, children: [
                    for (final m in chat.reversed)
                      Text(
                        m.system ? '• ${m.text}' : '${m.name}: ${m.text}',
                        style: TextStyle(fontSize: 11, color: m.system ? SpectreColors.muted : SpectreColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: closed
                  ? null
                  : () async {
                      final m = await askText(context, '${r['name']} masasına duyuru');
                      if (m != null && m.trim().isNotEmpty) await _roomAction(id, {'action': 'broadcast', 'text': m.trim()});
                    },
              icon: const Icon(Icons.campaign_rounded, size: 16),
              label: const Text('Duyuru'),
            ),
            OutlinedButton.icon(
              onPressed: closed ? null : () => _roomAction(id, {'action': locked ? 'unlock' : 'lock'}),
              icon: Icon(locked ? Icons.lock_open_rounded : Icons.lock_rounded, size: 16),
              label: Text(locked ? 'Kilidi aç' : 'Kilitle'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final n = await askText(context, 'Masa adı', initial: '${r['name']}');
                if (n != null && n.trim().isNotEmpty) await _roomAction(id, {'action': 'rename', 'name': n.trim()});
              },
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Ad'),
            ),
            PopupMenuButton<int>(
              tooltip: 'Renk teması',
              onSelected: (v) => _roomAction(id, {'action': 'theme', 'theme': v}),
              itemBuilder: (_) => [
                for (var i = 0; i < TableTheme.all.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Row(children: [
                      CircleAvatar(radius: 7, backgroundColor: TableTheme.all[i].primary),
                      const SizedBox(width: 8),
                      Text(TableTheme.all[i].name),
                    ]),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Icon(Icons.palette_rounded, size: 18, color: SpectreColors.accent),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                if (closed) {
                  await _roomAction(id, {'action': 'open'}, ok: 'Masa açıldı');
                } else if (await confirm(context, '${r['name']} kapatılsın mı? Oturan herkes kalkar.', danger: true)) {
                  await _roomAction(id, {'action': 'close'}, ok: 'Masa kapatıldı');
                }
              },
              icon: Icon(closed ? Icons.play_arrow_rounded : Icons.power_settings_new_rounded, size: 16),
              label: Text(closed ? 'Aç' : 'Kapat'),
            ),
            if (closed)
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirm(context, '${r['name']} kalıcı olarak silinsin mi?', danger: true, ok: 'Sil')) {
                    await _roomAction(id, {'action': 'delete'}, ok: 'Masa silindi');
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: SpectreColors.red),
                label: const Text('Sil'),
              ),
          ]),
        ]),
      ),
    );
  }
}
