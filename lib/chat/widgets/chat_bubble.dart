import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/node.dart';
import '../helpers/bubble_time.dart';
import '../helpers/emoji.dart';
import 'action_row.dart';

// Пузырь чата — отрисовывает одну ноду (text или api) с сопутствующими
// элементами: ряд действий, индикатор сиблингов-ответвлений, метка
// времени/id. Работает и с «running» api-нодами (прогресс вместо текста).
class ChatBubble extends StatelessWidget {
  final Node node;
  final int siblingCount;
  final int siblingIndex;
  final bool isCollapsed;
  final int maxLines;
  final bool renderMarkdown;
  final bool hideEmoji;
  final bool showTime;
  final bool showId;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDeleteBranch;
  final VoidCallback? onMarkup;
  final VoidCallback? onCompress;
  final bool markupActive;

  const ChatBubble({
    super.key,
    required this.node,
    this.siblingCount = 1,
    this.siblingIndex = 0,
    this.isCollapsed = false,
    this.maxLines = 5,
    this.renderMarkdown = false,
    this.hideEmoji = false,
    this.showTime = false,
    this.showId = false,
    this.onDoubleTap,
    this.onSwipeLeft,
    this.onSwipeRight,
    required this.onCopy,
    this.onEdit,
    this.onBranch,
    this.onRetry,
    this.onSettings,
    this.onDeleteBranch,
    this.onMarkup,
    this.onCompress,
    this.markupActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = node.type == NodeType.text;
    final displayText = hideEmoji ? stripEmoji(node.text) : node.text;

    Widget content;
    if (!isUser) {
      switch (node.status) {
        case NodeStatus.idle:
        case NodeStatus.running when node.text.isEmpty:
          content = const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        case NodeStatus.error:
          content = Text(
            displayText,
            style: const TextStyle(color: Colors.red),
            maxLines: isCollapsed ? maxLines : null,
            overflow: isCollapsed ? TextOverflow.ellipsis : null,
          );
        default:
          if (!isCollapsed &&
              renderMarkdown &&
              node.status == NodeStatus.done &&
              node.text.isNotEmpty) {
            content = MarkdownBody(
              data: displayText,
              selectable: true,
              softLineBreak: true,
            );
          } else {
            content = Text(
              displayText,
              maxLines: isCollapsed ? maxLines : null,
              overflow: isCollapsed ? TextOverflow.ellipsis : null,
            );
          }
      }
    } else {
      content = Text(
        displayText,
        maxLines: isCollapsed ? maxLines : null,
        overflow: isCollapsed ? TextOverflow.ellipsis : null,
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) onSwipeLeft?.call();
          if (v > 200) onSwipeRight?.call();
        },
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? Colors.grey.shade200
                    : Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: content,
            ),
            if (siblingCount > 1)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      siblingCount,
                      (i) => Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == siblingIndex
                                  ? Colors.grey[700]
                                  : Colors.grey[300],
                            ),
                          )),
                ),
              ),
            ActionRow(
              onCopy: onCopy,
              onEdit: onEdit,
              onBranch: onBranch,
              onRetry: onRetry,
              onSettings: onSettings,
              onDeleteBranch: onDeleteBranch,
              onMarkup: onMarkup,
              onCompress: onCompress,
              markupActive: markupActive,
            ),
            if (showTime || showId)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTime)
                      Text(
                        formatBubbleTime(node.createdAt),
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    if (showTime && showId)
                      Text('  ·  ',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[500])),
                    if (showId)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: node.id));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Скопировано: ${node.id.substring(0, 6)}'),
                            duration: const Duration(seconds: 1),
                          ));
                        },
                        child: Text(
                          node.id.substring(0, 6),
                          style:
                              TextStyle(fontSize: 10, color: Colors.teal[400]),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
