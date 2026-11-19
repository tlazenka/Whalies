package whaley.core

/** Original Whaley sound sources. The simulation emits outcomes; a platform
  * transport owns decoding, overlap, device lifetime and autoplay activation.
  * Jump is an upward bubble bounce, not the act of shooting a bubble.
  */
enum SoundCue(val file: String, val gain: Double, val onlyWhenIdle: Boolean) {
  case Knock extends SoundCue("knock.mp3", 0.5, false)
  case Pause extends SoundCue("pause01.wav", 1.0, false)
  case Jump extends SoundCue("jump01.wav", 1.0, true)
  case Bounce extends SoundCue("bounce01.wav", 1.0, true)
  case Coin extends SoundCue("coin01.wav", 1.0, false)
  case Death extends SoundCue("flame01.wav", 1.0, true)
  case Goal extends SoundCue("goal01.wav", 1.0, true)
  case Anvil extends SoundCue("bg01.mp3", 1.0, true)
}

/** The original menu tracks play once and retain their position while gameplay
  * pauses them. Completing all six levels selects the Glad soundtrack.
  */
enum MenuMusic(val file: String) {
  case Gray extends MenuMusic("A.mp3")
  case Glad extends MenuMusic("B.mp3")
}

trait AudioPlayer {
  def play(cue: SoundCue): Unit
  def setMusic(track: Option[MenuMusic]): Unit
  def setSuspended(value: Boolean): Unit
  def stopEffects(): Unit
  /** Call synchronously from a real user gesture. Native playback needs no unlock. */
  def unlock(): Unit
  def close(): Unit
}

object AudioPlayer {
  /** Used only after the platform reports why a device could not be opened. */
  val unavailable: AudioPlayer = new AudioPlayer {
    def play(cue: SoundCue): Unit = ()
    def setMusic(track: Option[MenuMusic]): Unit = ()
    def setSuspended(value: Boolean): Unit = ()
    def stopEffects(): Unit = ()
    def unlock(): Unit = ()
    def close(): Unit = ()
  }
}
