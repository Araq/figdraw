## Compile SPIR-V bytes into aligned words without emitting large C strings.

func spirvWords*(data: static[string]): array[data.len div 4, uint32] =
  static:
    doAssert data.len mod 4 == 0, "SPIR-V data must contain complete 32-bit words"
  for i in 0 ..< result.len:
    let offset = i * 4
    result[i] =
      uint32(ord(data[offset])) or (uint32(ord(data[offset + 1])) shl 8) or
      (uint32(ord(data[offset + 2])) shl 16) or (uint32(ord(data[offset + 3])) shl 24)
