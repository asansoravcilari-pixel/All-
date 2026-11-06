import 'package:flutter/material.dart';
import 'package:spectre_core/spectre_core.dart';

import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_client.dart';
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

  static String _ledgerLabel(String k) => switch (k) {
        'purchase' => 'Satın alma',
        'gift' => 'Hediye harcaması',
        'giftIncome' => 'Hediye geliri',
        'reward' => 'Ödüller',
        'adminAdjust' => 'Yönetici düzeltme',
        'refund' => 'İade',
        _ => k,
      };

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

  @override
  Widget build(BuildContext context) {
    return ApiView(
      key: ValueKey(_days),
      refresh: const Duration(seconds: 15),
      load: (a) => a.get('/economy', {'days': '$_days'}),
      builder: (context, d, reload) {
        final revenue = jn(d['revenue']);
        final byProvider = (d['byProvider'] as Map?)?.cast<String, dynamic>() ?? const {};
        final byPackage = (d['byPackage'] as Map?)?.cast<String, dynamic>() ?? const {};
        final ledger = (d['ledger'] as Map?)?.cast<String, dynamic>() ?? const {};
        final daily = [for (final v in (d['daily'] as List? ?? const [])) jn(v)];
        final top = jl(d['top']);
        return AdminPage(
          title: 'Ekonomi & Finans',
          subtitle: 'Gelir, coin akışı ve harcama analizi',
          actions: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 gün')),
                ButtonSegment(value: 30, label: Text('30 gün')),
                ButtonSegment(value: 90, label: Text('90 gün')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
          ],
          children: [
            ResponsiveGrid(children: [
              StatTile(label: 'Brüt gelir', value: tl(revenue), icon: Icons.trending_up_rounded, color: SpectreColors.green),
              StatTile(label: 'İadeler', value: tl(jn(d['refunded'])), icon: Icons.undo_rounded, color: SpectreColors.red),
              StatTile(label: 'Net gelir', value: tl(jn(d['net'])), icon: Icons.account_balance_wallet_rounded),
              StatTile(
                  label: 'Ödeme yapan',
                  value: '${jn(d['buyers'])}',
                  icon: Icons.person_pin_rounded,
                  color: SpectreColors.cyan,
                  hint: 'Dönüşüm %${((d['conversion'] as num?) ?? 0).toStringAsFixed(1)}'),
              StatTile(label: 'Kişi başı (ARPPU)', value: tl(jn(d['arppu'])), icon: Icons.person_rounded, color: SpectreColors.pink),
              StatTile(
                  label: 'Dolaşımdaki coin',
                  value: '${jn(d['coinsInCirculation'])}',
                  icon: Icons.toll_rounded,
                  color: SpectreColors.gold),
            ]),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Günlük gelir',
              icon: Icons.bar_chart_rounded,
              child: daily.every((v) => v == 0)
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: Text('Bu dönemde ödenmiş sipariş yok', style: TextStyle(color: SpectreColors.muted))))
                  : BarChart(values: daily, color: SpectreColors.green, height: 170),
            ),
            LayoutBuilder(builder: (context, box) {
              final prov = SectionCard(
                title: 'Ödeme yöntemine göre',
                icon: Icons.credit_card_rounded,
                child: byProvider.isEmpty
                    ? const Text('Veri yok', style: TextStyle(color: SpectreColors.muted))
                    : Column(children: [
                        for (final e in byProvider.entries) _shareRow(providerLabel(e.key), jn(e.value), revenue, SpectreColors.accent),
                      ]),
              );
              final pkg = SectionCard(
                title: 'Pakete göre',
                icon: Icons.inventory_2_rounded,
                child: byPackage.isEmpty
                    ? const Text('Veri yok', style: TextStyle(color: SpectreColors.muted))
                    : Column(children: [
                        for (final e in byPackage.entries) _shareRow(e.key, jn(e.value), revenue, SpectreColors.gold),
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
              title: 'Coin hareketleri ($_days gün)',
              icon: Icons.swap_vert_rounded,
              child: ledger.isEmpty
                  ? const Text('Hareket yok', style: TextStyle(color: SpectreColors.muted))
                  : Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final e in ledger.entries)
                        Chip(
                          label: Text('${_ledgerLabel(e.key)}: ${jn(e.value) >= 0 ? '+' : ''}${jn(e.value)}'),
                          backgroundColor: (jn(e.value) >= 0 ? SpectreColors.green : SpectreColors.red).withOpacity(0.1),
                        ),
                    ]),
            ),
            SectionCard(
              title: 'En çok harcayanlar',
              icon: Icons.emoji_events_rounded,
              child: top.isEmpty
                  ? const Text('Henüz harcama yok', style: TextStyle(color: SpectreColors.muted))
                  : Column(children: [
                      for (final (i, u) in top.indexed)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: SizedBox(
                            width: 70,
                            child: Row(children: [
                              SizedBox(width: 24, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800))),
                              PlayerAvatar(
                                player: SeatPlayer(userId: '${u['id']}', name: '${u['displayName']}', color: jn(u['color'])),
                                size: 32,
                              ),
                            ]),
                          ),
                          title: Text('${u['displayName']}'),
                          subtitle: Text('@${u['username']} · ${roleLabel('${u['role']}')}'),
                          trailing: Text(tl(jn(u['totalSpent'])), style: const TextStyle(fontWeight: FontWeight.w800)),
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
// Market: paketler + hediye kataloğu
// ---------------------------------------------------------------------------

class MarketAdminPage extends StatefulWidget {
  const MarketAdminPage({super.key});

  @override
  State<MarketAdminPage> createState() => _MarketAdminPageState();
}

class _MarketAdminPageState extends State<MarketAdminPage> {
  int _gen = 0;
  void _bump() => setState(() => _gen++);

  @override
  Widget build(BuildContext context) {
    return ApiView(
      key: ValueKey(_gen),
      load: (a) async {
        final r = await Future.wait([a.get('/packages'), a.get('/gifts'), a.get('/settings'), a.get('/features')]);
        return {'packages': r[0]['items'], 'gifts': r[1]['items'], 'settings': r[2]['settings'], 'features': r[3]['items']};
      },
      builder: (context, d, reload) {
        final pkgs = jl(d['packages']);
        final gifts = jl(d['gifts']);
        final features = jl(d['features']);
        final fname = {for (final f in features) '${f['key']}': '${f['name']}'};
        final open = (d['settings'] as Map?)?['marketOpen'] == true;
        final admin = AdminScope.read(context);
        return AdminPage(
          title: 'Market',
          subtitle: 'Coin paketleri ve hediye kataloğu',
          actions: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Market açık'),
              Switch(
                value: open,
                onChanged: (v) => act(context, () => admin.put('/settings', {'settings': {'marketOpen': v}, 'what': 'Market'}),
                    then: _bump),
              ),
            ]),
          ],
          children: [
            SectionCard(
              title: 'Coin paketleri',
              icon: Icons.inventory_2_rounded,
              trailing: TextButton.icon(
                onPressed: () => _editPackage(context, null, features, gifts),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Paket ekle'),
              ),
              child: pkgs.isEmpty
                  ? const Text('Henüz paket yok. “Paket ekle” ile oluşturun.', style: TextStyle(color: SpectreColors.muted))
                  : Column(children: [
                      for (final p in pkgs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: SpectreColors.gold.withOpacity(0.15),
                            child: Text(jn(p['vipDays']) > 0 ? '👑' : '🪙'),
                          ),
                          title: Row(children: [
                            Flexible(child: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                            const SizedBox(width: 8),
                            if (p['featured'] == true) const StatusBadge('Öne çıkan', SpectreColors.accent),
                            if (p['active'] != true) ...[const SizedBox(width: 4), const StatusBadge('Pasif', SpectreColors.red)],
                          ]),
                          subtitle: Text([
                            switch ('${p['kind']}') {
                              'subscription' => 'Abonelik',
                              'feature' => 'Tekli özellik',
                              _ => 'Coin',
                            },
                            if (jn(p['periodDays']) > 0) '${jn(p['periodDays'])} gün',
                            if (jn(p['coins']) > 0) '${jn(p['coins'])} coin${jn(p['bonusPercent']) > 0 ? ' +%${jn(p['bonusPercent'])}' : ''}',
                            for (final f in (p['features'] as List? ?? const [])) fname['$f'] ?? '$f',
                            for (final g in jl(p['gifts']))
                              '${gifts.where((x) => x['id'] == g['giftId']).map((x) => x['emoji']).firstOrNull ?? '🎁'}×${g['qty']}',
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(tl(jn(p['priceKurus'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Switch(
                              value: p['active'] == true,
                              onChanged: (v) => act(context, () => admin.post('/packages', {...p, 'active': v}), then: _bump),
                            ),
                            IconButton(
                                onPressed: () => _editPackage(context, p, features, gifts), icon: const Icon(Icons.edit_rounded, size: 18)),
                          ]),
                        ),
                    ]),
            ),
            Builder(builder: (context) {
              final st = (d['settings'] as Map).cast<String, dynamic>();
              final trial = [for (final x in (st['trialFeatures'] as List? ?? const [])) '$x'];
              Future<void> put(Map<String, dynamic> v) =>
                  act(context, () => admin.put('/settings', {'settings': v, 'what': 'Ücretsiz deneme'}), then: _bump);
              return SectionCard(
                title: 'Yeni üye ücretsiz deneme',
                icon: Icons.card_giftcard_rounded,
                trailing: Switch(value: st['trialEnabled'] == true, onChanged: (v) => put({'trialEnabled': v})),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Süre: '),
                    for (final dd in const [1, 2, 3, 7])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$dd gün'),
                          selected: jn(st['trialDays']) == dd,
                          onSelected: st['trialEnabled'] == true ? (_) => put({'trialDays': dd}) : null,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Denemede açılacak özellikler:', style: TextStyle(fontSize: 12, color: SpectreColors.muted)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final f in features)
                      FilterChip(
                        label: Text('${f['name']}'),
                        selected: trial.contains(f['key']),
                        onSelected: st['trialEnabled'] == true
                            ? (v) => put({'trialFeatures': v ? [...trial, '${f['key']}'] : trial.where((x) => x != f['key']).toList()})
                            : null,
                      ),
                  ]),
                ]),
              );
            }),
            SectionCard(
              title: 'Özellikler ve kilitler',
              icon: Icons.lock_person_rounded,
              trailing: TextButton.icon(
                onPressed: () async {
                  final key = await askText(context, 'Özellik anahtarı (ör. ozelCerceve)');
                  if (key == null || key.trim().isEmpty || !context.mounted) return;
                  final name = await askText(context, 'Görünen ad');
                  if (!context.mounted) return;
                  await act(context, () => admin.post('/features', {'key': key.trim(), 'name': (name ?? key).trim()}), then: _bump);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Özellik ekle'),
              ),
              child: Column(children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kilitli özellik yalnız o özelliği içeren paketi (abonelik/tekli) alan oyunculara açılır; süresi dolunca otomatik kilitlenir.',
                    style: TextStyle(color: SpectreColors.muted, fontSize: 12),
                  ),
                ),
                for (final f in features)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(f['locked'] == true ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: f['locked'] == true ? SpectreColors.gold : SpectreColors.muted),
                    title: Text('${f['name']}'),
                    subtitle: Text('${f['key']}${'${f['description']}'.isNotEmpty ? ' · ${f['description']}' : ''}'),
                    value: f['locked'] == true,
                    onChanged: (v) => act(context, () => admin.post('/features', {'key': f['key'], 'locked': v}), then: _bump),
                  ),
              ]),
            ),
            SectionCard(
              title: 'Hediye kataloğu',
              icon: Icons.card_giftcard_rounded,
              trailing: TextButton.icon(
                onPressed: () => _editGift(context, null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Hediye ekle'),
              ),
              child: gifts.isEmpty
                  ? const Text('Henüz hediye yok. Oyuncular hediye gönderebilsin diye katalog oluşturun.',
                      style: TextStyle(color: SpectreColors.muted))
                  : ResponsiveGrid(minItemWidth: 150, spacing: 8, children: [
                      for (final g in gifts)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _editGift(context, g),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: g['enabled'] != false ? SpectreColors.line : SpectreColors.red.withOpacity(0.5)),
                              color: Colors.white.withOpacity(g['enabled'] != false ? 0.04 : 0.01),
                            ),
                            child: Row(children: [
                              Text('${g['emoji']}', style: const TextStyle(fontSize: 26)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text('🪙 ${jn(g['price'])} · ${g['category']}',
                                      style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editPackage(BuildContext context, Json? p, List<Json> features, List<Json> gifts) async {
    final name = TextEditingController(text: '${p?['name'] ?? ''}');
    final desc = TextEditingController(text: '${p?['description'] ?? ''}');
    final coins = TextEditingController(text: p == null ? '0' : '${jn(p['coins'])}');
    final price = TextEditingController(
        text: p == null ? '' : (jn(p['priceKurus']) / 100).toStringAsFixed(2).replaceAll('.', ','));
    final bonus = TextEditingController(text: '${jn(p?['bonusPercent'])}');
    final days = TextEditingController(text: '${jn(p?['periodDays'])}');
    var kind = '${p?['kind'] ?? 'coins'}';
    var featured = p?['featured'] == true;
    final feats = <String>{for (final f in (p?['features'] as List? ?? const [])) '$f'};
    final giftQty = <String, int>{for (final g in jl(p?['gifts'])) '${g['giftId']}': jn(g['qty'])};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: SpectreColors.panel,
          title: Text(p == null ? 'Yeni paket' : 'Paketi düzenle'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'coins', label: Text('Coin')),
                    ButtonSegment(value: 'subscription', label: Text('Abonelik')),
                    ButtonSegment(value: 'feature', label: Text('Tekli özellik')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => set(() => kind = v.first),
                ),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
                const SizedBox(height: 8),
                TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Açıklama')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: price, decoration: const InputDecoration(labelText: 'Fiyat (₺)', hintText: '49,99'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(controller: coins, decoration: const InputDecoration(labelText: 'Coin'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(controller: bonus, decoration: const InputDecoration(labelText: 'Bonus %'), keyboardType: TextInputType.number)),
                ]),
                if (kind != 'coins') ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Süre: '),
                    for (final d in const [(1, 'Günlük'), (7, 'Haftalık'), (30, 'Aylık'), (0, 'Süresiz')])
                      ChoiceChip(
                        label: Text(d.$2),
                        selected: days.text == '${d.$1}',
                        onSelected: (_) => set(() => days.text = '${d.$1}'),
                      ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: days,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Gün'),
                        onChanged: (_) => set(() {}),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  const Text('Pakete dahil özellikler', style: TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final f in features)
                      FilterChip(
                        label: Text('${f['name']}'),
                        selected: feats.contains(f['key']),
                        onSelected: (v) => set(() => v ? feats.add('${f['key']}') : feats.remove(f['key'])),
                      ),
                  ]),
                ],
                const SizedBox(height: 12),
                const Text('Pakete dahil hediyeler', style: TextStyle(fontWeight: FontWeight.w700)),
                if (gifts.isEmpty) const Text('Önce hediye kataloğu oluşturun', style: TextStyle(color: SpectreColors.muted, fontSize: 12)),
                for (final g in gifts)
                  Row(children: [
                    Text('${g['emoji']}', style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${g['name']}')),
                    IconButton(
                      onPressed: (giftQty[g['id']] ?? 0) > 0 ? () => set(() => giftQty[g['id']] = giftQty[g['id']]! - 1) : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    SizedBox(width: 28, child: Text('${giftQty[g['id']] ?? 0}', textAlign: TextAlign.center)),
                    IconButton(
                      onPressed: () => set(() => giftQty['${g['id']}'] = (giftQty[g['id']] ?? 0) + 1),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Öne çıkar'),
                  value: featured,
                  onChanged: (v) => set(() => featured = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final kurus = ((double.tryParse(price.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0) * 100).round();
    await act(
      context,
      () => AdminScope.read(context).post('/packages', {
        if (p != null) 'id': p['id'],
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'kind': kind,
        'coins': int.tryParse(coins.text) ?? 0,
        'priceKurus': kurus,
        'bonusPercent': int.tryParse(bonus.text) ?? 0,
        'periodDays': kind == 'coins' ? 0 : (int.tryParse(days.text) ?? 0),
        'features': kind == 'coins' ? <String>[] : feats.toList(),
        'gifts': [
          for (final e in giftQty.entries)
            if (e.value > 0) {'giftId': e.key, 'qty': e.value}
        ],
        'featured': featured,
        'active': p?['active'] ?? true,
      }),
      ok: 'Paket kaydedildi',
      then: _bump,
    );
  }

  Future<void> _editGift(BuildContext context, Json? g) async {
    final name = TextEditingController(text: '${g?['name'] ?? ''}');
    final emoji = TextEditingController(text: '${g?['emoji'] ?? '🎁'}');
    final price = TextEditingController(text: g == null ? '' : '${jn(g['price'])}');
    final cat = TextEditingController(text: '${g?['category'] ?? 'Klasik'}');
    var enabled = g?['enabled'] != false;
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
    if (ok != true || !context.mounted) return;
    await act(
      context,
      () => AdminScope.read(context).post('/gifts', {
        if (g != null) 'id': g['id'],
        'name': name.text.trim(),
        'emoji': emoji.text.trim(),
        'price': int.tryParse(price.text) ?? -1,
        'category': cat.text.trim(),
        'enabled': enabled,
      }),
      ok: 'Hediye kaydedildi',
      then: _bump,
    );
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
  String _status = '';
  String _q = '';
  int _gen = 0;
  void _bump() => setState(() => _gen++);

  Color _color(String st) => switch (st) {
        'paid' => SpectreColors.green,
        'pending' => SpectreColors.amber,
        'failed' => SpectreColors.red,
        'refunded' => SpectreColors.pink,
        _ => SpectreColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.read(context);
    return ApiView(
      key: ValueKey('$_status|$_q|$_gen'),
      refresh: const Duration(seconds: 10),
      load: (a) async {
        final r = await Future.wait([
          a.get('/orders', {if (_status.isNotEmpty) 'status': _status, if (_q.isNotEmpty) 'q': _q}),
          a.get('/settings'),
        ]);
        return {...r[0], 'settings': r[1]['settings']};
      },
      builder: (context, d, reload) {
        final list = jl(d['items']);
        final counts = (d['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
        final s = (d['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
        Future<void> set(Map<String, dynamic> v, String what) =>
            act(context, () => admin.put('/settings', {'settings': v, 'what': what}), then: _bump);
        return AdminPage(
          title: 'Siparişler & Ödeme',
          subtitle: 'Sipariş onayı, iade ve ödeme yöntemleri',
          children: [
            SectionCard(
              title: 'Ödeme yöntemleri',
              icon: Icons.credit_card_rounded,
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Havale / EFT (yönetici onaylı)'),
                  value: s['manualPayment'] == true,
                  onChanged: (v) => set({'manualPayment': v}, 'Havale/EFT'),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    initialValue: '${s['manualPaymentInfo'] ?? ''}',
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Havale bilgisi (IBAN, alıcı, açıklama)'),
                    onFieldSubmitted: (v) => set({'manualPaymentInfo': v}, 'Havale bilgisi'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sanal POS — PayTR (kredi/banka kartı)'),
                  subtitle: Text(s['paytrKeySet'] == true
                      ? (s['paytrTestMode'] == true ? 'Anahtarlar kayıtlı · test modu' : 'Anahtarlar kayıtlı · canlı mod')
                      : 'Mağaza anahtarları girilmedi'),
                  value: s['paytrEnabled'] == true,
                  onChanged: (v) => set({'paytrEnabled': v}, 'PayTR'),
                ),
                if (s['paytrEnabled'] == true) ...[
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: '${s['paytrMerchantId'] ?? ''}',
                        decoration: const InputDecoration(labelText: 'Mağaza no (merchant_id)'),
                        onFieldSubmitted: (v) => set({'paytrMerchantId': v.trim()}, 'PayTR mağaza no'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        obscureText: true,
                        decoration: InputDecoration(
                            labelText: 'merchant_key', hintText: s['paytrKeySet'] == true ? '•••• kayıtlı' : null),
                        onFieldSubmitted: (v) => set({'paytrMerchantKey': v.trim()}, 'PayTR anahtar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        obscureText: true,
                        decoration: InputDecoration(
                            labelText: 'merchant_salt', hintText: s['paytrKeySet'] == true ? '•••• kayıtlı' : null),
                        onFieldSubmitted: (v) => set({'paytrMerchantSalt': v.trim()}, 'PayTR tuz'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: '${s['publicBaseUrl'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'Site adresi (ödeme dönüşü için)', hintText: 'https://oyun.alanadin.com'),
                    onFieldSubmitted: (v) => set({'publicBaseUrl': v.trim()}, 'Site adresi'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Test modu'),
                    value: s['paytrTestMode'] == true,
                    onChanged: (v) => set({'paytrTestMode': v}, 'PayTR test modu'),
                  ),
                  SelectableText(
                    'PayTR panelindeki "Bildirim URL" alanına yazın:  ${'${s['publicBaseUrl'] ?? ''}'.replaceAll(RegExp(r'/+$'), '')}/api/v1/pay/paytr/callback\n'
                    'Ödeme bildirimi imzası doğrulanınca sipariş otomatik onaylanır ve paket hakları tanımlanır. '
                    'Alanları Enter ile kaydedin.',
                    style: const TextStyle(fontSize: 12, color: SpectreColors.muted),
                  ),
                  const SizedBox(height: 8),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shopier'),
                  value: s['shopierEnabled'] == true,
                  onChanged: (v) => set({'shopierEnabled': v}, 'Shopier'),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Shopier için otomatik bildirim henüz yok; Shopier siparişleri onay bekler. '
                    'Gizli anahtarlar yalnız sunucuda saklanır, panele geri gösterilmez.',
                    style: TextStyle(color: SpectreColors.muted, fontSize: 12),
                  ),
                ),
              ]),
            ),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 240,
                child: TextFormField(
                  initialValue: _q,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Sipariş no veya kullanıcı'),
                  onFieldSubmitted: (v) => setState(() => _q = v.trim()),
                ),
              ),
              ChoiceChip(label: const Text('Tümü'), selected: _status.isEmpty, onSelected: (_) => setState(() => _status = '')),
              for (final st in const ['pending', 'paid', 'refunded', 'cancelled', 'failed'])
                ChoiceChip(
                  label: Text('${orderStatusLabel(st)} (${jn(counts[st])})'),
                  selected: _status == st,
                  onSelected: (_) => setState(() => _status = st),
                ),
            ]),
            const SizedBox(height: 12),
            Card(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('Sipariş yok', style: TextStyle(color: SpectreColors.muted))))
                  : Column(children: [
                      for (final o in list)
                        ListTile(
                          leading: Icon(
                            o['provider'] == 'manual' ? Icons.receipt_long_rounded : Icons.credit_card_rounded,
                            color: _color('${o['status']}'),
                          ),
                          title: Row(children: [
                            Text('${o['id']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            StatusBadge(orderStatusLabel('${o['status']}'), _color('${o['status']}')),
                          ]),
                          subtitle: Text(
                            '${o['displayName'] ?? '?'} (@${o['username'] ?? '?'}) · ${o['packageName']} · '
                            '${providerLabel('${o['provider']}')} · ${hm(jd(o['createdAt']) ?? DateTime.now())}',
                            style: const TextStyle(fontSize: 12, color: SpectreColors.muted),
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(tl(jn(o['amountKurus'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'refund' &&
                                    !await confirm(context, '${o['id']} iade edilsin mi? Coinler hesaptan düşülür.', danger: true)) {
                                  return;
                                }
                                if (!context.mounted) return;
                                await act(context, () => admin.post('/orders/${o['id']}/action', {'action': v}),
                                    ok: 'İşlem tamam', then: _bump);
                              },
                              itemBuilder: (_) => [
                                if (o['status'] == 'pending' || o['status'] == 'failed')
                                  const PopupMenuItem(value: 'approve', child: Text('Ödeme alındı — onayla')),
                                if (o['status'] == 'paid') const PopupMenuItem(value: 'refund', child: Text('İade et')),
                                if (o['status'] == 'pending') const PopupMenuItem(value: 'cancel', child: Text('İptal et')),
                              ],
                            ),
                          ]),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}
