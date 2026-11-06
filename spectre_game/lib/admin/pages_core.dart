import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/game_table.dart';
import '../data/models.dart';
import '../game/stage_painters.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_common.dart';

// ---------------------------------------------------------------------------
// Kontrol Merkezi
// ---------------------------------------------------------------------------

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final paidToday = be.orders.where((o) =>
        o.status == OrderStatus.paid && DateTime.now().difference(o.createdAt).inHours < 24);
    final todayRevenue = paidToday.fold(0, (a, o) => a + o.amountKurus);
    final pending = be.orders.where((o) => o.status == OrderStatus.pending).length;
    final banned = be.players.values.where((p) => p.status == AccountStatus.banned).length;
    final rev = be.dailyRevenue(14);
    return AdminPage(
      title: 'Kontrol Merkezi',
      subtitle: 'Platformun canlı özeti',
      actions: [
        PressButton(
          onTap: () async {
            final t = await askText(context, 'Tüm masalara duyuru', hint: 'Örn. 10 dk sonra etkinlik başlıyor!');
            if (t != null && t.trim().isNotEmpty) be.broadcastAll(t.trim());
          },
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.campaign_rounded),
            SizedBox(width: 6),
            Text('Duyuru yap'),
          ]),
        ),
      ],
      children: [
        ResponsiveGrid(children: [
          StatTile(label: 'Masalardaki oyuncu', value: '${be.onlineCount}', icon: Icons.people_alt_rounded),
          StatTile(
              label: 'Aktif masa',
              value: '${be.tables.where((t) => !t.closed).length}',
              icon: Icons.table_restaurant_rounded,
              color: SpectreColors.cyan),
          StatTile(label: 'Bugünkü gelir', value: tl(todayRevenue), icon: Icons.payments_rounded, color: SpectreColors.green),
          StatTile(
              label: 'Onay bekleyen sipariş',
              value: '$pending',
              icon: Icons.pending_actions_rounded,
              color: pending > 0 ? SpectreColors.amber : SpectreColors.muted),
          StatTile(label: 'Kayıtlı oyuncu', value: '${be.players.length}', icon: Icons.badge_rounded, color: SpectreColors.pink),
          StatTile(label: 'Yasaklı hesap', value: '$banned', icon: Icons.block_rounded, color: SpectreColors.red),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, box) {
          final revenue = SectionCard(
            title: 'Son 14 gün gelir',
            icon: Icons.bar_chart_rounded,
            trailing: Text(tl(rev.fold(0, (a, b) => a + b)), style: const TextStyle(fontWeight: FontWeight.w800)),
            child: BarChart(values: rev, color: SpectreColors.green),
          );
          final tables = SectionCard(
            title: 'Masa doluluğu',
            icon: Icons.donut_large_rounded,
            child: Column(
              children: [
                for (final t in be.tables.where((t) => !t.closed))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      SizedBox(width: 110, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: t.occupied / t.seats.length,
                            minHeight: 8,
                            backgroundColor: Colors.white10,
                            color: TableTheme.all[t.theme % 4].primary,
                          ),
                        ),
                      ),
                      SizedBox(width: 44, child: Text('  ${t.occupied}/12', style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
              ],
            ),
          );
          if (box.maxWidth < 900) return Column(children: [revenue, tables]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: revenue),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: tables),
          ]);
        }),
        SectionCard(
          title: 'Son yönetim işlemleri',
          icon: Icons.history_rounded,
          child: be.audit.isEmpty
              ? const Text('Henüz işlem yok', style: TextStyle(color: SpectreColors.muted))
              : Column(
                  children: [
                    for (final a in be.audit.take(8))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bolt_rounded, size: 18, color: SpectreColors.accent),
                        title: Text('${a.action} — ${a.target}'),
                        trailing: Text(ago(a.at), style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                      ),
                  ],
                ),
        ),
      ],
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
  AccountStatus? _status;
  PlayerRole? _role;
  bool _onlyOnline = false;
  String _sort = 'level';

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    var list = be.players.values.where((p) {
      if (_q.isNotEmpty &&
          !p.name.toLowerCase().contains(_q.toLowerCase()) &&
          !p.email.toLowerCase().contains(_q.toLowerCase()) &&
          p.id != _q) {
        return false;
      }
      if (_status != null && p.status != _status) return false;
      if (_role != null && p.role != _role) return false;
      if (_onlyOnline && be.tableOf(p.id) == null) return false;
      return true;
    }).toList();
    list.sort((a, b) => switch (_sort) {
          'coins' => b.coins.compareTo(a.coins),
          'spent' => b.totalSpent.compareTo(a.totalSpent),
          'hearts' => b.hearts.compareTo(a.hearts),
          'new' => b.joinedAt.compareTo(a.joinedAt),
          _ => b.level.compareTo(a.level),
        });
    return AdminPage(
      title: 'Oyuncular',
      subtitle: '${be.players.length} hesap · tam yönetim',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Ad, e-posta veya ID'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            DropdownButton<AccountStatus?>(
              value: _status,
              hint: const Text('Durum'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tüm durumlar')),
                for (final s in AccountStatus.values) DropdownMenuItem(value: s, child: Text(statusLabel(s))),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            DropdownButton<PlayerRole?>(
              value: _role,
              hint: const Text('Rol'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tüm roller')),
                for (final r in PlayerRole.values) DropdownMenuItem(value: r, child: Text(roleLabel(r))),
              ],
              onChanged: (v) => setState(() => _role = v),
            ),
            DropdownButton<String>(
              value: _sort,
              items: const [
                DropdownMenuItem(value: 'level', child: Text('Seviye')),
                DropdownMenuItem(value: 'coins', child: Text('Coin')),
                DropdownMenuItem(value: 'spent', child: Text('Harcama')),
                DropdownMenuItem(value: 'hearts', child: Text('Kalp')),
                DropdownMenuItem(value: 'new', child: Text('En yeni')),
              ],
              onChanged: (v) => setState(() => _sort = v!),
            ),
            FilterChip(
              label: const Text('Yalnız masadakiler'),
              selected: _onlyOnline,
              onSelected: (v) => setState(() => _onlyOnline = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final p in list.take(200))
                _PlayerRow(player: p, backend: be, onOpen: () => _openDetail(context, p)),
              if (list.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Sonuç yok')),
            ],
          ),
        ),
      ],
    );
  }

  void _openDetail(BuildContext context, Player p) {
    showDialog<void>(context: context, builder: (_) => PlayerDetailDialog(player: p));
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.backend, required this.onOpen});
  final Player player;
  final SpectreBackend backend;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final t = backend.tableOf(p.id);
    return ListTile(
      onTap: onOpen,
      leading: PlayerAvatar(player: p, size: 40),
      title: Row(children: [
        Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        if (p.role != PlayerRole.player) StatusBadge(roleLabel(p.role), SpectreColors.gold),
        if (p.status != AccountStatus.active) ...[
          const SizedBox(width: 4),
          StatusBadge(statusLabel(p.status), SpectreColors.red),
        ],
      ]),
      subtitle: Text(
        'Sv ${p.level} · 🪙 ${p.coins} · ♥ ${p.hearts}${t != null ? ' · 🟢 ${t.name}' : ''}',
        style: const TextStyle(color: SpectreColors.muted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class PlayerDetailDialog extends StatelessWidget {
  const PlayerDetailDialog({super.key, required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final p = player;
    final t = be.tableOf(p.id);
    final history = be.ledger.where((e) => e.playerId == p.id).toList().reversed.take(12).toList();
    final orders = be.orders.where((o) => o.playerId == p.id).take(8).toList();
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
    return Dialog(
      backgroundColor: SpectreColors.bg2,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          shrinkWrap: true,
          children: [
            Row(children: [
              PlayerAvatar(player: p, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Text('ID ${p.id} · ${p.email} · ${p.country}', style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    StatusBadge(roleLabel(p.role), SpectreColors.gold),
                    StatusBadge(statusLabel(p.status),
                        p.status == AccountStatus.active ? SpectreColors.green : SpectreColors.red),
                    StatusBadge(t == null ? 'Masada değil' : 'Masada: ${t.name}', SpectreColors.cyan),
                  ]),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 16),
            ResponsiveGrid(minItemWidth: 120, children: [
              _mini('Seviye', '${p.level}'),
              _mini('Coin', '${p.coins}'),
              _mini('Kalp', '${p.hearts}'),
              _mini('Harcama', tl(p.totalSpent)),
              _mini('Hediye (G/A)', '${p.giftsSent}/${p.giftsReceived}'),
              _mini('Kayıt', ago(p.joinedAt)),
            ]),
            const SizedBox(height: 16),
            const Text('Hesap işlemleri', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(children: [
              action(Icons.add_circle_outline_rounded, 'Coin ekle/çıkar', () async {
                final v = await askText(context, 'Coin miktarı (eksi = düş)', number: true);
                final n = int.tryParse(v ?? '');
                if (n == null || !context.mounted) return;
                final memo = await askText(context, 'Açıklama', hint: 'Örn. telafi');
                be.adjustCoins(p, n, memo?.trim().isNotEmpty == true ? memo!.trim() : 'manuel');
              }, c: SpectreColors.gold),
              action(Icons.chat_bubble_outline_rounded, p.status == AccountStatus.muted ? 'Susturmayı kaldır' : 'Sustur', () {
                be.setStatus(p, p.status == AccountStatus.muted ? AccountStatus.active : AccountStatus.muted);
              }, c: SpectreColors.amber),
              action(Icons.logout_rounded, 'Masadan çıkar', t == null ? null : () => be.kick(p), c: SpectreColors.amber),
              action(Icons.pause_circle_outline_rounded, p.status == AccountStatus.suspended ? 'Askıyı kaldır' : 'Askıya al', () {
                be.setStatus(p, p.status == AccountStatus.suspended ? AccountStatus.active : AccountStatus.suspended);
              }, c: SpectreColors.red),
              action(Icons.block_rounded, p.status == AccountStatus.banned ? 'Yasağı kaldır' : 'Yasakla', () async {
                if (p.status == AccountStatus.banned) {
                  be.setStatus(p, AccountStatus.active);
                  return;
                }
                final reason = await askText(context, 'Yasaklama nedeni');
                if (reason == null || !context.mounted) return;
                if (await confirm(context, '${p.name} kalıcı olarak yasaklansın mı?', ok: 'Yasakla', danger: true)) {
                  be.setStatus(p, AccountStatus.banned, reason: reason);
                }
              }, c: SpectreColors.red),
              action(Icons.warning_amber_rounded, 'Uyarı ver', () async {
                final w = await askText(context, 'Uyarı metni');
                if (w != null && w.trim().isNotEmpty) be.warn(p, w.trim());
              }, c: SpectreColors.amber),
              action(Icons.sticky_note_2_outlined, 'Not ekle', () async {
                final w = await askText(context, 'İç not (oyuncu görmez)');
                if (w != null && w.trim().isNotEmpty) be.addNote(p, w.trim());
              }),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Text('Rol: '),
              const SizedBox(width: 8),
              DropdownButton<PlayerRole>(
                value: p.role,
                items: [for (final r in PlayerRole.values) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
                onChanged: (r) => be.setRole(p, r!),
              ),
            ]),
            if (p.warnings.isNotEmpty || p.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Uyarılar & notlar', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final w in p.warnings) Text('⚠️ $w', style: const TextStyle(color: SpectreColors.amber)),
              for (final n in p.notes) Text('📝 $n', style: const TextStyle(color: SpectreColors.muted)),
            ],
            const SizedBox(height: 16),
            const Text('Coin hareketleri', style: TextStyle(fontWeight: FontWeight.w800)),
            if (history.isEmpty) const Text('Kayıt yok', style: TextStyle(color: SpectreColors.muted)),
            for (final e in history)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.memo.isEmpty ? e.kind.name : e.memo),
                subtitle: Text(hm(e.at)),
                trailing: Text('${e.delta >= 0 ? '+' : ''}${e.delta}',
                    style: TextStyle(color: e.delta >= 0 ? SpectreColors.green : SpectreColors.red, fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 8),
            const Text('Siparişler', style: TextStyle(fontWeight: FontWeight.w800)),
            if (orders.isEmpty) const Text('Sipariş yok', style: TextStyle(color: SpectreColors.muted)),
            for (final o in orders)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${o.id} · ${tl(o.amountKurus)}'),
                subtitle: Text('${providerLabel(o.provider)} · ${hm(o.createdAt)}'),
                trailing: Text(orderStatusLabel(o.status)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String l, String v) => Container(
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
}

// ---------------------------------------------------------------------------
// Canlı Masalar
// ---------------------------------------------------------------------------

class LiveTablesPage extends StatelessWidget {
  const LiveTablesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    return AdminPage(
      title: 'Canlı Masalar',
      subtitle: 'Masaları ve oyuncuları anlık izle, müdahale et',
      actions: [
        PressButton(
          onTap: () async {
            final n = await askText(context, 'Yeni masa adı');
            if (n != null && n.trim().isNotEmpty) be.createTable(n.trim());
          },
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded), SizedBox(width: 6), Text('Masa aç')]),
        ),
      ],
      children: [
        ResponsiveGrid(
          minItemWidth: 360,
          children: [for (final t in be.tables) _LiveTableCard(table: t, backend: be)],
        ),
      ],
    );
  }
}

class _LiveTableCard extends StatelessWidget {
  const _LiveTableCard({required this.table, required this.backend});
  final GameTable table;
  final SpectreBackend backend;

  @override
  Widget build(BuildContext context) {
    final t = table;
    final th = TableTheme.all[t.theme % 4];
    final r = t.round;
    final phase = switch (r.phase) {
      RoundPhase.idle => 'Çevirme bekleniyor',
      RoundPhase.spinning => 'Şişe dönüyor',
      RoundPhase.deciding => 'Karar aşaması',
      RoundPhase.result => 'Sonuç',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: th.primary)),
              const SizedBox(width: 8),
              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              if (t.closed)
                const StatusBadge('Kapalı', SpectreColors.red)
              else if (t.locked)
                const StatusBadge('Kilitli', SpectreColors.amber)
              else
                const StatusBadge('Canlı', SpectreColors.green),
            ]),
            const SizedBox(height: 6),
            Text('${t.occupied}/12 oyuncu · Tur ${r.roundNo} · $phase · ${t.totalMatches} eşleşme · ${t.totalGifts} hediye',
                style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in t.seats.where((s) => s.player != null))
                  Tooltip(
                    message: '${s.player!.name} · ${presenceLabel(s.presence)}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => showDialog<void>(context: context, builder: (_) => PlayerDetailDialog(player: s.player!)),
                      child: PlayerAvatar(
                        player: s.player!,
                        size: 34,
                        presence: s.presence,
                        highlight: s.index == r.spinnerSeat
                            ? SpectreColors.accent
                            : (s.index == r.targetSeat ? SpectreColors.pink : null),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 92,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
              child: ListView(
                reverse: true,
                children: [
                  for (final m in t.chat.reversed.take(12))
                    Text(
                      m.system ? '• ${m.text}' : '${m.from!.name}: ${m.text}',
                      style: TextStyle(fontSize: 11, color: m.system ? SpectreColors.muted : SpectreColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: t.closed
                    ? null
                    : () async {
                        final m = await askText(context, '${t.name} masasına duyuru');
                        if (m != null && m.trim().isNotEmpty) t.broadcast(m.trim());
                      },
                icon: const Icon(Icons.campaign_rounded, size: 16),
                label: const Text('Duyuru'),
              ),
              OutlinedButton.icon(
                onPressed: t.closed ? null : () => backend.toggleLock(t),
                icon: Icon(t.locked ? Icons.lock_open_rounded : Icons.lock_rounded, size: 16),
                label: Text(t.locked ? 'Kilidi aç' : 'Kilitle'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (t.closed) {
                    backend.reopenTable(t);
                  } else if (await confirm(context, '${t.name} kapatılsın mı? Tüm oyuncular çıkarılır.', danger: true)) {
                    backend.closeTable(t);
                  }
                },
                icon: Icon(t.closed ? Icons.play_arrow_rounded : Icons.power_settings_new_rounded, size: 16),
                label: Text(t.closed ? 'Aç' : 'Kapat'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
