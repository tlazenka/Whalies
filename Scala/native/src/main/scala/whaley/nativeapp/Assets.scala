package whaley.nativeapp

import java.io.File
import scala.scalanative.unsafe.*
import s2d.backend.sdl2.SDL.SDL_free
import whaley.core.{MenuMusic, PresentationData, SoundCue}

@extern
@link("SDL2")
private object ExecutableDirectory {
  def SDL_GetBasePath(): CString = extern
}

private object Assets {
  val required: Vector[String] = PresentationData.requiredImages
  private val requiredFiles: Vector[String] = required ++ SoundCue.values.toVector.map(_.file) ++ MenuMusic.values.toVector.map(_.file)

  def find(explicit: Option[File]): File = {
    val configured = explicit.orElse(sys.env.get("WHALEY_ASSET_ROOT").filter(_.nonEmpty).map(new File(_)))
    val candidates = configured.toVector match {
      case files if files.nonEmpty => files
      case _ => Vector(new File("target/assets"), new File("Scala/target/assets")) ++ executableAssets.toVector
    }
    candidates.find(root => requiredFiles.forall(name => new File(root, name).isFile)).getOrElse {
      throw new IllegalArgumentException(
        "Whaley assets are missing. Generate them with the Scala build, or use --assets DIRECTORY / WHALEY_ASSET_ROOT. " +
          s"Expected ${requiredFiles.mkString(", ")}. Checked: ${candidates.map(_.getAbsolutePath).mkString(", ")}")
    }.getCanonicalFile
  }

  private def executableAssets: Option[File] = {
    val path = ExecutableDirectory.SDL_GetBasePath()
    if (path == null) None
    else try Some(new File(fromCString(path), "assets"))
    finally SDL_free(path.asInstanceOf[Ptr[Byte]])
  }
}
