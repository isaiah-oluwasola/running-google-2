import 'dart:convert';
import 'dart:typed_data';

class Profile {
  final String id;
  final String name;
  final String username;
  final String? email;
  final bool isOnline;

  const Profile({
    required this.id,
    required this.name,
    required this.username,
    this.email,
    this.isOnline = false,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'].toString(),
        name: (j['name'] as String?) ?? 'User',
        username: (j['username'] as String?) ?? 'user',
        email: j['email'] as String?,
        isOnline: j['is_online'] == true,
      );

  String get initial => (name.isNotEmpty ? name[0] : 'U').toUpperCase();
}

class Message {
  final String? id;
  final String senderId;
  final String? receiverId;
  final String? groupId;
  final String content;
  final DateTime createdAt;
  final String status;
  final String? reaction;

  const Message({
    this.id,
    required this.senderId,
    this.receiverId,
    this.groupId,
    required this.content,
    required this.createdAt,
    this.status = 'sent',
    this.reaction,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id']?.toString(),
        senderId: j['sender_id'].toString(),
        receiverId: j['receiver_id']?.toString(),
        groupId: j['group_id']?.toString(),
        content: (j['content'] as String?) ?? '',
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        status: (j['status'] as String?) ?? 'sent',
        reaction: j['reaction'] as String?,
      );

  bool get isImage => content.startsWith('data:image');

  Message withReaction(String? emoji) => Message(
        id: id,
        senderId: senderId,
        receiverId: receiverId,
        groupId: groupId,
        content: content,
        createdAt: createdAt,
        status: status,
        reaction: emoji,
      );

  Uint8List? get imageBytes {
    if (!isImage) return null;
    try {
      return base64Decode(content.substring(content.indexOf(',') + 1));
    } catch (_) {
      return null;
    }
  }
}

class Group {
  final String id;
  final String name;
  final String createdBy;
  final DateTime? createdAt;
  final List<Profile> members;

  const Group({
    required this.id,
    required this.name,
    required this.createdBy,
    this.createdAt,
    this.members = const [],
  });

  factory Group.fromJson(Map<String, dynamic> j, {List<Profile> members = const []}) => Group(
        id: j['id'].toString(),
        name: (j['name'] as String?) ?? 'Group',
        createdBy: (j['created_by'] ?? '').toString(),
        createdAt: j['created_at'] == null ? null : DateTime.tryParse(j['created_at'] as String),
        members: members,
      );

  Group copyWith({List<Profile>? members}) => Group(
        id: id,
        name: name,
        createdBy: createdBy,
        createdAt: createdAt,
        members: members ?? this.members,
      );
}

/// One row in the chats list: either a 1:1 conversation or a group.
class ChatItem {
  final Profile? partner;
  final Group? group;
  final Message? lastMessage;
  final int unread;

  const ChatItem({this.partner, this.group, this.lastMessage, this.unread = 0});

  bool get isGroup => group != null;

  DateTime get sortTime => lastMessage?.createdAt ?? group?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}
