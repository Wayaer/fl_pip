package fl.pip

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min

/**
 * 视频播放层：负责视频播放、事件与控制面板，窗口展示统一委托给 [FlPiPWindowManager]。
 *
 * Android 视频只有悬浮窗一种承载方式；控制条与 iOS 画中画对齐：
 * 播放/暂停、进度、关闭和拖动。视频使用 MediaPlayer 输出到 TextureView。
 *
 * The video layer. It plays the video with MediaPlayer, emits events and draws the control panel,
 * while the overlay window itself is created and removed by [FlPiPWindowManager].
 */
class FlPiPVideoManager private constructor() {
    companion object {
        private const val TAG = "FlPiPMedia"

        @SuppressLint("StaticFieldLeak")
        private var instance: FlPiPVideoManager? = null

        fun getInstance(): FlPiPVideoManager = instance ?: synchronized(this) {
            instance ?: FlPiPVideoManager().also { instance = it }
        }
    }

    private class Session(
        val content: FrameLayout,
        val textureView: TextureView,
    ) {
        var player: MediaPlayer? = null
        var playing = false
        var speed = 1f
        var volume = 1f
        var loop = false

        /**
         * MediaPlayer 在 prepare 完成前调用 start/pause/seek/duration 等方法会抛
         * IllegalStateException；控制面板在 prepare 前就已经可见，必须用该标记做保护。
         *
         * MediaPlayer throws IllegalStateException before it is prepared; the control panel is
         * already visible at that point, so every player access is guarded by this flag.
         */
        var prepared = false

        /** prepare 之前的 seek 目标；prepare 完成后应用。 / Pending seek applied once prepared. */
        var pendingSeekMs: Int? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private val windowManager: FlPiPWindowManager = FlPiPWindowManager.getInstance()

    private var session: Session? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var seekBar: SeekBar? = null
    private var playButton: ImageView? = null
    private var controls: FrameLayout? = null
    private var hideControlsRunnable: Runnable? = null
    private var progressRunnable: Runnable? = null
    private var controlsEnabled = true
    private var lastControlsVisible = true
    private var showPlayPause = true
    private var showProgress = true
    private var showClose = true
    private var allowDrag = true
    private var autoHide = true

    fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        pluginBinding: FlutterPlugin.FlutterPluginBinding,
        currentContext: Context,
    ) {
        binding = pluginBinding
        when (call.method) {
            "playVideo" -> playVideo(call, result, currentContext)
            "stopVideo" -> result.success(stopMedia())
            "isVideoActive" -> result.success(isActive())
            "setVideoPlaying" -> result.success(setPlaying(call.argument<Boolean>("playing") ?: false))
            "seekVideo" -> result.success(seekTo(call.argument<Int>("positionMs") ?: 0))
            "seekVideoBy" -> result.success(seekBy(call.argument<Int>("offsetMs") ?: 0))
            "stopVideoPlayback" -> result.success(stopPlayback())
            "setVideoSpeed" -> result.success(setSpeed((call.argument<Double>("speed") ?: 1.0).toFloat()))
            "setVideoVolume" -> result.success(setVolume((call.argument<Double>("volume") ?: 0.0).toFloat()))
            "setVideoLooping" -> result.success(setLooping(call.argument<Boolean>("loop") ?: false))
            "getVideoStatus" -> result.success(statusMap())
            else -> result.notImplemented()
        }
    }

    fun isActive(): Boolean = session != null

    /**
     * 按视频原始宽高比缩放 TextureView 内容并居中，四周由黑色背景填充；
     * 否则 MediaPlayer 会把画面拉伸到整个视图，竖屏视频放进横向窗口时会被明显压扁。
     *
     * Scales the TextureView content to the video aspect ratio and centers it, so a portrait video
     * inside a landscape window is letterboxed instead of stretched.
     */
    private fun applyVideoAspect(current: Session) {
        val player = current.player ?: return
        if (!current.prepared) return
        val videoWidth = player.videoWidth
        val videoHeight = player.videoHeight
        if (videoWidth <= 0 || videoHeight <= 0) return
        val viewWidth = current.textureView.width.toFloat()
        val viewHeight = current.textureView.height.toFloat()
        if (viewWidth <= 0f || viewHeight <= 0f) return
        val scale = min(viewWidth / videoWidth, viewHeight / videoHeight)
        val matrix = Matrix()
        matrix.setScale(
            videoWidth * scale / viewWidth,
            videoHeight * scale / viewHeight,
            viewWidth / 2f,
            viewHeight / 2f,
        )
        current.textureView.setTransform(matrix)
    }

