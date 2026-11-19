package whaley.core

class JumpTrailSuite extends munit.FunSuite {
  private val dt = 1.0 / 60
  private def step(trail: JumpTrail, x: Double, y: Double, jump: Boolean = false,
                   airborne: Boolean = true): Unit =
    trail.advance(Vec2(x, y), dt, airborne, playing = true, jumped = jump)
  private def isRainbow(trail: JumpTrail): Boolean = trail.marks.exists(_.color.red == 239)

  test("falling alone does not start a trail") {
    val trail = new JumpTrail()
    for (i <- 0 until 60) step(trail, 100, 200 - i)
    assertEquals(trail.marks, Vector.empty)
  }

  test("three water launches then rainbow, repeating without randomness") {
    val trail = new JumpTrail()
    for (launch <- 1 to 8) {
      step(trail, 100, 100, jump = true)
      assertEquals(isRainbow(trail), launch % 4 == 0)
      step(trail, 104, 104)
      assert(trail.marks.nonEmpty)
      for (_ <- 0 until 60) step(trail, 104, 104, airborne = false)
      assertEquals(trail.marks, Vector.empty)
    }
  }

  test("pause freezes geometry and opacity") {
    val trail = new JumpTrail()
    step(trail, 20, 20, jump = true)
    step(trail, 24, 24)
    val marks = trail.marks
    for (_ <- 0 until 100)
      trail.advance(Vec2(24, 24), dt, airborne = true, playing = true, jumped = false, paused = true)
    assertEquals(trail.marks, marks)
  }

  test("landing stops emission and lets old marks expire") {
    val trail = new JumpTrail()
    step(trail, 20, 20, jump = true)
    step(trail, 24, 24)
    step(trail, 24, 24, airborne = false)
    assert(trail.marks.nonEmpty)
    for (i <- 1 to 60) step(trail, 24 + i, 24, airborne = false)
    assertEquals(trail.marks, Vector.empty)
  }

  test("death and victory discard the trail immediately") {
    val trail = new JumpTrail()
    step(trail, 20, 20, jump = true)
    trail.advance(Vec2(24, 24), dt, airborne = true, playing = false, jumped = false)
    assertEquals(trail.marks, Vector.empty)
  }

  test("teleports do not create connecting streaks or restart emission") {
    val trail = new JumpTrail()
    step(trail, 20, 20, jump = true)
    step(trail, 300, 400)
    step(trail, 304, 404)
    assertEquals(trail.marks, Vector.empty)
    step(trail, 304, 404, jump = true)
    assert(trail.marks.nonEmpty)
  }

  test("Reduce Motion clears marks and waits for a new launch after re-enabling") {
    val trail = new JumpTrail()
    step(trail, 20, 20, jump = true)
    trail.setReducedMotion(true)
    assertEquals(trail.marks, Vector.empty)
    step(trail, 24, 24, jump = true)
    assertEquals(trail.marks, Vector.empty)
    trail.setReducedMotion(false)
    step(trail, 28, 28)
    assertEquals(trail.marks, Vector.empty)
    step(trail, 28, 28, jump = true)
    assert(trail.marks.nonEmpty)
  }

  test("invalid time is ignored; invalid position and long gaps clear transient state") {
    val trail = new JumpTrail()
    step(trail, 20, 20, jump = true)
    val marks = trail.marks
    for (seconds <- Vector(Double.NaN, Double.PositiveInfinity, -1.0, 0.0)) {
      trail.advance(Vec2(20, 20), seconds, airborne = true, playing = true, jumped = false)
      assertEquals(trail.marks, marks)
    }
    trail.advance(Vec2(Double.NaN, 20), dt, airborne = true, playing = true, jumped = false)
    assertEquals(trail.marks, Vector.empty)
    step(trail, 20, 20, jump = true)
    trail.advance(Vec2(24, 24), 10, airborne = true, playing = true, jumped = false)
    assertEquals(trail.marks, Vector.empty)
  }

  test("capacity remains bounded throughout sustained fast movement") {
    val trail = new JumpTrail()
    for (i <- 0 until 500) {
      step(trail, i * 40, i * 20, jump = i % 30 == 0)
      assert(trail.marks.size <= 288)
      trail.marks.foreach { mark =>
        assert(mark.center.finite && mark.width > 0 && mark.height > 0)
        assert(mark.color.alpha >= 0 && mark.color.alpha <= 0.8)
      }
    }
  }

  test("sampling the same straight path at 30, 60 and 120 Hz gives matching marks") {
    def run(rate: Int): Vector[JumpTrailMark] = {
      val trail = new JumpTrail()
      step(trail, 0, 0, jump = true)
      for (i <- 1 to rate / 5)
        trail.advance(Vec2(240.0 * i / rate, 120.0 * i / rate), 1.0 / rate,
          airborne = true, playing = true, jumped = false)
      trail.marks
    }
    val reference = run(60)
    for (rate <- Vector(30, 120)) {
      val actual = run(rate)
      assertEquals(actual.size, reference.size)
      actual.zip(reference).foreach { case (a, b) =>
        assertEquals(a.center, b.center)
        assertEquals(a.color.copy(alpha = 1), b.color.copy(alpha = 1))
        assertEqualsDouble(a.color.alpha, b.color.alpha, 1e-8)
      }
    }
  }

  test("reading a trail is side-effect-free; reset restores the water-first sequence") {
    val trail = new JumpTrail()
    for (_ <- 0 until 4) step(trail, 20, 20, jump = true)
    val marks = trail.marks
    for (_ <- 0 until 100) assertEquals(trail.marks, marks)
    assert(isRainbow(trail))
    trail.reset()
    assertEquals(trail.marks, Vector.empty)
    step(trail, 20, 20, jump = true)
    assert(!isRainbow(trail))
  }
}
