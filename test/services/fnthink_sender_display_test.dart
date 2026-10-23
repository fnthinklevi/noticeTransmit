import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_sender_display.dart';

/// T172：收件里发送人的三档显示。
///
/// 三档都必须**至少给出一项**：备注/设备名都可能为空，最后回落永远是地址码。
/// 这条不是样式问题 —— 空字符串会让那一行看起来像"没有发送人"。
void main() {
  const address = '8K3FJ6QPTM9WZ4VHNS';

  String label(
    FnthinkSenderDisplayMode mode, {
    String alias = '',
    String name = '',
  }) => fnthinkSenderLabel(
    mode: mode,
    address: address,
    alias: alias,
    peerName: name,
  );

  test('备注优先：有备注用备注，没备注用设备名，都没有用地址码', () {
    expect(
      label(FnthinkSenderDisplayMode.aliasFirst, alias: '客厅', name: 'Xiaomi'),
      '客厅',
    );
    expect(
      label(FnthinkSenderDisplayMode.aliasFirst, name: 'Xiaomi'),
      'Xiaomi',
    );
    expect(label(FnthinkSenderDisplayMode.aliasFirst), address);
  });

  test('只看设备名：没设备名回落备注，再回落地址码', () {
    expect(
      label(FnthinkSenderDisplayMode.deviceName, alias: '客厅', name: 'Xiaomi'),
      'Xiaomi',
    );
    expect(label(FnthinkSenderDisplayMode.deviceName, alias: '客厅'), '客厅');
    expect(label(FnthinkSenderDisplayMode.deviceName), address);
  });

  test('两者都给：备注（设备名）；同名不重复，缺一个只给另一个', () {
    expect(
      label(FnthinkSenderDisplayMode.both, alias: '客厅', name: 'Xiaomi'),
      '客厅（Xiaomi）',
    );
    expect(label(FnthinkSenderDisplayMode.both, alias: '客厅', name: '客厅'), '客厅');
    expect(label(FnthinkSenderDisplayMode.both, name: 'Xiaomi'), 'Xiaomi');
    expect(label(FnthinkSenderDisplayMode.both), address);
  });

  test('认不出的偏好值回默认档，不猜别的档', () {
    expect(
      parseFnthinkSenderDisplayMode('nonsense'),
      FnthinkSenderDisplayMode.aliasFirst,
    );
    expect(
      parseFnthinkSenderDisplayMode(null),
      FnthinkSenderDisplayMode.aliasFirst,
    );
    for (final mode in FnthinkSenderDisplayMode.values) {
      expect(parseFnthinkSenderDisplayMode(mode.name), mode);
    }
  });
}
