import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'category_icons.dart';
import 'db.dart';

const List<Color> _palette = [
  Colors.blue,
  Colors.orange,
  Colors.green,
  Colors.purple,
  Colors.pink,
  Colors.amber,
  Colors.cyan,
  Colors.brown,
  Colors.indigo,
  Colors.teal,
];

/// 统计页：支出 / 收入 两个分页；每个分页可切换 周 / 月。
/// 上方折线图（含均值线）、中间饼图（缩小）、下方分类排行。
class StatPage extends StatefulWidget {
  final DBHelper db;

  const StatPage({super.key, required this.db});

  @override
  State<StatPage> createState() => _StatPageState();
}

class _StatPageState extends State<StatPage> {
  int statType = 0; // 0 支出，1 收入
  bool isWeek = true;
  bool loading = true;

  /// 当前选择的周期锚点（周：所在周的任意一天；月：该月）
  DateTime _anchor = DateTime.now();

  List<Bill> _bills = [];
  List<DateTime> _days = [];
  List<double> _daily = [];
  Map<String, double> _catSum = {};
  Map<String, String> _iconOf = {};
  double _total = 0;
  double _avg = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _start {
    if (isWeek) {
      final monday = _anchor.subtract(Duration(days: _anchor.weekday - 1));
      return DateTime(monday.year, monday.month, monday.day);
    }
    return DateTime(_anchor.year, _anchor.month);
  }

