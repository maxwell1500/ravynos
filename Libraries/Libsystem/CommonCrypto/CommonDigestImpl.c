/*
 * CommonDigest implementation for ravynOS libcommonCrypto.dylib.
 * Implements CC_MD5, CC_SHA1, CC_SHA224, CC_SHA256, CC_SHA384, CC_SHA512.
 */
#include <CommonCrypto/CommonDigest.h>
#include <string.h>
#include <stdlib.h>

/* --- MD5 --- */
#define F(x, y, z) (((x) & (y)) | ((~x) & (z)))
#define G(x, y, z) (((x) & (z)) | ((y) & (~z)))
#define H(x, y, z) ((x) ^ (y) ^ (z))
#define I(x, y, z) ((y) ^ ((x) | (~z)))

#define ROTL(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

#define FF(a, b, c, d, x, s, ac) { \
    (a) += F((b), (c), (d)) + (x) + (CC_LONG)(ac); \
    (a) = ROTL((a), (s)); \
    (a) += (b); \
}
#define GG(a, b, c, d, x, s, ac) { \
    (a) += G((b), (c), (d)) + (x) + (CC_LONG)(ac); \
    (a) = ROTL((a), (s)); \
    (a) += (b); \
}
#define HH(a, b, c, d, x, s, ac) { \
    (a) += H((b), (c), (d)) + (x) + (CC_LONG)(ac); \
    (a) = ROTL((a), (s)); \
    (a) += (b); \
}
#define II(a, b, c, d, x, s, ac) { \
    (a) += I((b), (c), (d)) + (x) + (CC_LONG)(ac); \
    (a) = ROTL((a), (s)); \
    (a) += (b); \
}

