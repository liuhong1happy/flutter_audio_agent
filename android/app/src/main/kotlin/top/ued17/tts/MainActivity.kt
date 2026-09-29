package top.ued17.tts

import io.flutter.embedding.android.FlutterFragmentActivity

// 必须是 FlutterFragmentActivity:local_auth(声纹录入前的设备认证)在
// Android 上基于 BiometricPrompt,要求宿主 Activity 是 FragmentActivity,
// 否则 authenticate() 直接抛 PlatformException,设备认证被判为不可用。
class MainActivity : FlutterFragmentActivity()
