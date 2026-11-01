package fl.multi.engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.MethodChannel

/**
 * 命名引擎的注册表：维护引擎实例、通道、生命周期状态以及原生监听器。
 *
 * 所有公开入口都在主线程调用，内部使用 `@Synchronized` 保护共享状态。
 *
 * Registry of named engines: instances, channels, lifecycle state and native listeners.
 */
internal object FlMultiEngineRegistry {
    const val MAIN_NAME = "main"

    internal class Entry(
        val name: String,
        val entrypoint: String,
        val engine: FlutterEngine,
        val isMain: Boolean,
        val createdAt: Long,
    ) {
        var channel: MethodChannel? = null
        var state: String = "running"

        fun toInfo(): FlMultiEngineInfo = FlMultiEngineInfo(name, entrypoint, state, createdAt, isMain)
    }

    internal data class NativeListener(
        val engineName: String,
        val method: String?,
        val callback: (sender: String, method: String, value: Map<String, Any?>) -> Unit,
    )

    private val entries = LinkedHashMap<String, Entry>()
    private val pendingNames = mutableMapOf<FlutterEngine, String>()
    private val listeners = mutableListOf<NativeListener>()
    private val destroyListeners = mutableListOf<FlMultiEngineDestroyListener>()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var context: Context? = null
    private var engineGroup: FlutterEngineGroup? = null
    private var mainAttached = false

    /** 返回全局共享的引擎组，保证同组引擎共享渲染等资源。 / Returns the shared engine group. */
    @Synchronized
    fun sharedGroup(currentContext: Context): FlutterEngineGroup =
        engineGroup ?: FlutterEngineGroup(currentContext).also { engineGroup = it }

    fun attachMain(engine: FlutterEngine, context: Context) {
        this.context = context.applicationContext
        // main 一旦注册过，后续再出现的「未命名引擎」都属于外部引擎（例如 fl_pip 的 pipMain），
        // 不能把它们当成 main，否则会覆盖主引擎的通道。
        // Once main is registered, later unnamed engines are external (for example the fl_pip
        // pipMain engine) and must not take over the main identity.
        mainAttached = true
        if (entries.containsKey(MAIN_NAME)) return
        entries[MAIN_NAME] = Entry(MAIN_NAME, "main", engine, true, System.currentTimeMillis())
    }

    /**
     * 返回引擎名称：由 [create] 创建的引擎返回自己的名字；外部引擎在 main 已注册后返回 `null`。
     *
     * Returns the engine name, or `null` for external engines once main is registered.
     */
    fun nameFor(engine: FlutterEngine): String? {
        pendingNames.remove(engine)?.let { return it }
        return if (mainAttached) null else MAIN_NAME
    }

    /** 记录引擎对应的 MethodChannel，供定向消息投递使用。 / Stores the channel used to deliver messages. */
    fun registerChannel(name: String, channel: MethodChannel) {
        entries[name]?.channel = channel
    }

    /** 引擎销毁时清除通道引用，避免向已失效的引擎发送消息。 / Clears the channel on detach. */
    fun unregisterChannel(name: String, channel: MethodChannel) {
        val entry = entries[name] ?: return
        if (entry.channel == channel) entry.channel = null
    }

    /**
     * 创建并启动命名引擎。
     *
     * 注意：创建时必须关闭引擎组的自动插件注册，因为插件注册依赖 pendingNames 中的引擎名称，
     * 而名称只有在引擎对象创建后才知道。
     *
     * Creates and starts a named engine. Automatic plugin registration is disabled on purpose
     * because the engine name is only known after the engine object exists.
     */
    @Synchronized
    fun create(
        name: String,
        entrypoint: String,
        arguments: List<String>,
    ): FlMultiEngineInfo {
        if (name.isEmpty() || entrypoint.isEmpty()) {
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.INVALID_NAME,
                "The engine name and entry point must not be empty",
            )
        }
        val currentContext = context
            ?: throw FlMultiEngineException(FlMultiEngineErrorCode.NOT_INITIALIZED, "fl_multi_engine is not attached to the main engine")
        if (name == MAIN_NAME || entries.containsKey(name)) {
            throw FlMultiEngineException(FlMultiEngineErrorCode.ENGINE_EXISTS, "The engine $name already exists")
        }

