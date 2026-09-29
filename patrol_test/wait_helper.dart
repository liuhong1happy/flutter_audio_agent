/// patrol 侧的"等一个条件成立"helper。
///
/// 为什么需要它:`waitUntilVisible` 只能等**界面上出现的东西**。而 v1.0.2 的
/// 后台任务(嵌入回填、记忆抽取、滚动摘要)是 fire-and-forget 的 —— 它们完成时
/// 界面不一定有变化,却又必须先落定才能做下一步断言,否则测试会随机失败。
///
/// patrol 跑在**真实时钟**上(不是 fake async),所以这里用 `pump` 推帧轮询,
/// 而不是 `Future.delayed` —— 后者会让 UI 停住,被等待的东西反而推进不了。
library;

import 'package:patrol/patrol.dart';

/// 轮询直到 [ready] 为真,然后 `pumpAndSettle` 一次。
///
/// [what] 只用于超时报错信息。超时即抛错(而不是静默继续),避免把
/// "后台任务根本没跑"误判成"跑完了但结果是空的"。
Future<void> waitForCondition(
  PatrolIntegrationTester $, {
  required String what,
  required Future<bool> Function() ready,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('等待超时(${timeout.inSeconds}s):$what');
    }
    await $.tester.pump(const Duration(milliseconds: 200));
  }
  await $.tester.pumpAndSettle();
}
