package whaley.nativeapp

import java.io.File
import scala.scalanative.unsafe.*
import whaley.core.{AudioPlayer, MenuMusic, SoundCue}

@extern
private object AudioBridge {
  def whaley_audio_open(effectCount: CInt): Ptr[Byte] = extern
  def whaley_audio_close(audio: Ptr[Byte]): Unit = extern
  def whaley_audio_error(): CString = extern
  def whaley_audio_load_effect(audio: Ptr[Byte], cue: CInt, path: CString, volume: CInt): CInt = extern
  def whaley_audio_play(audio: Ptr[Byte], cue: CInt, onlyWhenIdle: CInt): CInt = extern
  def whaley_audio_music(audio: Ptr[Byte], path: CString): CInt = extern
  def whaley_audio_pause_music(audio: Ptr[Byte]): Unit = extern
  def whaley_audio_stop_effects(audio: Ptr[Byte]): Unit = extern
}

private object Audio {
  def open(directory: File): AudioPlayer = {
    val handle = AudioBridge.whaley_audio_open(SoundCue.values.length)
    if (handle == null) {
      System.err.println(s"Whaley audio unavailable: ${lastError}")
      AudioPlayer.unavailable
    } else {
      try {
        SoundCue.values.foreach { cue =>
          val path = new File(directory, cue.file)
          require(path.isFile, s"Missing original sound ${path.getAbsolutePath}")
          Zone.acquire { implicit zone =>
            val result = AudioBridge.whaley_audio_load_effect(handle, cue.ordinal,
              toCString(path.getAbsolutePath), math.round(cue.gain * 128).toInt)
            if (result != 0) throw new IllegalStateException(lastError)
          }
        }
        new NativeAudio(directory, handle)
      } catch {
        case error: Throwable =>
          AudioBridge.whaley_audio_close(handle)
          System.err.println(s"Whaley audio unavailable: ${error.getMessage}")
          AudioPlayer.unavailable
      }
    }
  }

  private[nativeapp] def lastError: String = {
    val error = AudioBridge.whaley_audio_error()
    if (error == null) "unknown SDL_mixer error" else fromCString(error)
  }
}

/** Main-thread owner of the C audio lifetime. No managed callback is invoked by
  * SDL's mixing thread, and no miniaudio structure layout is assumed.
  */
private final class NativeAudio(directory: File, initial: Ptr[Byte]) extends AudioPlayer {
  private var handle = initial
  private var suspended = false
  private var desiredMusic: Option[MenuMusic] = None
  private var reported = Set.empty[String]

  def play(cue: SoundCue): Unit = if (handle != null && !suspended) {
    check(AudioBridge.whaley_audio_play(handle, cue.ordinal, if (cue.onlyWhenIdle) 1 else 0))
  }

  def setMusic(track: Option[MenuMusic]): Unit = {
    desiredMusic = track
    syncMusic()
  }

  def setSuspended(value: Boolean): Unit = if (suspended != value) {
    suspended = value
    if (value) stopEffects()
    syncMusic()
  }

  def stopEffects(): Unit = if (handle != null) AudioBridge.whaley_audio_stop_effects(handle)
  def unlock(): Unit = ()

  def close(): Unit = if (handle != null) {
    AudioBridge.whaley_audio_close(handle)
    handle = null
    desiredMusic = None
  }

  private def syncMusic(): Unit = if (handle != null) {
    if (suspended || desiredMusic.isEmpty) AudioBridge.whaley_audio_pause_music(handle)
    else Zone.acquire { implicit zone =>
      val path = new File(directory, desiredMusic.get.file)
      if (!path.isFile) report(s"Missing original menu music ${path.getAbsolutePath}")
      else check(AudioBridge.whaley_audio_music(handle, toCString(path.getAbsolutePath)))
    }
  }

  private def check(result: Int): Unit = if (result != 0) report(Audio.lastError)
  private def report(message: String): Unit = if (!reported(message)) {
    reported += message
    System.err.println(s"Whaley audio: $message")
  }
}
