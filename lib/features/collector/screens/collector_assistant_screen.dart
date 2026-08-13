import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design_system/collector_design_system.dart';

/// A lightweight, offline rule-based support assistant for collectors. It answers
/// the most common operational questions instantly (no backend/LLM needed) and,
/// when it can't help, points the collector to human dispatch via [onContactHuman].
class CollectorAssistantScreen extends StatefulWidget {
  const CollectorAssistantScreen({super.key, this.onContactHuman});
  final VoidCallback? onContactHuman;

  @override
  State<CollectorAssistantScreen> createState() => _CollectorAssistantScreenState();
}

class _BotMessage {
  _BotMessage(this.text, {required this.fromBot});
  final String text;
  final bool fromBot;
}

class _CollectorAssistantScreenState extends State<CollectorAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_BotMessage>[];

  // Quick-tap topics shown as chips.
  static const _topics = <String>[
    'Go online',
    'Accept a job',
    'Mark arrived',
    'Complete a pickup',
    'Get paid',
    'Verification',
    'Truck full',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(_BotMessage(
      "Hi 👋 I'm your BinLink assistant. Ask me anything, or tap a topic below. "
      'For account-specific issues, I can connect you to dispatch.',
      fromBot: true,
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_BotMessage(text, fromBot: false));
      _messages.add(_BotMessage(_answer(text), fromBot: true));
    });
    _input.clear();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
      }
    });
  }

  // Rule-based knowledge base — keyword match → canned answer.
  String _answer(String q) {
    final s = q.toLowerCase();
    bool has(List<String> words) => words.any((w) => s.contains(w));

    if (has(['online', 'go on', 'start work', 'receive job', 'available'])) {
      return "To go online: open the Map tab and tap GO ONLINE. You must have location "
          "permission enabled and be verified. Once online you'll receive nearby jobs with a "
          "loud alert — tap TAP TO ACCEPT within 30 seconds.";
    }
    if (has(['accept', 'take job', 'new request', 'incoming'])) {
      return "When a job comes in, the screen takes over with a ringing alert. Tap TAP TO "
          "ACCEPT to take it (or DECLINE). After accepting you'll see the pickup details, the "
          "customer's photos, and a Start Navigation button.";
    }
    if (has(['arriv', 'reached', 'at the', "i'm here", 'im here'])) {
      return "On the active job screen tap MARK ARRIVED once you reach the pickup. If you left "
          "the screen, go to the Map tab and tap RESUME on the active-job bar to get back to it.";
    }
    if (has(['complete', 'finish', 'done', 'collected', 'weight', 'end job'])) {
      return "To complete a pickup: on the active job, tap START COLLECTING, set the weight with "
          "the slider, then COMPLETE WITH WEIGHT. Capture BEFORE/AFTER photos as proof. If the "
          "price was negotiated, you'll enter the agreed amount before finishing.";
    }
    if (has(['pay', 'payout', 'withdraw', 'money', 'earning', 'cash out', 'momo'])) {
      return "Your earnings show on the Wallet tab. Tap Withdraw, enter your MoMo number and "
          "amount, and request a payout. Completed-job earnings move from Pending to Available "
          "after settlement.";
    }
    if (has(['verif', 'kyc', 'document', 'approve', 'ghana card', 'license'])) {
      return "To get verified, open Verification and upload your Ghana Card, driver's license and "
          "a vehicle photo. Approval is usually quick — you'll get a notification. You can't go "
          "online until you're verified.";
    }
    if (has(['full', 'capacity', 'dumpsite', 'offload', 'empty truck'])) {
      return "At ~90% load you'll see a dumpsite banner on the Map. Tap Navigate to route there, "
          "and after emptying tap \"I've offloaded\" to reset your load and resume matching.";
    }
    if (has(['call', 'phone', 'contact customer', 'reach customer'])) {
      return "On the active job screen tap the green phone icon to call the customer directly. "
          "You can also message them with the chat icon.";
    }
    if (has(['cancel', 'no show', "didn't show", 'not home', 'no-show'])) {
      return "If the customer isn't available, use \"Customer didn't show up?\" on the active job "
          "to report a no-show — you'll be compensated. For other issues use Report Issue.";
    }
    if (has(['rating', 'review', 'stars'])) {
      return "Customers rate you after each pickup. Keep your rating high by being punctual, "
          "polite, and capturing clear proof photos.";
    }
    if (has(['human', 'agent', 'dispatch', 'support', 'talk to', 'real person', 'help me'])) {
      return "Sure — I can connect you to dispatch. Tap the \"Contact dispatch\" button below.";
    }
    return "I'm not sure about that one. Try a topic below, or I can connect you to a human at "
        "dispatch — just type \"talk to support\".";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CollectorColors.dark,
      appBar: AppBar(
        backgroundColor: CollectorColors.charcoal,
        foregroundColor: CollectorColors.white,
        elevation: 0.5,
        title: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: CollectorColors.green.withAlpha(40),
            child: Icon(PhosphorIcons.robot(), color: CollectorColors.green, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Support Assistant', style: CollectorType.section),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _bubble(_messages[i]),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _topics.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ActionChip(
              backgroundColor: CollectorColors.charcoal,
              side: BorderSide(color: CollectorColors.line),
              label: Text(_topics[i], style: CollectorType.caption.copyWith(color: CollectorColors.white)),
              onPressed: () => _send(_topics[i]),
            ),
          ),
        ),
        if (widget.onContactHuman != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: widget.onContactHuman,
                icon: Icon(PhosphorIcons.headset(), color: CollectorColors.green, size: 18),
                label: Text('Contact dispatch (human)',
                    style: CollectorType.caption.copyWith(color: CollectorColors.green, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        _composer(),
      ]),
    );
  }

  Widget _bubble(_BotMessage m) {
    final mine = !m.fromBot;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: mine ? CollectorColors.green : CollectorColors.charcoal,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Text(m.text,
            style: CollectorType.body.copyWith(color: mine ? CollectorColors.dark : CollectorColors.white)),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.paddingOf(context).bottom + 8),
      color: CollectorColors.charcoal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            style: CollectorType.body.copyWith(color: CollectorColors.white),
            onSubmitted: _send,
            decoration: InputDecoration(
              hintText: 'Ask a question…',
              hintStyle: CollectorType.body.copyWith(color: CollectorColors.gray),
              filled: true,
              fillColor: CollectorColors.dark,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _send(_input.text),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: CollectorColors.green, shape: BoxShape.circle),
            child: Icon(PhosphorIcons.paperPlaneRight(PhosphorIconsStyle.fill), color: CollectorColors.dark, size: 20),
          ),
        ),
      ]),
    );
  }
}
