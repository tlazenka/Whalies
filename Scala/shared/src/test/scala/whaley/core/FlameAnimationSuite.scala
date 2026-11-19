package whaley.core

class FlameAnimationSuite extends munit.FunSuite {
  test("spin directions use opposite 30-degree steps and close after three seconds") {
    for (step <- 0 to 120) {
      val cw = FlameAnimation.poseAt(0, step * 0.25)
      val ccw = FlameAnimation.poseAt(1, step * 0.25)
      assertEquals(cw, FlamePose(clockwiseDegrees = step % 12 * 30))
      assertEquals(ccw, FlamePose(clockwiseDegrees = -cw.clockwiseDegrees))
    }
  }
  test("dance follows the approved two-pixel sequence without rotating") {
    val steps = Vector(0, 1, 2, 1, 0, -1, -2, -1)
    for (step <- 0 until 80)
      assertEquals(FlameAnimation.poseAt(2, step * 0.15), FlamePose(offsetX = steps(step % 8)))
  }
  test("hazard order assigns stable variants without consuming randomness") {
    for (index <- 0 until 100)
      assertEquals(FlameAnimation.poseAt(index, 1.75), FlameAnimation.poseAt(index % 3, 1.75))
  }
  test("pause freezes and reset restores the initial pose") {
    val animation = new FlameAnimation()
    animation.advance(0.25, paused = false)
    val before = (0 until 3).map(animation.pose(_))
    animation.advance(5, paused = true)
    assertEquals((0 until 3).map(animation.pose(_)), before)
    animation.reset()
    assert((0 until 3).forall(animation.pose(_) == FlamePose()))
  }
  test("30, 60 and 120 observations per second agree with the time-based policy") {
    for (fps <- Vector(30, 60, 120)) {
      val animation = new FlameAnimation()
      for (frame <- 1 to fps * 60) {
        animation.advance(1.0 / fps, paused = false)
        for (index <- 0 until 3)
          assertEquals(animation.pose(index), FlameAnimation.poseAt(index, frame.toDouble / fps))
      }
    }
  }
  test("reduced motion neutralizes both translation and rotation") {
    val animation = new FlameAnimation()
    animation.advance(0.25, paused = false)
    for (index <- 0 until 6) assertEquals(animation.pose(index, reducedMotion = true), FlamePose())
  }
  test("invalid and oversized frame deltas cannot poison the clock") {
    val animation = new FlameAnimation()
    for (seconds <- Vector(Double.NaN, Double.PositiveInfinity, -1.0, 0.0))
      animation.advance(seconds, paused = false)
    assertEquals(animation.pose(0), FlamePose())
    animation.advance(10, paused = false)
    assertEquals(animation.pose(0), FlamePose(clockwiseDegrees = 30))
    for (time <- Vector(Double.NaN, Double.PositiveInfinity, Double.NegativeInfinity, -1.0))
      assertEquals(FlameAnimation.poseAt(0, time), FlamePose())
  }
}
