# 🇪🇪 Gray Whale 🇪🇪

## iOS/Mac

| Scheme | App | Destinations | | |
| --- | --- | --- |  --- |  --- |
| `Whaley` | SpriteKit Gray Whale | iOS Simulator, iPhone/iPad, Mac Catalyst | <img width="1206" height="2622" alt="whale2" src="https://github.com/user-attachments/assets/b738f89e-cb83-41fc-9834-e21a7d2d0055" /> | <img width="1206" height="2622" alt="whale1" src="https://github.com/user-attachments/assets/2deae17c-f220-492b-8758-adae6b08a0ac" /> |
| `StadiumApp` | RealityKit WhaleKart | iPhone/iPad/Mac Catalyst | <img width="1206" height="2622" alt="kart2" src="https://github.com/user-attachments/assets/58aa1eaf-8e4e-4067-ae73-899e699b9395" /> | <img width="1206" height="2622" alt="kart1" src="https://github.com/user-attachments/assets/3c2c64ab-7e3e-4297-a449-7e2b30ea788f" /> |
| `WhaleyCLI` | whaley/whaley-relay | Mac | <img width="664" height="295" alt="cli1" src="https://github.com/user-attachments/assets/26df06bf-91b4-45a9-9d96-84bd1c38294a" /> |
| `Whaley2010` | cocos2d Gray Whale ca. 2010 | iPhone/iPad/Mac Catalyst | | |
| `WhaleyWebKit` | Scala.js/Canvas game bundled for `WKWebView` | iPhone/iPad/Mac Catalyst | | |

Minimum Xcode 27 and Swift 6.4. Compatible with [XcodeGen](https://github.com/yonaskolb/xcodegen). A typical flow:

```sh
brew install xcodegen && mint install yonaskolb/xcodegen
cd Apps && xcodegen generate && open Apps/Whaley.xcodeproj
```

### WhaleyWebKit

Install JDK 17+ e.g. through (SDKMan)[https://sdkman.io}:

```sh
sdk install java 17.0.21.0+9-tem
```

and Python 3.10+ if not installed, then run scheme WhaleyWebKit

## Browser

With JDK 17+ and Python 3.10+

```sh
python3 python/whaley.py web package --target pages
python3 -m http.server 8000 --bind 127.0.0.1 --directory Scala/target/pages
```

and navigate in your browser to http://localhost:800

With Docker and Docker Compose installed, run:

```sh
docker compose up --build db server
```

and browse to localhost:9000

## Desktop/Native

### macOS

Install Homebrew dependencies (omit openjdk@17 if already installed):

```sh
brew install openjdk@17 python llvm sdl2-compat sdl2_mixer glew pkgconf
```

then:

```sh
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
export PATH="$(brew --prefix llvm)/bin:$JAVA_HOME/bin:$PATH"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export WHALEY_NATIVE_LIB="$(brew --prefix)/lib"
python3 python/whaley.py sbt -- nativeApp/runNative
```

### Linux

For Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk python3 clang lld pkg-config libsdl2-dev libsdl2-mixer-dev libglew-dev libstb-dev
```

Then

```sh
python3 python/whaley.py sbt -- nativeApp/runNative
```

## CLI

Start the relay:

```sh
swift run whaley-relay
```

Then run the iOS `Whaley` app on simulator, and with a second terminal at repository root:

```sh
swift run whaley observe
```
