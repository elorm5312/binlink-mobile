import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/app_flavor.dart';
import '../../core/network/api_client.dart';
import '../../core/design_system/collector_design_system.dart';
import '../../core/design_system/household_design_system.dart';
import 'chat_screen.dart';

/// Inbox of the user's chat threads (one per booking that has messages), for
/// both flavors. Loads from `GET /api/chat/conversations`; tapping a row opens
/// the full [ChatScreen] for that booking.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _convos = [];
  bool _loading = true;
  String? _error;

  bool get _collector => FlavorConfig.isCollector;
  Color get _accent => _collector ? CollectorColors.green : HouseholdColors.primary;
  Color get _bg => _collector ? CollectorColors.dark : HouseholdColors.warmWhite;
  Color get _surface => _collector ? CollectorColors.charcoal : HouseholdColors.card;
  Color get _onSurface => _collector ? CollectorColors.white : HouseholdColors.charcoal;
  Color get _muted => _collector ? CollectorColors.gray : HouseholdColors.gray;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/chat/conversations');
      final list = (res.data['data'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _convos = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load messages. Check your connection.';
      });
    }
  }

  void _open(Map<String, dynamic> c) {
    final peer = c['peer'] as Map<String, dynamic>?;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            bookingId: c['bookingId'] as String,
            peerName: peer?['fullName'] as String? ?? (_collector ? 'Customer' : 'Collector'),
          ),
        ))
        .then((_) => _load());
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  String _time(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _onSurface,
        elevation: 0.5,
        title: Text('Messages', style: HouseholdType.section.copyWith(color: _onSurface)),
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return Center(child: CircularProgressIndicator(color: _accent));
    if (_error != null) {
      return _centered(PhosphorIcons.warningCircle(), _error!, action: 'Retry', onAction: () {
        setState(() => _loading = true);
        _load();
      });
    }
    if (_convos.isEmpty) {
      return _centered(PhosphorIcons.chatCircleDots(),
          'No conversations yet.\nMessages with your ${_collector ? 'customers' : 'collectors'} appear here.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _convos.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: _muted.withAlpha(30), indent: 76),
      itemBuilder: (_, i) => _tile(_convos[i]),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final peer = c['peer'] as Map<String, dynamic>?;
    final name = peer?['fullName'] as String? ?? (_collector ? 'Customer' : 'Collector');
    final last = c['lastMessage'] as String? ?? '';
    final fromMe = c['lastFromMe'] == true;
    final preview = last.isEmpty ? 'No messages' : (fromMe ? 'You: $last' : last);
    return ListTile(
      onTap: () => _open(c),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: _accent.withAlpha(40),
        child: Text(_initials(name),
            style: HouseholdType.section.copyWith(color: _accent, fontWeight: FontWeight.w800)),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: HouseholdType.section.copyWith(color: _onSurface)),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: HouseholdType.caption.copyWith(color: _muted)),
      trailing: Text(_time(c['lastAt'] as String?),
          style: HouseholdType.caption.copyWith(color: _muted, fontSize: 11)),
    );
  }

  Widget _centered(IconData icon, String text, {String? action, VoidCallback? onAction}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
        Icon(icon, color: _muted, size: 44),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: HouseholdType.body.copyWith(color: _muted)),
        if (action != null) ...[
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: onAction, child: Text(action, style: TextStyle(color: _accent)))),
        ],
      ],
    );
  }
}
