/// Одна страница списка, как её отдаёт бэкенд.
///
/// Общая модель для заметок и любых будущих списков: поля совпадают
/// с `PageResponse` на сервере.
class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
    required this.hasNext,
  });

  final List<T> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool hasNext;

  static PageResult<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) itemFromJson,
  ) {
    final rawItems = json['items'];
    return PageResult<T>(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(itemFromJson)
              .toList(growable: false)
          : const [],
      page: json['page'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
      totalElements: json['totalElements'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 0,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}
