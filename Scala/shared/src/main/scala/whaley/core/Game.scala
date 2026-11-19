package whaley.core

/** A first portable translation of WhaleyScene's normal 2D rules.
  *
  * The scene advances in 60 Hz ticks, matching the original per-update pixel
  * speeds. It deliberately does not substitute a gravity/velocity platformer
  * for the historical ascent/descent speed bands. This is shared by Native
  * and JS; neither renderer owns a second player or collision simulation.
  *
  * Reference: Sources/WhaleyObjectiveC/src/{WhaleyScene,Projectile,Helpers}.m.
  * Menu rewards select the original extra-bounce/infinite configuration.
  * Coin checkpoints and sound cues are shared data; storage and audio playback
  * belong to the platforms. Presentation decides when to retry after death.
  */
final class Game(val level: Level, val mode: BubbleMode = BubbleMode.Normal) {
  private val defaultBounces = if (mode == BubbleMode.ExtraBounce) 3 else 2
  private final case class Tween(from: Vec2, to: Vec2, fromRadius: Double,
                                 toRadius: Double, elapsed: Int, duration: Int,
                                 freezeWhenDone: Boolean)
  private final class Bubble(val id: Long, var position: Vec2,
                             var radius: Double = 22, var bounces: Int = defaultBounces,
                             var frozen: Boolean = true) {
    var selected = false
    var offset = Vec2(0, 0)
    var tween: Option[Tween] = None
  }
  private var ticks = 0L
  private var sceneTicks = 0L
  private var state = Status.Playing
  private var player = level.spawn
  private var air = AirMode.Falling
  private var facingLeft = false
  private var movingLaterally = false
  private var desiredX = player.x + 16
  private var xStep = 3
  private var yStep = 2
  private var groundY = player.y
  private var ceilingFactor = 1.0
  private var bubbleID = 1L
  private var bubbles = Vector.empty[Bubble]
  private var coins = Vector.empty[CoinView]
  private var used = 0
  private var lastCheckpoint: Option[GameCheckpoint] = None
  private var invincible = false
  private var sounds = Vector.empty[SoundCue]
  private var pointer: Option[Vec2] = None
  private var sustained = false
  private val smallScale = 44.0 / 128.0

  restart()

  def snapshot: Snapshot = Snapshot(
    ticks, PlayerView(player, air, facingLeft),
    bubbles.map(b => BubbleView(b.id, b.position, b.radius, b.bounces, b.selected, b.frozen)),
    coins, level.hazards.map(h => HazardView(h.position, hazardActive(h))),
    level.goal, state, level.coins.length - coins.length, used
  )

  /** The latest coin save is immutable until another coin is collected.
    * Platforms need only write when this value changes, not on every frame.
    */
  def checkpoint: Option[GameCheckpoint] = lastCheckpoint

  def isInvincible: Boolean = invincible
  def setInvincible(enabled: Boolean): Unit = invincible = enabled

  def drainSounds(): Vector[SoundCue] = {
    val pending = sounds
    sounds = Vector.empty
    pending
  }

  /** Explicitly begin a fresh attempt. The invincibility preference remains in force. */
  def restart(): Unit = {
    lastCheckpoint = None
    resetScene(level.spawn, Set.empty, 0L, 0)
  }

  /** Restore a process-persistent coin save without accepting arbitrary world
    * coordinates. An invalid/mismatched record leaves the current game intact.
    */
  def restoreCheckpoint(saved: GameCheckpoint): Boolean = {
    if (saved == null || !saved.validFor(level) || saved.mode != mode) return false
    lastCheckpoint = Some(saved.copy(collectedCoinIds = saved.collectedCoinIds.sorted))
    resetScene(level.coins(saved.lastCoinId) - Vec2(16, 16),
      saved.collectedCoinIds.toSet, saved.elapsedTicks, saved.bubblesUsed)
    true
  }

  /** Retry the scene at the last coin while retaining time and shots spent
    * since that coin, as the original in-memory Level does after death.
    * Returns false only when there was no coin: that retry starts at the level
    * origin. Pause Continue should simply continue ticking, not call resume().
    */
  def resume(): Boolean = {
    val saved = lastCheckpoint
    val position = saved.map(cp => level.coins(cp.lastCoinId) - Vec2(16, 16)).getOrElse(level.spawn)
    resetScene(position, saved.map(_.collectedCoinIds.toSet).getOrElse(Set.empty), ticks, used)
    saved.nonEmpty
  }

