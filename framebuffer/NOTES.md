# Notes from experimenting with `gemini-cli` (not generated)

## What went well

Overall it was very satisfying that it had no issues with zig toolchain. I do
believe zig should take some credit here for being very usable.

- It knew how to setup cross-compilation in `zig.build` (this is supposed to be
run on a raspberry pi and is developed on a mac).
- It figured out how zig interops with C and succesfully wrote code to render
fonts into bitmap.
- It also figured out the ioctl ABI like `fb_var_screeninfo`. It just generated
the current definiton in correct zig syntax, no hallucination at all.


## What could go better

- It failed to fix some basic syntax error and ended up looping. I had to jump
in to fix so that it can make further progress. It might be something in the
compiler's output that tricked gemini into a loop. I am almost sure this is
fixable with better prompting, but I had no success so far and I am still
learning.
- I needed to give it a little help when it found out zig cannot translate
`goto` statements with `@cInclude`. It seemed to me that Gemini was totally lost
there.
- It did a not-so-good job in understanding bits v.s. bytes. This was very
surprising to me. I was under the impression that this should fall into the
"too-easy" bucket for the LLMs nowadays. Gemini did eventually make the right
fix after being told `bits_per_pixel` is not supposed to be used when
`bytes_per_pixel` is expected.
- It did not produce the right code for `bits_per_pixel` < 8, the produced
code will loop for 0 times which is no-op. I was downgraded to 2.5-flash for
reaching the daily quota at this point.
