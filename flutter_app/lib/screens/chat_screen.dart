import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ai.dart';
import '../services/backend.dart';
import '../services/calls.dart';
import '../services/realtime.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'group_screens.dart';

const _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// 1:1 or group chat (index.html #screen-chat).
class ChatScreen extends StatefulWidget {
  final Profile? partner;
  final Group? group;

  const ChatScreen.direct({super.key, required Profile partner})
      : partner = partner,
        group = null;

  const ChatScreen.group({super.key, required Group group})
      : group = group,
        partner = null;

  bool get isGroup => group != null;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _app = AppState.instance;
  final _speech = stt.SpeechToText();

  List<Message> _messages = [];
  bool _sending = false;
  bool _listening = false;
  bool _partnerTyping = false;
  Group? _group;
  RealtimeChannel? _typingChannel;
  Timer? _typingStop;
  StreamSubscription<Message>? _dmSub;
  StreamSubscription<Message>? _groupSub;
  final Map<String, String> _translations = {};
  final Set<String> _translating = {};
  final Set<String> _shownTranslation = {};

  String get _myId => _app.me!.id;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _load();
    if (!widget.isGroup) {
      _setupTyping();
      _dmSub = Realtime.instance.directMessages.listen(_onDirect);
    } else {
      _groupSub = Realtime.instance.groupMessages.listen(_onGroup);
    }
  }

  @override
  void dispose() {
    _typingStop?.cancel();
    if (_typingChannel != null) Backend.db.removeChannel(_typingChannel!);
    _dmSub?.cancel();
    _groupSub?.cancel();
    _speech.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ----- data -----

  Future<void> _load() async {
    final me = _app.me;
    if (me == null) return;
    try {
      final msgs = widget.isGroup
          ? (await Backend.groupMessages([_group!.id])).toList()
          : await Backend.dmMessages(me.id, widget.partner!.id);
      if (!mounted) return;
      setState(() => _messages = msgs);
      if (!widget.isGroup) {
        await Backend.markRead(widget.partner!.id, me.id);
      }
    } catch (_) {}
  }

  void _onDirect(Message m) {
    if (widget.isGroup || m.senderId != widget.partner!.id) return;
    if (!mounted) return;
    setState(() => _messages = [..._messages, m]);
    Backend.markRead(widget.partner!.id, _myId);
  }

  void _onGroup(Message m) {
    if (!widget.isGroup || m.groupId != _group!.id) return;
    if (!mounted) return;
    if (_messages.any((x) => x.id != null && x.id == m.id)) return;
    setState(() => _messages = [..._messages, m]);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _sendTyping(false);
    _input.clear();
    await _sendContent(text);
  }

  /// Sends text or an image (data URL). Shared with the Generate screen.
  Future<void> _sendContent(String content) async {
    setState(() => _sending = true);
    try {
      final msg = await Backend.insertMessage(
        senderId: _myId,
        receiverId: widget.isGroup ? null : widget.partner!.id,
        groupId: widget.isGroup ? _group!.id : null,
        content: content,
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      if (widget.isGroup) Realtime.instance.sendGroupMessage(_group!.id, msg);
    } catch (_) {
      showToast('Send failed', error: true);
      if (!widget.isGroup) _input.text = content;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ----- typing indicator (DM only) -----

  void _setupTyping() {
    final ids = [_myId, widget.partner!.id]..sort();
    _typingChannel = Backend.db.channel('typing-${ids.join('-')}').onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (payload['from'] != _myId && mounted) {
          setState(() => _partnerTyping = payload['isTyping'] == true);
        }
      },
    );
    _typingChannel!.subscribe();
  }

  void _sendTyping(bool isTyping) {
    _typingChannel?.sendBroadcastMessage(event: 'typing', payload: {'from': _myId, 'isTyping': isTyping});
  }

  void _onComposerChanged(String _) {
    if (widget.isGroup) return;
    _sendTyping(true);
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), () => _sendTyping(false));
  }

  // ----- voice input -----

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      onError: (_) => setState(() => _listening = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') setState(() => _listening = false);
      },
    );
    if (!ok) {
      showToast('Voice input is not available on this device', error: true);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        _input.text = r.recognizedWords;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      },
    );
  }

  // ----- translation & reactions -----

  Future<void> _translate(Message m) async {
    if (_shownTranslation.contains(m.id)) {
      setState(() => _shownTranslation.remove(m.id));
      return;
    }
    final cached = _translations[m.id];
    if (cached != null) {
      setState(() => _shownTranslation.add(m.id ?? ""));
      return;
    }
    setState(() => _translating.add(m.id ?? ''));
    try {
      final out = await AiService.translate(m.content, _app.translateLang);
      _translations[m.id ?? ''] = out;
      if (mounted) setState(() => _shownTranslation.add(m.id ?? ''));
    } catch (_) {
      showToast('Translate failed', error: true);
    } finally {
      if (mounted) setState(() => _translating.remove(m.id ?? ''));
    }
  }

  Future<void> _react(Message m) async {
    final emoji = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              for (final e in _reactionEmojis)
                InkWell(
                  onTap: () => Navigator.pop(ctx, e),
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 28))),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null || m.id == null) return;
    final newValue = m.reaction == emoji ? null : emoji;
    try {
      await Backend.setReaction(m.id!, newValue);
      if (!mounted) return;
      setState(() => _messages = [
            for (final x in _messages) x.id == m.id ? x.withReaction(newValue) : x,
          ]);
    } catch (_) {
      showToast('Add a "reaction" text column to your messages table to enable reactions', error: true);
    }
  }

  // ----- UI -----

  String _senderName(String senderId) {
    if (senderId == _myId) return 'You';
    if (!widget.isGroup) return '@${widget.partner!.username}';
    for (final m in _group!.members) {
      if (m.id == senderId) return m.name;
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isGroup ? _group!.name : widget.partner!.name;
    final subtitle = widget.isGroup
        ? '${_group!.members.length} members'
        : _partnerTyping
            ? 'typing…'
            : widget.partner!.isOnline
                ? 'Online'
                : 'Offline';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: widget.isGroup ? _openGroupInfo : null,
          child: Row(children: [
            Avatar(
              letter: widget.isGroup ? '' : widget.partner!.initial,
              group: widget.isGroup,
              size: 40,
              online: !widget.isGroup && widget.partner!.isOnline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: subtitle == 'Online' || subtitle == 'typing…' ? AppColors.accent : AppColors.textFaint,
                      )),
                ],
              ),
            ),
          ]),
        ),
        actions: [
          if (!widget.isGroup) ...[
            IconButton(
              tooltip: 'Audio call',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => _startCall(video: false),
            ),
            IconButton(
              tooltip: 'Video call',
              icon: const Icon(Icons.videocam_outlined),
              onPressed: () => _startCall(video: true),
            ),
          ] else
            IconButton(
              tooltip: 'Group info',
              icon: const Icon(Icons.info_outline),
              onPressed: _openGroupInfo,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          _buildComposer(),
        ],
      ),
    );
  }

  Future<void> _startCall({required bool video}) async {
    final err = await CallService.instance.startCall(peer: widget.partner!, video: video);
    if (err != null) showToast(err, error: true);
  }

  Future<void> _openGroupInfo() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupInfoScreen(group: _group!)));
    final refreshed = AppState.instance.groups.where((g) => g.id == _group!.id).toList();
    if (refreshed.isNotEmpty && mounted) setState(() => _group = refreshed.first);
  }

  Widget _buildList() {
    if (_messages.isEmpty) {
      return const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', subtitle: 'Say hello 👋');
    }
    // Build entries (date chips + messages), newest at the bottom.
    final entries = <Object>[];
    String? lastDay;
    for (final m in _messages) {
      final day = '${m.createdAt.year}-${m.createdAt.month}-${m.createdAt.day}';
      if (day != lastDay) {
        entries.add(m.createdAt);
        lastDay = day;
      }
      entries.add(m);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        if (e is DateTime) {
          final now = DateTime.now();
          final isToday = e.year == now.year && e.month == now.month && e.day == now.day;
          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(20)),
              child: Text(isToday ? 'Today' : '${e.day}/${e.month}/${e.year}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ),
          );
        }
        return _bubble(e as Message);
      },
    );
  }

  Widget _bubble(Message m) {
    final isMine = m.senderId == _myId;
    final id = m.id ?? '';
    final showTranslated = _shownTranslation.contains(id);
    final translated = _translations[id];

    final content = <Widget>[];
    if (!isMine && widget.isGroup) {
      content.add(Text(_senderName(m.senderId),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textFaint)));
    }
    if (m.isImage && m.imageBytes != null) {
      content.add(ImageBubble(bytes: m.imageBytes!));
    } else {
      content.add(Text(m.content,
          style: TextStyle(
            color: isMine ? AppColors.onAccent : null,
            fontSize: 14.5,
            fontWeight: isMine ? FontWeight.w500 : FontWeight.w400,
          )));
    }
    if (showTranslated && translated != null) {
      content.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(translated, style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textDim)),
      ));
    }
    if (!isMine && !m.isImage && _app.translateLang.isNotEmpty) {
      final busy = _translating.contains(id);
      content.add(GestureDetector(
        onTap: busy ? null : () => _translate(m),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            busy ? 'Translating…' : (showTranslated ? 'Show original' : 'Translate'),
            style: const TextStyle(fontSize: 11.5, color: AppColors.blue, fontWeight: FontWeight.w600),
          ),
        ),
      ));
    }
    content.add(Align(
      alignment: Alignment.centerRight,
      child: Text(
        formatClock(m.createdAt) + (isMine ? ' ✓✓' : ''),
        style: TextStyle(fontSize: 10, color: isMine ? AppColors.onAccent.withValues(alpha: 0.7) : AppColors.textFaint),
      ),
    ));

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
      decoration: BoxDecoration(
        color: isMine ? null : AppColors.bgCard2,
        gradient: isMine ? const LinearGradient(colors: [AppColors.accentDark, AppColors.accent]) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: content),
    );

    final withReaction = Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onLongPress: m.id == null ? null : () => _react(m),
          child: bubble,
        ),
        if (m.reaction != null)
          Positioned(
            bottom: -10,
            right: isMine ? null : 6,
            left: isMine ? 6 : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(m.reaction!, style: const TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: m.reaction != null ? 12 : 4, top: 2),
        child: withReaction,
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: const Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        child: Row(children: [
          IconButton(
            tooltip: 'Voice input',
            icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? AppColors.danger : null),
            onPressed: _toggleVoice,
          ),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              onChanged: _onComposerChanged,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ]),
      ),
    );
  }
}
