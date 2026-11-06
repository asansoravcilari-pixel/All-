import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_common.dart';

// ---------------------------------------------------------------------------
// Ekonomi & Finans
// ---------------------------------------------------------------------------

class EconomyPage extends StatefulWidget {
  const EconomyPage({super.key});

  @override
  State<EconomyPage> createState() => _EconomyPageState();
}

class _EconomyPageState extends State<EconomyPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final since = DateTime.now().subtract(Duration(days: _days));
    final inRange = be.orders.where((o) => o.createdAt.isAfter(since)).toList();
    final paid = inRange.where((o) => o.status == OrderStatus.paid).toList();
    final revenue = paid.fold(0, (a, o) => a + o.amountKurus);
    final refunded = inRange.where((o) => o.status == OrderStatus.refunded).fold(0, (a, o) => a + o.amountKurus);
    final failed = inRange.where((o) => o.status == OrderStatus.failed).length;
    final buyers = paid.map((o) => o.playerId).toSet().length;
    final arppu = buyers == 0 ? 0 : revenue ~/ buyers;
    final conversion = be.players.isEmpty ? 0.0 : buyers / be.players.length * 100;
    final byProvider = {for (final p in PaymentProvider.values) p: 0};
    final byPackage = <String, int>{};
    for (final o in paid) {
      byProvider[o.provider] = byProvider[o.provider]! + o.amountKurus;
      byPackage[o.packageId] = (byPackage[o.packageId] ?? 0) + o.amountKurus;
    }
    final ledger = be.ledgerTotals();
    final top = be.players.values.toList()..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

    return AdminPage(
      title: 'Ekonomi & Finans',
      subtitle: 'Gelir, coin akışı ve harcama analizi',
      actions: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 gün')),
            ButtonSegment(value: 30, label: Text('30 gün')),
          ],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
      ],
      children: [
        ResponsiveGrid(children: [
          StatTile(label: 'Brüt gelir', value: tl(revenue), icon: Icons.trending_up_rounded, color: SpectreColors.green),
          StatTile(label: 'İadeler', value: tl(refunded), icon: Icons.undo_rounded, color: SpectreColors.red),
          StatTile(label: 'Net gelir', value: tl(revenue - refunded), icon: Icons.account_balance_wallet_rounded),
          StatTile(label: 'Ödeme yapan', value: '$buyers', icon: Icons.person_pin_rounded, color: SpectreColors.cyan,
              hint: 'Dönüşüm %${conversion.toStringAsFixed(1)}'),
          StatTile(label: 'Kişi başı (ARPPU)', value: tl(arppu), icon: Icons.person_rounded, color: SpectreColors.pink),
          StatTile(label: 'Başarısız ödeme', value: '$failed', icon: Icons.error_outline_rounded, color: SpectreColors.amber),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Günlük gelir',
          icon: Icons.bar_chart_rounded,
          child: BarChart(values: be.dailyRevenue(_days), color: SpectreColors.green, height: 170),
        ),
        LayoutBuilder(builder: (context, box) {
          final prov = SectionCard(
            title: 'Ödeme sağlayıcısına göre',
            icon: Icons.credit_card_rounded,
            child: Column(children: [
              for (final e in byProvider.entries)
                _shareRow(providerLabel(e.key), e.value, revenue, SpectreColors.accent),
            ]),
          );
          final pkg = SectionCard(
            title: 'Pakete göre',
            icon: Icons.inventory_2_rounded,
            child: Column(children: [
              for (final p in be.packages) _shareRow(p.name, byPackage[p.id] ?? 0, revenue, SpectreColors.gold),
            ]),
          );
          if (box.maxWidth < 800) return Column(children: [prov, pkg]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: prov),
            const SizedBox(width: 14),
            Expanded(child: pkg),
          ]);
        }),
        SectionCard(
          title: 'Coin ekonomisi (tüm zamanlar)',
          icon: Icons.toll_rounded,
          trailing: Text('Dolaşımda: 🪙 ${be.coinsInCirculation}', style: const TextStyle(fontWeight: FontWeight.w700)),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in ledger.entries)
              Chip(
                label: Text('${_ledgerLabel(e.key)}: ${e.value >= 0 ? '+' : ''}${e.value}'),
                backgroundColor: (e.value >= 0 ? SpectreColors.green : SpectreColors.red).withOpacity(0.1),
              ),
          ]),
        ),
        SectionCard(
          title: 'En çok harcayanlar',
          icon: Icons.emoji_events_rounded,
          child: Column(children: [
            for (final (i, p) in top.take(10).indexed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 70,
                  child: Row(children: [
                    SizedBox(width: 24, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800))),
                    PlayerAvatar(player: p, size: 32),
                  ]),
                ),
                title: Text(p.name),
                subtitle: Text('${roleLabel(p.role)} · Sv ${p.level}'),
                trailing: Text(tl(p.totalSpent), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ],
    );
  }

  Widget _shareRow(String label, int value, int total, Color c) {
    final f = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text('${tl(value)}  (%${(f * 100).toStringAsFixed(0)})', style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: f, minHeight: 7, color: c, backgroundColor: Colors.white10),
        ),
      ]),
    );
  }
}

