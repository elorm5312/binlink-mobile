import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/design_system/theme_provider.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/places_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/components/binlink_avatar.dart';
import '../../../shared/components/skeleton.dart';
import '../../../shared/models/app_notification.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/household_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final hp = context.read<HouseholdProvider>();
    try {
      await Future.wait([
        auth.refreshProfile(),
        hp.loadBookings(),
        hp.loadNotifications(),
      ]);
      if (!mounted) return;
      setState(() {
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load notifications.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HouseholdProvider>();
    final user = context.watch<AuthProvider>().user;
    final items = hp.notifications;
    final grouped = _groupNotifications(items);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
          children: [
            Row(children: [
              Expanded(child: Text('Notifications', style: HouseholdType.hero)),
              if (hp.unreadNotifications > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: HouseholdColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${hp.unreadNotifications} unread', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary)),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _markAllRead,
                  child: Text('Mark all read', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary)),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            Text('Pickup status, wallet events, offers, and collector updates.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
            const SizedBox(height: 18),
            HCard(
              child: Row(children: [
                BinLinkAvatar(
                  name: user?.fullName,
                  imagePath: user?.profilePhoto,
                  fallbackAsset: 'assets/household_assets/avatars/default_avatar.svg',
                  size: 72,
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.fullName ?? 'BinLink household', style: HouseholdType.title),
                  const SizedBox(height: 4),
                  Text(user?.email ?? 'Profile synced with your account', style: HouseholdType.caption),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const SkeletonList(count: 4)
            else if (_error != null)
              _StateCard(
                title: 'Notifications unavailable',
                copy: _error!,
                asset: HouseholdAssets.networkError,
                onRetry: _load,
              )
            else if (items.isEmpty)
              _StateCard(
                title: 'No notifications yet',
                copy: 'Pickup updates and wallet events will appear here.',
                asset: HouseholdAssets.noNotifications,
                onRetry: _load,
              )
            else ...[
              _SummaryCard(count: items.length, unread: hp.unreadNotifications),
              const SizedBox(height: 16),
              ...grouped.entries.expand((entry) => [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(entry.key, style: HouseholdType.section),
                    ),
                    ...entry.value.map((item) => _NotificationTile(
                          notification: item,
                          onTap: () => _openNotification(item),
                        )),
                    const SizedBox(height: 10),
                  ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _markAllRead() async {
    await context.read<HouseholdProvider>().markAllNotificationsRead();
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead) {
      await context.read<HouseholdProvider>().markNotificationRead(notification.id);
    }
    if (!mounted) return;
    final route = _routeForNotification(notification);
    Navigator.pushNamed(context, route);
  }

  String _routeForNotification(AppNotification notification) {
    final type = notification.type.toUpperCase();
    if (notification.bookingId != null) return '/household';
    if (type.contains('PAYMENT')) return '/wallet';
    if (type.contains('REWARD')) return '/wallet';
    if (type.contains('PROMOTION')) return '/rewards';
    if (type.contains('BOOKING_UPDATE')) return '/household';
    return '/household';
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

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
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
        'role': 'HOUSEHOLD',
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        'email': auth.user?.email,
        'name': auth.user?.fullName,
      });
      if (!mounted) return;
      setState(() => _success = 'Support request submitted.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit support request.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return _FormScreen(
      title: 'Help & FAQ',
      copy: 'Support for bookings, payments, pickups, subscriptions, and account security.',
      asset: 'assets/household_assets/illustrations/live_map.svg',
      success: _success,
      error: _error,
      loading: _loading,
      child: Form(
        key: _formKey,
        child: Column(children: [
          HCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contact support', style: HouseholdType.section),
              const SizedBox(height: 12),
              HTextField(controller: _subject, label: 'Subject', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a subject' : null),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                minLines: 5,
                maxLines: 8,
                validator: (v) => (v == null || v.trim().length < 10) ? 'Enter a message' : null,
                decoration: InputDecoration(
                  labelText: 'Message',
                  hintText: 'Describe the issue, payment reference, or pickup problem.',
                  filled: true,
                  fillColor: HouseholdColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const _DirectContactCard(),
          const SizedBox(height: 12),
          HButton(label: 'Submit request', icon: 'support', loading: _loading, onPressed: _submit),
          const SizedBox(height: 12),
          if (user != null)
            HCard(
              color: HouseholdColors.forest,
              child: Text('Logged in as ${user.fullName ?? user.email ?? 'household account'}', style: HouseholdType.body.copyWith(color: Colors.white)),
            ),
        ]),
      ),
    );
  }
}

// ── Direct contact card (call / email the BinLink team) ──────────────────────
class _DirectContactCard extends StatelessWidget {
  const _DirectContactCard();

  static const _phone = '0233200022';
  static const _email = 'binlinkeco@gmail.com';

  Future<void> _launch(String uri) async {
    final u = Uri.parse(uri);
    if (await canLaunchUrl(u)) await launchUrl(u);
  }

  @override
  Widget build(BuildContext context) {
    return HCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Reach us directly', style: HouseholdType.section),
        const SizedBox(height: 4),
        Text('Call or email the BinLink team.', style: HouseholdType.caption),
        const SizedBox(height: 14),
        _ContactTile(
          icon: HIcon('phone', color: HouseholdColors.primary, size: 20),
          label: 'Call us',
          value: '0233 200 022',
          onTap: () => _launch('tel:$_phone'),
        ),
        const SizedBox(height: 10),
        _ContactTile(
          icon: Icon(Icons.mail_outline_rounded, size: 20, color: HouseholdColors.primary),
          label: 'Email us',
          value: _email,
          onTap: () => _launch('mailto:$_email'),
        ),
      ]),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.label, required this.value, required this.onTap});
  final Widget icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: HouseholdColors.primary.withAlpha(20), shape: BoxShape.circle),
          child: Center(child: icon),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: HouseholdType.caption),
            Text(value, style: HouseholdType.section.copyWith(fontSize: 15)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, size: 20, color: HouseholdColors.gray),
      ]),
    );
  }
}

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _loading = true;
  bool _shareLocation = true;
  bool _shareReceipts = true;
  bool _personalizedOffers = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await context.read<AuthProvider>().refreshProfile();
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _shareLocation = prefs.getBool('household_share_location') ?? true;
        _shareReceipts = prefs.getBool('household_share_receipts') ?? true;
        _personalizedOffers = prefs.getBool('household_personalized_offers') ?? false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load privacy preferences.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('household_share_location', _shareLocation);
    await prefs.setBool('household_share_receipts', _shareReceipts);
    await prefs.setBool('household_personalized_offers', _personalizedOffers);
    if (mounted) setState(() => _success = 'Privacy preferences saved.');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return _FormScreen(
      title: 'Privacy',
      copy: 'Manage location, account, payment, and data preferences.',
      asset: 'assets/household_assets/illustrations/schedule_pickup.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Column(children: [
        HCard(
          child: Column(children: [
            SwitchListTile(
              value: _shareLocation,
              onChanged: (v) => setState(() => _shareLocation = v),
              title: Text('Share location for pickups', style: HouseholdType.section),
            ),
            SwitchListTile(
              value: _shareReceipts,
              onChanged: (v) => setState(() => _shareReceipts = v),
              title: Text('Store receipts in history', style: HouseholdType.section),
            ),
            SwitchListTile(
              value: _personalizedOffers,
              onChanged: (v) => setState(() => _personalizedOffers = v),
              title: Text('Personalized offers', style: HouseholdType.section),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        HButton(label: 'Save privacy settings', icon: 'privacy', onPressed: _save),
        if (user != null) ...[
          const SizedBox(height: 12),
          HCard(
            child: Text('Account: ${user.email ?? user.phone ?? 'synced profile'}', style: HouseholdType.body),
          ),
        ],
      ]),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
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
    _address.dispose();
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
      _address.text = user?.address ?? '';
      _avatarPath = user?.profilePhoto;
    } catch (_) {
      _error = 'Could not load profile details.';
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
      address: _address.text.trim(),
      profilePhoto: _avatarPath,
    );
    try {
      await ApiClient.patch('/api/profile', {
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        if (_avatarPath != null) 'profilePhoto': _avatarPath,
      });
      await auth.refreshProfile();
      if (updated != null) auth.updateUser(updated);
      if (mounted) setState(() => _success = 'Profile updated.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save profile changes.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return _FormScreen(
      title: 'Edit profile',
      copy: 'Update profile details used for pickups, receipts, and support.',
      asset: 'assets/household_assets/avatars/default_avatar.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Form(
        key: _formKey,
        child: Column(children: [
          HCard(
            child: Column(children: [
              BinLinkAvatar(
                name: user?.fullName,
                imagePath: _avatarPath,
                fallbackAsset: 'assets/household_assets/avatars/default_avatar.svg',
                size: 92,
              ),
              const SizedBox(height: 12),
              HButton(label: 'Change photo', icon: 'camera', secondary: true, onPressed: _pickAvatar),
              const SizedBox(height: 16),
              HTextField(controller: _name, label: 'Full name', validator: (v) => (v == null || v.trim().length < 3) ? 'Enter your name' : null),
              const SizedBox(height: 12),
              HTextField(controller: _phone, label: 'Phone number', keyboardType: TextInputType.phone, validator: (v) => (v == null || v.trim().length < 8) ? 'Enter a phone number' : null),
              const SizedBox(height: 12),
              HTextField(controller: _address, label: 'Default address', validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an address' : null),
            ]),
          ),
          const SizedBox(height: 12),
          HButton(label: 'Save profile', icon: 'profile', loading: _saving, onPressed: _save),
        ]),
      ),
    );
  }
}

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});
  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  final _label = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
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
    _label.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await context.read<HouseholdProvider>().loadSavedAddresses();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load saved addresses.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_label.text.trim().length < 2 || _address.text.trim().length < 4) {
      setState(() => _error = 'Enter a label and address.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    final ok = await context.read<HouseholdProvider>().addSavedAddress(
      label: _label.text.trim(),
      address: _address.text.trim(),
      gateNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (mounted) {
      setState(() {
        _saving = false;
        _success = ok ? 'Address saved.' : null;
        if (!ok) _error = 'Could not save address.';
      });
      if (ok) {
        _label.clear();
        _address.clear();
        _notes.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HouseholdProvider>();
    final items = hp.savedAddresses;
    return _FormScreen(
      title: 'Saved addresses',
      copy: 'Home, work, and frequently used pickup locations.',
      asset: 'assets/household_assets/empty_states/no_addresses.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Column(children: [
        HCard(
          child: Column(children: [
            HTextField(controller: _label, label: 'Label', hint: 'Home, Work, Gate'),
            const SizedBox(height: 12),
            HTextField(controller: _address, label: 'Address'),
            const SizedBox(height: 12),
            HTextField(controller: _notes, label: 'Gate notes', hint: 'Call on arrival, blue gate, etc.'),
          ]),
        ),
        const SizedBox(height: 12),
        HButton(label: 'Save address', icon: 'location', loading: _saving, onPressed: _add),
        const SizedBox(height: 16),
        if (items.isEmpty)
          HCard(child: Text('No saved addresses yet.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)))
        else
          ...items.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(children: [
                    HIcon('home', color: HouseholdColors.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a['label'] as String? ?? 'Saved address', style: HouseholdType.section),
                      Text(a['address'] as String? ?? '', style: HouseholdType.caption),
                    ])),
                    TextButton(
                      onPressed: () => context.read<HouseholdProvider>().deleteSavedAddress(a['id'] as String),
                      child: Text('Delete', style: HouseholdType.caption.copyWith(color: HouseholdColors.danger)),
                    ),
                  ]),
                ),
              )),
      ]),
    );
  }
}

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _plan = ValueNotifier<String>('WEEKLY');
  final _binSize = ValueNotifier<String>('MEDIUM');
  final _address = TextEditingController();
  final _notes = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;
  int? _pickupDay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _plan.dispose();
    _binSize.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await context.read<HouseholdProvider>().loadSubscriptions();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load subscriptions.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_address.text.trim().length < 4) {
      setState(() => _error = 'Enter a pickup address.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final provider = context.read<HouseholdProvider>();
      final predictions = await PlacesService.autocomplete(_address.text.trim());
      if (predictions.isEmpty || predictions.first.lat == null || predictions.first.lng == null) {
        throw Exception('No coordinates');
      }
      final detail = await PlacesService.getDetail(predictions.first.placeId);
      final created = await provider.createSubscription(
        plan: _plan.value,
        binSize: _binSize.value,
        pickupAddress: detail?.address ?? predictions.first.fullText,
        pickupLat: detail?.lat ?? predictions.first.lat!,
        pickupLng: detail?.lng ?? predictions.first.lng!,
        pickupDay: _pickupDay,
        addressNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (created == null) throw Exception('Create failed');
      if (mounted) {
        setState(() => _success = 'Subscription created.');
        _address.clear();
        _notes.clear();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create subscription.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HouseholdProvider>();
    final items = hp.subscriptions;
    return _FormScreen(
      title: 'Subscriptions',
      copy: 'Recurring waste collection plans for predictable household service.',
      asset: 'assets/household_assets/illustrations/schedule_pickup.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Column(children: [
        HCard(
          child: Column(children: [
            ValueListenableBuilder<String>(
              valueListenable: _plan,
              builder: (_, value, __) => DropdownButtonFormField<String>(
                initialValue: value,
                decoration: _inputDecoration('Plan'),
                items: const [
                  DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
                  DropdownMenuItem(value: 'BIWEEKLY', child: Text('Biweekly')),
                  DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                ],
                onChanged: (v) => _plan.value = v ?? 'WEEKLY',
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: _binSize,
              builder: (_, value, __) => DropdownButtonFormField<String>(
                initialValue: value,
                decoration: _inputDecoration('Bin size'),
                items: const ['SMALL', 'MEDIUM', 'LARGE']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => _binSize.value = v ?? 'MEDIUM',
              ),
            ),
            const SizedBox(height: 12),
            HTextField(controller: _address, label: 'Pickup address', validator: (v) => (v == null || v.trim().length < 4) ? 'Enter an address' : null),
            const SizedBox(height: 12),
            HTextField(controller: _notes, label: 'Address notes', hint: 'Gate, floor, call ahead'),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _pickupDay,
              decoration: _inputDecoration('Pickup day'),
              items: const [1, 2, 3, 4, 5, 6, 7].map((d) => DropdownMenuItem(value: d, child: Text('Day $d'))).toList(),
              onChanged: (v) => setState(() => _pickupDay = v),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        HButton(label: 'Create subscription', icon: 'calendar', loading: _saving, onPressed: _create),
        const SizedBox(height: 16),
        if (items.isEmpty)
          HCard(child: Text('No active subscriptions.', style: HouseholdType.body.copyWith(color: HouseholdColors.gray)))
        else
          ...items.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      HIcon('calendar', color: HouseholdColors.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_planLabel(s['plan'] as String? ?? 'WEEKLY'), style: HouseholdType.section),
                        Text(s['pickupAddress'] as String? ?? '', style: HouseholdType.caption),
                      ])),
                      _SubscriptionStatus(status: s['status'] as String? ?? 'ACTIVE'),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      (s['nextPickupDate'] as String?) == null
                          ? 'Next collection date unavailable'
                          : 'Next collection ${Fmt.relativeTime(DateTime.tryParse(s['nextPickupDate'] as String) ?? DateTime.now())}',
                      style: HouseholdType.caption,
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      HButton(
                        label: (s['status'] as String? ?? 'ACTIVE') == 'PAUSED' ? 'Resume' : 'Pause',
                        icon: 'schedule',
                        secondary: true,
                        onPressed: () async {
                          final id = s['id'] as String?;
                          if (id == null) return;
                          final status = s['status'] as String? ?? 'ACTIVE';
                          if (status == 'PAUSED') {
                            await context.read<HouseholdProvider>().resumeSubscription(id);
                          } else if (status == 'ACTIVE') {
                            await context.read<HouseholdProvider>().pauseSubscription(id);
                          }
                        },
                      ),
                      HButton(
                        label: 'Skip next',
                        icon: 'route',
                        secondary: true,
                        onPressed: (s['status'] as String? ?? 'ACTIVE') == 'ACTIVE'
                            ? () async {
                                final id = s['id'] as String?;
                                if (id != null) await context.read<HouseholdProvider>().skipNextSubscriptionPickup(id);
                              }
                            : null,
                      ),
                      HButton(
                        label: 'Cancel',
                        icon: 'support',
                        secondary: true,
                        onPressed: () async {
                          final id = s['id'] as String?;
                          if (id != null) await context.read<HouseholdProvider>().cancelSubscription(id);
                        },
                      ),
                    ]),
                  ]),
                ),
              )),
      ]),
    );
  }

  String _planLabel(String value) {
    switch (value) {
      case 'BIWEEKLY':
        return 'Biweekly';
      case 'MONTHLY':
        return 'Monthly';
      default:
        return 'Weekly';
    }
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: HouseholdColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
      );
}

