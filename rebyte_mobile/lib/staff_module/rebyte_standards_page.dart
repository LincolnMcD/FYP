import 'package:flutter/material.dart';

import 'services/staff_standard_service.dart';

class ReByteStandardsPage extends StatefulWidget {
  final VoidCallback onExit;

  const ReByteStandardsPage({super.key, required this.onExit});

  @override
  State<ReByteStandardsPage> createState() => _ReByteStandardsPageState();
}

class _ReByteStandardsPageState extends State<ReByteStandardsPage> {
  late Future<List<Map<String, dynamic>>> _standardsFuture;
  String? _selectedStandardId;

  @override
  void initState() {
    super.initState();
    _standardsFuture = StaffStandardService.getStandards();
  }

  void _reload() {
    final nextLoad = StaffStandardService.getStandards();
    setState(() {
      _standardsFuture = nextLoad;
    });
  }

  Future<void> _refresh() async {
    final nextLoad = StaffStandardService.getStandards();
    setState(() {
      _standardsFuture = nextLoad;
    });
    try {
      await nextLoad;
    } catch (_) {}
  }

  void _openStandard(Map<String, dynamic> summary) {
    final id = summary['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _selectedStandardId = id);
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = _selectedStandardId;
    if (selectedId != null) {
      return _ReByteStandardDetailPage(
        key: ValueKey(selectedId),
        standardId: selectedId,
        onBack: () => setState(() => _selectedStandardId = null),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 18, 4),
          child: Row(
            children: [
              _StandardBackButton(label: 'Back to staff home', onPressed: widget.onExit),
              const Expanded(
                child: Text('ReByte Standard', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _standardsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _StandardsMessage(
                  icon: Icons.cloud_off_outlined,
                  message: snapshot.error.toString().replaceFirst('Exception: ', ''),
                  buttonLabel: 'Try again',
                  onPressed: _reload,
                );
              }
              final standards = snapshot.data ?? [];
              if (standards.isEmpty) {
                return const _StandardsMessage(
                  icon: Icons.menu_book_outlined,
                  message: 'No standards are available yet.',
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: standards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final standard = standards[index];
                    final title = standard['title']?.toString().trim() ?? '';
                    final description = standard['description']?.toString().trim() ?? '';
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openStandard(standard),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title.isEmpty ? 'Untitled standard' : title,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Text(description, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.45)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReByteStandardDetailPage extends StatefulWidget {
  final String standardId;
  final VoidCallback onBack;

  const _ReByteStandardDetailPage({super.key, required this.standardId, required this.onBack});

  @override
  State<_ReByteStandardDetailPage> createState() => _ReByteStandardDetailPageState();
}

class _ReByteStandardDetailPageState extends State<_ReByteStandardDetailPage> {
  late Future<Map<String, dynamic>> _standardFuture;

  @override
  void initState() {
    super.initState();
    _standardFuture = StaffStandardService.getStandard(widget.standardId);
  }

  void _reload() {
    final nextLoad = StaffStandardService.getStandard(widget.standardId);
    setState(() {
      _standardFuture = nextLoad;
    });
  }

  List<String> _sectionImages(Map<String, dynamic> section) {
    final raw = section['images'];
    if (raw is List) return raw.map((value) => value.toString()).where((value) => value.trim().isNotEmpty).toList();
    final oneImage = section['imageUrl'] ?? section['image'];
    if (oneImage is String && oneImage.trim().isNotEmpty) return [oneImage.trim()];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 18, 4),
          child: Row(
            children: [
              _StandardBackButton(label: 'Back to all standards', onPressed: widget.onBack),
              const Expanded(
                child: Text(
                  'Standard Detail',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
      future: _standardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _StandardsMessage(
            icon: Icons.cloud_off_outlined,
            message: snapshot.error.toString().replaceFirst('Exception: ', ''),
            buttonLabel: 'Try again',
            onPressed: _reload,
          );
        }
        final standard = snapshot.data ?? {};
        final sections = standard['sections'] is List
            ? (standard['sections'] as List).whereType<Map>().map((section) => Map<String, dynamic>.from(section)).toList()
            : <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DetailTextCard(title: standard['title']?.toString() ?? '', description: standard['description']?.toString() ?? ''),
            const SizedBox(height: 14),
            ...sections.asMap().entries.map((entry) {
              final index = entry.key;
              final section = entry.value;
              final title = section['title']?.toString().trim() ?? '';
              final sectionLabel = title.isEmpty ? 'Section ${index + 1}' : title;
              final description = (section['instructions'] ?? section['description'] ?? section['sectionDescription'])?.toString().trim() ?? '';
              final images = _sectionImages(section);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${index + 1}. $sectionLabel',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      if (images.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SectionImageCarousel(images: images),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(description, style: const TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.5)),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
          ),
        ),
      ],
    );
  }
}

class _SectionImageCarousel extends StatefulWidget {
  final List<String> images;

  const _SectionImageCarousel({required this.images});

  @override
  State<_SectionImageCarousel> createState() => _SectionImageCarouselState();
}

class _SectionImageCarouselState extends State<_SectionImageCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.images[index],
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF1F5F9),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8), size: 36),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.images.length, (index) {
            final isCurrent = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: isCurrent ? 8 : 6,
              height: isCurrent ? 8 : 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent ? const Color(0xFF0F3D8C) : const Color(0xFFCBD5E1),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StandardBackButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _StandardBackButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF0F172A)),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
      ),
    );
  }
}

class _DetailTextCard extends StatelessWidget {
  final String title;
  final String description;

  const _DetailTextCard({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
        if (description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.5)),
        ],
      ]),
    );
  }
}

class _StandardsMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _StandardsMessage({required this.icon, required this.message, this.buttonLabel, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B), height: 1.4)),
          if (buttonLabel != null && onPressed != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onPressed, child: Text(buttonLabel!)),
          ],
        ]),
      ),
    );
  }
}
