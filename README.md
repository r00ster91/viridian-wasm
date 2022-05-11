# viridian-wasm

Viridian from the game [VVVVVV](https://store.steampowered.com/app/70300/VVVVVV/) on the [WASM-4](https://wasm4.org) fantasy console!

It is written in raw WebAsssembly Text and compiles down to merely 842 bytes.

https://user-images.githubusercontent.com/35064754/167928559-a6d92f58-b354-4997-8759-590328f37f4a.mp4

## Building

To build, you need `wat2wasm` and optionally `wasm-opt`.

Build the game by running:

```shell
make build
```

Then run it with:

```shell
w4 run viridian.wasm
```

For more info about setting up WASM-4, see the [quickstart guide](https://wasm4.org/docs/getting-started/setup/?code-lang=wat).
