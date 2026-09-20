"""Deterministic PNG data with four quadrants for crop and integrity checks."""
import struct
import zlib


def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))


def png(width=40, height=80, compressed=None):
    pixels = b''.join(b'\x00' + b''.join(bytes((255 if x < width // 2 else 0,
                                             255 if y < height // 2 else 0, 0))
                                      for x in range(width)) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels) if compressed is None else compressed) + chunk(b'IEND', b''))
