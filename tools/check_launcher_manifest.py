import sys
import xml.etree.ElementTree as ET

# 检查合并后的 AndroidManifest：
#   · Flutter 集成测试要求存在「带 MAIN+LAUNCHER 的 <activity>」（flutter_tools 只扫 activity，
#     不认 activity-alias）——读的是 src/main 源清单，但合并产物是最终真相，两边都要看。
#   · 线上（release/profile）必须仍是「只有 alias 可启动」，否则桌面双图标、启动路径被改。
# 合并后的清单里组件名是**全限定名**（com.fnthink.notice.MainActivity），
# 早先用正则匹配 ".MainActivity" 会得到假的 hasLAUNCHER=False——故此处用 XML 解析。
# 用法：python tools/check_launcher_manifest.py <manifest 路径>...

ANDROID = 'http://schemas.android.com/apk/res/android'


def short(name):
    return name.split('.')[-1] if name else name


def launcher_filters(elem):
    """该组件是否有 MAIN + LAUNCHER 的 intent-filter。"""
    for f in elem.findall('intent-filter'):
        names = {
            c.get('{%s}name' % ANDROID) for c in list(f)
        }
        if 'android.intent.action.MAIN' in names and \
           'android.intent.category.LAUNCHER' in names:
            return True
    return False


for path in sys.argv[1:]:
    root = ET.parse(path).getroot()
    app = root.find('application')
    activities = app.findall('activity') if app is not None else []
    aliases = app.findall('activity-alias') if app is not None else []

    def enabled(elem):
        v = elem.get('{%s}enabled' % ANDROID)
        return v != 'false'

    main_launchers = [
        short(a.get('{%s}name' % ANDROID))
        for a in activities
        if launcher_filters(a) and enabled(a)
    ]
    alias_launchers = [
        short(x.get('{%s}name' % ANDROID))
        for x in aliases
        if launcher_filters(x) and enabled(x)
    ]
    main_all = [
        short(a.get('{%s}name' % ANDROID))
        for a in activities
        if launcher_filters(a)
    ]

    print('--- %s' % path.split('merged_manifest/')[-1].split('/AndroidManifest.xml')[0])
    print('   <activity> 带 LAUNCHER: %s' % (main_all or '无'))
    print('   可启动 activity（enabled）: %s' % (main_launchers or '无'))
    print('   可启动 alias（enabled）   : %s' % (alias_launchers or '无'))
    total = len(main_launchers) + len(alias_launchers)
    print('   可启动组件合计 = %d  %s' % (total, 'OK(=1)' if total == 1 else '<<< 期望 1'))
