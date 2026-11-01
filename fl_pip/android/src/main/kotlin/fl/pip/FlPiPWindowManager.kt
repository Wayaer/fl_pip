package fl.pip

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import fl.multi.engine.FlMultiEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * 统一窗口层：引擎悬浮窗、视频悬浮窗和 Activity 系统画中画共用同一份窗口状态。
 *
 * 窗口状态只有一个：`owner`（engine / video / 无）、`mode`（overlay / systemPip）以及像素几何。
 * 前台服务在这里随窗口显示启动、随窗口关闭停止，`onPiPStatus` 也在这里统一上报。
 *
 * The shared window layer. It owns the single active window state (owner, mode, pixel geometry),
 * creates and removes every window, drives the foreground service and reports the PiP status.
 */
class FlPiPWindowManager private constructor() {
    companion object {
        private const val TAG = "FlPiPWindow"

        // 与 Dart FlPiPStatus 枚举的顺序保持一致。
        // Must stay in sync with the order of the Dart FlPiPStatus enum.
        private const val STATUS_ENABLED = 0
        private const val STATUS_DISABLED = 1
        private const val STATUS_UNAVAILABLE = 2

        private const val MODE_OVERLAY = "overlay"
        private const val MODE_SYSTEM_PIP = "systemPip"

        private const val OVERLAY_PERMISSION_REQUEST_CODE = 4201

        @SuppressLint("StaticFieldLeak")
        private var instance: FlPiPWindowManager? = null

        fun getInstance(): FlPiPWindowManager = instance ?: synchronized(this) {
            instance ?: FlPiPWindowManager().also { instance = it }
        }
    }

    /** 窗口所有者；没有窗口时为 `null`。 / The window owner, `null` when no window is shown. */
    private enum class Owner { ENGINE, VIDEO }

    private val engineManager: FlPiPEngineManager = FlPiPEngineManager.getInstance()

    private var activity: FlutterActivity? = null
    private var context: Context? = null
    private var isForeground = true

    private var owner: Owner? = null
    private var mode: String? = null
    private var systemPipEnabled = false

    /** 当前窗口展示的引擎名称；没有窗口时为 `null`。 */
    private var presentedEngineName: String? = null

    /** `present()` 关联的引擎名称，用于判断 hasEngine；引擎销毁后查询结果自动变为 `false`。 */
    private var pipEngineName: String? = null

    /** `present(name:)` 指定的画中画引擎名称，窗口关闭后引擎被保留时仍然返回该名称。 */
    internal val pipEngineNameForMessages: String?
        get() = pipEngineName

    /** 窗口关闭时是否销毁展示的引擎。 / Whether the presented engine is destroyed on dismissal. */
    private var destroyEngineOnDismiss: Boolean = true

    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null

    /** 当前窗口的像素几何。 / Pixel geometry of the active window. */
    private var overlayGeometry: OverlayGeometry? = null

    private var pendingOverlayResult: MethodChannel.Result? = null
    private var pendingOverlayAction: (() -> Unit)? = null
    private var isRequestingOverlayPermission = false

    /** 宿主 App 的 Application Context；Activity 未创建时为 `null`。 */
    internal val hostContext: Context? get() = context

    /** 当前是否有窗口（引擎或视频）可见。 / Whether any overlay window is currently shown. */
    internal val isWindowActive: Boolean get() = owner != null

    fun setActivity(activity: FlutterActivity, context: Context) {
        this.activity = activity
        this.context = context
    }

    /**
     * Activity 销毁时清除引用，避免单例一直持有已销毁的页面。
     * Clears the destroyed Activity.
     */
    fun clearActivity(activity: FlutterActivity) {
        if (this.activity === activity) {
            this.activity = null
        }
    }

    // ---------------------------------------------------------------------------------------------
    // 窗口展示 / Window presentation
    // ---------------------------------------------------------------------------------------------

