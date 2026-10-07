import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 表单型弹层的**外壳**（T90 片12）：标题 + 一叠字段 + 取消/保存。
///
/// 为什么要有它：`rule_edit_page`（part 文件 `rule_edit_widgets.dart`）里「新增条件 / 编辑条件 /
/// 新增动作 / 编辑动作」四枚对话框各写了一遍 `AlertDialog` 外壳 —— 圆角、背景色、按钮顺序、
/// 字号在四处各存一遍，而它们描述的是同一件事：一张要填几格的表。四份的下一幕与片11 那两枚
/// 重复框一样：改一处忘三处。
///
/// ⚠ 字段内容由调用方给（[fields]），本组件**不碰业务**：条件要的是「类型 + 值 + 逻辑」，
/// 动作要的是「类型 + 参数」，硬统一会逼出一个带一堆开关的假通用件。
/// 校验与 pop 时机也留在调用方（[onSubmit]）—— 每个表单的"能不能提交"判据不同，
/// 而这一层唯一该负责的是形状。
class IosFormDialog extends StatelessWidget {
  const IosFormDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.cancelText,
    required this.submitText,
    required this.onSubmit,
    this.submitEnabled = true,
    this.submitKey,
  });

  final String title;

  /// 从上到下排的字段（label + 控件由调用方组成）。
  final List<Widget> fields;
  final String cancelText;
  final String submitText;

  /// 保存那颗按下去时执行的动作（由调用方决定校验、写回与 `Navigator.pop`）。
  final VoidCallback onSubmit;

  /// 提交那颗**现在能不能按**。默认 true（片12 那四枚表单都是恒可用的：校验不过就地提示）。
  /// ⚠ 只有**幻念那两枚**（发一条 / 配对，片19）传 false：它们的判据是"填全了才让发"，
  ///   所以那颗在没填全时必须是灰的 —— 判据留在调用方，这里只管画成灰的。
  final bool submitEnabled;

  /// 提交那颗的 key。⚠ **不是装饰**：发版闸门与 `fnthink_settings_page_test` 的六条用例都是
  ///   按 `fnthink-send-submit` / `fnthink-pair-peer-submit` 这两枚 key 找到那颗钮的
  ///   （闸门还要读它的 `onPressed` 判「空正文不许能发」）—— 而壳外面挂不了 key，
  ///   所以这个口子是这两处真实需求逼出来的。
  final Key? submitKey;

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(title),
      // ⚠ 这层透明 `Material` 不是装饰：[fields] 是**调用方给的**，而现有调用点塞进去的是
      // Material 的 `TextField` 与 `InkWell`（`_IosSelectField`）—— `CupertinoAlertDialog`
      // 自己**不含** Material，少了这一层就整枚表单抛 "No Material widget found"
      // （闸门 5.7「编辑预制规则(加一个条件)」当场喊出来的；四条 widget 用例都检不到，
      //  因为它们用的 fields 是纯 `Text` ⇒ 见 ios_form_dialog_test 那条补上的用例）。
      // 用 transparency 而非默认 Material：不透明一层会把水波纹画不出来（本仓撞过一次）。
      content: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          // ⚠ 这里**不套** SingleChildScrollView：反证 FM1 把那层摘掉后一条用例都不红 ——
          // `CupertinoAlertDialog` 本来就把 content 放在有界可滚的位置里（与片6 PK5 同一课）。
          // 少一层是一层：那层壳会让后人以为「滚动是我方实现的」，于是去查不存在的 bug。
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: fields,
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: Text(cancelText),
        ),
        CupertinoDialogAction(
          key: submitKey,
          isDefaultAction: true,
          // ⚠ T90 片19：这一颗**可以是灰的**。幻念那两枚表单（发一条 / 配对）都要在"还没填全"时
          //   把提交置灰 —— 而那正是它们旧形状的一部分（`onPressed: null`），也是闸门在设备上
          //   断言的那一条（空正文不许能发）。⚠ Cupertino 的置灰不是 Material 的
          //   `TextButton(onPressed: null)`：后者把整颗按钮变灰，这一位是**文字**变灰、点击无声，
          //   用户能点下去但什么也不发生 ⇒ 对"空正文不许发出去"这种判据，它**不是等价替代品**。
          //   ⇒ 这里让调用方自己传 [submitEnabled]，由它在 false 时把 onPressed 置空。
          onPressed: submitEnabled ? onSubmit : null,
          child: Text(
            submitText,
            // 置灰时颜色跟着退（默认蓝配半透明灰），否则看着能点却按不动。
            style: TextStyle(color: submitEnabled ? AppColors.blue : null),
          ),
        ),
      ],
    );
  }
}
