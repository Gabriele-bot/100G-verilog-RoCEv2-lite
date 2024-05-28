# CRC32 VHDL block

## Computation (example with crc4 and data width=4)
For a CRC4 and data width=4 a generator matrix needs to be 4x8.  

### Poly Matrix
Starting from a given polynomyal, the `poly_matrix` is computed by right shifting the polynomyal by 1 for each row.  
poly = $x^4+x^2+x^1+1$  
Or in binary format: `10111`  
The `poly_matrix` is the following:
```
1 0 1 1 1 0 0 0 
0 1 0 1 1 1 0 0 
0 0 1 0 1 1 1 0 
0 0 0 1 0 1 1 1 
```
### Generator Matrix
The `generator_matrix` should have an identity matrix on the far left block:
```
1 0 0 0 - - - - 
0 1 0 0 - - - - 
0 0 1 0 - - - -
0 0 0 1 - - - - 
```
To achieve this we start from the first row and XOR the next if 1 is in its position:
e.g. row 0 we XOR `row 0` with `row 2`: `10111000 xor 00101110 = 10010110`, now we XOR the result with `row 3` and so on for all the rows.
The result will be:
```
1 0 0 0 0 0 0 1	
0 1 0 0 1 0 1 1 
0 0 1 0 1 1 1 0 
0 0 0 1 0 1 1 1
```

### Check Matrix
The `check_matrix` can be generated directly from the generator matrix. We have to take the far rigth block of the genrator matrix and transpose it:
```
0 0 0 1     0 1 1 0 
1 0 1 1 --> 0 0 1 1  
1 1 1 0 --> 0 1 1 1  
0 1 1 1     1 1 0 1 
```

### CRC computation
Now with the matrix computed we are able to compute the CRC value for a given data:  
$CRC4 = [M] \times D + CRC_{init}$  
Where:  
- `CRC4`     is the result
- `[M]`      is the check matrix
- `D`        is the data in
- `CRC_init` is the CRC initial value, e.g. 0xF for the first data in
```
0 1 1 0    D[0]   D[1] xor D[2] 
0 0 1 1  X D[1] = D[2] xor D[3]
0 1 1 1  X D[2] = D[1] xor D[2] xor D[3]
1 1 0 1    D[3]   D[0] xor D[1] xor D[3]
```
For example with `DATA=0110` we obatin `0101`

## VHDL block
Coming soon
