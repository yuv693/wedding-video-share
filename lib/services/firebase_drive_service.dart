import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String _firebaseFunctionsBase =
    'https://asia-south1-wedding-video-share.cloudfunctions.net';

class FirebaseDriveService {
  FirebaseDriveService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in before connecting Google Drive.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw StateError('Firebase sign-in token is unavailable.');
    return token;
  }

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    String method = 'POST',
    Map<String, dynamic>? body,
  }) async {
    final token = await _idToken();
    final uri = Uri.parse('$_firebaseFunctionsBase/$endpoint');
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    };
    final response = method == 'GET'
        ? await _client.get(uri, headers: headers).timeout(const Duration(seconds: 30))
        : await _client.post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 30));
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        data = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300 || data['ok'] != true) {
      throw Exception(data['error']?.toString() ??
          'Firebase request failed (HTTP ' + response.statusCode.toString() + ').');
    }
    return data;
  }

  Future<bool> connectGoogleDrive() async {
    final data = await _request('startGoogleDriveOAuth');
    final value = data['authorizationUrl']?.toString();
    if (value == null || value.isEmpty) {
      throw Exception('Google did not return an authorization link.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host != 'accounts.google.com') {
      throw Exception('Google returned an invalid authorization link.');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Map<String, dynamic>> getConnection() =>
      _request('getGoogleDriveConnection', method: 'GET');

  Future<Map<String, dynamic>> startUpload({
    required String orderId,
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) =>
      _request('startGoogleDriveUpload', body: {
        'orderId': orderId,
        'filename': filename,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      });

  Future<Map<String, dynamic>> resumeUpload() =>
      _request('resumeGoogleDriveUpload');

  Future<Map<String, dynamic>> finalizeUpload({required String fileId}) =>
      _request('finalizeGoogleDriveUpload', body: {'fileId': fileId});

  void dispose() => _client.close();
}
