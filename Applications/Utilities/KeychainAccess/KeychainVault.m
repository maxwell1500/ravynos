#import "KeychainVault.h"
#import <CommonCrypto/CommonDigest.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>

/* ---------------- SHA-256 ---------------- */
static const unsigned int K256[64] = {
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990623,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};

static void sha256(const unsigned char *data, size_t len, unsigned char *out) {
    unsigned int h[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    unsigned char buf[64];
    size_t total = len;
    // process full blocks
    size_t i = 0;
    unsigned int w[64];
    // We'll do streaming manually
    // First, handle all complete 64-byte blocks from data
    size_t pos = 0;
    unsigned long long bitlen = (unsigned long long)len * 8ULL;
    // We need process in blocks; handle remainder by padding
    // Simpler: copy data into a buffer with padding
    // But large data; do block loop
    unsigned int state[8]; memcpy(state,h,sizeof(state));
    // process complete blocks
    size_t off = 0;
    while (off + 64 <= len) {
        for (i=0;i<16;i++) {
            w[i] = ((unsigned int)data[off+i*4]<<24)|((unsigned int)data[off+i*4+1]<<16)|((unsigned int)data[off+i*4+2]<<8)|((unsigned int)data[off+i*4+3]);
        }
        for (i=16;i<64;i++) {
            unsigned int s0 = ((w[i-15]>>7)|(w[i-15]<<25)) ^ ((w[i-15]>>18)|(w[i-15]<<14)) ^ (w[i-15]>>3);
            unsigned int s1 = ((w[i-2]>>17)|(w[i-2]<<15)) ^ ((w[i-2]>>19)|(w[i-2]<<13)) ^ (w[i-2]>>10);
            w[i] = w[i-16]+s0+w[i-7]+s1;
        }
        unsigned int a=state[0],b=state[1],c=state[2],d=state[3],e=state[4],f=state[5],g=state[6],hh=state[7];
        for (i=0;i<64;i++) {
            unsigned int S1 = ((e>>6)|(e<<26)) ^ ((e>>11)|(e<<21)) ^ ((e>>25)|(e<<7));
            unsigned int ch = (e&f)^(~e&g);
            unsigned int temp1 = hh+S1+ch+K256[i]+w[i];
            unsigned int S0 = ((a>>2)|(a<<30)) ^ ((a>>13)|(a<<19)) ^ ((a>>22)|(a<<10));
            unsigned int maj = (a&b)^(a&c)^(b&c);
            unsigned int temp2 = S0+maj;
            hh=g; g=f; f=e; e=d+temp1; d=c; c=b; b=a; a=temp1+temp2;
        }
        state[0]+=a;state[1]+=b;state[2]+=c;state[3]+=d;state[4]+=e;state[5]+=f;state[6]+=g;state[7]+=hh;
        off += 64;
    }
    // padding
    size_t rem = len - off;
    unsigned char pad[128];
    memset(pad,0,sizeof(pad));
    memcpy(pad, data+off, rem);
    pad[rem] = 0x80;
    size_t padlen = rem + 1;
    // ensure 8 bytes length at end of final 64-block(s)
    if (padlen + 8 > 64) {
        // two blocks
        while (padlen < 64) pad[padlen++] = 0;
        // process first pad block
        // (reuse block processing by copying into buf)
        memcpy(buf, pad, 64);
        for (i=0;i<16;i++) w[i]=((unsigned int)buf[i*4]<<24)|((unsigned int)buf[i*4+1]<<16)|((unsigned int)buf[i*4+2]<<8)|((unsigned int)buf[i*4+3]);
        for (i=16;i<64;i++){unsigned int s0=((w[i-15]>>7)|(w[i-15]<<25))^((w[i-15]>>18)|(w[i-15]<<14))^(w[i-15]>>3);unsigned int s1=((w[i-2]>>17)|(w[i-2]<<15))^((w[i-2]>>19)|(w[i-2]<<13))^(w[i-2]>>10);w[i]=w[i-16]+s0+w[i-7]+s1;}
        unsigned int a=state[0],b=state[1],c=state[2],d=state[3],e=state[4],f=state[5],g=state[6],hh=state[7];
        for (i=0;i<64;i++){unsigned int S1=((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7));unsigned int ch=(e&f)^(~e&g);unsigned int temp1=hh+S1+ch+K256[i]+w[i];unsigned int S0=((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10));unsigned int maj=(a&b)^(a&c)^(b&c);unsigned int temp2=S0+maj;hh=g;g=f;f=e;e=d+temp1;d=c;c=b;b=a;a=temp1+temp2;}
        state[0]+=a;state[1]+=b;state[2]+=c;state[3]+=d;state[4]+=e;state[5]+=f;state[6]+=g;state[7]+=hh;
        // second block: zeros then length
        memset(pad,0,64);
        // put length in last 8 bytes (big-endian)
        for (i=0;i<8;i++) pad[64-8+i] = (unsigned char)((bitlen >> (56 - i*8)) & 0xff);
        // Actually pad currently has first block processed; need second block array
        // We'll process pad (now zeros+length) as second block
        memcpy(buf, pad, 64);
        // ensure length bytes
        // already set above? We set pad[56..63]
        for (i=0;i<16;i++) w[i]=((unsigned int)buf[i*4]<<24)|((unsigned int)buf[i*4+1]<<16)|((unsigned int)buf[i*4+2]<<8)|((unsigned int)buf[i*4+3]);
        for (i=16;i<64;i++){unsigned int s0=((w[i-15]>>7)|(w[i-15]<<25))^((w[i-15]>>18)|(w[i-15]<<14))^(w[i-15]>>3);unsigned int s1=((w[i-2]>>17)|(w[i-2]<<15))^((w[i-2]>>19)|(w[i-2]<<13))^(w[i-2]>>10);w[i]=w[i-16]+s0+w[i-7]+s1;}
        a=state[0];b=state[1];c=state[2];d=state[3];e=state[4];f=state[5];g=state[6];hh=state[7];
        for (i=0;i<64;i++){unsigned int S1=((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7));unsigned int ch=(e&f)^(~e&g);unsigned int temp1=hh+S1+ch+K256[i]+w[i];unsigned int S0=((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10));unsigned int maj=(a&b)^(a&c)^(b&c);unsigned int temp2=S0+maj;hh=g;g=f;f=e;e=d+temp1;d=c;c=b;b=a;a=temp1+temp2;}
        state[0]+=a;state[1]+=b;state[2]+=c;state[3]+=d;state[4]+=e;state[5]+=f;state[6]+=g;state[7]+=hh;
    } else {
        // single final block
        while (padlen < 56) pad[padlen++] = 0;
        for (i=0;i<8;i++) pad[56+i] = (unsigned char)((bitlen >> (56 - i*8)) & 0xff);
        memcpy(buf, pad, 64);
        for (i=0;i<16;i++) w[i]=((unsigned int)buf[i*4]<<24)|((unsigned int)buf[i*4+1]<<16)|((unsigned int)buf[i*4+2]<<8)|((unsigned int)buf[i*4+3]);
        for (i=16;i<64;i++){unsigned int s0=((w[i-15]>>7)|(w[i-15]<<25))^((w[i-15]>>18)|(w[i-15]<<14))^(w[i-15]>>3);unsigned int s1=((w[i-2]>>17)|(w[i-2]<<15))^((w[i-2]>>19)|(w[i-2]<<13))^(w[i-2]>>10);w[i]=w[i-16]+s0+w[i-7]+s1;}
        unsigned int a=state[0],b=state[1],c=state[2],d=state[3],e=state[4],f=state[5],g=state[6],hh=state[7];
        for (i=0;i<64;i++){unsigned int S1=((e>>6)|(e<<26))^((e>>11)|(e<<21))^((e>>25)|(e<<7));unsigned int ch=(e&f)^(~e&g);unsigned int temp1=hh+S1+ch+K256[i]+w[i];unsigned int S0=((a>>2)|(a<<30))^((a>>13)|(a<<19))^((a>>22)|(a<<10));unsigned int maj=(a&b)^(a&c)^(b&c);unsigned int temp2=S0+maj;hh=g;g=f;f=e;e=d+temp1;d=c;c=b;b=a;a=temp1+temp2;}
        state[0]+=a;state[1]+=b;state[2]+=c;state[3]+=d;state[4]+=e;state[5]+=f;state[6]+=g;state[7]+=hh;
    }
    for (i=0;i<8;i++) {
        out[i*4] = (unsigned char)((state[i]>>24)&0xff);
        out[i*4+1] = (unsigned char)((state[i]>>16)&0xff);
        out[i*4+2] = (unsigned char)((state[i]>>8)&0xff);
        out[i*4+3] = (unsigned char)(state[i]&0xff);
    }
}

/* ---------------- HMAC-SHA256 ---------------- */
static void hmac_sha256(const unsigned char *key, size_t keylen, const unsigned char *data, size_t datalen, unsigned char *out) {
    unsigned char k[64];
    memset(k,0,64);
    if (keylen > 64) {
        sha256(key, keylen, k);
    } else {
        memcpy(k, key, keylen);
    }
    unsigned char ipad[64], opad[64];
    for (size_t i=0;i<64;i++){ ipad[i]=k[i]^0x36; opad[i]=k[i]^0x5c; }
    // inner
    // hash(ipad || data)
    // build buffer
    size_t innerlen = 64 + datalen;
    unsigned char *inner = malloc(innerlen);
    memcpy(inner, ipad, 64);
    memcpy(inner+64, data, datalen);
    unsigned char innerhash[32];
    sha256(inner, innerlen, innerhash);
    free(inner);
    // outer
    unsigned char outer[64+32];
    memcpy(outer, opad, 64);
    memcpy(outer+64, innerhash, 32);
    sha256(outer, 64+32, out);
}

/* ---------------- PBKDF2-HMAC-SHA256 ---------------- */
static void pbkdf2_sha256(const unsigned char *password, size_t passlen, const unsigned char *salt, size_t saltlen, unsigned int iterations, unsigned char *dk, size_t dklen) {
    size_t hlen = 32;
    unsigned int blocks = (unsigned int)((dklen + hlen - 1) / hlen);
    for (unsigned int i = 1; i <= blocks; i++) {
        // U1 = HMAC(password, salt || INT(i))
        unsigned char salti[1024];
        memcpy(salti, salt, saltlen);
        salti[saltlen] = (unsigned char)((i>>24)&0xff);
        salti[saltlen+1] = (unsigned char)((i>>16)&0xff);
        salti[saltlen+2] = (unsigned char)((i>>8)&0xff);
        salti[saltlen+3] = (unsigned char)(i&0xff);
        unsigned char u[32], t[32];
        hmac_sha256(password, passlen, salti, saltlen+4, u);
        memcpy(t, u, 32);
        for (unsigned int j = 1; j < iterations; j++) {
            hmac_sha256(password, passlen, u, 32, u);
            for (size_t k=0;k<32;k++) t[k] ^= u[k];
        }
        size_t off = (i-1)*hlen;
        size_t copy = hlen;
        if (off + copy > dklen) copy = dklen - off;
        memcpy(dk + off, t, copy);
    }
}

/* ---------------- AES-256 ---------------- */
static const unsigned char sbox[256] = {
0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16};

static const unsigned char invsbox[256] = {
0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d};

static unsigned char gmul(unsigned char a, unsigned char b) {
    unsigned char r = 0;
    for (int i=0;i<8;i++){ if (b&1) r ^= a; int hi = a & 0x80; a <<= 1; if (hi) a ^= 0x1b; b >>= 1; }
    return r;
}

static void aes256_expand(const unsigned char *key, unsigned char *rk) {
    // key 32 bytes, rk 240 bytes
    memcpy(rk, key, 32);
    int bytesGenerated = 32;
    int rconIter = 1;
    unsigned char temp[4];
    while (bytesGenerated < 240) {
        for (int i=0;i<4;i++) temp[i] = rk[bytesGenerated - 4 + i];
        if (bytesGenerated % 32 == 0) {
            // rotword + subword + rcon
            unsigned char t = temp[0];
            temp[0]=sbox[temp[1]]; temp[1]=sbox[temp[2]]; temp[2]=sbox[temp[3]]; temp[3]=sbox[t];
            temp[0] ^= (unsigned char)(rconIter);
            // rconIter x2? standard: rcon = 1,2,4,...
            // We'll update rconIter below by doubling
        } else if (bytesGenerated % 32 == 16) {
            for (int i=0;i<4;i++) temp[i] = sbox[temp[i]];
        }
        for (int i=0;i<4;i++) {
            rk[bytesGenerated] = rk[bytesGenerated - 32] ^ temp[i];
            bytesGenerated++;
        }
        if (bytesGenerated % 32 == 0) {
            rconIter <<= 1;
            if (rconIter > 0x80) rconIter = 0x1b; // not strictly needed beyond 10 rounds? AES256 needs rcon up to 7? Actually 7 rounds of expansion? Fine.
        }
    }
}

static void addRoundKey(unsigned char *state, const unsigned char *rk) {
    for (int i=0;i<16;i++) state[i] ^= rk[i];
}
static void subBytes(unsigned char *state) { for (int i=0;i<16;i++) state[i]=sbox[state[i]]; }
static void invSubBytes(unsigned char *state) { for (int i=0;i<16;i++) state[i]=invsbox[state[i]]; }
static void shiftRows(unsigned char *s) {
    unsigned char t;
    // row1 shift left 1
    t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
    // row2 shift left 2
    t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
    // row3 shift left 3
    t=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=s[3]; s[3]=t;
}
static void invShiftRows(unsigned char *s) {
    unsigned char t;
    t=s[13]; s[13]=s[9]; s[9]=s[5]; s[5]=s[1]; s[1]=t;
    t=s[14]; s[14]=s[6]; s[6]=t; t=s[10]; s[10]=s[2]; s[2]=t;
    t=s[3]; s[3]=s[7]; s[7]=s[11]; s[11]=s[15]; s[15]=t;
}
static void mixColumns(unsigned char *s) {
    for (int c=0;c<4;c++) {
        unsigned char a=s[c*4], b=s[c*4+1], cc=s[c*4+2], d=s[c*4+3];
        s[c*4]   = gmul(a,2)^gmul(b,3)^cc^d;
        s[c*4+1] = a^gmul(b,2)^gmul(cc,3)^d;
        s[c*4+2] = a^b^gmul(cc,2)^gmul(d,3);
        s[c*4+3] = gmul(a,3)^b^cc^gmul(d,2);
    }
}
static void invMixColumns(unsigned char *s) {
    for (int c=0;c<4;c++) {
        unsigned char a=s[c*4], b=s[c*4+1], cc=s[c*4+2], d=s[c*4+3];
        s[c*4]   = gmul(a,14)^gmul(b,11)^gmul(cc,13)^gmul(d,9);
        s[c*4+1] = gmul(a,9)^gmul(b,14)^gmul(cc,11)^gmul(d,13);
        s[c*4+2] = gmul(a,13)^gmul(b,9)^gmul(cc,14)^gmul(d,11);
        s[c*4+3] = gmul(a,11)^gmul(b,13)^gmul(cc,9)^gmul(d,14);
    }
}

static void aes256_encrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *rk) {
    unsigned char state[16];
    memcpy(state, in, 16);
    addRoundKey(state, rk);
    for (int round=1; round<14; round++) {
        subBytes(state);
        shiftRows(state);
        mixColumns(state);
        addRoundKey(state, rk + round*16);
    }
    subBytes(state);
    shiftRows(state);
    addRoundKey(state, rk + 14*16);
    memcpy(out, state, 16);
}
static void aes256_decrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *rk) {
    unsigned char state[16];
    memcpy(state, in, 16);
    addRoundKey(state, rk + 14*16);
    for (int round=13; round>=1; round--) {
        invShiftRows(state);
        invSubBytes(state);
        addRoundKey(state, rk + round*16);
        invMixColumns(state);
    }
    invShiftRows(state);
    invSubBytes(state);
    addRoundKey(state, rk);
    memcpy(out, state, 16);
}

