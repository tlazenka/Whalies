package whaley.core

final case class FlamePose(offsetX: Double = 0, clockwiseDegrees: Double = 0)

object FlameAnimation {
  private val dance = Vector(0, 1, 2, 1, 0, -1, -2, -1)

  def poseAt(index: Int, elapsed: Double, reducedMotion: Boolean = false): FlamePose = {
    if (reducedMotion || !elapsed.isFinite || elapsed < 0) FlamePose()
    else {
      val time = elapsed % 6.0
      Math.floorMod(index, 3) match {
        case 0 => FlamePose(clockwiseDegrees = (math.floor(time / 0.25 + 1e-9).toInt % 12) * 30)
        case 1 => FlamePose(clockwiseDegrees = -(math.floor(time / 0.25 + 1e-9).toInt % 12) * 30)
        case _ => FlamePose(offsetX = dance(math.floor(time / 0.15 + 1e-9).toInt % 8))
      }
    }
  }
}

/** Presentation only: never changes a hazard's position or active phase. */
final class FlameAnimation {
  private var elapsed = 0.0
  def reset(): Unit = elapsed = 0
  def advance(seconds: Double, paused: Boolean): Unit = {
    if (!paused && seconds.isFinite && seconds > 0)
      elapsed = (elapsed + math.min(seconds, 0.25)) % 6.0
  }
  def pose(index: Int, reducedMotion: Boolean = false): FlamePose =
    FlameAnimation.poseAt(index, elapsed, reducedMotion)
}
