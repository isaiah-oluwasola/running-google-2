import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';

/// Data access for profiles, groups, and messages. Mirrors the queries in index.html.
class Backend {
  Backend._();

  static SupabaseClient get db => Supabase.instance.client;

  static Future<void> init() => Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );

  // ---------- Profiles ----------

  static Future<Profile?> fetchProfile(String uid) async {
    final row = await db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  static Future<bool> usernameTaken(String username) async {
    final row = await db.from('profiles').select('username').eq('username', username).maybeSingle();
    return row != null;
  }

  static Future<Profile> createProfile({
    required String id,
    required String name,
    required String username,
    String? email,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await db
        .from('profiles')
        .insert([
          {
            'id': id,
            'name': name,
            'username': username,
            'email': email,
            'is_online': true,
            'last_seen': now,
            'created_at': now,
          }
        ])
        .select()
        .single();
    return Profile.fromJson(row);
  }

  static Future<void> setOnline(String uid, bool online) async {
    await db.from('profiles').update({
      'is_online': online,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }

  static Future<Profile> updateName(String uid, String name) async {
    final row = await db.from('profiles').update({'name': name}).eq('id', uid).select().single();
    return Profile.fromJson(row);
  }

  static Future<List<Profile>> searchUsers(String myId, String term, {bool byEmail = false}) async {
    var query = db.from('profiles').select().neq('id', myId);
    query = byEmail ? query.ilike('email', '%$term%') : query.ilike('username', '%$term%');
    final rows = await query.limit(20);
    return rows.map(Profile.fromJson).toList();
  }

  // ---------- Groups ----------

  static Future<List<Group>> loadMyGroups(String myId) async {
    final memberships = await db.from('group_members').select('group_id').eq('user_id', myId);
    final groupIds = memberships.map((m) => m['group_id']).toList();
    if (groupIds.isEmpty) return [];

    final groups = await db.from('groups').select().inFilter('id', groupIds);
    final allMembers = await db.from('group_members').select('group_id, user_id').inFilter('group_id', groupIds);
    final memberIds = allMembers.map((m) => m['user_id']).toSet().toList();
    final profiles = memberIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await db.from('profiles').select().inFilter('id', memberIds);
    final profileById = {for (final p in profiles) p['id'].toString(): Profile.fromJson(p)};

    return groups.map((g) {
      final gid = g['id'].toString();
      final members = allMembers
          .where((m) => m['group_id'].toString() == gid)
          .map((m) => profileById[m['user_id'].toString()])
          .whereType<Profile>()
          .toList();
      return Group.fromJson(g, members: members);
    }).toList();
  }

  static Future<Group> createGroup({
    required String name,
    required String myId,
    required List<String> memberIds,
  }) async {
    final row = await db
        .from('groups')
        .insert([
          {'name': name, 'created_by': myId, 'created_at': DateTime.now().toUtc().toIso8601String()}
        ])
        .select()
        .single();
    final rows = [
      {'group_id': row['id'], 'user_id': myId},
      for (final id in memberIds) {'group_id': row['id'], 'user_id': id},
    ];
    await db.from('group_members').insert(rows);
    return Group.fromJson(row);
  }

  static Future<void> addMembers(String groupId, List<String> userIds) async {
    await db.from('group_members').insert([
      for (final id in userIds) {'group_id': groupId, 'user_id': id},
    ]);
  }

  static Future<void> leaveGroup(String groupId, String myId) async {
    await db.from('group_members').delete().eq('group_id', groupId).eq('user_id', myId);
  }

  // ---------- Messages ----------

  static String _dmFilter(String a, String b) =>
      'and(sender_id.eq.$a,receiver_id.eq.$b),and(sender_id.eq.$b,receiver_id.eq.$a)';

  static Future<List<Message>> dmMessages(String myId, String partnerId) async {
    final rows = await db
        .from('messages')
        .select()
        .or(_dmFilter(myId, partnerId))
        .isFilter('group_id', null)
        .order('created_at', ascending: true);
    return rows.map(Message.fromJson).toList();
  }

  static Future<List<Message>> allDmMessages(String myId) async {
    final rows = await db
        .from('messages')
        .select()
        .or('sender_id.eq.$myId,receiver_id.eq.$myId')
        .isFilter('group_id', null)
        .order('created_at', ascending: true);
    return rows.map(Message.fromJson).toList();
  }

  static Future<List<Message>> groupMessages(List<String> groupIds) async {
    if (groupIds.isEmpty) return [];
    final rows = await db
        .from('messages')
        .select()
        .inFilter('group_id', groupIds)
        .order('created_at', ascending: true);
    return rows.map(Message.fromJson).toList();
  }

  static Future<Message> insertMessage({
    required String senderId,
    String? receiverId,
    String? groupId,
    required String content,
  }) async {
    final row = await db
        .from('messages')
        .insert([
          {
            'sender_id': senderId,
            'receiver_id': receiverId,
            'group_id': groupId,
            'content': content,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'sent',
          }
        ])
        .select()
        .single();
    return Message.fromJson(row);
  }

  static Future<void> markRead(String partnerId, String myId) async {
    try {
      await db
          .from('messages')
          .update({'status': 'read'})
          .eq('sender_id', partnerId)
          .eq('receiver_id', myId)
          .neq('status', 'read');
    } catch (_) {}
  }

  static Future<void> setReaction(String messageId, String? emoji) async {
    await db.from('messages').update({'reaction': emoji}).eq('id', messageId);
  }

  /// Creates the opening "Hi" message if no DM exists yet (same as startChat in index.html).
  static Future<void> ensureConversation(String myId, Profile other) async {
    final existing = await db
        .from('messages')
        .select('id')
        .or(_dmFilter(myId, other.id))
        .limit(1);
    if (existing.isEmpty) {
      await db.from('messages').insert([
        {
          'sender_id': myId,
          'receiver_id': other.id,
          'content': "Hi ${other.name}! Let's connect on HeyApp 👋",
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'sent',
        }
      ]);
    }
  }

  /// Builds the chats list (DMs + groups), newest first, like loadChats() in index.html.
  static Future<List<ChatItem>> loadChatItems(String myId, List<Group> groups) async {
    final messages = await allDmMessages(myId);
    final partnerIds = <String>{};
    for (final m in messages) {
      if (m.senderId != myId) partnerIds.add(m.senderId);
      if (m.receiverId != null && m.receiverId != myId) partnerIds.add(m.receiverId!);
    }
    final partners = partnerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await db.from('profiles').select().inFilter('id', partnerIds.toList());
    final profileById = {for (final p in partners) p['id'].toString(): Profile.fromJson(p)};

    final items = <ChatItem>[];
    for (final pid in partnerIds) {
      final partner = profileById[pid];
      if (partner == null) continue;
      final msgs = messages
          .where((m) =>
              (m.senderId == myId && m.receiverId == pid) || (m.senderId == pid && m.receiverId == myId))
          .toList();
      final unread = msgs.where((m) => m.receiverId == myId && m.status != 'read').length;
      items.add(ChatItem(partner: partner, lastMessage: msgs.isEmpty ? null : msgs.last, unread: unread));
    }

    if (groups.isNotEmpty) {
      final groupMsgs = await groupMessages(groups.map((g) => g.id).toList());
      for (final g in groups) {
        final msgs = groupMsgs.where((m) => m.groupId == g.id).toList();
        items.add(ChatItem(group: g, lastMessage: msgs.isEmpty ? null : msgs.last));
      }
    }

    items.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return items;
  }
}
