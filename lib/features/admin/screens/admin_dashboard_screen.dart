import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../shared/components/skeleton.dart';
import '../../household/providers/household_provider.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _range = 'daily';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HouseholdProvider>().loadAdminDashboard(range: _range);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final live = provider.adminLiveOps ?? {};
    final summary = Map<String, dynamic>.from(live['summary'] as Map? ?? {});
    final analytics = provider.adminAnalytics ?? {};
    final analyticsSummary =
        Map<String, dynamic>.from(analytics['summary'] as Map? ?? {});

    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => provider.loadAdminDashboard(range: _range),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Operations',
                            style: HouseholdType.hero.copyWith(fontSize: 30)),
                        const SizedBox(height: 8),
                        Text('Live operations, pricing, fleet, and analytics.',
                            style: HouseholdType.body
                                .copyWith(color: HouseholdColors.gray)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => provider.loadAdminDashboard(range: _range),
                    icon: HIcon('route', color: HouseholdColors.charcoal),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (provider.loadingAdmin)
                const SkeletonList(count: 5)
              else if (provider.adminError != null)
                HCard(
                  child: Column(
                    children: [
                      Text('Could not load admin dashboard',
                          style: HouseholdType.title),
                      const SizedBox(height: 8),
                      Text(provider.adminError!,
                          style: HouseholdType.body
                              .copyWith(color: HouseholdColors.gray),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              else ...[
                _SummaryGrid(summary: summary),
                const SizedBox(height: 18),
                _MapPanel(
                  collectors: List<Map<String, dynamic>>.from(
                      live['collectors'] as List? ?? []),
                  pickups: List<Map<String, dynamic>>.from(
                      live['pickups'] as List? ?? []),
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Collector Approvals',
                  action: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: provider.pendingCollectors.isEmpty
                          ? HouseholdColors.gray.withAlpha(40)
                          : HouseholdColors.warning,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${provider.pendingCollectors.length} pending',
                        style: HouseholdType.caption.copyWith(
                            color: provider.pendingCollectors.isEmpty
                                ? HouseholdColors.gray
                                : Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                ...(provider.pendingCollectors.isEmpty
                    ? [const HCard(child: Text('No collectors awaiting verification.'))]
                    : provider.pendingCollectors
                        .map((c) => _CollectorApprovalTile(collector: c))),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Pricing Engine',
                  action: FilledButton.icon(
                    onPressed: () => _openPricingDialog(context),
                    icon: const HIcon('payment', size: 18, color: Colors.white),
                    label: const Text('Add rule'),
                  ),
                ),
                const SizedBox(height: 12),
                ...(provider.pricingRules.isEmpty
                    ? [const HCard(child: Text('No pricing rules configured.'))]
                    : provider.pricingRules
                        .map((rule) => _PricingTile(rule: rule))),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Fleet Management',
                  action: FilledButton.icon(
                    onPressed: () => _openVehicleDialog(context),
                    icon: const HIcon('truck', size: 18, color: Colors.white),
                    label: const Text('Add vehicle'),
                  ),
                ),
                const SizedBox(height: 12),
                ...(provider.fleetVehicles.isEmpty
                    ? [const HCard(child: Text('No vehicles in fleet.'))]
                    : provider.fleetVehicles
                        .map((vehicle) => _VehicleTile(vehicle: vehicle))),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Promo Codes',
                  action: FilledButton.icon(
                    onPressed: () => _openPromoDialog(context),
                    icon: const Icon(Icons.local_offer_outlined, size: 18, color: Colors.white),
                    label: const Text('Add code'),
                  ),
                ),
                const SizedBox(height: 12),
                ...(provider.promos.isEmpty
                    ? [const HCard(child: Text('No promo codes yet.'))]
                    : provider.promos.map((p) => _PromoTile(promo: p))),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Analytics',
                  action: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'daily', label: Text('Daily')),
                      ButtonSegment(value: 'weekly', label: Text('Weekly')),
                      ButtonSegment(value: 'monthly', label: Text('Monthly')),
                    ],
                    selected: {_range},
                    onSelectionChanged: (values) {
                      final selected = values.first;
                      setState(() => _range = selected);
                      provider.loadAdminDashboard(range: selected);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                HCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Kpi(
                              label: 'Success rate',
                              value:
                                  '${(((analyticsSummary['successRate'] as num?) ?? 0) * 100).toStringAsFixed(1)}%'),
                          _Kpi(
                              label: 'Active collectors',
                              value:
                                  '${analyticsSummary['activeCollectors'] ?? 0}'),
                          _Kpi(
                              label: 'Average ETA',
                              value:
                                  '${((((analyticsSummary['averageEtaSec'] as num?) ?? 0) / 60)).toStringAsFixed(1)} min'),
                          _Kpi(
                              label: 'Carbon savings',
                              value:
                                  '${((analyticsSummary['carbonSavingsKg'] as num?) ?? 0).toStringAsFixed(0)} kg'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 220,
                        child: _RevenueChart(
                            series: List<Map<String, dynamic>>.from(
                                analytics['revenue'] as List? ?? [])),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPromoDialog(BuildContext context) async {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    String type = 'PERCENT';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d2, setLocal) => AlertDialog(
        backgroundColor: HouseholdColors.card,
        title: Text('New promo code', style: HouseholdType.title),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: codeCtrl, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Code (e.g. WELCOME10)')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PERCENT', label: Text('%')),
                ButtonSegment(value: 'FIXED', label: Text('GHS')),
              ],
              selected: {type},
              onSelectionChanged: (v) => setLocal(() => type = v.first),
            )),
          ]),
          const SizedBox(height: 10),
          TextField(controller: valueCtrl, keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: type == 'PERCENT' ? 'Percent off' : 'Amount off (GHS)')),
          const SizedBox(height: 10),
          TextField(controller: minCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum order (GHS, optional)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d2, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d2, true), child: const Text('Create')),
        ],
      )),
    );
    if (ok != true || !context.mounted) return;
    final created = await context.read<HouseholdProvider>().createPromoCode({
      'code': codeCtrl.text.trim(),
      'discountType': type,
      'discountValue': double.tryParse(valueCtrl.text.trim()) ?? 0,
      'minAmount': double.tryParse(minCtrl.text.trim()) ?? 0,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(created ? 'Promo code created' : 'Could not create code')));
    }
  }

  Future<void> _openPricingDialog(BuildContext context,
      {Map<String, dynamic>? existing}) async {
    final provider = context.read<HouseholdProvider>();
    final name =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final wasteType =
        TextEditingController(text: existing?['wasteType']?.toString() ?? '');
    final binSize =
        TextEditingController(text: existing?['binSize']?.toString() ?? '');
    final baseFee =
        TextEditingController(text: existing?['baseFee']?.toString() ?? '0');
    final distanceFee = TextEditingController(
        text: existing?['distanceFeePerKm']?.toString() ?? '0');
    final weightFee = TextEditingController(
        text: existing?['weightFeePerKg']?.toString() ?? '0');
    final wasteFee = TextEditingController(
        text: existing?['wasteTypeFee']?.toString() ?? '0');
    final surge = TextEditingController(
        text: existing?['surgeMultiplier']?.toString() ?? '1');
    bool isActive = existing?['isActive'] as bool? ?? true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: HCard(
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    existing == null ? 'New pricing rule' : 'Edit pricing rule',
                    style: HouseholdType.title),
                const SizedBox(height: 16),
                HTextField(controller: name, label: 'Name'),
                const SizedBox(height: 10),
                HTextField(
                    controller: wasteType,
                    label: 'Waste type',
                    hint: 'Optional'),
                const SizedBox(height: 10),
                HTextField(
                    controller: binSize, label: 'Bin size', hint: 'Optional'),
                const SizedBox(height: 10),
                HTextField(controller: baseFee, label: 'Base fee'),
                const SizedBox(height: 10),
                HTextField(controller: distanceFee, label: 'Distance fee / km'),
                const SizedBox(height: 10),
                HTextField(controller: weightFee, label: 'Weight fee / kg'),
                const SizedBox(height: 10),
                HTextField(controller: wasteFee, label: 'Waste type fee'),
                const SizedBox(height: 10),
                HTextField(controller: surge, label: 'Surge multiplier'),
                SwitchListTile(
                  value: isActive,
                  onChanged: (value) => setSheetState(() => isActive = value),
                  title: Text('Active', style: HouseholdType.body),
                ),
                HButton(
                  label: 'Save rule',
                  icon: 'payment',
                  onPressed: () async {
                    final ok = await provider.savePricingRule({
                      'name': name.text.trim(),
                      'wasteType': wasteType.text.trim().isEmpty
                          ? null
                          : wasteType.text.trim(),
                      'binSize': binSize.text.trim().isEmpty
                          ? null
                          : binSize.text.trim(),
                      'baseFee': baseFee.text.trim(),
                      'distanceFeePerKm': distanceFee.text.trim(),
                      'weightFeePerKg': weightFee.text.trim(),
                      'wasteTypeFee': wasteFee.text.trim(),
                      'surgeMultiplier': surge.text.trim(),
                      'isActive': isActive,
                    }, id: existing?['id']?.toString());
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openVehicleDialog(BuildContext context,
      {Map<String, dynamic>? existing}) async {
    final provider = context.read<HouseholdProvider>();
    final plate =
        TextEditingController(text: existing?['plateNumber']?.toString() ?? '');
    final type = TextEditingController(
        text: existing?['vehicleType']?.toString() ?? 'TRUCK');
    final make =
        TextEditingController(text: existing?['make']?.toString() ?? '');
    final model =
        TextEditingController(text: existing?['model']?.toString() ?? '');
    final year = TextEditingController(
        text: existing?['year']?.toString() ?? DateTime.now().year.toString());
    final maxCapacity = TextEditingController(
        text: existing?['maxCapacityKg']?.toString() ?? '500');
    final currentLoad = TextEditingController(
        text: existing?['currentLoadKg']?.toString() ?? '0');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: HCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(existing == null ? 'New vehicle' : 'Edit vehicle',
                  style: HouseholdType.title),
              const SizedBox(height: 16),
              HTextField(controller: plate, label: 'Plate number'),
              const SizedBox(height: 10),
              HTextField(controller: type, label: 'Vehicle type'),
              const SizedBox(height: 10),
              HTextField(controller: make, label: 'Make'),
              const SizedBox(height: 10),
              HTextField(controller: model, label: 'Model'),
              const SizedBox(height: 10),
              HTextField(controller: year, label: 'Year'),
              const SizedBox(height: 10),
              HTextField(controller: maxCapacity, label: 'Capacity kg'),
              const SizedBox(height: 10),
              HTextField(controller: currentLoad, label: 'Current load kg'),
              const SizedBox(height: 16),
              HButton(
                label: 'Save vehicle',
                icon: 'truck',
                onPressed: () async {
                  final ok = await provider.saveVehicle({
                    'plateNumber': plate.text.trim(),
                    'vehicleType': type.text.trim(),
                    'make': make.text.trim(),
                    'model': model.text.trim(),
                    'year': year.text.trim(),
                    'maxCapacityKg': maxCapacity.text.trim(),
                    'currentLoadKg': currentLoad.text.trim(),
                  }, id: existing?['id']?.toString());
                  if (ok && context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Active pickups', '${summary['activePickups'] ?? 0}'),
      ('Searching', '${summary['searchingPickups'] ?? 0}'),
      ('Assigned', '${summary['assignedPickups'] ?? 0}'),
      ('Completed', '${summary['completedPickups'] ?? 0}'),
      ('Online collectors', '${summary['onlineCollectors'] ?? 0}'),
      ('Offline collectors', '${summary['offlineCollectors'] ?? 0}'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, index) => HCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(items[index].$1, style: HouseholdType.caption),
            const Spacer(),
            Text(items[index].$2,
                style: HouseholdType.hero.copyWith(fontSize: 28)),
          ],
        ),
      ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.collectors, required this.pickups});
  final List<Map<String, dynamic>> collectors;
  final List<Map<String, dynamic>> pickups;

  @override
  Widget build(BuildContext context) {
    return HCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Operations Map', style: HouseholdType.section),
          const SizedBox(height: 8),
          Text('Collector and pickup coordinates with status colors.',
              style: HouseholdType.caption),
          const SizedBox(height: 14),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: HouseholdColors.charcoal,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OpsMapPainter(
                        collectors: collectors, pickups: pickups),
                  ),
                ),
                const Positioned(
                  left: 14,
                  top: 14,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LegendDot(color: Colors.green, label: 'Online'),
                      _LegendDot(color: Colors.orange, label: 'Searching'),
                      _LegendDot(color: Colors.blue, label: 'Assigned'),
                      _LegendDot(color: Colors.red, label: 'Active'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(24),
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: HouseholdType.caption.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

class _OpsMapPainter extends CustomPainter {
  _OpsMapPainter({required this.collectors, required this.pickups});
  final List<Map<String, dynamic>> collectors;
  final List<Map<String, dynamic>> pickups;

  @override
  void paint(Canvas canvas, Size size) {
    final allPoints = [
      ...collectors.map((c) => Offset((c['lastLng'] as num?)?.toDouble() ?? 0,
          (c['lastLat'] as num?)?.toDouble() ?? 0)),
      ...pickups.map((p) => Offset((p['pickupLng'] as num?)?.toDouble() ?? 0,
          (p['pickupLat'] as num?)?.toDouble() ?? 0)),
    ].where((p) => p.dx != 0 || p.dy != 0).toList();
    if (allPoints.isEmpty) return;

    final minX = allPoints.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
    final maxX = allPoints.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
    final minY = allPoints.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final maxY = allPoints.map((p) => p.dy).reduce((a, b) => a > b ? a : b);

    Offset mapPoint(double x, double y) {
      final width = (maxX - minX).abs() < 0.0001 ? 1.0 : maxX - minX;
      final height = (maxY - minY).abs() < 0.0001 ? 1.0 : maxY - minY;
      final dx = ((x - minX) / width) * (size.width - 40) + 20;
      final dy =
          size.height - ((((y - minY) / height) * (size.height - 40)) + 20);
      return Offset(dx, dy);
    }

    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final pickup in pickups) {
      final point = mapPoint((pickup['pickupLng'] as num?)?.toDouble() ?? 0,
          (pickup['pickupLat'] as num?)?.toDouble() ?? 0);
      final status = pickup['status']?.toString() ?? 'SEARCHING';
      final color = switch (status) {
        'SEARCHING' => HouseholdColors.warning,
        'ASSIGNED' => HouseholdColors.blue,
        'UNASSIGNED' => HouseholdColors.gray,
        _ => HouseholdColors.danger,
      };
      canvas.drawCircle(point, 7, Paint()..color = color);
    }

    for (final collector in collectors) {
      final point = mapPoint((collector['lastLng'] as num?)?.toDouble() ?? 0,
          (collector['lastLat'] as num?)?.toDouble() ?? 0);
      final isOnline = collector['isOnline'] == true;
      canvas.drawCircle(
          point,
          9,
          Paint()
            ..color =
                isOnline ? HouseholdColors.ecoGreen : HouseholdColors.gray);
      canvas.drawCircle(point, 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _OpsMapPainter oldDelegate) =>
      oldDelegate.collectors != collectors || oldDelegate.pickups != pickups;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});
  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child:
                Text(title, style: HouseholdType.title.copyWith(fontSize: 22))),
        const SizedBox(width: 12),
        Flexible(child: action),
      ],
    );
  }
}

