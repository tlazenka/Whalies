package whaley.nativeapp

import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, StandardCopyOption}
import whaley.core.*

/** Coin saves replace one file beside a temporary file in the user's data directory. */
private final class ProgressStorage(enabled: Boolean = true) {
  private lazy val file: File = {
    val home = new File(sys.props.getOrElse("user.home", "."))
    val os = sys.props.getOrElse("os.name", "")
    val directory = sys.env.get("WHALEY_SAVE_DIR").filter(_.nonEmpty).map(new File(_)).getOrElse {
      if (os.startsWith("Windows"))
        new File(sys.env.getOrElse("LOCALAPPDATA", new File(home, "AppData/Local").getPath), "Whaley")
      else if (os.startsWith("Mac")) new File(home, "Library/Application Support/Whaley")
      else new File(sys.env.getOrElse("XDG_DATA_HOME", new File(home, ".local/share").getPath), "whaley")
    }
    new File(directory, "progress-v1.txt")
  }

  def load(): PlayerProgress = {
    if (!enabled) return PlayerProgress()
    try {
      if (!file.isFile) PlayerProgress()
      else {
        require(file.length() <= 400000, "Saved progress is too large")
        val decoded = PlayerProgressCodec.decode(new String(Files.readAllBytes(file.toPath), StandardCharsets.UTF_8), LevelData.all)
        if (decoded.isEmpty) System.err.println("Whaley ignored an invalid or unsupported saved progress record.")
        decoded.getOrElse(PlayerProgress())
      }
    } catch {
      case error: Throwable =>
        System.err.println(s"Whaley could not read saved progress: ${error.getMessage}")
        PlayerProgress()
    }
  }

  def save(progress: PlayerProgress): Unit = {
    if (!enabled) return
    try {
      Files.createDirectories(file.getParentFile.toPath)
      val temporary = Files.createTempFile(file.getParentFile.toPath, "progress-v1-", ".tmp")
      try {
        Files.write(temporary, PlayerProgressCodec.encode(progress).getBytes(StandardCharsets.UTF_8))
        // Scala Native 0.5.12 provides same-directory rename/MoveFileExW;
        // it does not provide AtomicMoveNotSupportedException or implement
        // ATOMIC_MOVE. Replace only after the complete temporary is closed.
        Files.move(temporary, file.toPath, StandardCopyOption.REPLACE_EXISTING)
      } finally Files.deleteIfExists(temporary)
    } catch {
      case error: Throwable => System.err.println(s"Whaley could not save progress: ${error.getMessage}")
    }
  }
}