        val group = sharedGroup(currentContext)
        val dartEntrypoint = DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
            entrypoint,
        )

        // 关闭引擎组的自动插件注册：插件注册需要知道引擎名称，而名称只能在引擎创建之后写入
        // pendingNames。若交给构造阶段自动注册，新引擎会被误判成 main 引擎。
        // Disable automatic plugin registration: the name is only known after the engine exists.
        val options = FlutterEngineGroup.Options(currentContext)
            .setDartEntrypoint(dartEntrypoint)
            .setDartEntrypointArgs(arguments)
            .setAutomaticallyRegisterPlugins(false)

        val engine = try {
            group.createAndRunEngine(options)
        } catch (exception: Exception) {
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.CREATE_FAILED,
                exception.message ?: "Unable to create the engine $name",
            )
        }

        val entry = Entry(name, entrypoint, engine, false, System.currentTimeMillis())
        entries[name] = entry
        // 先登记名称，再注册插件，插件 onAttachedToEngine 才能拿到正确的引擎名。
        // Register the name before the plugins so onAttachedToEngine sees the right name.
        pendingNames[engine] = name

        try {
            GeneratedPluginRegister.registerGeneratedPlugins(engine)
        } catch (exception: Exception) {
            entries.remove(name)
            pendingNames.remove(engine)
            engine.destroy()
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.CREATE_FAILED,
                exception.message ?: "Unable to register plugins on $name",
            )
        }

        notifyEnginesChanged()
        return entry.toInfo()
    }

    /** 销毁指定引擎。 / Destroys the engine called [name]. */
    @Synchronized
    fun destroy(name: String): Boolean {
        val entry = entries[name] ?: return false
        if (entry.isMain) {
            throw FlMultiEngineException(FlMultiEngineErrorCode.MAIN_ENGINE_NOT_DESTROYABLE, "The main engine cannot be destroyed")
        }
        entry.channel?.setMethodCallHandler(null)
        entry.state = "disposed"
        entries.remove(name)
        pendingNames.remove(entry.engine)
        // 先通知监听器（例如 fl_pip 会在这里关闭挂载在该引擎上的悬浮窗），再销毁引擎，
        // 避免视图仍然挂在已销毁的引擎上。
        // Notify listeners first so presented views are detached before the engine is destroyed.
        notifyDestroyed(name)
        // 引擎销毁必须与监听器回调同线程执行：非主线程调用时 notifyDestroyed 会把监听器
        // post 到主线程，若这里同步 destroy 会抢在监听器（如 fl_pip 解绑悬浮窗视图）之前执行。
        // Destroy on the same thread as the listeners; off the main thread the listeners are posted,
        // so destroying inline here would race ahead of them.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            entry.engine.destroy()
        } else {
            mainHandler.post { entry.engine.destroy() }
        }
        notifyEnginesChanged()
        return true
    }

    /**
     * 通知 Flutter 侧引擎列表发生变化；只发通知，不携带引擎数据。
     *
     * Notifies Flutter that the engine list changed. The notification carries no engine data.
     */
    private fun notifyEnginesChanged() {
        val channel = synchronized(this) { entries[MAIN_NAME]?.channel } ?: return
        // 延后到当前调用返回之后再通知，避免通知和 create/destroy 的结果竞争。
        // Post the notification so it arrives after the current create/destroy result.
        mainHandler.post { channel.invokeMethod("onEnginesChanged", null) }
    }

    /**
     * 通知原生监听器引擎即将被销毁；主线程直接执行，其他线程转移到主线程。
     *
     * Notifies destroy listeners; runs inline on the main thread and posts otherwise.
     */
    private fun notifyDestroyed(name: String) {
        val snapshot = synchronized(this) { destroyListeners.toList() }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            snapshot.forEach { listener -> listener.onEngineDestroyed(name) }
        } else {
            mainHandler.post { snapshot.forEach { listener -> listener.onEngineDestroyed(name) } }
        }
    }

    @Synchronized
    fun addDestroyListener(listener: FlMultiEngineDestroyListener) {
        destroyListeners.add(listener)
    }

    @Synchronized
    fun removeDestroyListener(listener: FlMultiEngineDestroyListener) {
        destroyListeners.remove(listener)
    }

    @Synchronized
    fun list(): List<FlMultiEngineInfo> = entries.values.map(Entry::toInfo)

    @Synchronized
    fun status(name: String): FlMultiEngineInfo? = entries[name]?.toInfo()

    @Synchronized
    fun engine(name: String): FlutterEngine? = entries[name]?.engine

    /**
     * 把消息定向投递给 [target] 引擎的 Dart 侧，同时通知该引擎上的原生监听器。
     * 返回 1 表示目标存在，0 表示目标不存在或尚未注册通道。
     *
     * Delivers a message to the Dart side of [target] and to its native listeners.
     */
    fun send(sender: String, target: String, method: String, value: Map<String, Any?>): Int {
        val exists = synchronized(this) { entries[target]?.channel != null }
        if (!exists) return 0

        val deliver = Runnable {
            val entry = synchronized(this) { entries[target] }
            if (entry?.channel == null) return@Runnable
            entry.channel?.invokeMethod(
                "onMessage",
                mapOf("sender" to sender, "method" to method, "value" to value),
            )
            val localListeners = synchronized(this) {
                listeners.filter { it.engineName == target && (it.method == null || it.method == method) }
            }
            localListeners.forEach { it.callback(sender, method, value) }
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            deliver.run()
        } else {
            mainHandler.post(deliver)
        }
        return 1
    }

    @Synchronized
    fun addListener(
        engineName: String,
        method: String?,
        callback: (sender: String, method: String, value: Map<String, Any?>) -> Unit,
    ): NativeListener {
        val listener = NativeListener(engineName, method, callback)
        listeners.add(listener)
        return listener
    }

    @Synchronized
    fun removeListener(listener: NativeListener) {
        listeners.remove(listener)
    }
}