/* ---------------- random ---------------- */
static void random_bytes(unsigned char *buf, size_t n) {
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) {
        size_t got = 0;
        while (got < n) {
            ssize_t r = read(fd, buf+got, n-got);
            if (r <= 0) break;
            got += (size_t)r;
        }
        close(fd);
        if (got == n) return;
    }
    for (size_t i=0;i<n;i++) buf[i] = (unsigned char)(rand() & 0xff);
}


/* ---------------- Vault ---------------- */
@interface KeychainVault () {
    NSString *_path;
    NSMutableArray *_items;
    NSString *_password;
    BOOL _locked;
}
@end

@implementation KeychainItem
- (NSString *)displayTitle {
    if (self.label.length) return self.label;
    if (self.service.length) return self.service;
    if (self.account.length) return self.account;
    return @"Item";
}
@end

@implementation KeychainVault
+ (instancetype)vaultWithPath:(NSString *)path {
    KeychainVault *v = [[KeychainVault alloc] init];
    v->_path = [path copy];
    v->_items = [NSMutableArray array];
    v->_locked = YES;
    return v;
}
- (NSString *)path { return _path; }
- (BOOL)isLocked { return _locked; }
- (BOOL)exists { return [[NSFileManager defaultManager] fileExistsAtPath:_path]; }

