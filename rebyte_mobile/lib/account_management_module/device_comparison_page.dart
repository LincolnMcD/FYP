import 'package:flutter/material.dart';

import '../device_tradein_module/data/phone_brands_data.dart';
import '../device_tradein_module/services/trade_in_service.dart';
import '../product_purchase_module/checkout_page.dart';
import '../product_purchase_module/models/cart_item_model.dart';
import '../product_purchase_module/models/product_model.dart';
import '../product_purchase_module/services/shop_service.dart';
import 'welcome_page.dart';

const _blue = Color(0xFF0C4AA3);
const _surface = Color(0xFFF2F3F5);
const _border = Color(0xFFC4C8D8);
const _ink = Color(0xFF102346);

class DeviceComparisonPage extends StatefulWidget {
  const DeviceComparisonPage({
    super.key,
    required this.onBack,
    required this.isLoggedIn,
    this.email,
    this.name,
    this.initialProduct,
  });

  final VoidCallback onBack;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final ProductModel? initialProduct;

  static void clearSelections() {
    for (final selection in _selections.values) {
      selection.value = [];
    }
    _selections.clear();
  }

  static final _selections = <String, ValueNotifier<List<ProductModel>>>{};

  @override
  State<DeviceComparisonPage> createState() => _DeviceComparisonPageState();
}

