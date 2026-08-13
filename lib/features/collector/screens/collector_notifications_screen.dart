import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/design_system/theme_provider.dart';
import '../../../core/l10n/strings.dart';
import 'collector_assistant_screen.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/components/binlink_avatar.dart';
import '../../../shared/components/skeleton.dart';
import '../../../shared/models/app_notification.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/collector_provider.dart';

class CollectorNotificationsScreen extends StatefulWidget {
  const CollectorNotificationsScreen({super.key});
  @override
  State<CollectorNotificationsScreen> createState() => _CollectorNotificationsScreenState();
}

class _CollectorNotificationsScreenState extends State<CollectorNotificationsScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Future.wait([
        context.read<CollectorProvider>().loadNotifications(),
        context.read<AuthProvider>().refreshProfile(),
      ]);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load notifications.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CollectorProvider>();
    final user = context.watch<AuthProvider>().user;
    final items = p.notifications;
    final count = items.length;
    final grouped = _groupNotifications(items);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
          children: [
            Text('Notifications', style: CollectorType.hero),
            const SizedBox(height: 8),
            Text('New jobs, truck capacity, fuel, maintenance, reviews, ratings, and payout updates.', style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
            const SizedBox(height: 16),
            if (p.unreadNotifications > 0) ...[
              CPanel(
                child: Row(children: [
                  CIcon('notifications', color: CollectorColors.warning),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${p.unreadNotifications} unread alerts', style: CollectorType.section)),
                  CButton(label: 'Mark all read', icon: 'history', secondary: true, onPressed: p.markAllNotificationsRead),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            CPanel(
              child: Row(children: [
                BinLinkAvatar(
                  name: user?.fullName,
                  imagePath: user?.profilePhoto,
                  fallbackAsset: 'assets/collector_assets/avatars/default_avatar.svg',
                  size: 80,
                  dark: true,
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.fullName ?? 'BinLink collector', style: CollectorType.title),
                  const SizedBox(height: 4),
                  Text(user?.vehiclePlate ?? 'Vehicle pending', style: CollectorType.caption),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const SkeletonList(count: 4, dark: true)
            else if (_error != null)
              _CollectorStateCard(title: 'Notifications unavailable', copy: _error!, asset: 'assets/collector_assets/errors/server_error.svg', onRetry: _load)
            else if (count == 0)
              _CollectorStateCard(title: 'No notifications yet', copy: 'New jobs, payouts, and reviews will appear here.', asset: 'assets/collector_assets/empty_states/no_notifications.svg', onRetry: _load)
            else ...[
              _SummaryCard(count: count, online: p.unreadNotifications == 0),
              const SizedBox(height: 16),
              ...grouped.entries.expand((entry) => [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(entry.key, style: CollectorType.section),
                    ),
                    ...entry.value.map((notification) => _CollectorNotificationItem(
                          notification: notification,
                          onTap: () => _openNotification(notification),
                        )),
                    const SizedBox(height: 8),
                  ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead) {
      await context.read<CollectorProvider>().markNotificationRead(notification.id);
    }
    if (!mounted) return;
    Navigator.pushNamed(context, _routeForNotification(notification));
  }

  String _routeForNotification(AppNotification notification) {
    final type = notification.type.toUpperCase();
    if (type.contains('PAYMENT')) return '/collector-wallet';
    if (type.contains('BOOKING_UPDATE')) return '/collector';
    if (type.contains('PICKUP_ASSIGNED')) return '/collector-jobs';
    if (type.contains('PICKUP_COMPLETED')) return '/collector-jobs';
    if (type.contains('SUPPORT')) return '/collector-support';
    return '/collector';
  }

  Map<String, List<AppNotification>> _groupNotifications(List<AppNotification> items) {
    final grouped = <String, List<AppNotification>>{};
    for (final item in items) {
      final key = _groupLabel(item.createdAt);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  String _groupLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(value.year, value.month, value.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

class CollectorHelpScreen extends CollectorSupportScreen {
  const CollectorHelpScreen({super.key});
}

class CollectorSupportScreen extends StatefulWidget {
  const CollectorSupportScreen({super.key});
  @override
  State<CollectorSupportScreen> createState() => _CollectorSupportScreenState();
}

class _CollectorSupportScreenState extends State<CollectorSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _bookingId = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _bookingId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await ApiClient.post('/api/support/tickets', {
        'role': 'COLLECTOR',
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        'bookingId': _bookingId.text.trim().isEmpty ? null : _bookingId.text.trim(),
        'name': auth.user?.fullName,
        'phone': auth.user?.phone,
      });
      if (mounted) setState(() => _success = 'Support request submitted.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit support request.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: 'Support',
      copy: 'Operational help for routes, pickup proof, weight capture, payouts, and vehicle status.',
      asset: 'assets/collector_assets/workflow/maintenance.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Form(
        key: _formKey,
        child: Column(children: [
          // Instant self-serve help before filing a ticket.
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CollectorAssistantScreen(
                  onContactHuman: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            child: CPanel(
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: CollectorColors.green.withAlpha(40),
                  child: Icon(PhosphorIcons.robot(), color: CollectorColors.green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ask the assistant', style: CollectorType.section),
                  Text('Instant answers on jobs, payouts, verification & more', style: CollectorType.caption),
                ])),
                Icon(PhosphorIcons.caretRight(), color: CollectorColors.gray),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          CPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contact dispatch', style: CollectorType.section),
              const SizedBox(height: 12),
              CTextField(controller: _subject, label: 'Subject', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a subject' : null),
              const SizedBox(height: 12),
              CTextField(controller: _bookingId, label: 'Booking id (optional)', hint: 'If this is about a job'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                minLines: 5,
                maxLines: 8,
                validator: (v) => (v == null || v.trim().length < 10) ? 'Enter a message' : null,
                decoration: InputDecoration(
                  labelText: 'Message',
                  filled: true,
                  fillColor: CollectorColors.charcoal,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          CButton(label: 'Submit request', icon: 'support', loading: _loading, onPressed: _submit),
        ]),
      ),
    );
  }
}

class CollectorPrivacyScreen extends StatefulWidget {
  const CollectorPrivacyScreen({super.key});
  @override
  State<CollectorPrivacyScreen> createState() => _CollectorPrivacyScreenState();
}

class _CollectorPrivacyScreenState extends State<CollectorPrivacyScreen> {
  bool _loading = true;
  bool _shareLocation = true;
  bool _shareRatings = false;
  bool _shareEarnings = false;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shareLocation = prefs.getBool('collector_share_location') ?? true;
      _shareRatings = prefs.getBool('collector_share_ratings') ?? false;
      _shareEarnings = prefs.getBool('collector_share_earnings') ?? false;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('collector_share_location', _shareLocation);
    await prefs.setBool('collector_share_ratings', _shareRatings);
    await prefs.setBool('collector_share_earnings', _shareEarnings);
    if (mounted) setState(() => _success = 'Privacy preferences saved.');
  }

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: 'Privacy',
      copy: 'Location sharing, profile data, job records, payout data, and account security.',
      asset: 'assets/collector_assets/errors/location_permission.svg',
      loading: _loading,
      success: _success,
      child: Column(children: [
        CPanel(
          child: Column(children: [
            SwitchListTile(
              value: _shareLocation,
              onChanged: (v) => setState(() => _shareLocation = v),
              title: Text('Share live location', style: CollectorType.section),
            ),
            SwitchListTile(
              value: _shareRatings,
              onChanged: (v) => setState(() => _shareRatings = v),
              title: Text('Share rating summary', style: CollectorType.section),
            ),
            SwitchListTile(
              value: _shareEarnings,
              onChanged: (v) => setState(() => _shareEarnings = v),
              title: Text('Share earnings summary', style: CollectorType.section),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        CButton(label: 'Save privacy settings', icon: 'privacy', onPressed: _save),
      ]),
    );
  }
}

class CollectorEditProfileScreen extends StatefulWidget {
  const CollectorEditProfileScreen({super.key});
  @override
  State<CollectorEditProfileScreen> createState() => _CollectorEditProfileScreenState();
}

class _CollectorEditProfileScreenState extends State<CollectorEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _vehiclePlate = TextEditingController();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _saving = false;
  String? _avatarPath;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehiclePlate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.refreshProfile();
      final user = auth.user;
      _name.text = user?.fullName ?? '';
      _phone.text = user?.phone ?? '';
      _vehiclePlate.text = user?.vehiclePlate ?? '';
      _avatarPath = user?.profilePhoto;
    } catch (_) {
      _error = 'Could not load collector profile.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (image != null && mounted) setState(() => _avatarPath = image.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final updated = user?.copyWith(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      vehiclePlate: _vehiclePlate.text.trim(),
      profilePhoto: _avatarPath,
    );
    try {
      await ApiClient.patch('/api/profile', {
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'vehiclePlate': _vehiclePlate.text.trim(),
        if (_avatarPath != null) 'profilePhoto': _avatarPath,
      });
      await auth.refreshProfile();
      if (updated != null) auth.updateUser(updated);
      if (mounted) setState(() => _success = 'Profile updated.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save collector profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return _CollectorFormScreen(
      title: 'Profile settings',
      copy: 'Edit collector profile, language, online preferences, and emergency contact.',
      asset: 'assets/collector_assets/avatars/default_avatar.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Form(
        key: _formKey,
        child: Column(children: [
          CPanel(
            child: Column(children: [
              BinLinkAvatar(
                name: user?.fullName,
                imagePath: _avatarPath,
                fallbackAsset: 'assets/collector_assets/avatars/default_avatar.svg',
                size: 92,
                dark: true,
              ),
              const SizedBox(height: 12),
              CButton(label: 'Change photo', icon: 'camera', secondary: true, onPressed: _pickAvatar),
              const SizedBox(height: 16),
              CTextField(controller: _name, label: 'Full name', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a name' : null),
              const SizedBox(height: 12),
              CTextField(controller: _phone, label: 'Phone number', keyboardType: TextInputType.phone, validator: (v) => (v == null || v.trim().length < 8) ? 'Enter a phone number' : null),
              const SizedBox(height: 12),
              CTextField(controller: _vehiclePlate, label: 'Vehicle plate', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a plate number' : null),
            ]),
          ),
          const SizedBox(height: 12),
          CButton(label: 'Save profile', icon: 'profile', loading: _saving, onPressed: _save),
        ]),
      ),
    );
  }
}

class VehicleDetailsScreen extends StatefulWidget {
  const VehicleDetailsScreen({super.key});
  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleType = TextEditingController();
  final _vehiclePlate = TextEditingController();
  final _capacity = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _vehicleType.dispose();
    _vehiclePlate.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.refreshProfile();
      final user = auth.user;
      _vehicleType.text = user?.vehicleType ?? '';
      _vehiclePlate.text = user?.vehiclePlate ?? '';
      _capacity.text = (user?.maxCapacityKg ?? 500).toStringAsFixed(0);
    } catch (_) {
      _error = 'Could not load vehicle details.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final capacity = user?.maxCapacityKg ?? 500;
    final updated = user?.copyWith(
      vehicleType: _vehicleType.text.trim(),
      vehiclePlate: _vehiclePlate.text.trim(),
      maxCapacityKg: double.tryParse(_capacity.text.trim()) ?? capacity,
    );
    try {
      await ApiClient.patch('/api/profile', {
        'vehicleType': _vehicleType.text.trim(),
        'vehiclePlate': _vehiclePlate.text.trim(),
        'maxCapacityKg': double.tryParse(_capacity.text.trim()),
      });
      await auth.refreshProfile();
      if (updated != null) auth.updateUser(updated);
      if (mounted) setState(() => _success = 'Vehicle details saved.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save vehicle details.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: 'Vehicle',
      copy: 'Truck type, capacity, fuel, maintenance, documents, and landfill access.',
      asset: 'assets/collector_assets/icons/fleet/fleet_dump_truck.png',
      loading: _loading,
      error: _error,
      success: _success,
      child: Form(
        key: _formKey,
        child: Column(children: [
          CPanel(
            child: Column(children: [
              Image.asset('assets/collector_assets/icons/fleet/fleet_dump_truck.png', height: 160),
              const SizedBox(height: 16),
              CTextField(controller: _vehicleType, label: 'Vehicle type', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter vehicle type' : null),
              const SizedBox(height: 12),
              CTextField(controller: _vehiclePlate, label: 'Vehicle plate', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter plate number' : null),
              const SizedBox(height: 12),
              CTextField(controller: _capacity, label: 'Capacity kg', keyboardType: TextInputType.number, validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a valid capacity' : null),
            ]),
          ),
          const SizedBox(height: 12),
          CButton(label: 'Save vehicle', icon: 'truck', loading: _saving, onPressed: _save),
        ]),
      ),
    );
  }
}

class CollectorReviewsScreen extends StatefulWidget {
  const CollectorReviewsScreen({super.key});
  @override
  State<CollectorReviewsScreen> createState() => _CollectorReviewsScreenState();
}

class _CollectorReviewsScreenState extends State<CollectorReviewsScreen> {
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  List<Map<String, dynamic>> _reviews = [];
  double _average = 0;
  int _totalReviews = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = context.read<AuthProvider>().user;
      final collectorId = user?.id;
      if (collectorId == null) throw Exception('Collector profile missing');
      final res = await ApiClient.get('/api/collectors/$collectorId/reviews', params: {'page': _page, 'limit': 10});
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      final stats = Map<String, dynamic>.from(data['stats'] as Map? ?? {});
      final pagination = Map<String, dynamic>.from(data['pagination'] as Map? ?? {});
      _reviews = List<Map<String, dynamic>>.from(data['reviews'] as List? ?? []);
      _average = Fmt.toDouble(stats['averageRating']);
      _totalReviews = (stats['totalReviews'] as num?)?.toInt() ?? 0;
      _totalPages = (pagination['pages'] as num?)?.toInt() ?? 1;
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load reviews.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: 'Reviews',
      copy: 'Customer review history from completed pickups.',
      asset: 'assets/collector_assets/workflow/reviews.svg',
      loading: _loading,
      error: _error,
      child: Column(children: [
        if (_reviews.isEmpty)
          _CollectorStateCard(
            title: 'No reviews yet',
            copy: 'Completed pickups with customer ratings or comments will appear here.',
            asset: 'assets/collector_assets/empty_states/no_reviews.svg',
            onRetry: _load,
          )
        else ...[
          CPanel(
            child: Row(
              children: [
                CIcon('star', color: CollectorColors.warning, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_average == 0 ? '--' : _average.toStringAsFixed(1), style: CollectorType.title),
                      const SizedBox(height: 4),
                      Text('$_totalReviews reviews', style: CollectorType.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._reviews.map((b) {
            final rating = Fmt.toDouble(b['rating']);
            final review = b['comment']?.toString();
            final household = (b['household'] as Map<String, dynamic>?)?['fullName'] as String?;
            final booking = b['booking'] as Map<String, dynamic>?;
            final images = [
              booking?['wastePhotoUrl'] as String?,
              booking?['beforePhotoUrl'] as String?,
              booking?['afterPhotoUrl'] as String?,
            ].whereType<String>().where((url) => url.isNotEmpty).toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CIcon('reviews', color: CollectorColors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            household ?? 'Customer review',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CollectorType.section,
                          ),
                          Text(
                            Fmt.relativeTime(
                              DateTime.tryParse(b['createdAt'] as String? ?? booking?['completedAt'] as String? ?? '') ?? DateTime.now(),
                            ),
                            style: CollectorType.caption,
                          ),
                        ]),
                      ),
                      Text(rating > 0 ? rating.toStringAsFixed(1) : '--', style: CollectorType.section),
                    ]),
                    if (review != null) ...[
                      const SizedBox(height: 12),
                      Text(review, style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
                    ],
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(images[index], width: 72, height: 64, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (_totalPages > 1) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CButton(
                    label: 'Previous',
                    icon: 'history',
                    secondary: true,
                    onPressed: _page > 1 ? () { setState(() => _page -= 1); _load(); } : null,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Page $_page of $_totalPages', style: CollectorType.caption),
                const SizedBox(width: 12),
                Expanded(
                  child: CButton(
                    label: 'Next',
                    icon: 'route',
                    onPressed: _page < _totalPages ? () { setState(() => _page += 1); _load(); } : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ]),
    );
  }
}

class CollectorRatingsScreen extends StatefulWidget {
  const CollectorRatingsScreen({super.key});
  @override
  State<CollectorRatingsScreen> createState() => _CollectorRatingsScreenState();
}

class _CollectorRatingsScreenState extends State<CollectorRatingsScreen> {
  bool _loading = true;
  String? _error;
  double _average = 0;
  int _totalReviews = 0;
  Map<int, int> _breakdown = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = context.read<AuthProvider>().user;
      final collectorId = user?.id;
      if (collectorId == null) throw Exception('Collector profile missing');
      final res = await ApiClient.get('/api/collectors/$collectorId/reviews', params: {'page': 1, 'limit': 50});
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      final stats = Map<String, dynamic>.from(data['stats'] as Map? ?? {});
      final reviews = List<Map<String, dynamic>>.from(data['reviews'] as List? ?? []);
      final ratings = reviews.map((item) => Fmt.toDouble(item['rating'])).where((value) => value > 0).toList();
      _average = Fmt.toDouble(stats['averageRating']);
      _totalReviews = (stats['totalReviews'] as num?)?.toInt() ?? 0;
      _breakdown = {
        for (var star = 5; star >= 1; star--)
          star: ratings.where((rating) => rating.round().clamp(1, 5) == star).length,
      };
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load rating metrics.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: 'Ratings',
      copy: 'Rating trends, service score, completion quality, and dispatch confidence.',
      asset: 'assets/collector_assets/workflow/rating.svg',
      loading: _loading,
      error: _error,
      child: Column(children: [
        if (_totalReviews == 0)
          _CollectorStateCard(
            title: 'No ratings yet',
            copy: 'Ratings will appear after completed pickups receive customer feedback.',
            asset: 'assets/collector_assets/empty_states/no_reviews.svg',
            onRetry: _load,
          )
        else ...[
          CPanel(
            child: Row(children: [
              CIcon('star', color: CollectorColors.warning, size: 32),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_average.toStringAsFixed(1)} / 5.0', style: CollectorType.title),
                Text('$_totalReviews reviews', style: CollectorType.caption),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          CPanel(
            child: Column(
              children: [
                ..._breakdown.entries.map((entry) {
                  final ratio = _totalReviews == 0 ? 0.0 : entry.value / _totalReviews;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(width: 48, child: Text('${entry.key} star', style: CollectorType.caption)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 8,
                                  backgroundColor: CollectorColors.line,
                                  valueColor: AlwaysStoppedAnimation(CollectorColors.warning),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(width: 28, child: Text('${entry.value}', textAlign: TextAlign.right, style: CollectorType.section)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
                _MiniStat(label: 'Average rating', value: _average.toStringAsFixed(1)),
                const SizedBox(height: 10),
                _MiniStat(label: 'Total reviews', value: '$_totalReviews'),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class CollectorSettingsScreen extends StatefulWidget {
  const CollectorSettingsScreen({super.key});
  @override
  State<CollectorSettingsScreen> createState() => _CollectorSettingsScreenState();
}

class _CollectorSettingsScreenState extends State<CollectorSettingsScreen> {
  bool _loading = true;
  bool _sound = true;
  bool _autoAccept = false;
  bool _showRatings = true;
  String _language = 'English';
  ThemeMode _themeMode = ThemeMode.dark;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sound = prefs.getBool('collector_sound') ?? true;
      _autoAccept = prefs.getBool('collector_auto_accept') ?? false;
      _showRatings = prefs.getBool('collector_show_ratings') ?? true;
      _language = context.read<AppStringsProvider>().langCode;
      _themeMode = context.read<ThemeProvider>().themeMode;
      _error = null;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final stringsProvider = context.read<AppStringsProvider>();
    final themeProvider = context.read<ThemeProvider>();
    setState(() {
      _error = null;
      _success = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('collector_sound', _sound);
      await prefs.setBool('collector_auto_accept', _autoAccept);
      await prefs.setBool('collector_show_ratings', _showRatings);
      await stringsProvider.setLanguage(_language);
      final themeChanged = themeProvider.themeMode != _themeMode;
      await themeProvider.setThemeMode(_themeMode);
      if (!mounted) return;
      if (themeChanged) {
        // Screens already on the stack were painted with the old palette â€”
        // rebuild the app from the map so the new theme applies everywhere.
        Navigator.of(context).pushNamedAndRemoveUntil('/collector', (r) => false);
        return;
      }
      setState(() => _success = 'Settings saved.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save collector settings.');
    }
  }

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    setState(() {
      _error = null;
      _success = null;
    });
    try {
      await auth.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not log out right now.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: 'Settings',
      copy: 'Operational preferences, language, display mode, notification controls, and security.',
      asset: 'assets/collector_assets/workflow/maintenance.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Column(children: [
        CPanel(
          child: Column(children: [
            DropdownButtonFormField<ThemeMode>(
              initialValue: _themeMode,
              decoration: InputDecoration(
                labelText: 'Theme',
                filled: true,
                fillColor: CollectorColors.charcoal,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
              ),
              items: const [
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark â€” green on black')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light â€” green on white')),
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _themeMode = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(
                labelText: 'Language',
                filled: true,
                fillColor: CollectorColors.charcoal,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: CollectorColors.line)),
              ),
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'FranÃ§ais', child: Text('FranÃ§ais')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _language = value);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _sound,
              onChanged: (v) => setState(() => _sound = v),
              title: Text('Sound alerts', style: CollectorType.section),
            ),
            SwitchListTile(
              value: _autoAccept,
              onChanged: (v) => setState(() => _autoAccept = v),
              title: Text('Auto-accept jobs', style: CollectorType.section),
            ),
            SwitchListTile(
              value: _showRatings,
              onChanged: (v) => setState(() => _showRatings = v),
              title: Text('Show rating summary', style: CollectorType.section),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        CButton(label: 'Save settings', icon: 'settings', onPressed: _save),
        const SizedBox(height: 12),
        CButton(label: 'Log out', icon: 'support', secondary: true, onPressed: _logout),
      ]),
    );
  }
}

class CollectorDetailScreen extends StatelessWidget {
  const CollectorDetailScreen({super.key, required this.title, required this.copy, required this.asset, required this.rows});
  final String title;
  final String copy;
  final String asset;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return _CollectorFormScreen(
      title: title,
      copy: copy,
      asset: asset,
      child: Column(
        children: [
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(children: [
                    CIcon(r.$1, color: CollectorColors.green),
                    const SizedBox(width: 14),
                    Expanded(child: Text(r.$2, style: CollectorType.section)),
                  ]),
                ),
              )),
        ],
      ),
    );
  }
}

class _CollectorFormScreen extends StatelessWidget {
  const _CollectorFormScreen({
    required this.title,
    required this.copy,
    required this.asset,
    required this.child,
    this.loading = false,
    this.error,
    this.success,
  });

  final String title;
  final String copy;
  final String asset;
  final Widget child;
  final bool loading;
  final String? error;
  final String? success;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CollectorColors.dark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.maybePop(context), icon: CIcon('route', color: CollectorColors.white)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: CollectorType.title)),
            ]),
            const SizedBox(height: 12),
            CPanel(
              child: Column(children: [
                if (asset.endsWith('.png'))
                  Image.asset(asset, height: 190, fit: BoxFit.contain)
                else
                  SvgPicture.asset(asset, height: 210),
                const SizedBox(height: 12),
                Text(title, style: CollectorType.hero, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(copy, style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA)), textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 16),
            if (loading) const SkeletonList(count: 3, dark: true) else ...[
              if (error != null) ...[
                _Banner(title: 'Error', copy: error!, color: CollectorColors.red),
                const SizedBox(height: 12),
              ],
              if (success != null) ...[
                _Banner(title: 'Success', copy: success!, color: CollectorColors.success),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.copy, required this.color});
  final String title;
  final String copy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: CollectorType.section.copyWith(color: color)),
        const SizedBox(height: 4),
        Text(copy, style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.online});
  final int count;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return CPanel(
      child: Row(children: [
        CIcon('notifications', color: CollectorColors.warning, size: 34),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count updates', style: CollectorType.title),
          const SizedBox(height: 4),
          Text(online ? 'You are online and receiving live updates.' : 'Go online to receive new updates.', style: CollectorType.caption),
        ])),
      ]),
    );
  }
}

class _CollectorNotificationItem extends StatelessWidget {
  const _CollectorNotificationItem({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CPanel(
        child: InkWell(
          onTap: onTap,
          child: Row(children: [
            CIcon(_iconForType(notification.type), color: CollectorColors.green),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(notification.title, style: CollectorType.section),
              Text(notification.body, style: CollectorType.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.relativeTime(notification.createdAt), style: CollectorType.caption),
                if (!notification.isRead)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(color: CollectorColors.warning, shape: BoxShape.circle),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  String _iconForType(String type) {
    if (type.contains('PAYOUT') || type.contains('PAYMENT')) return 'wallet';
    if (type.contains('REWARD')) return 'bonus';
    if (type.contains('SUBSCRIPTION')) return 'calendar';
    return 'notifications';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label, style: CollectorType.caption)),
      Text(value, style: CollectorType.section),
    ]);
  }
}

class _CollectorStateCard extends StatelessWidget {
  const _CollectorStateCard({required this.title, required this.copy, required this.asset, required this.onRetry});
  final String title;
  final String copy;
  final String asset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CPanel(
      child: Column(children: [
        SvgPicture.asset(asset, height: 190),
        Text(title, style: CollectorType.title),
        const SizedBox(height: 8),
        Text(copy, textAlign: TextAlign.center, style: CollectorType.body.copyWith(color: const Color(0xFFC8D0DA))),
        const SizedBox(height: 12),
        CButton(label: 'Retry', icon: 'recycle', secondary: true, onPressed: onRetry),
      ]),
    );
  }
}
