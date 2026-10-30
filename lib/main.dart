import 'package:flutter/material.dart';

import 'pages/home_page.dart';

void main() {
  runApp(const YuYinApp());
}

/// 应用入口：负责主题配置与首页
class YuYinApp extends StatelessWidget {
  const YuYinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '抖音无水印下载器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
