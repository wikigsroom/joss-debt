"""Change only the typed minSdkVersion field in an Android binary XML manifest."""
import struct

def minimum_sdk(data, minimum):
    result = bytearray(data)
    if struct.unpack_from("<H", result)[0] != 3: raise ValueError("Expected binary XML")
    offset = struct.unpack_from("<H", result, 2)[0]
    strings = []
    changed = 0
    while offset < len(result):
        kind, header, size = struct.unpack_from("<HHI", result, offset)
        if size < header or offset + size > len(result): raise ValueError("Invalid XML chunk")
        if kind == 1:
            count, _, flags, start = struct.unpack_from("<IIII", result, offset + 8)
            for index in range(count):
                relative = struct.unpack_from("<I", result, offset + header + index * 4)[0]
                pos = offset + start + relative
                if flags & 0x100:
                    def length(pos):
                        n = result[pos]; pos += 1
                        if n & 128: n = ((n & 127) << 8) | result[pos]; pos += 1
                        return n, pos
                    _, pos = length(pos); n, pos = length(pos)
                    strings.append(bytes(result[pos:pos + n]).decode("utf8"))
                else:
                    n = struct.unpack_from("<H", result, pos)[0]; pos += 2
                    if n & 0x8000:
                        n = ((n & 0x7fff) << 16) | struct.unpack_from("<H", result, pos)[0]; pos += 2
                    strings.append(bytes(result[pos:pos + n * 2]).decode("utf-16le"))
        elif kind == 0x102:
            element = struct.unpack_from("<I", result, offset + 20)[0]
            attribute_start, attribute_size, count = struct.unpack_from("<HHH", result, offset + 24)
            if strings[element] == "uses-sdk":
                for i in range(count):
                    pos = offset + 16 + attribute_start + i * attribute_size
                    name = struct.unpack_from("<I", result, pos + 4)[0]
                    if strings[name] == "minSdkVersion":
                        if result[pos + 15] != 0x10: raise ValueError("Minimum SDK must be an integer")
                        old = struct.unpack_from("<I", result, pos + 16)[0]
                        if old not in (24, minimum): raise ValueError("Unexpected original minimum SDK")
                        struct.pack_into("<I", result, pos + 8, 0xffffffff)
                        struct.pack_into("<I", result, pos + 16, minimum)
                        changed += 1
        offset += size
    if changed != 1: raise ValueError("Expected exactly one minimum SDK attribute")
    return bytes(result)
