import org.scalajs.linker.interface.ModuleKind
import scala.sys.process._
import sbt.complete.DefaultParsers.spaceDelimited

ThisBuild / scalaVersion := "3.8.3"
ThisBuild / organization := "com.whalekart"
ThisBuild / version := "0.1.0-SNAPSHOT"
ThisBuild / publish / skip := true

lazy val portBase = file(".").getCanonicalFile
lazy val python = sys.env.getOrElse("PYTHON", if (sys.props("os.name").startsWith("Windows")) "python" else "python3")
lazy val pythonCLI = (portBase.getParentFile / "python" / "whaley.py").getAbsolutePath
lazy val generateGameData = taskKey[Seq[File]]("Generate shared level/atlas data from the existing Whaley resources")
lazy val stageAssets = taskKey[File]("Stage the existing Whaley art without committing duplicate assets")
lazy val stage = taskKey[File]("Build a self-contained web directory")
lazy val stageNative = taskKey[File]("Link the native app and stage assets/licenses beside it")
lazy val runNative = inputKey[Unit]("Build, stage, and launch the native game")

// Homebrew places SDL2 headers in include/SDL2; Clang does not search that
// directory by default. Discover the platform flags at Native link time.
def nativeToolFlags(args: String*): Seq[String] = {
  val output = new StringBuilder
  val status =
    try Process(args, portBase).!(ProcessLogger(line => {
      output.append(line).append(' ')
      ()
    }, _ => ()))
    catch { case _: java.io.IOException => -1 }
  if (status != 0) Seq.empty
  else output.toString.trim.split("\\s+").filter(_.nonEmpty).toSeq
}


lazy val root: Project = project.in(file("."))
  .aggregate(coreJVM, coreJS, coreNative, web, nativeApp, server)
  .settings(
    name := "whaley-scala",
    generateGameData := {
      val output = portBase / "target" / "generated"
      val exit = Process(Seq(python, pythonCLI, "assets", "--source-output", output.getAbsolutePath), portBase).!
      if (exit != 0) sys.error("Whaley TMX/atlas generation failed")
      (output ** "*.scala").get
    },
    stageAssets := {
      val output = portBase / "target" / "assets"
      val exit = Process(Seq(python, pythonCLI, "assets", "--asset-output", output.getAbsolutePath), portBase).!
      if (exit != 0) sys.error("Whaley asset staging failed")
      output
    },
    Compile / sources := Nil
  )

lazy val coreSettings = Seq(
  Compile / unmanagedSourceDirectories := Seq(portBase / "shared" / "src" / "main" / "scala"),
  Test / unmanagedSourceDirectories := Seq(portBase / "shared" / "src" / "test" / "scala"),
  Compile / sourceGenerators += Def.task { (LocalRootProject / generateGameData).value }.taskValue,
  libraryDependencies += "org.scalameta" %%% "munit" % "1.2.1" % Test
)

lazy val coreJVM = project.in(file("core/jvm"))
  .settings(coreSettings)
  .settings(name := "whaley-core-jvm")

lazy val coreJS = project.in(file("core/js"))
  .enablePlugins(ScalaJSPlugin)
  .settings(coreSettings)
  .settings(name := "whaley-core-js")

lazy val coreNative = project.in(file("core/native"))
  .enablePlugins(ScalaNativePlugin)
  .settings(coreSettings)
  .settings(name := "whaley-core-native")

// All S2D sources are retained. Upstream miniaudio bindings assume opaque struct
// sizes and Unix-only linker flags. Whaley uses its own C-owned SDL_mixer bridge.
lazy val s2d = project.in(file("vendor/S2D"))
  .enablePlugins(ScalaNativePlugin)
  .settings(
    name := "whaley-vendored-s2d",
    Compile / unmanagedSources / excludeFilter := new SimpleFileFilter(f =>
      f.getAbsolutePath.replace('\\', '/').contains("/s2d/audio/") ||
      f.getAbsolutePath.replace('\\', '/').contains("/s2d/backend/miniaudio/")
    ),
    Compile / unmanagedResources / excludeFilter := "miniaudio_impl.c"
  )

