part of 'history_page.dart';

// 内容区左右滑切档：速度/位移判据、两段式动画与方向切换。
// R3 拆分：extension 挂在 _HistoryPageState 上（同 library），行为与拆分前完全一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageSwipe on _HistoryPageState {
  void _onSwipeTick() {
    if (!_swipeAnimating || _swipeSwitched) return;
    if (_swipeController.value < 0.5) return;
    _swipeSwitched = true;
    final target = _swipeTarget;
    if (target != null) _setDirection(target);
  }

  void _animateDirectionSwitch(String target, {required bool forward}) {
    if (_swipeAnimating) return;
    _swipeAnimating = true;
    _swipeSwitched = false;
    _swipeTarget = target;
    _swipeForward = forward;
    _swipeController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _swipeAnimating = false;
        _swipeSwitched = false;
        _swipeTarget = null;
        _swipeController.value = 0;
      });
    });
  }

  /// 点芯片时立刻回到静止态，免得在半路动画里又换一次档（把用户刚点的覆盖掉）。
  void _cancelSwipeAnimation() {
    if (!_swipeAnimating) return;
    _swipeAnimating = false;
    _swipeSwitched = true;
    _swipeTarget = null;
    _swipeController.stop();
    _swipeController.value = 0;
  }

  /// 当前动画帧的横向位移（以屏宽为 1）。
  double _swipeOffsetFraction() {
    if (!_swipeAnimating) return 0;
    final t = _swipeController.value;
    final dir = _swipeForward ? 1.0 : -1.0;
    if (t <= 0.5) {
      final p = Curves.easeOutCubic.transform(t / 0.5);
      return -dir * p;
    }
    final p = Curves.easeOutCubic.transform((t - 0.5) / 0.5);
    return dir * (1 - p);
  }

  /// 内容区左右滑切档。走的是与点顶部芯片**同一条** `_setDirection`：
  /// 换账本、退出选项态、补读数据都由那一处负责，这里不另写一份切档逻辑。
  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_swipeAnimating) return;
    final v = details.primaryVelocity ?? 0;
    // 轻扫（≥200 px/s）以速度方向为准；慢拖（速度不够）以累计位移为准。
    final dx = v.abs() >= 200 ? v : _swipeDx;
    if (dx.abs() < 60) return;
    final at = _HistoryPageState._directionOrder.indexOf(_direction);
    if (at < 0) return;
    final next = dx < 0 ? at + 1 : at - 1;
    if (next < 0 || next >= _HistoryPageState._directionOrder.length) return;
    _animateDirectionSwitch(
      _HistoryPageState._directionOrder[next],
      forward: dx < 0,
    );
  }

  void _setDirection(String value) {
    if (_direction == value) return;
    final nextIsFnthink = value == 'received' || value == 'sent';
    setState(() {
      _direction = value;
      if (nextIsFnthink) {
        // 换档 = 换账本：把上一档那几行清掉、置回"还没读"，免得旧的一档在新档位上闪一下。
        _inboxDirection = value == 'sent'
            ? kFnthinkDirectionOut
            : kFnthinkDirectionIn;
        _inbox = const [];
        _inboxLoaded = false;
        _commandRecords = const {};
      }
      // T193：选项态只属于收件档 —— 切走就退出（带着一批勾选走去发出档，
      // 那个"已选 N"既没有动作可做，也会把别的档的行当成同一批）。
      _exitInboxSelect(inSetState: false);
    });
    if (nextIsFnthink) unawaited(_loadInbox());
    if (value == 'forwarded' && _searchResults == null) {
      // 切回转发档而头一页还没读过（进页时停在别的档）：当场补读 ——
      // 与 initState 那一下同一条路，不另写一份。
      unawaited(_loadSearch(reset: true));
      unawaited(_refreshTotal());
    }
  }

  /// 点芯片：先停掉可能在跑的滑动动画，再换档（否则动画中点会覆盖用户刚点的这一下）。
  void _tapDirection(String value) {
    _cancelSwipeAnimation();
    _setDirection(value);
  }
}
