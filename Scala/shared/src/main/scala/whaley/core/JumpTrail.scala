package whaley.core

final case class JumpTrailMark(center: Vec2, width: Double, height: Double, color: UiColor)

/** Presentation only; mirrored by WhaleyJumpTrail.h for the SpriteKit adapter. */
final class JumpTrail {
  private case class Sample(point: Vec2, normal: Vec2, age: Double, rainbow: Boolean,
                            landedMask: Int = 0)
  private case class Surface(y: Double, left: Double, right: Double)
  private case class Puddle(point: Vec2, left: Double, right: Double, width: Double, age: Double)
  private val rainbowLifetime = 0.30
  private val waterLifetime = 0.75
  private val puddleLifetime = 4.0
  private val capacity = 48
  private val puddleCapacity = 48
  private val waterLaneCount = 3
  private val waterLandedMask = (1 << waterLaneCount) - 1
  private val spriteWidth = 32.0
  private val rainbowColors = Vector(UiColor(239, 82, 82), UiColor(255, 165, 66),
    UiColor(255, 221, 87), UiColor(86, 200, 116), UiColor(0, 114, 206), UiColor(150, 100, 225))
  private var samples = Vector.empty[Sample]
  private var puddles = Vector.empty[Puddle]
  private var surfaceLevel: Option[Level] = None
  private var cachedSurfaces = Vector.empty[Surface]
  private var previous: Option[Vec2] = None
  private var lastObserved: Option[(Int, Long)] = None
  private var launchCycle = 0
  private var emitting = false
  private var rainbow = false
  private var distanceRemainder = 0.0
  private var reducedMotion = false

  def reset(): Unit = {
    stop()
    launchCycle = 0
    rainbow = false
    lastObserved = None
    surfaceLevel = None
    cachedSurfaces = Vector.empty
  }

  private def stop(): Unit = {
    samples = Vector.empty
    puddles = Vector.empty
    previous = None
    emitting = false
    distanceRemainder = 0
  }

  def setReducedMotion(enabled: Boolean): Unit = {
    reducedMotion = enabled
    if (enabled) stop()
  }

  def observeTick(level: Level, before: Snapshot, after: Snapshot, cues: Vector[SoundCue]): Unit = {
    if (lastObserved.exists { case (number, tick) => number != level.number || after.tick < tick }) reset()
    if (lastObserved.contains((level.number, after.tick))) return
    lastObserved = Some((level.number, after.tick))
    advance(after.player.center, (after.tick - before.tick).toDouble / 60,
      after.player.airMode != AirMode.Grounded, after.status == Status.Playing,
      cues.contains(SoundCue.Jump), level = Some(level))
  }

  private def pixel(value: Double): Double = math.floor(value + 0.5)
  private def pixel(point: Vec2): Vec2 = Vec2(pixel(point.x), pixel(point.y))

  /** Ground markers describe the cell ABOVE a platform; walls occupy the cell below it. */
  private def surfaces(level: Level): Vector[Surface] = {
    if (!surfaceLevel.exists(_ eq level)) {
      def valid(x: Int, y: Int): Boolean = x >= 0 && x < level.width && y >= 0 && y < level.height
      val tile = level.tileSize.toDouble
      val grounds = level.grounds.iterator.collect {
        case (x, y) if valid(x, y) && !level.walls((x, y)) =>
          Surface(y * tile, x * tile, (x + 1) * tile)
      }
      val walls = level.walls.iterator.collect {
        case (x, y) if valid(x, y) && !level.walls((x, y + 1)) =>
          Surface((y + 1) * tile, x * tile, (x + 1) * tile)
      }
      // Merge touching supports so water can spread across a continuous platform,
      // while retaining the edges that keep it from hanging over a gap.
      cachedSurfaces = (grounds ++ walls).toVector.sortBy(s => (-s.y, s.left)).foldLeft(Vector.empty[Surface]) {
        case (out, surface) if out.lastOption.exists(s => s.y == surface.y && surface.left <= s.right) =>
          out.updated(out.size - 1, out.last.copy(right = math.max(out.last.right, surface.right)))
        case (out, surface) => out :+ surface
      }
      surfaceLevel = Some(level)
    }
    cachedSurfaces
  }

