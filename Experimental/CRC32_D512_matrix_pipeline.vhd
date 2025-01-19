library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.CRC32_pkg.all;

entity CRC32_D512_matrix_pipeline is
    generic(
        DATA_WIDTH     : integer                       := 512;
        CRC_POLY       : std_logic_vector(31 downto 0) := CRC32_POLY;
        CRC_INIT       : std_logic_vector(31 downto 0) := X"FFFFFFFF";
        REVERSE_INPUT  : boolean                       := FALSE;
        REVERSE_RESULT : boolean                       := FALSE;
        FINXOR         : std_logic_vector(31 downto 0) := X"00000000"
    );
    port(
        clk           : in  std_logic;
        rst           : in  std_logic;
        rst_crc       : in  std_logic;
        data_in       : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        keep_in       : in  std_logic_vector(DATA_WIDTH / 8 - 1 downto 0);
        valid_in      : in  std_logic;
        crcOut        : out std_logic_vector(31 downto 0);
        valid_crc_out : out std_logic
    );
end entity CRC32_D512_matrix_pipeline;

architecture RTL of CRC32_D512_matrix_pipeline is

    constant LATENCY : natural := DATA_WIDTH / 32;

    --constant CRC32_POLY_MATRIX  : matrix_32x64_t := get_poly_matrix(CRC_POLY);
    --constant CRC32_GEN_MATRIX   : matrix_32x64_t := get_generator_matrix(CRC_POLY);
    constant CRC32_CHECK_MATRIX : matrix_32x32_t := get_check_matrix(CRC_POLY);

    constant MATRIX_ARRAY : gen_matrix_array_t := gen_matrix_array(CRC32_CHECK_MATRIX, 16);

    --signal out_partial_crc : crc32_word_t;
    signal out_crc         : crc32_word_t;

    signal valid_shreg : std_logic_vector(LATENCY downto 0) := (others => '0');

    type keep_pipeline_stage_t is array (LATENCY downto 0) of std_logic_vector(DATA_WIDTH / 8 - 1 downto 0);
    signal keep_shreg : keep_pipeline_stage_t := (others => (others => '0'));

    signal data : std_logic_vector(DATA_WIDTH - 1 downto 0);

    type partial_crc_t is array (LATENCY downto 0) of crc32_word_t;
    --signal partial_crc_data      : partial_crc_t;
    signal partial_crc_init_seed : partial_crc_t := (others => CRC_INIT);
    signal partial_crc_last_seed : partial_crc_t := (others => CRC_INIT);
    signal crc_seed              : crc32_word_t;
    signal computation_ongoing   : std_logic := '0'; 

    type crc_pipeline_stage_t is array (LATENCY downto 0) of crc32_word_t;
    signal crc_stage : crc_pipeline_stage_t := (others => X"DEADBEEF");

    type data_pipeline_stage_t is array (LATENCY downto 0) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal data_stage : data_pipeline_stage_t := (others => (others => '0'));

    --signal test_in_value : std_logic_vector(31 downto 0);

    signal keep_block_number : integer range 1 to DATA_WIDTH / 32;

