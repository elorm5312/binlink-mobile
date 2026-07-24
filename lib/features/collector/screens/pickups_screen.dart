import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/utils/formatters.dart';
import '../providers/collector_provider.dart';
import 'active_pickup_screen.dart';

class PickupsScreen extends StatefulWidget {
  const PickupsScreen({super.key});
  @override
  State<PickupsScreen> createState() => _PickupsScreenState();
}

class _PickupsScreenState extends State<PickupsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<CollectorProvider>().loadJobs());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CollectorProvider>();
    final jobs = [...p.assignedJobs, ...p.pendingJobs, ...p.completedJobs];
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => p.loadJobs(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
          children: [
            Text('Jobs', style: CollectorType.hero),
            const SizedBox(height: 8),
            Text('Incoming, assigned, active route, before photo, after photo, weight capture, and completion work.', style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
            const SizedBox(height: 20),
            if (jobs.isEmpty)
              CPanel(child: Column(children: [
                SvgPicture.asset(CollectorAssets.noJobs, height: 210),
                Text('No jobs available', style: CollectorType.title),
                const SizedBox(height: 8),
                Text('Go online from the map to receive new requests.', textAlign: TextAlign.center, style: CollectorType.caption),
              ]))
            else
              ...jobs.map((j) => _JobCard(job: j)),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String? ?? 'PENDING';
    final active = ['ASSIGNED', 'ACCEPTED', 'EN_ROUTE', 'ON_THE_WAY', 'ARRIVED', 'COLLECTING', 'COLLECTED'].contains(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CIcon('jobs', color: CollectorColors.green),
            const SizedBox(width: 12),
            Expanded(child: Text(job['pickupAddress'] as String? ?? 'Pickup address', maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectorType.section)),
            Text(Fmt.currency(Fmt.toDouble(job['totalAmount']) * .9), style: CollectorType.caption.copyWith(color: CollectorColors.green, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          Text(status.replaceAll('_', ' '), style: CollectorType.caption.copyWith(color: active ? CollectorColors.green : const Color(0xFFC8D0DA))),
          const SizedBox(height: 14),
          CButton(
            label: active ? 'OPEN ACTIVE ROUTE' : 'VIEW JOB DETAILS',
            icon: active ? 'navigation' : 'jobs',
            secondary: !active,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActivePickupScreen(booking: job))),
          ),
        ]),
      ),
    );
  }
}
