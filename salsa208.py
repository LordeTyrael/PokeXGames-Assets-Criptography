# salsa20/8 - as used by the game
# verified against pycryptodome s20/20, same rounds just 4x instead of 10
#
# state is 16 words LE:
#   0: "expa"  1-4: key  5: "nd 3"  6-7: nonce
#   8-9: ctr   10: "2-by" 11-14: key  15: "te k"
import struct

SIGMA = (0x61707865, 0x3320646e, 0x79622d32, 0x6b206574)
M32 = 0xffffffff


def rotl(v, n):
    return ((v << n) | (v >> (32 - n))) & M32


def qr(y0, y1, y2, y3):
    y1 ^= rotl((y0 + y3) & M32, 7)
    y2 ^= rotl((y1 + y0) & M32, 9)
    y3 ^= rotl((y2 + y1) & M32, 13)
    y0 ^= rotl((y3 + y2) & M32, 18)
    return y0 & M32, y1, y2, y3


def doubleround(x):
    # columns
    x[0], x[4], x[8], x[12] = qr(x[0], x[4], x[8], x[12])
    x[5], x[9], x[13], x[1] = qr(x[5], x[9], x[13], x[1])
    x[10], x[14], x[2], x[6] = qr(x[10], x[14], x[2], x[6])
    x[15], x[3], x[7], x[11] = qr(x[15], x[3], x[7], x[11])
    # rows
    x[0], x[1], x[2], x[3] = qr(x[0], x[1], x[2], x[3])
    x[5], x[6], x[7], x[4] = qr(x[5], x[6], x[7], x[4])
    x[10], x[11], x[8], x[9] = qr(x[10], x[11], x[8], x[9])
    x[15], x[12], x[13], x[14] = qr(x[15], x[12], x[13], x[14])


def salsa_hash(b, rounds=8):
    x = list(struct.unpack("<16I", b))
    x0 = x[:]
    for _ in range(rounds // 2):
        doubleround(x)
    return struct.pack("<16I", *((x[i] + x0[i]) & M32 for i in range(16)))


class Salsa208(object):
    def __init__(self, key, nonce=b"\x00" * 8):
        assert len(key) == 32 and len(nonce) == 8
        self.kw = struct.unpack("<8I", key)
        self.nw = struct.unpack("<2I", nonce)
        self.ctr = 0

    def block(self, idx=None):
        if idx is None:
            idx = self.ctr
            self.ctr += 1
        st = (SIGMA[0],) + self.kw[:4] + (SIGMA[1],) + self.nw + \
             (idx & M32, (idx >> 32) & M32, SIGMA[2]) + self.kw[4:] + (SIGMA[3],)
        return salsa_hash(struct.pack("<16I", *st))

    def crypt(self, data):
        out = bytearray(data)
        off = 0
        while off < len(data):
            ks = self.block()
            n = min(64, len(data) - off)
            for i in range(n):
                out[off + i] ^= ks[i]
            off += n
        return bytes(out)


if __name__ == "__main__":
    # testvecs
    assert qr(1, 0, 0, 0) == (0x08008145, 0x80, 0x10200, 0x20500000)
    assert qr(0, 1, 0, 0) == (0x88000100, 1, 0x200, 0x402000)

    # s20/20 hash vec (pattern check only, game uses /8)
    st = struct.pack("<16I", 1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4)
    assert salsa_hash(st, 20).hex() == (
        "901772f6ddfa7305eb5aa7d2169a8da0c6acd3cf4eddc44bb2b2a17ca9a730ec"
        "9d08b67c575efc09d06f3027cf42fa6ebab45a915fd2612664703c6460424313")
    print("ok")
    
