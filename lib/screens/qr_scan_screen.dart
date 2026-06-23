import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

/// Full-screen QR scanner. Returns the scanned raw string via Navigator.pop.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;
  bool _returned = false;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller?.pauseCamera();
    }
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onViewCreated(QRViewController controller) {
    _controller = controller;
    controller.scannedDataStream.listen((barcode) {
      if (_returned) return;
      final code = barcode.code;
      if (code == null || code.isEmpty) return;
      _returned = true;
      if (!mounted) return;
      Navigator.of(context).pop(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: QRView(
        key: _qrKey,
        onQRViewCreated: _onViewCreated,
        overlay: QrScannerOverlayShape(
          borderColor: Colors.white,
          borderRadius: 12,
          borderLength: 28,
          borderWidth: 8,
          cutOutSize: 220,
          // Positive offset moves the cutout up. Keeps the bottom edge of the
          // square at the same Y as the previous 220-tall strip.
          cutOutBottomOffset: screenHeight / 12,
        ),
      ),
    );
  }
}
