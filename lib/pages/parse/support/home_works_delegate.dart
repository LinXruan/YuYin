part of '../../parse_page.dart';

/// 主页批量保存的作品补抓委托。
class _HomeWorksDelegate implements IUserHomeBatchDelegate {
  _HomeWorksDelegate(this._extract);

  final Future<List<SaveWorkItem>> Function(String secUid) _extract;

  @override
  Future<List<SaveWorkItem>> extractWorks(String secUid) => _extract(secUid);
}
