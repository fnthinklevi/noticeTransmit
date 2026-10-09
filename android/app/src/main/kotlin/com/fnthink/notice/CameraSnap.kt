package com.fnthink.notice

import android.Manifest
import android.app.ActivityManager
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.provider.MediaStore
import android.util.Size
import android.view.Surface
import android.view.WindowManager
import androidx.core.content.ContextCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 「让这台现在拍一张照片」（T124 片C-3 的 `camera:snap`，只在远端发起时用）。
 *
 * 四件写在这里的取舍：
 *  ① **只在这台有可见界面时拍**：Android 9 起后台不许开相机、11 起"前台服务"里开相机还要
 *     专门类型与 while-in-use 许可 —— 那是**又一条权限面**，不在这条里顺手开。所以这一发
 *     先查自己是不是有可见界面（`IMPORTANCE_FOREGROUND`），不是就诚实回 `no-foreground`。
 *  ② **只拍最小的一张**：从相机报的 JPEG 尺寸里挑面积最小的（够看清就行）——
 *     这一发的产出是"拍到了"这件事与文件名，不是摄影作品。
 *  ③ **落盘分两代**：29+ 用 MediaStore（相册可见、不要额外权限）；24–28 写进本 app 的
 *     图片目录（那个年代的公共相册要 `WRITE_EXTERNAL_STORAGE`，这一发没有、也不去要）——
 *     ⚠ 所以回传正文**不写"已保存到相册"**（那句在 24–28 上会是假的）。
 *  ④ **没权限回 null、没界面/拍失败回 `{snap:false, why}`**：三种下场在对面读起来不同。
 *
 * ⚠ 画面不回传（图像传输＋收件端渲染是另一个子系统）；本机开关（默认关）在 Dart 侧先判。
 */
object CameraSnap {
    private const val TAG = "CameraSnap"
    private const val TIMEOUT_MS = 4000L

    /** 纯函数（JVM 可测）：从可用 JPEG 尺寸里挑**面积最小**的一个；空表回 null。 */
    fun pickSmallest(sizes: List<Pair<Int, Int>>): Pair<Int, Int>? =
        sizes
            .filter { it.first > 0 && it.second > 0 }
            .minByOrNull { it.first.toLong() * it.second.toLong() }

    fun isGranted(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    /** 这一台现在有没有可见界面（见文件头 ①）。 */
    fun isAppForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        val pid = Process.myPid()
        val procs = try {
            am.runningAppProcesses
        } catch (e: Exception) {
            null
        } ?: return false
        return procs.any {
            it.pid == pid &&
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        }
    }

