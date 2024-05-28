library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.CRC32_pkg.all;

entity CRC32_D512_matrix is
    generic(
        CRC_POLY       : std_logic_vector(31 downto 0) := CRC32_POLY;
        CRC_INIT       : std_logic_vector(31 downto 0) := X"FFFFFFFF";
        REVERSE_RESULT : boolean                       := FALSE;
        FINXOR         : std_logic_vector(31 downto 0) := X"00000000"
    );
    port(
        clk           : in  std_logic;
        rst           : in  std_logic;
        rst_crc       : in  std_logic;
        data_in       : in  std_logic_vector(511 downto 0);
        keep_in       : in  std_logic_vector(63 downto 0);
        valid_in      : in  std_logic;
        crcOut        : out std_logic_vector(31 downto 0);
        valid_crc_out : out std_logic
    );
end entity CRC32_D512_matrix;

architecture RTL of CRC32_D512_matrix is

    constant CRC32_POLY_MATRIX  : matrix_32x64_t                := get_poly_matrix(CRC_POLY);
    constant CRC32_GEN_MATRIX   : matrix_32x64_t                := get_generator_matrix(CRC_POLY);
    constant CRC32_CHECK_MATRIX : matrix_32x32_t                := get_check_matrix(CRC_POLY);

    constant MATRIX_ARRAY : gen_matrix_array_t := gen_matrix_array(CRC32_CHECK_MATRIX, 16);

    signal out_partial_crc : crc32_word_t;
    signal out_crc         : crc32_word_t;

    signal valid_shreg : std_logic_vector(3 downto 0);

    type keep_pipeline_stage_t is array (3 downto 0) of std_logic_vector(63 downto 0);
    signal keep_shreg : keep_pipeline_stage_t;

    signal data : std_logic_vector(511 downto 0);
    signal keep : std_logic_vector(63 downto 0);

    type partial_crc_t is array (15 downto 0) of crc32_word_t;
    signal partial_crc_data : partial_crc_t;

