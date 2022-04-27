build:
	wat2wasm -o viridian.wasm main.wat
	wasm-opt -Oz -o viridian.wasm viridian.wasm