    /**
     * 拍一张。回 null = **没权限**；回 `{snap:false, why}` = 有条件不满足（见文件头 ④）；
     * 回 `{snap:true, name, width, height, timeMillis}` = 成了。
     * 不抛：一次拍摄失败不该让整轮收货崩在半路（与三份"搜/读"同一纪律）。
     */
    fun snap(context: Context): Map<String, Any?>? {
        if (!isGranted(context)) return null
        if (!isAppForeground(context)) return mapOf("snap" to false, "why" to "no-foreground")
        return try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                ?: return mapOf("snap" to false, "why" to "failed")
            val cameraId = pickCameraId(manager) ?: return mapOf("snap" to false, "why" to "failed")
            val chars = manager.getCameraCharacteristics(cameraId)
            val configs = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val sizes = configs?.getOutputSizes(ImageFormat.JPEG)
                ?.map { it.width to it.height }
                ?: emptyList()
            val pick = pickSmallest(sizes) ?: return mapOf("snap" to false, "why" to "failed")
            val jpeg = capture(context, manager, cameraId, pick)
                ?: return mapOf("snap" to false, "why" to "failed")
            val now = System.currentTimeMillis()
            val name = "NT_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date(now)) + ".jpg"
            val saved = saveImage(context, jpeg, name, now)
            if (!saved) return mapOf("snap" to false, "why" to "failed")
            mapOf(
                "snap" to true,
                "name" to name,
                "width" to pick.first,
                "height" to pick.second,
                "timeMillis" to now,
            )
        } catch (e: SecurityException) {
            android.util.Log.w(TAG, "相机权限被拒", e)
            null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "拍摄失败", e)
            mapOf("snap" to false, "why" to "failed")
        }
    }

    /** 后摄优先，没有就第一颗（有些设备只有一颗）。 */
    private fun pickCameraId(manager: CameraManager): String? {
        val ids = try {
            manager.cameraIdList
        } catch (e: Exception) {
            null
        } ?: return null
        for (id in ids) {
            val facing = try {
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.LENS_FACING)
            } catch (e: Exception) {
                null
            }
            if (facing == CameraCharacteristics.LENS_FACING_BACK) return id
        }
        return ids.firstOrNull()
    }

    /** 开一次、拍一帧、关掉（见文件头 ②）。回 null = 拍不出字节。 */
    private fun capture(
        context: Context,
        manager: CameraManager,
        cameraId: String,
        size: Pair<Int, Int>,
    ): ByteArray? {
        val thread = HandlerThread("fnthink-camera-snap")
        thread.start()
        val handler = Handler(thread.looper)
        val reader = ImageReader.newInstance(size.first, size.second, ImageFormat.JPEG, 1)
        val latch = CountDownLatch(1)
        var bytes: ByteArray? = null
        reader.setOnImageAvailableListener({ r ->
            try {
                r.acquireLatestImage()?.use { image ->
                    val buffer = image.planes[0].buffer
                    bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
                }
            } catch (e: Exception) {
                android.util.Log.w(TAG, "取帧失败", e)
            } finally {
                latch.countDown()
            }
        }, handler)
        var device: CameraDevice? = null
        var session: CameraCaptureSession? = null
        try {
            // ⚠ 紧挨着 openCamera 的这一次检查不是重复：① 让 lint 的数据流看得见（它认不出
            //   snap() 里那道 isGranted 的检查）；② 收掉"检查与开相机之间权限被撤"的窄窗。
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return null
            }
            manager.openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        device = camera
                        try {
                            camera.createCaptureSession(
                                listOf(reader.surface),
                                object : CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(s: CameraCaptureSession) {
                                        session = s
                                        try {
                                            val request =
                                                camera.createCaptureRequest(
                                                    CameraDevice.TEMPLATE_STILL_CAPTURE,
                                                ).apply {
                                                    addTarget(reader.surface)
                                                    set(
                                                        CaptureRequest.CONTROL_AF_MODE,
                                                        CaptureRequest
                                                            .CONTROL_AF_MODE_CONTINUOUS_PICTURE,
                                                    )
                                                    set(
                                                        CaptureRequest.JPEG_ORIENTATION,
                                                        jpegOrientation(context),
                                                    )
                                                }
                                            s.capture(request.build(), null, handler)
                                        } catch (e: Exception) {
                                            android.util.Log.e(TAG, "发拍摄请求失败", e)
                                            latch.countDown()
                                        }
                                    }

                                    override fun onConfigureFailed(s: CameraCaptureSession) {
                                        android.util.Log.e(TAG, "会话配置失败", null)
                                        latch.countDown()
                                    }
                                },
                                handler,
                            )
                        } catch (e: Exception) {
                            android.util.Log.e(TAG, "建会话失败", e)
                            latch.countDown()
                        }
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        camera.close()
                    }

                    override fun onError(camera: CameraDevice, error: Int) {
                        android.util.Log.e(TAG, "相机报错 $error", null)
                        camera.close()
                        latch.countDown()
                    }
                },
                handler,
            )
            latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "开相机失败", e)
        } finally {
            try {
                session?.close()
            } catch (_: Exception) {
            }
            try {
                device?.close()
            } catch (_: Exception) {
            }
            reader.close()
            thread.quitSafely()
        }
        return bytes
    }

    /** 相册方向那一格（按屏幕当前旋转；取不到就 0，不猜）。 */
    private fun jpegOrientation(context: Context): Int =
        try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            @Suppress("DEPRECATION")
            when (wm?.defaultDisplay?.rotation) {
                Surface.ROTATION_90 -> 90
                Surface.ROTATION_180 -> 180
                Surface.ROTATION_270 -> 270
                else -> 0
            }
        } catch (e: Exception) {
            0
        }

    /** 落盘（见文件头 ③）：29+ 走 MediaStore 相册；24–28 落本 app 的图片目录。 */
    private fun saveImage(
        context: Context,
        jpeg: ByteArray,
        name: String,
        takenAt: Long,
    ): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, jpeg, name, takenAt)
        } else {
            saveToAppPictures(context, jpeg, name)
        }

    private fun saveViaMediaStore(
        context: Context,
        jpeg: ByteArray,
        name: String,
        takenAt: Long,
    ): Boolean = try {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.DATE_TAKEN, takenAt)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/NoticeTransmit",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return false
        resolver.openOutputStream(uri)?.use { it.write(jpeg) } ?: return false
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        true
    } catch (e: Exception) {
        android.util.Log.e(TAG, "写相册失败", e)
        false
    }

    private fun saveToAppPictures(context: Context, jpeg: ByteArray, name: String): Boolean = try {
        val dir = context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            ?: context.filesDir
        val target = File(dir, name)
        target.writeBytes(jpeg)
        true
    } catch (e: Exception) {
        android.util.Log.e(TAG, "写 app 图片目录失败", e)
        false
    }
}
