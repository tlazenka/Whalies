"""Launch the pinned sbt distribution with its verified checksum."""
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import urllib.request

VERSION = "1.12.4"
SHA256 = "45eb459f46b234ccdfe4a16c6863dc5a793ac5f71acc2412a2b2b5b176461104"


def launch(root: Path, arguments: list[str]) -> int:
    scala = root / "Scala"
    jar = scala / "target" / "tools" / f"sbt-launch-{VERSION}.jar"
    jar.parent.mkdir(parents=True, exist_ok=True)
    if not jar.is_file():
        url = f"https://repo.maven.apache.org/maven2/org/scala-sbt/sbt-launch/{VERSION}/sbt-launch-{VERSION}.jar"
        with urllib.request.urlopen(url, timeout=60) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != SHA256:
            raise RuntimeError("Downloaded sbt launcher checksum does not match")
        jar.write_bytes(content)
    if hashlib.sha256(jar.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError("Cached sbt launcher checksum does not match")
    java = str(Path(os.environ["JAVA_HOME"]) / "bin" / "java") if "JAVA_HOME" in os.environ else "java"
    options = shlex.split(os.environ.get("WHALEY_JAVA_OPTS", "-Xmx2G -XX:ActiveProcessorCount=4"))
    return subprocess.call([
        java, *options, "-Dsbt.supershell=false", "-Dsbt.server.autostart=false",
        "-jar", str(jar), *arguments,
    ], cwd=scala)


def run(args, root: Path) -> int:
    arguments = args.arguments
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    return launch(root, arguments)
