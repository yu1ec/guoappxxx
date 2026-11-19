package com.duanju.duanjuapp

import io.flutter.embedding.android.FlutterActivity
import android.app.UiModeManager
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.BatteryManager
import android.os.PowerManager
import android.os.SystemClock
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.net.ConnectivityManager
import android.net.Uri
import android.util.Rational
import android.view.InputDevice
import android.view.WindowManager
import android.provider.Settings
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private fun hasAllFilesAccess(): Boolean = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
            Environment.isExternalStorageManager()
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        else -> true
    }

  private fun requestStorageAccess() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      runCatching {
        startActivity(
          Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
          }
        )
      }.onFailure {
        startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
      }
      return
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      @Suppress("DEPRECATION")
      requestPermissions(
        arrayOf(
          android.Manifest.permission.READ_EXTERNAL_STORAGE,
          android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ),
        90210,
      )
    }
  }

    private var headroomReadAt = 0L
    private var thermalHeadroom: Double? = null
    private var deviceChannel: MethodChannel? = null
    private var castChannel: MethodChannel? = null
    private var cast: DlnaCast? = null
    private var televisionMode = false

    @Suppress("DEPRECATION")
    private fun isTelevisionDevice(): Boolean {
        val configuration = resources.configuration
        val mode = (getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType
            ?: (configuration.uiMode and Configuration.UI_MODE_TYPE_MASK)
        if (mode == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            packageManager.hasSystemFeature("amazon.hardware.fire_tv")) {
            return true
        }
        if (mode == Configuration.UI_MODE_TYPE_CAR ||
            mode == Configuration.UI_MODE_TYPE_WATCH ||
            mode == Configuration.UI_MODE_TYPE_VR_HEADSET ||
            configuration.touchscreen != Configuration.TOUCHSCREEN_NOTOUCH ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_ACCELEROMETER) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_PC)) {
            return false
        }
        val remoteNavigation = configuration.navigation == Configuration.NAVIGATION_DPAD ||
            InputDevice.getDeviceIds().any { id ->
                val device = InputDevice.getDevice(id)
                device != null && !device.isVirtual && device.supportsSource(InputDevice.SOURCE_DPAD)
            }
        return remoteNavigation || packageManager.hasSystemFeature(PackageManager.FEATURE_LIVE_TV)
    }

    private fun renderingPreferences() =
        getSharedPreferences("duanju_rendering", Context.MODE_PRIVATE)

    private fun compatibleRendering(): Boolean =
        renderingPreferences().getBoolean("compatibleRendering", false)

    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        if (compatibleRendering()) args.add("--enable-impeller=false")
        return args
    }

    private fun restartApplication() {
        startActivity(Intent.makeRestartActivityTask(ComponentName(this, MainActivity::class.java)))
        Runtime.getRuntime().exit(0)
    }

    private fun installedApkAbi(): String {
        val libDir = applicationInfo.nativeLibraryDir.orEmpty()
        return when {
            libDir.contains("arm64") -> "arm64-v8a"
            libDir.contains("x86_64") -> "x86_64"
            libDir.contains("x86") && !libDir.contains("x86_64") -> "x86"
            libDir.contains("arm") -> "armeabi-v7a"
            else -> "arm64-v8a"
        }
    }

    private fun packageVersionLabel(): String {
        @Suppress("DEPRECATION")
        val pkg = packageManager.getPackageInfo(packageName, 0)
        val name = pkg.versionName.orEmpty()
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pkg.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            pkg.versionCode.toLong()
        }
        // Flutter split-per-abi 会给 versionCode 加 ABI 前缀（×1000），须还原 pubspec 构建号。
        val build = if (code >= 1000) code % 1000 else code
        return if (name.isNotEmpty()) "$name+$build" else build.toString()
    }

    override fun setRequestedOrientation(requestedOrientation: Int) {
        super.setRequestedOrientation(
            if (televisionMode) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else requestedOrientation
        )
    }

    private fun playbackPower(): Map<String, Any?> {
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val activity = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val now = SystemClock.elapsedRealtime()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            (headroomReadAt == 0L || now - headroomReadAt >= 10000L)) {
            headroomReadAt = now
            thermalHeadroom = runCatching {
                power?.getThermalHeadroom(0)?.toDouble()?.takeIf { it.isFinite() }
            }.getOrNull()
        }
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            power?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
        } else 0
        return mapOf(
            "batterySaver" to (power?.isPowerSaveMode ?: false),
            "onBattery" to ((battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1) <= 0),
            "thermalStatus" to thermalStatus,
            "headroom" to thermalHeadroom,
            "lowMemory" to (activity?.isLowRamDevice ?: true),
            "gles" to (activity?.deviceConfigurationInfo?.reqGlEsVersion ?: 0)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        televisionMode = if (savedInstanceState?.containsKey("duanju.televisionMode") == true) {
            savedInstanceState.getBoolean("duanju.televisionMode")
        } else isTelevisionDevice()
        super.onCreate(savedInstanceState)
        if (televisionMode) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onResume() {
        super.onResume()
        if (televisionMode) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("duanju.televisionMode", televisionMode)
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duanju/device")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "deviceInfo" -> {
                            result.success(
                                mapOf(
                                    "television" to isTelevisionDevice(),
                                    "version" to packageVersionLabel(),
                                    "apkAbi" to installedApkAbi(),
                                )
                            )
                        }
                        "installApk" -> {
                            val path = call.argument<String>("path")
                            if (path.isNullOrBlank()) {
                                result.error("invalid_path", "缺少 APK 路径", null)
                            } else {
                                val file = File(path)
                                if (!file.isFile) {
                                    result.error("missing_file", "安装包不存在", null)
                                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                    !packageManager.canRequestPackageInstalls()
                                ) {
                                    runCatching {
                                        startActivity(
                                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                                data = Uri.parse("package:$packageName")
                                            }
                                        )
                                    }
                                    result.error("need_permission", "请允许安装未知应用后重试", null)
                                } else {
                                    try {
                                        val uri = FileProvider.getUriForFile(
                                            this,
                                            "$packageName.fileprovider",
                                            file,
                                        )
                                        val intent = Intent(Intent.ACTION_VIEW).apply {
                                            setDataAndType(uri, "application/vnd.android.package-archive")
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                        startActivity(intent)
                                        result.success(null)
                                    } catch (e: Exception) {
                                        result.error("install_failed", e.message, null)
                                    }
                                }
                            }
                        }
                        "openUrl" -> {
                            val url = call.argument<String>("url")
                            if (url.isNullOrBlank()) {
                                result.error("invalid_url", "链接为空", null)
                            } else {
                                try {
                                    startActivity(
                                        Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                    )
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error("open_failed", e.message, null)
                                }
                            }
                        }
                        "setTelevisionMode" -> {
                            val enabled = call.argument<Boolean>("enabled")
                            if (enabled == null) {
                                result.error("invalid_display_mode", "缺少电视模式状态", null)
                            } else {
                                val changed = televisionMode != enabled
                                televisionMode = enabled
                                if (enabled || changed) {
                                    requestedOrientation = if (enabled) {
                                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                                    } else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                                }
                                result.success(null)
                            }
                        }
                        "playbackPower" -> result.success(runCatching { playbackPower() }.getOrNull())
                        "compatibleRendering" -> result.success(compatibleRendering())
                        "setCompatibleRendering" -> {
                            val enabled = call.argument<Boolean>("enabled")
                            if (enabled == null) {
                                result.error("invalid_rendering_mode", "缺少兼容渲染模式状态", null)
                            } else if (!renderingPreferences().edit()
                                    .putBoolean("compatibleRendering", enabled).commit()) {
                                result.error("rendering_mode_not_saved", "兼容渲染模式未能保存", null)
                            } else {
                                result.success(null)
                                restartApplication()
                            }
                        }
                        "systemProxy" -> {
                            val connection = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                            val proxy = connection.defaultProxy
                            val host = proxy?.host.orEmpty()
                            val address = if (host.isNotEmpty() && (proxy?.port ?: 0) > 0) {
                                "http://${if (host.contains(':')) "[$host]" else host}:${proxy!!.port}"
                            } else ""
                            result.success(mapOf(
                                "http" to address,
                                "https" to address,
                                "bypass" to (proxy?.exclusionList?.toList() ?: emptyList<String>()),
                                "pac" to (proxy != null && proxy.pacFileUrl != Uri.EMPTY)
                            ))
                        }
                        "pictureInPictureStatus" -> result.success(pictureInPictureStatus())
                        "enterPictureInPicture" -> {
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            result.success(enterPlayerPictureInPicture(
                                width,
                                height,
                                call.argument<Int>("left"),
                                call.argument<Int>("top"),
                                call.argument<Int>("right"),
                                call.argument<Int>("bottom")
                            ))
                        }
                        "getBrightness" -> {
                            val lp = window.attributes
                            val current = if (lp.screenBrightness >= 0f) {
                                lp.screenBrightness.toDouble()
                            } else {
                                try {
                                    val sys = Settings.System.getInt(
                                        contentResolver,
                                        Settings.System.SCREEN_BRIGHTNESS
                                    )
                                    (sys / 255.0).coerceIn(0.0, 1.0)
                                } catch (e: Exception) {
                                    0.5
                                }
                            }
                            result.success(current)
                        }
                        "setBrightness" -> {
                            val value = call.argument<Double>("brightness")?.toFloat()
                            if (value != null) {
                                val lp = window.attributes
                                lp.screenBrightness = value.coerceIn(0.01f, 1.0f)
                                window.attributes = lp
                                result.success(true)
                            } else {
                                result.error("invalid_arg", "缺少亮度数值", null)
                            }
                        }
                        "resetBrightness" -> {
                            val lp = window.attributes
                            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = lp
                            result.success(true)
                        }
                        "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                        "publicDownloadDirectory" -> {
                            @Suppress("DEPRECATION")
                            result.success(
                                Environment.getExternalStoragePublicDirectory(
                                    Environment.DIRECTORY_DOWNLOADS
                                ).absolutePath
                            )
                        }
                        "requestStorageAccess" -> {
                            requestStorageAccess()
                            result.success(null)
                        }
                        "scanMediaFile" -> {
                            val path = call.arguments as? String
                            if (path.isNullOrBlank()) {
                                result.error("invalid_path", "缺少要扫描的文件路径", null)
                            } else {
                                MediaScannerConnection.scanFile(
                                    this,
                                    arrayOf(path),
                                    arrayOf("video/mp4"),
                                    null,
                                )
                                result.success(null)
                            }
                        }
                        "openExternalPlayer" -> {
                            val url = call.argument<String>("url")
                            val title = call.argument<String>("title") ?: "短剧"
                            if (!url.isNullOrEmpty()) {
                                try {
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(Uri.parse(url), "video/*")
                                        putExtra("title", title)
                                        putExtra("return_result", true)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("no_player", "未找到外部播放器: ${e.message}", null)
                                }
                            } else {
                                result.error("invalid_url", "播放地址为空", null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        // 投屏（DLNA）：Flutter 侧只负责选设备与按钮，搜索 / SOAP 下发都在
        // DlnaCast 的单线程里跑，网络耗时不能占主线程。
        val dlna = DlnaCast(applicationContext)
        cast = dlna
        castChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duanju/cast")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "discover" -> dlna.discover { devices, error ->
                            result.success(
                                mapOf(
                                    "devices" to devices.map { it.toMap() },
                                    "error" to error
                                )
                            )
                        }
                        "play" -> {
                            val control = call.argument<String>("controlUrl").orEmpty()
                            val url = call.argument<String>("url").orEmpty()
                            val title = call.argument<String>("title").orEmpty()
                            val position = call.argument<Number>("positionMs")?.toLong() ?: 0L
                            // 直连投屏电视自己拉流，只有转发才需要手机保持唤醒。
                            val relay = call.argument<Boolean>("relay") ?: false
                            if (control.isEmpty() || url.isEmpty()) {
                                result.error("invalid_cast", "缺少投屏设备或播放地址", null)
                            } else {
                                dlna.play(control, url, title, position, relay) { ok, message ->
                                    if (ok) result.success(null)
                                    else result.error("cast_failed", message, null)
                                }
                            }
                        }
                        "control" -> {
                            val control = call.argument<String>("controlUrl").orEmpty()
                            val command = call.argument<String>("command").orEmpty()
                            if (control.isEmpty() || command.isEmpty()) {
                                result.error("invalid_cast", "缺少投屏设备或操作", null)
                            } else {
                                dlna.control(control, command) { ok, message ->
                                    if (ok) result.success(null)
                                    else result.error("cast_failed", message, null)
                                }
                            }
                        }
                        "status" -> {
                            val control = call.argument<String>("controlUrl").orEmpty()
                            if (control.isEmpty()) {
                                result.success(mapOf("state" to "UNKNOWN"))
                            } else {
                                dlna.status(control) { state -> result.success(state) }
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.O)
    private fun pictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun pictureInPictureStatus(): Map<String, Any> {
        return mapOf(
            "supported" to pictureInPictureSupported(),
            "active" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode)
        )
    }

    private fun enterPlayerPictureInPicture(
        width: Int,
        height: Int,
        left: Int?,
        top: Int?,
        right: Int?,
        bottom: Int?
    ): Map<String, Any> {
        if (!pictureInPictureSupported()) return pictureInPictureStatus()
        val safeWidth = width.coerceIn(1, 10000)
        val safeHeight = height.coerceIn(1, 10000)
        return runCatching {
            val builder = PictureInPictureParams.Builder()
            builder.setAspectRatio(Rational(safeWidth, safeHeight))
            if (left != null && top != null && right != null && bottom != null &&
                right > left && bottom > top) {
                builder.setSourceRectHint(Rect(left, top, right, bottom))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(true)
            }
            val entered = enterPictureInPictureMode(builder.build())
            pictureInPictureStatus() + ("requested" to entered)
        }.getOrElse { pictureInPictureStatus() }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        deviceChannel?.invokeMethod(
            "pictureInPictureChanged",
            mapOf("active" to isInPictureInPictureMode)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        deviceChannel?.setMethodCallHandler(null)
        deviceChannel = null
        castChannel?.setMethodCallHandler(null)
        castChannel = null
        cast?.close()
        cast = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
