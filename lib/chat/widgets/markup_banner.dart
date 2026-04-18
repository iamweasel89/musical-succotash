import 'package:flutter/material.dart';

// Баннер «режим тезисов активен» в верхней части чата.
// Показывает количество накопленных тезисов, кнопку «Открыть →» к мастерской
// тезисов и крестик для выхода из режима.
class MarkupBanner extends StatelessWidget {
  final int count;
  final VoidCallback onExit;
  final VoidCallback onOpen;
  const MarkupBanner({
    super.key,
    required this.count,
    required this.onExit,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.deepPurple[50],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.format_quote_outlined,
              size: 16, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text('Тезисы · $count',
              style:
                  const TextStyle(fontSize: 13, color: Colors.deepPurple)),
          const Spacer(),
          GestureDetector(
            onTap: onOpen,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('Открыть →',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          GestureDetector(
            onTap: onExit,
            child: const Icon(Icons.close,
                size: 18, color: Colors.deepPurple),
          ),
        ],
      ),
    );
  }
}
