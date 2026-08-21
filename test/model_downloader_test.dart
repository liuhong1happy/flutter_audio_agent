/// HttpModelDownloader Range 断点续传测试。
///
/// 用假 `HttpClientAdapter` 模拟服务端,验证:
/// - 有部分文件时发送 `Range: bytes=<offset>-`,206 增量追加。
/// - 服务端忽略 Range 返回 200 → 截断整包重下,不产生重复字节。
/// - 服务端返回 416 → 删除部分文件并整包重试。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/data/model_downloader.dart';

/// 假 adapter:按请求中的 Range 头返回对应偏移起的字节流。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    required this.total,
    this.ignoreRange = false,
    this.failWith416 = false,
  });

  final int total;
  final bool ignoreRange;
  final bool failWith416;

  /// 记录每次请求的 URL 与 Range 头。
  final List<({String url, String? range})> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final rangeHeader = options.headers['Range']?.toString();
    requests.add((url: options.path, range: rangeHeader));

    // 416:仅对带 Range 的首请求返回;整包重试(无 Range)时返回 200 全量。
    if (failWith416 && rangeHeader != null) {
      return ResponseBody(Stream.value(Uint8List(0)), 416, headers: {});
    }

    var start = 0;
    if (!ignoreRange && rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      start = int.parse(rangeHeader.substring('bytes='.length).split('-').first);
    }

    final bytes = Uint8List.fromList(
      List<int>.generate(total - start, (i) => (start + i) & 0xff),
    );
    return ResponseBody(
      Stream.value(bytes),
      start > 0 ? 206 : 200,
      headers: <String, List<String>>{
        'content-range': ['bytes $start-${total - 1}/$total'],
        'content-length': ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HttpModelDownloader _downloader(_FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpModelDownloader(dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('有部分文件时发送 Range 并 206 增量追加', () async {
    final tempDir = Directory.systemTemp.createTempSync('resume_ok_');
    final file = File('${tempDir.path}/model.tar.bz2');
    await file.writeAsBytes(List<int>.filled(500, 0xAA)); // 已有 500 字节部分。

    final adapter = _FakeAdapter(total: 1000);
    await _downloader(adapter).download(
      url: 'https://example/model.tar.bz2',
      savePath: file.path,
    );

    expect(adapter.requests.single.range, 'bytes=500-', reason: '应带 Range 头');
    expect(adapter.requests.single.url, 'https://example/model.tar.bz2');
    expect(await file.length(), 1000, reason: '追加后应得到完整文件');

    // 校验内容:前 500 字节保持部分文件内容,后 500 来自服务端。
    final bytes = await file.readAsBytes();
    expect(bytes[0], 0xAA);
    expect(bytes[500], 500 & 0xff, reason: '服务端从偏移 500 起,字节值 = (500) & 0xff');
    tempDir.deleteSync(recursive: true);
  });

  test('服务端忽略 Range 返回 200 时截断整包重下', () async {
    final tempDir = Directory.systemTemp.createTempSync('resume_full_');
    final file = File('${tempDir.path}/model.tar.bz2');
    await file.writeAsBytes(List<int>.filled(500, 0xAA));

    final adapter = _FakeAdapter(total: 1000, ignoreRange: true);
    await _downloader(adapter).download(
      url: 'https://example/model.tar.bz2',
      savePath: file.path,
    );

    expect(await file.length(), 1000, reason: '整包重下后长度为 total(无重复)');
    final bytes = await file.readAsBytes();
    expect(bytes[0], 0, reason: '应从头覆盖,不再是旧的部分内容');
    tempDir.deleteSync(recursive: true);
  });

  test('服务端返回 416 时删除部分文件并整包重试', () async {
    final tempDir = Directory.systemTemp.createTempSync('resume_416_');
    final file = File('${tempDir.path}/model.tar.bz2');
    await file.writeAsBytes(List<int>.filled(500, 0xAA));

    final adapter = _FakeAdapter(total: 1000, failWith416: true);
    await _downloader(adapter).download(
      url: 'https://example/model.tar.bz2',
      savePath: file.path,
    );

    expect(adapter.requests, hasLength(2), reason: '416 后应整包重试');
    expect(adapter.requests[0].range, 'bytes=500-');
    expect(adapter.requests[1].range, isNull, reason: '重试时不应再带 Range');
    expect(await file.length(), 1000, reason: '整包重试后得到完整文件');
    tempDir.deleteSync(recursive: true);
  });
}