    /**
     * 展示指定引擎的窗口：overlay 把引擎放进悬浮窗，systemPip 只缩小宿主 Activity。
     *
     * 引擎不存在时会通过 `fl_multi_engine` 用 `pipMain` 入口补建，成功时返回引擎信息。
     *
     * Shows the engine window: the overlay renders the engine in a floating window, while systemPip
     * only shrinks the host Activity. The engine is created through `fl_multi_engine` when missing.
     */
    fun present(args: Map<*, *>?, result: MethodChannel.Result) {
        if (pendingOverlayResult != null || isRequestingOverlayPermission) {
            result.error(
                FlPiPErrorCode.PERMISSION_REQUEST_IN_PROGRESS,
                "An overlay permission request is already in progress",
                null,
            )
            return
        }

        val arguments: Map<*, *> = args ?: emptyMap<String, Any?>()
        val name = (arguments["name"] as? String).orEmpty()
        if (name.isEmpty()) {
            result.error(FlPiPErrorCode.INVALID_CONFIGURATION, "The engine name must not be empty", null)
            return
        }
        val requestedMode = resolveMode(arguments)
        if (requestedMode == MODE_OVERLAY && !hasOverlayPermission()) {
            requestOverlayPermission(result) { completePresent(arguments, name, result) }
            return
        }
        completePresent(arguments, name, result)
    }

