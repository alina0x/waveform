import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Единый [Talker] приложения: общий лог для API (talker_dio_logger),
/// Riverpod-обсервера (talker_riverpod_logger) и ручных записей.
///
/// В `main()` переопределяется тем же инстансом, что отдан обсерверу и
/// Dio-интерсептору, — чтобы история логов была одна на всех.
final talkerProvider = Provider<Talker>((ref) => TalkerFlutter.init());
