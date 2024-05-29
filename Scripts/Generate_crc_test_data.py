import numpy as np
import argparse

parser = argparse.ArgumentParser(description='GT-Final OR board Pattern producer')
parser.add_argument('-p', '--polynomial', metavar='N', type=np.uint32, default=0x04c11db7,
                    help='CRC polynomyal')
parser.add_argument('-n', '--data_points', metavar='N', type=np.uint32, default=1000,
                    help='Data words to test')
parser.add_argument('-i', '--CRC_init', metavar='N', type=np.uint32, default=0xFFFFFFFF,
                    help='CRC init value')

args = parser.parse_args()

def reverse_poly_bits(x):

    x = np.array(x)
    n_bits = x.dtype.itemsize * 8

    x_reversed = np.zeros_like(x)
    for i in range(n_bits):
        x_reversed = (x_reversed << 1) | x & np.uint32(1)
        x >>= np.uint32(1)
    return x_reversed

def compute_crc(data,  poly, crc_init):
    poly_reversed = reverse_poly_bits(np.uint32(poly))
    crc = crc_init
    for i in range(4):
        crc ^= data>>(8*i)&0xFF
        for j in range(8):
            mask = -(crc & 1);
            crc = (crc >> 1) ^ (poly_reversed & mask);
    return crc

N = args.data_points
polynomial = args.polynomial
CRC_init = args.CRC_init

# Generate 16*N 32-bit words
test_data = np.random.uniform(0, 2**32-1, N)
test_data = np.uint32(test_data)
crc_value = []

crc = CRC_init
counter = 0
for value in test_data:
    crc = compute_crc(value, polynomial, crc)
    # every 16 drames append the crc value (512 bits data in)
    if counter == 15:
        crc_value.append(crc)
        counter = 0
    else:
        counter += 1
# append the last crc too if tot len is not multiple of 16
if len (test_data) % 16 != 0:
    crc_value.append(crc)

#test_data = np.reshape(test_data, (N, 16))
np.savetxt("../Sim/data_in_file.txt", np.int32(test_data), fmt='%i')
np.savetxt("../Sim/crc_out_file.txt", np.int32(crc_value), fmt='%-10i')
