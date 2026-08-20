// Patrol iOS 集成测试原生 runner。
//
// 使用说明(需 macOS + Xcode):
//  1. 在 Xcode 中为 Runner 新建 "UI Testing Bundle" 目标,命名为
//     RunnerUITests,并把本文件加入该目标。
//  2. 在 ios/Podfile 中把 RunnerUITests 目标嵌套进 Runner 并
//     inherit! :complete(若使用 CocoaPods);patrol 4.7+ 也支持 SPM。
//  3. pod install 后,在 Mac 上运行:
//       patrol test -t patrol_test/app_smoke_test.dart
#import <XCTest/XCTest.h>
#import <patrol/patrol.h>
#import <objc/runtime.h>

PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
