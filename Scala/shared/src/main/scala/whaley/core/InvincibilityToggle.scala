package whaley.core

/** The host-level star stays the same size as the play surface is resized.
  * Both hosts draw this polygon in a 24 x 24 icon; native input uses window
  * coordinates so the button also works in the letterbox around the game.
  */
object InvincibilityToggle {
  val size: Double = 44
  val margin: Double = 8
  val iconSize: Double = 24
  val starPoints: Vector[Vec2] = Vector(
    Vec2(12, 2), Vec2(15.09, 8.26), Vec2(22, 9.27), Vec2(17, 14.14),
    Vec2(18.18, 21.02), Vec2(12, 17.77), Vec2(5.82, 21.02),
    Vec2(7, 14.14), Vec2(2, 9.27), Vec2(8.91, 8.26))

  def bounds(width: Double, height: Double): Rect =
    Rect(math.max(0, width - margin - size), math.max(0, height - margin - size), size, size)

  def contains(point: Vec2, width: Double, height: Double): Boolean = {
    val rect = bounds(width, height)
    point.finite && width.isFinite && height.isFinite && width > 0 && height > 0 &&
      point.x >= rect.x && point.x < math.min(width, rect.x + rect.width) &&
      point.y >= rect.y && point.y < math.min(height, rect.y + rect.height)
  }
}