class _SubscriptionStatus extends StatelessWidget {
  const _SubscriptionStatus({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'PAUSED' => HouseholdColors.warning,
      'CANCELLED' => HouseholdColors.danger,
      _ => HouseholdColors.ecoGreen,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status, style: HouseholdType.caption.copyWith(color: color)),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _pushNotifications = true;
  bool _emailReceipts = true;
  bool _sound = true;
  String _language = 'English';
  ThemeMode _themeMode = ThemeMode.light;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final strings = context.read<AppStringsProvider>();
    final theme = context.read<ThemeProvider>();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pushNotifications = prefs.getBool('household_push_notifications') ?? true;
      _emailReceipts = prefs.getBool('household_email_receipts') ?? true;
      _sound = prefs.getBool('household_sound') ?? true;
      _language = strings.langCode;
      _themeMode = theme.themeMode;
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
      await prefs.setBool('household_push_notifications', _pushNotifications);
      await prefs.setBool('household_email_receipts', _emailReceipts);
      await prefs.setBool('household_sound', _sound);
      await stringsProvider.setLanguage(_language);
      final themeChanged = themeProvider.themeMode != _themeMode;
      await themeProvider.setThemeMode(_themeMode);
      if (!mounted) return;
      if (themeChanged) {
        // Screens already on the stack were painted with the old palette —
        // rebuild the app from home so the new theme applies everywhere.
        Navigator.of(context).pushNamedAndRemoveUntil('/household', (r) => false);
        return;
      }
      setState(() => _success = 'Settings saved.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save settings.');
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
    return _FormScreen(
      title: 'Settings',
      copy: 'Manage notifications, language, theme, account session, and receipt delivery.',
      asset: 'assets/household_assets/illustrations/live_map.svg',
      loading: _loading,
      error: _error,
      success: _success,
      child: Column(children: [
        HCard(
          child: Column(children: [
            DropdownButtonFormField<ThemeMode>(
              initialValue: _themeMode,
              decoration: _settingsDecoration('Theme'),
              items: const [
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _themeMode = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: _settingsDecoration('Language'),
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'Français', child: Text('Français')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _language = value);
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: _pushNotifications,
              onChanged: (v) => setState(() => _pushNotifications = v),
              title: Text('Push notifications', style: HouseholdType.section),
            ),
            SwitchListTile(
              value: _emailReceipts,
              onChanged: (v) => setState(() => _emailReceipts = v),
              title: Text('Email receipts', style: HouseholdType.section),
            ),
            SwitchListTile(
              value: _sound,
              onChanged: (v) => setState(() => _sound = v),
              title: Text('Sound alerts', style: HouseholdType.section),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        HButton(label: 'Save settings', icon: 'settings', onPressed: _save),
        const SizedBox(height: 12),
        HButton(label: 'Log out', icon: 'support', secondary: true, onPressed: _logout),
      ]),
    );
  }

  InputDecoration _settingsDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: HouseholdColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: HouseholdColors.border)),
      );
}

class _FormScreen extends StatelessWidget {
  const _FormScreen({
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
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.maybePop(context), icon: HIcon('route', color: HouseholdColors.forest)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: HouseholdType.title)),
            ]),
            const SizedBox(height: 12),
            HCard(
              child: Column(children: [
                SvgPicture.asset(asset, height: 210),
                const SizedBox(height: 12),
                Text(title, style: HouseholdType.hero, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(copy, style: HouseholdType.body.copyWith(color: HouseholdColors.gray), textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 16),
            if (loading) const SkeletonList(count: 3) else ...[
              if (error != null) ...[
                _StateBanner(title: 'Error', copy: error!, color: HouseholdColors.danger),
                const SizedBox(height: 12),
              ],
              if (success != null) ...[
                _StateBanner(title: 'Success', copy: success!, color: HouseholdColors.ecoGreen),
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

class _StateBanner extends StatelessWidget {
  const _StateBanner({required this.title, required this.copy, required this.color});
  final String title;
  final String copy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return HCard(
      color: color.withAlpha(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: HouseholdType.section.copyWith(color: color)),
        const SizedBox(height: 4),
        Text(copy, style: HouseholdType.body.copyWith(color: HouseholdColors.charcoal)),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.unread});
  final int count;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return HCard(
      color: HouseholdColors.forest,
      child: Row(children: [
        SvgPicture.asset(HouseholdAssets.searching, height: 84),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count updates', style: HouseholdType.title.copyWith(color: Colors.white)),
          const SizedBox(height: 4),
          Text(unread == 0 ? 'All notifications are read.' : '$unread updates still need attention.', style: HouseholdType.caption.copyWith(color: Colors.white70)),
        ])),
      ]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});
  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HCard(
        color: notification.isRead
            ? HouseholdColors.card
            : (HouseholdColors.isDark ? const Color(0xFF14241B) : const Color(0xFFF0FFF6)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: InkWell(
          onTap: onTap,
          child: Row(children: [
            HIcon(_iconForType(notification.type), color: HouseholdColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(notification.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: HouseholdType.section),
                Text(notification.body, style: HouseholdType.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.relativeTime(notification.createdAt), style: HouseholdType.caption),
                if (!notification.isRead)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(color: HouseholdColors.primary, shape: BoxShape.circle),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  String _iconForType(String type) {
    if (type.contains('PAYMENT')) return 'payment';
    if (type.contains('REWARD')) return 'rewards';
    if (type.contains('SUBSCRIPTION')) return 'calendar';
    return 'notifications';
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.title, required this.copy, required this.asset, required this.onRetry});
  final String title;
  final String copy;
  final String asset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HCard(
      child: Column(children: [
        SvgPicture.asset(asset, height: 190),
        Text(title, style: HouseholdType.title),
        const SizedBox(height: 8),
        Text(copy, textAlign: TextAlign.center, style: HouseholdType.body.copyWith(color: HouseholdColors.gray)),
        const SizedBox(height: 12),
        HButton(label: 'Retry', icon: 'recycle', secondary: true, onPressed: onRetry),
      ]),
    );
  }
}

// ─── Terms of Service ─────────────────────────────────────────────────────────

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.maybePop(context), icon: HIcon('route', color: HouseholdColors.forest)),
              Expanded(child: Text('Terms of Service', style: HouseholdType.title)),
            ]),
            const SizedBox(height: 6),
            Text('Last updated: June 2026', style: HouseholdType.caption),
            const SizedBox(height: 20),
            for (final section in _kTermsSections) ...[
              HCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(section.$1, style: HouseholdType.section),
                  const SizedBox(height: 10),
                  Text(section.$2, style: HouseholdType.body.copyWith(height: 1.55, color: HouseholdColors.gray)),
                ]),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

const _kTermsSections = [
  (
    '1. Acceptance of Terms',
    'By downloading, installing, or using the BinLink application, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the app.',
  ),
  (
    '2. Description of Service',
    'BinLink is a waste collection platform that connects households and businesses with independent waste collectors in Ghana. BinLink acts as a marketplace facilitator and is not directly responsible for the quality or completion of collection services.',
  ),
  (
    '3. Eligibility',
    'You must be at least 18 years of age to use BinLink. By registering, you represent and warrant that you meet this requirement and that all information you provide is accurate and complete.',
  ),
  (
    '4. Bookings & Payments',
    'Bookings are confirmed only upon successful payment via Mobile Money (MTN MoMo, Telecel Cash, or AirtelTigo) or cash on collection. Prices are denominated in Ghana Cedis (GHS). BinLink reserves the right to update pricing at any time with reasonable notice.',
  ),
  (
    '5. Cancellations',
    'Households may cancel a booking up to 3 times per 24-hour period. Excessive cancellations may result in account restrictions. Collectors who cancel or fail to arrive may be subject to penalties at BinLink\'s discretion.',
  ),
  (
    '6. Data & Privacy',
    'BinLink collects location data, contact information, and transaction history to provide its service. Your data is stored securely and is never sold to third parties. Please review our Privacy Policy for full details.',
  ),
  (
    '7. Eco Rewards',
    'Eco Points earned through recyclable waste pickups have no cash value and may only be redeemed as discounts on future BinLink bookings. Points expire after 12 months of account inactivity.',
  ),
  (
    '8. Liability',
    'BinLink\'s liability is limited to the amount paid for the disputed booking. We are not liable for indirect damages, missed pickups due to force majeure, or disputes between users and Collectors that arise outside the app.',
  ),
  (
    '9. Account Termination',
    'BinLink reserves the right to suspend or terminate any account that violates these terms, engages in fraudulent activity, or abuses the platform or its Collectors.',
  ),
  (
    '10. Governing Law',
    'These Terms are governed by the laws of the Republic of Ghana. Any disputes shall be resolved through mediation or the courts of Ghana.',
  ),
  (
    '11. Contact',
    'For questions about these Terms of Service, please contact us at binlinkeco@gmail.com, call 0233200022, or use the Help & Support section in the app.',
  ),
];
