import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/update_checker.dart';

void main() {
  group('UpdateChecker 语义化版本比对测试', () {
    test('相同版本返回 0', () {
      expect(UpdateChecker.compareVersion('1.2.3', '1.2.3'), equals(0));
      expect(UpdateChecker.compareVersion('v1.2.3', '1.2.3'), equals(0));
      expect(UpdateChecker.compareVersion('1.2.3+129', '1.2.3+130'), equals(0));
      expect(UpdateChecker.compareVersion('V1.2.3', 'v1.2.3'), equals(0));
    });

    test('更高版本返回 1', () {
      expect(UpdateChecker.compareVersion('1.2.4', '1.2.3'), equals(1));
      expect(UpdateChecker.compareVersion('v1.3.0', '1.2.3'), equals(1));
      expect(UpdateChecker.compareVersion('2.0.0', '1.9.9'), equals(1));
      // 数值比较而非字典序（1.10.0 应大于 1.9.0）
      expect(UpdateChecker.compareVersion('1.10.0', '1.9.0'), equals(1));
    });

    test('更低版本返回 -1', () {
      expect(UpdateChecker.compareVersion('1.2.2', '1.2.3'), equals(-1));
      expect(UpdateChecker.compareVersion('1.1.9', '1.2.0'), equals(-1));
      expect(UpdateChecker.compareVersion('0.9.0', '1.0.0'), equals(-1));
    });

    test('版本号长度不同时的补零对齐', () {
      expect(UpdateChecker.compareVersion('1.2.3.1', '1.2.3'), equals(1));
      expect(UpdateChecker.compareVersion('1.2', '1.2.0'), equals(0));
      expect(UpdateChecker.compareVersion('1.2.0.0', '1.2'), equals(0));
    });
  });

  group('UpdateChecker HTML 更新说明清洗测试', () {
    test('空内容或纯标签返回默认文案', () {
      expect(UpdateChecker.cleanHtmlContent(''), equals('暂无更新说明'));
      expect(UpdateChecker.cleanHtmlContent('   '), equals('暂无更新说明'));
    });

    test('排版标签转换为换行与醒目标题符号', () {
      const html = '''
<h3>后端</h3>
<p>修复抖音登录状态检测</p>
<h3>前端</h3>
<p>修复暗夜模式部分ui<br>
删除清除按钮<br>
美化登录ui</p>
''';
      final cleaned = UpdateChecker.cleanHtmlContent(html);
      expect(cleaned, contains('【后端】'));
      expect(cleaned, contains('修复抖音登录状态检测'));
      expect(cleaned, contains('【前端】'));
      expect(cleaned, contains('删除清除按钮'));
      expect(cleaned.contains('<p>'), isFalse);
      expect(cleaned.contains('<h3>'), isFalse);
      expect(cleaned.contains('<br>'), isFalse);
    });

    test('支持 XML 转义的 Atom Feed 内容', () {
      const xmlEscaped = '''
&lt;h3&gt;移动端选择v8a，其它均选择universal&lt;/h3&gt;
&lt;h3&gt;后端&lt;/h3&gt;
&lt;p&gt;修复抖音登录状态检测&lt;/p&gt;
&lt;h3&gt;前端&lt;/h3&gt;
&lt;p&gt;修复暗夜模式部分ui&lt;br&gt;
删除清除按钮&lt;br&gt;
美化登录ui&lt;/p&gt;
''';
      final cleaned = UpdateChecker.cleanHtmlContent(xmlEscaped);
      expect(cleaned, contains('【移动端选择v8a，其它均选择universal】'));
      expect(cleaned, contains('【后端】'));
      expect(cleaned, contains('修复抖音登录状态检测'));
      expect(cleaned, contains('【前端】'));
      expect(cleaned, contains('删除清除按钮'));
      expect(cleaned.contains('&lt;'), isFalse);
      expect(cleaned.contains('&gt;'), isFalse);
      expect(cleaned.contains('<h3>'), isFalse);
      expect(cleaned.contains('<p>'), isFalse);
    });

    test('支持 Markdown 原生标题格式', () {
      const md = '''
### 移动端选择v8a，其它均选择universal
### 后端
修复抖音登录状态检测
''';
      final cleaned = UpdateChecker.cleanHtmlContent(md);
      expect(cleaned, contains('【移动端选择v8a，其它均选择universal】'));
      expect(cleaned, contains('【后端】'));
      expect(cleaned, contains('修复抖音登录状态检测'));
    });

    test('HTML 实体解码且不破坏文本中的 <v8a>', () {
      const html = '<p>&lt;v8a&gt; &amp; &quot;universal&#39;&nbsp;test</p>';
      final cleaned = UpdateChecker.cleanHtmlContent(html);
      expect(cleaned, contains('<v8a> & "universal\' test'));
    });
  });

  group('UpdateChecker 静态特征与取消机制', () {
    test('dispose 释放时不抛出异常', () {
      final checker = UpdateChecker();
      expect(checker.dispose, returnsNormally);
    });
  });
}
