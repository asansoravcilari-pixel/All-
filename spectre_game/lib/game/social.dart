import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spectre_core/spectre_core.dart';

import '../data/api.dart';
import '../data/client.dart';
import '../platform/file_pick.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Alt sayfa çerçevesi (tüm açılır pencereler).
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child, this.title, this.subtitle, this.maxHeight});
  final Widget child;
  final String? title;
  final String? subtitle;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight ?? mq.size.height * 0.86),
          child: GlassPanel(
            radius: 22,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              if (title != null)
                Row(children: [
                  Expanded(child: Text(title!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(subtitle!, style: const TextStyle(color: SpectreColors.muted, fontSize: 13)),
                ),
              Flexible(child: child),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Kare kullanıcı fotoğrafı (yoksa baş harfler).
class SquareAvatar extends StatelessWidget {
  const SquareAvatar({super.key, required this.name, required this.color, this.url = '', this.size = 28, this.online});
  final String name;
  final int color;
  final String url;
  final double size;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final c = Color(color == 0 ? 0xFF65C5FF : color);
    final radius = BorderRadius.circular(size * 0.18);
    final initials = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(c, Colors.white, 0.25)!, c, Color.lerp(c, Colors.black, 0.5)!],
        ),
      ),
      child: Center(
        child: Text(initialsOf(name),
            style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: const Color(0xFF3E7AA1))),
            child: ClipRRect(
              borderRadius: radius,
              child: url.isEmpty
                  ? initials
                  : Image.network(mediaUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => initials),
            ),
          ),
        ),
        if (online != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online! ? SpectreColors.green : SpectreColors.muted,
                border: Border.all(color: SpectreColors.bg, width: 1.5),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Masa sohbeti satırı: kare fotoğraf, renkli ad, metin; çeviri varsa çevrilmiş metin önde.
class ChatLineView extends StatefulWidget {
  const ChatLineView({super.key, required this.m, required this.lang, this.onTapUser});
  final ChatLine m;
  final String lang;
  final void Function(String userId)? onTapUser;

  @override
  State<ChatLineView> createState() => _ChatLineViewState();
}

class _ChatLineViewState extends State<ChatLineView> {
  bool _original = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    if (m.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(m.text, style: const TextStyle(color: SpectreColors.muted, fontSize: 12, fontStyle: FontStyle.italic)),
      );
    }
    final tr = m.translations[widget.lang];
    final shown = tr != null && !_original ? tr : m.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: m.userId == null ? null : () => widget.onTapUser?.call(m.userId!),
          child: SquareAvatar(name: m.name, color: m.color, url: m.avatarUrl, size: 26),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, style: TextStyle(color: Color(m.color), fontWeight: FontWeight.w800, fontSize: 12)),
            Text(shown, style: const TextStyle(fontSize: 13.5, height: 1.25)),
            if (tr != null)
              GestureDetector(
                onTap: () => setState(() => _original = !_original),
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.translate_rounded, size: 11, color: SpectreColors.muted),
                    const SizedBox(width: 3),
                    Text(_original ? 'Çeviriyi göster' : 'Aslını göster',
                        style: const TextStyle(fontSize: 10.5, color: SpectreColors.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

String _date(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} ${_hm(t)}';

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Mesaj kutusu
// ---------------------------------------------------------------------------

class DmInboxSheet extends StatefulWidget {
  const DmInboxSheet({super.key, required this.client});
  final SpectreClient client;

  @override
  State<DmInboxSheet> createState() => _DmInboxSheetState();
}

class _DmInboxSheetState extends State<DmInboxSheet> {
  Map<String, dynamic>? _data;
  String? _err;
  StreamSubscription<DmMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.client.dmStream.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.client.dmThreads();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final items = [for (final x in (_data?['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    return SheetFrame(
      title: c.t('dm.title', 'Mesaj kutusu'),
      subtitle: c.config.popup('dm'),
      child: _data == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: _err != null ? Text(_err!) : const CircularProgressIndicator()),
            )
          : items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(c.t('dm.empty', 'Henüz mesaj yok'),
                      textAlign: TextAlign.center, style: const TextStyle(color: SpectreColors.muted)),
                )
              : ListView(shrinkWrap: true, children: [
                  for (final it in items)
                    Builder(builder: (context) {
                      final peer = (it['peer'] as Map).cast<String, dynamic>();
                      final last = DmMessage((it['last'] as Map).cast<String, dynamic>());
                      final unread = (it['unread'] as num?)?.toInt() ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          Navigator.pop(context);
                          showDmThread(context, c, '${peer['id']}');
                        },
                        leading: SquareAvatar(
                          name: '${peer['name']}',
                          color: (peer['color'] as num?)?.toInt() ?? 0,
                          url: '${peer['avatarUrl'] ?? ''}',
                          size: 42,
                          online: peer['isOnline'] == true,
                        ),
                        title: Text('${peer['name']}', style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600)),
                        subtitle: Text(last.translation(c.me?.lang ?? 'tr') ?? last.text,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SpectreColors.muted)),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_hm(last.at), style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                          if (unread > 0) CountBadge(count: unread),
                        ]),
                      );
                    }),
                ]),
    );
  }
}

