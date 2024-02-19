# Copyright 2019 The NATS Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import base64
import binascii
import ed25519

# PREFIX_BYTE_SEED is the version byte used for encoded NATS Seeds
PREFIX_BYTE_SEED     = 18 << 3    # Base32-encodes to 'S...'

# PREFIX_BYTE_PRIVATE is the version byte used for encoded NATS Private keys
PREFIX_BYTE_PRIVATE  = 15 << 3    # Base32-encodes to 'P...'

# PREFIX_BYTE_SERVER is the version byte used for encoded NATS Servers
PREFIX_BYTE_SERVER   = 13 << 3    # Base32-encodes to 'N...'

# PREFIX_BYTE_CLUSTER is the version byte used for encoded NATS Clusters
PREFIX_BYTE_CLUSTER  = 2 << 3     # Base32-encodes to 'C...'

# PREFIX_BYTE_OPERATOR is the version byte used for encoded NATS Operators
PREFIX_BYTE_OPERATOR = 14 << 3    # Base32-encodes to 'O...'

# PREFIX_BYTE_ACCOUNT is the version byte used for encoded NATS Accounts
PREFIX_BYTE_ACCOUNT  = 0          # Base32-encodes to 'A...'

# PREFIX_BYTE_USER is the version byte used for encoded NATS Users
PREFIX_BYTE_USER     = 20 << 3    # Base32-encodes to 'U...'

def from_seed(seed):
    _, raw_seed = decode_seed(seed)
    keys = ed25519.SigningKey(raw_seed)
    del raw_seed
    return KeyPair(keys=keys, seed=seed)

def decode_seed(src):
    # Add missing padding if required.
    padding = bytearray()
    padding += b'=' * (-len(src) % 8)

    try:
        base32_decoded = base64.b32decode(src+padding)
        raw = base32_decoded[:(len(base32_decoded)-2)]
    except binascii.Error:
        raise ErrInvalidSeed()

    if len(raw) < 32:
        raise ErrInvalidSeed()

    # 248 = 11111000
    b1 = raw[0] & 248

    # 7 = 00000111
    b2 = (raw[0] & 7) << 5 | ((raw[1] & 248) >> 3)

    if b1 != PREFIX_BYTE_SEED:
        raise ErrInvalidSeed()
    elif not valid_public_prefix_byte(b2):
        raise ErrInvalidPrefixByte()

    prefix = b2
    result = raw[2:(len(raw))]
    return (prefix, result)

def valid_public_prefix_byte(prefix):
    if prefix == PREFIX_BYTE_OPERATOR \
       or prefix == PREFIX_BYTE_SERVER \
       or prefix == PREFIX_BYTE_CLUSTER \
       or prefix == PREFIX_BYTE_ACCOUNT \
       or prefix == PREFIX_BYTE_USER:
        return True
    else:
        return False

def valid_prefix_byte(prefix):
    if prefix == PREFIX_BYTE_OPERATOR \
       or prefix == PREFIX_BYTE_SERVER \
       or prefix == PREFIX_BYTE_CLUSTER \
       or prefix == PREFIX_BYTE_ACCOUNT \
       or prefix == PREFIX_BYTE_USER \
       or prefix == PREFIX_BYTE_SEED \
       or prefix == PREFIX_BYTE_PRIVATE:
        return True
    else:
        return False

