package fl.pip

import fl.multi.engine.FlMultiEngine
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.IdentityHashMap

/**
 * fl_pip 的平台通道入口：只解析参数并分派给窗口层或视频层，不持有视图与播放器。
 *
 * 每个 Flutter 引擎都注册一个 `fl_pip` 通道，所有通道统一记录在伴生对象里，
 * `send` 只投递给 `present(name:)` 指定的画中画引擎，该引擎发送时回到主引擎；窗口状态与
 * 状态通知由 [FlPiPWindowManager] 统一维护。
 *
 * Platform channel entry point of fl_pip. It only parses arguments and dispatches to the window and
 * video layers; views and players are not held here. Every engine registers one `fl_pip` channel,
 * all of them are tracked so `send` reaches the picture-in-picture engine selected by
 * `present(name:)`, whose own `send` goes back to the main engine.
 */
class FlPiPPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        /** 所有引擎注册的 `fl_pip` 通道，用于状态/视频事件广播。 */
        private val channels = mutableListOf<MethodChannel>()

        /** 引擎实例与 `fl_pip` 通道的对应关系，用于定向投递消息。 */
        private val engineChannels = IdentityHashMap<FlutterEngine, MethodChannel>()

        /** 向所有引擎的 `fl_pip` 通道广播事件。 / Broadcasts an event to every registered channel. */
        internal fun broadcast(method: String, payload: Any?) {
            channels.toList().forEach { channel -> channel.invokeMethod(method, payload) }
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var pluginBinding: FlutterPlugin.FlutterPluginBinding
    private val windowManager: FlPiPWindowManager = FlPiPWindowManager.getInstance()
    private val videoManager: FlPiPVideoManager = FlPiPVideoManager.getInstance()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
        channel = MethodChannel(binding.binaryMessenger, FL_PIP_CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        channels.add(channel)
        engineChannels[binding.flutterEngine] = channel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = windowManager.hostContext
        // 媒体窗口和引擎悬浮窗只需要 Application Context，Activity 销毁后仍要能控制它们。
        // Overlays only need the application context, so they stay controllable after the Activity
        // has been destroyed; a missing context means FlPiPActivity was never initialized.
        if (context == null) {
            result.error(FlPiPErrorCode.ACTIVITY_NOT_INITIALIZED, "MainActivity must extend FlPiPActivity", null)
            return
        }

        when (call.method) {
            "present" -> windowManager.present(call.arguments as? Map<*, *>, result)
            "dismiss" -> windowManager.dismiss(result)
            "isActive" -> result.success(windowManager.currentStatusMap())
            "available" -> result.success(windowManager.isPiPAvailable(context))
            "toggle" -> windowManager.toggle(call.arguments == true, result)
            "send" -> send(call, result)
            "playVideo", "stopVideo", "isVideoActive",
            "setVideoPlaying", "seekVideo", "seekVideoBy", "stopVideoPlayback", "setVideoSpeed",
            "setVideoVolume", "setVideoLooping", "getVideoStatus" ->
                videoManager.onMethodCall(call, result, pluginBinding, context)

            else -> result.notImplemented()
        }
    }

    /**
     * 向画中画引擎投递消息：主引擎发往 `present(name:)` 指定的引擎，该引擎发往主引擎。
     *
     * 只投递一次，返回送达数量（`1` 或 `0`），其他引擎不会收到消息。
     *
     * Delivers a message to the picture-in-picture engine (or back to the main engine when the
     * picture-in-picture engine sends) and returns `1` when it was delivered, `0` otherwise.
     */
    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error(FlPiPErrorCode.INVALID_CONFIGURATION, "send arguments are missing", null)
            return
        }
        val target = resolveMessageTarget()
        if (target == null) {
            result.success(0)
            return
        }
        target.invokeMethod("onMessage", arguments)
        result.success(1)
    }

    /** 解析消息目标通道；没有画中画引擎时返回 `null`。 / Resolves the message target channel. */
    private fun resolveMessageTarget(): MethodChannel? {
        val pipName = windowManager.pipEngineNameForMessages ?: return null
        val pipChannel = FlMultiEngine.engine(pipName)?.let { engineChannels[it] } ?: return null
        if (pipChannel !== channel) return pipChannel
        // 画中画引擎向主引擎发消息。 / The picture-in-picture engine sends back to the main engine.
        val mainName = FlMultiEngine.engines().firstOrNull { it.isMain }?.name ?: return null
        val mainChannel = FlMultiEngine.engine(mainName)?.let { engineChannels[it] } ?: return null
        // 主引擎本身是画中画引擎时没有其他引擎可投递。
        return if (mainChannel === channel) null else mainChannel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        channels.remove(channel)
        engineChannels.remove(binding.flutterEngine)
    }
}