begin

    gen_keep_to_block : if DATA_WIDTH = 512 generate
        process(clk) is
        begin
            if rising_edge(clk) then
                if valid_shreg(LATENCY - 2) then
                    keep_block_number <= keep2blocknumber_64(keep_shreg(LATENCY - 2));
                end if;
            end if;
        end process;
    elsif DATA_WIDTH = 64 generate
        process(clk) is
        begin
            if rising_edge(clk) then
                if valid_shreg(LATENCY - 2) then
                    keep_block_number <= keep2blocknumber_8(keep_shreg(LATENCY - 2));
                end if;
            end if;
        end process;
    else generate
        keep_block_number <= 0;
    end generate;

    --TODO REVERSE also keep!!!
    reverse_in_g : if REVERSE_INPUT generate
        reverse_g : for i in 0 to DATA_WIDTH - 1 generate
            data(i) <= data_in(DATA_WIDTH - 1 - i);
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
            if (valid_shreg(valid_shreg'high-1) and not computation_ongoing) then
                computation_ongoing <= '1';
            elsif computation_ongoing and rst_crc then
                computation_ongoing <= '0';
            end if;
        end if;
    end process;

    -- this is not clocked !!!
    -- compute every stage of the init crc out
    gen_crc_seed_matrix_vector_mul_g : for i in 0 to LATENCY - 1 generate
        partial_crc_init_seed(i) <= matrix_vector_mul(MATRIX_ARRAY(i), CRC_INIT);
        partial_crc_last_seed(i) <= matrix_vector_mul(MATRIX_ARRAY(i), out_crc);
    end generate;

    -- select which CRC should be XORed with the result
    -- partial_crc_init_seed when first frame in packet
    -- partial_crc_last_seed otherwise
    --crc_seed <= partial_crc_init_seed(keep_block_number - 1) when (rst_crc or not valid_crc_out) else partial_crc_last_seed(keep_block_number - 1);
    crc_seed <= partial_crc_init_seed(keep_block_number - 1) when (not computation_ongoing) else partial_crc_last_seed(keep_block_number - 1);

    crc_stage_0 : process(clk)
    begin
        if rising_edge(clk) then
            if valid_shreg(0) then
                --if keep_shreg(0)(3 downto 0) = X"F" and keep_shreg(0)(7 downto 4) = X"F" then
                if keep_shreg(0)(3 downto 0) = X"F" then
                    crc_stage(0) <= matrix_vector_mul(MATRIX_ARRAY(0), data_stage(0)(31 downto 0));
                else --this should never happen for valid data words
                    crc_stage(0) <= (others => '0');
                end if;
            else
                crc_stage(0) <= crc_stage(0);
            end if;
        end if;
    end process;

    gen_mid_block : if LATENCY >= 3 generate
        gen_crc_stage_g : for i in 1 to LATENCY - 2 generate
            process(clk)
                variable data_xor_crc : crc32_word_t;
            begin
                if rising_edge(clk) then
                    if valid_shreg(i) then
                        if keep_shreg(i)((i + 1) * 4 - 1 downto (i) * 4) = X"F" then
                            data_xor_crc := data_stage(i)((i + 1) * 32 - 1 downto i * 32) xor crc_stage(i - 1);
                            crc_stage(i) <= matrix_vector_mul(MATRIX_ARRAY(0), data_xor_crc);
                        else --passthrough
                            crc_stage(i) <= crc_stage(i - 1);
                        end if;
                    else
                        crc_stage(i) <= crc_stage(i);
                    end if;
                end if;
            end process;
        end generate;
    end generate;

    gen_last_block : if LATENCY >= 2 generate
        crc_stage_last : process(clk)
            variable data_xor_crc : crc32_word_t;
        begin
            if rising_edge(clk) then
                if valid_shreg(LATENCY - 1) then
                    if keep_shreg(LATENCY - 1)(LATENCY * 4 - 1 downto (LATENCY - 1) * 4) = X"F" then
                        data_xor_crc           := data_stage(LATENCY - 1)((LATENCY) * 32 - 1 downto (LATENCY - 1) * 32) xor crc_stage(LATENCY - 2);
                        crc_stage(LATENCY - 1) <= matrix_vector_mul(MATRIX_ARRAY(0), data_xor_crc) xor crc_seed;
                    else                    --this should never happen
                        crc_stage(LATENCY - 1) <= crc_stage(LATENCY - 2) xor crc_seed;
                    end if;
                else                    --this should never happen
                    crc_stage(LATENCY - 1) <= crc_stage(LATENCY - 1);
                end if;
            end if;
        end process;
    end generate;

    out_crc  <= crc_stage(LATENCY - 1);
    
    --process(clk) is
    --begin
    --    if rising_edge(clk) then
    --        if rst_crc or not valid_crc_out then
    --            partial_crc_seed(i) <= matrix_vector_mul(MATRIX_ARRAY(i), CRC_INIT);
    --        else
    --            partial_crc_seed(i) <= matrix_vector_mul(MATRIX_ARRAY(i), out_crc);
    --        end if;
    --    end if;
    --end process;

    reverse_out_g : if REVERSE_RESULT generate
        reverse_g : for i in 0 to 31 generate
            crcOut(i) <= out_crc(31 - i) xor FINXOR(31 - i);
        end generate;
    else generate
        crcOut <= out_crc xor FINXOR;
    end generate;

    valid_crc_out <= valid_shreg(valid_shreg'high);

end architecture RTL;
