import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'backend.dart';
import 'firebase_drive_service.dart';

const int maxVideoBytes = 40000000000;
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

String? _fileIdFromResponse(http.Response response, int expectedSize) {
  try {
    final meta = _asMap(jsonDecode(response.body));
    final id = meta['id']?.toString();
    final size = int.tryParse('${meta['size']}') ?? -1;
    if (id != null && id.isNotEmpty && size == expectedSize) return id;
  } catch (_) {
    return null;
  }
  return null;
}

int _acceptedOffset(String? range) {
  if (range == null) return 0;
  final match = RegExp(r'bytes=0-(\d+)').firstMatch(range);
  if (match == null) throw Exception('Google Drive returned an invalid upload checkpoint.');
  return int.parse(match.group(1)!) + 1;
}

class VideoUploadResult {
  const VideoUploadResult({required this.fileName});
  final String fileName;
}

class VideoUploadService {
  VideoUploadService({this.useFirebase = false});

  final bool useFirebase;
  final FirebaseDriveService _firebaseDrive = FirebaseDriveService();

  Future<VideoUploadResult> upload({
    required String orderId,
    required PlatformFile file,
    required void Function(double progress) onProgress,
  }) async {
    if (file.size <= 0 || file.size > maxVideoBytes) {
      throw Exception('Choose a video larger than 0 bytes and no bigger than 40 GB.');
    }
    final mime = _mimeFor(file.name);
    final startData = await _openOrResumeSession(orderId: orderId, file: file, mime: mime);
    final uri = Uri.parse(startData['uploadUrl'].toString());
    if (uri.scheme != 'https' || uri.host != 'www.googleapis.com') {
      throw Exception('Google Drive returned an invalid upload address.');
    }

    var offset = (startData['resumeOffset'] as int?) ?? 0;
    var fileId = startData['completedFileId']?.toString() ?? '';
    if (offset < 0 || offset > file.size) throw Exception('The saved upload checkpoint is invalid.');
    onProgress(offset / file.size);

    if (fileId.isEmpty) {
      final source = file.readStream;
      if (source == null) {
        throw Exception('Android did not provide a video stream. Please select the video again.');
      }
      final iterator = StreamIterator<List<int>>(source);
      final buffered = <int>[];
      var sourceEnded = false;
      var current = Uint8List(0);
      var currentOffset = 0;
      var retries = 0;

      Future<void> fillBuffer(int wanted) async {
        while (buffered.length < wanted && !sourceEnded) {
          if (await iterator.moveNext()) {
            buffered.addAll(iterator.current);
          } else {
            sourceEnded = true;
          }
        }
      }

      try {
        var skipped = 0;
        while (skipped < offset) {
          if (!await iterator.moveNext()) {
            throw Exception('The selected file is shorter than the saved upload checkpoint.');
          }
          final part = iterator.current;
          final discard = min(part.length, offset - skipped);
          skipped += discard;
          if (discard < part.length) buffered.addAll(part.sublist(discard));
        }

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
              throw Exception('The phone supplied an incomplete upload chunk. Please select the video again.');
            }
            current = Uint8List.fromList(buffered.sublist(0, take));
            buffered.removeRange(0, take);
            currentOffset = 0;
          }

          final remainingChunk = current.length - currentOffset;
          final startByte = offset;
          final endByte = startByte + remainingChunk - 1;
          http.Response response;
          try {
            response = await http.put(
              uri,
              headers: {
                'Content-Type': mime,
                'Content-Length': '$remainingChunk',
                'Content-Range': 'bytes $startByte-$endByte/${file.size}',
              },
              body: Uint8List.sublistView(current, currentOffset),
            ).timeout(const Duration(minutes: 5));
          } catch (_) {
            retries++;
            if (retries > 5) {
              throw Exception('Internet interrupted during upload. Reopen the same video to resume.');
            }
            await Future<void>.delayed(Duration(seconds: min(8, retries * 2)));
            continue;
          }

          if (response.statusCode == 200 || response.statusCode == 201) {
            fileId = _fileIdFromResponse(response, file.size) ?? '';
            if (fileId.isEmpty) throw Exception('Google Drive did not confirm the exact uploaded file size.');
            offset = file.size;
            onProgress(1);
            break;
          }

          if (response.statusCode == 308) {
            final accepted = _acceptedOffset(response.headers['range']);
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

          if (response.statusCode == 404 || response.statusCode == 410) {
            throw Exception('Google Drive upload session expired. Please choose the video again to start a fresh upload.');
          }
          throw Exception('Google Drive upload failed (HTTP ${response.statusCode}). Please retry.');
        }
      } finally {
        await iterator.cancel();
      }
    }

    if (fileId.isEmpty) throw Exception('Google Drive did not confirm the completed upload.');

    if (useFirebase) {
      await _firebaseDrive.finalizeUpload(fileId: fileId);
    } else {
      final finalize = await supabase.functions.invoke('google-drive-storage', body: {
        'action': 'finalize_upload',
        'orderId': orderId,
        'fileId': fileId,
      });
      final finalData = _asMap(finalize.data);
      if (finalize.status != 200 || finalData['ok'] != true) {
        throw Exception(finalData['error']?.toString() ?? 'The uploaded file could not be verified.');
      }
    }

    return VideoUploadResult(fileName: file.name);
  }

  Future<Map<String, dynamic>> _openOrResumeSession({
    required String orderId,
    required PlatformFile file,
    required String mime,
  }) async {
    if (useFirebase) {
      Map<String, dynamic>? resumeData;
      try {
        resumeData = await _firebaseDrive.resumeUpload();
      } catch (error) {
        // Only a confirmed missing session permits a fresh upload. Network,
        // authentication, and server errors must not silently start another.
        if (!error.toString().contains('No resumable upload session')) rethrow;
      }
      if (resumeData != null) {
        final matches = resumeData['filename'] == file.name &&
            int.tryParse('${resumeData['expectedSizeBytes']}') == file.size &&
            resumeData['mimeType'] == mime &&
            resumeData['uploadUrl'] != null;
        if (!matches) {
          throw Exception('A different video upload is already in progress for this account. Select the same video to resume it.');
        }
        return {
          'uploadUrl': resumeData['uploadUrl'].toString(),
          'resumeOffset': resumeData['resumeOffset'] as int? ?? 0,
          if (resumeData['uploadComplete'] == true)
            'completedFileId': resumeData['completedFileId']?.toString() ?? '',
        };
      }
      final started = await _firebaseDrive.startUpload(
        orderId: orderId,
        filename: file.name,
        mimeType: mime,
        sizeBytes: file.size,
      );
      return {
        'uploadUrl': started['uploadUrl'].toString(),
        'resumeOffset': started['resumeOffset'] as int? ?? 0,
      };
    }

    final resume = await supabase.functions.invoke('google-drive-storage', body: {
      'action': 'resume_upload',
      'orderId': orderId,
    });
    final resumeData = _asMap(resume.data);
    if (resume.status == 200 && resumeData['ok'] == true &&
        resumeData['filename'] == file.name &&
        int.tryParse('${resumeData['expectedSizeBytes']}') == file.size &&
        resumeData['mimeType'] == mime && resumeData['uploadUrl'] != null) {
      final uri = Uri.parse(resumeData['uploadUrl'].toString());
      final probe = await http.put(
        uri,
        headers: {
          'Content-Length': '0',
          'Content-Range': 'bytes */${file.size}',
        },
        body: Uint8List(0),
      ).timeout(const Duration(seconds: 45));
      if (probe.statusCode == 308) {
        final offset = _acceptedOffset(probe.headers['range']);
        return {'uploadUrl': uri.toString(), 'resumeOffset': offset};
      }
      if (probe.statusCode == 200 || probe.statusCode == 201) {
        final id = _fileIdFromResponse(probe, file.size);
        if (id != null) {
          return {'uploadUrl': uri.toString(), 'resumeOffset': file.size, 'completedFileId': id};
        }
      }
      if (probe.statusCode != 404 && probe.statusCode != 410) {
        throw Exception('Could not check the saved Google Drive upload session (HTTP ${probe.statusCode}).');
      }
    }

    final start = await supabase.functions.invoke('google-drive-storage', body: {
      'action': 'start_upload',
      'orderId': orderId,
      'filename': file.name,
      'sizeBytes': file.size,
      'mimeType': mime,
    });
    final startData = _asMap(start.data);
    if (start.status != 200 || startData['ok'] != true || startData['uploadUrl'] == null) {
      throw Exception(startData['error']?.toString() ?? 'Could not start Google Drive upload.');
    }
    return {'uploadUrl': startData['uploadUrl'].toString(), 'resumeOffset': 0};
  }
}
