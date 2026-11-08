import 'dart:async';
import 'package:flutter/material.dart';
import 'services/help_desk_service.dart';

class HelpDeskPage extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<String> onNavigate;

  const HelpDeskPage({super.key, required this.onBack, required this.onNavigate});

  @override
  State<HelpDeskPage> createState() => _HelpDeskPageState();
}

class _HelpDeskPageState extends State<HelpDeskPage> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _messagesScrollController = ScrollController();
  final List<_HelpDeskMessage> _messages = [];
  bool _isSending = false;
  SupportTicket? _ticket;
  bool _isManual = false;
  bool _isRefreshingTicket = false;
  Timer? _messagePollTimer;
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _resumeActiveTicket();
  }

  Future<void> _resumeActiveTicket() async {
    try {
      final ticket = await HelpDeskService.getActiveTicket();
      if (!mounted || ticket == null) return;
      _ticket = ticket;
      _isManual = true;
      await _loadTicketMessages();
      _startPolling();
      if (mounted) setState(() {});
    } catch (_) {
      // Ticket history is optional on initial page load; AI chat remains available.
    }
  }

  void _startPolling() {
    _messagePollTimer?.cancel();
    _messagePollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshManualChat());
  }

  Future<void> _refreshManualChat() async {
    final currentTicket = _ticket;
    if (currentTicket == null || _isRefreshingTicket || currentTicket.ticketStatus.toLowerCase() == 'resolved') return;
    _isRefreshingTicket = true;
    try {
      final latestTicket = await HelpDeskService.getTicket(currentTicket.ticketID);
      if (!mounted || !_isManual) return;
      final becameResolved = latestTicket.ticketStatus.toLowerCase() == 'resolved' && currentTicket.ticketStatus.toLowerCase() != 'resolved';
      setState(() => _ticket = latestTicket);
      await _loadTicketMessages();
      if (becameResolved) _messagePollTimer?.cancel();
    } catch (_) {
      await _loadTicketMessages();
    } finally {
      _isRefreshingTicket = false;
    }
  }

  void _showToast(String message) {
    _toastEntry?.remove();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 24,
        right: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 34,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF991B1B), borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 5))]),
                child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_toastEntry == entry) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }

  void _leaveResolvedChat() {
    _messageFocusNode.unfocus();
    _messagePollTimer?.cancel();
    setState(() {
      _isManual = false;
      _ticket = null;
      _messages.clear();
    });
  }

  void _handleResolvedInput() {
    if (_ticket?.ticketStatus.toLowerCase() != 'resolved') return;
    _showToast('This chat is resolved. Use Back to Help Desk to leave this conversation.');
  }

  Future<void> _loadTicketMessages() async {
    final ticket = _ticket;
    if (ticket == null) return;
    try {
      final fetched = await HelpDeskService.getMessages(ticket.ticketID);
      if (!mounted || !_isManual) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(fetched.map((item) => _HelpDeskMessage(
                text: item.messageContent,
                isFromCustomer: item.senderRole == 'customer',
              )));
      });
      _scrollToLatest();
    } catch (_) {}
  }

  Future<void> _showManualChatPrompt() async {
    final category = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        const categories = [
          ('Purchase', Icons.shopping_bag_outlined),
          ('Trade In', Icons.autorenew_rounded),
          ('Rent', Icons.calendar_month_outlined),
          ('Other', Icons.more_horiz_rounded),
        ];
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
          title: Row(children: [
            const Expanded(child: Text('Talk to customer service', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close), tooltip: 'Close'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(alignment: Alignment.centerLeft, child: Text('What do you need help with?', style: TextStyle(color: Color(0xFF64748B)))),
              const SizedBox(height: 12),
              ...categories.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, entry.$1),
                        icon: Icon(entry.$2, color: const Color(0xFF0C4AA3)),
                        label: Text(entry.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), foregroundColor: const Color(0xFF0F172A), side: const BorderSide(color: Color(0xFFCBD5E1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  )),
            ],
          ),
        );
      },
    );
    if (category == null || !mounted) return;
    try {
      final ticket = await HelpDeskService.createTicket(category);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _isManual = true;
        _messages.clear();
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _messagesScrollController.dispose();
    _messagePollTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollController.hasClients) return;
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    if (_isManual && _ticket?.ticketStatus.toLowerCase() == 'resolved') {
      _handleResolvedInput();
      return;
    }
    if (_isSending) return;
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    final history = _messages
        .take(12)
        .map((item) => <String, String>{
              'role': item.isFromCustomer ? 'user' : 'model',
              'text': item.text,
            })
        .toList();
    setState(() {
      _messages.add(_HelpDeskMessage(text: message, isFromCustomer: true));
      _messageController.clear();
      _isSending = true;
    });
    _scrollToLatest();
    try {
      if (_isManual && _ticket != null) {
        await HelpDeskService.sendTicketMessage(_ticket!.ticketID, message);
        _messageController.clear();
        await _loadTicketMessages();
        return;
      }
      final reply = await HelpDeskService.sendMessage(message: message, history: history);
      if (!mounted) return;
      setState(() => _messages.add(_HelpDeskMessage(
            text: reply.text,
            isFromCustomer: false,
            intent: reply.intent,
            actions: reply.actions,
            steps: reply.steps,
            needsStaff: reply.needsStaff,
          )));
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      if (_isManual) {
        setState(() { if (_messages.isNotEmpty && _messages.last.isFromCustomer) _messages.removeLast(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
      } else {
        setState(() => _messages.add(_HelpDeskMessage(
              text: error.toString().replaceFirst('Exception: ', ''),
              isFromCustomer: false,
            )));
        _scrollToLatest();
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
        children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 18, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: _isManual && _ticket?.ticketStatus.toLowerCase() == 'resolved' ? _leaveResolvedChat : widget.onBack,
                icon: const Icon(Icons.arrow_back, color: Color(0xFF475569)),
                tooltip: 'Back to home',
              ),
              Expanded(child: Text(_isManual ? 'Customer Service' : 'Help Desk', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)))),
              if (!_isManual)
                IconButton(
                  onPressed: _showManualChatPrompt,
                  icon: const Icon(Icons.support_agent_rounded, color: Color(0xFF0C4AA3)),
                  tooltip: 'Talk to customer service',
                )
              else
                Text('Ticket ${_ticket?.ticketID ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.support_agent, size: 48, color: Color(0xFF0C5AD2)),
                        const SizedBox(height: 12),
                        Text(_isManual ? 'You’re connected to customer service' : 'How can we help you?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        const SizedBox(height: 6),
                        Text(_isManual ? 'Send a message and a ReByte staff member will reply here.' : 'Send a message to start a conversation with ReByte Support.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _messagesScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  itemCount: _messages.length + (_isSending ? 1 : 0) + (_isManual && _ticket?.ticketStatus.toLowerCase() == 'resolved' ? 1 : 0),
                  itemBuilder: (context, index) => Align(
                    alignment: index < _messages.length && _messages[index].isFromCustomer ? Alignment.centerLeft : Alignment.centerRight,
                    child: _isManual && _ticket?.ticketStatus.toLowerCase() == 'resolved' && index == _messages.length + (_isSending ? 1 : 0)
                        ? Container(
                            width: double.infinity,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(20)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 18, color: Color(0xFF64748B)), SizedBox(width: 8), Text('This support chat has been resolved', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w700))]),
                            ),
                          )
                        : index >= _messages.length
                        ? Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                            child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: _messages[index].isFromCustomer ? const Color(0xFF0C4AA3) : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(_messages[index].isFromCustomer ? 4 : 18),
                                bottomRight: Radius.circular(_messages[index].isFromCustomer ? 18 : 4),
                              ),
                              border: _messages[index].isFromCustomer ? null : Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _messages[index].text,
                                  style: TextStyle(color: _messages[index].isFromCustomer ? Colors.white : const Color(0xFF0F172A), fontSize: 16, height: 1.45),
                                ),
                                if (!_messages[index].isFromCustomer && _messages[index].steps.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  ..._messages[index].steps.asMap().entries.map((entry) => Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 24,
                                              height: 24,
                                              alignment: Alignment.center,
                                              decoration: const BoxDecoration(color: Color(0xFF0C4AA3), shape: BoxShape.circle),
                                              child: Text('${entry.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(entry.value, style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF334155))),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                                ],
                                if (!_messages[index].isFromCustomer && _messages[index].actions.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _messages[index].actions.map((action) => ElevatedButton.icon(
                                          onPressed: () => widget.onNavigate(action),
                                          icon: Icon(_actionIcon(action), size: 16),
                                          label: Text(_actionLabel(action)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0C4AA3),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                          ),
                                        )).toList(),
                                  ),
                                ],
                                if (!_isManual && !_messages[index].isFromCustomer && _messages[index].needsStaff) ...[
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: _showManualChatPrompt,
                                    icon: const Icon(Icons.support_agent_rounded, size: 18),
                                    label: const Text('Talk to a staff member'),
                                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF0C4AA3), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FB),
            border: Border(top: BorderSide(color: Color(0xFFCBD5E1))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isManual && _ticket?.ticketStatus.toLowerCase() == 'resolved')
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _leaveResolvedChat,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Help Desk'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0C4AA3), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ),
              Row(
                children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageFocusNode,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  onTap: _handleResolvedInput,
                  enabled: !_isSending,
                  decoration: InputDecoration(
                    hintText: _isManual && _ticket?.ticketStatus.toLowerCase() == 'resolved' ? 'This chat is resolved' : _isManual ? 'Message customer service...' : 'Type a message...',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _isSending ? null : _sendMessage,
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF0C4AA3), foregroundColor: Colors.white, fixedSize: const Size(52, 52)),
                icon: const Icon(Icons.send_rounded),
                tooltip: 'Send message',
              ),
                ],
              ),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'trade_in': return 'Trade in your tech';
      case 'buy': return 'Shop smartphones';
      case 'rent': return 'Rent smartphones';
      case 'view_orders': return 'View my orders';
      case 'view_rentals': return 'View my rentals';
      case 'view_trade_in': return 'View trade-in requests';
      case 'compare_devices': return 'Compare devices (coming soon)';
      case 'test_device': return 'Test my device';
      default: return 'Open page';
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'trade_in': return Icons.autorenew_rounded;
      case 'buy': return Icons.shopping_bag_outlined;
      case 'rent': return Icons.calendar_month_outlined;
      case 'view_orders': return Icons.receipt_long_outlined;
      case 'view_rentals': return Icons.event_available_outlined;
      case 'view_trade_in': return Icons.phone_android_outlined;
      case 'compare_devices': return Icons.compare_arrows_rounded;
      case 'test_device': return Icons.phonelink_setup_rounded;
      default: return Icons.arrow_forward_rounded;
    }
  }
}

class _HelpDeskMessage {
  final String text;
  final bool isFromCustomer;
  final String intent;
  final List<String> actions;
  final List<String> steps;
  final bool needsStaff;

  const _HelpDeskMessage({required this.text, required this.isFromCustomer, this.intent = 'general', this.actions = const [], this.steps = const [], this.needsStaff = false});
}
