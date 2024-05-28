library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.CRC32_pkg.all;

entity CRC32_D512_matrix_pipeline is
    generic(
        REVERSE_INPUT  : boolean                       := FALSE;
        REVERSE_RESULT : boolean                       := FALSE;
        FINXOR         : std_logic_vector(31 downto 0) := X"00000000"
    );
    port(
        clk           : in  std_logic;
        rst           : in  std_logic;
        crcIn         : in  std_logic_vector(31 downto 0); -- It needs to be fed 1 clock cycle before the expected output
        data_in       : in  std_logic_vector(511 downto 0);
        keep_in       : in  std_logic_vector(63 downto 0);
        valid_in      : in  std_logic;
        crcOut        : out std_logic_vector(31 downto 0);
        valid_crc_out : out std_logic
    );
end entity CRC32_D512_matrix_pipeline;

architecture RTL of CRC32_D512_matrix_pipeline is

    constant LATENCY : natural := 16;

    signal out_partial_crc : crc32_word_t;
    signal out_crc         : crc32_word_t;

    signal valid_shreg : std_logic_vector(LATENCY downto 0);

    type keep_pipeline_stage_t is array (LATENCY downto 0) of std_logic_vector(63 downto 0);
    signal keep_shreg : keep_pipeline_stage_t;

    signal data : std_logic_vector(511 downto 0);

    type partial_crc_t is array (15 downto 0) of crc32_word_t;
    signal partial_crc_data : partial_crc_t;
    signal partial_crc_seed : partial_crc_t;

    type crc_pipeline_stage_t is array (7 downto 0) of crc32_word_t;
    signal crc_stage : crc_pipeline_stage_t;

    type data_pipeline_stage_t is array (8 downto 0) of std_logic_vector(511 downto 0);
    signal data_stage : data_pipeline_stage_t;

begin

    --TODO REVERSE also keep!!!
    everse_in_g : if REVERSE_INPUT generate
        reverse_g : for i in 0 to 511 generate
            data(i) <= data_in(511 - i);
        end generate;
    else generate
        data <= data_in;
    end generate;

    data_stage(0) <= data;
    process(clk)
    begin
        if rising_edge(clk) then
            data_stage(data_stage'high downto 1) <= data_stage(data_stage'high - 1 downto 0);
        end if;
    end process;

    valid_shreg(0) <= valid_in;
    process(clk)
    begin
        if rising_edge(clk) then
            valid_shreg(valid_shreg'high downto 1) <= valid_shreg(valid_shreg'high - 1 downto 0);
        end if;
    end process;

    keep_shreg(0) <= keep_in;
    process(clk)
    begin
        if rising_edge(clk) then
            keep_shreg(keep_shreg'high downto 1) <= keep_shreg(keep_shreg'high - 1 downto 0);
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if keep_shreg(0)(3 downto 0) = X"F" then
                crc_stage(0) <= matrix_vector_mul(CRC_MATRIX_EXP_ARRAY(0), data_stage(0)(31 downto 0));
            else                        --this shuld never happen
                crc_stage(0) <= (others => '0');
            end if;
        end if;
    end process;
    
    -- this is not clocked !!!
    gen_crc_seed_matrix_vector_mul_g : for i in 0 to 15 generate
        process(crcIn) is
        begin
            partial_crc_seed(15 - i) <= matrix_vector_mul(CRC_MATRIX_EXP_ARRAY(i), crcIn);
        end process;
    end generate;

    gen_crc_stage_g : for i in 1 to 14 generate
        process(clk)
            variable data_xor_crc : crc32_word_t;
        begin
            if rising_edge(clk) then
                if keep_shreg(i)((i + 1) * 4 - 1 downto (i) * 4) = X"F" and keep_shreg(i)((i + 2) * 4 - 1 downto (i+1) * 4) = X"0"  then
                    data_xor_crc := data_stage(i)((i + 1) * 32 - 1 downto i * 32) xor crc_stage(i-1);
                    crc_stage(i) <= matrix_vector_mul(CRC_MATRIX_EXP_ARRAY(0), data_xor_crc) xor partial_crc_seed(i);
                elsif keep_shreg(i)((i + 1) * 4 - 1 downto (i) * 4) = X"F" and keep_shreg(i)((i + 2) * 4 - 1 downto (i+1) * 4) = X"F"then
                    data_xor_crc := data_stage(i)((i + 1) * 32 - 1 downto i * 32) xor crc_stage(i-1);
                    crc_stage(i) <= matrix_vector_mul(CRC_MATRIX_EXP_ARRAY(0), data_xor_crc);
                else
                    crc_stage(i) <= crc_stage(i-1);
                end if;
            end if;
        end process;
    end generate;

end architecture RTL;
