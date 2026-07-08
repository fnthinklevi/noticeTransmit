import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class KeywordsPage extends StatefulWidget {
  final List<String> blacklistKeywords;
  final List<String> whitelistKeywords;

  const KeywordsPage({
    super.key,
    required this.blacklistKeywords,
    required this.whitelistKeywords,
  });

  @override
  State<KeywordsPage> createState() => _KeywordsPageState();
}

class _KeywordsPageState extends State<KeywordsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _blacklist;
  late List<String> _whitelist;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _blacklist = List<String>.from(widget.blacklistKeywords);
    _whitelist = List<String>.from(widget.whitelistKeywords);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final keyword = _textController.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      if (_tabController.index == 0) {
        if (!_whitelist.contains(keyword)) {
          _whitelist.add(keyword);
        }
      } else {
        if (!_blacklist.contains(keyword)) {
          _blacklist.add(keyword);
        }
      }
      _textController.clear();
    });
  }

  void _removeKeyword(int index) {
    setState(() {
      if (_tabController.index == 0) {
        _whitelist.removeAt(index);
      } else {
        _blacklist.removeAt(index);
      }
    });
  }

  void _saveAndBack() {
    Navigator.pop(context, {'whitelist': _whitelist, 'blacklist': _blacklist});
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _tabController.index == 0 ? _whitelist : _blacklist;
    final isWhitelist = _tabController.index == 0;

    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text(
          '关键词过滤',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          labelColor: const Color(0xFF007AFF),
          unselectedLabelColor: AppColors.secondaryLabel(context),
          indicatorColor: const Color(0xFF007AFF),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '白名单'),
            Tab(text: '黑名单'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saveAndBack,
            child: const Text(
              '保存',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.separator(context)),
                    ),
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: isWhitelist ? '输入白名单关键词' : '输入黑名单关键词',
                        hintStyle: TextStyle(
                          color: AppColors.secondaryLabel(context),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        color: AppColors.primaryLabel(context),
                        fontSize: 15,
                      ),
                      onSubmitted: (_) => _addKeyword(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _addKeyword,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      '添加',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isWhitelist
                    ? const Color(0xFF34C759).withValues(alpha: 0.1)
                    : const Color(0xFFFF9500).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isWhitelist ? Icons.check_circle : Icons.info_outline,
                    color: isWhitelist
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF9500),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWhitelist
                          ? '白名单：通知内容包含任一关键词时，即使应用未被选中也会推送（优先级最高）'
                          : '黑名单：通知内容包含任一关键词时，即使应用被选中也不会推送',
                      style: TextStyle(
                        fontSize: 13,
                        color: isWhitelist
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF9500),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: currentList.isEmpty
                ? Center(
                    child: Text(
                      isWhitelist ? '暂无白名单关键词' : '暂无黑名单关键词',
                      style: TextStyle(
                        color: AppColors.secondaryLabel(context),
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: currentList.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBg(context),
                          borderRadius: BorderRadius.only(
                            topLeft: index == 0
                                ? const Radius.circular(12)
                                : Radius.zero,
                            topRight: index == 0
                                ? const Radius.circular(12)
                                : Radius.zero,
                            bottomLeft: index == currentList.length - 1
                                ? const Radius.circular(12)
                                : Radius.zero,
                            bottomRight: index == currentList.length - 1
                                ? const Radius.circular(12)
                                : Radius.zero,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isWhitelist
                                  ? const Color(
                                      0xFF34C759,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFFF9500,
                                    ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isWhitelist ? Icons.check : Icons.block,
                              color: isWhitelist
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFFF9500),
                              size: 18,
                            ),
                          ),
                          title: Text(
                            currentList[index],
                            style: TextStyle(
                              fontSize: 15,
                              color: AppColors.primaryLabel(context),
                            ),
                          ),
                          trailing: GestureDetector(
                            onTap: () => _removeKeyword(index),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF3B30,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Color(0xFFFF3B30),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
