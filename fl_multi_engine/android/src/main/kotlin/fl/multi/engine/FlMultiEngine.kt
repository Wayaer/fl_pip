package fl.multi.engine

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup

/**
 * 命名引擎被销毁时的回调，回调在主线程执行。
 *
 * Called on the main thread when a named engine is destroyed.
 */
fun interface FlMultiEngineDestroyListener {
    fun onEngineDestroyed(name: String)
}

/**
 * 命名引擎管理器的原生入口，宿主 App 可以不经过 Flutter 直接创建、销毁和查询引擎。
 * 插件与 Flutter 侧共用同一份注册表。
 *
 * Native entry point of the engine manager.
 *
 * Host apps can create, destroy and inspect engines without going through Flutter.
 * The Flutter plugin uses the same registry.
 */
object FlMultiEngine {
    /** 注册引擎销毁监听，供其他插件在引擎消失时释放对应的原生视图。 / Adds a destroy listener. */
    @JvmStatic
    fun addEngineDestroyListener(listener: FlMultiEngineDestroyListener) {
        FlMultiEngineRegistry.addDestroyListener(listener)
    }

    /** 移除引擎销毁监听。 / Removes a destroy listener. */
    @JvmStatic
    fun removeEngineDestroyListener(listener: FlMultiEngineDestroyListener) {
        FlMultiEngineRegistry.removeDestroyListener(listener)
    }

    /** 创建并启动一个运行 [entrypoint] 的命名引擎。 / Creates an engine. */
    @JvmStatic
    fun create(
        name: String,
        entrypoint: String,
        arguments: List<String> = emptyList(),
    ): FlMultiEngineInfo = FlMultiEngineRegistry.create(name, entrypoint, arguments)

    /** 销毁指定引擎，主引擎不允许销毁。 / Destroys the engine; the main engine is protected. */
    @JvmStatic
    fun destroy(name: String): Boolean = FlMultiEngineRegistry.destroy(name)

    /** 返回所有已注册引擎（包含主引擎）。 / Returns every registered engine. */
    @JvmStatic
    fun engines(): List<FlMultiEngineInfo> = FlMultiEngineRegistry.list()

    /** 返回指定引擎的信息，不存在时返回 null。 / Returns the info of an engine or null. */
    @JvmStatic
    fun status(name: String): FlMultiEngineInfo? = FlMultiEngineRegistry.status(name)

    /** 返回指定引擎的 FlutterEngine 实例，不存在时返回 null。 / Returns the running engine or null. */
    @JvmStatic
    fun engine(name: String): FlutterEngine? = FlMultiEngineRegistry.engine(name)

    /** 返回创建新引擎时复用的共享引擎组。 / Returns the shared engine group used for new engines. */
    @JvmStatic
    fun engineGroup(context: Context): FlutterEngineGroup =
        FlMultiEngineRegistry.sharedGroup(context.applicationContext)
}

/** 描述一个由 fl_multi_engine 管理的引擎。 / Describes an engine managed by fl_multi_engine. */
data class FlMultiEngineInfo(
    val name: String,
    val entrypoint: String,
    val state: String,
    val createdAt: Long,
    val isMain: Boolean,
) {
    /** 转换成平台通道使用的 Map。 / Converts the info into the platform channel map. */
    fun toMap(): Map<String, Any> = mapOf(
        "name" to name,
        "entrypoint" to entrypoint,
        "state" to state,
        "createdAt" to createdAt,
        "isMain" to isMain,
    )
}

/** 引擎管理器抛出的错误，[code] 与 Dart 侧的错误码一一对应。 / Error reported by the engine manager. */
class FlMultiEngineException(val code: String, message: String) : Exception(message)

/**
 * 与 Dart 侧 `FlMultiEngineErrorCode` 一一对应的稳定错误码。
 *
 * Stable error codes shared with the Dart implementation.
 */
object FlMultiEngineErrorCode {
    const val NOT_SUPPORTED = "not_supported"
    const val INVALID_NAME = "invalid_name"
    const val ENGINE_EXISTS = "engine_exists"
    const val CREATE_FAILED = "create_failed"
    const val MAIN_ENGINE_NOT_DESTROYABLE = "main_engine_not_destroyable"
    const val NOT_INITIALIZED = "not_initialized"
    const val UNKNOWN = "unknown"
}

/**
 * 原生侧消息桥：以某个引擎身份向其他命名引擎发送消息，并监听投递到该引擎的消息。
 *
 * Sends messages from a native engine to a named engine and listens to messages delivered to that
 * engine.
 */
class FlMultiEngineBridge(private val engineName: String) {
    private val listeners = mutableListOf<FlMultiEngineRegistry.NativeListener>()

    /** 向 [target] 发送消息，目标存在返回 1，否则返回 0。 / Sends [value] to [target]. */
    fun send(target: String, method: String = "message", value: Map<String, Any?> = emptyMap()): Int =
        FlMultiEngineRegistry.send(engineName, target, method, value)

    /** 监听投递到 [engineName] 的所有消息。 / Listens to every message delivered to [engineName]. */
    fun listen(callback: (sender: String, method: String, value: Map<String, Any?>) -> Unit) {
        listeners.add(FlMultiEngineRegistry.addListener(engineName, null, callback))
    }

    /** Listens to the messages with [method] delivered to [engineName]. */
    fun listen(method: String, callback: (value: Map<String, Any?>) -> Unit) {
        listeners.add(
            FlMultiEngineRegistry.addListener(engineName, method) { _, _, value -> callback(value) },
        )
    }

    /** Stops listening to all messages. */
    fun dispose() {
        listeners.forEach(FlMultiEngineRegistry::removeListener)
        listeners.clear()
    }
}
