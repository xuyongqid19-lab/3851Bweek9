import 'api_config.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  @visibleForTesting
  static http.Client? httpClientOverride;

  static const String _configuredBaseUrl = String.fromEnvironment(
    'AUTH_API_BASE_URL',
  );

  static String get baseUrl {
    final portable = portableApiUrl('auth');
    if (portable != null) return portable;
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb) return 'http://localhost:3002';
    return 'http://10.0.2.2:3002';
  }

  static Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static Future<String?> getAuthToken() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('auth_token');
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final preferences = await SharedPreferences.getInstance();
    final rawUser = preferences.getString('auth_user');
    if (rawUser == null || rawUser.isEmpty) return null;
    try {
      return jsonDecode(rawUser) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<String> currentUserDisplayName() async {
    final user = await getCurrentUser();
    final fullName = user?['fullName']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;
    final username = user?['username']?.toString().trim();
    if (username != null && username.isNotEmpty) return username;
    return 'Current User';
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final headers = await authHeaders();
    http.Response response;
    try {
      response = await http.get(
        _uri('/auth/users/search?q=${Uri.encodeQueryComponent(q)}'),
        headers: headers,
      );
    } catch (_) {
      throw const AuthException(
        'Cannot connect to the login database. Make sure Docker Desktop and '
        'the auth containers are running.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AuthException('User search failed. Please try again.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final users = payload['users'];
    if (users is! List) return [];
    return users
        .whereType<Map<String, dynamic>>()
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  /// 兴趣匹配候选人：后端返回的其他用户（不含 phone / address）。
  static Future<List<Map<String, dynamic>>> fetchMatchCandidates({
    int limit = 200,
  }) async {
    final headers = await authHeaders();
    http.Response response;
    try {
      final get = httpClientOverride?.get ?? http.get;
      response = await get(
        _uri('/auth/match/candidates?limit=$limit'),
        headers: headers,
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AuthException(
        'Cannot connect to the login database. Make sure Docker Desktop and '
        'the auth containers are running.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AuthException(
        'Failed to load match suggestions. Please try again.',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final users = payload['users'];
    if (users is! List) return [];
    return users
        .whereType<Map<String, dynamic>>()
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  static Future<Map<String, dynamic>?> fetchUserById(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final headers = await authHeaders();
    http.Response response;
    try {
      response = await http
          .get(_uri('/auth/users/$id'), headers: headers)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const AuthException(
        'Cannot connect to the login database. Make sure Docker Desktop and '
        'the auth containers are running.',
      );
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AuthException('Failed to load profile. Please try again.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final user = payload['user'];
    if (user is! Map<String, dynamic>) return null;
    return Map<String, dynamic>.from(user);
  }

  static Future<Map<String, dynamic>?> fetchMe() async {
    final headers = await authHeaders();
    http.Response response;
    try {
      final get = httpClientOverride?.get ?? http.get;
      response = await get(_uri('/auth/me'), headers: headers)
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AuthException(
        'Cannot connect to the login database. Make sure Docker Desktop and '
        'the auth containers are running.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AuthException('Failed to load profile. Please try again.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final user = payload['user'];
    if (user is! Map<String, dynamic>) return null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('auth_user', jsonEncode(user));
    return Map<String, dynamic>.from(user);
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String fullName,
    required String username,
    required String birthDate,
    required String phone,
    required String community,
    required String address,
    required List<String> interests,
    required Map<String, String> customCategories,
  }) async {
    final headers = await authHeaders(json: true);
    http.Response response;
    try {
      final patch = httpClientOverride?.patch ?? http.patch;
      response = await patch(
        _uri('/auth/me'),
        headers: headers,
        body: jsonEncode(<String, dynamic>{
          'fullName': fullName,
          'username': username,
          'birthDate': birthDate,
          'phone': phone,
          'community': community,
          'address': address,
          'interests': interests,
          'customCategories': customCategories,
        }),
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AuthException(
        'Cannot connect to the login database. Make sure Docker Desktop and '
        'the auth containers are running.',
      );
    }
    Map<String, dynamic> payload = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const AuthException(
          'The login server returned an invalid response.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        payload['error']?.toString() ?? 'Failed to save profile.',
      );
    }
    final user = payload['user'];
    if (user is Map<String, dynamic>) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('auth_user', jsonEncode(user));
      return Map<String, dynamic>.from(user);
    }
    return <String, dynamic>{};
  }

  static Future<void> clearSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('auth_token');
    await preferences.remove('auth_user');
  }

  static Future<Map<String, String>> authHeaders({
    bool requireAuth = true,
    bool json = false,
  }) async {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = await getAuthToken();
    if (token == null || token.isEmpty) {
      if (requireAuth) {
        throw const AuthException('Please login before using this feature.');
      }
      return headers;
    }
    headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String birthDate,
    required String interest,
    required String username,
    required String email,
    required String phone,
    required String password,
    List<Map<String, String>> securityQuestions = const [],
  }) async {
    final response = await _post('/auth/register', <String, dynamic>{
      'fullName': fullName,
      'birthDate': birthDate,
      'interest': interest,
      'username': username,
      'email': email,
      'phone': phone,
      'password': password,
      'securityQuestions': securityQuestions,
    });
    return response;
  }

  static Future<Map<String, dynamic>> login({
    required String account,
    required String password,
  }) async {
    final response = await _post('/auth/login', <String, dynamic>{
      'account': account,
      'password': password,
    });
    await _saveSession(response);
    return response;
  }

  static Future<Map<String, dynamic>> requestPasswordResetCode(String email) {
    return _post('/auth/forgot-password', {'email': email.trim()});
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _post('/auth/reset-password', {
      'email': email.trim(),
      'code': code.trim(),
      'newPassword': newPassword,
    });
    await clearSession();
  }

  static Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
  }) async {
    final response = await _post('/auth/google', <String, dynamic>{
      'idToken': idToken,
    });
    await _saveSession(response);
    return response;
  }

  static Future<Map<String, dynamic>> identifySecurityQuestion(String account) {
    return _post(
        '/auth/security-question/identify', {'account': account.trim()});
  }

  static Future<Map<String, dynamic>> verifySecurityAnswer({
    required String challenge,
    required List<String> answers,
  }) {
    return _post('/auth/security-question/verify', {
      'challenge': challenge,
      'answers': answers,
    });
  }

  static Future<void> resetPasswordWithSecurityQuestion({
    required String resetToken,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    await _post('/auth/security-question/reset', {
      'resetToken': resetToken,
      'newPassword': newPassword,
      'confirmNewPassword': confirmNewPassword,
    });
    await clearSession();
  }

  static Future<Map<String, dynamic>> fetchSecurityQuestions() async {
    final headers = await authHeaders();
    http.Response response;
    try {
      final get = httpClientOverride?.get ?? http.get;
      response = await get(_uri('/auth/security-questions'), headers: headers)
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AuthException(
          'Unable to load security questions. Please try again.');
    }
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException(
          'The login server returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
          payload['error']?.toString() ?? 'Unable to load security questions.');
    }
    return payload;
  }

  static Future<void> saveSecurityQuestions({
    required String currentPassword,
    required List<Map<String, String>> securityQuestions,
  }) async {
    await _post(
        '/auth/security-questions',
        {
          'currentPassword': currentPassword,
          'securityQuestions': securityQuestions,
        },
        headers: await authHeaders(json: true));
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    await _post(
        '/auth/change-password',
        {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          'confirmNewPassword': confirmNewPassword,
        },
        headers: await authHeaders(json: true));
    await clearSession();
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    http.Response response;
    try {
      final post = httpClientOverride?.post ?? http.post;
      response = await post(
        _uri(path),
        headers: headers ?? const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AuthException(
        'Cannot connect to the login database. Make sure Docker Desktop and '
        'the auth containers are running.',
      );
    }

    Map<String, dynamic> payload = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const AuthException(
          'The login server returned an invalid response.',
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        payload['error']?.toString() ?? 'Login server request failed.',
      );
    }
    return payload;
  }

  static Future<void> _saveSession(Map<String, dynamic> response) async {
    final token = response['token']?.toString();
    final user = response['user'];
    if (token == null || token.isEmpty || user is! Map<String, dynamic>) return;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('auth_token', token);
    await preferences.setString('auth_user', jsonEncode(user));
  }
}
