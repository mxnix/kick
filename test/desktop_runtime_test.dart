import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/platform/desktop_runtime.dart';

void main() {
  test('detects hidden startup argument', () {
    final options = DesktopLaunchOptions.fromArguments(const [
      '--foo',
      desktopLaunchToTrayArgument,
    ]);

    expect(options.startHidden, isTrue);
  });

  test('ignores unrelated startup arguments', () {
    final options = DesktopLaunchOptions.fromArguments(const ['--foo', '--bar']);

    expect(options.startHidden, isFalse);
  });
}