Future<void> showDmThread(BuildContext context, SpectreClient c, String userId) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DmThreadSheet(client: c, userId: userId),
    );

class DmThreadSheet extends StatefulWidget {
  const DmThreadSheet({super.key, required this.client, required this.userId});
  final SpectreClient client;
  final String userId;

  @override
  State<DmThreadSheet> createState() => _DmThreadSheetState();
}

class _DmThreadSheetState extends State<DmThreadSheet> {
  Map<String, dynamic>? _peer;
  final List<DmMessage> _items = [];
  final _ctl = TextEditingController();
  StreamSubscription<DmMessage>? _sub;
  String? _err;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.client.dmStream.listen((m) {
      final me = widget.client.me?.id;
      final mine = (m.from == me && m.to == widget.userId) || (m.from == widget.userId && m.to == me);
      if (!mine || !mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == m.id);
        if (i >= 0) {
          _items[i] = m;
        } else {
          _items.add(m);
        }
      });
      if (m.from == widget.userId) widget.client.dmThread(widget.userId); // okundu
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (peer, items) = await widget.client.dmThread(widget.userId);
      if (!mounted) return;
      setState(() {
        _peer = peer;
        _items
          ..clear()
          ..addAll(items);
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.client.sendDm(widget.userId, text);
      _ctl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final meId = c.me?.id;
    final lang = c.me?.lang ?? 'tr';
    final peer = _peer;
    return SheetFrame(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (peer != null)
            SquareAvatar(
              name: '${peer['name']}',
              color: (peer['color'] as num?)?.toInt() ?? 0,
              url: '${peer['avatarUrl'] ?? ''}',
              size: 40,
              online: peer['isOnline'] == true,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(peer == null ? '…' : '${peer['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close_rounded)),
        ]),
        const Divider(),
        Flexible(
          child: _err != null
              ? Padding(padding: const EdgeInsets.all(20), child: Text(_err!))
              : ListView.builder(
                  reverse: true,
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final m = _items[_items.length - 1 - i];
                    final mine = m.from == meId;
                    final tr = mine ? null : m.translation(lang);
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!mine) ...[
                            SquareAvatar(name: m.fromName, color: m.fromColor, url: m.fromAvatar, size: 24),
                            const SizedBox(width: 6),
                          ],
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: mine ? SpectreColors.accent.withOpacity(0.22) : Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: mine ? SpectreColors.accent.withOpacity(0.4) : SpectreColors.line),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tr ?? m.text, style: const TextStyle(fontSize: 14)),
                                if (tr != null)
                                  Text(m.text, style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                                Text(_hm(m.at), style: const TextStyle(fontSize: 10, color: SpectreColors.muted)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(counterText: '', hintText: c.t('chat.placeholder', 'Mesaj yaz')),
            ),
          ),
          const SizedBox(width: 8),
          PressButton(onTap: _sending ? null : _send, padding: const EdgeInsets.all(11), radius: 10, child: const Icon(Icons.send_rounded)),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Bildirimler (sunucudan)
// ---------------------------------------------------------------------------

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key, required this.client});
  final SpectreClient client;

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    widget.client.notifications().then((v) {
      if (mounted) setState(() => _items = v);
      widget.client.markNotificationsRead();
    }).catchError((_) {
      if (mounted) setState(() => _items = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    (IconData, Color) icon(String k) => switch (k) {
          'gift' => (Icons.card_giftcard_rounded, SpectreColors.gold),
          'match' => (Icons.favorite_rounded, SpectreColors.pink),
          'order' => (Icons.receipt_long_rounded, SpectreColors.green),
          'admin' => (Icons.campaign_rounded, SpectreColors.amber),
          _ => (Icons.info_outline_rounded, SpectreColors.accent),
        };
    final items = _items;
    return SheetFrame(
      title: c.t('notifications.title', 'Bildirimler'),
      subtitle: c.config.popup('notifications'),
      child: items == null
          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          : items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(c.t('notifications.empty', 'Bildirim yok'),
                      textAlign: TextAlign.center, style: const TextStyle(color: SpectreColors.muted)),
                )
              : ListView(shrinkWrap: true, children: [
                  for (final n in items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon('${n['kind']}').$1, color: icon('${n['kind']}').$2),
                      title: Text('${n['text']}',
                          style: TextStyle(fontWeight: n['read'] == true ? FontWeight.w500 : FontWeight.w800)),
                      trailing: Text(_hm(DateTime.tryParse('${n['at']}')?.toLocal() ?? DateTime.now()),
                          style: const TextStyle(fontSize: 11, color: SpectreColors.muted)),
                    ),
                ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Profil: fotoğraf, ad, dil
// ---------------------------------------------------------------------------

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key, required this.client});
  final SpectreClient client;

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  bool _busy = false;

  static const _langNames = {
    'tr': 'Türkçe',
    'en': 'English',
    'de': 'Deutsch',
    'ar': 'العربية',
    'ru': 'Русский',
    'az': 'Azərbaycan',
    'fr': 'Français',
    'es': 'Español',
    'nl': 'Nederlands',
  };

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final me = c.me;
        if (me == null) return const SizedBox.shrink();
        return SheetFrame(
          subtitle: c.config.popup('profile'),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                SquareAvatar(name: me.displayName, color: me.color, url: me.avatarUrl, size: 96),
                if (!me.guest)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: PressButton(
                      onTap: _busy
                          ? null
                          : me.isLocked('avatar')
                              ? () => showLocked(context, c, 'avatar')
                              : () => _run(() async {
                                    final bytes = await pickImageBytes();
                                    if (bytes != null) await c.uploadAvatar(bytes);
                                  }),
                      padding: const EdgeInsets.all(8),
                      radius: 20,
                      tooltip: 'Fotoğraf yükle',
                      child: const Icon(Icons.photo_camera_rounded, size: 18),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(me.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'Adı değiştir',
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: _busy
                      ? null
                      : () async {
                          final ctl = TextEditingController(text: me.displayName);
                          final v = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: SpectreColors.panel,
                              title: const Text('Görünen ad'),
                              content: TextField(controller: ctl, autofocus: true, maxLength: 20),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Kaydet')),
                              ],
                            ),
                          );
                          if (v != null && v.trim().isNotEmpty) await _run(() => c.rename(v.trim()));
                        },
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                Chip(label: Text('Seviye ${me.level}')),
                Chip(label: Text('♥ ${me.hearts}')),
                Chip(label: Text('🪙 ${me.coins}')),
                if (me.vip) const Chip(label: Text('👑 VIP')),
                if (me.guest) const Chip(label: Text('Misafir')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.translate_rounded, size: 18, color: SpectreColors.muted),
                const SizedBox(width: 8),
                const Expanded(child: Text('Mesajları şu dile çevir')),
                DropdownButton<String>(
                  value: c.config.languages.contains(me.lang) ? me.lang : null,
                  hint: Text(me.lang),
                  items: [
                    for (final l in c.config.languages) DropdownMenuItem(value: l, child: Text(_langNames[l] ?? l)),
                  ],
                  onChanged: _busy ? null : (v) => v == null ? null : _run(() => c.setLang(v)),
                ),
              ]),
              if (!c.config.translate)
                const Text('Otomatik çeviri şu an kapalı.', style: TextStyle(fontSize: 11, color: SpectreColors.muted)),
              if (!me.guest) ...[
                const Divider(height: 24),
                Row(children: [
                  const Icon(Icons.alternate_email_rounded, size: 18, color: SpectreColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(me.email.isEmpty ? 'E-posta eklenmemiş' : me.email,
                        style: TextStyle(color: me.email.isEmpty ? SpectreColors.muted : SpectreColors.ink)),
                  ),
                  if (me.email.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(me.emailVerified ? '✓ doğrulandı' : 'doğrulanmadı',
                          style: TextStyle(fontSize: 11, color: me.emailVerified ? SpectreColors.green : SpectreColors.amber)),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final ctl = TextEditingController(text: me.email);
                            final v = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: SpectreColors.panel,
                                title: const Text('E-posta adresi'),
                                content: TextField(
                                    controller: ctl, autofocus: true, keyboardType: TextInputType.emailAddress),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Kaydet')),
                                ],
                              ),
                            );
                            if (v != null) await _run(() => c.setEmail(v.trim()));
                          },
                    child: Text(me.email.isEmpty ? 'Ekle' : 'Değiştir'),
                  ),
                ]),
                if (me.email.isNotEmpty && !me.emailVerified)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await c.resendVerify();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('Doğrulama e-postası gönderildi')));
                                }
                              }),
                      child: const Text('Doğrulama e-postasını tekrar gönder'),
                    ),
                  ),
              ],
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Paket haklarım', style: TextStyle(fontWeight: FontWeight.w800, color: SpectreColors.ink.withOpacity(0.9))),
              ),
              const SizedBox(height: 6),
              if (me.entitlements.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Aktif paket hakkın yok.', style: TextStyle(color: SpectreColors.muted, fontSize: 13)),
                )
              else
                for (final e in me.entitlements.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_rounded, color: SpectreColors.green, size: 20),
                    title: Text(me.featureNames[e.key] ?? e.key),
                    trailing: Text(e.value.year >= 2100 ? 'süresiz' : 'bitiş ${_date(e.value)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: e.value.difference(DateTime.now()).inDays < 3 ? SpectreColors.amber : SpectreColors.muted)),
                  ),
              if (me.locked.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in me.locked)
                    Chip(
                      avatar: const Icon(Icons.lock_rounded, size: 14),
                      label: Text(me.featureNames[k] ?? k, style: const TextStyle(fontSize: 12)),
                    ),
                ]),
              ],
              if (me.inventory.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in me.inventory.entries)
                      Chip(
                        label: Text(
                            '${c.gifts.where((g) => g.id == e.key).map((g) => '${g.emoji} ${g.name}').firstOrNull ?? e.key} ×${e.value}'),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

/// Kutu köşesindeki okunmamış sayısı rozeti.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: SpectreMotion.normal,
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: Container(
          key: ValueKey(count),
          constraints: const BoxConstraints(minWidth: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDCD7DF)),
          ),
          child: Text(count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCA1A49), fontSize: 10, fontWeight: FontWeight.w800, height: 1.7)),
        ),
      );
}


