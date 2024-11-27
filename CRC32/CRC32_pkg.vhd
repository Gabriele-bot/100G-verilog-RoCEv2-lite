library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package CRC32_pkg is

    -- +============================================+
    -- |             !LITTLE ENDIAN!                |
    -- +============================================+

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

    function keep2blocknumber_64(keep_value : in std_logic_vector(63 downto 0))
    return integer;

    function keep2blocknumber_8(keep_value : in std_logic_vector(7 downto 0))
    return integer;

    --constant MATRIX_CRC32_LE_IDX0   : matrix_32x32_t                  := get_check_matrix(CRC32_POLY);
    --constant CRC32_MATRIX_EXP_ARRAY : gen_matrix_array_t(15 downto 0) := gen_matrix_array(MATRIX_CRC32_LE_IDX0, 16);

    subtype crc32_word_t is std_logic_vector(31 downto 0);

end package CRC32_pkg;

package body CRC32_pkg is

    function matrix_transpose(matrix : in matrix_32x32_t)
    return matrix_32x32_t is
        variable matrix_transp : matrix_32x32_t;
    begin
        outer_loop : for i in 0 to matrix'high loop
            inner_loop : for j in 0 to matrix'high loop
                matrix_transp(j)(i) := matrix(i)(j);
            end loop;
        end loop;
        return matrix_transp;
    end function matrix_transpose;

    function matrix_vector_mul(matrix : in matrix_32x32_t; vector : in std_logic_vector(31 downto 0))
    return std_logic_vector is
        variable prod : std_logic_vector(vector'high downto 0);
    begin
        gen_prod_l : for i in 0 to matrix'high loop
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
        outer_loop : for i in 0 to matrix_1'high loop
            inner_loop : for j in 0 to matrix_transposed'high loop
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

    function keep2blocknumber_64(keep_value : in std_logic_vector(63 downto 0))
    return integer is
        variable index : integer := 0;
    begin
        case keep_value is
            
            when X"--------------0F" => index := 1;
            when X"-------------0F-" => index := 2;
            when X"------------0F--" => index := 3;
            when X"-----------0F---" => index := 4;
            when X"----------0F----" => index := 5;
            when X"---------0F-----" => index := 6;
            when X"--------0F------" => index := 7;
            when X"-------0F-------" => index := 8;
            when X"------0F--------" => index := 9;
            when X"-----0F---------" => index := 10;
            when X"----0F----------" => index := 11;
            when X"---0F-----------" => index := 12;
            when X"--0F------------" => index := 13;
            when X"-0F-------------" => index := 14;
            when X"0F--------------" => index := 15;
            when X"F---------------" => index := 16;
            when others              => index := 1;
        end case;
        return index;
    end function keep2blocknumber_64;

    function keep2blocknumber_8(keep_value : in std_logic_vector(7 downto 0))
    return integer is
        variable index : integer := 0;
    begin
        case keep_value is
            when X"-0" => index := 0;
            when X"0F" => index := 1;
            when X"F-" => index := 2;
            when others      => index := 0;
        end case;
        return index;
    end function keep2blocknumber_8;

end package body CRC32_pkg;
