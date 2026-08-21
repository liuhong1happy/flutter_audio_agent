/// 验证 `TransferableTypedData` 包装在自定义对象中跨 isolate 移交的语义,
/// 与 `SherpaTtsEngine` worker 回传音频采样的模式一致(零拷贝)。
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

class _Reply {
  const _Reply(this.id, this.payload);
  final int id;
  final Object? payload;
}

void _worker(SendPort main) {
  final control = ReceivePort();
  main.send(control.sendPort);
  // 模拟 generate 回传:TransferableTypedData 内嵌在 _Reply.payload 列表中。
  final samples = Float32List.fromList([1.0, 2.0, 3.0, 4.0]);
  main.send(_Reply(7, [TransferableTypedData.fromList([samples]), 16000]));
}

void main() {
  test('TransferableTypedData 内嵌对象跨 isolate 移交后可 materialize', () async {
    final replies = ReceivePort();
    final worker = await Isolate.spawn(_worker, replies.sendPort);

    // 两条消息:worker 回传的 control port 与 _Reply。
    final msgs = await replies.take(2).toList();
    expect(msgs[0], isA<SendPort>());

    final reply = msgs[1] as _Reply;
    expect(reply.id, 7);

    final payload = reply.payload as List;
    final transfer = payload[0] as TransferableTypedData;
    final samples = transfer.materialize().asFloat32List();
    expect(samples, [1.0, 2.0, 3.0, 4.0]);
    expect(payload[1], 16000);

    worker.kill(priority: Isolate.immediate);
  });
}
