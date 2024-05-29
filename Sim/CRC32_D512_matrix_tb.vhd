library IEEE;
use IEEE.Std_logic_1164.all;
use IEEE.Numeric_Std.all;

use std.textio.all;

use work.CRC32_pkg.all;

entity CRC32_D512_matrix_tb is
end;

architecture bench of CRC32_D512_matrix_tb is

    constant LATENCY_CRC_BLOCK : integer := 3;

    signal clk           : std_logic;
    signal rst           : std_logic;
    signal rst_crc       : std_logic;
    signal data_in       : std_logic_vector(511 downto 0);
    signal keep_in       : std_logic_vector(63 downto 0) := (others => '0');
    signal valid_in      : std_logic                     := '0';
    signal crcOut        : std_logic_vector(31 downto 0);
    signal valid_crc_out : std_logic;

    signal ena           : std_logic                      := '0';
    signal data_in_value : std_logic_vector(511 downto 0) := (others => '0');
    signal data_in_keep  : std_logic_vector(63 downto 0)  := (others => '0');
    signal file_in_end   : boolean                        := false;

    signal enb           : std_logic                     := '0';
    signal crc_out_value : std_logic_vector(31 downto 0) := (others => '0');
    signal file_out_end  : boolean                       := false;

    signal data_block_index : integer := 0;
    signal error_count      : integer := 0;

    constant clock_period : time := 10 ns;
    signal stop_the_clock : boolean;

begin

    -- Insert values for generic parameters !!
    uut : entity work.CRC32_D512_matrix
        generic map(
            CRC_POLY       => CRC32_POLY,
            CRC_INIT       => X"FFFFFFFF",
            REVERSE_RESULT => FALSE,
            FINXOR         => X"00000000"
        )
        port map(
            clk           => clk,
            rst           => rst,
            rst_crc       => rst_crc,
            data_in       => data_in,
            keep_in       => keep_in,
            valid_in      => valid_in,
            crcOut        => crcOut,
            valid_crc_out => valid_crc_out
        );

    read_in_p : process(clk, rst) is
        ---------------------------------------------------------------------------------------------------------

        file test_vector            : text open read_mode is "data_in_file.txt";
        variable row                : line;
        variable v_data_read        : integer;
        variable v_data_row_counter : integer := 0;
        variable data_block         : integer := 0;

        -----------------------------------------------------------------------------------------------------------
    begin
        --if (rst = '1') then
        --    v_data_row_counter := 0;
        --    v_data_read        := (others => -1);
        --------------------------------------
        --elsif (rising_edge(clk)) then
        --
        --    if (ena = '1' and not file_in_end) then         -- external enable signal
        --
        --        data_in  <= (others => '0');
        --        keep_in  <= (others => '0');
        --        valid_in <= '1';
        --
        --        for i in 0 to 15 loop
        --            -- read from input file in "row" variable;
        --            if (not endfile(test_vector)) then
        --                v_data_row_counter := v_data_row_counter + 1;
        --                readline(test_vector, row);
        --
        --                for kk in 1 to NUM_COL loop
        --                    read(row, v_data_read(kk));
        --                end loop;
        --                
        --                data_in(32 * (i + 1) - 1 downto 32 * i) <= std_logic_vector(to_unsigned(v_data_read(1), 32));
        --                keep_in(4 * (i + 1) - 1 downto 4 * i)   <= X"F";
        --
        --            else
        --                file_in_end <= true;
        --                valid_in    <= '0';
        --            end if;
        --        end loop;
        --    end if;
        --end if;
        if (rst = '1') then
            v_data_row_counter := 0;
            v_data_read        := -1;
            data_block         := 0;
        ------------------------------------
        elsif (rising_edge(clk)) then

            if (ena = '1') then         -- external enable signal

                data_in <= (others => '0');
                keep_in <= (others => '0');

                -- read from input file in "row" variable
                report "Loading data block " & integer'image(data_block);
                for i in 0 to 15 loop
                    if (not endfile(test_vector)) then

                        v_data_row_counter                      := v_data_row_counter + 1;
                        readline(test_vector, row);
                        read(row, v_data_read);
                        data_in(32 * (i + 1) - 1 downto 32 * i) <= std_logic_vector(to_signed(v_data_read, 32));
                        keep_in(4 * (i + 1) - 1 downto 4 * i)   <= X"F";
                        --test := std_logic_vector(to_unsigned(v_data_read, 32));
                        report "Loading data frame from file, value : " & to_hstring(to_signed(v_data_read, 32));
                    else
                        file_in_end <= true;

                    end if;
                end loop;
                data_block := data_block + 1;
            else
                data_in <= (others => '0');
                keep_in <= (others => '0');
            end if;

        end if;

    end process read_in_p;

    valid_in <= '0' when keep_in = X"0000000000000000" else '1';

    read_out_p : process(clk, rst) is
        ---------------------------------------------------------------------------------------------------------

        file test_vector            : text open read_mode is "crc_out_file.txt";
        variable row                : line;
        variable v_data_read        : integer;
        variable v_data_row_counter : integer := 0;

        -----------------------------------------------------------------------------------------------------------
    begin
        if (rst = '1') then
            v_data_row_counter := 0;
            v_data_read        := -1;
        ------------------------------------
        elsif (rising_edge(clk)) then

            if (enb = '1') then         -- external enable signal

                -- read from input file in "row" variable
                if (not endfile(test_vector)) then
                    v_data_row_counter := v_data_row_counter + 1;
                    readline(test_vector, row);
                else
                    file_out_end <= true;
                end if;

                -- read integer number from "row" variable in integer array
                read(row, v_data_read);
                crc_out_value    <= std_logic_vector(to_signed(v_data_read, 32));
                data_block_index <= data_block_index + 1;

                --check
                if crcOut /= std_logic_vector(to_signed(v_data_read, 32)) then
                    report "Mismatch found on data block " & integer'image(data_block_index) & ", expected 0x" & to_hstring(to_signed(v_data_read, 32)) & " got 0x" & to_hstring(signed(crcOut)) severity warning;
                    error_count <= error_count + 1;
                end if;
            end if;

        end if;
    end process read_out_p;

    stimulus : process
    begin
        rst     <= '0';
        rst_crc <= '0';
        --data_in  <= (others => '0');
        --keep_in  <= (others => '0');
        --valid_in <= '0';
        wait for 5 * clock_period;
        rst     <= '1';
        rst_crc <= '1';
        wait for 10 * clock_period;
        rst     <= '0';
        rst_crc <= '0';
        wait for 5 * clock_period;

        ena <= '1';
        wait until file_in_end;
        ena <= '0';

        wait for (LATENCY_CRC_BLOCK + 1) * clock_period;

        stop_the_clock <= true;
        wait;
    end process;

    enb <= valid_crc_out;

    clocking : process
    begin
        while not stop_the_clock loop
            clk <= '0', '1' after clock_period / 2;
            wait for clock_period;
        end loop;
        wait;
    end process;

    check : process
    begin
        wait until stop_the_clock;
        if error_count /= 0 then
            report "Test failed" severity failure;
        else
            report "TB completed successfully" severity note;
        end if;
        wait;
    end process;

end;
