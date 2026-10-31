/// 把 JSON 中的数字/字符串统一转成正整数，0、负数或无效值返回 null。
int? positiveInt(Object? value) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}
