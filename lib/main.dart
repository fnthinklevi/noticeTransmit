import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'pages/main_page.dart';
import 'di/service_locator.dart';

void main() {
  FlutterError.onError = (details) {
    log(
      'FlutterError: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () {
      log('=== 应用启动开始 ===');
      WidgetsFlutterBinding.ensureInitialized();
      log('FlutterBinding 初始化完成');

      try {
        setupLocator();
        log('依赖注入配置完成');
      } catch (e, stack) {
        log('依赖注入失败: $e', error: e, stackTrace: stack);
      }

      runApp(const MyApp());
      log('runApp 调用完成');
    },
    (error, stackTrace) {
      log('全局未捕获异常: $error', error: error, stackTrace: stackTrace);
    },
  );
}
