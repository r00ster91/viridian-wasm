# viridian-wasm

Viridian from the game [VVVVVV](https://store.steampowered.com/app/70300/VVVVVV/) on the [WASM-4](https://wasm4.org) fantasy console!

It is written in raw WebAsssembly Text and compiles down to merely 842 bytes.

![image](https://user-images.githubusercontent.com/35064754/165492461-137c318b-95a8-4db4-acd6-073d19b81005.png)

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
