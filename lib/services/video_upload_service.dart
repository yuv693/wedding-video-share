import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'backend.dart';

const int maxVideoBytes = 15000000000;
const int uploadChunkBytes = 8 * 1024 * 1024;
const int _driveGranularity = 256 * 1024;

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

String _mimeFor(String filename) {
  switch (filename.toLowerCase().split('.').last) {
    case 'mp4': return 'video/mp4';
    case 'mov': return 'video/quicktime';
    case 'm4v': return 'video/x-m4v';
    case 'mkv': return 'video/x-matroska';
    case 'webm': return 'video/webm';
    case 'avi': return 'video/x-msvideo';
    case '3gp': return 'video/3gpp';
    default: return 'application/octet-stream';
  }
}

class VideoUploadResult {
  const VideoUploadResult({required this.shareUrl, required this.fileName});
  final String shareUrl;
  final String fileName;
}

class VideoUploadService {
  Future<VideoUploadResult> upload({
    required String orderId,
    required PlatformFile file,
    required void Function(double progress) onProgress,
  }) async {
    if (file.size <= 0 || file.size > maxVideoBytes) {
      throw Exception('Choose a video larger than 0 bytes and no bigger than 15 GB.');
    }
    if (!file.name.contains('.')) {
      throw Exception('The selected file must have a video filename extension.');
    }

    final start = await supabase.functions.invoke('google-drive-storage', body: {
      'action': 'start_upload',
      'orderId': orderId,
      'filename': file.name,
      'sizeBytes': file.size,
      'mimeType': _mimeFor(file.name),
    });
    final startData = _asMap(start.data);
    final uploadUrl = startData['uploadUrl']?.toString();
    if (start.status != 200 || startData['ok'] != true || uploadUrl == null) {
      throw Exception(startData['error']?.toString() ?? 'Could not start Google Drive upload.');
    }

    final uri = Uri.parse(uploadUrl);
    if (uri.scheme != 'https' || uri.host != 'www.googleapis.com') {
      throw Exception('Google Drive returned an invalid upload address.');
    }
    final source = file.readStream;
    if (source == null) {
      throw Exception('Android did not provide a video stream. Please select the video again.');
    }

    final iterator = StreamIterator<List<int>>(source);
    final buffered = <int>[];
    var sourceEnded = false;
    var offset = 0;
    var fileId = '';
    var current = Uint8List(0);
    var currentOffset = 0;
    var retries = 0;

    Future<bool> fillBuffer(int wanted) async {
      while (buffered.length < wanted && !sourceEnded) {
        if (await iterator.moveNext()) {
          buffered.addAll(iterator.current);
        } else {
          sourceEnded = true;
        }
      }
      return buffered.isNotEmpty;
    }

    try {
      while (offset < file.size) {
        if (currentOffset >= current.length) {
          current = Uint8List(0);
          currentOffset = 0;
          final remaining = file.size - offset;
          final requested = min(uploadChunkBytes, remaining);
          await fillBuffer(requested);
          if (buffered.isEmpty) {
            throw Exception('The selected video stream ended before the full file was read.');
          }
          final take = min(requested, buffered.length);
          if (take < remaining && take % _driveGranularity != 0) {
            throw Exception('The phone supplied an incomplete upload chunk. Please retry the video selection.');
          }
          current = Uint8List.fromList(buffered.sublist(0, take));
          buffered.removeRange(0, take);
          currentOffset = 0;
        }

        final remainingChunk = current.length - currentOffset;
        final startByte = offset;
        final endByte = startByte + remainingChunk - 1;
        final response;
        try {
          response = await http.put(
            uri,
            headers: {
              'Content-Type': _mimeFor(file.name),
              'Content-Length': '$remainingChunk',
              'Content-Range': 'bytes $startByte-$endByte/${file.size}',
            },
            body: Uint8List.sublistView(current, currentOffset),
          ).timeout(const Duration(minutes: 5));
        } catch (_) {
          retries++;
          if (retries > 5) {
            throw Exception('Internet interrupted during upload. Please retry when the connection is stable.');
          }
          await Future<void>.delayed(Duration(seconds: min(8, retries * 2)));
          continue;
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          final meta = _asMap(jsonDecode(response.body));
          final actualSize = int.tryParse('${meta['size']}') ?? -1;
          final returnedId = meta['id']?.toString() ?? '';
          if (returnedId.isEmpty || actualSize != file.size) {
            throw Exception('Google Drive did not confirm the exact uploaded file size.');
          }
          fileId = returnedId;
          offset = file.size;
          currentOffset = current.length;
          onProgress(1);
          break;
        }

        if (response.statusCode == 308) {
          final range = response.headers['range'];
          var accepted = offset;
          if (range != null) {
            final match = RegExp(r'bytes=0-(\d+)').firstMatch(range);
            if (match == null) throw Exception('Google Drive returned an invalid upload checkpoint.');
            accepted = int.parse(match.group(1)!) + 1;
          }
          if (accepted < offset || accepted > endByte + 1) {
            throw Exception('Google Drive returned an unexpected upload checkpoint.');
          }
          final sent = accepted - offset;
          if (sent == 0) {
            retries++;
            if (retries > 5) throw Exception('Google Drive did not accept the upload chunk. Please retry.');
            await Future<void>.delayed(Duration(seconds: min(8, retries * 2)));
            continue;
          }
          retries = 0;
          offset = accepted;
          currentOffset += sent;
          onProgress(min(0.999, offset / file.size));
          continue;
        }

        throw Exception('Google Drive upload failed (HTTP ${response.statusCode}). Please retry.');
      }
    } finally {
      await iterator.cancel();
    }

    if (fileId.isEmpty) throw Exception('Google Drive did not confirm the completed upload.');

    final finalize = await supabase.functions.invoke('google-drive-storage', body: {
      'action': 'finalize_upload',
      'orderId': orderId,
      'fileId': fileId,
    });
    final finalData = _asMap(finalize.data);
    if (finalize.status != 200 || finalData['ok'] != true) {
      throw Exception(finalData['error']?.toString() ?? 'The uploaded file could not be verified.');
    }

    final share = await supabase.functions.invoke('wedding-share', body: {
      'action': 'create_share',
      'orderId': orderId,
    });
    final shareData = _asMap(share.data);
    final shareUrl = shareData['shareUrl']?.toString();
    if (share.status != 200 || shareData['ok'] != true || shareUrl == null) {
      throw Exception(shareData['error']?.toString() ?? 'Video uploaded, but the private share link could not be created.');
    }

    return VideoUploadResult(shareUrl: shareUrl, fileName: file.name);
  }
}
