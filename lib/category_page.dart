import 'package:flutter/material.dart';

import 'category_icons.dart';
import 'db.dart';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class CategoryPage extends StatefulWidget {
  final DBHelper db;

  const CategoryPage({super.key, required this.db});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<Category> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cats = await widget.db.getCategories();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _loading = false;
    });
  }

  List<Category> _of(int type) => _cats.where((c) => c.type == type).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: '支出分类'), Tab(text: '收入分类')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_buildList(0), _buildList(1)],
            ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: () => _edit(type: _tab.index),
          icon: const Icon(Icons.add),
          label: Text(_tab.index == 0 ? '新增支出分类' : '新增收入分类'),
        ),
      ),
    );
  }

  Widget _buildList(int type) {
    final items = _of(type);
    if (items.isEmpty) {
      return const Center(child: Text('还没有分类，点右下角添加'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = items[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.teal.shade50,
            child: Icon(iconOf(c.icon), color: Colors.teal),
          ),
          title: Text(c.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(existing: c, type: type),
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(c),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _edit({Category? existing, required int type}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var iconKey = existing?.icon ?? 'other';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: Text(existing == null ? '新增分类' : '编辑分类'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: existing == null,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: '分类名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('选择图标',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kCategoryIcons.entries.map((e) {
                        final selected = iconKey == e.key;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setDlg(() => iconKey = e.key),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.teal.withOpacity(0.15)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? Colors.teal
                                    : Colors.grey.shade300,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              e.value,
                              color: selected ? Colors.teal : Colors.grey.shade700,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    final name = nameCtrl.text.trim();
    if (result != true) return;

    if (name.isEmpty) {
      if (mounted) _toast(context, '名称不能为空');
      return;
    }
    final dup =
        _cats.any((c) => c.type == type && c.name == name && c.id != existing?.id);
    if (dup) {
      if (mounted) _toast(context, '该分类已存在');
      return;
    }

    if (existing == null) {
      final sort = _of(type).length;
      await widget.db.addCategory(
          Category(name: name, type: type, icon: iconKey, sort: sort));
      if (mounted) _toast(context, '已添加「$name」');
    } else {
      existing
        ..name = name
        ..icon = iconKey;
      await widget.db.updateCategory(existing);
      if (mounted) _toast(context, '已保存');
    }
    await _load();
  }

  Future<void> _delete(Category c) async {
    final count = await widget.db.countBillsOfCategory(c.name, c.type);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分类'),
        content: Text(
          count > 0
              ? '「${c.name}」下有 $count 条账单。删除分类不会删除这些账单，它们会保留原分类名。确定删除？'
              : '确定删除分类「${c.name}」？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.db.deleteCategory(c.id!);
    if (mounted) _toast(context, '已删除「${c.name}」');
    await _load();
  }
}
