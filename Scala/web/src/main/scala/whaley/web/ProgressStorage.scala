package whaley.web

import org.scalajs.dom
import whaley.core.*

/** One versioned record, synchronously saved when a coin or setting changes. */
private object ProgressStorage {
  private val key = "whaley.progress.v1"

  def load(): PlayerProgress = try {
    Option(dom.window.localStorage.getItem(key)).flatMap { raw =>
      val decoded = PlayerProgressCodec.decode(raw, LevelData.all)
      if (decoded.isEmpty) dom.console.warn("Whaley ignored an invalid or unsupported saved progress record.")
      decoded
    }.getOrElse(PlayerProgress())
  } catch {
    case error: Throwable =>
      dom.console.warn(s"Whaley could not read saved progress: ${error.getMessage}")
      PlayerProgress()
  }

  def save(progress: PlayerProgress): Unit = try {
    dom.window.localStorage.setItem(key, PlayerProgressCodec.encode(progress))
  } catch {
    case error: Throwable => dom.console.error(s"Whaley could not save progress: ${error.getMessage}")
  }
}