  private def resetScene(position: Vec2, collected: Set[Int], elapsedTicks: Long,
                         bubblesUsed: Int): Unit = {
    ticks = elapsedTicks
    sceneTicks = 0
    state = Status.Playing
    player = position
    air = AirMode.Falling
    facingLeft = false
    movingLaterally = false
    desiredX = player.x + 16
    xStep = 3
    yStep = 2
    groundY = player.y
    ceilingFactor = 1
    bubbleID = 1
    bubbles = level.bubbles.map { p =>
      val b = new Bubble(bubbleID, p)
      bubbleID += 1
      b
    }
    coins = level.coins.zipWithIndex.collect { case (p, i) if !collected(i) => CoinView(i, p) }
    used = bubblesUsed
    pointer = None
    sustained = false
    sounds = Vector.empty
    if (restingOnGround) air = AirMode.Grounded
  }

  def pointerDown(point: Vec2): Unit = {
    if (state != Status.Playing || !point.finite || pointer.nonEmpty) return
    pointer = Some(point)
    sustained = true
    if (!selectBubble(point) && point.y < player.y + 32) shoot(point)
  }

  def pointerMove(point: Vec2): Unit = {
    if (state != Status.Playing || pointer.isEmpty || !point.finite) return
    pointer = Some(point)
    sustained = false
    bubbles.find(_.selected) match {
      case Some(b) =>
        b.position = point - b.offset
        // Pointer movement must not be overwritten by an earlier move tween.
        b.tween = b.tween.map(t => t.copy(from = b.position, to = b.position))
      case None => selectBubble(point)
    }
  }

  def pointerUp(point: Vec2): Unit = {
    if (pointer.isEmpty) return
    releaseSelection()
    pointer = None
    sustained = false
  }

  /** Browser pointer cancellation/window focus loss releases the selected
    * bubble without firing another shot or leaving a held interaction alive.
    */
  def cancelPointer(): Unit = {
    releaseSelection()
    pointer = None
    sustained = false
  }

  private def releaseSelection(): Unit = bubbles.filter(_.selected).foreach { b =>
    b.selected = false
    val destination = b.position + b.offset * (1 - smallScale)
    b.tween = Some(Tween(b.position, destination, b.radius, 22, 0, 6, false))
  }

  private def selectBubble(point: Vec2): Boolean = {
    bubbles.find(b => b.frozen && !b.selected && distanceSquared(point, b.position) < square(b.radius + 5)) match {
      case Some(b) =>
        b.selected = true
        b.offset = (point - b.position) * (1 / smallScale)
        val destination = point - b.offset
        b.tween = Some(Tween(b.position, destination, b.radius, 64, 0, 6, false))
        true
      case None => false
    }
  }

  private def shoot(point: Vec2): Unit = {
    val left = point.x < player.x + 16
    // Original ExtraBounce/Infinite modes allow a centered shot within the
    // player's half-width + MIDDLE_BOUNCE_RANGE (16 + 6 logical pixels).
    val middle = mode != BubbleMode.Normal && math.abs(point.x - (player.x + 16)) <= 22
    val x = if (middle) player.x + 16 else if (left) player.x else player.x + 33
    if (!middle) facingLeft = !left
    val yOffset = if (air == AirMode.JumpingDown || air == AirMode.Falling) -1 - yStep else -1
    val near = point.y + 44 > player.y + yOffset
    // The Objective-C declaration truncates ReallySmallScale=0.1 to NSInteger.
    // Use its effective 0 for destination parity, and animate visible radius.
    val targetY = math.max(0, if (near) player.y + yOffset else point.y)
    val target = Vec2(x, targetY)
    val start = if (near) target else Vec2(x, player.y)
    val bubble = new Bubble(bubbleID, start, radius = 0, frozen = near)
    bubbleID += 1
    bubble.tween = Some(Tween(start, target, 0, 22, 0, if (near) 6 else 12, !near))
    if (bubbles.length >= 500) bubbles = bubbles.tail
    bubbles :+= bubble
    if (used < Int.MaxValue) used += 1
  }

