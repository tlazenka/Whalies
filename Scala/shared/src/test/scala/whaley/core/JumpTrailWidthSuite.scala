package whaley.core

class JumpTrailWidthSuite extends munit.FunSuite {
  private val dt = 1.0 / 60

  private def launch(rainbow: Boolean, direction: Vec2): Vector[JumpTrailMark] = {
    val trail = new JumpTrail()
    if (rainbow) {
      for (_ <- 0 until 3) {
        trail.advance(Vec2(0, 0), dt, airborne = true, playing = true, jumped = true)
        for (_ <- 0 until 60)
          trail.advance(Vec2(0, 0), dt, airborne = false, playing = true, jumped = false)
      }
    }
    trail.advance(Vec2(0, 0), dt, airborne = false, playing = true, jumped = false)
    trail.advance(direction * 4, dt, airborne = true, playing = true, jumped = true)
    trail.marks
  }

  private def span(marks: Vector[JumpTrailMark], normal: Vec2): Double = {
    val intervals = marks.map { mark =>
      val center = mark.center.x * normal.x + mark.center.y * normal.y
      val half = (mark.width * math.abs(normal.x) + mark.height * math.abs(normal.y)) / 2
      (center - half, center + half)
    }
    intervals.map(_._2).max - intervals.map(_._1).min
  }

  for (rainbow <- Vector(false, true)) {
    test(s"${if (rainbow) "rainbow" else "water"} spans the 32-pixel sprite width on both axes") {
      for (direction <- Vector(Vec2(0, 1), Vec2(0, -1), Vec2(1, 0), Vec2(-1, 0))) {
        val marks = launch(rainbow, direction)
        assertEquals(marks.size, 6)
        assertEqualsDouble(span(marks, Vec2(-direction.y, direction.x)), 32, 1e-8)
      }
    }

    test(s"${if (rainbow) "rainbow" else "water"} retains its transverse width around diagonal paths") {
      for (degrees <- 0 until 360) {
        val angle = degrees * math.Pi / 180
        val direction = Vec2(math.cos(angle), math.sin(angle))
        val width = span(launch(rainbow, direction), Vec2(-direction.y, direction.x))
        assert(math.abs(width - 32) <= math.sqrt(2) + 1e-8)
      }
    }
  }

  test("water stays three small droplets with contained white highlights") {
    val marks = launch(false, Vec2(0, 1))
    assertEquals(marks.map(_.width), Vector(2.0, 1.0, 2.0, 1.0, 2.0, 1.0))
    assertEquals(marks.map(_.height), Vector(3.0, 1.0, 3.0, 1.0, 3.0, 1.0))
    assertEquals(marks.count(_.color == UiColor(0, 114, 206, 0.8)), 3)
  }

  test("rainbow keeps six adjacent colored bands, not six narrow separated lines") {
    val marks = launch(true, Vec2(0, 1)).sortBy(_.center.x)
    assertEquals(marks.map(_.color).distinct.size, 6)
    marks.sliding(2).foreach { pair =>
      assert(pair(1).center.x - pair(0).center.x <= (pair(0).width + pair(1).width) / 2)
    }
  }
}