  private def deposit(x: Double, surface: Surface, age: Double): Unit = {
    if (age >= puddleLifetime) return
    val matching = puddles.indexWhere(p => math.abs(p.point.x - x) <= 6 &&
      math.abs(p.point.y - surface.y) <= 1e-9 && p.left == surface.left && p.right == surface.right)
    if (matching >= 0) {
      val old = puddles(matching)
      puddles = puddles.updated(matching,
        old.copy(width = math.min(12, old.width + 2), age = math.min(old.age, age)))
    } else {
      puddles = (puddles :+ Puddle(Vec2(x, surface.y), surface.left, surface.right, 8, age)).takeRight(puddleCapacity)
    }
  }

  private def waterOrigin(sample: Sample, lane: Int): Vec2 = {
    val spread = spriteWidth - 2 * math.abs(sample.normal.x) - 3 * math.abs(sample.normal.y)
    sample.point + sample.normal * ((lane.toDouble / (waterLaneCount - 1) - 0.5) * spread)
  }

  private def waterBottom(origin: Vec2, age: Double): Double = origin.y - 1.5 - 20 * age - 90 * age * age

  /** Sweep before expiry so a droplet cannot skip its last ground contact on a long tick. */
  private def ageSample(sample: Sample, seconds: Double, supports: Vector[Surface]): Option[Sample] = {
    val nextAge = sample.age + seconds
    val lifetime = if (sample.rainbow) rainbowLifetime else waterLifetime
    var landed = sample.landedMask
    if (!sample.rainbow && supports.nonEmpty) {
      val endAge = math.min(nextAge, waterLifetime)
      for (lane <- 0 until waterLaneCount if (landed & (1 << lane)) == 0) {
        val origin = waterOrigin(sample, lane)
        val x = pixel(origin.x)
        val fromBottom = waterBottom(origin, sample.age)
        val toBottom = waterBottom(origin, endAge)
        supports.find(s => x >= s.left && x < s.right &&
          fromBottom >= s.y - 1e-9 && toBottom <= s.y + 1e-9).foreach { surface =>
          val impactAge = math.max(sample.age,
            (-20 + math.sqrt(math.max(0, 400 + 360 * (origin.y - 1.5 - surface.y)))) / 180)
          deposit(x, surface, math.max(0, nextAge - impactAge))
          landed |= 1 << lane
        }
      }
    }
    if (nextAge < lifetime && (sample.rainbow || landed != waterLandedMask)) Some(sample.copy(age = nextAge, landedMask = landed))
    else None
  }

  private def append(sample: Sample, supports: Vector[Surface]): Unit = {
    // Interpolated samples are already partway through this tick when born.
    ageSample(sample.copy(age = 0), sample.age, supports).foreach { aged =>
      samples = (samples :+ aged).takeRight(capacity)
    }
  }