class _DeviceComparisonPageState extends State<DeviceComparisonPage> {
  final _specs = <String, Map<String, dynamic>>{};
  late final _selection = DeviceComparisonPage._selections.putIfAbsent(
    widget.email?.trim().toLowerCase() ?? '',
    () => ValueNotifier<List<ProductModel>>([]),
  );
  List<ProductModel> get _devices => _selection.value;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialProduct;
    _selection.addListener(_selectionChanged);
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _includeDevices([initial]);
      });
    }
    _selectionChanged();
  }

  @override
  void dispose() {
    _selection.removeListener(_selectionChanged);
    super.dispose();
  }

  final _loadingSpecs = <ProductModel>{};

  void _selectionChanged() {
    final ids = _devices.map((device) => device.productID).toSet();
    _specs.removeWhere((id, _) => !ids.contains(id));
    for (final device in _devices) {
      if (!_specs.containsKey(device.productID) && _loadingSpecs.add(device)) {
        _loadSpecs(device);
      }
    }
    setState(() {});
  }

  void _includeDevices(List<ProductModel> picked) {
    final ids = _devices.map((device) => device.productID).toSet();
    final additions = picked
        .where((device) => ids.add(device.productID))
        .toList();
    if (additions.isNotEmpty) _selection.value = [..._devices, ...additions];
  }

  Future<void> _addDevices() async {
    final picked = await showModalBottomSheet<List<ProductModel>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DevicePicker(
        existing: _devices.map((device) => device.productID).toSet(),
      ),
    );
    if (!mounted || picked == null) return;
    _includeDevices(picked);
  }

  Future<void> _loadSpecs(ProductModel product) async {
    final data = await ShopService.fetchProductSpecs(
      product.productID,
      deviceID: product.deviceID,
    );
    _loadingSpecs.remove(product);
    if (!mounted || !_devices.contains(product)) return;
    setState(() {
      _specs[product.productID] = {
        ...?data?['specs'] as Map<String, dynamic>?,
        'unitRam': data?['deviceRam'],
        'unitStorage': data?['deviceStorage'],
      };
    });
  }

  Future<void> _buy(ProductModel product) async {
    if (!widget.isLoggedIn || widget.email?.isNotEmpty != true) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const WelcomePage()));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          email: widget.email!,
          name: widget.name,
          items: [
            CartItemModel(
              productID: product.productID,
              listingTitle: product.displayTitle,
              description: product.description,
              sellingPrice: product.sellingPrice,
              imageUrl: product.imageUrl,
              listingStatus: product.listingStatus,
              brand: product.brand,
              model: product.model,
              ram: product.ram,
              storage: product.storage,
              color: product.color,
              condition: product.condition,
              deviceID: product.deviceID,
              modelCode: product.modelCode,
              isSelected: true,
            ),
          ],
        ),
      ),
    );
  }

  static double? _number(String text, RegExp pattern) =>
      double.tryParse(pattern.firstMatch(text)?.group(1) ?? '');

  static double? _capacity(String text) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(TB|GB|MB)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final size = double.parse(match[1]!);
    return switch (match[2]!.toUpperCase()) {
      'TB' => size * 1024,
      'MB' => size / 1024,
      _ => size,
    };
  }

  static (String, double?) _condition(String value) {
    final key = value.trim().toLowerCase();
    final grade =
        RegExp(r'^(?:grade\s+)?([a-d])$').firstMatch(key)?[1] ??
        switch (key) {
          'pristine' || 'like new' || 'excellent' => 'a',
          'good' => 'b',
          'fair' => 'c',
          'poor' => 'd',
          _ => null,
        };
    return grade == null
        ? (value, null)
        : (
            'Grade ${grade.toUpperCase()}',
            (101 - grade.codeUnitAt(0)).toDouble(),
          );
  }

  static int _compareDisplays(String a, String b) {
    List<double> criteria(String display) {
      final text = display.toLowerCase();
      final type = text.contains('oled')
          ? (text.contains('ltpo') ? 5 : 4)
          : text.contains('ips')
          ? 3
          : text.contains('pls')
          ? 2
          : text.contains('tft')
          ? 1
          : 0;
      final resolution = RegExp(
        r'(\d+)\s*[x×]\s*(\d+)\s*pixels',
      ).firstMatch(text);
      return [
        type.toDouble(),
        _number(text, RegExp(r'(\d+)\s*hz\b')) ?? 0,
        resolution == null
            ? 0
            : double.parse(resolution[1]!) * double.parse(resolution[2]!),
        _number(text, RegExp(r'(\d+(?:\.\d+)?)\s*inches?')) ?? 0,
      ];
    }

    final left = criteria(a);
    final right = criteria(b);
    for (var i = 0; i < left.length; i++) {
      final comparison = left[i].compareTo(right[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  List<(String, String, double?)> _rows(ProductModel product) {
    final specs = _specs[product.productID];
    String spec(String key) => specs?[key]?.toString() ?? '';
    String join(List<String> parts) =>
        parts.where((value) => value.isNotEmpty).join('\n');
    final (grade, gradeScore) = _condition(product.condition);
    final display = spec('screen');
    final rear = spec('rear_camera').isNotEmpty
        ? spec('rear_camera')
        : spec('main_camera');
    final front = spec('selfie_camera');
    final battery = spec('battery');
    final weight = spec('weight');
    final grams = _number(weight, RegExp(r'(\d+(?:\.\d+)?)\s*g\b'));
    String extract(String text, String pattern) =>
        RegExp(pattern, caseSensitive: false).firstMatch(text)?.group(0) ?? '';
    String megapixels(String text) => RegExp(
      r'\d+(?:\.\d+)?\s*MP\b',
      caseSensitive: false,
    ).allMatches(text).map((match) => match[0]!).join(' + ');
    final displaySummary = [
      extract(display, r'\d+(?:\.\d+)?\s*inches?'),
      display.split(' · ').length >= 3
          ? display.split(' · ')[1].split(',').first
          : '',
      extract(display, r'\d+\s*[x×]\s*\d+\s*pixels'),
      extract(display, r'\d+\s*Hz\b'),
    ].where((part) => part.isNotEmpty).join(' · ');
    final rearSummary = megapixels(rear);
    final frontSummary = megapixels(front);

    return [
      ('Condition Grade', grade, gradeScore),
      ('Processor / Chipset', spec('soc'), null),
      ('RAM', spec('unitRam'), _capacity(spec('unitRam'))),
      ('Storage', spec('unitStorage'), _capacity(spec('unitStorage'))),
      ('Display', displaySummary, null),
      (
        'Camera',
        join([
          if (rearSummary.isNotEmpty) 'Rear: $rearSummary',
          if (frontSummary.isNotEmpty) 'Front: $frontSummary',
        ]),
        _number(rear, RegExp(r'(\d+(?:\.\d+)?)\s*MP', caseSensitive: false)),
      ),
      (
        'Battery',
        join([battery, spec('charging')]),
        _number(battery, RegExp(r'(\d+)\s*mAh', caseSensitive: false)),
      ),
      (
        'Dimensions & Weight',
        join([
          extract(
            spec('dimensions'),
            r'\d+(?:\.\d+)?(?:\s*[x×]\s*\d+(?:\.\d+)?){2}\s*mm\b',
          ).replaceAll(' x ', ' × '),
          extract(weight, r'\d+(?:\.\d+)?\s*g\b'),
        ]),
        grams == null ? null : -grams,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _devices.map(_rows).toList();
    final displays = _devices
        .map((device) => _specs[device.productID]?['screen']?.toString() ?? '')
        .toList();
    for (var i = 0; i < rows.length; i++) {
      final (label, value, _) = rows[i][4];
      if (displays[i].isEmpty) continue;
      final rank = displays
          .where(
            (other) =>
                other.isNotEmpty && _compareDisplays(displays[i], other) > 0,
          )
          .length;
      rows[i][4] = (label, value, rank.toDouble());
    }
    return ColoredBox(
      color: _surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Device Comparison',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _addDevices,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add devices',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('Tap + to add devices to compare.'),
                      )
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < rows.length; i++)
                                _deviceCard(_devices[i], rows, i),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceCard(
    ProductModel product,
    List<List<(String, String, double?)>> rows,
    int index,
  ) {
    return SizedBox(
      width: 272,
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(right: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  _productImage(product, 126),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remove from comparison',
                      icon: const Icon(Icons.close),
                      onPressed: () => _selection.value = _devices
                          .where(
                            (device) => device.productID != product.productID,
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: Text(
                  product.displayTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                _price(product),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              for (var row = 0; row < rows[index].length; row++)
                _specRow(
                  rows[index][row],
                  height: _specHeight(context, rows, row),
                  rows
                      .map((device) => device[row].$3)
                      .whereType<double>()
                      .toList(),
                  waiting: !_specs.containsKey(product.productID),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _buy(product),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Buy Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _specHeight(
    BuildContext context,
    List<List<(String, String, double?)>> rows,
    int index,
  ) {
    var height = 89.0;
    for (final device in rows) {
      final (label, value, _) = device[index];
      double measure(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: 232);
        final result = painter.height;
        painter.dispose();
        return result;
      }

      final needed =
          22 +
          measure(
            label,
            const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ) +
          measure(
            value.isEmpty ? 'Unavailable' : value,
            const TextStyle(fontSize: 13),
          );
      if (needed > height) height = needed.ceilToDouble();
    }
    return height;
  }

  Widget _specRow(
    (String, String, double?) row,
    List<double> scores, {
    required bool waiting,
    required double height,
  }) {
    final (label, value, score) = row;
    final winner =
        score != null &&
        scores.any((other) => other < score) &&
        scores.every((other) => other <= score);
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: winner ? const Color(0xFFFFF6B5) : null,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value.isEmpty ? (waiting ? 'Loading…' : 'Unavailable') : value,
            textAlign: TextAlign.justify,
            style: const TextStyle(fontSize: 13, color: _ink),
          ),
        ],
      ),
    );
  }
}

String _price(ProductModel item) =>
    'RM ${item.sellingPrice.toStringAsFixed(2)}';

Widget _productImage(ProductModel item, double size) {
  const placeholder = Icon(Icons.smartphone, color: _blue);
  return SizedBox(
    width: size,
    height: size,
    child: item.images.isEmpty
        ? placeholder
        : Image.network(
            item.images.first,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => placeholder,
          ),
  );
}

class _DevicePicker extends StatefulWidget {
  const _DevicePicker({required this.existing});
  final Set<String> existing;

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  final _deviceDetails = <String, Future<Map<String, dynamic>?>>{};
  final _selected = <String, ProductModel>{};
  final _items = <ProductModel>[];
  String _query = '';
  String _brand = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final seen = <String>{};
    final items = <ProductModel>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final response = await ShopService.fetchProductPage(
        status: 'listed',
        cursor: cursor,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (response['error'] != null) {
        setState(() {
          _error = response['error'].toString();
          _loading = false;
        });
        return;
      }
      items.addAll(
        (response['products'] as List<ProductModel>).where(
          (item) =>
              item.productID.isNotEmpty &&
              item.listingStatus.trim().toLowerCase() == 'listed' &&
              seen.add(item.productID),
        ),
      );
      cursor = response['hasMore'] == true
          ? response['nextCursor'] as String?
          : null;
    } while (cursor != null && cursors.add(cursor));
    setState(() {
      _items
        ..clear()
        ..addAll(items);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items
        .where(
          (item) =>
              (_brand.isEmpty ||
                  item.brand.trim().toLowerCase() == _brand.toLowerCase()) &&
              '${item.displayTitle} ${item.brand} ${item.model}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .9,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: BackButton(onPressed: () => Navigator.pop(context)),
                title: const Text(
                  'Add Device',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _blue,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(color: _border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search smartphones, brands, models…',
                    filled: true,
                    fillColor: const Color(0xFFF0F1FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: DropdownButtonFormField<String>(
                  initialValue: _brand,
                  decoration: InputDecoration(
                    labelText: 'Brand',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All brands'),
                    ),
                    for (final brand in PhoneBrandsData.wellKnownPhoneBrands)
                      DropdownMenuItem(value: brand, child: Text(brand)),
                  ],
                  onChanged: (brand) => setState(() => _brand = brand ?? ''),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: TextButton(
                          onPressed: _load,
                          child: const Text('Could not load listings. Retry'),
                        ),
                      )
                    : filtered.isEmpty
                    ? const Center(child: Text('No purchase listings found'))
                    : ColoredBox(
                        color: _surface,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final added = widget.existing.contains(
                              item.productID,
                            );
                            final selected = _selected.containsKey(
                              item.productID,
                            );
                            void toggle() => setState(() {
                              if (selected) {
                                _selected.remove(item.productID);
                              } else {
                                _selected[item.productID] = item;
                              }
                            });
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: _border),
                              ),
                              color: added
                                  ? const Color(0xFFE5E7EB)
                                  : Colors.white,
                              child: ListTile(
                                enabled: !added,
                                onTap: added ? null : toggle,
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: added || selected,
                                      onChanged: added ? null : (_) => toggle(),
                                    ),
                                    _productImage(item, 38),
                                  ],
                                ),
                                title: Text(
                                  item.displayTitle,
                                  textAlign: TextAlign.justify,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: FutureBuilder<Map<String, dynamic>?>(
                                  future: item.deviceID.isEmpty
                                      ? null
                                      : _deviceDetails.putIfAbsent(
                                          item.deviceID,
                                          () => TradeInService.getDeviceById(
                                            item.deviceID,
                                          ),
                                        ),
                                  builder: (context, snapshot) {
                                    final ram =
                                        snapshot.data?['ram']
                                            ?.toString()
                                            .trim() ??
                                        '';
                                    final capacity =
                                        snapshot.data?['storageCapacity']
                                            ?.toString()
                                            .trim() ??
                                        '';
                                    final storage = capacity.isNotEmpty
                                        ? capacity
                                        : snapshot.data?['storage']
                                                  ?.toString()
                                                  .trim() ??
                                              '';
                                    return Text(
                                      [
                                        if (ram.isNotEmpty)
                                          ram.toLowerCase().endsWith('ram')
                                              ? ram
                                              : '$ram RAM',
                                        if (storage.isNotEmpty) storage,
                                        if (item.color.isNotEmpty) item.color,
                                        if (added) 'Added',
                                      ].join(' · '),
                                      style: const TextStyle(fontSize: 12),
                                    );
                                  },
                                ),
                                trailing: Text(
                                  _price(item),
                                  style: const TextStyle(
                                    color: _blue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _selected.isEmpty
                        ? null
                        : () =>
                              Navigator.pop(context, _selected.values.toList()),
                    child: Text('Add Selected (${_selected.length})'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
