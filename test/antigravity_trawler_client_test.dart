import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/proxy/gemini/antigravity_trawler_client.dart';

void main() {
  test('returns raw body when Trawler responds with non-JSON content', () async {
    final client = AntigravityTrawlerClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1internal:fetchFromTrawlerCache');
        return http.Response('<html>cached</html>', 200);
      }),
      baseEndpoint: 'https://cloudcode.test',
    );

    final body = await client.fetchUrl(
      url: 'https://example.test',
      accessToken: 'access-token',
      projectId: 'project-1',
    );

    expect(body, '<html>cached</html>');
    client.dispose();
  });
}
