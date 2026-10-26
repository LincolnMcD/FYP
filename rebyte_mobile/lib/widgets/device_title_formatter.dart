/// Centralized smart formatter for phone & device titles across customer & staff sides.
/// Ensures brand names are never duplicated (e.g. "Samsung Galaxy A15", not "Samsung Samsung Galaxy A15").
String formatDeviceTitle(String? brand, String? model) {
  final b = (brand ?? '').trim();
  var m = (model ?? '').trim();
  if (b.isEmpty) return m;
  if (m.isEmpty) return b;
  if (m.toLowerCase().startsWith('${b.toLowerCase()} ')) {
    m = m.substring(b.length).trim();
  } else if (m.toLowerCase() == b.toLowerCase()) {
    return b;
  }
  return '$b $m';
}
