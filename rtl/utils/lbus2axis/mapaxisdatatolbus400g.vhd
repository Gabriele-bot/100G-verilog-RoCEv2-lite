--------------------------------------------------------------------------------
-- Company          : Kutleng Dynamic Electronics Systems (Pty) Ltd            -
-- Engineer         : Benjamin Hector Hlophe                                   -
--                                                                             -
-- Design Name      : CASPER BSP                                               -
-- Module Name      : mapaxisdatatolbus - rtl                                  -
-- Project Name     : SKARAB2                                                  -
-- Target Devices   : N/A                                                      -
-- Tool Versions    : N/A                                                      -
-- Description      : This module is used to align the AXIS data to L-BUS.     -
--                    The two interfaces have differing byte order.            -
--                                                                             -
-- Dependencies     : N/A                                                      -
-- Revision History : V1.0 - Initial design                                    -
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity mapaxisdatatolbus400g is
    generic(
        DATASWAP     : boolean  := false
    );
    port(
        lbus_txclk   : in  STD_LOGIC;
        axis_data    : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_dataout : out STD_LOGIC_VECTOR(127 downto 0)
    );
end entity mapaxisdatatolbus400g;

architecture rtl of mapaxisdatatolbus400g is

begin
    -- Swapdata : if (DATASWAP = true) generate
    -- begin
    --     MappingProc : process(lbus_txclk)
    --     begin
    --         if rising_edge(lbus_txclk) then
    --             -- Swap the bytes from big endian to little endian
    --             lbus_dataout(127 downto 120) <= axis_data(7 downto 0);
    --             lbus_dataout(119 downto 112) <= axis_data(15 downto 8);
    --             lbus_dataout(111 downto 104) <= axis_data(23 downto 16);
    --             lbus_dataout(103 downto 96)  <= axis_data(31 downto 24);
    --             lbus_dataout(95 downto 88)   <= axis_data(39 downto 32);
    --             lbus_dataout(87 downto 80)   <= axis_data(47 downto 40);
    --             lbus_dataout(79 downto 72)   <= axis_data(55 downto 48);
    --             lbus_dataout(71 downto 64)   <= axis_data(63 downto 56);
    --             lbus_dataout(63 downto 56)   <= axis_data(71 downto 64);
    --             lbus_dataout(55 downto 48)   <= axis_data(79 downto 72);
    --             lbus_dataout(47 downto 40)   <= axis_data(87 downto 80);
    --             lbus_dataout(39 downto 32)   <= axis_data(95 downto 88);
    --             lbus_dataout(31 downto 24)   <= axis_data(103 downto 96);
    --             lbus_dataout(23 downto 16)   <= axis_data(111 downto 104);
    --             lbus_dataout(15 downto 8)    <= axis_data(119 downto 112);
    --             lbus_dataout(7 downto 0)     <= axis_data(127 downto 120);
    --         end if;
    --     end process MappingProc;
    -- end generate;
    
    MappingProc : process(lbus_txclk)
    begin
        if rising_edge(lbus_txclk) then
            -- Swap the bytes from big endian to little endian
            lbus_dataout <= axis_data;
        end if;
    end process MappingProc;

end architecture rtl;
