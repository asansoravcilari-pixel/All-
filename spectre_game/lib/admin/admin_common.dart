import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Admin sayfası iskeleti: başlık + kaydırılabilir içerik.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 14, wide ? 24 : 12, wide ? 28 : 14, 40),
      children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      if (subtitle != null)
                        Text(subtitle!, style: const TextStyle(color: SpectreColors.muted)),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          )
        else if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: actions),
          ),
        ...children,
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.trailing, required this.child, this.icon});
  final String title;
  final Widget? trailing;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: SpectreColors.accent),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Esnek ızgara: genişliğe göre sütun sayısı.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 220, this.spacing = 12});
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / minItemWidth).floor().clamp(1, 6);
      final w = (box.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    });
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds} sn önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  return '${d.inDays} gün önce';
}

String hm(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

Future<String?> askText(BuildContext context, String title, {String hint = '', String initial = '', bool number = false}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SpectreColors.panel,
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: number ? const TextInputType.numberWithOptions(signed: true) : null,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Tamam')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String text, {String ok = 'Onayla', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SpectreColors.panel,
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: SpectreColors.red) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
