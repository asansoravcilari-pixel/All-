import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_client.dart';
import 'admin_common.dart';

Widget _save(bool dirty, VoidCallback f) => PressButton(
      onTap: dirty ? f : null,
      child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.save_rounded), SizedBox(width: 6), Text('Kaydet')]),
    );

// ---------------------------------------------------------------------------
// Mail: SMTP, şablonlar, test, gönderim kaydı
// ---------------------------------------------------------------------------

class MailPage extends StatefulWidget {
  const MailPage({super.key});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  Json? _s;
  Map<String, Map<String, String>> _tpl = {};
  Map<String, String> _names = {};
  List<String> _vars = [];
  List<Json> _log = [];
  String _sel = 'welcome';
  bool _dirty = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = AdminScope.read(context);
    try {
      final r = await Future.wait([a.get('/settings'), a.get('/mail/templates'), a.get('/mail/log')]);
      if (!mounted) return;
      final items = (r[1]['items'] as Map).cast<String, dynamic>();
      setState(() {
        _s = Map<String, dynamic>.from(r[0]['settings'] as Map);
        _tpl = {
          for (final e in items.entries)
            e.key: {'subject': '${(e.value as Map)['subject']}', 'body': '${(e.value as Map)['body']}'}
        };
        _names = {for (final e in items.entries) e.key: '${(e.value as Map)['name'] ?? e.key}'};
        _vars = [for (final v in (r[1]['variables'] as List? ?? const [])) '$v'];
        _log = jl(r[2]['items']);
        _dirty = false;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  void _edit(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  Future<void> _saveAll() async {
    final s = _s!;
    final ok = await act(
        context, () => AdminScope.read(context).put('/settings', {'settings': {...s, 'mailTemplates': _tpl}, 'what': 'Mail'}),
        ok: 'Mail ayarları kaydedildi');
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return Center(child: _err != null ? Text(_err!) : const CircularProgressIndicator());
    Widget field(String key, String label, {bool obscure = false, String? hint, TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            initialValue: obscure ? '' : '${s[key] ?? ''}',
            obscureText: obscure,
            keyboardType: type,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onChanged: (v) => _edit(() => s[key] = type == TextInputType.number ? (int.tryParse(v) ?? s[key]) : v.trim()),
          ),
        );
    final t = _tpl[_sel] ?? {'subject': '', 'body': ''};
    return AdminPage(
      title: 'Mail',
      subtitle: 'SMTP, otomatik e-postalar ve şablonlar',
      actions: [_save(_dirty, _saveAll)],
      children: [
        SectionCard(
          title: 'Gönderim (SMTP)',
          icon: Icons.outgoing_mail,
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Otomatik e-postalar açık'),
              subtitle: const Text('Kayıt, doğrulama, şifre sıfırlama, satın alma, abonelik bitişi, destek yanıtı'),
              value: s['mailEnabled'] == true,
              onChanged: (v) => _edit(() => s['mailEnabled'] = v),
            ),
            field('publicBaseUrl', 'Site adresi', hint: 'https://oyun.alanadin.com (bağlantılar bununla üretilir)'),
            Row(children: [
              Expanded(flex: 3, child: field('smtpHost', 'SMTP sunucusu', hint: 'smtp.alanadin.com')),
              const SizedBox(width: 10),
              Expanded(child: field('smtpPort', 'Port', type: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    value: '${s['smtpSecurity'] ?? 'starttls'}',
                    decoration: const InputDecoration(labelText: 'Güvenlik'),
                    items: const [
                      DropdownMenuItem(value: 'starttls', child: Text('STARTTLS')),
                      DropdownMenuItem(value: 'ssl', child: Text('SSL/TLS')),
                      DropdownMenuItem(value: 'none', child: Text('Yok')),
                    ],
                    onChanged: (v) => _edit(() => s['smtpSecurity'] = v),
                  ),
                ),
              ),
            ]),
            Row(children: [
              Expanded(child: field('smtpUser', 'Kullanıcı')),
              const SizedBox(width: 10),
              Expanded(
                child: field('smtpPassword', 'Şifre',
                    obscure: true, hint: s['smtpPasswordSet'] == true ? '•••••• kayıtlı (değiştirmek için yazın)' : null),
              ),
            ]),
            Row(children: [
              Expanded(child: field('mailFrom', 'Gönderen adresi', hint: 'oyun@alanadin.com')),
              const SizedBox(width: 10),
              Expanded(child: field('mailFromName', 'Gönderen adı')),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kayıtta e-posta zorunlu'),
              value: s['requireEmail'] == true,
              onChanged: (v) => _edit(() => s['requireEmail'] = v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Şablonlar',
          icon: Icons.drafts_rounded,
          trailing: TextButton.icon(
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Test gönder'),
            onPressed: () async {
              final to = await askText(context, 'Test e-postası gönderilecek adres');
              if (to == null || to.trim().isEmpty || !context.mounted) return;
              if (_dirty) await _saveAll();
              if (!context.mounted) return;
              await act(context, () => AdminScope.read(context).post('/mail/test', {'to': to.trim(), 'template': _sel}),
                  ok: 'Test e-postası gönderildi');
              await _load();
            },
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in _tpl.keys)
                ChoiceChip(label: Text(_names[k] ?? k), selected: _sel == k, onSelected: (_) => setState(() => _sel = k)),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('subj-$_sel'),
              initialValue: t['subject'],
              decoration: const InputDecoration(labelText: 'Konu'),
              onChanged: (v) => _edit(() => _tpl[_sel] = {...t, 'subject': v}),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('body-$_sel'),
              initialValue: t['body'],
              minLines: 6,
              maxLines: 14,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(labelText: 'İçerik (HTML)'),
              onChanged: (v) => _edit(() => _tpl[_sel] = {...(_tpl[_sel] ?? t), 'body': v}),
            ),
            const SizedBox(height: 8),
            Text('Kullanılabilir alanlar: ${_vars.map((v) => '{{$v}}').join('  ')}',
                style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
          ]),
        ),
        SectionCard(
          title: 'Son gönderimler',
          icon: Icons.history_rounded,
          child: _log.isEmpty
              ? const Text('Kayıt yok', style: TextStyle(color: SpectreColors.muted))
              : Column(children: [
                  for (final l in _log.take(40))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(l['ok'] == true ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: l['ok'] == true ? SpectreColors.green : SpectreColors.red, size: 18),
                      title: Text('${l['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${l['to']} · ${_names[l['template']] ?? l['template']}'
                          '${l['error'] != null ? ' · ${l['error']}' : ''}'),
                      trailing: Text(hm(jd(l['at']) ?? DateTime.now()), style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                    ),
                ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Destek: gelen kutusu, bilgi tabanı, robot ayarları
// ---------------------------------------------------------------------------

class SupportAdminPage extends StatefulWidget {
  const SupportAdminPage({super.key});

  @override
  State<SupportAdminPage> createState() => _SupportAdminPageState();
}

class _SupportAdminPageState extends State<SupportAdminPage> {
  String _status = 'waiting';
  int _gen = 0;

  Color _c(String s) => switch (s) {
        'waiting' => SpectreColors.amber,
        'answered' => SpectreColors.green,
        'locked' => SpectreColors.red,
        'closed' => SpectreColors.muted,
        _ => SpectreColors.accent,
      };

  String _l(String s) => switch (s) {
        'waiting' => 'Yanıt bekliyor',
        'answered' => 'Yanıtlandı',
        'locked' => 'Kilitli',
        'closed' => 'Kapalı',
        'bot' => 'Robotla',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return ApiView(
      key: ValueKey('$_status|$_gen'),
      refresh: const Duration(seconds: 10),
      load: (a) => a.get('/support/tickets', {if (_status.isNotEmpty) 'status': _status}),
      builder: (context, d, reload) {
        final counts = (d['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
        final items = jl(d['items']);
        return AdminPage(
          title: 'Destek',
          subtitle: 'Robot görüşmeleri, yetkili talepleri ve bilgi tabanı',
          actions: [
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context, builder: (_) => AdminScope(admin: AdminScope.read(context), child: const _KbDialog())),
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: const Text('Bilgi tabanı & robot'),
            ),
          ],
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final st in const ['waiting', 'answered', 'bot', 'locked', 'closed'])
                ChoiceChip(
                  label: Text('${_l(st)} (${jn(counts[st])})'),
                  selected: _status == st,
                  onSelected: (_) => setState(() => _status = st),
                ),
              ChoiceChip(label: const Text('Tümü'), selected: _status.isEmpty, onSelected: (_) => setState(() => _status = '')),
            ]),
            const SizedBox(height: 12),
            Card(
              child: items.isEmpty
                  ? const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('Talep yok')))
                  : Column(children: [
                      for (final t in items)
                        ListTile(
                          onTap: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => AdminScope(admin: AdminScope.read(context), child: _TicketDialog(ticket: t)),
                            );
                            setState(() => _gen++);
                          },
                          leading: Icon(Icons.support_agent_rounded, color: _c('${t['status']}')),
                          title: Row(children: [
                            Flexible(child: Text('${t['displayName'] ?? '?'}', style: const TextStyle(fontWeight: FontWeight.w700))),
                            const SizedBox(width: 6),
                            Text('@${t['username'] ?? ''}', style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
                            const SizedBox(width: 8),
                            StatusBadge(_l('${t['status']}'), _c('${t['status']}')),
                          ]),
                          subtitle: Text(
                            '${((t['messages'] as List?)?.lastOrNull as Map?)?['text'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(ago(jd(t['updatedAt']) ?? DateTime.now()),
                              style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}

class _TicketDialog extends StatefulWidget {
  const _TicketDialog({required this.ticket});
  final Json ticket;

  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  late Json _t = widget.ticket;
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _do(String action, [String? text]) async {
    try {
      final r = await AdminScope.read(context)
          .post('/support/tickets/${_t['id']}/action', {'action': action, if (text != null) 'text': text});
      if (mounted) setState(() => _t = r);
      _ctl.clear();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = jl(_t['messages']);
    return Dialog(
      backgroundColor: SpectreColors.bg2,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('${_t['displayName'] ?? ''} · @${_t['username'] ?? ''}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (_t['status'] == 'locked') TextButton(onPressed: () => _do('unlock'), child: const Text('Kilidi aç')),
              if (_t['status'] != 'closed') TextButton(onPressed: () => _do('close'), child: const Text('Kapat')),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
            const Divider(),
            Expanded(
              child: ListView(reverse: true, children: [
                for (final m in msgs.reversed)
                  Align(
                    alignment: m['from'] == 'user' ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 420),
                      decoration: BoxDecoration(
                        color: m['from'] == 'user'
                            ? Colors.white.withOpacity(0.06)
                            : '${m['from']}'.startsWith('admin:')
                                ? SpectreColors.green.withOpacity(0.15)
                                : SpectreColors.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['from'] == 'user' ? 'Oyuncu' : ('${m['from']}'.startsWith('admin:') ? '${m['from']}'.substring(6) : 'Robot'),
                            style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                        Text('${m['text']}'),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Yanıt yaz (oyuncuya bildirim + e-posta gider)'),
                ),
              ),
              const SizedBox(width: 8),
              PressButton(
                onTap: () => _ctl.text.trim().isEmpty ? null : _do('reply', _ctl.text.trim()),
                padding: const EdgeInsets.all(11),
                radius: 10,
                child: const Icon(Icons.send_rounded),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _KbDialog extends StatefulWidget {
  const _KbDialog();

  @override
  State<_KbDialog> createState() => _KbDialogState();
}

class _KbDialogState extends State<_KbDialog> {
  List<Json>? _kb;
  Json? _s;

  @override
  void initState() {
    super.initState();
    final a = AdminScope.read(context);
    Future.wait([a.get('/support/kb'), a.get('/settings')]).then((r) {
      if (!mounted) return;
      setState(() {
        _kb = [for (final e in jl(r[0]['items'])) Map<String, dynamic>.from(e)];
        _s = Map<String, dynamic>.from(r[1]['settings'] as Map);
      });
    });
  }

  Future<void> _save() async {
    final a = AdminScope.read(context);
    final s = _s!;
    final ok = await act(context, () async {
      await a.put('/support/kb', {'items': _kb});
      await a.put('/settings', {
        'settings': {
          for (final k in const [
            'supportEnabled',
            'supportBotName',
            'supportGreeting',
            'supportHumanForMembersOnly',
            'supportLockMinutes',
            'supportSafetyWords'
          ])
            k: s[k]
        },
        'what': 'Destek robotu'
      });
      return null;
    }, ok: 'Kaydedildi');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kb = _kb;
    final s = _s;
    return Dialog(
      backgroundColor: SpectreColors.bg2,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: kb == null || s == null
            ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            : ListView(padding: const EdgeInsets.all(20), children: [
                Row(children: [
                  const Expanded(child: Text('Destek robotu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  PressButton(onTap: _save, child: const Text('Kaydet')),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Destek açık'),
                  value: s['supportEnabled'] == true,
                  onChanged: (v) => setState(() => s['supportEnabled'] = v),
                ),
                TextFormField(
                  initialValue: '${s['supportBotName']}',
                  decoration: const InputDecoration(labelText: 'Robot adı'),
                  onChanged: (v) => s['supportBotName'] = v,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: '${s['supportGreeting']}',
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Karşılama mesajı'),
                  onChanged: (v) => s['supportGreeting'] = v,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Yetkiliye yalnız üyeler bağlanabilir'),
                  value: s['supportHumanForMembersOnly'] == true,
                  onChanged: (v) => setState(() => s['supportHumanForMembersOnly'] = v),
                ),
                TextFormField(
                  initialValue: '${s['supportLockMinutes']}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kural dışı ifadede kilit süresi (dakika)'),
                  onChanged: (v) => s['supportLockMinutes'] = int.tryParse(v) ?? s['supportLockMinutes'],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: [for (final w in (s['supportSafetyWords'] as List? ?? const [])) '$w'].join(', '),
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Güvenlik kelimeleri (virgülle)'),
                  onChanged: (v) => s['supportSafetyWords'] = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('Bilgi tabanı', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  TextButton.icon(
                    onPressed: () => setState(() => kb.add({'question': '', 'keywords': <String>[], 'answer': ''})),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Kayıt ekle'),
                  ),
                ]),
                for (final (i, e) in kb.indexed)
                  Card(
                    key: ObjectKey(e),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: '${e['question']}',
                              decoration: const InputDecoration(labelText: 'Soru'),
                              onChanged: (v) => e['question'] = v,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => kb.removeAt(i)),
                            icon: const Icon(Icons.delete_outline_rounded, color: SpectreColors.red),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: [for (final k in (e['keywords'] as List? ?? const [])) '$k'].join(', '),
                          decoration: const InputDecoration(labelText: 'Anahtar kelimeler (virgülle)'),
                          onChanged: (v) => e['keywords'] = v.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: '${e['answer']}',
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Yanıt'),
                          onChanged: (v) => e['answer'] = v,
                        ),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animasyonlar
// ---------------------------------------------------------------------------

class AnimationsPage extends StatefulWidget {
  const AnimationsPage({super.key});

  @override
  State<AnimationsPage> createState() => _AnimationsPageState();
}

class _AnimationsPageState extends State<AnimationsPage> {
  Json? _a;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await AdminScope.read(context).get('/settings');
    if (mounted) {
      setState(() {
        _a = Map<String, dynamic>.from((d['settings'] as Map)['animations'] as Map);
        _dirty = false;
      });
    }
  }

  void _e(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return const Center(child: CircularProgressIndicator());
    Widget slider(String k, String label, int min, int max, {String unit = 'ms'}) {
      final v = (jn(a[k])).clamp(min, max).toDouble();
      return Row(children: [
        SizedBox(width: 220, child: Text(label)),
        Expanded(
          child: Slider(
            value: v,
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: ((max - min) / (unit == 'ms' ? 100 : 1)).round().clamp(1, 200),
            label: '${v.round()} $unit',
            onChanged: (x) => _e(() => a[k] = x.round()),
          ),
        ),
        SizedBox(width: 70, child: Text('${v.round()} $unit', textAlign: TextAlign.end)),
      ]);
    }

    Widget sw(String k, String label) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: a[k] != false,
          onChanged: (v) => _e(() => a[k] = v),
        );
    Widget text(String k, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            initialValue: '${a[k] ?? ''}',
            decoration: InputDecoration(labelText: label),
            onChanged: (v) => _e(() => a[k] = v),
          ),
        );
    return AdminPage(
      title: 'Animasyonlar',
      subtitle: 'Şişe, eşleşme, red ve hediye efektleri — kaydedince masalara anında uygulanır',
      actions: [
        _save(_dirty, () async {
          final ok = await act(context, () => AdminScope.read(context).put('/settings', {
                'settings': {'animations': a},
                'what': 'Animasyonlar'
              }), ok: 'Kaydedildi');
          if (ok) await _load();
        }),
      ],
      children: [
        SectionCard(
          title: 'Zamanlama',
          icon: Icons.timer_rounded,
          child: Column(children: [
            slider('spinMs', 'Şişe dönüş süresi', 1500, 10000),
            slider('resultMs', 'Sonuç (kabul/red) gösterimi', 800, 8000),
            slider('giftFlightMs', 'Hediye uçuş süresi', 300, 5000),
          ]),
        ),
        SectionCard(
          title: 'Efektler',
          icon: Icons.auto_awesome_rounded,
          child: Column(children: [
            text('matchEmoji', 'Eşleşme (kabul) simgesi'),
            text('rejectEmoji', 'Red (pas) simgesi'),
            slider('burstCount', 'Eşleşme parçacık sayısı', 0, 60, unit: 'adet'),
            text('reactions', 'Tepki simgeleri (boşlukla ayır)'),
            sw('bottleWobble', 'Sıra bendeyken şişe hafif sallansın'),
            sw('targetBeam', 'Seçilen koltuğa ışın'),
            sw('floorGlow', 'Masa ortasında nefes alan ışık'),
          ]),
        ),
      ],
    );
  }
}
