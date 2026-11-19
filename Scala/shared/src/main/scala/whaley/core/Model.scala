package whaley.core

/** Portable, pixel-space world coordinates. +Y points up; player positions are
  * bottom-left, while bubble/coin/hazard/goal positions are their centers.
  */
final case class Vec2(x: Double, y: Double) {
  def +(other: Vec2): Vec2 = Vec2(x + other.x, y + other.y)
  def -(other: Vec2): Vec2 = Vec2(x - other.x, y - other.y)
  def *(scale: Double): Vec2 = Vec2(x * scale, y * scale)
  def finite: Boolean = x.isFinite && y.isFinite
}

final case class Rect(x: Double, y: Double, width: Double, height: Double) {
  def center: Vec2 = Vec2(x + width / 2, y + height / 2)
}

final case class HazardSpawn(position: Vec2, phase: Int)

/** Width/height and wall/ground coordinates are in TILES. Row zero is at the
  * world bottom (the generator flips TMX's top-down rows). Object positions
  * are pixels. `grounds` are one-way platforms, `walls` block all directions.
  */
final case class Level(
    number: Int,
    width: Int,
    height: Int,
    tileSize: Int,
    walls: Set[(Int, Int)],
    grounds: Set[(Int, Int)],
    spawn: Vec2,
    bubbles: Vector[Vec2],
    coins: Vector[Vec2],
    hazards: Vector[HazardSpawn],
    goal: Vec2
) {
  require(width > 0 && height > 0 && tileSize > 0)
  def worldWidth: Double = width.toDouble * tileSize
  def worldHeight: Double = height.toDouble * tileSize
}

enum AirMode { case Grounded, JumpingUp, JumpingDown, Falling }
enum Status { case Playing, Dead, Won }

/** Original menu rewards configure bubble lifetime and center shots. Normal
  * remains the default for direct level selection and existing simulations.
  */
enum BubbleMode { case Normal, ExtraBounce, Infinite }

final case class PlayerView(position: Vec2, airMode: AirMode, facingLeft: Boolean) {
  def bounds: Rect = Rect(position.x, position.y, 32, 32)
  def center: Vec2 = bounds.center
}
final case class BubbleView(id: Long, position: Vec2, radius: Double, bouncesLeft: Int, selected: Boolean, frozen: Boolean)
final case class CoinView(id: Int, position: Vec2)
final case class HazardView(position: Vec2, active: Boolean)
final case class Snapshot(
    tick: Long,
    player: PlayerView,
    bubbles: Vector[BubbleView],
    coins: Vector[CoinView],
    hazards: Vector[HazardView],
    goal: Vec2,
    status: Status,
    collected: Int,
    bubblesUsed: Int
) {
  def time: Double = tick.toDouble / 60.0
}

/** Shared input/output transform. Both renderers fit the original 320 x 568
  * viewport and use exactly this inverse for pointer hit testing.
  */
final case class Viewport(screenWidth: Double, screenHeight: Double, cameraBottom: Double,
                          worldWidth: Double = 320, viewHeight: Double = 568, cameraLeft: Double = 0) {
  // worldWidth names the visible span for renderer compatibility, not map width.
  def viewWidth: Double = worldWidth
  val scale: Double = math.min(screenWidth / worldWidth, screenHeight / viewHeight)
  val left: Double = (screenWidth - worldWidth * scale) / 2
  val top: Double = (screenHeight - viewHeight * scale) / 2
  def toScreen(world: Vec2): Vec2 = Vec2(left + (world.x - cameraLeft) * scale, top + (viewHeight - world.y + cameraBottom) * scale)
  def toWorld(screen: Vec2): Option[Vec2] = {
    if (scale <= 0 || !screen.finite || screen.x < left || screen.x > left + worldWidth * scale ||
        screen.y < top || screen.y > top + viewHeight * scale) None
    else Some(Vec2(cameraLeft + (screen.x - left) / scale, cameraBottom + viewHeight - (screen.y - top) / scale))
  }
}
object Viewport {
  def forGame(level: Level, state: Snapshot, width: Double, height: Double): Viewport = {
    val visibleWidth = 320.0
    val visibleHeight = 568.0
    // Helpers.setViewpointCenter first applies MAX(center, half-screen), then
    // MIN(map-size - half-screen). Preserve that order: the 544px-high level
    // 2/5 maps sit above a 24px bottom strip inside the original 568px view.
    val cameraLeft = math.min(math.max(state.player.center.x - visibleWidth / 2, 0), level.worldWidth - visibleWidth)
    val bottom = math.min(math.max(state.player.center.y - visibleHeight / 2, 0), level.worldHeight - visibleHeight)
    Viewport(width, height, bottom, visibleWidth, visibleHeight, cameraLeft)
  }
}

/** Bounded fixed-step accumulator. Resume after hiding a window with reset():
  * elapsed wall-clock gaps must not silently advance an unattended game.
  */
final class FixedStepClock(val maxSteps: Int = 15) {
  require(maxSteps > 0)
  private var accumulator = 0.0
  val step: Double = 1.0 / 60.0
  def reset(): Unit = accumulator = 0.0
  def advance(seconds: Double)(tick: () => Unit): Int = {
    if (!seconds.isFinite || seconds <= 0) return 0
    accumulator += math.min(seconds, maxSteps * step)
    var count = 0
    while (accumulator + 1e-10 >= step && count < maxSteps) {
      tick()
      accumulator = math.max(0, accumulator - step)
      count += 1
    }
    count
  }
}