    private fun completePresent(
        args: Map<*, *>,
        name: String,
        result: MethodChannel.Result,
    ) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error(FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED, "MainActivity must extend FlPiPActivity", null)
            return
        }
        val destroy = (args["destroyEngineOnDismiss"] as? Boolean) ?: true
        val requestedMode = resolveMode(args)
        if (requestedMode == MODE_SYSTEM_PIP && !isPiPAvailable(currentActivity)) {
            result.error(FlPiPErrorCode.NOT_SUPPORTED, "Picture-in-picture is not supported on this device", null)
            return
        }
        // 同一时刻只允许一个窗口，视频窗口也算。
        // Only one window at a time; video windows count too.
        if (owner != null) {
            result.error(FlPiPErrorCode.ALREADY_ENABLED, "Picture-in-picture is already enabled", null)
            return
        }
        if (!engineManager.ensureEngine(name)) {
            result.error(FlPiPErrorCode.ENGINE_CREATION_FAILED, "Unable to create the engine $name", null)
            return
        }
        val info = FlMultiEngine.status(name)
        if (info == null) {
            result.error(FlPiPErrorCode.ENGINE_NOT_FOUND, "The engine $name does not exist", null)
            return
        }
        if (info.isMain && destroy) {
            result.error(FlPiPErrorCode.INVALID_CONFIGURATION, "The main engine cannot be destroyed", null)
            return
        }

        presentedEngineName = name
        pipEngineName = name
        destroyEngineOnDismiss = destroy
        val error = if (requestedMode == MODE_SYSTEM_PIP) {
            enableSystemPip(args)
        } else {
            enableEngineOverlay(name, args)
        }
        if (error != null) {
            if (destroy) {
                engineManager.destroy(name)
            } else if (requestedMode == MODE_OVERLAY) {
                engineManager.releaseView()
            }
            resetEngineState()
            result.error(error, "Unable to enable picture-in-picture", null)
            return
        }
        result.success(info.toMap())
    }

    /** 关闭引擎窗口；是否销毁引擎由 `present()` 的 `destroyEngineOnDismiss` 决定。 */
    fun dismiss(result: MethodChannel.Result) {
        // 权限申请过程中调用 dismiss 时，取消挂起的展示，避免授权后窗口又弹出来。
        // Cancel a pending overlay permission flow so granting it does not present a window.
        cancelPendingOverlayRequest()
        val currentActivity = activity
        if (currentActivity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            currentActivity.isInPictureInPictureMode
        ) {
            launchApp()
        }
        // 视频窗口由 FlPiPVideo 的 stop 关闭，这里只处理引擎窗口。
        // Video windows are closed by FlPiPVideo.stop; only the engine window is handled here.
        if (owner == Owner.ENGINE) {
            requestDismissEngine()
        }
        result.success(true)
    }

    /** 关闭引擎窗口；按展示时记录的 `destroyEngineOnDismiss` 决定是否销毁引擎。 */
    private fun requestDismissEngine() {
        val name = presentedEngineName
        val shouldDestroy = destroyEngineOnDismiss
        detachWindow()
        if (name != null) {
            if (shouldDestroy) {
                engineManager.destroy(name)
            } else {
                engineManager.releaseView()
            }
        }
        resetEngineState()
        setPiPStatus(STATUS_DISABLED)
    }

    private fun resetEngineState() {
        presentedEngineName = null
        destroyEngineOnDismiss = true
    }

    /**
     * 展示视频悬浮窗，内容视图、几何与拖拽均由窗口层负责。
     *
     * Shows the video overlay; the content view, geometry and dragging are owned by this layer.
     */
    fun showVideoWindow(
        content: View,
        args: Map<*, *>,
        cornerRadius: Double,
        allowDrag: () -> Boolean,
        onTap: () -> Unit,
    ): Boolean {
        val currentContext = context ?: return false
        if (owner != null) return false

        val geometry = resolveGeometry(args, currentContext)
        val params = buildOverlayParams(geometry)
        val root = FrameLayout(currentContext).apply {
            // 内容尚未准备好时窗口保持黑色，避免整块悬浮窗透出下层界面。
            // Keep the window black before content is ready so it never looks transparent.
            setBackgroundColor(Color.BLACK)
        }
        root.addView(
            content,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        applyRoundedCorners(root, dp2px(currentContext, cornerRadius))
        root.setOnTouchListener(
            OverlayDragTouchListener(
                layoutParams = params,
                context = currentContext,
                windowManagerProvider = { windowManager },
                rootViewProvider = { rootView },
                allowDrag = allowDrag,
                onTap = onTap,
                consumeTouch = true,
            ),
        )
        val installed = installWindow(Owner.VIDEO, MODE_OVERLAY, root, params)
        if (installed) setPiPStatus(STATUS_ENABLED)
        return installed
    }

    /** 关闭视频悬浮窗。 / Closes the video overlay. */
    fun closeVideoWindow() {
        if (owner != Owner.VIDEO) return
        detachWindow()
        setPiPStatus(STATUS_DISABLED)
    }

    /**
     * 引擎被 FlMultiEngine 外部销毁时关闭挂载在它上面的悬浮窗。
     * Closes the overlay that renders a destroyed engine.
     */
    fun onEngineDestroyed() {
        if (owner != Owner.ENGINE || mode != MODE_OVERLAY) return
        detachWindow()
        resetEngineState()
        setPiPStatus(STATUS_DISABLED)
    }

    private fun enableEngineOverlay(
        name: String,
        args: Map<*, *>,
    ): String? {
        val currentContext = context ?: return FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED
        if (!hasOverlayPermission()) return FlPiPErrorCode.PERMISSION_DENIED

        val geometry = resolveGeometry(args, currentContext)
        val params = buildOverlayParams(geometry)
        val cornerRadius = (args["cornerRadius"] as? Number)?.toDouble() ?: 12.0

        val flutterView = engineManager.attachEngineFlutterView(currentContext, name)
            ?: return FlPiPErrorCode.ENGINE_NOT_FOUND
        val root = FrameLayout(currentContext).apply {
            // 引擎首帧绘制前保持黑色，避免悬浮窗透出下层界面。
            // Stay black until the engine draws its first frame.
            setBackgroundColor(Color.BLACK)
            addView(
                flutterView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        applyRoundedCorners(root, dp2px(currentContext, cornerRadius))
        addCloseIcon(root, currentContext)
        flutterView.setOnTouchListener(
            OverlayDragTouchListener(
                layoutParams = params,
                context = currentContext,
                windowManagerProvider = { windowManager },
                rootViewProvider = { rootView },
            ),
        )

        if (!installWindow(Owner.ENGINE, MODE_OVERLAY, root, params)) {
            return FlPiPErrorCode.OVERLAY_CREATION_FAILED
        }
        setPiPStatus(STATUS_ENABLED)
        return null
    }

    private fun enableSystemPip(args: Map<*, *>): String? {
        val currentActivity = activity ?: return FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return FlPiPErrorCode.NOT_SUPPORTED

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            currentActivity.enterPictureInPictureMode()
        } else {
            val ratio = try {
                Rational(
                    ((args["numerator"] as? Number)?.toInt() ?: 1).coerceAtLeast(1),
                    ((args["denominator"] as? Number)?.toInt() ?: 1).coerceAtLeast(1),
                )
            } catch (exception: IllegalArgumentException) {
                Log.e(TAG, "Invalid aspect ratio", exception)
                return FlPiPErrorCode.INVALID_CONFIGURATION
            }

            val builder = PictureInPictureParams.Builder().apply {
                setAspectRatio(ratio)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setSeamlessResizeEnabled(false)
                }
            }
            val entered = try {
                currentActivity.enterPictureInPictureMode(builder.build())
            } catch (exception: IllegalArgumentException) {
                Log.e(TAG, "Unable to enter picture-in-picture mode", exception)
                false
            }
            if (!entered) return FlPiPErrorCode.START_FAILED
        }

        owner = Owner.ENGINE
        mode = MODE_SYSTEM_PIP
        systemPipEnabled = true
        setPiPStatus(STATUS_ENABLED)
        return null
    }

    private fun installWindow(
        windowOwner: Owner,
        windowMode: String,
        root: FrameLayout,
        params: WindowManager.LayoutParams,
    ): Boolean {
        val currentContext = context ?: return false
        val manager = currentContext.getSystemService(Service.WINDOW_SERVICE) as? WindowManager
            ?: return false
        return try {
            manager.addView(root, params)
            windowManager = manager
            rootView = root
            overlayGeometry = OverlayGeometry(params.width, params.height, params.x, params.y)
            owner = windowOwner
            mode = windowMode
            // 悬浮窗同样需要前台服务保活，否则 App 在后台时进程可能被回收。
            // Overlays need the foreground service so the process survives in the background.
            FlPiPForegroundService.start(currentContext, media = windowOwner == Owner.VIDEO)
            true
        } catch (exception: Exception) {
            Log.e(TAG, "Unable to create the floating window", exception)
            try {
                manager.removeView(root)
            } catch (removeException: Exception) {
                Log.w(TAG, "Unable to remove the floating window", removeException)
            }
            windowManager = null
            rootView = null
            overlayGeometry = null
            owner = null
            mode = null
            false
        }
    }

    /**
     * 移除当前窗口并停止前台服务，窗口状态归零。
     * Removes the window, stops the foreground service and resets the state.
     */
    private fun detachWindow() {
        val root = rootView
        if (root != null) {
            try {
                windowManager?.removeView(root)
            } catch (exception: Exception) {
                Log.w(TAG, "Unable to remove the floating window", exception)
            }
        }
        windowManager = null
        rootView = null
        overlayGeometry = null
        // 先清空 owner，再销毁引擎，避免销毁回调重复关闭窗口。
        // Clear the owner before destroying the engine so the destroy callback does not run twice.
        owner = null
        mode = null
        context?.let { FlPiPForegroundService.stop(it) }
    }

    private fun addCloseIcon(root: FrameLayout, currentContext: Context) {
        val close = ImageView(currentContext).apply {
            setImageResource(R.drawable.fl_pip_ic_close)
            scaleType = ImageView.ScaleType.CENTER
            setPadding(
                dp2px(currentContext, 5),
                dp2px(currentContext, 5),
                dp2px(currentContext, 5),
                dp2px(currentContext, 5),
            )
            setOnClickListener { closeEngineOverlay() }
        }
        val params = FrameLayout.LayoutParams(dp2px(currentContext, 24), dp2px(currentContext, 24)).apply {
            gravity = Gravity.END or Gravity.TOP
            setMargins(0, dp2px(currentContext, 8), dp2px(currentContext, 8), 0)
        }
        root.addView(close, params)
    }

    private fun closeEngineOverlay() {
        moveTaskToFront()
        if (owner != Owner.ENGINE || mode != MODE_OVERLAY) return
        requestDismissEngine()
    }

    // ---------------------------------------------------------------------------------------------
    // 宿主状态与权限 / Host state and permissions
    // ---------------------------------------------------------------------------------------------

    /**
     * 申请悬浮窗权限，用户授权后执行 [action]；授权被拒绝或跳转失败时直接回调错误。
     * [action] 必须且只能调用一次 `result`。
     *
     * Requests the overlay permission and runs [action] when the user grants it.
     */
    fun requestOverlayPermission(result: MethodChannel.Result, action: () -> Unit) {
        val currentActivity = activity
        val currentContext = context
        if (currentActivity == null || currentContext == null) {
            result.error(FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED, "MainActivity must extend FlPiPActivity", null)
            return
        }
        if (isRequestingOverlayPermission) {
            result.error(
                FlPiPErrorCode.PERMISSION_REQUEST_IN_PROGRESS,
                "An overlay permission request is already in progress",
                null,
            )
            return
        }

        pendingOverlayResult = result
        pendingOverlayAction = action
        isRequestingOverlayPermission = true
        try {
            currentActivity.startActivityForResult(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${currentContext.packageName}")),
                OVERLAY_PERMISSION_REQUEST_CODE,
            )
        } catch (exception: Exception) {
            Log.e(TAG, "Unable to open the overlay permission settings", exception)
            finishOverlayPermissionRequest(false)
        }
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != OVERLAY_PERMISSION_REQUEST_CODE) return
        finishOverlayPermissionRequest(hasOverlayPermission())
    }

    /**
     * 取消挂起的悬浮窗权限请求；之后的授权结果不会触发窗口创建。
     *
     * Cancels a pending overlay permission request so a later grant does not create a window.
     */
    private fun cancelPendingOverlayRequest() {
        if (!isRequestingOverlayPermission) return
        isRequestingOverlayPermission = false
        val result = pendingOverlayResult
        pendingOverlayResult = null
        pendingOverlayAction = null
        result?.error(
            FlPiPErrorCode.START_FAILED,
            "Picture-in-picture was disabled while requesting the overlay permission",
            null,
        )
    }

    private fun finishOverlayPermissionRequest(granted: Boolean) {
        if (!isRequestingOverlayPermission) return
        isRequestingOverlayPermission = false
        val result = pendingOverlayResult ?: return
        val action = pendingOverlayAction
        pendingOverlayResult = null
        pendingOverlayAction = null
        if (!granted) {
            result.error(FlPiPErrorCode.PERMISSION_DENIED, "The overlay permission was denied", null)
            return
        }
        try {
            action?.invoke()
        } catch (exception: Exception) {
            Log.e(TAG, "Overlay permission action failed", exception)
            result.error(FlPiPErrorCode.OVERLAY_CREATION_FAILED, exception.message ?: "Unable to start the overlay", null)
        }
    }

    fun hasOverlayPermission(): Boolean = context?.let { Settings.canDrawOverlays(it) } ?: false

    fun isPiPAvailable(currentContext: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            currentContext.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    // ---------------------------------------------------------------------------------------------
    // 前后台与状态 / App state and status
    // ---------------------------------------------------------------------------------------------

    /** 切换 App 前后台。 / Switches the app between foreground and background. */
    fun toggle(foreground: Boolean, result: MethodChannel.Result) {
        if (foreground) {
            if (activity == null) {
                result.error(FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED, "MainActivity must extend FlPiPActivity", null)
                return
            }
            launchApp()
        } else {
            background()
        }
        result.success(null)
    }

    /** 当前画中画状态快照，字段与 Dart [FlPiPStatusInfo] 保持一致。 */
    fun currentStatusMap(): Map<String, Any?> = statusMap(active = isWindowActive)

    private fun statusMap(active: Boolean): Map<String, Any?> {
        val available = context?.let { isPiPAvailable(it) } ?: false
        // hasEngine 只反映 present() 关联的引擎是否仍存在，与窗口是否展示无关。
        // hasEngine only reflects whether the engine from present() still exists, whether or not
        // the window is visible.
        val hasEngine = pipEngineName?.let { engineManager.isRunning(it) } == true
        return mutableMapOf(
            "status" to when {
                !available -> STATUS_UNAVAILABLE
                active -> STATUS_ENABLED
                else -> STATUS_DISABLED
            },
            "mode" to if (active) mode else null,
            // present 始终会按 name 创建引擎，systemPip 只是不渲染它。
            "hasEngine" to hasEngine,
        )
    }

    private fun isEngineWindowActive(): Boolean = when {
        owner != Owner.ENGINE -> false
        mode == MODE_OVERLAY -> true
        mode == MODE_SYSTEM_PIP -> systemPipEnabled ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity?.isInPictureInPictureMode == true)
        else -> false
    }

    private fun setPiPStatus(status: Int) {
        FlPiPPlugin.broadcast("onPiPStatus", statusMap(active = status == STATUS_ENABLED))
    }

    /** Activity 进入后台时记录前后台状态。 / Records the background state when the activity pauses. */
    fun onActivityPaused() {
        isForeground = false
    }

    fun onActivityResume() {
        isForeground = true
        if (isRequestingOverlayPermission) {
            // 个别设备的权限设置页不会返回结果，回到前台时主动校验一次。
            // The permission settings page may not report a result on every device.
            finishOverlayPermissionRequest(hasOverlayPermission())
        }
    }

    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        systemPipEnabled = isInPictureInPictureMode
        if (!isInPictureInPictureMode && owner == Owner.ENGINE && mode == MODE_SYSTEM_PIP) {
            // 系统画中画结束后释放窗口状态，并按 present 的设置销毁或保留引擎。
            // Release the window state after leaving system PiP, destroying or keeping the engine.
            val name = presentedEngineName
            val shouldDestroy = destroyEngineOnDismiss
            owner = null
            mode = null
            if (name != null) {
                if (shouldDestroy) {
                    engineManager.destroy(name)
                } else {
                    engineManager.releaseView()
                }
            }
            resetEngineState()
            setPiPStatus(STATUS_DISABLED)
            return
        }
        setPiPStatus(if (isEngineWindowActive()) STATUS_ENABLED else STATUS_DISABLED)
    }

    private fun background() {
        if (!isForeground) return
        activity?.startActivity(
            Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) },
        )
    }

    private fun launchApp() {
        if (isForeground) return
        val currentActivity = activity ?: return
        val intent = currentActivity.packageManager.getLaunchIntentForPackage(currentActivity.packageName) ?: return
        intent.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        currentActivity.startActivity(intent)
    }

    private fun moveTaskToFront() {
        val currentActivity = activity ?: return
        (context?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)?.moveTaskToFront(
            currentActivity.taskId,
            ActivityManager.MOVE_TASK_WITH_HOME,
        )
    }

    // ---------------------------------------------------------------------------------------------
    // 几何与视图 / Geometry and views
    // ---------------------------------------------------------------------------------------------

    private class OverlayGeometry(val width: Int, val height: Int, val left: Int, val top: Int)

    private fun resolveMode(args: Map<*, *>): String =
        if (args["mode"] as? String == MODE_SYSTEM_PIP) MODE_SYSTEM_PIP else MODE_OVERLAY

    /**
     * 宽高与位置全部是物理像素；未指定宽高时宽度接近铺满屏幕，高度按 16:9 计算。
     *
     * Size and offsets are physical pixels; without an explicit size the window takes almost the
     * full width with a 16:9 height.
     */
    private fun resolveGeometry(args: Map<*, *>, currentContext: Context): OverlayGeometry {
        val metrics = currentContext.resources.displayMetrics
        val margin = dp2px(currentContext, 16)
        // 自定义宽高不能超过屏幕，偏移也不能超过“屏幕尺寸 - 窗口尺寸”，保证整个悬浮窗都在屏幕内。
        // The custom size never exceeds the screen and the offsets are clamped so the whole overlay
        // stays on screen.
        val requestedWidth = (args["width"] as? Number)?.toInt()
        val requestedHeight = (args["height"] as? Number)?.toInt()
        val width = (requestedWidth ?: (metrics.widthPixels - margin * 2).coerceAtLeast(1))
            .coerceIn(1, metrics.widthPixels)
        val height = (requestedHeight ?: (width * 9 / 16).coerceAtLeast(1))
            .coerceIn(1, metrics.heightPixels)
        val maxLeft = (metrics.widthPixels - width).coerceAtLeast(0)
        val maxTop = (metrics.heightPixels - height).coerceAtLeast(0)
        val left = ((args["left"] as? Number)?.toInt() ?: (maxLeft / 2)).coerceIn(0, maxLeft)
        val top = ((args["top"] as? Number)?.toInt() ?: (maxTop / 2)).coerceIn(0, maxTop)
        return OverlayGeometry(width, height, left, top)
    }

    private fun buildOverlayParams(geometry: OverlayGeometry): WindowManager.LayoutParams =
        WindowManager.LayoutParams().apply {
            type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_TOAST
            }
            format = PixelFormat.TRANSLUCENT
            // TextureView 只在硬件加速窗口中绘制；WindowManager 手动添加的窗口默认是软件渲染。
            // TextureView only draws in a hardware-accelerated window, which is not the default here.
            flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            width = geometry.width
            height = geometry.height
            gravity = Gravity.START or Gravity.TOP
            x = geometry.left
            y = geometry.top
        }

    /**
     * 给悬浮窗根视图按像素半径裁剪圆角。
     * Clips the overlay root view to the given corner radius in pixels.
     */
    private fun applyRoundedCorners(target: View, radiusPx: Float) {
        if (radiusPx <= 0f) return
        target.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, radiusPx)
            }
        }
        target.clipToOutline = true
    }

    private fun dp2px(currentContext: Context, value: Int): Int {
        val scale = currentContext.resources.displayMetrics.density
        return (value * scale + 0.5f).toInt()
    }

    private fun dp2px(currentContext: Context, value: Double): Float {
        val scale = currentContext.resources.displayMetrics.density
        return (value * scale).toFloat()
    }

    /**
     * 悬浮窗拖拽：拖动时限制在屏幕内，松手后自动回到带边距的位置，
     * 贴近 iOS 画中画的停靠效果。引擎与视频悬浮窗共用同一套拖动行为。
     *
     * Overlay drag: keeps the window on screen while dragging and springs it back inside a small
     * edge margin on release. Engine and video overlays share the same behavior.
     */
    private class OverlayDragTouchListener(
        private val layoutParams: WindowManager.LayoutParams,
        private val context: Context,
        private val windowManagerProvider: () -> WindowManager?,
        private val rootViewProvider: () -> View?,
        private val edgeMarginDp: Int = 8,
        private val allowDrag: () -> Boolean = { true },
        private val onTap: (() -> Unit)? = null,
        // 挂在不接收触摸的容器上（如媒体窗口根视图）时需要消费事件，
        // 避免手势穿透到底层应用；挂在 FlutterView 上时必须返回 false，
        // 否则引擎页面收不到任何触摸。
        // Consume touches when attached to a passive container so gestures do not fall through to
        // the app behind; return false when attached to a FlutterView so the engine still gets touches.
        private val consumeTouch: Boolean = false,
    ) : View.OnTouchListener {
        private var initialX = 0
        private var initialY = 0
        private var initialTouchX = 0f
        private var initialTouchY = 0f
        private var moved = false
        private var animator: ValueAnimator? = null

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(view: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    animator?.cancel()
                    initialX = layoutParams.x
                    initialY = layoutParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                }

                MotionEvent.ACTION_MOVE -> {
                    if (!allowDrag()) return consumeTouch
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!moved && (abs(dx) > 5 || abs(dy) > 5)) moved = true
                    val metrics = context.resources.displayMetrics
                    val maxX = (metrics.widthPixels - layoutParams.width).coerceAtLeast(0)
                    val maxY = (metrics.heightPixels - layoutParams.height).coerceAtLeast(0)
                    layoutParams.x = (initialX + dx).toInt().coerceIn(0, maxX)
                    layoutParams.y = (initialY + dy).toInt().coerceIn(0, maxY)
                    updateLayout()
                }

                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        springToEdge()
                    } else {
                        onTap?.invoke()
                    }
                }

                MotionEvent.ACTION_CANCEL -> springToEdge()
            }
            return consumeTouch
        }

        private fun updateLayout() {
            val manager = windowManagerProvider() ?: return
            val root = rootViewProvider() ?: return
            manager.updateViewLayout(root, layoutParams)
        }

        private fun springToEdge() {
            val metrics = context.resources.displayMetrics
            val margin = (edgeMarginDp * metrics.density).toInt()
            val maxX = (metrics.widthPixels - layoutParams.width).coerceAtLeast(0)
            val maxY = (metrics.heightPixels - layoutParams.height).coerceAtLeast(0)
            val minX = margin.coerceAtMost(maxX)
            val minY = margin.coerceAtMost(maxY)
            val maxAllowedX = (maxX - margin).coerceAtLeast(minX)
            val maxAllowedY = (maxY - margin).coerceAtLeast(minY)
            val targetX = layoutParams.x.coerceIn(minX, maxAllowedX)
            val targetY = layoutParams.y.coerceIn(minY, maxAllowedY)
            if (targetX == layoutParams.x && targetY == layoutParams.y) return

            val startX = layoutParams.x
            val startY = layoutParams.y
            animator?.cancel()
            animator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 180
                addUpdateListener { animation ->
                    val fraction = animation.animatedValue as Float
                    layoutParams.x = startX + ((targetX - startX) * fraction).toInt()
                    layoutParams.y = startY + ((targetY - startY) * fraction).toInt()
                    updateLayout()
                }
                start()
            }
        }
    }
}
