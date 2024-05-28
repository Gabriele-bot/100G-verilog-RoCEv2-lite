library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package CRC32_pkg is

    constant CRC32_POLY  : std_logic_vector(31 downto 0) := X"04C11DB7";
    constant CRC32C_POLY : std_logic_vector(31 downto 0) := X"1EDC6F41";
    constant CRC32Q_POLY : std_logic_vector(31 downto 0) := X"814141AB";

    type matrix_32x64_t is array (31 downto 0) of std_logic_vector(63 downto 0);
    type matrix_32x32_t is array (31 downto 0) of std_logic_vector(31 downto 0);

    type gen_matrix_array_t is array (integer range <>) of matrix_32x32_t;

    function matrix_transpose(matrix : in matrix_32x32_t)
    return matrix_32x32_t;

    function matrix_vector_mul(matrix : in matrix_32x32_t; vector : in std_logic_vector(31 downto 0))
    return std_logic_vector;

    function matrix_matrix_mul(matrix_1 : in matrix_32x32_t; matrix_2 : in matrix_32x32_t)
    return matrix_32x32_t;

    function matrix_exp(matrix : in matrix_32x32_t; exp : natural)
    return matrix_32x32_t;

    function get_poly_matrix(poly : in std_logic_vector(31 downto 0))
    return matrix_32x64_t;

    function get_generator_matrix(poly : in std_logic_vector(31 downto 0))
    return matrix_32x64_t;

    function get_check_matrix(poly : in std_logic_vector(31 downto 0))
    return matrix_32x32_t;

    function gen_matrix_array(matrix : in matrix_32x32_t; n : integer)
    return gen_matrix_array_t;

    -- +============================================+
    -- |              LITTLE ENDIAN                 |
    -- +============================================+
    constant MATRIX_LE_IDX0 : matrix_32x32_t := (
        0  => X"04d101df",
        1  => X"09a203be",
        2  => X"1344077d",
        3  => X"26880efa",
        4  => X"4d101df4",
        5  => X"9a203be9",
        6  => X"3091760d",
        7  => X"6122ec1a",
        8  => X"c245d835",
        9  => X"805ab1b5",
        10 => X"046462b5",
        11 => X"08c8c56a",
        12 => X"11918ad4",
        13 => X"232315a9",
        14 => X"46462b53",
        15 => X"8c8c56a6",
        16 => X"1dc9ac92",
        17 => X"3b935924",
        18 => X"7726b249",
        19 => X"ee4d6493",
        20 => X"d84bc8f9",
        21 => X"b446902d",
        22 => X"6c5c2184",
        23 => X"d8b84309",
        24 => X"b5a187cc",
        25 => X"6f920e46",
        26 => X"df241c8c",
        27 => X"ba9938c7",
        28 => X"71e37051",
        29 => X"e3c6e0a3",
        30 => X"c35cc098",
        31 => X"826880ef"
    );

    constant CRC_MATRIX_EXP_ARRAY : gen_matrix_array_t(15 downto 0) := gen_matrix_array(MATRIX_LE_IDX0, 16);

    subtype crc32_word_t is std_logic_vector(31 downto 0);

end package CRC32_pkg;

