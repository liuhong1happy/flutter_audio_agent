/// 设备认证门闩:保护"会降低安全性"的写操作(注册/删除声纹、调声纹阈值)。
///
/// ⚠️ 这只是便利性保护,不是安全边界。它挡的是"本机随手改动",挡不住
/// 有心人:声纹嵌入以明文 JSON 落盘(dva ReduxPersistor,非 Keystore/
/// Keychain),能拿到本机文件的人可以直接改档案绕过一切。真正的修复是把
/// 嵌入搬进 `flutter_secure_storage`(Phase 2,未做)。
///
/// 之所以重点守**录入**而不是识别:录入是信任根 —— 谁能录入,谁就能把
/// 自己加进白名单然后通过识别。
library;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// 认证门闩接口(可注入假实现,避免测试碰真插件)。
abstract class AppLockService {
  /// 设备是否具备可用认证方式(生物识别,或已设系统 PIN/密码)。
  Future<bool> isSupported();

  /// 认证一次。不可用 / 取消 / 失败一律返回 false,不抛异常。
  Future<bool> authenticate(String reason);

  /// 认证并开启一段解锁会话;会话有效期内的重复调用直接放行。
  ///
  /// 必须有会话:否则连续注册多个说话人要反复按指纹,滑块之类的高频操作
  /// 更是完全不可用。
  Future<bool> ensureUnlocked(
    String reason, {
    Duration validFor = const Duration(minutes: 5),
  });

  /// 当前是否处于解锁会话内。UI 用它做同步判定(比如滑块:认证没通过就不
  /// 该把值写进去)。
  bool get isUnlocked;

  /// 立即结束解锁会话(可用于"锁定"入口)。
  void lock();
}

/// 基于 local_auth 的真实实现。
class LocalAuthAppLockService implements AppLockService {
  LocalAuthAppLockService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;
  DateTime? _unlockedUntil;

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // 桌面等无实现平台:归入"不可用",由调用方给用户显式选择,
      // 不能让它冒泡成崩溃。
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // 允许 PIN/密码兜底:biometricOnly 为 true 时,没录指纹的设备
        // 会直接锁死。
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> ensureUnlocked(
    String reason, {
    Duration validFor = const Duration(minutes: 5),
  }) async {
    final until = _unlockedUntil;
    if (until != null && DateTime.now().isBefore(until)) return true;
    if (!await authenticate(reason)) return false;
    _unlockedUntil = DateTime.now().add(validFor);
    return true;
  }

  @override
  bool get isUnlocked {
    final until = _unlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  void lock() => _unlockedUntil = null;
}
