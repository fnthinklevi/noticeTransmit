# sqflite_common 2.5.11（vendored）

来源：`pub.dev` 的 `sqflite_common 2.5.11`，只保留 `lib/`、`pubspec.yaml`、
`LICENSE`、`CHANGELOG.md`、`README.md`（`doc/`、`example/`、`test/`、`tool/`
没有随包进来）。`pubspec.yaml` 的 `dependency_overrides` 指向本目录。

## 为什么 vendored

`sqflite_sqlcipher 3.4.1` 的 `SqfliteSqlCipherOpenDatabaseOptions` 只是
`implements SqlCipherOpenDatabaseOptions`，**不是** `SqfliteOpenDatabaseOptions`
的子类。`sqflite_common` 在"原生端恢复了一个仍在事务中的单实例库"这条分支里
把它硬转成 `SqfliteOpenDatabaseOptions`：

- `lib/src/database_mixin.dart` 的 `doOpen`：
  `(options as SqfliteOpenDatabaseOptions).rollbackActiveTransactionOnOpen`

后果（真机 2026-10-29 实测，MEIZU 21 / 1.6.3+163）：

1. 后台收货引擎在 `db.transaction` 中途被 WorkManager 的 90 秒超时
   `destroyEngine()`，事务悬挂在原生单实例上；
2. 前台再次 open 同一路径 ⇒ 原生返回 `recoveredInTransaction=true` ⇒ 上面这行
   抛 CastError；
3. `ROLLBACK` 排在这行之后，永远执行不到 ⇒ 悬挂事务清不掉、原生实例还在
   ⇒ 进程不重启就永久打不开；T199 只能保证原库不被改名清空，治不了它。

上游 `sqflite_common` 2.5.14 仍未修；`sqflite_sqlcipher` 最新版仍是 3.4.1。

## 补丁（两处，均带 `PATCH(fnthink)` 注释）

1. `lib/src/database_mixin.dart` 的 `recoveredInTransaction` 分支：
   先把字段 `options` 绑到局部变量 `openOptions`（Dart 不对字段做类型提升），
   再用类型判断替代硬转；**未知 options 类型按 2.5.8 之前的旧行为回滚**
   （`true`）。不能只修 cast 而不回滚 —— 2.5.8 起 release 默认
   `rollbackActiveTransactionOnOpen=false`，那样会"打开成功但带着旧事务"，
   后续 `db.transaction` 会报嵌套事务。
2. 同文件 `onDowngrade` 那一处硬转：改成 `if (options is ...)`，未知类型
   保留它自己的 `onDowngrade`。

## 维护

- 升级 `sqflite_common` 时：先看上游有没有修这两处；修了就删本目录与
  `pubspec.yaml` 的 `dependency_overrides`，否则把补丁重放到新版本。
- 守卫：`test/architecture/sqflite_common_vendored_patch_test.dart` 钉住
  两处类型判断、禁止硬转长回来、钉住 override 指向。
- 许可证：见同目录 `LICENSE`（上游 BSD-2-Clause）。
