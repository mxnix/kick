import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/luma/luma_canvas_sync_client.dart';

void main() {
  group('LumaCanvasSyncClient frame parser', () {
    test('extracts artifact id and kind when shape props flip', () {
      const frame =
          '{"type":"push","clientClock":4,"diff":{"shape:-ZImvw0D":["patch",'
          '{"meta":["patch",{"subtitle":["put",null]}],'
          '"props":["patch",{"artifact_id":["append","L2MaUja1",0],'
          '"type":["put","image"]}]}]}}';

      final updates = debugParseLumaFrame(frame);

      expect(updates, hasLength(1));
      expect(updates.first.artifactId, 'L2MaUja1');
      expect(updates.first.kind, 'image');
      expect(updates.first.shapeId, '-ZImvw0D');
    });

    test('captures display metadata from later patch frames', () {
      const frame =
          '{"type":"push","clientClock":5,"diff":{"shape:-ZImvw0D":["patch",'
          '{"meta":["patch",{"leadingHeading":["put","Unnamed 2026-05-17"],'
          '"subtitle":["put","Nano Banana Pro"]}],'
          '"props":["patch",{"artifact_id":["append","L2MaUja1",0],'
          '"type":["put","image"]}]}]}}';

      final updates = debugParseLumaFrame(frame);

      expect(updates, hasLength(1));
      expect(updates.first.subtitle, 'Nano Banana Pro');
      expect(updates.first.heading, 'Unnamed 2026-05-17');
    });

    test('ignores placeholder shapes without an artifact id', () {
      const frame =
          '{"type":"push","clientClock":1,"diff":{"shape:-ZImvw0D":["put",'
          '{"id":"shape:-ZImvw0D","type":"artifact","props":'
          '{"w":313,"h":176,"artifact_id":"","type":"placeholder"},'
          '"parentId":"page:page","index":"a1yYtsuV","typeName":"shape"}]}}';

      expect(debugParseLumaFrame(frame), isEmpty);
    });

    test('ignores estimate-only patches', () {
      const frame =
          '{"type":"push","clientClock":2,"diff":{"shape:-ZImvw0D":["patch",'
          '{"meta":["patch",{"estimatedCredits":["put",35]}]}]}}';

      expect(debugParseLumaFrame(frame), isEmpty);
    });

    test('walks data-wrapped frames', () {
      const frame =
          '{"type":"data","data":[{"type":"push","clientClock":4,"diff":{"shape:abc":["patch",'
          '{"props":["patch",{"artifact_id":["append","XYZ12345",0],"type":["put","video"]}]}]}}]}';

      final updates = debugParseLumaFrame(frame);

      expect(updates, hasLength(1));
      expect(updates.first.artifactId, 'XYZ12345');
      expect(updates.first.kind, 'video');
      expect(updates.first.shapeId, 'abc');
    });

    test('returns empty list for malformed JSON', () {
      expect(debugParseLumaFrame('not json'), isEmpty);
      expect(debugParseLumaFrame(''), isEmpty);
    });
  });
}
