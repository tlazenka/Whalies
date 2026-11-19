package whaley.core

/** Facial rows in the 32-pixel character atlas, each with a 3 x 3 gaze grid. */
enum CharacterExpression(val row: Int) {
  case Neutral extends CharacterExpression(0)
  case Pensive extends CharacterExpression(1)
  case Alarmed extends CharacterExpression(2)
  case Relief extends CharacterExpression(3)
  case Happy extends CharacterExpression(4)
  case Playful extends CharacterExpression(5)
  case Relaxed extends CharacterExpression(6)
  case Whistle extends CharacterExpression(7)
  case TongueOut extends CharacterExpression(8)
  case EyeRoll extends CharacterExpression(9)
  case Exasperated extends CharacterExpression(10)
}

enum CharacterTargetKind { case Hazard, Coin }
final case class CharacterTarget(kind: CharacterTargetKind, id: Int)
final case class CharacterFrame(expression: CharacterExpression, column: Int,
                                target: Option[CharacterTarget]) {
  def row: Int = expression.row
  def source: Rect = Rect(column * 32, row * 32, 32, 32)
}

/** Observes completed simulation steps without owning movement or collision.
  * All transient lifetimes and target locks use those steps, never render
  * frequency. Sounds are confirmed outcomes supplied before audio filtering.
  */
final class CharacterPresentation {
  import CharacterExpression.*
  private final case class Candidate(key: CharacterTarget, position: Vec2,
                                     rank: Int, distanceSquared: Double)
  private final case class Reaction(expression: CharacterExpression, start: Long,
                                    duration: Int, priority: Int)

  private var lastObserved: Option[(Int, Long)] = None
  private var tick = 0L
  private var target: Option[Candidate] = None
  private var targetSince = 0L
  private var reaction: Option[Reaction] = None
  private var urgent = false
  private var closeCall = false
  private var safeTicks = 0
  private var idleTicks = 0
  private var coinCount = 0
  private var coinTick: Option[Long] = None
  private var jumpCount = 0
  private var jumpTick: Option[Long] = None
  private var sideCount = 0
  private var sideTick: Option[Long] = None
  private var sideBubble: Option[Long] = None
  private var sideDirection = 0

  def reset(): Unit = {
    lastObserved = None
    tick = 0
    target = None
    targetSince = 0
    reaction = None
    urgent = false
    closeCall = false
    safeTicks = 0
    idleTicks = 0
    coinCount = 0
    coinTick = None
    jumpCount = 0
    jumpTick = None
    sideCount = 0
    sideTick = None
    sideBubble = None
    sideDirection = 0
  }

  private def lengthSquared(point: Vec2): Double = point.x * point.x + point.y * point.y
  private def segmentDistanceSquared(point: Vec2, start: Vec2, end: Vec2): Double = {
    val line = end - start
    val length = lengthSquared(line)
    val fraction = if (length == 0) 0.0 else {
      val delta = point - start
      math.max(0, math.min(1, (delta.x * line.x + delta.y * line.y) / length))
    }
    lengthSquared(point - (start + line * fraction))
  }

