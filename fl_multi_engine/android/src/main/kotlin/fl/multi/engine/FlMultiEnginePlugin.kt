package fl.multi.engine

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 在每个 Flutter 引擎上注册 fl_multi_engine 通道。
 *
 * 主引擎由 Flutter 工具自动附加；其余引擎由 [FlMultiEngineRegistry] 创建后手动注册。
 * 插件实例会记录自己所属的引擎名，用于消息收发时的 sender 标识。
 *
 * Registers the fl_multi_engine channel on every Flutter engine.
 *
 * The plugin is attached to the main engine by the Flutter tool and to every engine created by
 * [FlMultiEngineRegistry]. The channel identity is used as the sender of messages.
 */
class FlMultiEnginePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null

    /** 引擎名称；不是由 fl_multi_engine 创建的外部引擎为 null。 / Null for external engines. */
    private var engineName: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val name = FlMultiEngineRegistry.nameFor(binding.flutterEngine)
        engineName = name
        if (name == FlMultiEngineRegistry.MAIN_NAME) {
            FlMultiEngineRegistry.attachMain(binding.flutterEngine, binding.applicationContext)
        }

        val methodChannel = MethodChannel(binding.binaryMessenger, "fl_multi_engine")
        methodChannel.setMethodCallHandler(this)
        channel = methodChannel
        // 外部引擎同样可以收发消息，但不能登记成任何命名引擎，否则会覆盖 main 的通道。
        // External engines can still send messages but must never register a named channel.
        if (name != null) {
            FlMultiEngineRegistry.registerChannel(name, methodChannel)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // 通道随引擎一起失效，同步清理注册表，避免后续消息投递到已销毁的引擎。
        // The channel dies with the engine, so clear the registry entry as well.
        val name = engineName
        if (name != null) {
            channel?.let { FlMultiEngineRegistry.unregisterChannel(name, it) }
        }
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "currentEngineName" -> result.success(engineName)

                "create" -> {
                    val name = call.argument<String>("name") ?: ""
                    val entrypoint = call.argument<String>("entrypoint") ?: ""
                    val arguments = call.argument<List<Any?>>("arguments")
                        ?.mapNotNull { it as? String }
                        ?: emptyList()
                    // 只返回创建成功的唯一 ID，Dart 侧会重新拉取引擎列表并筛选。
                    // Only return the unique ID; Dart re-fetches the engine list afterwards.
                    val info = FlMultiEngineRegistry.create(name, entrypoint, arguments)
                    result.success(info.name)
                }

                "destroy" -> {
                    val name = call.argument<String>("name") ?: ""
                    result.success(FlMultiEngineRegistry.destroy(name))
                }

                "list" -> result.success(FlMultiEngineRegistry.list().map(FlMultiEngineInfo::toMap))

                "status" -> {
                    val name = call.argument<String>("name") ?: ""
                    result.success(FlMultiEngineRegistry.status(name)?.toMap())
                }

                "send" -> {
                    val target = call.argument<String>("target") ?: ""
                    val method = call.argument<String>("method") ?: "message"
                    val value = call.argument<Map<Any?, Any?>>("value")
                        ?.mapNotNull { entry -> (entry.key as? String)?.let { it to entry.value } }
                        ?.toMap()
                        ?: emptyMap()
                    result.success(FlMultiEngineRegistry.send(engineName ?: "", target, method, value))
                }

                else -> result.notImplemented()
            }
        } catch (exception: FlMultiEngineException) {
            result.error(exception.code, exception.message, null)
        } catch (exception: Exception) {
            result.error(
                FlMultiEngineErrorCode.UNKNOWN,
                exception.message ?: "Unknown fl_multi_engine error",
                null,
            )
        }
    }
}