- (BOOL)unlockWithPassword:(NSString *)password error:(NSError **)error {
    _password = [password copy];
    _items = [NSMutableArray array];
    if (!self.exists) {
        /* First unlock of a new keychain defines its password: write the
         * (empty) vault now, bound to this password.  Leaving it uncreated
         * meant a later unlock accepted any password at all. */
        _locked = NO;
        if (![self saveAll:error]) {
            _locked = YES;
            return NO;
        }
        return YES;
    }
    NSData *fileData = [NSData dataWithContentsOfFile:_path];
    if (fileData.length < 4+4+16+16+4+32) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Corrupt keychain"}];
        _locked = YES;
        return NO;
    }
    const unsigned char *b = (const unsigned char *)fileData.bytes;
    // magic
    if (memcmp(b, "KCHN", 4) != 0) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Bad magic"}];
        _locked = YES;
        return NO;
    }
    b += 4;
    uint32_t version = (b[0]) | (b[1]<<8) | (b[2]<<16) | (b[3]<<24); b += 4;
    (void)version;
    unsigned char salt[16]; memcpy(salt, b, 16); b += 16;
    unsigned char iv[16]; memcpy(iv, b, 16); b += 16;
    uint32_t ctLen = (b[0]) | (b[1]<<8) | (b[2]<<16) | (b[3]<<24); b += 4;
    if (ctLen + 32 > fileData.length - (b - (const unsigned char *)fileData.bytes)) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Truncated"}];
        _locked = YES;
        return NO;
    }
    const unsigned char *ct = b; b += ctLen;
    const unsigned char *hmac = b;
    // derive
    const char *pw = [password UTF8String];
    unsigned char dk[64];
    pbkdf2_sha256((const unsigned char *)pw, strlen(pw), salt, 16, 2000, dk, 64);
    unsigned char *aesKey = dk;
    unsigned char *hmacKey = dk + 32;
    // verify hmac over salt+iv+ct
    size_t msgLen = 16+16+ctLen;
    unsigned char *msg = malloc(msgLen);
    memcpy(msg, salt, 16); memcpy(msg+16, iv, 16); memcpy(msg+32, ct, ctLen);
    unsigned char calc[32];
    hmac_sha256(hmacKey, 32, msg, msgLen, calc);
    free(msg);
    if (memcmp(calc, hmac, 32) != 0) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Incorrect password"}];
        _locked = YES;
        return NO;
    }
    // decrypt
    unsigned char *pt = malloc(ctLen);
    // CBC decrypt
    unsigned char prev[16]; memcpy(prev, iv, 16);
    size_t blocks = ctLen / 16;
    for (size_t bi=0; bi<blocks; bi++) {
        aes256_decrypt_block(ct + bi*16, pt + bi*16, aesKey);
        for (int j=0;j<16;j++) pt[bi*16+j] ^= prev[j];
        memcpy(prev, ct + bi*16, 16);
    }
    // PKCS7 unpad
    if (ctLen == 0) { free(pt); 
        _locked = NO; return YES; }
    unsigned char pad = pt[ctLen-1];
    if (pad == 0 || pad > 16) { free(pt); 
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:5 userInfo:@{NSLocalizedDescriptionKey:@"Bad padding"}];
        _locked = YES; return NO; }
    for (int i=0;i<pad;i++) if (pt[ctLen-1-i] != pad) { free(pt); 
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:5 userInfo:@{NSLocalizedDescriptionKey:@"Bad padding"}];
        _locked = YES; return NO; }
    size_t ptLen = ctLen - pad;
    NSData *plain = [NSData dataWithBytes:pt length:ptLen];
    free(pt);
    // deserialize
    NSString *errDesc = nil;
    NSPropertyListFormat fmt;
    id plist = [NSPropertyListSerialization propertyListFromData:plain mutabilityOption:NSPropertyListMutableContainers format:&fmt errorDescription:&errDesc];
    if (![plist isKindOfClass:[NSArray class]]) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:6 userInfo:@{NSLocalizedDescriptionKey: errDesc ?: @"Bad plist"}];
        _locked = YES;
        return NO;
    }
    for (NSDictionary *d in (NSArray *)plist) {
        KeychainItem *it = [[KeychainItem alloc] init];
        it.uuid = d[@"uuid"];
        it.itemClass = d[@"class"];
        it.service = d[@"service"];
        it.account = d[@"account"];
        it.label = d[@"label"];
        it.secretData = d[@"secret"];
        it.notes = d[@"notes"];
        it.created = d[@"created"];
        it.modified = d[@"modified"];
        [_items addObject:it];
    }
    _locked = NO;
    return YES;
}

