import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/sniffer/common/log_message_policy.dart';

void main() {
  group('LogMessagePolicy', () {
    test('识别并格式化主页抓取进度', () {
      expect(
        LogMessagePolicy.classify('已捕获 10 / 308 条...'),
        SnifferLogKind.homeProgress,
      );
      expect(
        LogMessagePolicy.formatHomeProgress('已捕获 10 / 308 条...'),
        '正在抓取主页作品：已捕获 10 / 308 条',
      );
      expect(
        LogMessagePolicy.formatHomeProgress('已捕获 18 条'),
        '正在抓取主页作品：已捕获 18 条',
      );
    });

    test('未知主页总数时保留原计数', () {
      expect(
        LogMessagePolicy.formatHomeProgress('已捕获 5 条...'),
        '正在抓取主页作品：已捕获 5 条',
      );
    });

    test('完成与内部日志只作为诊断', () {
      expect(
        LogMessagePolicy.classify('主页作品捕获完成: 共 18 条作品'),
        SnifferLogKind.diagnostic,
      );
      expect(
        LogMessagePolicy.classify('解析完成: 共 3 个资源'),
        SnifferLogKind.diagnostic,
      );
      expect(
        LogMessagePolicy.classify('命中作品接口(fetch): /aweme/v1/web/aweme/post/'),
        SnifferLogKind.diagnostic,
      );
    });

    test('空串不作为进度', () {
      expect(LogMessagePolicy.classify(''), SnifferLogKind.diagnostic);
      expect(LogMessagePolicy.isHomeProgress('已捕获 条'), isFalse);
    });
  });
}
