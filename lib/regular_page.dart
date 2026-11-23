import 'package:flutter/material.dart';

import 'category_icons.dart';
import 'db.dart';

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class RegularPage extends StatefulWidget {
  final DBHelper db;

  const RegularPage({super.key, required this.db});

  @override
  State<RegularPage> createState() => _RegularPageState();
}

class _RegularPageState extends State<RegularPage> {
  List<Regular> regulars = [];
  List<Category> cats = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.db.getRegulars();
    final c = await widget.db.getCategories();
    if (!mounted) return;
    setState(() {
      regulars = r;
      cats = c;
      loading = false;
    });
  }

  Map<String, String> get _iconMap =>
      {for (final c in cats) '${c.type}:${c.name}': c.icon};

  List<Category> _catsOf(int t) => cats.where((c) => c.type == t).toList();

  Future<void> _edit({Regular? existing}) async {
    var type = existing?.type ?? 0;
    String? cat = existing?.category;
    String payMethod = existing?.payMethod ?? '';
    final amountCtrl = TextEditingController(
        text: existing != null && existing.amount != 0
            ? _fmt(existing.amount)
            : '');
    final remarkCtrl = TextEditingController(text: existing?.remark ?? '');

    final ok = await showDialog<Object>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final list = _catsOf(type);
          return AlertDialog(
            title: Text(existing == null ? '新增常用记账' : '编辑常用记账'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('支出'),
                          selected: type == 0,
                          onSelected: (_) => setDlg(() {
                            type = 0;
                            if (!_catsOf(0).any((c) => c.name == cat)) {
                              cat = null;
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('收入'),
                          selected: type == 1,
                          onSelected: (_) => setDlg(() {
                            type = 1;
                            if (!_catsOf(1).any((c) => c.name == cat)) {
                              cat = null;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: list
                        .map((c) => ChoiceChip(
                              selected: cat == c.name,
                              selectedColor: Colors.teal.shade600,
                              avatar: Icon(iconOf(c.icon),
                                  size: 16,
                                  color: cat == c.name
                                      ? Colors.white
                                      : Colors.grey.shade700),
                              label: Text(c.name,
                                  style: TextStyle(
                                      color: cat == c.name
                                          ? Colors.white
                                          : Colors.black87)),
                              onSelected: (_) =>
                                  setDlg(() => cat = c.name),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '金额', prefixText: '¥ '),
                  ),
                  TextField(
                    controller: remarkCtrl,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('支付方式',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['', '储蓄卡', '信用卡', '微信', '支付宝']
                        .map((p) => ChoiceChip(
                              selected: payMethod == p,
                              selectedColor: Colors.teal.shade600,
                              label: Text(p.isEmpty ? '无' : p,
                                  style: TextStyle(
                                      color: payMethod == p
                                          ? Colors.white
                                          : Colors.black87)),
                              onSelected: (_) =>
                                  setDlg(() => payMethod = p),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              if (existing != null)
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    child: const Text('删除',
                        style: TextStyle(color: Colors.red))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存')),
            ],
          );
        },
      ),
    );
    if (ok == null) return;
    if (ok == 'delete') {
      await widget.db.deleteRegular(existing!.id!);
      await _load();
      return;
    }
    if (ok != true) return;

    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (cat == null) {
      _toast('请选择分类');
      return;
    }
    if (amount <= 0) {
      _toast('请输入金额');
      return;
    }
    final r = Regular(
      id: existing?.id,
      type: type,
      category: cat!,
      amount: amount,
      remark: remarkCtrl.text.trim(),
      payMethod: payMethod,
    );
    if (existing == null) {
      await widget.db.addRegular(r);
    } else {
      await widget.db.updateRegular(r);
    }
    await _load();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('常用记账')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : regulars.isEmpty
              ? const Center(
                  child: Text('还没有常用记账，点右下角添加',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: regulars.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = regulars[i];
                    final accent =
                        r.type == 0 ? Colors.red : Colors.green;
                    final iconKey =
                        _iconMap['${r.type}:${r.category}'] ?? 'other';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accent.withOpacity(0.1),
                        child: Icon(iconOf(iconKey), color: accent),
                      ),
                      title: Text(r.category),
                      subtitle: Text(
                          [r.remark, r.payMethod]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Text(
                        '${r.type == 0 ? '-' : '+'}¥${fmtMoney(r.amount)}',
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.w600),
                      ),
                      onTap: () => _edit(existing: r),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
