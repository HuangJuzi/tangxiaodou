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
}
