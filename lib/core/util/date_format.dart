/// Человекочитаемая дата для карточек списка.
///
/// Без пакета intl: нужен один формат, а лишняя зависимость с локалями
/// ради него не оправдана.
String formatNoteDate(DateTime timestamp) {
  final local = timestamp.toLocal();
  final difference = DateTime.now().difference(local);

  if (difference.inMinutes < 1) return 'только что';
  if (difference.inHours < 1) return '${difference.inMinutes} мин назад';
  if (difference.inDays < 1) return '${difference.inHours} ч назад';
  if (difference.inDays < 7) return '${difference.inDays} дн назад';

  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}
