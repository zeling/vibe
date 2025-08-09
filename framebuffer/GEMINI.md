You are writing a Zig program to render a given text with a TrueType font a framebuffer device.
You do not need to implement the parsing of TTFs yourself, instead try to use the library functions from `stb`.

In the current directory, I have setup the following environment for you:

- The development environment is specified in `flake.nix`, it currently has `git` and `zig`, in case you need
  extra dependencies for the project, add them there.
- A checkout of the latest [`stb`](https://github.com/nothings/stb) library. This is a header-only C library. Read
  the source code for documentation. The 2 files that you should focus on are `stb_truetype.h` and `stb_image_write.h`.


# Specification

## Input
The program should accept the following arguments:

- `--font`, required, the filepath for the `ttf` font.
- `--text`, required, the text to render.
- `--fb`, optional, the path to the framebuffer device, defaults to `/dev/fb0`.

## Behavior
The program should open the framebuffer device and figure out the geometry: the height, width and number of bits per
pixel. Using these information to render the given text and given font, write the rendered image to the framebuffer

## Output
Reasonable logs to indicate events and/or errors happening.

# Build and Test
Use the `zig` cli tools to build and test to verify the code you write.