  def advance(point: Vec2, seconds: Double, airborne: Boolean, playing: Boolean,
              jumped: Boolean, paused: Boolean = false, level: Option[Level] = None): Unit = {
    if (!point.finite || !playing || reducedMotion) { stop(); return }
    if (paused) { previous = Some(point); distanceRemainder = 0; return }
    if (!seconds.isFinite || seconds <= 0) return
    if (seconds > 0.25) { stop(); previous = Some(point); return }
    val supports = level.map(surfaces).getOrElse(Vector.empty)
    puddles = puddles.map(p => p.copy(age = p.age + seconds)).filter(_.age < puddleLifetime)
    samples = samples.flatMap(s => ageSample(s, seconds, supports))
    val delta = previous.map(point - _).getOrElse(Vec2(0, 0))
    var distance = math.hypot(delta.x, delta.y)
    if (!distance.isFinite || distance > 96) { stop(); distance = 0 }
    if (jumped && airborne) {
      launchCycle = (launchCycle + 1) % 4
      rainbow = launchCycle == 0
      emitting = true
      distanceRemainder = 0
      val normal = if (distance > 1e-9) Vec2(-delta.y / distance, delta.x / distance) else Vec2(-1, 0)
      append(Sample(point, normal, 0, rainbow), supports)
    } else {
      if (!airborne) { emitting = false; distanceRemainder = 0 }
      if (emitting && distance > 1e-9) {
        val spacing = if (rainbow) 2.0 else 4.0
        val normal = Vec2(-delta.y / distance, delta.x / distance)
        val start = previous.getOrElse(point)
        var offset = spacing - distanceRemainder
        while (offset <= distance + 1e-9) {
          val fraction = math.min(1, offset / distance)
          append(Sample(start + delta * fraction, normal, seconds * (1 - fraction), rainbow), supports)
          offset += spacing
        }
        distanceRemainder = (distanceRemainder + distance) % spacing
        if (distanceRemainder < 1e-9 || spacing - distanceRemainder < 1e-9) distanceRemainder = 0
      }
    }
    previous = Some(point)
  }

  private def puddleMarks: Vector[JumpTrailMark] = puddles.flatMap { puddle =>
    val remaining = math.max(0, 1 - puddle.age / puddleLifetime)
    val spread = 0.75 + 0.25 * math.min(puddle.age / 0.15, 1)
    val width = math.max(2, pixel(puddle.width * spread * (1 - 0.6 * puddle.age / puddleLifetime)))
    val wantedLeft = pixel(puddle.point.x - width / 2)
    val left = math.max(puddle.left, wantedLeft)
    val right = math.min(puddle.right, wantedLeft + width)
    val actualWidth = right - left
    if (actualWidth < 1) Vector.empty
    else {
      val x = (left + right) / 2
      val height = if (puddle.age < 2) 2.0 else 1.0
      Vector(JumpTrailMark(Vec2(x, puddle.point.y + height / 2), actualWidth, height,
        UiColor(0, 114, 206, 0.6 * remaining)),
        JumpTrailMark(Vec2(x, puddle.point.y + height - 0.5), math.max(1, pixel(actualWidth * 0.5)), 1,
          UiColor(150, 220, 255, 0.45 * remaining)))
    }
  }

  /** Read-only, bottom-left world coordinates; camera movement never ages the trail. */
  def marks: Vector[JumpTrailMark] = puddleMarks ++ samples.flatMap { sample =>
    val lifetime = if (sample.rainbow) rainbowLifetime else waterLifetime
    val alpha = 0.8 * math.max(0, 1 - sample.age / lifetime)
    if (sample.rainbow) rainbowColors.zipWithIndex.map { case (color, band) =>
      val spread = spriteWidth - 6 * (math.abs(sample.normal.x) + math.abs(sample.normal.y))
      val offset = (band / 5.0 - 0.5) * spread
      JumpTrailMark(pixel(sample.point + sample.normal * offset), 6, 6, color.copy(alpha = alpha))
    } else {
      val age = sample.age
      (0 until waterLaneCount).toVector.filter(lane => (sample.landedMask & (1 << lane)) == 0).flatMap { lane =>
        val origin = waterOrigin(sample, lane)
        val center = Vec2(pixel(origin.x), pixel(origin.y - 20 * age - 90 * age * age))
        Vector(JumpTrailMark(center, 2, 3, UiColor(0, 114, 206, alpha)),
          JumpTrailMark(center + Vec2(-0.5, 0.5), 1, 1, UiColor(alpha = alpha)))
      }
    }
  }

  def commands(view: Viewport): Vector[UiDraw] = marks.map { mark =>
    val x = mark.center.x - view.cameraLeft
    val y = view.viewHeight - (mark.center.y - view.cameraBottom)
    UiDraw.Fill(Rect(x - mark.width / 2, y - mark.height / 2, mark.width, mark.height), mark.color)
  }
}