class KeyPair(object):

    def __init__(self,
                 seed=None,
                 keys=None,
                 public_key=None,
                 private_key=None,
                 ):
        """
        NKEYS KeyPair used to sign and verify data.

        :param seed: The seed as a bytearray used to create the keypair.
        :param keys: The keypair that can be used for signing.
        :param public_key: The public key as a bytearray.

        :rtype: nkeys.Keypair
        :return: A KeyPair that can be used to sign and verify data.
        """
        self._seed = seed
        self._keys = keys
        self._public_key = public_key
        self._private_key = private_key

    def sign(self, input):
        """
        NKEYS KeyPair used to sign and verify data.

        :param input: The payload in bytes to sign.

        :rtype bytes:
        :return: The raw bytes representing the signed data.
        """
        return self._keys.sign(input)

    def verify(self, input, sig):
        """
        :param input: The payload in bytes that was signed.
        :param sig: The signature in bytes that will be verified.

        :rtype bool:
        :return: boolean expressing that the signature is valid.
        """
        kp = self._keys.get_verifying_key()

        try:
            kp.verify(sig, input)
            return True
        except ed25519.BadSignatureError:
            raise ErrInvalidSignature()

    @property
    def public_key(self):
        """
        Return the encoded public key associated with the KeyPair.

        :rtype bytes:
        :return: public key associated with the key pair
        """
        # If already generated then just return.
        if self._public_key is not None:
            return self._public_key

        # Get the public key from the seed to verify later.
        prefix, _ = decode_seed(self._seed)

        kp = self._keys.get_verifying_key()
        src = bytearray(kp.to_bytes())
        src.insert(0, prefix)

        # Calculate and include crc16 checksum
        crc = crc16(src)
        crc_bytes = (crc).to_bytes(2, byteorder='little')
        src.extend(crc_bytes)

        # Encode to base32
        base32_encoded = base64.b32encode(src)
        del src
        self._public_key = base32_encoded
        return self._public_key

    @property
    def private_key(self):
        if self._private_key is not None:
            return self._private_key

        src = bytearray(self._keys.to_bytes())
        src.insert(0, PREFIX_BYTE_PRIVATE)

        # Calculate and include crc16 checksum
        crc = crc16(src)
        crc_bytes = (crc).to_bytes(2, byteorder='little')
        src.extend(crc_bytes)

        base32_encoded = base64.b32encode(src)
        del src
        self._private_key = base32_encoded[:(len(base32_encoded)-4)]
        return self._private_key

    @property
    def seed(self):
        if not hasattr(self, "_seed"):
            raise ErrInvalidSeed()
        return self._seed

    def wipe(self):
        self._seed = None
        self._keys = None
        self._public_key = None
        self._private_key = None
        del self._seed
        del self._keys
        del self._public_key
        del self._private_key

CRC16TAB = [
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7,
    0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
    0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6,
    0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de,
    0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485,
    0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d,
    0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4,
    0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc,
    0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823,
    0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b,
    0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12,
    0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a,
    0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41,
    0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49,
    0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70,
    0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78,
    0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f,
    0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067,
    0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e,
    0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256,
    0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d,
    0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
    0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c,
    0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634,
    0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab,
    0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3,
    0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a,
    0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92,
    0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9,
    0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1,
    0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8,
    0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0,
    ]

def crc16(data):
    crc = 0
    for c in data:
        crc = ((crc << 8) & 0xffff) ^ CRC16TAB[((crc>>8)^c)&0x00FF]
    return crc

class NkeysError(Exception):
    pass

class ErrInvalidSeed(NkeysError):
    def __str__(self):
        return "nkeys: invalid seed"

class ErrInvalidPrefixByte(NkeysError):
    def __str__(self):
        return "nkeys: invalid prefix byte"

class ErrInvalidKey(NkeysError):
    def __str__(self):
        return "nkeys: invalid key"

class ErrInvalidPublicKey(NkeysError):
    def __str__(self):
        return "nkeys: invalid public key"

class ErrInvalidSeedLen(NkeysError):
    def __str__(self):
        return "nkeys: invalid seed length"

class ErrInvalidSeed(NkeysError):
    def __str__(self):
        return "nkeys: invalid seed"

class ErrInvalidEncoding(NkeysError):
    def __str__(self):
        return "nkeys: invalid encoded key"

class ErrInvalidSignature(NkeysError):
    def __str__(self):
        return "nkeys: signature verification failed"

class ErrCannotSign(NkeysError):
    def __str__(self):
        return "nkeys: can not sign, no private key available"

class ErrPublicKeyOnly(NkeysError):
    def __str__(self):
        return "nkeys: no seed or private key available"
