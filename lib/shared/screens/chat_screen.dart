import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_flavor.dart';
import '../../core/network/api_client.dart';
import '../../core/design_system/household_design_system.dart';
import '../../core/design_system/collector_design_system.dart';
import '../models/chat_message.dart';

/// Real-time in-app chat between a household and their assigned collector for a
/// single booking. Shared across both flavors — accent and surfaces adapt via
/// [FlavorConfig]. History loads from `GET /api/bookings/:id/chat`; new messages
/// post to `POST /api/bookings/:id/chat` and arrive live over Supabase Realtime.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.bookingId, required this.peerName});

  final String bookingId;
  final String peerName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _ids = <String>{};
  final _messages = <ChatMessage>[];

  RealtimeChannel? _channel;
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String get _myRole => FlavorConfig.defaultRole;

  // Flavor-aware palette.
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
    _subscribe();
    // Polling fallback: Supabase Realtime can drop silently on mobile networks,
    // which left the recipient never seeing new messages until they reopened the
    // chat. A light 4s poll guarantees delivery regardless of socket health;
    // messages are de-duplicated by id so this never double-adds.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Silent background refresh (no spinner) used by the polling fallback.
  Future<void> _refresh() async {
    try {
      final res = await ApiClient.get('/api/bookings/${widget.bookingId}/chat');
      final list = (res.data['data'] as List?) ?? const [];
      for (final e in list) {
        _appendUnique(ChatMessage.fromMap(Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {
      // Best-effort; the next tick retries.
    }
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/bookings/${widget.bookingId}/chat');
      final list = (res.data['data'] as List?) ?? const [];
      final parsed =
          list.map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(parsed);
        _ids
          ..clear()
          ..addAll(parsed.map((m) => m.id));
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load messages. Check your connection.';
      });
    }
  }

  void _subscribe() {
    try {
      _channel = Supabase.instance.client
          .channel('chat_${widget.bookingId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: widget.bookingId,
            ),
            callback: (payload) {
              final msg = ChatMessage.fromMap(Map<String, dynamic>.from(payload.newRecord));
              _appendUnique(msg);
            },
          )
          .subscribe();
    } catch (_) {
      // Realtime is best-effort; the POST response still appends locally.
    }
  }

  void _appendUnique(ChatMessage msg) {
    if (msg.id.isEmpty || _ids.contains(msg.id) || !mounted) return;
    setState(() {
      _ids.add(msg.id);
      _messages.add(msg);
    });
    _scrollToEnd();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await ApiClient.post(
        '/api/bookings/${widget.bookingId}/chat',
        {'message': text},
      );
      _input.clear();
      final data = res.data['data'];
      if (data is Map) {
        _appendUnique(ChatMessage.fromMap(Map<String, dynamic>.from(data)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message failed to send. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0.5,
        foregroundColor: _onSurface,
        titleSpacing: 0,
        // Explicit, always-visible back button.
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(PhosphorIconsStyle.bold), color: _onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _accent.withAlpha(40),
              child: Text(_initials(widget.peerName),
                  style: HouseholdType.caption.copyWith(color: _accent, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.peerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: HouseholdType.section.copyWith(color: _onSurface)),
                  Text('Pickup chat',
                      style: HouseholdType.caption.copyWith(color: _muted)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.warningCircle(), color: _muted, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: HouseholdType.body.copyWith(color: _muted)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: Text('Retry', style: TextStyle(color: _accent)),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.chatCircleDots(), color: _muted, size: 44),
              const SizedBox(height: 12),
              Text('No messages yet',
                  style: HouseholdType.section.copyWith(color: _onSurface)),
              const SizedBox(height: 6),
              Text('Send a message to coordinate your pickup.',
                  textAlign: TextAlign.center,
                  style: HouseholdType.caption.copyWith(color: _muted)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.isMine(_myRole);
    final bubbleColor = mine ? _accent : _surface;
    final textColor = mine ? Colors.white : _onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.message,
                style: HouseholdType.body.copyWith(color: textColor)),
            const SizedBox(height: 3),
            Text(_time(m.sentAt),
                style: HouseholdType.caption.copyWith(
                    color: textColor.withAlpha(170), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.paddingOf(context).bottom + 8),
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: HouseholdType.body.copyWith(color: _onSurface),
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: HouseholdType.body.copyWith(color: _muted),
                filled: true,
                fillColor: _bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(PhosphorIcons.paperPlaneRight(PhosphorIconsStyle.fill),
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime? t) {
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}