lazy val nativeApp = project.in(file("native"))
  .enablePlugins(ScalaNativePlugin)
  .dependsOn(coreNative, s2d)
  .settings(
    name := "whaley-native",
    Compile / mainClass := Some("whaley.nativeapp.Main"),
    nativeConfig ~= { config =>
      val windows = sys.props("os.name").startsWith("Windows")
      val macos = sys.props("os.name").startsWith("Mac")
      // nativeConfig is a task: prepare headers before native compilation, not at build load.
      // One directory per line preserves paths containing spaces.
      val includes = Process(Seq(python, pythonCLI, "native-deps", "--print-includes"), portBase).!!
        .linesIterator.filter(_.nonEmpty).map("-I" + _).toVector
      val libraryPath = sys.env.get("WHALEY_NATIVE_LIB").toSeq.map("-L" + _)
      // Use the installed SDL2 and mixer metadata on macOS. Homebrew keg
      // prefixes also cover libraries that are not symlinked into its root.
      val macHeaders = if (macos) nativeToolFlags("sdl2-config", "--cflags") ++
        nativeToolFlags("pkg-config", "--cflags", "SDL2_mixer") else Seq.empty
      val macLinks = if (macos) nativeToolFlags("sdl2-config", "--libs") ++
        nativeToolFlags("pkg-config", "--libs", "SDL2_mixer") else Seq.empty
      val brewPrefixes = if (macos) Seq("sdl2-compat", "sdl2_mixer")
        .flatMap(name => nativeToolFlags("brew", "--prefix", name)) else Seq.empty
      val brewHeaders = brewPrefixes.flatMap(prefix =>
        Seq("-I" + prefix + "/include", "-I" + prefix + "/include/SDL2"))
      val brewLinks = brewPrefixes.map(prefix => "-L" + prefix + "/lib")
      val libraries =
        if (windows) Seq("-lSDL2_mixer", "-lSDL2", "-lglew32", "-lopengl32")
        else if (macos) Seq("-lSDL2_mixer", "-lSDL2", "-lGLEW", "-framework", "OpenGL")
        else Seq("-lSDL2_mixer", "-lSDL2", "-lGLEW", "-lGL")
      config.withCompileOptions(config.compileOptions ++ macHeaders ++ brewHeaders ++ includes)
        .withLinkingOptions(config.linkingOptions ++ macLinks ++ brewLinks ++ libraryPath ++ libraries)
    },
    stageNative := {
      val binary = (Compile / nativeLink).value
      val assets = (LocalRootProject / stageAssets).value
      val output = portBase / "target" / "native"
      IO.delete(output)
      IO.createDirectory(output)
      val executable = output / (if (sys.props("os.name").startsWith("Windows")) "whaley.exe" else "whaley")
      IO.copyFile(binary, executable)
      executable.setExecutable(true)
      IO.copyDirectory(assets, output / "assets")
      IO.copyFile(portBase.getParentFile / "LICENSE", output / "licenses" / "WhaleKart.txt")
      IO.copyFile(portBase / "vendor" / "S2D" / "LICENSE", output / "licenses" / "S2D.txt")
      val stbLicense = portBase / "target" / "stb" / "LICENSE"
      if (stbLicense.isFile) IO.copyFile(stbLicense, output / "licenses" / "stb.txt")
      sys.env.get("WHALEY_NATIVE_BIN").foreach { dir =>
        (file(dir) * "*.dll").get.foreach(dll => IO.copyFile(dll, output / dll.getName))
      }
      sys.env.get("WHALEY_NATIVE_SHARE").foreach { dir =>
        // Include transitive decoder notices as well as directly linked DLLs.
        (file(dir) * "*" / "copyright").get.foreach { notice =>
          IO.copyFile(notice, output / "licenses" / (notice.getParentFile.getName + ".txt"))
        }
      }
      streams.value.log.info("Native build: " + executable)
      output
    },
    runNative := {
      val arguments = spaceDelimited("<argument>").parsed
      val directory = stageNative.value
      val executable = directory / (if (sys.props("os.name").startsWith("Windows")) "whaley.exe" else "whaley")
      val exit = Process(Seq(executable.getAbsolutePath) ++ arguments, portBase).!
      if (exit != 0) sys.error("Whaley exited with status " + exit)
    }
  )

lazy val web = project.in(file("web"))
  .enablePlugins(ScalaJSPlugin)
  .dependsOn(coreJS)
  .settings(
    name := "whaley-web",
    libraryDependencies += "org.scala-js" %%% "scalajs-dom" % "2.8.1",
    scalaJSUseMainModuleInitializer := true,
    Compile / mainClass := Some("whaley.web.Main"),
    scalaJSLinkerConfig ~= (_.withModuleKind(ModuleKind.ESModule)),
    stage := {
      (Compile / fastLinkJS).value
      val assets = (LocalRootProject / stageAssets).value
      val output = portBase / "target" / "web"
      IO.delete(output)
      IO.copyDirectory(portBase / "web" / "public", output)
      IO.copyDirectory((Compile / fastLinkJS / scalaJSLinkerOutputDirectory).value, output)
      IO.copyDirectory(assets, output / "assets")
      streams.value.log.info("Web build: " + output)
      output
    }
  )

// The HTTP application is JVM-only. GameInfo.scala is the one shared source of
// truth, compiled into Play's supported Scala 3.3 LTS version and the 3.8 game.
lazy val server = project.in(file("server"))
  .enablePlugins(PlayScala)
  .settings(
    name := "whaley-play",
    scalaVersion := "3.3.6",
    Compile / unmanagedSources += portBase / "shared" / "src" / "main" / "scala" / "whaley" / "core" / "GameInfo.scala",
    // Play serves the linked Scala.js module, CSS and original game art from
    // the same origin as Twirl, without a separate HTTP or Python server.
    Compile / resourceGenerators += Def.task {
      val staged = (web / stage).value
      val output = (Compile / resourceManaged).value / "public" / "assets"
      IO.delete(output)
      IO.createDirectory(output)
      IO.copyFile(staged / "main.js", output / "main.js")
      IO.copyFile(staged / "styles.css", output / "styles.css")
      IO.copyDirectory(staged / "assets", output)
      (output ** "*").get.filter(_.isFile)
    }.taskValue,
    libraryDependencies ++= Seq(
      guice, jdbc, evolutions,
      "org.postgresql" % "postgresql" % "42.7.8",
      "org.typelevel" %% "cats-effect" % "3.6.3",
      "org.tpolecat" %% "skunk-core" % "0.6.5"
    )
  )

addCommandAlias("check", ";coreJVM/test;coreJS/test;web/stage;nativeApp/compile;server/compile")