- (void)lock {
    _locked = YES;
    [_items removeAllObjects];
    _password = nil;
}

- (BOOL)verifyPassword:(NSString *)password {
    if (_locked) return NO;
    return [_password isEqualToString:password];
}

- (BOOL)changePassword:(NSString *)oldPassword to:(NSString *)newPassword error:(NSError **)error {
    if (_locked) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:7 userInfo:@{NSLocalizedDescriptionKey:@"Locked"}];
        return NO;
    }
    if (![oldPassword isEqualToString:_password]) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Incorrect password"}];
        return NO;
    }
    _password = [newPassword copy];
    // re-encrypt by saving
    return [self saveAll:error];
}

- (BOOL)saveAll:(NSError **)error {
    if (_locked) return NO;
    // serialize items
    NSMutableArray *arr = [NSMutableArray array];
    for (KeychainItem *it in _items) {
        [arr addObject:@{
            @"uuid": it.uuid ?: @"",
            @"class": it.itemClass ?: @"password",
            @"service": it.service ?: @"",
            @"account": it.account ?: @"",
            @"label": it.label ?: @"",
            @"secret": it.secretData ?: [NSData data],
            @"notes": it.notes ?: @"",
            @"created": it.created ?: [NSDate date],
            @"modified": it.modified ?: [NSDate date],
        }];
    }
    NSString *errDesc = nil;
    NSData *plain = [NSPropertyListSerialization dataFromPropertyList:arr format:NSPropertyListXMLFormat_v1_0 errorDescription:&errDesc];
    if (!plain) {
        if (error) *error = [NSError errorWithDomain:@"Keychain" code:8 userInfo:@{NSLocalizedDescriptionKey: errDesc ?: @"Serialize failed"}];
        return NO;
    }
    // ensure parent dir
    NSString *dir = [_path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    unsigned char salt[16], iv[16];
    random_bytes(salt, 16);
    random_bytes(iv, 16);
    const char *pw = [_password UTF8String];
    unsigned char dk[64];
    pbkdf2_sha256((const unsigned char *)pw, strlen(pw), salt, 16, 2000, dk, 64);
    unsigned char *aesKey = dk;
    unsigned char *hmacKey = dk + 32;

    size_t ptLen = plain.length;
    size_t pad = 16 - (ptLen % 16);
    if (pad == 0) pad = 16;
    size_t ctLen = ptLen + pad;
    unsigned char *pt = malloc(ctLen);
    memcpy(pt, plain.bytes, ptLen);
    for (size_t i=ptLen;i<ctLen;i++) pt[i] = (unsigned char)pad;

    unsigned char *ct = malloc(ctLen);
    unsigned char prev[16]; memcpy(prev, iv, 16);
    for (size_t bi=0; bi<ctLen/16; bi++) {
        unsigned char block[16];
        for (int j=0;j<16;j++) block[j] = pt[bi*16+j] ^ prev[j];
        aes256_encrypt_block(block, ct + bi*16, aesKey);
        memcpy(prev, ct + bi*16, 16);
    }
    free(pt);

    // hmac
    size_t msgLen = 16+16+ctLen;
    unsigned char *msg = malloc(msgLen);
    memcpy(msg, salt, 16); memcpy(msg+16, iv, 16); memcpy(msg+32, ct, ctLen);
    unsigned char hmac[32];
    hmac_sha256(hmacKey, 32, msg, msgLen, hmac);
    free(msg);

    // write file
    NSMutableData *out = [NSMutableData data];
    [out appendBytes:"KCHN" length:4];
    uint32_t ver = 1;
    unsigned char vb[4] = { (unsigned char)(ver&0xff), (unsigned char)((ver>>8)&0xff), (unsigned char)((ver>>16)&0xff), (unsigned char)((ver>>24)&0xff) };
    [out appendBytes:vb length:4];
    [out appendBytes:salt length:16];
    [out appendBytes:iv length:16];
    uint32_t cl = (uint32_t)ctLen;
    unsigned char cb[4] = { (unsigned char)(cl&0xff), (unsigned char)((cl>>8)&0xff), (unsigned char)((cl>>16)&0xff), (unsigned char)((cl>>24)&0xff) };
    [out appendBytes:cb length:4];
    [out appendBytes:ct length:ctLen];
    [out appendBytes:hmac length:32];
    free(ct);

    BOOL ok = [out writeToFile:_path atomically:YES];
    if (!ok && error) *error = [NSError errorWithDomain:@"Keychain" code:9 userInfo:@{NSLocalizedDescriptionKey:@"Write failed"}];
    return ok;
}

- (NSArray *)allItems {
    if (_locked) return @[];
    return [_items copy];
}
- (NSArray *)itemsMatchingClass:(NSString *)cls {
    if (_locked) return @[];
    if (!cls || [cls isEqualToString:@"all"]) return [_items copy];
    NSMutableArray *res = [NSMutableArray array];
    for (KeychainItem *it in _items) {
        if ([it.itemClass isEqualToString:cls]) [res addObject:it];
    }
    return res;
}
- (BOOL)addItem:(KeychainItem *)item error:(NSError **)error {
    if (_locked) { if (error) *error = [NSError errorWithDomain:@"Keychain" code:7 userInfo:@{NSLocalizedDescriptionKey:@"Locked"}]; return NO; }
    if (!item.uuid) item.uuid = [NSString stringWithFormat:@"%ld-%u", (long)time(NULL), arc4random()];
    if (!item.created) item.created = [NSDate date];
    item.modified = [NSDate date];
    [_items addObject:item];
    return [self saveAll:error];
}
- (BOOL)updateItem:(KeychainItem *)item error:(NSError **)error {
    if (_locked) { if (error) *error = [NSError errorWithDomain:@"Keychain" code:7 userInfo:@{NSLocalizedDescriptionKey:@"Locked"}]; return NO; }
    for (NSUInteger i=0;i<_items.count;i++) {
        if ([((KeychainItem *)_items[i]).uuid isEqualToString:item.uuid]) {
            _items[i] = item;
            item.modified = [NSDate date];
            return [self saveAll:error];
        }
    }
    if (error) *error = [NSError errorWithDomain:@"Keychain" code:10 userInfo:@{NSLocalizedDescriptionKey:@"Not found"}];
    return NO;
}
- (BOOL)deleteItem:(KeychainItem *)item error:(NSError **)error {
    if (_locked) { if (error) *error = [NSError errorWithDomain:@"Keychain" code:7 userInfo:@{NSLocalizedDescriptionKey:@"Locked"}]; return NO; }
    for (NSUInteger i=0;i<_items.count;i++) {
        if ([((KeychainItem *)_items[i]).uuid isEqualToString:item.uuid]) {
            [_items removeObjectAtIndex:i];
            return [self saveAll:error];
        }
    }
    if (error) *error = [NSError errorWithDomain:@"Keychain" code:10 userInfo:@{NSLocalizedDescriptionKey:@"Not found"}];
    return NO;
}
@end
