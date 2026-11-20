package com.debug.yuyin.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// 音频试听原生状态机：显式 prepared 态、音频焦点与错误即释放。
///
/// 调用方只通过 MethodChannel 收发，方法名与参数保持与旧实现一致。
class AudioPreviewPlayer(
    context: Context,
    private val channel: MethodChannel
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private var player: MediaPlayer? = null
    private var prepared = false
    private var currentUrl: String? = null
    private var currentHeaders: Map<String, String>? = null
    private var focusRequest: AudioFocusRequest? = null
    private var resumeOnFocusGain = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> play(call, result)
            "pause" -> pause(result)
            "stop" -> stop(result)
            "seek" -> seek(call, result)
            "getPosition" -> position(result)
            else -> result.notImplemented()
        }
    }

    private fun play(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("INVALID_URL", "Audio URL is empty", null)
            return
        }
        val headers = call.argument<Map<String, String>>("headers")

        val existing = player
        if (existing != null && currentUrl == url) {
            if (headers != null) currentHeaders = headers
            if (!prepared) {
                // 仍在 Preparing：prepared 回调会负责 start，避免触发 IllegalStateException
                result.success(true)
                return
            }
            try {
                if (!existing.isPlaying) {
                    if (!requestFocus()) {
                        result.error("AUDIO_FOCUS", "无法获取音频焦点", null)
                        return
                    }
                    existing.start()
                    notifyState("playing", existing.duration)
                }
                result.success(true)
            } catch (e: Exception) {
                notifyState("error", null, e.message)
                releaseInternal(notifyIdle = false)
                result.error("PLAY_ERROR", e.message, null)
            }
            return
        }

        releaseInternal(notifyIdle = false)
        currentUrl = url
        currentHeaders = headers
        notifyState("buffering")

        if (!requestFocus()) {
            notifyState("error", null, "无法获取音频焦点")
            result.error("AUDIO_FOCUS", "无法获取音频焦点", null)
            return
        }

        val mp = MediaPlayer()
        player = mp
        prepared = false
        try {
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build()
            )
            val merged = HashMap<String, String>()
            merged["User-Agent"] = DEFAULT_USER_AGENT
            currentHeaders?.let { merged.putAll(it) }
            mp.setDataSource(appContext, Uri.parse(url), merged)
            mp.setOnPreparedListener { preparedPlayer ->
                if (preparedPlayer !== player) return@setOnPreparedListener
                prepared = true
                try {
                    preparedPlayer.start()
                    notifyState("playing", preparedPlayer.duration)
                } catch (e: Exception) {
                    notifyState("error", null, e.message)
                    releaseInternal(notifyIdle = false)
                }
            }
            mp.setOnCompletionListener { completedPlayer ->
                if (completedPlayer === player) {
                    notifyState("completed", completedPlayer.duration)
                }
            }
            mp.setOnErrorListener { errorPlayer, what, extra ->
                if (errorPlayer === player) {
                    notifyState("error", null, "what=$what, extra=$extra")
                    // 错误后立即释放：旧实例不可复用，重播时重建，避免永久死锁
                    releaseInternal(notifyIdle = false)
                }
                true
            }
            mp.prepareAsync()
            result.success(true)
        } catch (e: Exception) {
            notifyState("error", null, e.message)
            releaseInternal(notifyIdle = false)
            result.error("PLAY_ERROR", e.message, null)
        }
    }

    private fun pause(result: MethodChannel.Result) {
        val mp = player
        if (mp == null || !prepared) {
            result.success(true)
            return
        }
        try {
            if (mp.isPlaying) {
                mp.pause()
                notifyState("paused")
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PAUSE_ERROR", e.message, null)
        }
    }

    private fun stop(result: MethodChannel.Result) {
        releaseInternal(notifyIdle = true)
        result.success(true)
    }

    private fun seek(call: MethodCall, result: MethodChannel.Result) {
        val mp = player
        if (mp == null || !prepared) {
            result.success(false)
            return
        }
        val positionMs = call.argument<Int>("position") ?: 0
        try {
            mp.seekTo(positionMs)
            result.success(true)
        } catch (e: Exception) {
            result.error("SEEK_ERROR", e.message, null)
        }
    }

    private fun position(result: MethodChannel.Result) {
        val mp = player
        if (mp == null || !prepared) {
            result.success(mapOf("position" to 0, "duration" to 0))
            return
        }
        try {
            result.success(
                mapOf("position" to mp.currentPosition, "duration" to mp.duration)
            )
        } catch (_: Exception) {
            result.success(mapOf("position" to 0, "duration" to 0))
        }
    }

    /// 应用退到后台或失去音频焦点时暂停，不改变当前曲目
    fun pauseForBackground() {
        val mp = player ?: return
        if (!prepared) return
        try {
            if (mp.isPlaying) {
                mp.pause()
                notifyState("paused")
            }
        } catch (_: Exception) {
        }
    }

    /// 释放播放器与音频焦点（Activity 销毁时调用）
    fun release() {
        releaseInternal(notifyIdle = false)
        channel.setMethodCallHandler(null)
    }

    private fun releaseInternal(notifyIdle: Boolean) {
        val mp = player
        player = null
        prepared = false
        if (mp != null) {
            try {
                mp.setOnPreparedListener(null)
                mp.setOnCompletionListener(null)
                mp.setOnErrorListener(null)
            } catch (_: Exception) {
            }
            try {
                if (mp.isPlaying) mp.stop()
            } catch (_: Exception) {
            }
            try {
                mp.reset()
            } catch (_: Exception) {
            }
            try {
                mp.release()
            } catch (_: Exception) {
            }
        }
        if (notifyIdle) {
            currentUrl = null
            notifyState("idle")
        }
        abandonFocus()
    }

    private fun notifyState(state: String, durationMs: Int? = null, message: String? = null) {
        val payload = HashMap<String, Any>()
        payload["state"] = state
        if (durationMs != null && durationMs > 0) payload["duration"] = durationMs
        if (message != null) payload["message"] = message
        runOnMain { channel.invokeMethod("onPlayerStateChanged", payload) }
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeOnFocusGain = false
                pauseForBackground()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeOnFocusGain = player?.isPlaying == true
                pauseForBackground()
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (!resumeOnFocusGain) return@OnAudioFocusChangeListener
                resumeOnFocusGain = false
                val mp = player
                if (mp != null && prepared) {
                    try {
                        mp.start()
                        notifyState("playing", mp.duration)
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun requestFocus(): Boolean {
        val manager = audioManager ?: return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
                .also { focusRequest = it }
            manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonFocus() {
        val manager = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { manager.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                manager.abandonAudioFocus(focusListener)
            }
        } catch (_: Exception) {
        }
    }

    private companion object {
        const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    }
}
