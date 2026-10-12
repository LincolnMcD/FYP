import 'package:flutter/material.dart';

class SearchableSelectionSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final List<String> items;
  final Future<List<String>> Function()? asyncItemsLoader;
  final String? selectedItem;
  final Map<String, Color>? itemColors; // Optional color swatches for colors
  final bool allowCustomWriteIn;

  const SearchableSelectionSheet({
    super.key,
    required this.title,
    this.searchHint = 'Search...',
    this.items = const [],
    this.asyncItemsLoader,
    this.selectedItem,
    this.itemColors,
    this.allowCustomWriteIn = true,
  });

  static Future<String?> show({
    required BuildContext context,
    required String title,
    String searchHint = 'Search...',
    List<String> items = const [],
    Future<List<String>> Function()? asyncItemsLoader,
    String? selectedItem,
    Map<String, Color>? itemColors,
    bool allowCustomWriteIn = true,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchableSelectionSheet(
        title: title,
        searchHint: searchHint,
        items: items,
        asyncItemsLoader: asyncItemsLoader,
        selectedItem: selectedItem,
        itemColors: itemColors,
        allowCustomWriteIn: allowCustomWriteIn,
      ),
    );
  }

  @override
  State<SearchableSelectionSheet> createState() => _SearchableSelectionSheetState();
}

class _SearchableSelectionSheetState extends State<SearchableSelectionSheet> {
  late TextEditingController _searchController;
  late List<String> _allItems;
  late List<String> _filteredItems;
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _allItems = List.from(widget.items);
    _filteredItems = List.from(widget.items);

    if (widget.asyncItemsLoader != null) {
      _isLoading = _allItems.isEmpty;
      _loadAsyncItems();
    }
  }

  Future<void> _loadAsyncItems() async {
    try {
      final loaded = await widget.asyncItemsLoader!();
      if (!mounted) return;
      setState(() {
        _allItems = loaded;
        _isLoading = false;
        _applyFilter(_searchQuery);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
      _applyFilter(_searchQuery);
    });
  }

  void _applyFilter(String query) {
    if (query.isEmpty) {
      _filteredItems = List.from(_allItems);
    } else {
      _filteredItems = _allItems.where((item) {
        return item.toLowerCase().contains(query);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxHeight = mediaQuery.size.height * 0.85;

    final hasExactMatch = _filteredItems.any((e) => e.toLowerCase() == _searchQuery);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (_allItems.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_allItems.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0C5AD2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 22),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                autofocus: false,
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  hintText: widget.searchHint,
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Divider
          const Divider(color: Color(0xFFF1F5F9), height: 1),

          // Content area
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0C5AD2)),
                          SizedBox(height: 16),
                          Text(
                            'Loading library catalogue...',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : _filteredItems.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No results for "${_searchController.text}"',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                            ),
                            if (widget.allowCustomWriteIn && _searchController.text.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context, _searchController.text.trim());
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0C5AD2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.check, size: 16),
                                label: Text('Use "${_searchController.text.trim()}"'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                        itemCount: _filteredItems.length +
                            (widget.allowCustomWriteIn &&
                                    _searchQuery.isNotEmpty &&
                                    !hasExactMatch
                                ? 1
                                : 0),
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Color(0xFFF8FAFC),
                          indent: 20,
                          endIndent: 20,
                        ),
                        itemBuilder: (context, index) {
                          if (index == _filteredItems.length) {
                            // Custom search item option
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                              leading: const Icon(Icons.add_circle_outline, color: Color(0xFF0C5AD2)),
                              title: Text(
                                'Use "${_searchController.text.trim()}"',
                                style: const TextStyle(
                                  color: Color(0xFF0C5AD2),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context, _searchController.text.trim());
                              },
                            );
                          }

                          final item = _filteredItems[index];
                          final isSelected = item == widget.selectedItem;
                          final swatchColor = widget.itemColors?[item];

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                            leading: swatchColor != null
                                ? Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: swatchColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey.shade400,
                                        width: 1.2,
                                      ),
                                    ),
                                  )
                                : null,
                            title: Text(
                              item,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF1E293B),
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Color(0xFF0C5AD2), size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(context, item);
                            },
                          );
                        },
                      ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
}
