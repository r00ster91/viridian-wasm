;; References:
;; * https://wasm4.org/docs/
;; * https://github.com/sunfishcode/wasm-reference-manual/blob/master/WebAssembly.md
;; * https://pengowray.github.io/wasm-ops/

(module
  ;;
  ;; wasm4 imports
  ;;

  (import "env" "memory" (memory 1)) (; 64 KiB of memory
                                        because size of 1 page = 64 KiB ;)
  (import "env" "blit" (func $blit (param i32 i32 i32 i32 i32 i32)))
  (import "env" "rect" (func $rect (param i32 i32 i32 i32)))
  (import "env" "tracef" (func $tracef (param i32 i32)))
  (import "env" "text" (func $text (param i32 i32 i32)))
  (import "env" "tone" (func $tone (param i32 i32 i32 i32)))
  (global $DRAW_COLORS i32 (i32.const 0x14))
  (global $GAMEPAD1 i32 (i32.const 0x16))
  (global $FRAMEBUFFER i32 (i32.const 0xa0))
  (global $BUTTON_1 i32 (i32.const 1))
  (global $BUTTON_2 i32 (i32.const 2))
  (global $BUTTON_LEFT i32 (i32.const 16))
  (global $BUTTON_RIGHT i32 (i32.const 32))
  (global $BLIT_1BPP i32 (i32.const 0))
  (global $BLIT_FLIP_X i32 (i32.const 2))
  (global $BLIT_FLIP_Y i32 (i32.const 4))
  (global $PALETTE0 i32 (i32.const 0x04))
  (global $PALETTE1 i32 (i32.const 0x08))
  (global $PALETTE2 i32 (i32.const 0x0c))
  (global $PALETTE3 i32 (i32.const 0x10))
  (global $TONE_PULSE1 i32 (i32.const 0))
  (global $TONE_MODE1 i32 (i32.const 0))

  ;;
  ;; The game
  ;;

  (; 0x19A0 is the start address in memory
     where we can safely put any data we want ;)

  ;; Here follows some constant data
  (data (i32.const 0x19a0) "VVVVVV\00") ;; We need to zero-terminate to mark the string's end
  (global $vvvvvv i32 (i32.const 0x19a0))

  (; The following is a bitmap sprite of captain Viridian,
     generated using `w4 png2src --wat Viridian.png` ;)
  (data
    (i32.const 0x19f4)
    "\7f\80\ff\c0\99\c0\99\c0\ff\c0\ff\c0\81\c0\c3\c0\7f\80\1e\00\7f\80\ff\c0\ff\c0\ff\c0\de\c0\de\c0\3f\00\33\00\73\80\73\80\73\80"
  )
  (global $viridian-sprite i32 (i32.const 0x19f4))
  (global $viridian-sprite-width i32 (i32.const 16))
  (global $viridian-sprite-height i32 (i32.const 21))

  (; The following is a bitmap sprite of captain Viridian walking,
     generated using `w4 png2src --wat "Walking Viridian.png"` ;)
  (data
    (i32.const 0x1a41)
    "\3f\c0\7f\e0\4c\e0\4c\e0\7f\e0\7f\e0\40\e0\61\e0\3f\c0\0f\00\3f\c0\7f\e0\ff\f0\cf\30\cf\30\1f\80\19\80\39\c0\70\e0\70\e0"
  )
  (global $viridian-walking-sprite i32 (i32.const 0x1a41))
  (global $viridian-walking-sprite-width i32 (i32.const 16))
  (global $viridian-walking-sprite-height i32 (i32.const 20))

  ;; See `tracef` below
  (data
    (i32.const 0x1a8a)
    "X: %f\00"
  )
  (data
    (i32.const 0x1a90)
    "Y: %d\00"
  )

  ;; Viridian's state
  (global $viridian-x (mut f32) (f32.const 0.0)) ;; Needs to be a floating-point number because the horizontal speed is a float too
  (global $viridian-y (mut i32) (i32.const 160))
  (global $viridian-direction (mut i32) (i32.const 1)) (; 0 = left
                                                          1 = right ;)
  (global $viridian-flipped (mut i32) (i32.const 0)) ;; Viridian is initially not flipped
  (global $viridian-midair (mut i32) (i32.const 0)) ;; Is Viridian in midair?
  (global $viridian-horizontal-speed f32 (f32.const 1.75)) ;; For this value 1 is too slow and 2 is too fast, so let's use a floating-point number!
  (global $viridian-vertical-speed i32 (i32.const 3))

  ;; This is used to animate Viridian's movement
  (global $counter (mut i32) (i32.const 0))

  (global $gamepad-previous (mut i32) (i32.const 0))

  (func (export "start")
    (global.set $viridian-y (i32.sub (global.get $viridian-y) (global.get $viridian-sprite-height)))

    (i32.store (global.get $PALETTE0) (i32.const 0x000000)) ;; Background
    (i32.store (global.get $PALETTE1) (i32.const 0x90C2D0)) ;; Foreground
    (i32.store (global.get $PALETTE2) (i32.const 0x123321)) ;; Warp hole
    (i32.store (global.get $PALETTE3) (i32.const 0x54E4FF)) ;; VVVVVV text
  )

  (func (export "update")
    (call $update)
    (call $draw)
  )

  ;;
  ;; Updating
  ;;
  ;; These functions are responsible for updating game state.
  ;;

  (func $update
    (call $handle-input)
    (call $update-viridian)
  )

  (func $handle-input
    (local $gamepad i32)
    (local $gamepad-this-frame i32)
    (local $flip-tone-frequency i32)

    (local.set $gamepad (i32.load8_u (global.get $GAMEPAD1)))

    (local.set $gamepad-this-frame
      (i32.and
        (local.get $gamepad)
        ;; This filters out the old input
        (i32.xor
          (local.get $gamepad)
          (global.get $gamepad-previous)
        )
      )
    )

    (global.set $gamepad-previous (local.get $gamepad))

    (if
      (i32.and
        (i32.or
          ;; This will accept either Z, X, or space bar to jump
          (i32.and (local.get $gamepad-this-frame) (global.get $BUTTON_1))
          (i32.and (local.get $gamepad-this-frame) (global.get $BUTTON_2))
        )
        ;; Make sure we can't flip while we're already in midair
        (i32.xor (global.get $viridian-midair) (i32.const 1))
      )
      (then
        ;; Flip!

        (; Make the flip tone sound different depending on whether
           Viridian is flipped or not ;)
        (global.get $viridian-flipped)
        if
          (local.set $flip-tone-frequency (i32.const 200))
        else
          (local.set $flip-tone-frequency (i32.const 250))
        end

        (global.set $viridian-flipped ;; Flip the flag
          (i32.xor (global.get $viridian-flipped) (i32.const 1)))

        ;; Give some visual feedback
        (call $tone (local.get $flip-tone-frequency) (i32.const 5) (i32.const 25) (i32.or (global.get $TONE_PULSE1) (global.get $TONE_MODE1)))
        (call $clear)
        (return)
      )
    )

    (i32.and (local.get $gamepad) (global.get $BUTTON_LEFT))
    if
      (global.set $viridian-x (f32.sub (global.get $viridian-x) (global.get $viridian-horizontal-speed)))
      (global.set $viridian-direction (i32.const 0))
      (global.set $counter (i32.add (global.get $counter) (i32.const 1)))
    else
      (i32.and (local.get $gamepad) (global.get $BUTTON_RIGHT))
      if
        (global.set $viridian-x (f32.add (global.get $viridian-x) (global.get $viridian-horizontal-speed)))
        (global.set $viridian-direction (i32.const 1))
        (global.set $counter (i32.add (global.get $counter) (i32.const 1)))
      else
        ;; Neither button is pressed
        (global.set $counter (i32.const 0))
      end
    end
  )

  (func $update-viridian
    ;; This is the Y-axis of Viridian on the ground
    (local $ground-y i32)

    (local.set $ground-y (i32.const 160))
    (local.set $ground-y (i32.sub (local.get $ground-y) (global.get $viridian-sprite-height)))

    ;; Initially assume Viridian is not in midair
    (global.set $viridian-midair (i32.const 0))

    (global.get $viridian-flipped)
    if
      (if ;; Is Viridian below the ceiling?
        (i32.gt_u (global.get $viridian-y) (i32.const 0))
        (then
          (global.set $viridian-y (i32.sub (global.get $viridian-y) (global.get $viridian-vertical-speed)))
          (global.set $viridian-midair (i32.const 1))
        )
      )
    else
      (if ;; Is Viridian above the ground?
        (i32.lt_u (global.get $viridian-y) (local.get $ground-y))
        (then
          (global.set $viridian-y (i32.add (global.get $viridian-y) (global.get $viridian-vertical-speed)))
          (global.set $viridian-midair (i32.const 1))
        )
      )
    end

    ;; Make sure Viridian doesn't get out of bounds
    (if (i32.lt_s (global.get $viridian-y) (i32.const 0))
      (then
        (global.set $viridian-y (i32.const 0))
      )
    )
    (if (i32.gt_s (global.get $viridian-y) (local.get $ground-y))
      (then
        (global.set $viridian-y (local.get $ground-y))
      )
    )

    (; Here's some `printf`-like debugging. This will print the position of Viridian in decimal.
       First we store the X-axis and Y-axis of Viridian in memory at some address (`offset`)
       without any dynamic offset (`$base`). ;)

    ;; (f32.store offset=0x2500 (i32.const 0) (global.get $viridian-x))
    ;; (i32.store offset=0x2504 (i32.const 0) (global.get $viridian-y)) ;; An f32 takes 4 bytes, hence the offset

    (; Then we simply pass the memory addresses (pointers) of the
       two values to the function.
       The first pointer's string was defined above in the file. ;)

    ;; (call $tracef (i32.const 0x1a8a) (i32.const 0x2500))
    ;; (call $tracef (i32.const 0x1a90) (i32.const 0x2504))
  )

  ;;
  ;; Drawing
  ;;
  ;; These functions are responsible for presenting state to the screen.
  ;;

  (func $draw
    ;; This is initially zero
    (local $vertical-flip-flag i32)

    (if (global.get $viridian-flipped)
      (then
        (local.set $vertical-flip-flag (global.get $BLIT_FLIP_Y))
      )
    )

    (i32.store8 (global.get $DRAW_COLORS) (i32.const 0x31))
    (call $draw-warp-hole)

    (i32.store8 (global.get $DRAW_COLORS) (i32.const 0x14))
    (call $text (global.get $vvvvvv)
      (i32.const 56) ;; 160 / 2  - ((7 + 1) * 6) / 2
      (i32.const 77) ;; 160 / 2  - 7 / 2
    )

    (i32.store8 (global.get $DRAW_COLORS) (i32.const 0x21))

    ;; If you visualize an integer constantly incrementing by 1,
    ;; in binary, you might understand why this works
    (i32.and (global.get $counter) (i32.const 4))
    if
      (call $draw-walking-viridian (local.get $vertical-flip-flag))
    else
      (call $draw-viridian (local.get $vertical-flip-flag))
    end
  )

  (func $draw-warp-hole
    (local $position i32)
    (local $size i32)

    ;; The warp hole is currently not actually drawn because it doesn't look very good
    ;; because of the way Viridian is drawn on top of it
    (return)

    (local.set $size (i32.add (local.get $size) (i32.const 160)))

    (loop $loop
      (call $rect (local.get $position) (local.get $position) (local.get $size) (local.get $size))

      (local.set $position (i32.add (local.get $position) (i32.const 5)))
      (local.set $size (i32.sub (local.get $size) (i32.const 10)))

      (br_if $loop (i32.lt_u (local.get $position) (i32.const 150)))
    )
  )

  (func $draw-viridian (param $vertical-flip-flag i32)
    ;; Draw Viridian!
    (global.get $viridian-direction)
    if ;; Viridian is facing the right
      (; This is required to make Viridian flip correctly because the sprite
         horizontally contains 4 more pixels than Viridian actually has ;)
      (global.set $viridian-x (f32.sub (global.get $viridian-x) (f32.const 5)))

      (call $blit
        (global.get $viridian-sprite)
        (i32.trunc_f32_s (global.get $viridian-x)) (global.get $viridian-y)
        (global.get $viridian-sprite-width) (global.get $viridian-sprite-height)
        (i32.or
          (i32.or
            (global.get $BLIT_1BPP)
            (global.get $BLIT_FLIP_X)
          )
          (local.get $vertical-flip-flag)
        )
      )

      ;; Now reset the X-axis
      (global.set $viridian-x (f32.add (global.get $viridian-x) (f32.const 5)))
    else ;; Viridian is facing the left
        (call $blit
          (global.get $viridian-sprite)
          (i32.trunc_f32_s (global.get $viridian-x)) (global.get $viridian-y)
          (global.get $viridian-sprite-width) (global.get $viridian-sprite-height)
          (i32.or
            (global.get $BLIT_1BPP)
            (local.get $vertical-flip-flag)
          )
        )
    end
  )

  (func $draw-walking-viridian (param $vertical-flip-flag i32)
    ;; Draw walking Viridian!

    ;; Alignment
    (global.get $viridian-flipped)
    if
      (global.set $viridian-y (i32.sub (global.get $viridian-y) (i32.const 1)))
    else
      (global.set $viridian-y (i32.add (global.get $viridian-y) (i32.const 1)))
    end

    (global.get $viridian-direction)
    if ;; Viridian is facing the right
      (; This is required to make Viridian flip correctly because the sprite
         horizontally contains 4 more pixels than Viridian actually has ;)
      (global.set $viridian-x (f32.sub (global.get $viridian-x) (f32.const 4)))

      (call $blit
        (global.get $viridian-walking-sprite)
        (i32.trunc_f32_s (global.get $viridian-x)) (global.get $viridian-y)
        (global.get $viridian-walking-sprite-width) (global.get $viridian-walking-sprite-height)
        (i32.or
          (i32.or
            (global.get $BLIT_1BPP)
            (global.get $BLIT_FLIP_X)
          )
          (local.get $vertical-flip-flag)
        )
      )

      ;; Now reset the X-axis
      (global.set $viridian-x (f32.add (global.get $viridian-x) (f32.const 4)))
    else ;; Viridian is facing the left
      (global.set $viridian-x (f32.sub (global.get $viridian-x) (f32.const 1))) ;; Alignment
      (call $blit
        (global.get $viridian-walking-sprite)
        (i32.trunc_f32_s (global.get $viridian-x)) (global.get $viridian-y)
        (global.get $viridian-walking-sprite-width) (global.get $viridian-walking-sprite-height)
        (i32.or
          (global.get $BLIT_1BPP)
          (local.get $vertical-flip-flag)
        )
      )

      ;; Reset
      (global.get $viridian-flipped)
      if
        (global.set $viridian-y (i32.add (global.get $viridian-y) (i32.const 1)))
      else
        (global.set $viridian-y (i32.sub (global.get $viridian-y) (i32.const 1)))
      end
    end
    (global.set $viridian-y (i32.sub (global.get $viridian-y) (i32.const 1))) ;; Reset
  )

  (func $clear
    (local $index i32)

    ;; Find the upper bound address of the framebuffer
    (local $framebuffer-upper-bound i32)
    (local.set $framebuffer-upper-bound
      (i32.mul (i32.const 160) (i32.const 160)))
    (local.set $framebuffer-upper-bound
      (i32.div_u (local.get $framebuffer-upper-bound) (i32.const 4)))

    (loop $loop
      ;; 0xa0 is the start address of the framebuffer
      (i32.store8 offset=0xa0 (local.get $index) (i32.const 0xaa))

      (local.set $index (i32.add (local.get $index) (i32.const 1)))

      (br_if $loop (i32.lt_u (local.get $index) (local.get $framebuffer-upper-bound)))
    )
  )
)