begin

    data <= data_in;
    keep <= keep_in;

    valid_shreg(0) <= valid_in;
    process(clk)
    begin
        if rising_edge(clk) then
            valid_shreg(valid_shreg'high downto 1) <= valid_shreg(valid_shreg'high - 1 downto 0);
        end if;
    end process;

    keep_shreg(0) <= keep;
    process(clk)
    begin
        if rising_edge(clk) then
            keep_shreg(keep_shreg'high downto 1) <= keep_shreg(keep_shreg'high - 1 downto 0);
        end if;
    end process;

    gen_crc_data_matrix_vector_mul_g : for i in 0 to 15 generate
        process(clk) is
        begin
            if rising_edge(clk) then
                case keep_shreg(0) is
                    when X"000000000000000F" => --Should not happen
                        partial_crc_data(0)           <= matrix_vector_mul(MATRIX_ARRAY(0), data(31 downto 0));
                        partial_crc_data(15 downto 1) <= (others => (others => '0'));
                    when X"00000000000000FF" =>
                        loop_2 : for i in 0 to 1 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(1 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 2) <= (others => (others => '0'));
                    when X"0000000000000FFF" =>
                        loop_3 : for i in 0 to 2 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(2 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 3) <= (others => (others => '0'));
                    when X"000000000000FFFF" =>
                        loop_4 : for i in 0 to 3 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(3 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 4) <= (others => (others => '0'));
                    when X"00000000000FFFFF" =>
                        loop_5 : for i in 0 to 4 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(4 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 5) <= (others => (others => '0'));
                    when X"0000000000FFFFFF" =>
                        loop_6 : for i in 0 to 5 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(5 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 6) <= (others => (others => '0'));
                    when X"000000000FFFFFFF" =>
                        loop_7 : for i in 0 to 6 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(6 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 7) <= (others => (others => '0'));
                    when X"00000000FFFFFFFF" =>
                        loop_8 : for i in 0 to 7 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(7 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 8) <= (others => (others => '0'));
                    when X"0000000FFFFFFFFF" =>
                        loop_9 : for i in 0 to 8 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(8 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 9) <= (others => (others => '0'));
                    when X"000000FFFFFFFFFF" =>
                        loop_10 : for i in 0 to 9 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(9 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 10) <= (others => (others => '0'));
                    when X"00000FFFFFFFFFFF" =>
                        loop_11 : for i in 0 to 10 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(10 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 11) <= (others => (others => '0'));
                    when X"0000FFFFFFFFFFFF" =>
                        loop_12 : for i in 0 to 11 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(11 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 12) <= (others => (others => '0'));
                    when X"000FFFFFFFFFFFFF" =>
                        loop_13 : for i in 0 to 12 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(12 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 13) <= (others => (others => '0'));
                    when X"00FFFFFFFFFFFFFF" =>
                        loop_14 : for i in 0 to 13 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(13 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15 downto 14) <= (others => (others => '0'));
                    when X"0FFFFFFFFFFFFFFF" =>
                        loop_15 : for i in 0 to 14 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(14 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                        partial_crc_data(15) <= (others => '0');
                    when X"FFFFFFFFFFFFFFFF" =>
                        loop_16 : for i in 0 to 15 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(15 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                    when others =>
                        loop_others : for i in 0 to 15 loop
                            partial_crc_data(i) <= matrix_vector_mul(MATRIX_ARRAY(15 - i), data(32 * (i + 1) - 1 downto 32 * i));
                        end loop;
                end case;
            end if;
        end process;
    end generate;

    out_partial_p : process(clk) is
        variable crc_data_comp : crc32_word_t;
    begin
        if rising_edge(clk) then
            crc_data_comp   := (others => '0');
            crc_loop : for i in 0 to 15 loop
                if keep_shreg(1)((i + 1) * 4 - 1 downto i * 4) = X"F" then
                    crc_data_comp := crc_data_comp xor partial_crc_data(i);
                else
                    crc_data_comp := crc_data_comp;
                end if;
            end loop;
            out_partial_crc <= crc_data_comp;

        end if;
    end process;

    out_total_p : process(clk) is
    begin
        if rising_edge(clk) then
            if rst then
                out_crc <= CRC_INIT;
            else
                case keep_shreg(2) is
                    when X"000000000000000F" => --Should not happen
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(0), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(0), out_crc);
                        end if;
                    when X"00000000000000FF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(1), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(1), out_crc);
                        end if;
                    when X"0000000000000FFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(2), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(2), out_crc);
                        end if;
                    when X"000000000000FFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(3), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(3), out_crc);
                        end if;
                    when X"00000000000FFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(4), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(4), out_crc);
                        end if;
                    when X"0000000000FFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(5), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(5), out_crc);
                        end if;
                    when X"000000000FFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(6), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(6), out_crc);
                        end if;
                    when X"00000000FFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(7), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(7), out_crc);
                        end if;
                    when X"0000000FFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(8), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(8), out_crc);
                        end if;
                    when X"000000FFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(9), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(9), out_crc);
                        end if;
                    when X"00000FFFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(10), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(10), out_crc);
                        end if;
                    when X"0000FFFFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(11), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(11), out_crc);
                        end if;
                    when X"000FFFFFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(12), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(12), out_crc);
                        end if;
                    when X"00FFFFFFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(13), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(13), out_crc);
                        end if;
                    when X"0FFFFFFFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(14), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(14), out_crc);
                        end if;
                    when X"FFFFFFFFFFFFFFFF" =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(15), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(15), out_crc);
                        end if;
                    when others =>
                        if rst_crc then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(15), CRC_INIT);
                        elsif valid_shreg(2) then
                            out_crc <= out_partial_crc xor matrix_vector_mul(MATRIX_ARRAY(15), out_crc);
                        end if;
                end case;
            end if;
        end if;
    end process;

    reverse_out_g : if REVERSE_RESULT generate
        reverse_g : for i in 0 to 31 generate
            crcOut(i) <= out_crc(31 - i) xor FINXOR(31 - i);
        end generate;
    else generate
        crcOut <= out_crc xor FINXOR;
    end generate;

    valid_crc_out <= valid_shreg(valid_shreg'high);

end architecture RTL;