class _PricingTile extends StatelessWidget {
  const _PricingTile({required this.rule});
  final Map<String, dynamic> rule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule['name']?.toString() ?? 'Pricing rule',
                      style: HouseholdType.section),
                  const SizedBox(height: 6),
                  Text(
                      'Base ${rule['baseFee']} • Distance ${rule['distanceFeePerKm']} • Weight ${rule['weightFeePerKg']} • Surge x${rule['surgeMultiplier']}',
                      style: HouseholdType.caption),
                ],
              ),
            ),
            Switch(
                value: rule['isActive'] == true,
                onChanged: (value) => context
                    .read<HouseholdProvider>()
                    .savePricingRule({'isActive': value},
                        id: rule['id'].toString())),
            IconButton(
              onPressed: () => context
                  .read<HouseholdProvider>()
                  .deletePricingRule(rule['id'].toString()),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.vehicle});
  final Map<String, dynamic> vehicle;

  @override
  Widget build(BuildContext context) {
    final maintenance = List<Map<String, dynamic>>.from(
        vehicle['maintenanceLogs'] as List? ?? []);
    final capacityLogs =
        List<Map<String, dynamic>>.from(vehicle['capacityLogs'] as List? ?? []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(
                        '${vehicle['plateNumber']} • ${vehicle['vehicleType']}',
                        style: HouseholdType.section)),
                Text(vehicle['status']?.toString() ?? 'ACTIVE',
                    style: HouseholdType.caption
                        .copyWith(color: HouseholdColors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Capacity ${vehicle['currentLoadKg']} / ${vehicle['maxCapacityKg']} kg',
                style: HouseholdType.body),
            const SizedBox(height: 10),
            if (maintenance.isNotEmpty)
              Text(
                  'Maintenance: ${maintenance.first['description']} (${maintenance.first['status']})',
                  style: HouseholdType.caption),
            if (capacityLogs.isNotEmpty)
              Text('Latest load event: ${capacityLogs.first['totalLoadKg']} kg',
                  style: HouseholdType.caption),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HouseholdColors.sand,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HouseholdType.caption),
          const SizedBox(height: 8),
          Text(value, style: HouseholdType.title),
        ],
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.series});
  final List<Map<String, dynamic>> series;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return Center(
          child: Text('No analytics data yet.', style: HouseholdType.body));
    }
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= series.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(series[index]['label']?.toString() ?? '',
                      style: HouseholdType.caption),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: HouseholdColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            spots: [
              for (var i = 0; i < series.length; i++)
                FlSpot(i.toDouble(),
                    ((series[i]['value'] as num?) ?? 0).toDouble()),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Collector verification approval tile ──────────────────────────────────────
class _CollectorApprovalTile extends StatelessWidget {
  const _CollectorApprovalTile({required this.collector});
  final Map<String, dynamic> collector;

  @override
  Widget build(BuildContext context) {
    final name = collector['fullName'] as String? ?? 'Collector';
    final contact = (collector['email'] as String?) ?? (collector['phone'] as String?) ?? '';
    final kyc = collector['kyc'] as Map<String, dynamic>?;
    final docs = <String, String?>{
      'Ghana Card': kyc?['ghanaCardUrl'] as String?,
      'License': kyc?['licenseUrl'] as String?,
      'Vehicle': kyc?['vehiclePhotoUrl'] as String?,
    };
    final hasDocs = docs.values.any((v) => v != null && v.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            HIcon('profile', color: HouseholdColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: HouseholdType.section),
              if (contact.isNotEmpty) Text(contact, style: HouseholdType.caption),
              if (kyc?['ghanaCardNumber'] != null)
                Text('Ghana Card: ${kyc!['ghanaCardNumber']}', style: HouseholdType.caption),
              if (kyc?['licenseNumber'] != null)
                Text('License: ${kyc!['licenseNumber']}', style: HouseholdType.caption),
            ])),
          ]),
          if (hasDocs) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 78,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final entry in docs.entries)
                  if (entry.value != null && entry.value!.isNotEmpty)
                    GestureDetector(
                      onTap: () => _viewDoc(context, entry.key, entry.value!),
                      child: Container(
                        width: 78,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E0D8)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(entry.value!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(child: HIcon('security', size: 18))),
                      ),
                    ),
              ]),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('No documents uploaded yet.', style: HouseholdType.caption.copyWith(color: HouseholdColors.warning)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _reject(context, collector['id'] as String),
              style: OutlinedButton.styleFrom(foregroundColor: HouseholdColors.danger,
                  side: BorderSide(color: HouseholdColors.danger)),
              child: const Text('Reject'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(
              onPressed: () => _approve(context, collector['id'] as String),
              style: FilledButton.styleFrom(backgroundColor: HouseholdColors.ecoGreen),
              child: const Text('Approve'),
            )),
          ]),
        ]),
      ),
    );
  }

  void _viewDoc(BuildContext context, String label, String url) {
    showDialog<void>(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(label,
            style: HouseholdType.section.copyWith(color: Colors.white))),
        Flexible(child: InteractiveViewer(child: Image.network(url,
            errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(40), child: Text('Could not load image',
                    style: TextStyle(color: Colors.white)))))),
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white))),
      ]),
    ));
  }

  Future<void> _approve(BuildContext context, String id) async {
    final ok = await context.read<HouseholdProvider>().reviewCollector(id, 'approve');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Collector approved' : 'Could not approve')));
    }
  }

  Future<void> _reject(BuildContext context, String id) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      title: Text('Reject collector', style: HouseholdType.title),
      content: TextField(controller: ctrl, decoration: const InputDecoration(
          hintText: 'Reason (shown to the collector)'), maxLines: 2),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: HouseholdColors.danger),
          onPressed: () => Navigator.pop(d, ctrl.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    ));
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<HouseholdProvider>().reviewCollector(id, 'reject', reason: reason);
    messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Collector rejected' : 'Could not reject')));
  }
}

// ── Promo code tile ───────────────────────────────────────────────────────────
class _PromoTile extends StatelessWidget {
  const _PromoTile({required this.promo});
  final Map<String, dynamic> promo;

  @override
  Widget build(BuildContext context) {
    final type = promo['discountType'] as String? ?? 'PERCENT';
    final value = (promo['discountValue'] as num?)?.toDouble() ?? 0;
    final label = type == 'PERCENT' ? '${value.toStringAsFixed(0)}% off' : 'GHS ${value.toStringAsFixed(2)} off';
    final used = (promo['_count']?['redemptions'] as num?)?.toInt() ?? 0;
    final active = promo['isActive'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(children: [
          Icon(Icons.local_offer, color: HouseholdColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(promo['code'] as String? ?? '', style: HouseholdType.section.copyWith(letterSpacing: 2)),
            Text('$label · used $used×', style: HouseholdType.caption),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (active ? HouseholdColors.ecoGreen : HouseholdColors.gray).withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(active ? 'Active' : 'Off', style: HouseholdType.caption.copyWith(
                color: active ? HouseholdColors.ecoGreen : HouseholdColors.gray, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}
