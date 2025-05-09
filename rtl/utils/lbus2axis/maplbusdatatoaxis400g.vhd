--------------------------------------------------------------------------------
-- Company          : Kutleng Dynamic Electronics Systems (Pty) Ltd            -
-- Engineer         : Benjamin Hector Hlophe                                   -
--                                                                             -
-- Design Name      : CASPER BSP                                               -
-- Module Name      : maplbusdatatoaxis - rtl                                  -
-- Project Name     : SKARAB2                                                  -
-- Target Devices   : N/A                                                      -
-- Tool Versions    : N/A                                                      -
-- Description      : This module is used to align the L-BUS data to AXIS.     -
--                    The two interfaces have differing byte order.            -
--                                                                             -
-- Dependencies     : N/A                                                      -
-- Revision History : V1.0 - Initial design                                    -
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity maplbusdatatoaxis400g is
    port(
        lbus_rxclk   : in  STD_LOGIC;
        lbus_data    : in  STD_LOGIC_VECTOR(127 downto 0);
        axis_dataout : out STD_LOGIC_VECTOR(127 downto 0)
    );
end entity maplbusdatatoaxis400g;

architecture rtl of maplbusdatatoaxis400g is

begin

    -- MappingProc : process(lbus_rxclk)
    -- begin
    --     if rising_edge(lbus_rxclk) then
    --         -- Swap the bytes from big endian to little endian
    --         axis_dataout(127 downto 120) <= lbus_data(7 downto 0);
    --         axis_dataout(119 downto 112) <= lbus_data(15 downto 8);
    --         axis_dataout(111 downto 104) <= lbus_data(23 downto 16);
    --         axis_dataout(103 downto 96)  <= lbus_data(31 downto 24);
    --         axis_dataout(95 downto 88)   <= lbus_data(39 downto 32);
    --         axis_dataout(87 downto 80)   <= lbus_data(47 downto 40);
    --         axis_dataout(79 downto 72)   <= lbus_data(55 downto 48);
    --         axis_dataout(71 downto 64)   <= lbus_data(63 downto 56);
    --         axis_dataout(63 downto 56)   <= lbus_data(71 downto 64);
    --         axis_dataout(55 downto 48)   <= lbus_data(79 downto 72);
    --         axis_dataout(47 downto 40)   <= lbus_data(87 downto 80);
    --         axis_dataout(39 downto 32)   <= lbus_data(95 downto 88);
    --         axis_dataout(31 downto 24)   <= lbus_data(103 downto 96);
    --         axis_dataout(23 downto 16)   <= lbus_data(111 downto 104);
    --         axis_dataout(15 downto 8)    <= lbus_data(119 downto 112);
    --         axis_dataout(7 downto 0)     <= lbus_data(127 downto 120);
    --     end if;
    -- end process MappingProc;
    MappingProc : process(lbus_rxclk)
    begin
        if rising_edge(lbus_rxclk) then
            -- No need to swap for 400G
            axis_dataout <= lbus_data;
        end if;
    end process MappingProc;
end architecture rtl;
