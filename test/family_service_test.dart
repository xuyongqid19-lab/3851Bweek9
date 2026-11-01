import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:global_village_app/services/family_service.dart';

void main() {
  test('Family requests send Auth credentials and preserve Unicode identities',
      () async {
    final api = FamilyService(
        baseUrl: 'http://family.test',
        headers: () async => {
              'Authorization': 'Bearer session',
              'Content-Type': 'application/json'
            },
        client: MockClient((request) async {
          expect(request.url.path, '/families');
          expect(request.headers['Authorization'], 'Bearer session');
          expect(jsonDecode(request.body)['kinship'], '舅舅');
          return http.Response('{"id":"g1"}', 200);
        }));
    expect(
        (await api.request(
            'POST', '/families', {'realName': '陈明', 'kinship': '舅舅'}))['id'],
        'g1');
    api.close();
  });
  test('permission failures retain server status and message', () async {
    final api = FamilyService(
        headers: () async => {},
        client: MockClient(
            (_) async => http.Response('{"error":"Not a member"}', 403)));
    await expectLater(
        api.inbox(),
        throwsA(
            isA<FamilyApiException>().having((e) => e.status, 'status', 403)));
    api.close();
  });
  test('invalid JSON does not masquerade as an empty family list', () async {
    final api = FamilyService(
        headers: () async => {},
        client: MockClient(
            (_) async => http.Response('<html>offline</html>', 200)));
    await expectLater(
        api.inbox(),
        throwsA(isA<FamilyApiException>().having(
            (e) => e.message, 'message', contains('invalid response'))));
    api.close();
  });
  test('connection failure is actionable and does not create local demo data',
      () async {
    final api = FamilyService(
        headers: () async => {},
        client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(
        api.inbox(),
        throwsA(isA<FamilyApiException>()
            .having((e) => e.message, 'message', contains('Cannot reach'))));
    api.close();
  });
}
