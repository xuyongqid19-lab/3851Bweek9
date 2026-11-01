import 'api_config.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/family_group.dart';
import 'auth_service.dart';

class FamilyApiException implements Exception {
  const FamilyApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Sends only the existing Auth bearer token; the Family server verifies every request.
class FamilyService {
  FamilyService(
      {http.Client? client,
      String? baseUrl,
      Future<Map<String, String>> Function()? headers})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? defaultBaseUrl,
        _headers = headers ?? (() => AuthService.authHeaders(json: true));
  static String get defaultBaseUrl {
    final portable = portableApiUrl('family');
    if (portable != null) return portable;
    const configured = String.fromEnvironment('FAMILY_API_BASE_URL');
    return configured.isNotEmpty
        ? configured
        : kIsWeb
            ? 'http://localhost:3003'
            : 'http://10.0.2.2:3003';
  }

  final http.Client _client;
  final String _baseUrl;
  final Future<Map<String, String>> Function() _headers;
  void close() => _client.close();
  Future<FamilyJson> request(String method, String path,
      [FamilyJson? data]) async {
    try {
      final headers = await _headers();
      final req = http.Request(method, Uri.parse('$_baseUrl$path'))
        ..headers.addAll(headers);
      if (data != null) req.body = jsonEncode(data);
      final response = await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
      FamilyJson body;
      try {
        body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const FamilyApiException(
            'Family service returned an invalid response. Please retry.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FamilyApiException(
            body['error']?.toString() ?? 'Family request failed.',
            response.statusCode);
      }
      return body;
    } on AuthException catch (e) {
      throw FamilyApiException(e.message, 401);
    } on FamilyApiException {
      rethrow;
    } on TimeoutException {
      throw const FamilyApiException(
          'Family service timed out. Your input has been kept. Please retry.');
    } catch (_) {
      throw const FamilyApiException(
          'Cannot reach Family. Check your connection and try again.');
    }
  }

  Future<FamilyInbox> inbox() async =>
      FamilyInbox(await request('GET', '/families'));
  Future<FamilyGroup> group(String id) async =>
      FamilyGroup(await request('GET', '/families/$id'));
}
