--------------------------------------------------------------------------------
-- Company          : Kutleng Dynamic Electronics Systems (Pty) Ltd            -
-- Engineer         : Benjamin Hector Hlophe                                   -
--                                                                             -
-- Design Name      : CASPER BSP                                               -
-- Module Name      : mapmtytotkeep - rtl                                      -
-- Project Name     : SKARAB2                                                  -
-- Target Devices   : N/A                                                      -
-- Tool Versions    : N/A                                                      -
-- Description      : This module is used to map MTY to TKEEP.                 -
--                                                                             -
-- Dependencies     : N/A                                                      -
-- Revision History : V1.0 - Initial design                                    -
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity mapmtytotkeep is
    port(
        lbus_rxclk    : in  STD_LOGIC;
        lbus_rxen     : in  STD_LOGIC;
        lbus_rxmty    : in  STD_LOGIC_VECTOR(3 downto 0);
        axis_tkeepout : out STD_LOGIC_VECTOR(15 downto 0)
    );
end entity mapmtytotkeep;

architecture rtl of mapmtytotkeep is

begin

    MappingProc : process(lbus_rxclk)
    begin
        if rising_edge(lbus_rxclk) then
            if (lbus_rxen = '1') then
                case (lbus_rxmty) is
                    -- When all bytes are enabled 
                    -- There are no empty byte slots
                    when b"0000" =>
                        axis_tkeepout <= b"1111111111111111";
                    -- Only 1 byte is disabled
                    -- Only 15 bytes are enabled
                    -- There is 1 empty slot
                    when b"0001" =>
                        axis_tkeepout <= b"0111111111111111";
                    -- Only 2 bytes are disabled
                    -- Only 14 bytes are enabled
                    -- There are 2 empty slots
                    when b"0010" =>
                        axis_tkeepout <= b"0011111111111111";
                    -- Only 3 bytes are disabled
                    -- Only 13 bytes are enabled
                    -- There are 3 empty slots
                    when b"0011" =>
                        axis_tkeepout <= b"0001111111111111";
                    -- Only 4 bytes are disabled
                    -- Only 12 bytes are enabled
                    -- There are 4 empty slots
                    when b"0100" =>
                        axis_tkeepout <= b"0000111111111111";
                    -- Only 5 bytes are disabled
                    -- Only 11 bytes are enabled
                    -- There are 5 empty slots
                    when b"0101" =>
                        axis_tkeepout <= b"0000011111111111";
                    -- Only 6 bytes are disabled
                    -- Only 10 bytes are enabled
                    -- There are 6 empty slots
                    when b"0110" =>
                        axis_tkeepout <= b"0000001111111111";
                    -- Only 7 bytes are disabled
                    -- Only 9 bytes are enabled
                    -- There are 7 empty slots
                    when b"0111" =>
                        axis_tkeepout <= b"0000000111111111";
                    -- Only 8 bytes are disabled
                    -- Only 8 bytes are enabled
                    -- There are 8 empty slots
                    when b"1000" =>
                        axis_tkeepout <= b"0000000011111111";
                    -- Only 9 bytes are disabled
                    -- Only 7 bytes are enabled
                    -- There are 9 empty slots
                    when b"1001" =>
                        axis_tkeepout <= b"0000000001111111";
                    -- Only 10 bytes are disabled
                    -- Only 6 bytes are enabled
                    -- There are 10 empty slots
                    when b"1010" =>
                        axis_tkeepout <= b"0000000000111111";
                    -- Only 11 bytes are disabled
                    -- Only 5 bytes are enabled
                    -- There are 11 empty slots
                    when b"1011" =>
                        axis_tkeepout <= b"0000000000011111";
                    -- Only 12 bytes are disabled
                    -- Only 4 bytes are enabled
                    -- There are 12 empty slots
                    when b"1100" =>
                        axis_tkeepout <= b"0000000000001111";
                    -- Only 13 bytes are disabled
                    -- Only 3 bytes are enabled
                    -- There are 13 empty slots
                    when b"1101" =>
                        axis_tkeepout <= b"0000000000000111";
                    -- Only 14 bytes are disabled
                    -- Only 2 bytes are enabled
                    -- There are 14 empty slots
                    when b"1110" =>
                        axis_tkeepout <= b"0000000000000011";
                    -- Only 15 bytes are disabled
                    -- Only 1 byte is enabled
                    -- There are 15 empty slots
                    when b"1111" =>
                        axis_tkeepout <= b"0000000000000001";
                    when others =>
                        null;
                end case;
            else
                axis_tkeepout <= b"0000000000000000";
            end if;
        end if;
    end process MappingProc;

end architecture rtl;
