import 'package:uuid/uuid.dart';

enum MessageRole { user, ai }

class Message {
  final String id;
  final MessageRole role;
  String content;
  bool isStreaming;
  final DateTime createdAt;

  Message({
    String? id,
    required this.role,
    required this.content,
    this.isStreaming = false,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role == MessageRole.user ? 'user' : 'ai',
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: (json['role'] as String) == 'user' ? MessageRole.user : MessageRole.ai,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
