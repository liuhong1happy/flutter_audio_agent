/// 合成页专属辅助方法。
library;

import 'package:flutter_tts_demo/utils/tts_streaming_service.dart';

/// 是否处于活跃播放态(用于按钮/控制条开关)。
bool isActiveStreamingPhase(StreamingPhase phase) =>
    phase == StreamingPhase.synthesizing ||
    phase == StreamingPhase.playing ||
    phase == StreamingPhase.preparing ||
    phase == StreamingPhase.paused;
