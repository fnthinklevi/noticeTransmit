import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/home_service_status.dart';

/// 首页那一格的三态判定（纯函数）。
///
/// 这一格原本只有两态，而**监听开着、推送被用户从通知栏或桌面小部件单独暂停**是真实存在的
/// 第三种处境。每条用例钉的都是"判错之后用户会看到哪句假话"，不是函数长什么样。
void main() {
  test('监听在跑、推送也开着 ⇒ 就是原来的"运行中，点击可停止"', () {
    expect(
      homeServiceTone(listening: true, pushActive: true),
      HomeServiceTone.listening,
    );
  });

  test('监听在跑、推送被暂停 ⇒ 第三态（这一态此前根本不存在）', () {
    // 判错的代价就是要么说"一切照旧"（用户以为验证码会推出来），
    // 要么说"已停止"（用户以为通知不再被读，其实一直在读、一直在记历史）。
    expect(
      homeServiceTone(listening: true, pushActive: false),
      HomeServiceTone.paused,
    );
  });

  test('监听没在跑 ⇒ stopped，此时推送开关那句话不许抢着说', () {
    // 暂停与停止是两件事：监听都停了还说"当前继续读取设备通知"，就是凭空作保。
    // 这一条同时钉住"两态的旧行为没被这次改动带歪"。
    expect(
      homeServiceTone(listening: false, pushActive: false),
      HomeServiceTone.stopped,
    );
    expect(
      homeServiceTone(listening: false, pushActive: true),
      HomeServiceTone.stopped,
    );
    expect(
      homeServiceTone(listening: false, pushActive: null),
      HomeServiceTone.stopped,
    );
  });

  test('读不到推送开关 ⇒ 不许宣布"暂停"（没问到不等于答案是暂停）', () {
    // 那一发是进程内的本地读数，正常情况下不会失败；失败意味着通道没接上。
    // 此时猜 true 与猜 false 都会有一句假话，而猜 true 至少不改变原有的两态语义
    //（点它仍是"停止监听"，而那正是这一态唯一确定的动作）。
    expect(
      homeServiceTone(listening: true, pushActive: null),
      HomeServiceTone.listening,
    );
  });
}