package body CRC32_pkg is

    function matrix_transpose(matrix : in matrix_32x32_t)
    return matrix_32x32_t is
        variable matrix_transp : matrix_32x32_t;
    begin
        outer_loop : for i in 0 to MATRIX_LE_IDX0'high loop
            inner_loop : for j in 0 to MATRIX_LE_IDX0'high loop
                matrix_transp(j)(i) := matrix(i)(j);
            end loop;
        end loop;
        return matrix_transp;
    end function matrix_transpose;

    function matrix_vector_mul(matrix : in matrix_32x32_t; vector : in std_logic_vector(31 downto 0))
    return std_logic_vector is
        variable prod : std_logic_vector(vector'high downto 0);
    begin
        gen_prod_l : for i in 0 to MATRIX_LE_IDX0'high loop
            prod(i) := xor (matrix(i) and vector);
        end loop;
        return prod;
    end function matrix_vector_mul;

    function matrix_matrix_mul(matrix_1 : in matrix_32x32_t; matrix_2 : in matrix_32x32_t)
    return matrix_32x32_t is
        variable matrix_prod       : matrix_32x32_t;
        variable matrix_transposed : matrix_32x32_t;
    begin
        matrix_transposed := matrix_transpose(matrix_2);
        outer_loop : for i in 0 to MATRIX_LE_IDX0'high loop
            inner_loop : for j in 0 to MATRIX_LE_IDX0'high loop
                matrix_prod(i)(j) := xor (matrix_1(i) and matrix_transposed(j));
            end loop;
        end loop;
        return matrix_prod;
    end function matrix_matrix_mul;

    function matrix_exp(matrix : in matrix_32x32_t; exp : natural)
    return matrix_32x32_t is
        variable matrix_result : matrix_32x32_t := matrix;
    begin
        mult_loop : for i in 0 to exp - 1 loop
            matrix_result := matrix_matrix_mul(matrix_result, matrix);
        end loop;
        return matrix_result;
    end function matrix_exp;

    function get_poly_matrix(poly : in std_logic_vector(31 downto 0))
    return matrix_32x64_t is
        variable poly_matrix_shift : matrix_32x64_t;
    begin

        -- Generate a matrix from the poly just shifting it to the right
        -- Remember the one at the end of the poly! (Position 63 in the matrix)
        poly_matrix_shift(0)(63)           := '1';
        poly_matrix_shift(0)(62 downto 31) := poly;
        poly_matrix_shift(0)(30 downto 0)  := (others => '0');

        gen_loop : for i in 1 to 31 loop
            poly_matrix_shift(i) := poly_matrix_shift(i - 1) srl 1;
        end loop;

        return poly_matrix_shift;
    end function get_poly_matrix;

    function get_generator_matrix(poly : in std_logic_vector(31 downto 0))
    return matrix_32x64_t is
        variable poly_matrix_shift    : matrix_32x64_t := get_poly_matrix(poly);
        variable generator_matrix_res : matrix_32x64_t := get_poly_matrix(poly);
    begin

        -- Produce the generator matrix, goal is to have an identity block (32x32) on the left
        -- It's achieved xoring rows of the poly matrix
        xor_loop_row : for j in 0 to 31 loop
            xor_loop_column : for k in 0 to 31 loop
                if j < k then
                    if generator_matrix_res(j)(63 - k) then
                        generator_matrix_res(j) := generator_matrix_res(j) xor poly_matrix_shift(k);
                    end if;
                end if;
            end loop;
        end loop;
        return generator_matrix_res;
    end function get_generator_matrix;

    function get_check_matrix(poly : in std_logic_vector(31 downto 0))
    return matrix_32x32_t is
        variable generator_matrix : matrix_32x64_t := get_generator_matrix(poly);
        variable right_block      : matrix_32x32_t;
        variable check_matrix     : matrix_32x32_t;
    begin

        gen_loop : for i in 0 to 31 loop
            right_block(i) := generator_matrix(i)(31 downto 0);
        end loop;

        -- Get the far right block of the gen matrix and transpose it
        loop_row : for j in 0 to 31 loop
            loop_column : for k in 0 to 31 loop
                check_matrix(31 - j)(k) := right_block(k)(j);
            end loop;
        end loop;
        return check_matrix;
    end function get_check_matrix;

    function gen_matrix_array(matrix : in matrix_32x32_t; n : integer)
    return gen_matrix_array_t is
        variable matrix_array_result : gen_matrix_array_t(n - 1 downto 0) := (others => matrix);
    begin
        gen_loop : for i in 1 to n - 1 loop
            matrix_array_result(i) := matrix_exp(matrix, i);
        end loop;
        return matrix_array_result;
    end function gen_matrix_array;

end package body CRC32_pkg;
