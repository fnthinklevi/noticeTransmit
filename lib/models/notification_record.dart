class NotificationRecord {
  final String id;
  final String title;
  final String content;
  final String subText;
  final String packageName;
  final String appName;
  final String type;
  final int postTime;
  final String time;
  final String deviceName;

  NotificationRecord({
    required this.id,
    required this.title,
    required this.content,
    required this.subText,
    required this.packageName,
    required this.appName,
    required this.type,
    required this.postTime,
    required this.time,
    required this.deviceName,
  });

  factory NotificationRecord.fromMap(Map<String, dynamic> map) {
    return NotificationRecord(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      subText: map['subText'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      type: map['type'] as String? ?? 'normal',
      postTime: map['postTime'] as int? ?? 0,
      time: map['time'] as String? ?? '',
      deviceName: map['deviceName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'subText': subText,
      'packageName': packageName,
      'appName': appName,
      'type': type,
      'postTime': postTime,
      'time': time,
      'deviceName': deviceName,
    };
  }

  NotificationRecord copyWith({
    String? id,
    String? title,
    String? content,
    String? subText,
    String? packageName,
    String? appName,
    String? type,
    int? postTime,
    String? time,
    String? deviceName,
  }) {
    return NotificationRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      subText: subText ?? this.subText,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      type: type ?? this.type,
      postTime: postTime ?? this.postTime,
      time: time ?? this.time,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationRecord &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