  def tick(): Unit = {
    if (state == Status.Won) return
    if (ticks < GameCheckpoint.MaxElapsedTicks) ticks += 1
    // The original score clock includes its two-second death presentation.
    // The platforms continue fixed ticks until presentation requests retry.
    if (state == Status.Dead) return
    sceneTicks += 1
    if ((level.number == 1 || level.number == 4) && sceneTicks % 600 == 0) sounds :+= SoundCue.Anvil
    advanceBubbles()
    if (!invincible && level.hazards.exists(h => hazardActive(h) && circleHitsPlayer(h.position, 8, 2, 2))) {
      state = Status.Dead
      sounds :+= SoundCue.Death
      cancelPointer()
      return
    }

    movePlayer()
    if (air != AirMode.JumpingUp) {
      collideBubbles()
      // WhaleyScene retries a stationary touch in its collision block. A
      // held pointer does not acquire another bubble during later ascent.
      if (sustained && !bubbles.exists(_.selected)) pointer.foreach(selectBubble)
    }

    val collected = coins.filter(c => circleHitsPlayer(c.position, 15, 1, 0))
    if (collected.nonEmpty) {
      val collectedNow = collected.map(_.id).toSet
      coins = coins.filterNot(c => collectedNow(c.id))
      val remainingIDs = coins.map(_.id).toSet
      lastCheckpoint = Some(GameCheckpoint(level.number, mode, collected.last.id,
        level.coins.indices.filterNot(remainingIDs).toVector, ticks, used))
      collected.foreach(_ => sounds :+= SoundCue.Coin)
    }
    if (circleHitsPlayer(level.goal, 15, 1, 0)) {
      state = Status.Won
      lastCheckpoint = None
      sounds :+= SoundCue.Goal
      cancelPointer()
    }
  }

  private def advanceBubbles(): Unit = bubbles.foreach { b =>
    b.tween.foreach { t =>
      val next = t.elapsed + 1
      val fraction = math.min(1.0, next.toDouble / t.duration)
      // Original shot scales for 0.1s, then travels for 0.1s.
      val movementFraction = if (t.freezeWhenDone) math.max(0, (next - 6).toDouble / 6) else fraction
      val radiusFraction = if (t.freezeWhenDone) math.min(1.0, next.toDouble / 6) else fraction
      b.position = t.from + (t.to - t.from) * movementFraction
      b.radius = t.fromRadius + (t.toRadius - t.fromRadius) * radiusFraction
      if (next >= t.duration) {
        if (t.freezeWhenDone) b.frozen = true
        b.tween = None
      } else b.tween = Some(t.copy(elapsed = next))
    }
  }

  private def movePlayer(): Unit = {
    val previousCenterX = player.x + 16
    if (movingLaterally) {
      val diff = desiredX - (player.x + 16)
      val direction = if (diff > 0) 1 else -1
      val available = (xStep to 1 by -1).find(n => !wallAt(player + Vec2(n * direction, 0)))
      available match {
        case Some(n) => player = player + Vec2(n * direction, 0)
        case None => movingLaterally = false
      }
      if (math.abs(diff) < xStep || player.x <= 0 || player.x >= level.worldWidth - 32) movingLaterally = false
    }

    if (air != AirMode.Grounded) {
      xStep = 2
      if (air == AirMode.JumpingUp && wallAt(player + Vec2(0, yStep))) {
        air = AirMode.JumpingDown
        yStep = 1
        ceilingFactor = (player.y - groundY) / 90
        if (ceilingFactor < 1.0 / 3) air = AirMode.Falling
      }
      if (air == AirMode.Falling) yStep = 1
      if (level.number >= 4) { ceilingFactor = 0.5; yStep = 1 }
      if (air == AirMode.JumpingUp) {
        if (!wallAt(player + Vec2(0, yStep))) player = player + Vec2(0, yStep)
      } else {
        if (!wallAt(player + Vec2(0, -yStep))) player = player + Vec2(0, -yStep)
      }
      if (air != AirMode.Falling) {
        val height = player.y - groundY
        if (height <= 0) air = AirMode.Falling
        else if (height <= 45 * ceilingFactor) yStep = 3
        else if (height <= 75 * ceilingFactor) yStep = 2
        else if (height <= 87 * ceilingFactor && ceilingFactor >= 0.8) yStep = 2
        else if (height <= 90 * ceilingFactor) yStep = 1
        else { yStep = 1; air = AirMode.JumpingDown }
      }
      // Ground metadata does not block movement. The source first checks the
      // occupied cells, slows an unaligned descent to FALLING, and grounds
      // only at a tile boundary. In particular, do not ground above a wall
      // merely because a three-pixel step would cross its top edge.
      if (air != AirMode.JumpingUp && (atGround(player) || wallAt(player + Vec2(0, -yStep)))) {
        if (onTileBoundary) land(previousCenterX)
        else air = AirMode.Falling
      }
    }
    if (air != AirMode.JumpingUp && air != AirMode.JumpingDown &&
        !atGround(player) && !wallAt(player + Vec2(0, -yStep))) {
      air = AirMode.Falling
      movingLaterally = false
      yStep = 1
    }
  }

