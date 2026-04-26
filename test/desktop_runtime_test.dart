import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/platform/desktop_runtime.dart';

void main() {
  tearDown(() {
    DesktopRuntime.configureLaunchOptions(const DesktopLaunchOptions(startHidden: false));
  });

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

  test('uses configured launch options for the current process', () {
    DesktopRuntime.configureLaunchOptions(
      DesktopLaunchOptions.fromArguments(const [desktopLaunchToTrayArgument]),
    );

    expect(DesktopRuntime.launchOptions.startHidden, isTrue);
  });
}