  def observeTick(level: Level, before: Snapshot, after: Snapshot,
                  cues: Vector[SoundCue]): Unit = {
    if (lastObserved.exists { case (number, previous) => number != level.number || after.tick < previous }) reset()
    if (lastObserved.contains((level.number, after.tick))) return
    lastObserved = Some((level.number, after.tick))
    tick = after.tick
    if (after.status != Status.Playing) {
      target = None
      reaction = None
      urgent = false
      closeCall = false
      safeTicks = 0
      idleTicks = 0
      coinCount = 0
      coinTick = None
      jumpCount = 0
      jumpTick = None
      sideCount = 0
      sideTick = None
      sideBubble = None
      sideDirection = 0
      return
    }
    reaction = reaction.filter(r => tick - r.start < r.duration)
    val center = after.player.center
    val movement = after.player.position - before.player.position
    val moving = lengthSquared(movement) > 0.01 * 0.01
    val travel = if (moving) movement else Vec2(if (after.player.facingLeft) -1 else 1, 0)
    val predicted = center + movement * 18
    val travelLength = math.sqrt(lengthSquared(travel))

    def hazardCandidate(h: HazardView, id: Int, radius: Double): Option[Candidate] = {
      val distance = lengthSquared(h.position - center)
      val predictedDistance = segmentDistanceSquared(h.position, center, predicted)
      Option.when(h.active && distance <= radius * radius && predictedDistance <= 96 * 96) {
        val immediate = predictedDistance <= 40 * 40 && distance <= 96 * 96
        Candidate(CharacterTarget(CharacterTargetKind.Hazard, id), h.position,
          if (immediate) 0 else 1, predictedDistance)
      }
    }
    def coinCandidate(c: CoinView, radius: Double): Option[Candidate] = {
      val delta = c.position - center
      val distance = lengthSquared(delta)
      Option.when(distance <= radius * radius &&
        delta.x * travel.x + delta.y * travel.y >= -24 * travelLength) {
        Candidate(CharacterTarget(CharacterTargetKind.Coin, c.id), c.position, 2, distance)
      }
    }
    val hazards = after.hazards.zipWithIndex.flatMap { case (h, id) => hazardCandidate(h, id, 160) }
    val candidates = hazards ++ after.coins.flatMap(coinCandidate(_, 160))
    val best = candidates.sortBy(c => (c.rank, c.distanceSquared, c.key.id)).headOption
    val retained = target.flatMap { previous =>
      previous.key.kind match {
        case CharacterTargetKind.Hazard => after.hazards.lift(previous.key.id).flatMap(h => hazardCandidate(h, previous.key.id, 200))
        case CharacterTargetKind.Coin => after.coins.find(_.id == previous.key.id).flatMap(coinCandidate(_, 200))
      }
    }
    val next = retained match {
      case None => best
      case Some(current) => best match {
        case Some(challenger) if challenger.key != current.key &&
            ((challenger.rank == 0 && current.rank != 0) ||
              (tick - targetSince >= 18 && (challenger.rank < current.rank ||
                (challenger.rank == current.rank &&
                  challenger.distanceSquared < current.distanceSquared * 0.64)))) => Some(challenger)
        case _ => retained
      }
    }
    if (next.map(_.key) != target.map(_.key)) targetSince = tick
    target = next
    urgent = hazards.exists(_.rank == 0)
    // A celebration interrupted by danger must not reappear when it passes.
    if (urgent) reaction = None

    val activeDistances = after.hazards.filter(_.active).map(h => lengthSquared(h.position - center))
    // Spawn/checkpoint placement beside a flame is not a survived approach.
    if (after.hazards.exists(h => h.active && lengthSquared(h.position - center) <= 36 * 36 &&
        lengthSquared(h.position - before.player.center) > 36 * 36)) closeCall = true
    if (closeCall && !urgent && activeDistances.forall(_ > 64 * 64)) safeTicks += 1
    else safeTicks = 0
    if (closeCall && safeTicks >= 12) {
      request(Relief, 48, 80)
      closeCall = false
      safeTicks = 0
    }

    if (after.player.airMode == AirMode.Grounded) {
      jumpCount = 0
      jumpTick = None
    }
    val coins = cues.count(_ == SoundCue.Coin)
    if (coins > 0) {
      coinCount = math.min(3, if (coinTick.exists(tick - _ <= 90)) coinCount + coins else coins)
      coinTick = Some(tick)
      if (coinCount >= 3) request(Happy, 54, 55)
      else if (coinCount == 2) request(Playful, 36, 45)
      else request(Happy, 36, 40)
    }
    val jumps = cues.count(_ == SoundCue.Jump)
    if (jumps > 0) {
      jumpCount = math.min(3, if (jumpTick.exists(tick - _ <= 120)) jumpCount + jumps else jumps)
      jumpTick = Some(tick)
      if (jumpCount >= 3) request(Playful, 27, 50)
      else if (jumpCount == 2) request(TongueOut, 30, 40)
      else request(Happy, 24, 40)
    }
    if (cues.contains(SoundCue.Bounce)) {
      // A consumed bubble can be absent from `after`. Repeated contact with a
      // surviving held bubble is one reaction, not sixty new events a second.
      val bubble = before.bubbles.filter(_.frozen).sortBy(b => (lengthSquared(b.position - center), b.id)).headOption
      val id = bubble.map(_.id)
      if (sideTick.isEmpty || id != sideBubble || sideTick.exists(tick - _ >= 18)) {
        val horizontal = bubble.map(b => center.x - b.position.x).getOrElse(travel.x)
        val direction = if (horizontal < 0) -1 else if (horizontal > 0) 1 else if (after.player.facingLeft) -1 else 1
        val alternating = sideTick.exists(tick - _ <= 90) && direction != sideDirection
        sideCount = if (alternating) math.min(3, sideCount + 1) else 1
        sideTick = Some(tick)
        sideBubble = id
        sideDirection = direction
        if (sideCount >= 3) request(Exasperated, 42, 70)
        else if (sideCount == 2) request(EyeRoll, 36, 60)
        else request(TongueOut, 24, 40)
      }
    }

    if (moving || after.player.airMode != AirMode.Grounded || coins > 0 || jumps > 0 ||
        cues.contains(SoundCue.Bounce) || urgent || activeDistances.exists(_ <= 96 * 96)) idleTicks = 0
    else idleTicks = math.min(300, idleTicks + 1)
  }

  private def request(expression: CharacterExpression, duration: Int, priority: Int): Unit = {
    if (!urgent && reaction.forall(_.priority <= priority)) reaction = Some(Reaction(expression, tick, duration, priority))
  }

  /** Public read-only result also supports deterministic reference renders. */
  def frame(state: Snapshot): CharacterFrame = {
    if (state.status == Status.Dead) return CharacterFrame(Exasperated, 4, None)
    if (state.status == Status.Won) return CharacterFrame(Happy, 4, None)
    val expression = if (urgent) Alarmed
      else reaction.map(_.expression).getOrElse {
        if (idleTicks >= 300) Whistle
        else if (idleTicks >= 180) Relaxed
        else if (target.nonEmpty) Pensive
        else Neutral
      }
    val age = reaction.map(r => tick - r.start).getOrElse(0L)
    val column = expression match {
      case EyeRoll => Vector(3, 0, 1, 2, 5, 4)(math.min(5, age / 6).toInt)
      case _ => target.map { candidate =>
        val delta = candidate.position - state.player.center
        def axis(value: Double): Int = if (value < -8) -1 else if (value > 8) 1 else 0
        val x = axis(delta.x) * (if (state.player.facingLeft) -1 else 1)
        val y = -axis(delta.y)
        (y + 1) * 3 + x + 1
      }.getOrElse(4)
    }
    CharacterFrame(expression, column, target.map(_.key))
  }
}
