import std/[os, unittest]
import ../src/figdraw/vulkan/spirv

template checkShader(path: static[string]) =
  const words = spirvWords(staticRead(path))
  let bytes = readFile(currentSourcePath().parentDir / path)
  check words.len * sizeof(uint32) == bytes.len
  check words[0] == 0x07230203'u32
  check cast[uint](unsafeAddr words[0]) mod alignof(uint32).uint == 0
  for i, value in bytes:
    check uint8((words[i div 4] shr ((i mod 4) * 8)) and 0xff) == uint8(ord(value))

suite "Embedded SPIR-V words":
  test "decode little-endian words including high bits and zero bytes":
    const words = spirvWords("\x03\x02\x23\x07\x00\x80\xff\x00")
    check words == [0x07230203'u32, 0x00ff8000'u32]

  test "SDF vertex shader retains every byte":
    checkShader("../src/figdraw/vulkan/shaders/sdf.vert.spv")

  test "SDF fragment shader retains every byte":
    checkShader("../src/figdraw/vulkan/shaders/sdf.frag.spv")

  test "blur vertex shader retains every byte":
    checkShader("../src/figdraw/vulkan/shaders/blur.vert.spv")

  test "blur fragment shader retains every byte":
    checkShader("../src/figdraw/vulkan/shaders/blur.frag.spv")
