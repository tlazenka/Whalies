package whaley.core

/** Durable choices and coin checkpoints; live movement remains in Game. */
final case class PlayerProgress(
    levelsAchieved: Int = 1,
    rewardVisible: Boolean = true,
    invincible: Boolean = false,
    checkpoints: Map[Int, GameCheckpoint] = Map.empty
)

object PlayerProgressCodec {
  private val Prefix = "whaley-progress|1"
  private val MaximumSize = 400000

  def encode(progress: PlayerProgress): String = {
    val settings = s"${progress.levelsAchieved}|${progress.rewardVisible}|${progress.invincible}"
    (Vector(Prefix, settings) ++ progress.checkpoints.toVector.sortBy(_._1)
      .map { case (_, checkpoint) => GameCheckpointCodec.encode(checkpoint) }).mkString("\n")
  }

  def decode(text: String, levels: Seq[Level]): Option[PlayerProgress] = {
    if (text == null || text.length > MaximumSize) return None
    val lines = text.split("\n", -1).toVector
    if (lines.length < 2 || lines.length > levels.size + 2 || lines.head != Prefix) return None
    val settings = lines(1).split("\\|", -1)
    if (settings.length != 3) return None
    val records = lines.drop(2).map(GameCheckpointCodec.decode(_, levels))
    for {
      achieved <- settings(0).toIntOption.filter(n => n >= 1 && n <= levels.size + 1)
      reward <- boolean(settings(1))
      invincible <- boolean(settings(2))
      if records.forall(_.nonEmpty)
      checkpoints = records.flatten
      if checkpoints.map(_.levelNumber).distinct.size == checkpoints.size
      // A resumed practice level must remain reachable from the gallery.
      unlocked = math.max(achieved, checkpoints.map(_.levelNumber).maxOption.getOrElse(1))
    } yield PlayerProgress(unlocked, reward, invincible,
      checkpoints.map(cp => cp.levelNumber -> cp).toMap)
  }

  private def boolean(value: String): Option[Boolean] = value match {
    case "true" => Some(true)
    case "false" => Some(false)
    case _ => None
  }
}
