# 🇪🇪 Gray Whale 🇪🇪

_Scala.js live at https://tlazenka.github.io/WhaleyWeb/_

## iOS/Mac

| Scheme | App | Destinations | | |
| --- | --- | --- |  --- |  --- |
| `Whaley` | SpriteKit Gray Whale | iOS Simulator, iPhone/iPad, Mac Catalyst | <img width="1206" height="2622" alt="whale2" src="https://github.com/user-attachments/assets/e7ef54a6-72e1-4a68-9d3f-6dd1da4a91dc" /> | <img width="1206" height="2622" alt="whale1" src="https://github.com/user-attachments/assets/54d286b6-f2a3-4226-b5cc-384d3b6bd4f6" /> |
| `StadiumApp` | RealityKit WhaleKart | iPhone/iPad/Mac Catalyst | <img width="1206" height="2622" alt="kart2" src="https://github.com/user-attachments/assets/3406f47f-f658-447f-bdc9-9feea5b155d6" /> | <img width="1206" height="2622" alt="kart1" src="https://github.com/user-attachments/assets/31dd6409-b29c-4c3f-ac54-ff22fb610b3c" /> |
| `WhaleyCLI` | whaley/whaley-relay | Mac | <img width="664" height="295" alt="cli1" src="https://github.com/user-attachments/assets/7e07cfc4-7f7b-4a1e-9bd7-99608b445c12" /> |
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
