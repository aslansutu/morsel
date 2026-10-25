import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

const _channel = MethodChannel('morsel/vision');

/// Where the app keeps its own files: Application Support on iOS, the app's files
/// folder on Android. Asked over this channel because path_provider's current
/// platform packages bring JNI (the Android release crash behind the
/// shared_preferences_android pin) and an FFI build step.
Future<Directory> appFolder() async => Directory((await _channel.invokeMethod<String>('appFolder'))!);

/// Small secrets, such as the Open Food Facts password: in the iOS Keychain, or
/// encrypted with an Android Keystore key. Never in preferences, which backups copy.
class Secrets {
  const Secrets();

  Future<String?> read(String name) => _channel.invokeMethod<String>('readSecret', name);

  Future<void> write(String name, String value) =>
      _channel.invokeMethod<void>('writeSecret', {'name': name, 'value': value});

  Future<void> delete(String name) => _channel.invokeMethod<void>('deleteSecret', name);
}

/// A line of text read from a photo. Box edges are fractions of the image size,
/// measured from the top left.
class TextLine {
  const TextLine(this.text, this.left, this.top, this.right, this.bottom, {this.slope = 0});

  factory TextLine.fromMap(Map<Object?, Object?> m) => TextLine(
        m['text'] as String,
        (m['left'] as num).toDouble(),
        (m['top'] as num).toDouble(),
        (m['right'] as num).toDouble(),
        (m['bottom'] as num).toDouble(),
        slope: (m['slope'] as num?)?.toDouble() ?? 0,
      );

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// How far the text's baseline drops per unit across, in the same fractions:
  /// positive when a photo taken at an angle tilts the line down to the right.
  final double slope;

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;

  Map<String, Object> toMap() =>
      {'text': text, 'left': left, 'top': top, 'right': right, 'bottom': bottom, 'slope': slope};
}

/// The device can't do this, such as the document scanner on a simulator.
class VisionUnavailable implements Exception {
  VisionUnavailable(this.message);
  final String? message;
  @override
  String toString() => message ?? 'Not available on this device';
}

/// The phone's own document scanner, text recognition and subject cut-out:
/// Apple Vision and VisionKit on iOS, Google ML Kit on Android
/// (ios/Runner/AppDelegate.swift, android/…/LabelVision.kt). Nothing leaves the device.
class Vision {
  const Vision();

  /// Opens the system document scanner. Returns the scanned page as an image
  /// file, or null if the user backed out.
  Future<String?> scanDocument() async {
    try {
      return await _channel.invokeMethod<String>('scanDocument');
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') throw VisionUnavailable(e.message);
      rethrow;
    }
  }

  /// Takes a photo or picks one from the library; null if the user backed out.
  Future<String?> pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400);
    return file?.path;
  }

  Future<List<TextLine>> readText(String imagePath) async {
    final lines = await _channel.invokeListMethod<Map<Object?, Object?>>('readText', imagePath);
    return [for (final m in lines ?? const <Map<Object?, Object?>>[]) TextLine.fromMap(m)];
  }

  /// The photo's main subject, cut out onto white, as a new image file; null when
  /// the photo has no clear subject.
  Future<String?> cutOut(String imagePath) => _channel.invokeMethod<String>('cutOut', imagePath);

  /// A copy of the photo to send to Open Food Facts: upright, at most 2400 px
  /// across, a JPEG without the original's metadata, so no location leaves with it.
  Future<String> forUpload(String imagePath) async =>
      (await _channel.invokeMethod<String>('forUpload', imagePath))!;
}