static void md5_transform(CC_LONG state[4], const unsigned char block[64]) {
    CC_LONG a = state[0], b = state[1], c = state[2], d = state[3], x[16];
    for (int i = 0, j = 0; i < 16; i++, j += 4)
        x[i] = ((CC_LONG)block[j]) | (((CC_LONG)block[j+1]) << 8) |
               (((CC_LONG)block[j+2]) << 16) | (((CC_LONG)block[j+3]) << 24);

    FF(a, b, c, d, x[ 0],  7, 0xd76aa478); FF(d, a, b, c, x[ 1], 12, 0xe8c7b756);
    FF(c, d, a, b, x[ 2], 17, 0x242070db); FF(b, c, d, a, x[ 3], 22, 0xc1bdceee);
    FF(a, b, c, d, x[ 4],  7, 0xf57c0faf); FF(d, a, b, c, x[ 5], 12, 0x4787c62a);
    FF(c, d, a, b, x[ 6], 17, 0xa8304613); FF(b, c, d, a, x[ 7], 22, 0xfd469501);
    FF(a, b, c, d, x[ 8],  7, 0x698098d8); FF(d, a, b, c, x[ 9], 12, 0x8b44f7af);
    FF(c, d, a, b, x[10], 17, 0xffff5bb1); FF(b, c, d, a, x[11], 22, 0x895cd7be);
    FF(a, b, c, d, x[12],  7, 0x6b901122); FF(d, a, b, c, x[13], 12, 0xfd987193);
    FF(c, d, a, b, x[14], 17, 0xa679438e); FF(b, c, d, a, x[15], 22, 0x49b40821);

    GG(a, b, c, d, x[ 1],  5, 0xf61e2562); GG(d, a, b, c, x[ 6],  9, 0xc040b340);
    GG(c, d, a, b, x[11], 14, 0x265e5a51); GG(b, c, d, a, x[ 0], 20, 0xe9b6c7aa);
    GG(a, b, c, d, x[ 5],  5, 0xd62f105d); GG(d, a, b, c, x[10],  9, 0x02441453);
    GG(c, d, a, b, x[15], 14, 0xd8a1e681); GG(b, c, d, a, x[ 4], 20, 0xe7d3fbc8);
    GG(a, b, c, d, x[ 9],  5, 0x21e1cde6); GG(d, a, b, c, x[14],  9, 0xc33707d6);
    GG(c, d, a, b, x[ 3], 14, 0xf4d50d87); GG(b, c, d, a, x[ 8], 20, 0x455a14ed);
    GG(a, b, c, d, x[13],  5, 0xa9e3e905); GG(d, a, b, c, x[ 2],  9, 0xfcefa3f8);
    GG(c, d, a, b, x[ 7], 14, 0x676f02d9); GG(b, c, d, a, x[12], 20, 0x8d2a4c8a);

    HH(a, b, c, d, x[ 5],  4, 0xfffa3942); HH(d, a, b, c, x[ 8], 11, 0x8771f681);
    HH(c, d, a, b, x[11], 16, 0x6d9d6122); HH(b, c, d, a, x[14], 23, 0xfde5380c);
    HH(a, b, c, d, x[ 1],  4, 0xa4beea44); HH(d, a, b, c, x[ 4], 11, 0x4bdecfa9);
    HH(c, d, a, b, x[ 7], 16, 0xf6bb4b60); HH(b, c, d, a, x[10], 23, 0xbebfbc70);
    HH(a, b, c, d, x[13],  4, 0x289b7ec6); HH(d, a, b, c, x[ 0], 11, 0xeaa127fa);
    HH(c, d, a, b, x[ 3], 16, 0xd4ef3085); HH(b, c, d, a, x[ 6], 23, 0x04881d05);
    HH(a, b, c, d, x[ 9],  4, 0xd9d4d039); HH(d, a, b, c, x[12], 11, 0xe6db99e5);
    HH(c, d, a, b, x[15], 16, 0x1fa27cf8); HH(b, c, d, a, x[ 2], 23, 0xc4ac5665);

    II(a, b, c, d, x[ 0],  6, 0xf4292244); II(d, a, b, c, x[ 7], 10, 0x432aff97);
    II(c, d, a, b, x[14], 15, 0xab9423a7); II(b, c, d, a, x[ 5], 21, 0xfc93a039);
    II(a, b, c, d, x[12],  6, 0x655b59c3); II(d, a, b, c, x[ 3], 10, 0x8f0ccc92);
    II(c, d, a, b, x[10], 15, 0xffeff47d); II(b, c, d, a, x[ 1], 21, 0x85845dd1);
    II(a, b, c, d, x[ 8],  6, 0x6fa87e4f); II(d, a, b, c, x[15], 10, 0xfe2ce6e0);
    II(c, d, a, b, x[ 6], 15, 0xa3014314); II(b, c, d, a, x[13], 21, 0x4e0811a1);
    II(a, b, c, d, x[ 4],  6, 0xf7537e82); II(d, a, b, c, x[11], 10, 0xbd3af235);
    II(c, d, a, b, x[ 2], 15, 0x2ad7d2bb); II(b, c, d, a, x[ 9], 21, 0xeb86d391);

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
}

int CC_MD5_Init(CC_MD5_CTX *c) {
    if (!c) return 0;
    c->A = 0x67452301;
    c->B = 0xefcdab89;
    c->C = 0x98badcfe;
    c->D = 0x10325476;
    c->Nl = c->Nh = 0;
    c->num = 0;
    return 1;
}

int CC_MD5_Update(CC_MD5_CTX *c, const void *data, CC_LONG len) {
    if (!c || !data || len == 0) return 1;
    const unsigned char *input = (const unsigned char *)data;
    CC_LONG left = c->Nl & 0x3F;
    c->Nl += (len << 3);
    if (c->Nl < (len << 3)) c->Nh++;
    c->Nh += (len >> 29);

    CC_LONG fill = 64 - left;
    unsigned char *buf = (unsigned char *)c->data;
    if (len >= fill) {
        memcpy(buf + left, input, fill);
        md5_transform(&c->A, buf);
        input += fill;
        len -= fill;
        while (len >= 64) {
            md5_transform(&c->A, input);
            input += 64;
            len -= 64;
        }
        left = 0;
    }
    memcpy(buf + left, input, len);
    return 1;
}

