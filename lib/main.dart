import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'asset_page.dart';
import 'category_icons.dart';
import 'category_page.dart';
import 'db.dart';
import 'regular_page.dart';
import 'stat_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Record',
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
  double totalAssets = 0;
  double totalLiabilities = 0;
  Map<String, double> catSum = {};
  Map<DateTime, List<Bill>> dayGroups = {};
  List<DateTime> dayKeys = [];
  List<PieChartSectionData> sections = [];

  /// "类型:分类名" -> 图标 key，供账单列表显示分类图标
  Map<String, String> catIcons = {};

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
      final accountsFuture = db.getAccounts();
      final list = await listFuture;
      final budget = await budgetFuture;
      final cats = await catsFuture;
      final accounts = await accountsFuture;

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
        double ta = 0, tl = 0;
        for (final a in accounts) {
          if (a.isLiability) {
            tl += a.amount;
          } else {
            ta += a.amount;
          }
        }
        totalAssets = ta;
        totalLiabilities = tl;
        catSum = group;
        dayGroups = groups;
        dayKeys = keys;
        sections = _buildSections(group);
        outCats = cats.where((c) => c.type == 0).toList();
        inCats = cats.where((c) => c.type == 1).toList();
        catIcons = {
          for (final c in cats) '${c.type}:${c.name}': c.icon,
        };
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
        title: '$cat\n¥${fmtMoney(val)}',
        radius: 80,
        color: colors[i % colors.length],
        titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
      ));
      i++;
    });
    return list;
  }

  /// 弹出年 / 月双滚轮，快速定位到任意年月
  Future<void> selectYearMonth() async {
    final now = DateTime.now();
    final years = [for (var y = 2000; y <= now.year; y++) y];
    var selYear = viewMonth.year;
    var selMonth = viewMonth.month;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    const Expanded(
                      child: Text(
                        '选择年月',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('确定')),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _wheel(
                          count: years.length,
                          initial: years.indexOf(viewMonth.year),
                          label: (i) => '${years[i]}年',
                          onChanged: (i) => selYear = years[i],
                        ),
                      ),
                      Expanded(
                        child: _wheel(
                          count: 12,
                          initial: viewMonth.month - 1,
                          label: (i) => '${i + 1}月',
                          onChanged: (i) => selMonth = i + 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true) return;
    final target = DateTime(selYear, selMonth);
    if (target.year == viewMonth.year && target.month == viewMonth.month) {
      return;
    }
    budgetFocus.unfocus();
    setState(() => viewMonth = target);
    loadData();
  }

  Widget _wheel({
    required int count,
    required int initial,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: FixedExtentScrollController(initialItem: initial),
      itemExtent: 40,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (_, i) => Center(
          child: Text(label(i), style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget monthNav({bool onDark = false}) {
    final color = onDark ? Colors.white : Colors.black87;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: selectYearMonth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _monthLabel(viewMonth),
                  style: TextStyle(
                      color: color, fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, color: color, size: 22),
              ],
            ),
          ),
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
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AddBillSheet(
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
      ),
    );
  }

  Future<void> confirmDelete(Bill b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除账单：${b.category} ¥${fmtMoney(b.amount)}'),
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
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(
                8, MediaQuery.of(context).padding.top + 8, 8, 16),
            child: Column(
              children: [
                monthNav(),
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
                    double dayIn = 0, dayOut = 0;
                    for (final b in dayBills) {
                      if (b.type == 1) {
                        dayIn += b.amount;
                      } else {
                        dayOut += b.amount;
                      }
                    }
                    final dayNet = dayIn - dayOut;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              Text(
                                _dayLabel(date),
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13),
                              ),
                              const Spacer(),
                              _dayStat('收', dayIn, Colors.green),
                              const SizedBox(width: 10),
                              _dayStat('支', dayOut, Colors.red),
                              const SizedBox(width: 10),
                              _dayStat('净', dayNet,
                                  dayNet >= 0 ? Colors.green : Colors.red,
                                  signed: true),
                            ],
                          ),
                        ),
                        ...dayBills.map((b) {
                          return ListTile(
                            onTap: () => openAddOrEditSheet(bill: b),
                            onLongPress: () => confirmDelete(b),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: (b.type == 0
                                      ? Colors.red
                                      : Colors.green)
                                  .withOpacity(0.12),
                              child: Icon(
                                iconOf(catIcons['${b.type}:${b.category}'] ??
                                    'other'),
                                size: 20,
                                color:
                                    b.type == 0 ? Colors.red : Colors.green,
                              ),
                            ),
                            title: Text(b.category),
                            subtitle: Text(
                                b.remark.isNotEmpty ? b.remark : '无备注'),
                            trailing: Text(
                              '${b.type == 0 ? '-' : '+'}${fmtMoney(b.amount)}',
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
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 4),
        Text('¥${fmtMoney(value)}',
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// 日期行右侧的当日收支小块：收入/支出取非负，净收入带正负号
  Widget _dayStat(String label, double v, Color color, {bool signed = false}) {
    final text = signed
        ? '${v >= 0 ? '+' : '-'}¥${fmtMoney(v.abs())}'
        : '¥${fmtMoney(v.abs())}';
    return Text(
      '$label $text',
      style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w500),
    );
  }

  // ---------------- 统计 ----------------

  Widget buildStat() => StatPage(db: db);

  // ---------------- 预算 ----------------

  Widget buildBudget() {
    final hasBudget = monthBudget > 0;
    final remain = monthBudget - expense;
    final double remainRatio =
        hasBudget ? (remain / monthBudget).clamp(0.0, 1.0).toDouble() : 0.0;
    final double remainPct = hasBudget
        ? ((remain / monthBudget) * 100).clamp(0.0, 100.0).toDouble()
        : 0.0;
    final remainColor = remain >= 0 ? Colors.teal : Colors.red;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // 顶部：月份（居中）+ 编辑（日期右侧）
          Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: monthNav(),
              ),
              Positioned(
                right: 8,
                child: TextButton(
                  onPressed: _editBudget,
                  child: const Text('编辑'),
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                children: [
                  _budgetCard(
                      hasBudget, remain, remainRatio, remainPct, remainColor),
                  const SizedBox(height: 16),
                  _assetCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetCard(bool hasBudget, double remain, double remainRatio,
      double remainPct, Color remainColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${viewMonth.month}月总预算',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CircularProgressIndicator(
                        // 剩余部分有颜色，花费掉的部分留白
                        value: remainRatio,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            hasBudget ? remainColor : Colors.grey),
                      ),
                    ),
                    Text(
                      hasBudget ? '${remainPct.toStringAsFixed(0)}%' : '--',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: hasBudget ? remainColor : Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('剩余预算：¥${fmtMoney(remain)}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: remainColor)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Color(0xFFE6E6E6)),
                    ),
                    Text('本月预算：¥${fmtMoney(monthBudget)}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text('本月支出：¥${fmtMoney(expense)}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _assetCard() {
    final net = totalAssets - totalLiabilities;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('资产',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              IconButton(
                tooltip: '资产明细',
                icon: const Icon(Icons.chevron_right),
                onPressed: openAssetPage,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Expanded(child: _assetStat('净资产', net)),
                Expanded(child: _assetStat('资产', totalAssets)),
                Expanded(child: _assetStat('负债', totalLiabilities)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _assetStat(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text('¥${fmtMoney(value)}',
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> openAssetPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AssetPage(db: db)),
    );
    await loadData();
  }

  Future<void> _editBudget() async {
    final ctrl = TextEditingController(
        text: monthBudget > 0 ? _trimNum(monthBudget) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${viewMonth.month}月预算'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '预算金额',
            prefixText: '¥ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text.trim()) ?? 0;
    if (v < 0) {
      if (mounted) _snack(context, '预算不能为负数');
      return;
    }
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
          ListTile(
            leading: const Icon(Icons.bolt),
            title: const Text('常用记账'),
            subtitle: const Text('设置高频使用的快捷记账模板'),
            trailing: const Icon(Icons.chevron_right),
            onTap: openRegularPage,
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('Record v1.2.0 · 数据仅保存在本机'),
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

  Future<void> openRegularPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegularPage(db: db)),
    );
    await loadData();
  }

  /// 快捷记账：选择常用模板，一键记录到今天
  Future<void> _openQuickRecord() async {
    final regulars = await db.getRegulars();
    if (!mounted) return;
    if (regulars.isEmpty) {
      _snack(context, '还没有常用记账，请到 设置 → 常用记账 添加');
      return;
    }
    final picked = await showModalBottomSheet<Regular>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('快捷记账',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...regulars.map((r) {
              final accent = r.type == 0 ? Colors.red : Colors.green;
              final iconKey = catIcons['${r.type}:${r.category}'] ?? 'other';
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
                  style:
                      TextStyle(color: accent, fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(ctx, r),
              );
            }),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final b = Bill(
      amount: picked.amount,
      type: picked.type,
      category: picked.category,
      remark: picked.remark,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payMethod: picked.payMethod,
    );
    await db.addBill(b);
    await loadData();
    if (mounted) {
      _snack(context, '已记录 ${picked.category} ¥${fmtMoney(picked.amount)}');
    }
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
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 黄色闪电：快捷记账（常用模板）
                FloatingActionButton(
                  heroTag: 'quick',
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.white,
                  onPressed: _openQuickRecord,
                  child: const Icon(Icons.bolt),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'add',
                  onPressed: () => openAddOrEditSheet(),
                  child: const Icon(Icons.add),
                ),
              ],
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
  String payMethod = '';

  final amountCtrl = TextEditingController();
  final remarkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = widget.editBill;
    if (b != null) {
      type = b.type;
      cat = b.category;
      payMethod = b.payMethod;
      date = DateTime.fromMillisecondsSinceEpoch(b.timestamp);
      amountCtrl.text = _trimNum(b.amount);
      remarkCtrl.text = b.remark;
    } else {
      type = 0;
      date = widget.initialDate;
      payMethod = '';
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
        payMethod: payMethod,
      ));
    } catch (err) {
      if (!mounted) return;
      setState(() => saving = false);
      _snack(context, '保存失败：$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
                          selectedColor: Colors.teal.shade600,
                          avatar: Icon(iconOf(c.icon),
                              size: 18,
                              color: cat == c.name
                                  ? Colors.white
                                  : Colors.grey.shade700),
                          label: Text(c.name,
                              style: TextStyle(
                                  color: cat == c.name
                                      ? Colors.white
                                      : Colors.black87)),
                          onSelected: (_) => setState(() => cat = c.name),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('支付方式',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['储蓄卡', '信用卡', '微信', '支付宝']
                  .map((p) => ChoiceChip(
                        selected: payMethod == p,
                        selectedColor: Colors.teal.shade600,
                        label: Text(p,
                            style: TextStyle(
                                color: payMethod == p
                                    ? Colors.white
                                    : Colors.black87)),
                        onSelected: (_) => setState(
                            () => payMethod = payMethod == p ? '' : p),
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
