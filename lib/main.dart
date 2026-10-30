import 'package:flutter/material.dart';

import 'pages/app_shell.dart';

void main() {
  runApp(const YuYinApp());
}

/// 应用入口：负责主题配置与首页
class YuYinApp extends StatelessWidget {
  const YuYinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '余音',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