/// Kilitli özellik uyarısı: paket önerisiyle.
void showLocked(BuildContext context, SpectreClient c, String feature) {
  final name = c.me?.featureNames[feature] ?? feature;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.lock_rounded, size: 18, color: SpectreColors.gold),
      const SizedBox(width: 8),
      Expanded(child: Text('$name paketinde yok — Market\'ten açabilirsin')),
    ]),
  ));
}

/// Şifremi unuttum penceresi.
Future<void> showForgotPassword(BuildContext context, SpectreClient c) async {
  final ctl = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SpectreColors.panel,
      title: const Text('Şifremi unuttum'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Hesabına kayıtlı e-posta adresini ya da kullanıcı adını yaz; sıfırlama bağlantısı gönderelim.',
            style: TextStyle(color: SpectreColors.muted, fontSize: 13)),
        const SizedBox(height: 10),
        TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.emailAddress),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Gönder')),
      ],
    ),
  );
  if (v == null || v.trim().isEmpty || !context.mounted) return;
  try {
    final msg = await c.forgotPassword(v.trim());
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

// ---------------------------------------------------------------------------
// Destek
// ---------------------------------------------------------------------------

class SupportSheet extends StatefulWidget {
  const SupportSheet({super.key, required this.client});
  final SpectreClient client;

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  Map<String, dynamic>? _t;
  String _bot = 'Asistan';
  String? _err;
  bool _sending = false;
  final _ctl = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> r) {
    if (!mounted) return;
    setState(() {
      _t = (r['ticket'] as Map).cast<String, dynamic>();
      _bot = '${r['botName'] ?? 'Asistan'}';
      _err = null;
    });
  }

  Future<void> _load() async {
    try {
      _apply(await widget.client.support());
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctl.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      _apply(await widget.client.support(text));
      _ctl.clear();
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = [for (final m in (_t?['messages'] as List? ?? const [])) (m as Map).cast<String, dynamic>()];
    final status = '${_t?['status'] ?? ''}';
    final lockedChat = status == 'locked';
    return SheetFrame(
      title: 'Destek',
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (status == 'waiting')
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Talebin bir yetkiliye iletildi; yanıt burada görünecek.',
                style: TextStyle(color: SpectreColors.amber, fontSize: 12)),
          ),
        Flexible(
          child: ListView.builder(
            reverse: true,
            shrinkWrap: true,
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[msgs.length - 1 - i];
              final from = '${m['from']}';
              final mine = from == 'user';
              final who = mine ? '' : (from.startsWith('admin:') ? 'Yetkili' : _bot);
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: mine
                          ? SpectreColors.accent.withOpacity(0.22)
                          : from.startsWith('admin:')
                              ? SpectreColors.green.withOpacity(0.14)
                              : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SpectreColors.line),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (who.isNotEmpty)
                        Text(who, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: SpectreColors.cyan)),
                      Text('${m['text']}', style: const TextStyle(fontSize: 14)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        if (_err != null) Text(_err!, style: const TextStyle(color: SpectreColors.red, fontSize: 12)),
        const SizedBox(height: 6),
        if (!lockedChat)
          Wrap(spacing: 6, children: [
            for (final q in const ['Paketlerim', 'Siparişim', 'Coin nasıl alırım?', 'Yetkili'])
              ActionChip(label: Text(q, style: const TextStyle(fontSize: 12)), onPressed: _sending ? null : () => _send(q)),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              enabled: !lockedChat,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(counterText: '', hintText: lockedChat ? 'Görüşme kilitlendi' : 'Sorunu yaz'),
            ),
          ),
          const SizedBox(width: 8),
          PressButton(
              onTap: _sending || lockedChat ? null : _send,
              padding: const EdgeInsets.all(11),
              radius: 10,
              child: const Icon(Icons.send_rounded)),
        ]),
      ]),
    );
  }
}