int CC_MD5_Final(unsigned char *md, CC_MD5_CTX *c) {
    if (!c || !md) return 0;
    static const unsigned char PADDING[64] = { 0x80 };
    unsigned char bits[8];
    for (int i = 0; i < 4; i++) bits[i] = (unsigned char)((c->Nl >> (i * 8)) & 0xFF);
    for (int i = 0; i < 4; i++) bits[i + 4] = (unsigned char)((c->Nh >> (i * 8)) & 0xFF);

    CC_LONG index = (c->Nl >> 3) & 0x3F;
    CC_LONG padLen = (index < 56) ? (56 - index) : (120 - index);
    CC_MD5_Update(c, PADDING, padLen);
    CC_MD5_Update(c, bits, 8);

    for (int i = 0; i < 4; i++) {
        CC_LONG val = (&c->A)[i];
        md[i * 4]     = (unsigned char)(val & 0xFF);
        md[i * 4 + 1] = (unsigned char)((val >> 8) & 0xFF);
        md[i * 4 + 2] = (unsigned char)((val >> 16) & 0xFF);
        md[i * 4 + 3] = (unsigned char)((val >> 24) & 0xFF);
    }
    return 1;
}

unsigned char *CC_MD5(const void *data, CC_LONG len, unsigned char *md) {
    static unsigned char static_md[CC_MD5_DIGEST_LENGTH];
    if (!md) md = static_md;
    CC_MD5_CTX ctx;
    CC_MD5_Init(&ctx);
    CC_MD5_Update(&ctx, data, len);
    CC_MD5_Final(md, &ctx);
    return md;
}

