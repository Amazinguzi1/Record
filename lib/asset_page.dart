import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'db.dart';

const Map<String, String> _typeName = {
  'cash': '现金',
  'debit': '储蓄卡',
  'credit': '信用卡',
  'mobile': '移动支付',
  'custom': '自定义资产',
  'custom_debt': '自定义欠款',
};

const Map<String, IconData> _typeIcon = {
  'cash': Icons.money,
  'debit': Icons.credit_card,
  'credit': Icons.credit_card_outlined,
  'mobile': Icons.phone_android,
  'custom': Icons.category,
  'custom_debt': Icons.trending_down,
};

const List<Color> _palette = [
  Colors.blue,
  Colors.orange,
  Colors.green,
  Colors.purple,
  Colors.pink,
  Colors.amber,
  Colors.cyan,
  Colors.brown,
];

String _fmtAmount(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class AssetPage extends StatefulWidget {
  final DBHelper db;

  const AssetPage({super.key, required this.db});

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  int tab = 0;
  bool loading = true;
  List<Account> accounts = [];

  int year = DateTime.now().year;
  Map<int, double> monthlyNet = {}; // 某年各月净收支（收入-支出）

  double get totalAssets =>
      accounts.where((a) => !a.isLiability).fold(0.0, (s, a) => s + a.amount);
  double get totalLiabilities =>
      accounts.where((a) => a.isLiability).fold(0.0, (s, a) => s + a.amount);
  double get netWorth => totalAssets - totalLiabilities;

  @override
  void initState() {
    super.initState();
    _load();
    _loadYearBills();
  }

  Future<void> _load() async {
    final list = await widget.db.getAccounts();
    if (!mounted) return;
    setState(() {
      accounts = list;
      loading = false;
    });
  }

  Future<void> _loadYearBills() async {
    final start = DateTime(year, 1, 1).millisecondsSinceEpoch;
    final end =
        DateTime(year, 12, 31, 23, 59, 59, 999).millisecondsSinceEpoch;
    final list = await widget.db.getMonthBill(start, end);
    final net = <int, double>{};
    for (final b in list) {
      final m = DateTime.fromMillisecondsSinceEpoch(b.timestamp).month;
      final delta = b.type == 1 ? b.amount : -b.amount;
      net[m] = (net[m] ?? 0) + delta;
    }
    if (!mounted) return;
    setState(() => monthlyNet = net);
  }

  void _setYear(int y) {
    if (y == year) return;
    setState(() => year = y);
    _loadYearBills();
  }

  // ---------------- 添加 / 编辑账户 ----------------

  Future<void> _addAsset() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择资产种类',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ..._typeName.entries.map((e) => ListTile(
                  leading: Icon(_typeIcon[e.key]),
                  title: Text(e.value),
                  onTap: () => Navigator.pop(ctx, e.key),
                )),
          ],
        ),
      ),
    );
    if (type == null) return;
    await _editAccount(type: type);
  }

  Future<void> _editAccount({Account? existing, required String type}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final bankCtrl = TextEditingController(text: existing?.bankName ?? '');
    final cardCtrl = TextEditingController(text: existing?.cardLast4 ?? '');
    final remarkCtrl = TextEditingController(text: existing?.remark ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null && existing.amount != 0
            ? _fmtAmount(existing.amount)
            : '');

    final isCard = type == 'debit' || type == 'credit';
    final isDebt = type == 'credit' || type == 'custom_debt';

    final ok = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null
            ? '添加${_typeName[type]}'
            : '编辑${_typeName[type]}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCard)
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(labelText: '银行名'),
                ),
              if (isCard)
                TextField(
                  controller: cardCtrl,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: '卡号后四位'),
                ),
              if (!isCard)
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isDebt ? '欠款' : '余额',
                  prefixText: '¥ ',
                ),
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
                child:
                    const Text('删除', style: TextStyle(color: Colors.red))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok == null) return;
    if (ok == 'delete') {
      await widget.db.deleteAccount(existing!.id!);
      await _load();
      return;
    }
    if (ok != true) return;

    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final baseName = isCard ? bankCtrl.text.trim() : nameCtrl.text.trim();
    if (isCard && baseName.isEmpty) {
      if (mounted) _toast('请填写银行名');
      return;
    }
    final a = Account(
      id: existing?.id,
      type: type,
      name: baseName.isEmpty ? _typeName[type]! : baseName,
      bankName: bankCtrl.text.trim(),
      cardLast4: cardCtrl.text.trim(),
      remark: remarkCtrl.text.trim(),
      amount: amount,
    );
    if (existing == null) {
      await widget.db.addAccount(a);
    } else {
      await widget.db.updateAccount(a);
    }
    await _load();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('资产')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (tab == 0 ? _buildAssetTab() : _buildStatTab()),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: '资产'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '统计'),
        ],
      ),
    );
  }

  Widget _buildAssetTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 净资产块
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('净资产',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              Text('¥${fmtMoney(netWorth)}',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('资产 ¥${fmtMoney(totalAssets)}',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54)),
                  const SizedBox(width: 16),
                  Text('负债 ¥${fmtMoney(totalLiabilities)}',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 添加资产
        InkWell(
          onTap: _addAsset,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade100),
            ),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: Colors.teal),
                  SizedBox(width: 4),
                  Text('添加资产',
                      style: TextStyle(
                          color: Colors.teal,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 账户列表
        if (accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('还没有资产，点击上方添加',
                    style: TextStyle(color: Colors.grey))),
          )
        else
          ...accounts.map((a) => _accountRow(a)),
      ],
    );
  }

  Widget _accountRow(Account a) {
    final accent = a.isLiability ? Colors.red : Colors.teal;
    final sub = [
      _typeName[a.type] ?? '',
      if (a.cardLast4.isNotEmpty) '****${a.cardLast4}',
      if (a.remark.isNotEmpty) a.remark,
    ].where((s) => s.isNotEmpty).join('  ');
    return InkWell(
      onTap: () => _editAccount(existing: a, type: a.type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: accent.withOpacity(0.1),
              child: Icon(_typeIcon[a.type] ?? Icons.category,
                  color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Text('¥${fmtMoney(a.amount)}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: a.isLiability ? Colors.red : Colors.black87)),
          ],
        ),
      ),
    );
  }

  // ---------------- 统计 ----------------

  Widget _buildStatTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTrendCard(),
        const SizedBox(height: 24),
        _buildPieCard(),
        const SizedBox(height: 24),
        _buildProgressCard(),
        const SizedBox(height: 24),
        _buildRanking(),
      ],
    );
  }

  Widget _buildTrendCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('资产走势图',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            PopupMenuButton<int>(
              initialValue: year,
              onSelected: _setYear,
              itemBuilder: (_) => [
                for (var y = DateTime.now().year;
                    y >= DateTime.now().year - 10;
                    y--)
                  PopupMenuItem(value: y, child: Text('$y')),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$year',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(height: 200, child: LineChart(_trendData())),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(Colors.green, '资产'),
            const SizedBox(width: 14),
            _legendDot(Colors.red, '负债'),
            const SizedBox(width: 14),
            _legendDot(Colors.amber.shade700, '净资产'),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  LineChartData _trendData() {
    final currentMonth =
        (year == DateTime.now().year) ? DateTime.now().month : 12;
    double assetAt(int m) {
      double v = totalAssets;
      for (var k = m + 1; k <= currentMonth; k++) {
        v -= (monthlyNet[k] ?? 0);
      }
      return v;
    }

    final assetSpots = <FlSpot>[];
    final liabSpots = <FlSpot>[];
    final netSpots = <FlSpot>[];
    double lo = 0, hi = 0;
    for (var m = 1; m <= 12; m++) {
      final a = assetAt(m);
      final l = totalLiabilities;
      final n = a - l;
      assetSpots.add(FlSpot((m - 1).toDouble(), a));
      liabSpots.add(FlSpot((m - 1).toDouble(), l));
      netSpots.add(FlSpot((m - 1).toDouble(), n));
      for (final v in [a, l, n]) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (hi == 0) hi = 10;
    lo = lo < 0 ? lo * 1.15 : 0;
    hi = hi * 1.15;

    return LineChartData(
      minX: 0,
      maxX: 11,
      minY: lo,
      maxY: hi,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (v, m) => Text('${v.toInt() + 1}',
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ),
        ),
      ),
      lineBarsData: [
        _line(assetSpots, Colors.green),
        _line(liabSpots, Colors.red),
        _line(netSpots, Colors.amber.shade700),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color c) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: c,
      barWidth: 2,
      dotData: FlDotData(
        show: true,
        getDotPainter: (s, p, b, i) =>
            FlDotCirclePainter(radius: 2.5, color: c, strokeWidth: 0),
      ),
    );
  }

  Widget _buildPieCard() {
    final assetItems =
        accounts.where((a) => !a.isLiability && a.amount > 0).toList();
    final liabItems =
        accounts.where((a) => a.isLiability && a.amount > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('资产状况',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _pieBox('资产', assetItems, Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _pieBox('负债', liabItems, Colors.red)),
          ],
        ),
      ],
    );
  }

  Widget _pieBox(String label, List<Account> items, Color accent) {
    final total = items.fold<double>(0, (s, a) => s + a.amount);
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 6),
        SizedBox(
          height: 120,
          child: items.isEmpty
              ? const Center(
                  child: Text('暂无',
                      style:
                          TextStyle(color: Colors.grey, fontSize: 12)))
              : PieChart(
                  PieChartData(
                    sectionsSpace: 1,
                    centerSpaceRadius: 18,
                    sections: [
                      for (final a in items)
                        PieChartSectionData(
                          value: a.amount,
                          title: '',
                          radius: 40,
                          color: _palette[
                              accounts.indexOf(a) % _palette.length],
                        ),
                    ],
                  ),
                ),
        ),
        Text('¥${fmtMoney(total)}',
            style: TextStyle(
                fontSize: 12, color: accent, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildProgressCard() {
    final a = totalAssets;
    final l = totalLiabilities;
    final net = a - l;
    final ratio = a > 0 ? (l / a).clamp(0.0, 1.0).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 16,
            child: Stack(
              children: [
                Container(color: Colors.amber.shade400),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(color: Colors.red),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('负债 ¥${fmtMoney(l)}',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
            const Spacer(),
            Text('净资产 ¥${fmtMoney(net)}',
                style: TextStyle(
                    fontSize: 12, color: Colors.amber.shade800)),
          ],
        ),
      ],
    );
  }

  Widget _buildRanking() {
    final items = [...accounts]..sort((a, b) => b.amount.compareTo(a.amount));
    if (items.isEmpty) {
      return const Text('暂无资产', style: TextStyle(color: Colors.grey));
    }
    final maxAmt = items.first.amount == 0 ? 1.0 : items.first.amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('资产排行',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...items.map((a) {
          final c = a.isLiability ? Colors.red : Colors.teal;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_typeIcon[a.type] ?? Icons.category,
                        size: 18, color: c),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(a.name,
                            overflow: TextOverflow.ellipsis)),
                    Text('¥${fmtMoney(a.amount)}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text(a.isLiability ? '负债' : '资产',
                        style: TextStyle(fontSize: 11, color: c)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (a.amount / maxAmt).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    color: c,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