  int get _dayCount {
    final s = _start;
    if (isWeek) return 7;
    return DateTime(s.year, s.month + 1, 0).day;
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final start = _start;
    final count = _dayCount;
    final end = DateTime(start.year, start.month, start.day + count)
        .subtract(const Duration(milliseconds: 1));
    final list = await widget.db.getMonthBill(
        start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
    final cats = await widget.db.getCategories();
    if (!mounted) return;
    _bills = list;
    _days = [
      for (var i = 0; i < count; i++)
        DateTime(start.year, start.month, start.day + i)
    ];
    _iconOf = {
      for (final c in cats) '${c.type}:${c.name}': c.icon,
    };
    _recompute();
    setState(() => loading = false);
  }

  void _recompute() {
    final filtered = _bills.where((b) => b.type == statType).toList();
    final cat = <String, double>{};
    final daily = List<double>.filled(_days.length, 0);
    double total = 0;
    for (final b in filtered) {
      total += b.amount;
      cat[b.category] = (cat[b.category] ?? 0) + b.amount;
      final d = DateTime.fromMillisecondsSinceEpoch(b.timestamp);
      final idx =
          DateTime(d.year, d.month, d.day).difference(_days.first).inDays;
      if (idx >= 0 && idx < daily.length) daily[idx] += b.amount;
    }
    setState(() {
      _catSum = cat;
      _daily = daily;
      _total = total;
      _avg = _days.isEmpty ? 0 : total / _days.length;
    });
  }

  void _switchType(int t) {
    if (t == statType) return;
    setState(() => statType = t);
    _recompute();
  }

  void _switchPeriod(bool week) {
    if (week == isWeek) return;
    setState(() => isWeek = week);
    _load();
  }

  /// 是否正处于当前周/月（用于禁用「下一个」按钮，避免看未来）
  bool get _isCurrentPeriod {
    final now = DateTime.now();
    final s = _start;
    if (isWeek) {
      final nowMonday = now.subtract(Duration(days: now.weekday - 1));
      return s.year == nowMonday.year &&
          s.month == nowMonday.month &&
          s.day == nowMonday.day;
    }
    return s.year == now.year && s.month == now.month;
  }

  String get _periodLabel {
    final s = _start;
    if (isWeek) {
      final e = DateTime(s.year, s.month, s.day + 6);
      return '${s.month}/${s.day} - ${e.month}/${e.day}';
    }
    return '${s.year}年${s.month}月';
  }

  void _shift(int delta) {
    if (delta > 0 && _isCurrentPeriod) return;
    setState(() {
      if (isWeek) {
        _anchor = _anchor.add(Duration(days: 7 * delta));
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
      }
    });
    _load();
  }

  /// 点击周期文字弹出滚轮，快速定位到指定周 / 月
  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    if (isWeek) {
      final thisMonday = now.subtract(Duration(days: now.weekday - 1));
      const weekCount = 520; // 约十年
      final weeks = [
        for (var i = weekCount - 1; i >= 0; i--)
          DateTime(thisMonday.year, thisMonday.month, thisMonday.day - i * 7)
      ];
      final cur = _start;
      var sel = weeks.indexWhere(
          (w) => w.year == cur.year && w.month == cur.month && w.day == cur.day);
      if (sel < 0) sel = weeks.length - 1;
      var picked = sel;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
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
                      child: Text('选择周',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('确定')),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: _wheel(
                    count: weeks.length,
                    initial: sel,
                    label: (i) {
                      final w = weeks[i];
                      final e = DateTime(w.year, w.month, w.day + 6);
                      return '${w.month}/${w.day} - ${e.month}/${e.day}';
                    },
                    onChanged: (i) => picked = i,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (ok != true) return;
      setState(() => _anchor = weeks[picked]);
      _load();
    } else {
      final years = [for (var y = 2000; y <= now.year; y++) y];
      var selYear = _start.year;
      var selMonth = _start.month;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
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
                      child: Text('选择年月',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
                          initial: years.indexOf(selYear),
                          label: (i) => '${years[i]}年',
                          onChanged: (i) => selYear = years[i],
                        ),
                      ),
                      Expanded(
                        child: _wheel(
                          count: 12,
                          initial: selMonth - 1,
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
        ),
      );
      if (ok != true) return;
      setState(() => _anchor = DateTime(selYear, selMonth, 1));
      _load();
    }
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

  Color get _accent => statType == 0 ? Colors.red : Colors.green;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                    child: _seg('支出', statType == 0,
                        () => _switchType(0), Colors.red)),
                const SizedBox(width: 8),
                Expanded(
                    child: _seg('收入', statType == 1,
                        () => _switchType(1), Colors.green)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _period('周', isWeek, () => _switchPeriod(true))),
              Expanded(
                  child: _period('月', !isWeek, () => _switchPeriod(false))),
            ],
          ),
          // 周期导航：选择具体的周 / 月
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一${isWeek ? '周' : '月'}',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _pickPeriod,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _periodLabel,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一${isWeek ? '周' : '月'}',
                icon: const Icon(Icons.chevron_right),
                onPressed: _isCurrentPeriod ? null : () => _shift(1),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _lineChartCard(),
                      const SizedBox(height: 20),
                      _pieCard(),
                      const SizedBox(height: 20),
                      ..._ranking(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _period(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Colors.teal : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.teal : Colors.grey,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // ---------------- 折线图 ----------------

  Widget _lineChartCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '日${statType == 0 ? '支出' : '收入'}趋势',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            // 折线图右上角：当前周/月的收入/消费总和
            Text(
              '${statType == 0 ? '支出' : '收入'} ¥${fmtMoney(_total)}',
              style: TextStyle(
                  fontSize: 12,
                  color: _accent,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: _daily.isEmpty
              ? const Center(child: Text('暂无数据'))
              : LineChart(_lineData()),
        ),
      ],
    );
  }

  LineChartData _lineData() {
    final spots = [
      for (var i = 0; i < _daily.length; i++) FlSpot(i.toDouble(), _daily[i])
    ];
    final peak = _daily.fold<double>(0, (m, v) => v > m ? v : m);
    final maxY = (peak == 0 ? 10.0 : peak) * 1.25;
    // 左侧纵坐标只显示平均值：以平均值为刻度间隔，仅渲染均值那一个刻度
    final leftInterval = _avg > 0 ? _avg : maxY;
    return LineChartData(
      minX: 0,
      maxX: (_daily.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        // 去掉固定纵坐标，只在平均值位置显示均值
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            interval: leftInterval > 0 ? leftInterval : 1,
            getTitlesWidget: (v, meta) {
              if (_avg > 0 && (v - _avg).abs() < leftInterval * 0.01) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '均值\n${fmtMoney(_avg)}',
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(fontSize: 9, color: Colors.orange),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: isWeek,
            reservedSize: 26,
            interval: 1,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= _days.length) return const SizedBox.shrink();
              final d = _days[i];
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${d.month}/${d.day}',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: _avg,
            color: Colors.orange,
            strokeWidth: 1,
            dashArray: [6, 4],
          ),
        ],
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: _accent, // 折线与拐点同色
          barWidth: 2,
          // 数据点：有记录的实心（当前主题色），无记录的空心圈
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final hasData = spot.y > 0;
              return FlDotCirclePainter(
                radius: isWeek ? 3.5 : 2.5,
                color: hasData ? _accent : Colors.white,
                strokeWidth: hasData ? 0 : 1.5,
                strokeColor: hasData ? Colors.transparent : _accent,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _accent.withOpacity(0.10),
          ),
        ),
      ],
    );
  }

  // ---------------- 饼图（缩小） ----------------

  Widget _pieCard() {
    final entries = _catSum.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final half = (entries.length + 1) ~/ 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${statType == 0 ? '支出' : '收入'}分类占比',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const SizedBox(
            height: 100,
            child: Center(child: Text('暂无数据')),
          )
        else
          Row(
            children: [
              Expanded(child: _legend(entries, 0, half, true)),
              SizedBox(
                width: 150,
                height: 150,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 1,
                    centerSpaceRadius: 22,
                    sections: [
                      for (var i = 0; i < entries.length; i++)
                        PieChartSectionData(
                          value: entries[i].value,
                          title: '',
                          radius: 50,
                          color: _palette[i % _palette.length],
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _legend(entries, half, entries.length, false)),
            ],
          ),
      ],
    );
  }

  /// 饼图左右两侧的图例：色块 + 分类名（左列靠右、右列靠左，紧贴饼图）
  Widget _legend(List<MapEntry<String, double>> entries, int from, int to,
      bool alignRight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (var i = from; i < to; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _palette[i % _palette.length],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    entries[i].key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------- 分类排行（含进度条） ----------------

  Future<void> _openCategory(String cat, String iconKey) async {
    final start = _start;
    final end = DateTime(start.year, start.month, start.day + _dayCount)
        .subtract(const Duration(milliseconds: 1));
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CategoryDetailPage(
        db: widget.db,
        statType: statType,
        category: cat,
        iconKey: iconKey,
        startTs: start.millisecondsSinceEpoch,
        endTs: end.millisecondsSinceEpoch,
      ),
    ));
  }

  List<Widget> _ranking() {
    final entries = _catSum.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const [
        Text('暂无排行数据', style: TextStyle(color: Colors.grey)),
      ];
    }
    return [
      Text(
        '${statType == 0 ? '支出' : '收入'}排行',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      ...entries.asMap().entries.map((e) {
        final rank = e.key;
        final cat = e.value.key;
        final val = e.value.value;
        final pct = _total > 0 ? val / _total : 0.0;
        // 进度条以最高金额为基准
        final maxVal = entries.first.value;
        final ratio = maxVal > 0 ? val / maxVal : 0.0;
        final iconKey = _iconOf['$statType:$cat'] ?? 'other';
        final color = _palette[rank % _palette.length];
        return InkWell(
          onTap: () => _openCategory(cat, iconKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(iconOf(iconKey), size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(cat, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      '¥${fmtMoney(val)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${(pct * 100).toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ];
  }
}

Color _accentColor(int statType) => statType == 0 ? Colors.red : Colors.green;

String _dateStr(DateTime d) {
  const wd = ['一', '二', '三', '四', '五', '六', '日'];
  return '${d.year}年${d.month}月${d.day}日 周${wd[d.weekday - 1]}';
}

/// 细分类别统计页：某分类在该区间内的各笔记录排行
class CategoryDetailPage extends StatefulWidget {
  final DBHelper db;
  final int statType;
  final String category;
  final String iconKey;
  final int startTs;
  final int endTs;

  const CategoryDetailPage({
    super.key,
    required this.db,
    required this.statType,
    required this.category,
    required this.iconKey,
    required this.startTs,
    required this.endTs,
  });

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  bool loading = true;
  List<Bill> bills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.db.getMonthBill(widget.startTs, widget.endTs);
    final list = all
        .where((b) =>
            b.type == widget.statType && b.category == widget.category)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    if (!mounted) return;
    setState(() {
      bills = list;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = bills.fold<double>(0, (s, b) => s + b.amount);
    final maxAmt = bills.isEmpty ? 0.0 : bills.first.amount;
    final accent = _accentColor(widget.statType);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
            '${widget.statType == 0 ? '支出' : '收入'} · ${widget.category}'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : bills.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: bills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final b = bills[i];
                    final pct = total > 0 ? b.amount / total : 0.0;
                    // 进度条以最高金额为基准
                    final ratio = maxAmt > 0 ? b.amount / maxAmt : 0.0;
                    final d = DateTime.fromMillisecondsSinceEpoch(b.timestamp);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(iconOf(widget.iconKey),
                                  size: 20, color: accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.remark.isNotEmpty ? b.remark : '无备注',
                                      style: const TextStyle(fontSize: 15),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                        '${(pct * 100).toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('¥${fmtMoney(b.amount)}',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio.clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(_dateStr(d),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
