package com.fnthink.notice

import android.appwidget.AppWidgetProvider

/**
 * 4×2 宽规格桌面小部件。
 *
 * 与 [PushToggleWidgetProvider] 共用同一套布局自适应逻辑（按当前宽度选择布局），
 * 但以独立 receiver 注册，使得桌面小部件列表中同时出现「2×2」与「4×2」两个规格，
 * 用户可直接添加任意规格；拉伸尺寸后由 onAppWidgetOptionsChanged 自动切换布局。
 */
class PushToggleWidgetWideProvider : PushToggleWidgetProvider()