    /** 视频播放前先确保拥有悬浮窗权限。 / Ensures the overlay permission before playing. */
    private fun playVideo(call: MethodCall, result: MethodChannel.Result, currentContext: Context) {
        // 同一时刻只允许一个窗口，引擎悬浮窗或系统画中画也要先排除。
        // Only one window at a time; reject when an engine window is active.
        if (session != null || windowManager.isWindowActive) {
            result.error(FlPiPErrorCode.ALREADY_ENABLED, "A window is already visible", null)
            return
        }
        if (!windowManager.hasOverlayPermission()) {
            windowManager.requestOverlayPermission(result) { startVideo(call, result, currentContext) }
            return
        }
        startVideo(call, result, currentContext)
    }

    /** 创建视频会话：MediaPlayer + TextureView，并注册各种播放回调。 */
    private fun startVideo(call: MethodCall, result: MethodChannel.Result, currentContext: Context) {
        if (session != null || windowManager.isWindowActive) {
            result.error(FlPiPErrorCode.ALREADY_ENABLED, "A window is already visible", null)
            return
        }
        val source = call.argument<String>("uri") ?: ""
        if (source.isEmpty()) {
            result.error(FlPiPErrorCode.INVALID_CONFIGURATION, "The video source must not be empty", null)
            return
        }
        // type 与 Dart 的 FlPiPVideoSourceType 保持一致：asset / file / network。
        // type matches the Dart FlPiPVideoSourceType values: asset / file / network.
        val sourceType = call.argument<String>("type") ?: "asset"
        val loop = call.argument<Boolean>("loop") ?: false
        val muted = call.argument<Boolean>("muted") ?: false
        // 资源所属的 packageName；为空时使用当前 App 的资源目录。
        // Package that owns the asset; null means the host app assets.
        val packageName = call.argument<String>("packageName")
        applyControls(call.argument<Map<*, *>>("controls"))
        // 先校验来源，源不可用时直接返回错误；窗口创建后再失败只能通过事件上报，
        // 会让 Dart 的 playVideo 返回值与真实结果不一致。
        // Validate the source first: failing after the window is shown can only be reported
        // through an event, which makes the playVideo return value lie.
        if (!isVideoSourceValid(currentContext, sourceType, source, packageName)) {
            result.error(FlPiPErrorCode.VIDEO_ASSET_NOT_FOUND, "Unable to resolve the video source", null)
            return
        }

        val current = createSession(currentContext)
        val arguments: Map<*, *> = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val cornerRadius = (arguments["cornerRadius"] as? Number)?.toDouble() ?: 12.0
        val shown = windowManager.showVideoWindow(
            content = current.content,
            args = arguments,
            cornerRadius = cornerRadius,
            allowDrag = { allowDrag },
            onTap = { toggleControls() },
        )
        if (!shown) {
            resetUi()
            result.error(FlPiPErrorCode.OVERLAY_CREATION_FAILED, "Unable to create the overlay", null)
            return
        }
        session = current
        current.playing = true
        val player = MediaPlayer()
        current.player = player
        current.loop = loop
        current.volume = if (muted) 0f else 1f
        player.isLooping = loop
        player.setVolume(current.volume, current.volume)

        player.setOnPreparedListener {
            current.prepared = true
            // 竖屏视频放进宽窗口时按比例居中显示，避免被拉伸。
            // A portrait video inside a wide window is letterboxed instead of stretched.
            applyVideoAspect(current)
            current.pendingSeekMs?.let { position ->
                player.seekTo(position.coerceIn(0, player.duration.coerceAtLeast(0)))
                current.pendingSeekMs = null
            }
            // prepare 之前用户可能已经点过暂停，这里按当前播放意图决定是否 start。
            // The user may have paused before preparation; honour the current intent.
            if (current.playing) it.start()
            updatePlayButton(current.playing)
            updateProgress()
            notifyEvent("play", playing = current.playing, action = "play")
        }
        player.setOnCompletionListener {
            current.playing = false
            updatePlayButton(false)
            notifyEvent("ended", playing = false, action = "pause")
        }
        player.setOnErrorListener { _, what, extra ->
            Log.e(TAG, "MediaPlayer error $what/$extra")
            notifyEvent("error", playing = false)
            false
        }

        val textureView = current.textureView
        val preparePlayback = {
            try {
                val texture = textureView.surfaceTexture
                if (texture == null) {
                    notifyEvent("error", playing = false)
                } else {
                    player.setSurface(Surface(texture))
                    setVideoSource(player, currentContext, sourceType, source, packageName)
                    player.prepareAsync()
                }
            } catch (exception: Exception) {
                Log.e(TAG, "Unable to prepare the video", exception)
                notifyEvent("error", playing = false)
            }
        }
        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                preparePlayback()
            }

            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
                applyVideoAspect(current)
            }

            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                // 窗口关闭时会先释放 MediaPlayer，此处不能再调用已释放的 player。
                // The player is released before the window is removed; do not touch it afterwards.
                try {
                    player.setSurface(null)
                } catch (exception: IllegalStateException) {
                    Log.w(TAG, "Unable to detach the released player", exception)
                }
                return true
            }

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
        }
        // 监听器设置时纹理可能已经可用，此时系统不会再回调 onSurfaceTextureAvailable。
        // The texture may already be available; in that case onSurfaceTextureAvailable is not called.
        if (textureView.isAvailable) preparePlayback()
        // 视图尺寸在 prepare 之后才确定时，等布局完成再套用一次画面比例。
        // The view size may only be known after preparation; apply the aspect once layout finishes.
        textureView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyVideoAspect(current) }

        result.success(true)
    }

    private fun createSession(currentContext: Context): Session {
        val content = FrameLayout(currentContext)
        // 视频使用 TextureView 交给 MediaPlayer 渲染。
        // Videos render through a TextureView.
        val textureView = TextureView(currentContext)
        content.addView(
            textureView,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        lastControlsVisible = controlsEnabled
        val controlView = buildControls(currentContext)
        controlView.visibility = if (controlsEnabled) View.VISIBLE else View.GONE
        content.addView(
            controlView,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        // 关闭按钮固定在右上角，并且不跟随控制面板自动隐藏，与 iOS 画中画一致。
        // The close button stays in the upper right corner and never auto-hides, like iOS PiP.
        if (showClose) addCloseButton(content, currentContext)
        return Session(content, textureView)
    }

    private fun applyControls(map: Map<*, *>?) {
        controlsEnabled = map?.get("enabled") as? Boolean ?: true
        showPlayPause = map?.get("showPlayPause") as? Boolean ?: true
        showProgress = map?.get("showProgress") as? Boolean ?: true
        showClose = map?.get("showClose") as? Boolean ?: true
        allowDrag = map?.get("allowDrag") as? Boolean ?: true
        autoHide = map?.get("autoHide") as? Boolean ?: true
    }

    private fun buildControls(currentContext: Context): FrameLayout {
        val container = FrameLayout(currentContext)

        val seek = SeekBar(currentContext).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(0xCCFFFFFF.toInt())
            progressBackgroundTintList = ColorStateList.valueOf(0x33FFFFFF)
            thumbTintList = ColorStateList.valueOf(Color.WHITE)
            splitTrack = false
            setOnSeekBarChangeListener(
                object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                        if (!fromUser) return
                        val current = session
                        if (current == null || !current.prepared) return
                        current.player?.let { player ->
                            if (player.duration > 0) player.seekTo(progress)
                        }
                    }

                    override fun onStartTrackingTouch(seekBar: SeekBar?) {}

                    override fun onStopTrackingTouch(seekBar: SeekBar?) {}
                },
            )
        }
        seekBar = seek

        val bar = LinearLayout(currentContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val play = iconButton(currentContext, R.drawable.fl_pip_ic_pause) { togglePlay() }
        playButton = play
        if (showPlayPause) bar.addView(play)

        // 进度条与控制按钮自下而上紧挨排列，避免用固定 margin 叠加出过大间距。
        // The progress bar and the controls stack tightly from the bottom without extra margins.
        val bottom = LinearLayout(currentContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(currentContext, 12), 0, dp(currentContext, 12), 0)
        }
        if (showProgress) {
            bottom.addView(
                seek,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(currentContext, 24)),
            )
        }
        if (bar.childCount > 0) {
            bottom.addView(
                bar,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(currentContext, 32)),
            )
        }
        container.addView(
            bottom,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ).apply { bottomMargin = dp(currentContext, 8) },
        )

        controls = container
        if (controlsEnabled) scheduleHideControls()
        return container
    }

    private fun addCloseButton(root: FrameLayout, currentContext: Context) {
        val close = ImageView(currentContext).apply {
            setImageResource(R.drawable.fl_pip_ic_close)
            scaleType = ImageView.ScaleType.CENTER
            setPadding(dp(currentContext, 5), dp(currentContext, 5), dp(currentContext, 5), dp(currentContext, 5))
            setOnClickListener { stopMedia() }
        }
        val params = FrameLayout.LayoutParams(dp(currentContext, 24), dp(currentContext, 24)).apply {
            gravity = Gravity.END or Gravity.TOP
            setMargins(0, dp(currentContext, 8), dp(currentContext, 8), 0)
        }
        root.addView(close, params)
    }

    private fun iconButton(currentContext: Context, iconRes: Int, onClick: () -> Unit): ImageView =
        ImageView(currentContext).apply {
            setImageResource(iconRes)
            scaleType = ImageView.ScaleType.CENTER
            setPadding(dp(currentContext, 4), dp(currentContext, 4), dp(currentContext, 4), dp(currentContext, 4))
            layoutParams = LinearLayout.LayoutParams(dp(currentContext, 32), dp(currentContext, 32))
            setOnClickListener {
                onClick()
                scheduleHideControls()
            }
        }

    private fun updatePlayButton(playing: Boolean) {
        playButton?.setImageResource(
            if (playing) R.drawable.fl_pip_ic_pause else R.drawable.fl_pip_ic_play,
        )
    }

    private fun setPlaying(playing: Boolean): Boolean {
        val current = session ?: return false
        current.playing = playing
        current.player?.let { player ->
            if (!current.prepared) return@let
            if (playing) {
                player.start()
                // 恢复播放时套用上次设置的倍速，避免暂停前设置的倍速丢失。
                // Re-apply the stored speed because some players reset it on pause/resume.
                if (current.speed != 1f) applySpeed(player, current.speed)
            } else {
                player.pause()
            }
        }
        updatePlayButton(playing)
        notifyEvent("playPause", playing = playing, action = if (playing) "play" else "pause")
        return true
    }

    private fun seekTo(positionMs: Int): Boolean {
        val current = session ?: return false
        val player = current.player ?: return false
        val duration = if (current.prepared) player.duration.coerceAtLeast(0) else 0
        val target = if (duration > 0) {
            positionMs.coerceIn(0, duration)
        } else {
            positionMs.coerceAtLeast(0)
        }
        if (!current.prepared) {
            // prepare 之前只记录目标位置，onPrepared 再应用。
            // Record the target before `prepared` and apply it in onPrepared.
            current.pendingSeekMs = target
        } else {
            player.seekTo(target)
        }
        notifyEvent(
            "position",
            playing = current.playing,
            positionMs = target,
            durationMs = duration,
            action = "seek",
        )
        return true
    }

    private fun seekBy(offsetMs: Int): Boolean {
        val current = session ?: return false
        val player = current.player ?: return false
        if (!current.prepared) {
            // prepare 之前以已记录的 seek 目标（默认 0）为基准。
            // Use the pending seek target (0 by default) before `prepared`.
            return seekTo((current.pendingSeekMs ?: 0) + offsetMs)
        }
        return seekTo(player.currentPosition + offsetMs)
    }

    private fun stopPlayback(): Boolean {
        val current = session ?: return false
        current.playing = false
        if (current.prepared) {
            current.player?.let { player ->
                player.pause()
                player.seekTo(0)
            }
        } else {
            // prepare 之前先记录目标位置，onPrepared 再回到开头。
            // Record the restart target before `prepared` and apply it in onPrepared.
            current.pendingSeekMs = 0
        }
        updatePlayButton(false)
        notifyEvent("stop", playing = false, positionMs = 0, action = "pause")
        return true
    }

    private fun setSpeed(speed: Float): Boolean {
        val current = session ?: return false
        val player = current.player ?: return false
        if (speed <= 0f) return false
        current.speed = speed
        return try {
            // 只在准备完成后且播放中应用：暂停状态下设置 playbackParams 会意外恢复播放。
            // Apply only while prepared and playing; setting playback params on a paused player
            // may resume it.
            if (current.prepared && current.playing) applySpeed(player, speed)
            notifyEvent("speed", playing = current.playing)
            true
        } catch (exception: Exception) {
            Log.w(TAG, "Unable to set the playback speed", exception)
            false
        }
    }

    private fun applySpeed(player: MediaPlayer, speed: Float) {
        val params = player.playbackParams
        params.speed = speed
        player.playbackParams = params
    }

    private fun setVolume(volume: Float): Boolean {
        val current = session ?: return false
        val player = current.player ?: return false
        val clamped = volume.coerceIn(0f, 1f)
        player.setVolume(clamped, clamped)
        current.volume = clamped
        notifyEvent("volume", playing = current.playing)
        return true
    }

    private fun setLooping(loop: Boolean): Boolean {
        val current = session ?: return false
        val player = current.player ?: return false
        current.loop = loop
        player.isLooping = loop
        return true
    }

    private fun statusMap(): Map<String, Any>? {
        val current = session ?: return null
        val player = current.player
        var position = 0
        var duration = 0
        if (player != null && current.prepared) {
            position = player.currentPosition
            duration = player.duration.coerceAtLeast(0)
        }
        return mapOf(
            "playing" to current.playing,
            "positionMs" to position,
            "durationMs" to duration,
            "speed" to current.speed,
            "volume" to current.volume,
        )
    }

    private fun togglePlay() {
        val current = session ?: return
        setPlaying(!current.playing)
    }

    private fun updateProgress() {
        progressRunnable?.let(handler::removeCallbacks)
        progressRunnable = object : Runnable {
            override fun run() {
                val current = session ?: return
                current.player?.let { player ->
                    val duration = player.duration.coerceAtLeast(0)
                    val position = player.currentPosition
                    if (duration > 0) {
                        seekBar?.max = duration
                        seekBar?.progress = position
                    }
                    notifyEvent(
                        "position",
                        playing = current.playing,
                        positionMs = position,
                        durationMs = duration,
                        action = "progress",
                    )
                }
                handler.postDelayed(this, 500L)
            }
        }
        handler.post(progressRunnable!!)
    }

    private fun scheduleHideControls() {
        if (!controlsEnabled) {
            setControlsVisible(false)
            return
        }
        setControlsVisible(true)
        if (!autoHide) return
        hideControlsRunnable?.let(handler::removeCallbacks)
        hideControlsRunnable = Runnable { setControlsVisible(false) }
        handler.postDelayed(hideControlsRunnable!!, 3000L)
    }

    private fun setControlsVisible(visible: Boolean) {
        val target = visible && controlsEnabled
        controls?.visibility = if (target) View.VISIBLE else View.GONE
        if (target != lastControlsVisible) {
            lastControlsVisible = target
            notifyEvent("controls", action = if (target) "show" else "hide")
        }
    }

    /** 点击窗口空白处切换控制面板；关闭按钮不随面板隐藏。 / Taps toggle the control panel. */
    private fun toggleControls() {
        if (!controlsEnabled) return
        if (controls?.visibility == View.VISIBLE) {
            setControlsVisible(false)
        } else {
            scheduleHideControls()
        }
    }

    /**
     * 校验视频源是否能在播放前解析；asset 与 file 做存在性检查，network 只校验非空。
     * Checks that the source can be resolved before showing the window.
     */
    private fun isVideoSourceValid(
        currentContext: Context,
        sourceType: String,
        source: String,
        packageName: String?,
    ): Boolean = when (sourceType) {
        "network" -> source.isNotBlank()
        "file" -> if (source.startsWith("file://")) {
            Uri.parse(source).path?.let { java.io.File(it).exists() } == true
        } else {
            java.io.File(source).exists()
        }

        else -> {
            val assets = binding?.flutterAssets
            val assetPath = if (packageName == null) {
                assets?.getAssetFilePathByName(source)
            } else {
                assets?.getAssetFilePathByName(source, packageName)
            }
            if (assetPath == null) {
                false
            } else {
                runCatching { currentContext.assets.open(assetPath).use { true } }.getOrDefault(false)
            }
        }
    }

    /** 根据来源类型（network / file / Flutter asset）设置 MediaPlayer 数据源。 */
    private fun setVideoSource(
        player: MediaPlayer,
        currentContext: Context,
        sourceType: String,
        source: String,
        packageName: String?,
    ) {
        when (sourceType) {
            "network" -> player.setDataSource(source)
            "file" -> {
                if (source.startsWith("file://")) {
                    player.setDataSource(currentContext, Uri.parse(source))
                } else {
                    player.setDataSource(source)
                }
            }

            else -> {
                val assets = binding?.flutterAssets
                val assetPath = if (packageName == null) {
                    assets?.getAssetFilePathByName(source)
                } else {
                    assets?.getAssetFilePathByName(source, packageName)
                }
                if (assetPath == null) throw IllegalArgumentException("Unable to resolve the asset $source")
                try {
                    currentContext.assets.openFd(assetPath).use { descriptor ->
                        player.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                    }
                } catch (exception: Exception) {
                    val file = java.io.File(currentContext.cacheDir, "fl_pip_media_${source.hashCode()}")
                    currentContext.assets.open(assetPath).use { input ->
                        file.outputStream().use { output -> input.copyTo(output) }
                    }
                    player.setDataSource(file.absolutePath)
                }
            }
        }
    }

    fun stopMedia(): Boolean {
        val current = session ?: return false
        session = null
        progressRunnable?.let(handler::removeCallbacks)
        progressRunnable = null
        hideControlsRunnable?.let(handler::removeCallbacks)
        hideControlsRunnable = null
        current.player?.let { player ->
            try {
                player.stop()
            } catch (exception: IllegalStateException) {
                Log.w(TAG, "Unable to stop the player", exception)
            }
            player.release()
        }
        current.player = null
        windowManager.closeVideoWindow()
        notifyEvent("close", action = "close")
        resetUi()
        return true
    }

    private fun resetUi() {
        controls = null
        seekBar = null
        playButton = null
    }

    private fun notifyEvent(
        event: String,
        playing: Boolean? = null,
        positionMs: Int? = null,
        durationMs: Int? = null,
        action: String? = null,
    ) {
        val payload = mutableMapOf<String, Any>("event" to event)
        playing?.let { payload["playing"] = it }
        positionMs?.let { payload["positionMs"] = it }
        durationMs?.let { payload["durationMs"] = it }
        action?.let { payload["action"] = it }
        FlPiPPlugin.broadcast("onVideoEvent", payload)
    }

    private fun dp(currentContext: Context, value: Int): Int {
        val scale = currentContext.resources.displayMetrics.density
        return (value * scale + 0.5f).toInt()
    }
}
