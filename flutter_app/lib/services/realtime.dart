import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'backend.dart';

/// Keeps realtime subscriptions alive for the signed-in user:
///  - new direct messages (postgres_changes on messages.receiver_id)
///  - group messages (broadcast on group-<id>)
/// Screens listen to the streams below.
class Realtime {
  Realtime._();
  static final Realtime instance = Realtime._();

  final _dmController = StreamController<Message>.broadcast();
  final _groupController = StreamController<Message>.broadcast();

  /// Direct messages received by me (includes messages from every partner).
  Stream<Message> get directMessages => _dmController.stream;

  /// Group messages sent by others (realtime broadcast).
  Stream<Message> get groupMessages => _groupController.stream;

  RealtimeChannel? _dmChannel;
  final Map<String, RealtimeChannel> _groupChannels = {};

  void startDirect(String myId) {
    stopDirect();
    _dmChannel = Backend.db
        .channel('messages-channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty || row['group_id'] != null) return; // groups arrive via broadcast
            _dmController.add(Message.fromJson(row));
          },
        )
        .subscribe();
  }

  void stopDirect() {
    final ch = _dmChannel;
    if (ch != null) Backend.db.removeChannel(ch);
    _dmChannel = null;
  }

  void syncGroups(List<Group> groups) {
    final ids = groups.map((g) => g.id).toSet();
    for (final id in _groupChannels.keys.toList()) {
      if (!ids.contains(id)) {
        Backend.db.removeChannel(_groupChannels.remove(id)!);
      }
    }
    for (final id in ids) {
      if (_groupChannels.containsKey(id)) continue;
      final ch = Backend.db.channel('group-$id').onBroadcast(
        event: 'new-message',
        callback: (payload) {
          if (payload.isEmpty) return;
          _groupController.add(Message.fromJson(Map<String, dynamic>.from(payload)));
        },
      );
      ch.subscribe();
      _groupChannels[id] = ch;
    }
  }

  void sendGroupMessage(String groupId, Message message) {
    final ch = _groupChannels[groupId];
    if (ch == null) return;
    ch.sendBroadcastMessage(event: 'new-message', payload: {
      'id': message.id,
      'sender_id': message.senderId,
      'receiver_id': null,
      'group_id': groupId,
      'content': message.content,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'status': message.status,
    });
  }

  void stopGroups() {
    for (final ch in _groupChannels.values) {
      Backend.db.removeChannel(ch);
    }
    _groupChannels.clear();
  }

  void stopAll() {
    stopDirect();
    stopGroups();
  }
}
