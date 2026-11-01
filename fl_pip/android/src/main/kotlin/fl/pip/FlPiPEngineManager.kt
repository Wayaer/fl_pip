package fl.pip

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import fl.multi.engine.FlMultiEngine
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView

/**
 * 画中画引擎的视图挂载与销毁，引擎实例本身统一交给 fl_multi_engine 管理。
 *
 * `present()` 传入的引擎名直接使用 Flutter 通过 fl_multi_engine 创建的引擎；本类只负责把
 * FlutterView 挂到对应引擎上，并在引擎被外部销毁时通知窗口层。
 *
 * Attaches and detaches the FlutterView for engine windows. Engine instances are owned by
 * fl_multi_engine; windows reuse the named engines created by Flutter.
 */
class FlPiPEngineManager private constructor() {
    companion object {
        private const val TAG = "FlPiPEngine"

        private const val ENTRYPOINT = "pipMain"

        @SuppressLint("StaticFieldLeak")
        private var instance: FlPiPEngineManager? = null

        fun getInstance(): FlPiPEngineManager = instance ?: synchronized(this) {
            instance ?: FlPiPEngineManager().also { instance = it }
        }
    }

    private var flutterView: FlutterView? = null

    /** 当前视图挂载的引擎名称；没有视图时为 `null`。 */
    private var attachedEngineName: String? = null

    /**
     * 已附着平台视图控制器的引擎名称；每个引擎的控制器只能附着一次，重复附例会抛出
     * `AssertionError`。
     *
     * Name of the engine whose platform views controller is attached; it can only be attached once.
     */
    private var platformViewsEngineName: String? = null

    init {
        // 引擎被外部销毁时先解绑视图，再关闭挂在它上面的悬浮窗。
        // Detach the view first, then close the overlay that renders it.
        FlMultiEngine.addEngineDestroyListener { name ->
            if (name == attachedEngineName || name == platformViewsEngineName) handleExternalDestroy()
        }
    }

    /** 指定引擎是否已创建。 / Whether the engine called [name] exists. */
    fun isRunning(name: String): Boolean = FlMultiEngine.engine(name) != null

    /**
     * 确保指定名称的引擎已创建；不存在时用 `pipMain` 入口补建。
     *
     * Ensures the engine called [name] exists, creating it with the `pipMain` entry point when it
     * was not created by Flutter yet.
     */
    fun ensureEngine(name: String): Boolean {
        if (isRunning(name)) return true
        return try {
            FlMultiEngine.create(name, ENTRYPOINT)
            true
        } catch (exception: Exception) {
            Log.e(TAG, "Unable to create the engine $name", exception)
            false
        }
    }

    /**
     * 把已创建引擎的视图挂载好并返回；引擎不存在时返回 `null`，不会创建引擎。
     *
     * 悬浮窗使用 TextureView：SurfaceView 在 WindowManager 悬浮窗里是独立图层，部分设备/系统上
     * 会显示为空或与关闭按钮的层级冲突。
     *
     * Attaches a FlutterView to an existing engine and returns it; never creates the engine.
     */
    fun attachEngineFlutterView(context: Context, name: String): FlutterView? {
        flutterView?.let { if (attachedEngineName == name) return it }
        detachView()
        val engine = FlMultiEngine.engine(name) ?: return null
        return try {
            val view = FlutterView(context, FlutterTextureView(context))
            view.attachToFlutterEngine(engine)
            // 独立引擎不依附任何 Activity，需要手动挂载平台视图控制器与生命周期通道。
            // 控制器只能附着一次，重复展示同一引擎时复用已有附着。
            // The dedicated engine is not attached to an Activity, so the platform views controller
            // and the lifecycle channel have to be attached manually. The controller can only be
            // attached once, so reuse the existing attachment when the engine is presented again.
            if (platformViewsEngineName != name) {
                engine.platformViewsControllerDelegator.attach(
                    context,
                    engine.renderer,
                    engine.dartExecutor,
                )
                platformViewsEngineName = name
            }
            engine.lifecycleChannel.appIsResumed()
            flutterView = view
            attachedEngineName = name
            view
        } catch (throwable: Throwable) {
            Log.e(TAG, "Unable to attach the view of the engine $name", throwable)
            null
        }
    }

    /** 解绑当前视图但不销毁引擎。 / Detaches the current view without destroying the engine. */
    fun releaseView() {
        detachView()
    }

    /** 销毁指定引擎并解绑视图。 / Destroys the engine called [name] and detaches the view. */
    fun destroy(name: String) {
        detachView()
        if (platformViewsEngineName == name) platformViewsEngineName = null
        FlMultiEngine.destroy(name)
    }

    private fun handleExternalDestroy() {
        detachView()
        platformViewsEngineName = null
        FlPiPWindowManager.getInstance().onEngineDestroyed()
    }

    private fun detachView() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        attachedEngineName = null
    }
}