String _ledgerLabel(LedgerKind k) => switch (k) {
      LedgerKind.purchase => 'Satın alma',
      LedgerKind.gift => 'Hediye harcaması',
      LedgerKind.reward => 'Ödüller',
      LedgerKind.adminAdjust => 'Yönetici düzeltme',
      LedgerKind.refund => 'İade',
    };

// ---------------------------------------------------------------------------
// Market: paketler + hediye kataloğu
// ---------------------------------------------------------------------------

class MarketAdminPage extends StatelessWidget {
  const MarketAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    return AdminPage(
      title: 'Market',
      subtitle: 'Coin paketleri ve hediye kataloğu',
      actions: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Market açık'),
          Switch(
            value: be.settings.marketOpen,
            onChanged: (v) {
              be.settings.marketOpen = v;
              be.touchSettings('Market ${v ? 'açıldı' : 'kapatıldı'}');
            },
          ),
        ]),
      ],
      children: [
        SectionCard(
          title: 'Coin paketleri',
          icon: Icons.inventory_2_rounded,
          trailing: TextButton.icon(
            onPressed: () => _editPackage(context, be, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Paket ekle'),
          ),
          child: Column(children: [
            for (final p in be.packages)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: SpectreColors.gold.withOpacity(0.15),
                  child: Text(p.vipDays > 0 ? '👑' : '🪙'),
                ),
                title: Row(children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  if (p.featured) const StatusBadge('Öne çıkan', SpectreColors.accent),
                  if (!p.active) ...[const SizedBox(width: 4), const StatusBadge('Pasif', SpectreColors.red)],
                ]),
                subtitle: Text(
                    '${p.coins} coin${p.bonusPercent > 0 ? ' +%${p.bonusPercent}' : ''}${p.vipDays > 0 ? ' · ${p.vipDays} gün VIP' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tl(p.priceKurus), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Switch(
                    value: p.active,
                    onChanged: (v) {
                      p.active = v;
                      be.upsertPackage(p);
                    },
                  ),
                  IconButton(onPressed: () => _editPackage(context, be, p), icon: const Icon(Icons.edit_rounded, size: 18)),
                ]),
              ),
          ]),
        ),
        SectionCard(
          title: 'Hediye kataloğu',
          icon: Icons.card_giftcard_rounded,
          trailing: TextButton.icon(
            onPressed: () => _editGift(context, be, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Hediye ekle'),
          ),
          child: ResponsiveGrid(
            minItemWidth: 150,
            spacing: 8,
            children: [
              for (final g in be.gifts)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _editGift(context, be, g),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: g.enabled ? SpectreColors.line : SpectreColors.red.withOpacity(0.5)),
                      color: Colors.white.withOpacity(g.enabled ? 0.04 : 0.01),
                    ),
                    child: Row(children: [
                      Text(g.emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('🪙 ${g.price} · ${g.category}', style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editPackage(BuildContext context, SpectreBackend be, StorePackage? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final coins = TextEditingController(text: '${p?.coins ?? 500}');
    final price = TextEditingController(text: p == null ? '49,99' : (p.priceKurus / 100).toStringAsFixed(2).replaceAll('.', ','));
    final bonus = TextEditingController(text: '${p?.bonusPercent ?? 0}');
    final vip = TextEditingController(text: '${p?.vipDays ?? 0}');
    var featured = p?.featured ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: SpectreColors.panel,
          title: Text(p == null ? 'Yeni paket' : 'Paketi düzenle'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              const SizedBox(height: 8),
              TextField(controller: coins, decoration: const InputDecoration(labelText: 'Coin'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: price, decoration: const InputDecoration(labelText: 'Fiyat (₺)')),
              const SizedBox(height: 8),
              TextField(controller: bonus, decoration: const InputDecoration(labelText: 'Bonus %'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: vip, decoration: const InputDecoration(labelText: 'VIP gün'), keyboardType: TextInputType.number),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Öne çıkar'),
                value: featured,
                onChanged: (v) => set(() => featured = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final kurus = ((double.tryParse(price.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0) * 100).round();
    final pkg = p ?? StorePackage(id: 'p${DateTime.now().millisecondsSinceEpoch}', name: '', coins: 0, priceKurus: 0);
    pkg
      ..name = name.text.trim().isEmpty ? 'Paket' : name.text.trim()
      ..coins = int.tryParse(coins.text) ?? pkg.coins
      ..priceKurus = kurus
      ..bonusPercent = int.tryParse(bonus.text) ?? 0
      ..vipDays = int.tryParse(vip.text) ?? 0
      ..featured = featured;
    be.upsertPackage(pkg);
  }

  Future<void> _editGift(BuildContext context, SpectreBackend be, Gift? g) async {
    final name = TextEditingController(text: g?.name ?? '');
    final emoji = TextEditingController(text: g?.emoji ?? '🎁');
    final price = TextEditingController(text: '${g?.price ?? 20}');
    final cat = TextEditingController(text: g?.category ?? 'Klasik');
    var enabled = g?.enabled ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: SpectreColors.panel,
          title: Text(g == null ? 'Yeni hediye' : 'Hediyeyi düzenle'),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: emoji, decoration: const InputDecoration(labelText: 'Simge (emoji)')),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              const SizedBox(height: 8),
              TextField(controller: price, decoration: const InputDecoration(labelText: 'Fiyat (coin)'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: cat, decoration: const InputDecoration(labelText: 'Kategori')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Satışta'),
                value: enabled,
                onChanged: (v) => set(() => enabled = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    be.upsertGift(Gift(
      id: g?.id ?? 'g${DateTime.now().millisecondsSinceEpoch}',
      name: name.text.trim().isEmpty ? 'Hediye' : name.text.trim(),
      emoji: emoji.text.trim().isEmpty ? '🎁' : emoji.text.trim(),
      price: int.tryParse(price.text) ?? 10,
      category: cat.text.trim().isEmpty ? 'Klasik' : cat.text.trim(),
      enabled: enabled,
    ));
  }
}

// ---------------------------------------------------------------------------
// Siparişler & Ödeme
// ---------------------------------------------------------------------------

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  OrderStatus? _filter;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final s = be.settings;
    final list = be.orders.where((o) {
      if (_filter != null && o.status != _filter) return false;
      if (_q.isNotEmpty) {
        final p = be.players[o.playerId];
        if (!o.id.toLowerCase().contains(_q) && !(p?.name.toLowerCase().contains(_q) ?? false)) return false;
      }
      return true;
    }).take(150).toList();
    Color statusColor(OrderStatus st) => switch (st) {
          OrderStatus.paid => SpectreColors.green,
          OrderStatus.pending => SpectreColors.amber,
          OrderStatus.failed => SpectreColors.red,
          OrderStatus.refunded => SpectreColors.pink,
          OrderStatus.cancelled => SpectreColors.muted,
        };
    return AdminPage(
      title: 'Siparişler & Ödeme',
      subtitle: 'Sipariş onayı, iade ve ödeme sağlayıcıları',
      children: [
        SectionCard(
          title: 'Ödeme sağlayıcıları',
          icon: Icons.credit_card_rounded,
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PayTR'),
              subtitle: Text(s.paytrTestMode ? 'Test modu açık' : 'Canlı mod'),
              value: s.paytrEnabled,
              onChanged: (v) {
                s.paytrEnabled = v;
                be.touchSettings('PayTR ${v ? 'açık' : 'kapalı'}');
              },
            ),
            if (s.paytrEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: s.paytrMerchantId,
                      decoration: const InputDecoration(labelText: 'Mağaza no (merchant_id)'),
                      onChanged: (v) => s.paytrMerchantId = v.trim(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilterChip(
                    label: const Text('Test modu'),
                    selected: s.paytrTestMode,
                    onSelected: (v) {
                      s.paytrTestMode = v;
                      be.touchSettings('PayTR test modu');
                    },
                  ),
                ]),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shopier'),
              value: s.shopierEnabled,
              onChanged: (v) {
                s.shopierEnabled = v;
                be.touchSettings('Shopier ${v ? 'açık' : 'kapalı'}');
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Manuel onay (Havale/EFT)'),
              value: s.manualApproval,
              onChanged: (v) {
                s.manualApproval = v;
                be.touchSettings('Manuel onay');
              },
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Gizli anahtarlar (merchant_key / salt) istemci uygulamasında tutulmaz; sunucu ortam değişkenlerinde saklanmalıdır.',
                style: TextStyle(color: SpectreColors.muted, fontSize: 12),
              ),
            ),
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Sipariş no veya oyuncu'),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          ChoiceChip(label: const Text('Tümü'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
          for (final st in OrderStatus.values)
            ChoiceChip(
              label: Text('${orderStatusLabel(st)} (${be.orders.where((o) => o.status == st).length})'),
              selected: _filter == st,
              onSelected: (_) => setState(() => _filter = st),
            ),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            for (final o in list)
              ListTile(
                leading: Icon(
                  o.provider == PaymentProvider.manual ? Icons.receipt_long_rounded : Icons.credit_card_rounded,
                  color: statusColor(o.status),
                ),
                title: Row(children: [
                  Text(o.id, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  StatusBadge(orderStatusLabel(o.status), statusColor(o.status)),
                ]),
                subtitle: Text(
                  '${be.players[o.playerId]?.name ?? o.playerId} · '
                  '${be.packages.where((p) => p.id == o.packageId).map((p) => p.name).firstOrNull ?? o.packageId} · '
                  '${providerLabel(o.provider)} · ${hm(o.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: SpectreColors.muted),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tl(o.amountKurus), style: const TextStyle(fontWeight: FontWeight.w800)),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'approve':
                          be.approveOrder(o);
                          toast(context, '${o.id} onaylandı, coin yüklendi');
                        case 'refund':
                          if (await confirm(context, '${o.id} iade edilsin mi? Coinler hesaptan düşülür.', danger: true)) {
                            be.refundOrder(o);
                          }
                        case 'cancel':
                          be.cancelOrder(o);
                      }
                    },
                    itemBuilder: (_) => [
                      if (o.status == OrderStatus.pending || o.status == OrderStatus.failed)
                        const PopupMenuItem(value: 'approve', child: Text('Ödendi olarak onayla')),
                      if (o.status == OrderStatus.paid) const PopupMenuItem(value: 'refund', child: Text('İade et')),
                      if (o.status == OrderStatus.pending) const PopupMenuItem(value: 'cancel', child: Text('İptal et')),
                    ],
                  ),
                ]),
              ),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Sipariş yok')),
          ]),
        ),
      ],
    );
  }
}
