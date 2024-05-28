library IEEE;
use IEEE.Std_logic_1164.all;
use IEEE.Numeric_Std.all;

use work.CRC32_pkg.all;

entity CRC32_D512_matrix_tb is
end;

architecture bench of CRC32_D512_matrix_tb is

    constant DATA_0 : std_logic_vector(127 downto 0) := X"0123456789ABCDEFFEDCBA9876543210";
    constant DATA_1 : std_logic_vector(127 downto 0) := X"02468ACEFDB9753102468ACEFDB97531";
    constant DATA_2 : std_logic_vector(127 downto 0) := X"DEADBEEFDEADBEEFDEADBEEFDEADBEEF";
    constant DATA_3 : std_logic_vector(127 downto 0) := X"ABBA00001234FFFFFFFFAAAAAAAAAAAA";

    signal clk           : std_logic;
    signal rst           : std_logic;
    signal rst_crc       : std_logic;
    signal data_in       : std_logic_vector(511 downto 0);
    signal keep_in       : std_logic_vector(63 downto 0);
    signal valid_in      : std_logic;
    signal crcOut        : std_logic_vector(31 downto 0);
    signal valid_crc_out : std_logic;

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

    stimulus : process
    begin
        rst      <= '0';
        rst_crc  <= '0';
        data_in  <= (others => '0');
        keep_in  <= (others => '0');
        valid_in <= '0';
        wait for 5 * clock_period;
        rst      <= '1';
        rst_crc  <= '1';
        wait for 10 * clock_period;
        rst      <= '0';
        rst_crc  <= '0';
        wait for 5 * clock_period;
        
        data_in  <= DATA_0 & DATA_1 & DATA_2 & DATA_3;
        keep_in  <= (others => '1');
        valid_in <= '1';
        wait for clock_period;
        
        data_in  <= DATA_1 & DATA_2 & DATA_3 & DATA_2;
        keep_in  <= (others => '1');
        valid_in <= '1';
        wait for  clock_period;
        
        data_in  <= DATA_1 & DATA_1 & DATA_2 & DATA_0;
        keep_in  <= X"00000000FFFFFFFF";
        valid_in <= '1';
        wait for clock_period;
        
        data_in  <= DATA_1 & DATA_0 & DATA_2 & DATA_3;
        keep_in  <= X"000000000000FFFF";
        valid_in <= '1';
        wait for clock_period;
        
        data_in  <= (others => '0');
        keep_in  <= (others => '0');
        valid_in <= '0';
        wait for 20 * clock_period;

        stop_the_clock <= true;
        wait;
    end process;

    clocking : process
    begin
        while not stop_the_clock loop
            clk <= '0', '1' after clock_period / 2;
            wait for clock_period;
        end loop;
        wait;
    end process;

end;
