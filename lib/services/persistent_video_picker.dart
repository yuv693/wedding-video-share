import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class PersistentVideo {
  PersistentVideo({
    required this.uri,
    required this.name,
    required this.size,
    required this.orderId,
  });

  final String uri;
  final String name;
  final int size;
  final String orderId;

  PlatformFile toPlatformFile() =>
      PlatformFile(name: name, size: size, readStream: const Stream.empty());

  Stream<List<int>> streamFrom(int offset) async* {
    var position = offset;
    while (position < size) {
      final length = (size - position).clamp(1, 8 * 1024 * 1024);
      final bytes = await _channel.invokeMethod<Uint8List>('readChunk', {
        'uri': uri,
        'offset': position,
        'length': length,
      });
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Android could not read the selected video at byte $position.');
      }
      position += bytes.length;
      yield bytes;
    }
  }

  static const MethodChannel _channel =
      MethodChannel('wedding_video_share/persistent_upload');

  static Future<List<PersistentVideo>> pick(String orderId) async {
    final rows = await _channel.invokeMethod<List<dynamic>>('pickVideos', {
      'orderId': orderId,
    });
    return (rows ?? []).map(_fromMap).toList();
  }

  static Future<List<PersistentVideo>> pending() async {
    final rows = await _channel.invokeMethod<List<dynamic>>('listPending');
    return (rows ?? []).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      return PersistentVideo(
        uri: map['uri'].toString(),
        name: map['name'].toString(),
        size: (map['size'] as num).toInt(),
        orderId: (map['orderId'] ?? '').toString(),
      );
    }).toList();
  }

  static Future<void> remove(String uri) =>
      _channel.invokeMethod<void>('removePending', {'uri': uri});

  static PersistentVideo _fromMap(dynamic row) {
    final map = Map<String, dynamic>.from(row as Map);
    return PersistentVideo(
      uri: map['uri'].toString(),
      name: map['name'].toString(),
      size: (map['size'] as num).toInt(),
      orderId: (map['orderId'] ?? '').toString(),
    );
  }
}
