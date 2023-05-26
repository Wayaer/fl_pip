package com.fl.pip

import android.app.PictureInPictureUiState
import android.content.res.Configuration
import com.fl.pip.FlPipPlugin.Companion.channel
import io.flutter.embedding.android.FlutterActivity

class FlPipActivity : FlutterActivity() {

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            channel.invokeMethod("start", null)
        } else {
            channel.invokeMethod("stop", null)
        }

    }

    override fun onPictureInPictureUiStateChanged(pipState: PictureInPictureUiState) {
        super.onPictureInPictureUiStateChanged(pipState)

    }
}