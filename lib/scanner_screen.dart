import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';

/// The camera tab: reads retail barcodes and hands each one to [onCode].
class ScanTab extends StatefulWidget {
  const ScanTab({super.key, required this.onCode});

  /// Shows the product; completes when the user comes back to the scanner.
  final Future<void> Function(String code) onCode;

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _busy = false;

  Future<void> _open(String code) async {
    if (_busy) return;
    _busy = true;
    // Pause the camera while the product is open: saves battery and stops a
    // second barcode in frame from firing.
    await _controller.stop();
    await widget.onCode(code);
    if (mounted) await _controller.start();
    _busy = false;
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.map((b) => b.rawValue).nonNulls.firstOrNull;
    if (code == null || _busy) return;
    HapticFeedback.mediumImpact();
    _open(code);
  }

  Future<void> _typeCode() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CodeSheet(),
    );
    if (code != null) await _open(code);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder(
        valueListenable: _controller,
        builder: (context, state, _) {
          final error = state.error;
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => const SizedBox.shrink(),
              ),
              if (error != null)
                _CameraUnavailable(error: error, onType: _typeCode)
              else ...[
                const _Viewfinder(),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _typeCode,
                            icon: const Icon(Icons.keyboard_outlined),
                            label: const Text('Type barcode'),
                          ),
                          if (state.torchState != TorchState.unavailable) ...[
                            const SizedBox(width: 12),
                            IconButton.filledTonal(
                              tooltip: state.torchState == TorchState.on
                                  ? 'Turn off torch'
                                  : 'Turn on torch',
                              onPressed: _controller.toggleTorch,
                              icon: Icon(state.torchState == TorchState.on
                                  ? Icons.flashlight_off_outlined
                                  : Icons.flashlight_on_outlined),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Dims everything outside a barcode-shaped window.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScrimPainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 168 + 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Point at a barcode',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  static const window = Size(280, 168);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: window.width, height: window.height),
      const Radius.circular(20),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    // Corner brackets, the same shape as the logo's scanner frame.
    final bracket = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final r = hole.outerRect;
    for (final (corner, sx, sy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..save()
        ..translate(corner.dx, corner.dy)
        ..scale(sx, sy)
        ..drawPath(
          Path()
            ..moveTo(0, 44)
            ..lineTo(0, 20)
            ..arcToPoint(const Offset(20, 0), radius: const Radius.circular(20))
            ..lineTo(44, 0),
          bracket,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) => false;
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error, required this.onType});

  final MobileScannerException error;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => (
          'Camera access is off',
          'Allow camera access for Morsel in your device settings, or type the barcode.',
        ),
      MobileScannerErrorCode.unsupported => (
          'No camera available',
          'This device has no camera Morsel can use. You can still type a barcode.',
        ),
      _ => ("The camera couldn't start", 'Try again later, or type the barcode.'),
    };
    final text = Theme.of(context).textTheme;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined, size: 48, color: MorselColors.of(context).inkMuted),
              const SizedBox(height: 16),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onType,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Type barcode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeSheet extends StatefulWidget {
  const _CodeSheet();

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _field = TextEditingController();

  void _submit() {
    final code = _field.text.trim();
    if (code.isNotEmpty) Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Type a barcode', style: text.titleLarge),
          const SizedBox(height: 4),
          Text('The digits printed under the bars.',
              style: text.bodyMedium?.copyWith(color: MorselColors.of(context).inkMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Barcode',
              hintText: '3017620422003',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Look up')),
        ],
      ),
    );
  }
}
