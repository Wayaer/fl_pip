package com.fl.pip

import android.content.res.Configuration
import com.fl.pip.FlPiPPlugin.Companion.channel
import io.flutter.embedding.android.FlutterActivity

open class FlPiPActivity : FlutterActivity() {

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel.invokeMethod("onPiPStatus", if (isInPictureInPictureMode) 0 else 1)
    }

}