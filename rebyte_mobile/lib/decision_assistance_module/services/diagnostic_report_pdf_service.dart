import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../device_tradein_module/models/device_model.dart';

class DiagnosticReportPdfService {
  static Future<Uint8List> generateReport({
    required DeviceModel? device,
    required int overallScore,
    required String conditionLabel,
    required int touchScore,
    required int displayScore,
    required int cameraScore,
    required int micScore,
    required int speakerScore,
    required int sensorScore,
    required int networkScore,
    required int gpsScore,
    required bool isTouchSkipped,
    required bool isDisplaySkipped,
    required bool isCameraSkipped,
    required bool isMicSkipped,
    required bool isSpeakerSkipped,
    required bool isSensorSkipped,
    required bool isNetworkSkipped,
    required bool isGpsSkipped,
  }) async {
    final pdf = pw.Document();

    final DateTime now = DateTime.now();
    final String monthYear = DateFormat('MMMM yyyy').format(now).toUpperCase();
    final String fullDate = DateFormat('MMM d, yyyy').format(now);

    final fontRegular = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();
    final fontSemiBold = await PdfGoogleFonts.interSemiBold();

    // Map each of the 8 tested components separately
    final List<Map<String, dynamic>> components = [
      {
        'title': 'Touchscreen',
        'score': touchScore,
        'isSkipped': isTouchSkipped,
        'desc': isTouchSkipped
            ? 'Test skipped by user.'
            : (touchScore >= 90
                ? 'Pass - Full responsiveness, multi-touch grid registered.'
                : 'Sub-optimal touch response or missed sectors registered.'),
      },
      {
        'title': 'Display & Pixels',
        'score': displayScore,
        'isSkipped': isDisplaySkipped,
        'desc': isDisplaySkipped
            ? 'Inspection skipped by user.'
            : (displayScore >= 85
                ? 'Pass - Uniform RGB color purity, zero dead pixels or burn-in.'
                : 'Defect or uneven panel coloration reported.'),
      },
      {
        'title': 'Camera System',
        'score': cameraScore,
        'isSkipped': isCameraSkipped,
        'desc': isCameraSkipped
            ? 'Test skipped by user.'
            : (cameraScore >= 85
                ? 'Pass - Front & rear lenses functional, sensors clear.'
                : 'Defects reported in image acquisition or lens clarity.'),
      },
      {
        'title': 'Microphone',
        'score': micScore,
        'isSkipped': isMicSkipped,
        'desc': isMicSkipped
            ? 'Test skipped by user.'
            : (micScore >= 85
                ? 'Pass - Clean input recording, no background distortion.'
                : 'Distortion or low amplitude recorded.'),
      },
      {
        'title': 'Speaker',
        'score': speakerScore,
        'isSkipped': isSpeakerSkipped,
        'desc': isSpeakerSkipped
            ? 'Test skipped by user.'
            : (speakerScore >= 85
                ? 'Pass - Clear numeric playback, speaker output verified.'
                : 'Audio output mismatch or distortion reported.'),
      },
      {
        'title': 'Sensors & Hardware',
        'score': sensorScore,
        'isSkipped': isSensorSkipped,
        'desc': isSensorSkipped
            ? 'Test skipped by user.'
            : (sensorScore >= 85
                ? 'Pass - Accelerometer, gyroscope & proximity verified.'
                : 'Incomplete registration on hardware motion sensors.'),
      },
      {
        'title': 'Network & Cellular',
        'score': networkScore,
        'isSkipped': isNetworkSkipped,
        'desc': isNetworkSkipped
            ? 'Test skipped by user.'
            : (networkScore >= 85
                ? 'Pass - Wi-Fi & Mobile data connections & internet active.'
                : 'Network connectivity timeout or connection failed.'),
      },
      {
        'title': 'GPS & Location',
        'score': gpsScore,
        'isSkipped': isGpsSkipped,
        'desc': isGpsSkipped
            ? 'Test skipped by user.'
            : (gpsScore >= 85
                ? 'Pass - Fast coordinate lock & stationary precision confirmed.'
                : 'Location accuracy or stability threshold not met.'),
      },
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. Header (ReByte Inspection Report | Month CONFIDENTIAL)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ReByte',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 26,
                          color: const PdfColor.fromInt(0xFF0C3D82),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Inspection Report',
                        style: pw.TextStyle(
                          font: fontSemiBold,
                          fontSize: 14,
                          color: const PdfColor.fromInt(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        monthYear,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 10,
                          color: const PdfColor.fromInt(0xFF0C3D82),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'CONFIDENTIAL',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 9,
                          color: const PdfColor.fromInt(0xFF94A3B8),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
              pw.SizedBox(height: 24),

              // 2. Inspection Summary Card (Circular/Badge Score + Description)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFFAFAFA),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Circular-style score indicator
                    pw.Container(
                      width: 72,
                      height: 72,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        border: pw.Border.all(
                          color: const PdfColor.fromInt(0xFF0C3D82),
                          width: 4,
                        ),
                      ),
                      child: pw.Center(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              '$overallScore',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 24,
                                color: const PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                            pw.Text(
                              '/100',
                              style: pw.TextStyle(
                                font: fontSemiBold,
                                fontSize: 9,
                                color: const PdfColor.fromInt(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 24),

                    // Details
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Inspection Summary',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 15,
                              color: const PdfColor.fromInt(0xFF0F172A),
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: pw.BoxDecoration(
                              color: overallScore >= 80
                                  ? const PdfColor.fromInt(0xFFDCFCE7)
                                  : const PdfColor.fromInt(0xFFFEF3C7),
                              borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(12),
                              ),
                            ),
                            child: pw.Text(
                              conditionLabel.toUpperCase(),
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: overallScore >= 80
                                    ? const PdfColor.fromInt(0xFF15803D)
                                    : const PdfColor.fromInt(0xFFB45309),
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            'Device has completed full self-diagnostic tests. Inspection reflects operational performance of physical display, camera sensors, audio channels, and wireless connectivity.',
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: const PdfColor.fromInt(0xFF475569),
                              lineSpacing: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 32),

              // 3. Detailed Diagnostics Section
              pw.Text(
                'Detailed Diagnostics',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 15,
                  color: const PdfColor.fromInt(0xFF0C3D82),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
              pw.SizedBox(height: 16),

              // 2-Column Grid for Component Results (8 items, 4 rows x 2 cols)
              pw.Wrap(
                spacing: 24,
                runSpacing: 16,
                children: components.map((comp) {
                  final int score = comp['score'] as int;
                  final bool skipped = comp['isSkipped'] as bool;

                  return pw.SizedBox(
                    width: 245,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              comp['title'] as String,
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 11.5,
                                color: const PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: pw.BoxDecoration(
                                color: skipped
                                    ? const PdfColor.fromInt(0xFFE2E8F0)
                                    : (score >= 80
                                        ? const PdfColor.fromInt(0xFF16A34A)
                                        : (score >= 50
                                            ? const PdfColor.fromInt(0xFFD97706)
                                            : const PdfColor.fromInt(0xFFE11D48))),
                                borderRadius: const pw.BorderRadius.all(
                                  pw.Radius.circular(10),
                                ),
                              ),
                              child: pw.Text(
                                skipped ? 'N/A' : '$score/100',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 8.5,
                                  color: PdfColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          comp['desc'] as String,
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: const PdfColor.fromInt(0xFF64748B),
                            lineSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              pw.Spacer(),

              // 4. Clean Footer
              pw.Divider(thickness: 0.8, color: const PdfColor.fromInt(0xFFE2E8F0)),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated on $fullDate • ReByte Internal Reporting System',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: const PdfColor.fromInt(0xFF94A3B8),
                    ),
                  ),
                  pw.Text(
                    'Page 1 of 1',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: const PdfColor.fromInt(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<String?> downloadOrPrintReport({
    required DeviceModel? device,
    required int overallScore,
    required String conditionLabel,
    required int touchScore,
    required int displayScore,
    required int cameraScore,
    required int micScore,
    required int speakerScore,
    required int sensorScore,
    required int networkScore,
    required int gpsScore,
    required bool isTouchSkipped,
    required bool isDisplaySkipped,
    required bool isCameraSkipped,
    required bool isMicSkipped,
    required bool isSpeakerSkipped,
    required bool isSensorSkipped,
    required bool isNetworkSkipped,
    required bool isGpsSkipped,
  }) async {
    final pdfBytes = await generateReport(
      device: device,
      overallScore: overallScore,
      conditionLabel: conditionLabel,
      touchScore: touchScore,
      displayScore: displayScore,
      cameraScore: cameraScore,
      micScore: micScore,
      speakerScore: speakerScore,
      sensorScore: sensorScore,
      networkScore: networkScore,
      gpsScore: gpsScore,
      isTouchSkipped: isTouchSkipped,
      isDisplaySkipped: isDisplaySkipped,
      isCameraSkipped: isCameraSkipped,
      isMicSkipped: isMicSkipped,
      isSpeakerSkipped: isSpeakerSkipped,
      isSensorSkipped: isSensorSkipped,
      isNetworkSkipped: isNetworkSkipped,
      isGpsSkipped: isGpsSkipped,
    );

    final filename = 'ReByte_Inspection_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

    String? savedPath;
    try {
      // Attempt to save directly to Android public Download folder
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$filename');
        await file.writeAsBytes(pdfBytes);
        savedPath = file.path;
      }
    } catch (_) {
      // Fallback if permission/path differs
    }

    // Also share / preview so the user has immediate access and can save to any app/folder
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );

    return savedPath ?? 'Downloads / Storage';
  }
}
