import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'backend.dart';

/// Resumable Google Drive source-media sync for editable wedding timelines.
/// Upload URLs are short-lived bearer capabilities and are kept in memory only.
class EditorMediaSyncService {
  static const int chunkBytes = 8 * 1024 * 1024;

  Future<List<Map<String, dynamic>>> listAssets(String editorProjectId) async {
    final response = await supabase.functions.invoke(
      'wedding-editor-media',
      body: {'action': 'list', 'editorProjectId': editorProjectId},
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map || data['ok'] != true) {
      throw Exception(data is Map ? data['error'] ?? 'Could not list editor media' : 'Could not list editor media');
    }
    return (data['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> uploadFile({
    required String editorProjectId,
    required File file,
    required String filename,
    required String mimeType,
    required String mediaKind,
  }) async {
    final size = await file.length();
    final start = await supabase.functions.invoke(
      'wedding-editor-media',
      body: {
        'action': 'start',
        'editorProjectId': editorProjectId,
        'filename': filename,
        'sizeBytes': size,
        'mimeType': mimeType,
        'mediaKind': mediaKind,
      },
    );
    final startData = start.data;
    if (start.status < 200 || start.status >= 300 || startData is! Map || startData['ok'] != true) {
      throw Exception(startData is Map ? startData['error'] ?? 'Could not start Drive upload' : 'Could not start Drive upload');
    }
    final sessionId = startData['sessionId'].toString();
    final uploadUri = Uri.parse(startData['uploadUrl'].toString());
    String? fileId;
    var offset = 0;
    while (offset < size) {
      final endExclusive = (offset + chunkBytes).clamp(0, size);
      final builder = BytesBuilder(copy: false);
      await for (final part in file.openRead(offset, endExclusive)) {
        builder.add(part);
      }
      final chunk = builder.takeBytes();
      final response = await http.put(
        uploadUri,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': '${chunk.length}',
          'Content-Range': 'bytes $offset-${endExclusive - 1}/$size',
        },
        body: chunk,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        fileId = (jsonDecode(response.body) as Map)['id']?.toString();
        offset = endExclusive;
        break;
      }
      if (response.statusCode != 308) {
        throw Exception('Google Drive upload failed (${response.statusCode}).');
      }
      offset = endExclusive;
    }
    if (fileId == null || fileId.isEmpty) throw Exception('Google Drive did not confirm the uploaded file.');
    final finish = await supabase.functions.invoke(
      'wedding-editor-media',
      body: {
        'action': 'finalize',
        'editorProjectId': editorProjectId,
        'sessionId': sessionId,
        'fileId': fileId,
      },
    );
    final finishData = finish.data;
    if (finish.status < 200 || finish.status >= 300 || finishData is! Map || finishData['ok'] != true) {
      throw Exception(finishData is Map ? finishData['error'] ?? 'Could not verify Drive upload' : 'Could not verify Drive upload');
    }
    return Map<String, dynamic>.from(finishData);
  }

  Future<File> downloadFile({
    required String editorProjectId,
    required String fileId,
    required String filename,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Please sign in again.');
    final uri = Uri.parse('$supabaseUrl/functions/v1/wedding-editor-media').replace(
      queryParameters: {'editorProjectId': editorProjectId, 'fileId': fileId},
    );
    final response = await http.get(uri, headers: {'Authorization': 'Bearer ${session.accessToken}', 'apikey': supabasePublishableKey});
    if (response.statusCode != 200) throw Exception('Could not restore media from Google Drive (${response.statusCode}).');
    final directory = Directory('${(await getApplicationDocumentsDirectory()).path}/wedding_editor_media');
    await directory.create(recursive: true);
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = File('${directory.path}/${fileId}_$safeName');
    await target.writeAsBytes(response.bodyBytes, flush: true);
    return target;
  }
}
