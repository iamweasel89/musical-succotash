import 'package:flutter/material.dart';

// Ряд маленьких иконок-действий под чат-пузырём:
//   копировать, редактировать, ветвление, повторить, настройки,
//   удалить ветку, тезис, сжать.
// markupActive — визуальный маркер активного режима тезисов.
class ActionRow extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback? onDeleteBranch;
  final VoidCallback? onMarkup;
  final VoidCallback? onCompress;
  final bool markupActive;

  const ActionRow({
    super.key,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(icon: Icons.copy_outlined, tooltip: 'Копировать', onTap: onCopy),
        if (onEdit != null)
          _Btn(icon: Icons.edit_outlined, tooltip: 'Редактировать', onTap: onEdit!),
        if (onBranch != null)
          _Btn(icon: Icons.call_split, tooltip: 'Ветвление', onTap: onBranch!),
        if (onRetry != null)
          _Btn(icon: Icons.replay, tooltip: 'Повторить', onTap: onRetry!),
        if (onSettings != null)
          _Btn(icon: Icons.more_horiz, tooltip: 'Настройки', onTap: onSettings!),
        if (onDeleteBranch != null)
          _Btn(icon: Icons.delete_outline, tooltip: 'Удалить ветку', onTap: onDeleteBranch!, color: Colors.red[300]),
        if (onMarkup != null)
          _Btn(
            icon: Icons.format_quote_outlined,
            tooltip: 'Добавить тезис',
            onTap: onMarkup!,
            color: markupActive ? Colors.deepPurple[300] : null,
          ),
        if (onCompress != null)
          _Btn(icon: Icons.compress, tooltip: 'Сжать…', onTap: onCompress!),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _Btn({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onTap,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      color: color ?? Colors.grey[600],
    );
  }
}

// Toolbar button (larger, supports null = disabled). Используется в верхнем
// toolbar'е чата (свернуть/развернуть, undo/redo, и т.п.).
class ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const ToolBtn({super.key, required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onTap,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      color: onTap != null ? Colors.grey[700] : Colors.grey[400],
    );
  }
}
