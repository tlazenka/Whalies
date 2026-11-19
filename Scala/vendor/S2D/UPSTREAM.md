# S2D source provenance

- Upstream: https://github.com/FinochioM/S2D
- Revision: `794bed1482f92bae8b3132e3b73f2846a493d50c`
- Upstream version: `0.4.0`; Scala version: `3.8.3`.
- License: zlib, preserved verbatim in `LICENSE`.
- The complete upstream `src/` tree is checked in here. This is an editable
  source dependency, with no Git submodule or published S2D binary dependency.
- `upstream-build.sbt.txt` records the original build. WhaleKart's parent
  `build.sbt` supplies the missing sbt plugin configuration and platform flags.
- `UPSTREAM.sha256` records original hashes before the changes listed below.
  It is a provenance record; modified files are expected to differ.

## WhaleKart changes to this source distribution

| File | Change |
| --- | --- |
| `src/main/scala/s2d/core/Window.scala` | Clear old window state, update logical dimensions and drawable viewport, report focus/minimization, consume the resize flag correctly. |
| `src/main/scala/s2d/core/Drawing.scala` | Handle SDL window resize/focus events and sample the mouse after polling events. |
| `src/main/scala/s2d/core/Input.scala` | Release stale held inputs when focus is lost. Treat `setExitKey(Key.Unknown)` as disabling automatic exit so the host can route Escape between scenes; unmapped SDL keys must not close the window. |
| `src/main/scala/s2d/textures/Textures.scala`, `src/main/scala/s2d/textures/TextureRenderer.scala` | Add an optional `flipX` argument to `drawPro` / `renderTexturePro` that reverses texture U coordinates while preserving nonnegative source and destination rectangle dimensions. |
| `src/main/resources/scala-native/stb_impl.c` | Accept both Debian's `stb/` header layout and vcpkg's flat include layout; enable `STBI_WINDOWS_UTF8` so Unicode asset paths work on Windows. |

The parent build excludes `s2d/audio`, `s2d/backend/miniaudio`, and
`miniaudio_impl.c` from compilation. Their original sources remain available.
The upstream audio bindings allocate opaque C structures using hardcoded sizes
and declare Unix-only libraries. Enabling them requires a portable C allocation
boundary and platform-specific linking. Whaley now uses its own SDL2_mixer
bridge in `../../native/src/main/resources/scala-native/whaley_audio.c`; SDL owns
the decoder objects, and Scala owns only a handle with explicit cleanup.

SDL2, SDL2_mixer (for the Whaley host), GLEW, OpenGL, and stb are separate native prerequisites. On Linux the build
uses system development packages. On macOS it links Apple's OpenGL framework,
uses Homebrew's SDL2-compatible and GLEW libraries, and reads the downloaded stb
headers from `WHALEY_NATIVE_INCLUDE`; the setup commands pin stb to the same
revision as the Windows manifest. On Windows `../../vcpkg.json` pins the package
registry baseline. No platform depends on an assumed `C:\libs` directory.

When updating S2D, select an explicit upstream revision, compare these changes,
and run both native compilation and rendering checks. Do not replace this tree
with an unrecorded download during the build.