  private def land(previousCenterX: Double): Unit = {
    air = AirMode.Grounded
    xStep = 3
    desiredX = previousCenterX
    groundY = player.y
  }

  private def collideBubbles(): Unit = {
    val remove = scala.collection.mutable.Set.empty[Long]
    bubbles.filter(_.frozen).foreach { b =>
      // The source tests the frozen snapshot in insertion order once it has
      // entered this block, including overlapping bubbles after a bounce.
      if (circleHitsPlayer(b.position, b.radius - 1, 1, 0)) {
        val dx = player.x + 16 - b.position.x
        val dy = player.y + 16 - b.position.y
        if (math.abs(dx) <= 2 && math.abs(dy) <= 2) remove += b.id
        else {
          val jump = dy >= b.radius
          if (jump) {
            sounds :+= SoundCue.Jump
            air = AirMode.JumpingUp
            ceilingFactor = 1
            groundY = player.y
            yStep = 3
            movingLaterally = math.abs(dx) >= b.radius / 2
            xStep = 3
            desiredX = player.x + 16 + (if (dx > 0) 1 else -1) * level.tileSize * 1.5
          } else {
            sounds :+= SoundCue.Bounce
            movingLaterally = true
            xStep = 3
            desiredX = if (dx > 0) level.worldWidth - 32 else 0
          }
          if (mode != BubbleMode.Infinite && (!b.selected || jump)) b.bounces -= 1
          if (b.bounces <= 0) remove += b.id
        }
      }
    }
    bubbles = bubbles.filterNot(b => remove(b.id))
  }

  private def hazardActive(h: HazardSpawn): Boolean = {
    if (h.phase == -1) true
    else {
      val phase = if ((sceneTicks / 120) % 2 == 0) 180 else 0
      h.phase == phase && sceneTicks % 120 >= 15
    }
  }

  private def wallAt(p: Vec2): Boolean = {
    if (p.x < 0 || p.y < 0 || p.x + 32 > level.worldWidth || p.y + 32 > level.worldHeight) true
    else overlapsCells(p, level.walls)
  }

  /** A ground marker is the cell the player occupies while grounded. This
    * matches Helpers.isAt + isYposExactlyOnTile: its surface is the BOTTOM
    * edge, unlike a wall's top edge. Ascending through ground is allowed.
    */
  private def atGround(p: Vec2): Boolean = overlapsCells(p, level.grounds)

  private def overlapsCells(p: Vec2, cells: Set[(Int, Int)]): Boolean = {
    val left = math.floor(p.x / level.tileSize).toInt
    val right = math.floor((p.x + 32 - 0.00001) / level.tileSize).toInt
    val bottom = math.floor(p.y / level.tileSize).toInt
    val top = math.floor((p.y + 32 - 0.00001) / level.tileSize).toInt
    (left to right).exists(x => (bottom to top).exists(y => cells((x, y))))
  }

  private def onTileBoundary: Boolean = player.y.toInt % level.tileSize == 0

  private def restingOnGround: Boolean =
    (atGround(player) || wallAt(player + Vec2(0, -yStep))) && onTileBoundary

  private def circleHitsPlayer(center: Vec2, radius: Double, insetX: Double, insetY: Double): Boolean = {
    if (radius <= 0) false
    else {
      val closest = Vec2(clamp(center.x, player.x + insetX, player.x + 31 - insetX),
                         clamp(center.y, player.y + insetY, player.y + 31 - insetY))
      distanceSquared(center, closest) < radius * radius
    }
  }
  private def clamp(value: Double, low: Double, high: Double): Double = math.max(low, math.min(high, value))
  private def square(value: Double): Double = value * value
  private def distanceSquared(a: Vec2, b: Vec2): Double = square(a.x - b.x) + square(a.y - b.y)
}