/* --- SHA-1 --- */
static void sha1_transform(CC_LONG state[5], const unsigned char buffer[64]) {
    CC_LONG a = state[0], b = state[1], c = state[2], d = state[3], e = state[4];
    CC_LONG w[80];
    for (int i = 0; i < 16; i++) {
        w[i] = ((CC_LONG)buffer[i * 4] << 24) |
               ((CC_LONG)buffer[i * 4 + 1] << 16) |
               ((CC_LONG)buffer[i * 4 + 2] << 8) |
               ((CC_LONG)buffer[i * 4 + 3]);
    }
    for (int i = 16; i < 80; i++) {
        w[i] = ROTL(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    for (int i = 0; i < 80; i++) {
        CC_LONG f, k;
        if (i < 20) {
            f = (b & c) | ((~b) & d);
            k = 0x5A827999;
        } else if (i < 40) {
            f = b ^ c ^ d;
            k = 0x6ED9EBA1;
        } else if (i < 60) {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8F1BBCDC;
        } else {
            f = b ^ c ^ d;
            k = 0xCA62C1D6;
        }
        CC_LONG temp = ROTL(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = ROTL(b, 30);
        b = a;
        a = temp;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d; state[4] += e;
}

int CC_SHA1_Init(CC_SHA1_CTX *c) {
    if (!c) return 0;
    c->h0 = 0x67452301;
    c->h1 = 0xEFCDAB89;
    c->h2 = 0x98BADCFE;
    c->h3 = 0x10325476;
    c->h4 = 0xC3D2E1F0;
    c->Nl = c->Nh = 0;
    c->num = 0;
    return 1;
}

int CC_SHA1_Update(CC_SHA1_CTX *c, const void *data, CC_LONG len) {
    if (!c || !data || len == 0) return 1;
    const unsigned char *input = (const unsigned char *)data;
    CC_LONG left = (c->Nl >> 3) & 0x3F;
    c->Nl += (len << 3);
    if (c->Nl < (len << 3)) c->Nh++;
    c->Nh += (len >> 29);

    CC_LONG fill = 64 - left;
    unsigned char *buf = (unsigned char *)c->data;
    if (len >= fill) {
        memcpy(buf + left, input, fill);
        sha1_transform(&c->h0, buf);
        input += fill;
        len -= fill;
        while (len >= 64) {
            sha1_transform(&c->h0, input);
            input += 64;
            len -= 64;
        }
        left = 0;
    }
    memcpy(buf + left, input, len);
    return 1;
}

int CC_SHA1_Final(unsigned char *md, CC_SHA1_CTX *c) {
    if (!c || !md) return 0;
    static const unsigned char PADDING[64] = { 0x80 };
    unsigned char bits[8];
    for (int i = 0; i < 4; i++) bits[i] = (unsigned char)((c->Nh >> ((3 - i) * 8)) & 0xFF);
    for (int i = 0; i < 4; i++) bits[i + 4] = (unsigned char)((c->Nl >> ((3 - i) * 8)) & 0xFF);

    CC_LONG index = (c->Nl >> 3) & 0x3F;
    CC_LONG padLen = (index < 56) ? (56 - index) : (120 - index);
    CC_SHA1_Update(c, PADDING, padLen);
    CC_SHA1_Update(c, bits, 8);

    for (int i = 0; i < 5; i++) {
        CC_LONG val = (&c->h0)[i];
        md[i * 4]     = (unsigned char)((val >> 24) & 0xFF);
        md[i * 4 + 1] = (unsigned char)((val >> 16) & 0xFF);
        md[i * 4 + 2] = (unsigned char)((val >> 8) & 0xFF);
        md[i * 4 + 3] = (unsigned char)(val & 0xFF);
    }
    return 1;
}

unsigned char *CC_SHA1(const void *data, CC_LONG len, unsigned char *md) {
    static unsigned char static_md[CC_SHA1_DIGEST_LENGTH];
    if (!md) md = static_md;
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    CC_SHA1_Update(&ctx, data, len);
    CC_SHA1_Final(md, &ctx);
    return md;
}

/* --- SHA-256 --- */
#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22))
#define EP1(x) (ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25))
#define SIG0(x) (ROTR(x, 7) ^ ROTR(x, 18) ^ ((x) >> 3))
#define SIG1(x) (ROTR(x, 17) ^ ROTR(x, 19) ^ ((x) >> 10))

static const CC_LONG K256[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void sha256_transform(CC_LONG state[8], const unsigned char data[64]) {
    CC_LONG a = state[0], b = state[1], c = state[2], d = state[3];
    CC_LONG e = state[4], f = state[5], g = state[6], h = state[7];
    CC_LONG m[64];
    for (int i = 0, j = 0; i < 16; i++, j += 4)
        m[i] = ((CC_LONG)data[j] << 24) | ((CC_LONG)data[j+1] << 16) |
               ((CC_LONG)data[j+2] << 8) | ((CC_LONG)data[j+3]);
    for (int i = 16; i < 64; i++)
        m[i] = SIG1(m[i - 2]) + m[i - 7] + SIG0(m[i - 15]) + m[i - 16];

    for (int i = 0; i < 64; i++) {
        CC_LONG t1 = h + EP1(e) + CH(e, f, g) + K256[i] + m[i];
        CC_LONG t2 = EP0(a) + MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

int CC_SHA256_Init(CC_SHA256_CTX *c) {
    if (!c) return 0;
    c->count[0] = c->count[1] = 0;
    c->hash[0] = 0x6a09e667;
    c->hash[1] = 0xbb67ae85;
    c->hash[2] = 0x3c6ef372;
    c->hash[3] = 0xa54ff53a;
    c->hash[4] = 0x510e527f;
    c->hash[5] = 0x9b05688c;
    c->hash[6] = 0x1f83d9ab;
    c->hash[7] = 0x5be0cd19;
    return 1;
}

int CC_SHA256_Update(CC_SHA256_CTX *c, const void *data, CC_LONG len) {
    if (!c || !data || len == 0) return 1;
    const unsigned char *input = (const unsigned char *)data;
    CC_LONG left = (c->count[0] >> 3) & 0x3F;
    c->count[0] += (len << 3);
    if (c->count[0] < (len << 3)) c->count[1]++;
    c->count[1] += (len >> 29);

    CC_LONG fill = 64 - left;
    unsigned char *buf = (unsigned char *)c->wbuf;
    if (len >= fill) {
        memcpy(buf + left, input, fill);
        sha256_transform(c->hash, buf);
        input += fill;
        len -= fill;
        while (len >= 64) {
            sha256_transform(c->hash, input);
            input += 64;
            len -= 64;
        }
        left = 0;
    }
    memcpy(buf + left, input, len);
    return 1;
}

int CC_SHA256_Final(unsigned char *md, CC_SHA256_CTX *c) {
    if (!c || !md) return 0;
    static const unsigned char PADDING[64] = { 0x80 };
    unsigned char bits[8];
    for (int i = 0; i < 4; i++) bits[i] = (unsigned char)((c->count[1] >> ((3 - i) * 8)) & 0xFF);
    for (int i = 0; i < 4; i++) bits[i + 4] = (unsigned char)((c->count[0] >> ((3 - i) * 8)) & 0xFF);

    CC_LONG index = (c->count[0] >> 3) & 0x3F;
    CC_LONG padLen = (index < 56) ? (56 - index) : (120 - index);
    CC_SHA256_Update(c, PADDING, padLen);
    CC_SHA256_Update(c, bits, 8);

    for (int i = 0; i < 8; i++) {
        CC_LONG val = c->hash[i];
        md[i * 4]     = (unsigned char)((val >> 24) & 0xFF);
        md[i * 4 + 1] = (unsigned char)((val >> 16) & 0xFF);
        md[i * 4 + 2] = (unsigned char)((val >> 8) & 0xFF);
        md[i * 4 + 3] = (unsigned char)(val & 0xFF);
    }
    return 1;
}

unsigned char *CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
    static unsigned char static_md[CC_SHA256_DIGEST_LENGTH];
    if (!md) md = static_md;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, data, len);
    CC_SHA256_Final(md, &ctx);
    return md;
}

/* --- SHA-224 --- */
int CC_SHA224_Init(CC_SHA256_CTX *c) {
    if (!c) return 0;
    c->count[0] = c->count[1] = 0;
    c->hash[0] = 0xc1059ed8;
    c->hash[1] = 0x367cd507;
    c->hash[2] = 0x3070dd17;
    c->hash[3] = 0xf70e5939;
    c->hash[4] = 0xffc00b31;
    c->hash[5] = 0x68581511;
    c->hash[6] = 0x64f98fa7;
    c->hash[7] = 0xbefa4fa4;
    return 1;
}
int CC_SHA224_Update(CC_SHA256_CTX *c, const void *data, CC_LONG len) {
    return CC_SHA256_Update(c, data, len);
}
int CC_SHA224_Final(unsigned char *md, CC_SHA256_CTX *c) {
    unsigned char full[CC_SHA256_DIGEST_LENGTH];
    if (!CC_SHA256_Final(full, c)) return 0;
    memcpy(md, full, CC_SHA224_DIGEST_LENGTH);
    return 1;
}
unsigned char *CC_SHA224(const void *data, CC_LONG len, unsigned char *md) {
    static unsigned char static_md[CC_SHA224_DIGEST_LENGTH];
    if (!md) md = static_md;
    CC_SHA256_CTX ctx;
    CC_SHA224_Init(&ctx);
    CC_SHA224_Update(&ctx, data, len);
    CC_SHA224_Final(md, &ctx);
    return md;
}
