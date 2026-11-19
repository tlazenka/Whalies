package whaley.core

/** The durable state written by the original game when a coin is collected.
  * Player position comes from the coin's stable TMX ordinal. A checkpoint does
  * not preserve a held pointer, movement tween, or player-created bubble.
  */
final case class GameCheckpoint(
    levelNumber: Int,
    mode: BubbleMode,
    lastCoinId: Int,
    collectedCoinIds: Vector[Int],
    elapsedTicks: Long,
    bubblesUsed: Int,
    version: Int = GameCheckpoint.CurrentVersion
) {
  def validFor(level: Level): Boolean = {
    val ids = collectedCoinIds
    version == GameCheckpoint.CurrentVersion && levelNumber == level.number &&
      mode != null && elapsedTicks >= 0 && elapsedTicks <= GameCheckpoint.MaxElapsedTicks &&
      bubblesUsed >= 0 && ids.nonEmpty && ids.length <= level.coins.length &&
      ids.distinct.length == ids.length && ids.contains(lastCoinId) &&
      ids.forall { id =>
        id >= 0 && id < level.coins.length && {
          val p = level.coins(id)
          // These coordinates are never accepted from the saved string.
          p.finite && p.x >= 16 && p.y >= 16 &&
            p.x + 16 <= level.worldWidth && p.y + 16 <= level.worldHeight
        }
      }
  }
}

object GameCheckpoint {
  val CurrentVersion = 1
  // Results render time as a signed integer number of seconds. Keep loaded
  // counters representable and saturate live counters at the same boundary.
  val MaxElapsedTicks: Long = Int.MaxValue.toLong * 60L
}

/** A small versioned, platform-independent storage format. Only bounded
  * integers and a closed mode name are serialized, so there is no JSON parser
  * or platform-specific persistence dependency in the simulation.
  */
object GameCheckpointCodec {
  private val Prefix = "whaley-checkpoint"
  private val MaxRecordChars = 65536

  def encode(checkpoint: GameCheckpoint): String =
    Vector(Prefix, checkpoint.version.toString, checkpoint.levelNumber.toString,
      checkpoint.mode.toString, checkpoint.lastCoinId.toString,
      checkpoint.elapsedTicks.toString, checkpoint.bubblesUsed.toString,
      checkpoint.collectedCoinIds.sorted.mkString(",")).mkString("|")

  /** Unknown versions/levels, malformed counters and invalid coin references
    * fail closed. Callers can discard the stored record and start normally.
    */
  def decode(text: String, levels: Seq[Level]): Option[GameCheckpoint] = {
    if (text == null || text.length > MaxRecordChars) return None
    val parts = text.split("\\|", -1)
    if (parts.length != 8 || parts(0) != Prefix) return None
    for {
      version <- decimalInt(parts(1))
      levelNumber <- decimalInt(parts(2))
      mode <- BubbleMode.values.find(_.toString == parts(3))
      coin <- decimalInt(parts(4))
      ticks <- decimalLong(parts(5))
      used <- decimalInt(parts(6))
      level <- levels.find(_.number == levelNumber)
      ids <- coinIds(parts(7), level.coins.length)
      checkpoint = GameCheckpoint(levelNumber, mode, coin, ids.sorted, ticks, used, version)
      if checkpoint.validFor(level)
    } yield checkpoint
  }

  private def decimalInt(text: String): Option[Int] =
    if (digits(text)) text.toIntOption else None

  private def decimalLong(text: String): Option[Long] =
    if (digits(text)) text.toLongOption else None

  private def digits(text: String): Boolean =
    text.nonEmpty && text.length <= 19 && text.forall(c => c >= '0' && c <= '9')

  private def coinIds(text: String, maximum: Int): Option[Vector[Int]] = {
    val parts = text.split(",", -1)
    if (parts.length > maximum) None
    else {
      val parsed = parts.toVector.map(decimalInt)
      if (parsed.forall(_.nonEmpty)) Some(parsed.flatten) else None
    }
  }
}
