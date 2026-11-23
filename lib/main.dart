import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'category_icons.dart';
import 'category_page.dart';
import 'db.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '简易记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: false),
      home: const HomePage(),
    );
  }
}

const List<String> _weekdayCn = ['一', '二', '三', '四', '五', '六', '日'];

String _monthLabel(DateTime d) =>
    '${d.year}年${d.month.toString().padLeft(2, '0')}月';

String _dayLabel(DateTime d) =>
    '${d.month}月${d.day}日 周${_weekdayCn[d.weekday - 1]}';

String _fullDate(DateTime d) =>
    '${d.year}年${d.month}月${d.day}日 周${_weekdayCn[d.weekday - 1]}';

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tabIndex = 0;
  final DBHelper db = DBHelper();

  /// 当前查看的月份（该月 1 号 00:00）
  late DateTime viewMonth;

  List<Bill> bills = [];
  List<Category> outCats = [];
  List<Category> inCats = [];
  double income = 0;
  double expense = 0;
  double monthBudget = 0;
  Map<String, double> catSum = {};
  Map<DateTime, List<Bill>> dayGroups = {};
  List<DateTime> dayKeys = [];
  List<PieChartSectionData> sections = [];

  /// 已构建过的 tab：切换时按需构建，避免首屏一次性建四个页面
  final Set<int> builtTabs = {0};

  final TextEditingController budgetCtrl = TextEditingController();
  final FocusNode budgetFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    viewMonth = DateTime(now.year, now.month);
    loadData();
  }

  @override
  void dispose() {
    budgetCtrl.dispose();
    budgetFocus.dispose();
    super.dispose();
  }

  bool get isCurrentMonth {
    final now = DateTime.now();
    return viewMonth.year == now.year && viewMonth.month == now.month;
  }

  int get monthStartTs => viewMonth.millisecondsSinceEpoch;
  int get monthEndTs =>
      DateTime(viewMonth.year, viewMonth.month + 1).millisecondsSinceEpoch - 1;
  String get monthKey =>
      '${viewMonth.year}-${viewMonth.month.toString().padLeft(2, '0')}';

  Future<void> loadData() async {
    try {
      final start = monthStartTs;
      final end = monthEndTs;
      // 三个查询一次性提交，减少往返等待
      final listFuture = db.getMonthBill(start, end);
      final budgetFuture = db.getBudget(monthKey);
      final catsFuture = db.getCategories();
      final list = await listFuture;
      final budget = await budgetFuture;
      final cats = await catsFuture;

      // 在内存里一次遍历算出收支与分类汇总，省掉两次 SQL 聚合查询
      double inSum = 0;
      double outSum = 0;
      final group = <String, double>{};
      for (final b in list) {
        if (b.type == 1) {
          inSum += b.amount;
        } else {
          outSum += b.amount;
          group[b.category] = (group[b.category] ?? 0) + b.amount;
        }
      }

      final groups = groupBy<Bill, DateTime>(
        list,
        (b) => DateTime.fromMillisecondsSinceEpoch(b.timestamp).dateOnly(),
      );
      final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

      if (!mounted) return;
      setState(() {
        bills = list;
        income = inSum;
        expense = outSum;
        monthBudget = budget;
        catSum = group;
        dayGroups = groups;
        dayKeys = keys;
        sections = _buildSections(group);
        outCats = cats.where((c) => c.type == 0).toList();
        inCats = cats.where((c) => c.type == 1).toList();
        if (!budgetFocus.hasFocus) {
          budgetCtrl.text = budget > 0 ? _trimNum(budget) : '';
        }
      });
    } catch (err) {
      if (!mounted) return;
      _snack(context, '数据加载失败：$err');
    }
  }

  /// 饼图分段只在数据变化时构建一次，避免每次 rebuild 重算
  List<PieChartSectionData> _buildSections(Map<String, double> data) {
    const colors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.brown,
    ];
    final list = <PieChartSectionData>[];
    var i = 0;
    data.forEach((cat, val) {
      list.add(PieChartSectionData(
        value: val,
        title: '$cat\n¥${val.toStringAsFixed(2)}',
        radius: 80,
        color: colors[i % colors.length],
        titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
      ));
      i++;
    });
    return list;
  }

  void changeMonth(int delta) {
    if (delta > 0 && isCurrentMonth) return;
    budgetFocus.unfocus();
    setState(() {
      viewMonth = DateTime(viewMonth.year, viewMonth.month + delta);
    });
    loadData();
  }

  Widget monthNav({bool onDark = false}) {
    final color = onDark ? Colors.white : Colors.black87;
    final disabledColor = color.withOpacity(0.35);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上个月',
          icon: Icon(Icons.chevron_left, color: color),
          onPressed: () => changeMonth(-1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            _monthLabel(viewMonth),
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '下个月',
          icon: Icon(Icons.chevron_right,
              color: isCurrentMonth ? disabledColor : color),
          onPressed: isCurrentMonth ? null : () => changeMonth(1),
        ),
      ],
    );
  }

  Future<void> openAddOrEditSheet({Bill? bill}) async {
    final initialDate =
        isCurrentMonth ? DateTime.now() : DateTime(viewMonth.year, viewMonth.month, 1);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AddBillSheet(
        outCats: outCats,
        inCats: inCats,
        editBill: bill,
        initialDate: initialDate,
        onSave: (b) async {
          if (b.id == null) {
            await db.addBill(b);
          } else {
            await db.updateBill(b);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          await loadData();
        },
      ),
    );
  }

  Future<void> confirmDelete(Bill b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除账单：${b.category} ¥${b.amount.toStringAsFixed(2)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && b.id != null) {
      await db.deleteBill(b.id!);
      await loadData();
    }
  }

  // ---------------- 首页：账单 ----------------

  Widget buildHome() {
    return Column(
      children: [
        Container(
          color: Colors.teal,
          padding: EdgeInsets.fromLTRB(
              8, MediaQuery.of(context).padding.top + 8, 8, 16),
          child: Column(
            children: [
              monthNav(onDark: true),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryTile('收入', income),
                  _summaryTile('支出', expense),
                  _summaryTile('结余', income - expense),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: bills.isEmpty
              ? Center(
                  child: Text(isCurrentMonth ? '本月暂无账单，点 + 开始记账' : '该月暂无账单'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: dayKeys.length,
                  itemBuilder: (_, idx) {
                    final date = dayKeys[idx];
                    final dayBills = dayGroups[date]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Text(
                            _dayLabel(date),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        ...dayBills.map((b) {
                          return ListTile(
                            onTap: () => openAddOrEditSheet(bill: b),
                            onLongPress: () => confirmDelete(b),
                            leading: Icon(
                              b.type == 0
                                  ? Icons.remove_circle
                                  : Icons.add_circle,
                              color: b.type == 0 ? Colors.red : Colors.green,
                            ),
                            title: Text(b.category),
                            subtitle: Text(
                                b.remark.isNotEmpty ? b.remark : '无备注'),
                            trailing: Text(
                              '${b.type == 0 ? '-' : '+'}${b.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color:
                                    b.type == 0 ? Colors.red : Colors.green,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _summaryTile(String label, double value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text('¥${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ],
    );
  }

  // ---------------- 统计 ----------------

  Widget buildStat() {
    return Column(
      children: [
        SafeArea(bottom: false, child: monthNav()),
        Expanded(
          child: catSum.isEmpty
              ? const Center(child: Text('该月暂无支出数据'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('支出分类占比',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 280,
                        child: RepaintBoundary(
                          child: PieChart(PieChartData(sections: sections)),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ---------------- 预算 ----------------

  Widget buildBudget() {
    final hasBudget = monthBudget > 0;
    final remain = monthBudget - expense;
    final double progress =
        hasBudget ? (expense / monthBudget).clamp(0.0, 1.0).toDouble() : 0.0;

    return Column(
      children: [
        SafeArea(bottom: false, child: monthNav()),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('月度预算',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetCtrl,
                  focusNode: budgetFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '本月预算金额',
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saveBudget,
                    child: const Text('保存预算'),
                  ),
                ),
                const SizedBox(height: 24),
                if (hasBudget) ...[
                  Text('已支出：¥${expense.toStringAsFixed(2)}'),
                  Text('预算总额：¥${monthBudget.toStringAsFixed(2)}'),
                  Text(
                    '剩余预算：¥${remain.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: remain >= 0 ? Colors.green : Colors.red),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      color: remain >= 0 ? Colors.teal : Colors.red,
                    ),
                  ),
                  if (expense > monthBudget)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '已超出预算 ¥${(expense - monthBudget).toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ] else
                  const Text('该月还没有设置预算',
                      style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> saveBudget() async {
    final v = double.tryParse(budgetCtrl.text.trim()) ?? 0;
    if (v < 0) {
      _snack(context, '预算不能为负数');
      return;
    }
    budgetFocus.unfocus();
    await db.saveBudget(monthKey, v);
    await loadData();
    if (mounted) {
      _snack(context, v == 0 ? '已清除该月预算' : '预算已保存');
    }
  }

  // ---------------- 设置 ----------------

  Widget buildSettings() {
    return SafeArea(
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('分类管理'),
            subtitle: const Text('自定义收支分类与图标'),
            trailing: const Icon(Icons.chevron_right),
            onTap: openCategoryPage,
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('简易记账 v1.1.0 · 数据仅保存在本机'),
          ),
        ],
      ),
    );
  }

  Future<void> openCategoryPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategoryPage(db: db)),
    );
    await loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: List.generate(4, (i) {
          if (!builtTabs.contains(i)) return const SizedBox.shrink();
          return switch (i) {
            0 => buildHome(),
            1 => buildStat(),
            2 => buildBudget(),
            _ => buildSettings(),
          };
        }),
      ),
      floatingActionButton: tabIndex == 0
          ? FloatingActionButton(
              onPressed: () => openAddOrEditSheet(),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: tabIndex,
        onTap: (i) => setState(() {
          tabIndex = i;
          builtTabs.add(i);
        }),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: '账单'),
          BottomNavigationBarItem(
              icon: Icon(Icons.pie_chart_outline), label: '统计'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined), label: '预算'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}

class AddBillSheet extends StatefulWidget {
  final List<Category> outCats;
  final List<Category> inCats;
  final Bill? editBill;
  final DateTime initialDate;
  final Future<void> Function(Bill) onSave;

  const AddBillSheet({
    super.key,
    required this.outCats,
    required this.inCats,
    required this.initialDate,
    required this.onSave,
    this.editBill,
  });

  @override
  State<AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<AddBillSheet> {
  late int type;
  String? cat;
  late DateTime date;
  bool saving = false;

  final amountCtrl = TextEditingController();
  final remarkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = widget.editBill;
    if (b != null) {
      type = b.type;
      cat = b.category;
      date = DateTime.fromMillisecondsSinceEpoch(b.timestamp);
      amountCtrl.text = _trimNum(b.amount);
      remarkCtrl.text = b.remark;
    } else {
      type = 0;
      date = widget.initialDate;
    }
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    remarkCtrl.dispose();
    super.dispose();
  }

  List<Category> get currentCats => type == 0 ? widget.outCats : widget.inCats;

  void switchType(int t) {
    setState(() {
      type = t;
      final cats = t == 0 ? widget.outCats : widget.inCats;
      // 切换收支类型时，若原分类不在新列表里则清空，避免“收入-餐饮”这种脏数据
      if (!cats.any((c) => c.name == cat)) cat = null;
    });
  }

  Future<void> pickDate() async {
    final now = DateTime.now();
    final initial = date.isAfter(now) ? now : date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: '选择账单日期',
    );
    if (picked != null) {
      setState(() => date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> save() async {
    if (saving) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      _snack(context, '请输入正确的金额');
      return;
    }
    if (cat == null) {
      _snack(context, '请选择分类');
      return;
    }

    final sel = DateTime(date.year, date.month, date.day);
    int ts = sel.millisecondsSinceEpoch;
    final b = widget.editBill;
    if (b != null) {
      final orig = DateTime.fromMillisecondsSinceEpoch(b.timestamp);
      if (DateUtils.isSameDay(orig, sel)) {
        ts = b.timestamp;
      } else if (DateUtils.isSameDay(sel, DateTime.now())) {
        ts = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (DateUtils.isSameDay(sel, DateTime.now())) {
      ts = DateTime.now().millisecondsSinceEpoch;
    }

    setState(() => saving = true);
    try {
      await widget.onSave(Bill(
        id: b?.id,
        amount: amount,
        type: type,
        category: cat!,
        remark: remarkCtrl.text.trim(),
        timestamp: ts,
      ));
    } catch (err) {
      if (!mounted) return;
      setState(() => saving = false);
      _snack(context, '保存失败：$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _typeButton('支出', 0)),
                Expanded(child: _typeButton('收入', 1)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '日期',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(_fullDate(date)),
              ),
            ),
            const SizedBox(height: 12),
            if (currentCats.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('还没有分类，请到「设置 → 分类管理」添加',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: currentCats
                    .map((c) => ChoiceChip(
                          selected: cat == c.name,
                          avatar: Icon(iconOf(c.icon), size: 18),
                          label: Text(c.name),
                          onSelected: (_) => setState(() => cat = c.name),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: remarkCtrl,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saving ? null : save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(widget.editBill == null ? '新增' : '保存修改'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeButton(String label, int t) {
    final selected = type == t;
    return TextButton(
      onPressed: () => switchType(t),
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.teal : Colors.grey,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

extension DateOnly on DateTime {
  DateTime dateOnly() => DateTime(year, month, day);
}
