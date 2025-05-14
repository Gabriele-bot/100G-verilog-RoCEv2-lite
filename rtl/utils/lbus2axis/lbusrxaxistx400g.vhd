--------------------------------------------------------------------------------
-- Company          : Kutleng Dynamic Electronics Systems (Pty) Ltd            -
-- Engineer         : Benjamin Hector Hlophe                                   -
--                                                                             -
-- Design Name      : CASPER BSP                                               -
-- Module Name      : lbusrxaxistx - rtl                                        -
-- Project Name     : SKARAB2                                                  -
-- Target Devices   : N/A                                                      -
-- Tool Versions    : N/A                                                      -
-- Description      : This module is used to map the L-BUS to AXIS interface.  -
--                                                                             -
-- Dependencies     : maplbusdatatoaxis,mapmtytotkeep                          -
-- Revision History : V1.0 - Initial design                                    -
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity lbusrxaxistx400g is
    port(
        lbus_rxclk     : in  STD_LOGIC;
        lbus_rxreset   : in  STD_LOGIC;
        -- Outputs to AXIS bus
        axis_tx_tdata  : out STD_LOGIC_VECTOR(1023 downto 0);
        axis_tx_tvalid : out STD_LOGIC;
        axis_tx_tkeep  : out STD_LOGIC_VECTOR(127 downto 0);
        axis_tx_tlast  : out STD_LOGIC;
        axis_tx_tuser  : out STD_LOGIC;
        -- Inputs from L-BUS interface
        lbus_rxvldin0  : in  STD_LOGIC;
        lbus_rxdatain0 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain0  : in  STD_LOGIC;
        lbus_rxsopin0  : in  STD_LOGIC;
        lbus_rxeopin0  : in  STD_LOGIC;
        lbus_rxerrin0  : in  STD_LOGIC;
        lbus_rxmtyin0  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain1 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain1  : in  STD_LOGIC;
        lbus_rxsopin1  : in  STD_LOGIC;
        lbus_rxeopin1  : in  STD_LOGIC;
        lbus_rxerrin1  : in  STD_LOGIC;
        lbus_rxmtyin1  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain2 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain2  : in  STD_LOGIC;
        lbus_rxsopin2  : in  STD_LOGIC;
        lbus_rxeopin2  : in  STD_LOGIC;
        lbus_rxerrin2  : in  STD_LOGIC;
        lbus_rxmtyin2  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain3 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain3  : in  STD_LOGIC;
        lbus_rxsopin3  : in  STD_LOGIC;
        lbus_rxeopin3  : in  STD_LOGIC;
        lbus_rxerrin3  : in  STD_LOGIC;
        lbus_rxmtyin3  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain4 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain4  : in  STD_LOGIC;
        lbus_rxsopin4  : in  STD_LOGIC;
        lbus_rxeopin4  : in  STD_LOGIC;
        lbus_rxerrin4  : in  STD_LOGIC;
        lbus_rxmtyin4  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain5 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain5  : in  STD_LOGIC;
        lbus_rxsopin5  : in  STD_LOGIC;
        lbus_rxeopin5  : in  STD_LOGIC;
        lbus_rxerrin5  : in  STD_LOGIC;
        lbus_rxmtyin5  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain6 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain6  : in  STD_LOGIC;
        lbus_rxsopin6  : in  STD_LOGIC;
        lbus_rxeopin6  : in  STD_LOGIC;
        lbus_rxerrin6  : in  STD_LOGIC;
        lbus_rxmtyin6  : in  STD_LOGIC_VECTOR(3 downto 0);
        lbus_rxdatain7 : in  STD_LOGIC_VECTOR(127 downto 0);
        lbus_rxenain7  : in  STD_LOGIC;
        lbus_rxsopin7  : in  STD_LOGIC;
        lbus_rxeopin7  : in  STD_LOGIC;
        lbus_rxerrin7  : in  STD_LOGIC;
        lbus_rxmtyin7  : in  STD_LOGIC_VECTOR(3 downto 0)
    );
end entity lbusrxaxistx400g;

architecture rtl of lbusrxaxistx400g is
    component maplbusdatatoaxis400g is
        port(
            lbus_rxclk   : in  STD_LOGIC;
            lbus_data    : in  STD_LOGIC_VECTOR(127 downto 0);
            axis_dataout : out STD_LOGIC_VECTOR(127 downto 0)
        );
    end component maplbusdatatoaxis400g;
    component mapmtytotkeep is
        port(
            lbus_rxclk    : in  STD_LOGIC;
            lbus_rxen     : in  STD_LOGIC;
            lbus_rxmty    : in  STD_LOGIC_VECTOR(3 downto 0);
            axis_tkeepout : out STD_LOGIC_VECTOR(15 downto 0)
        );
    end component mapmtytotkeep;

    alias lbus_rxdatain0fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain0;
    alias lbus_rxdatain1fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain1;
    alias lbus_rxdatain2fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain2;
    alias lbus_rxdatain3fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain3;
    alias lbus_rxdatain4fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain4;
    alias lbus_rxdatain5fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain5;
    alias lbus_rxdatain6fs0 : STD_LOGIC_VECTOR(127 downto 0) is lbus_rxdatain6;

    signal lbus_rxdatain0fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain1fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain2fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain3fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain4fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain5fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain6fs1 : STD_LOGIC_VECTOR(127 downto 0);
    signal lbus_rxdatain7fs1 : STD_LOGIC_VECTOR(127 downto 0);

    signal aligned_rxdatain0 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain1 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain2 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain3 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain4 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain5 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain6 : STD_LOGIC_VECTOR(127 downto 0);
    signal aligned_rxdatain7 : STD_LOGIC_VECTOR(127 downto 0);

    alias lbus_rxmtyin0fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin0;
    alias lbus_rxmtyin1fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin1;
    alias lbus_rxmtyin2fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin2;
    alias lbus_rxmtyin3fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin3;
    alias lbus_rxmtyin4fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin4;
    alias lbus_rxmtyin5fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin5;
    alias lbus_rxmtyin6fs0 : STD_LOGIC_VECTOR(3 downto 0) is lbus_rxmtyin6;

    signal lbus_rxmtyin0fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin1fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin2fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin3fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin4fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin5fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin6fs1 : STD_LOGIC_VECTOR(3 downto 0);
    signal lbus_rxmtyin7fs1 : STD_LOGIC_VECTOR(3 downto 0);

    signal aligned_rxmtyin0 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin1 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin2 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin3 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin4 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin5 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin6 : STD_LOGIC_VECTOR(3 downto 0);
    signal aligned_rxmtyin7 : STD_LOGIC_VECTOR(3 downto 0);

    alias lbus_rxeopin0fs0 : STD_LOGIC is lbus_rxeopin0;
    alias lbus_rxeopin1fs0 : STD_LOGIC is lbus_rxeopin1;
    alias lbus_rxeopin2fs0 : STD_LOGIC is lbus_rxeopin2;
    alias lbus_rxeopin3fs0 : STD_LOGIC is lbus_rxeopin3;
    alias lbus_rxeopin4fs0 : STD_LOGIC is lbus_rxeopin4;
    alias lbus_rxeopin5fs0 : STD_LOGIC is lbus_rxeopin5;
    alias lbus_rxeopin6fs0 : STD_LOGIC is lbus_rxeopin6;

    signal lbus_rxeopin0fs1 : STD_LOGIC;
    signal lbus_rxeopin1fs1 : STD_LOGIC;
    signal lbus_rxeopin2fs1 : STD_LOGIC;
    signal lbus_rxeopin3fs1 : STD_LOGIC;
    signal lbus_rxeopin4fs1 : STD_LOGIC;
    signal lbus_rxeopin5fs1 : STD_LOGIC;
    signal lbus_rxeopin6fs1 : STD_LOGIC;
    signal lbus_rxeopin7fs1 : STD_LOGIC;

    signal aligned_rxeopin0 : STD_LOGIC;
    signal aligned_rxeopin1 : STD_LOGIC;
    signal aligned_rxeopin2 : STD_LOGIC;
    signal aligned_rxeopin3 : STD_LOGIC;
    signal aligned_rxeopin4 : STD_LOGIC;
    signal aligned_rxeopin5 : STD_LOGIC;
    signal aligned_rxeopin6 : STD_LOGIC;
    signal aligned_rxeopin7 : STD_LOGIC;

    alias lbus_rxenain0fs0 : STD_LOGIC is lbus_rxenain0;
    alias lbus_rxenain1fs0 : STD_LOGIC is lbus_rxenain1;
    alias lbus_rxenain2fs0 : STD_LOGIC is lbus_rxenain2;
    alias lbus_rxenain3fs0 : STD_LOGIC is lbus_rxenain3;
    alias lbus_rxenain4fs0 : STD_LOGIC is lbus_rxenain4;
    alias lbus_rxenain5fs0 : STD_LOGIC is lbus_rxenain5;
    alias lbus_rxenain6fs0 : STD_LOGIC is lbus_rxenain6;

    alias lbus_rxvldinfs0 : STD_LOGIC is lbus_rxvldin0;

    signal lbus_rxenain0fs1 : STD_LOGIC;
    signal lbus_rxenain1fs1 : STD_LOGIC;
    signal lbus_rxenain2fs1 : STD_LOGIC;
    signal lbus_rxenain3fs1 : STD_LOGIC;
    signal lbus_rxenain4fs1 : STD_LOGIC;
    signal lbus_rxenain5fs1 : STD_LOGIC;
    signal lbus_rxenain6fs1 : STD_LOGIC;
    signal lbus_rxenain7fs1 : STD_LOGIC;

    signal lbus_rxvldinfs1 : STD_LOGIC;

    signal aligned_rxenain0 : STD_LOGIC;
    signal aligned_rxenain1 : STD_LOGIC;
    signal aligned_rxenain2 : STD_LOGIC;
    signal aligned_rxenain3 : STD_LOGIC;
    signal aligned_rxenain4 : STD_LOGIC;
    signal aligned_rxenain5 : STD_LOGIC;
    signal aligned_rxenain6 : STD_LOGIC;
    signal aligned_rxenain7 : STD_LOGIC;

    signal aligned_rxvldin : STD_LOGIC;

    signal CurrentAlignment : STD_LOGIC_VECTOR(2 downto 0);

begin

    ControlAxisProc : process(lbus_rxclk)
    begin
        if rising_edge(lbus_rxclk) then
            -- Whenever there is an EOP we signal TLAST
            axis_tx_tlast  <= aligned_rxvldin and (aligned_rxeopin0 or aligned_rxeopin1 or aligned_rxeopin2 or aligned_rxeopin3 or aligned_rxeopin4 or aligned_rxeopin5 or aligned_rxeopin6 or aligned_rxeopin7);
            --axis_tx_tlast  <= (aligned_rxeopin0 or aligned_rxeopin1 or aligned_rxeopin2 or aligned_rxeopin3 or aligned_rxeopin4 or aligned_rxeopin5 or aligned_rxeopin6 or aligned_rxeopin7);
            -- When ever there is an enable we signal TVALID			
            axis_tx_tvalid <= aligned_rxvldin and (aligned_rxenain0  or aligned_rxenain1 or aligned_rxenain2 or aligned_rxenain3 or aligned_rxenain4  or aligned_rxenain5 or aligned_rxenain6 or aligned_rxenain7);
            --axis_tx_tvalid <= (aligned_rxenain0  or aligned_rxenain1 or aligned_rxenain2 or aligned_rxenain3 or aligned_rxenain4  or aligned_rxenain5 or aligned_rxenain6 or aligned_rxenain7);
            if ((aligned_rxeopin0 = '1') or (aligned_rxeopin1 = '1') or (aligned_rxeopin2 = '1') or (aligned_rxeopin3 = '1') or (aligned_rxeopin4 = '1') or (aligned_rxeopin5 = '1') or (aligned_rxeopin6 = '1') or (aligned_rxeopin7 = '1')) then
                -- Flag an error signal on TUSER if there was an error and TLAST is valid 
                axis_tx_tuser <= lbus_rxerrin0 or lbus_rxerrin1 or lbus_rxerrin2 or lbus_rxerrin3 or lbus_rxerrin4 or lbus_rxerrin5 or lbus_rxerrin6 or lbus_rxerrin7;
            else
                -- Signal no error otherwise
                axis_tx_tuser <= '0';
            end if;
        end if;
    end process ControlAxisProc;

    AlignmentBarrelShifterProc : process(lbus_rxclk)
    begin
        if rising_edge(lbus_rxclk) then
            -- Save the data frame
            lbus_rxdatain0fs1 <= lbus_rxdatain0;
            lbus_rxdatain1fs1 <= lbus_rxdatain1;
            lbus_rxdatain2fs1 <= lbus_rxdatain2;
            lbus_rxdatain3fs1 <= lbus_rxdatain3;
            lbus_rxdatain4fs1 <= lbus_rxdatain4;
            lbus_rxdatain5fs1 <= lbus_rxdatain5;
            lbus_rxdatain6fs1 <= lbus_rxdatain6;
            lbus_rxdatain7fs1 <= lbus_rxdatain7;
            -- Save the MTY frame
            lbus_rxmtyin0fs1  <= lbus_rxmtyin0;
            lbus_rxmtyin1fs1  <= lbus_rxmtyin1;
            lbus_rxmtyin2fs1  <= lbus_rxmtyin2;
            lbus_rxmtyin3fs1  <= lbus_rxmtyin3;
            lbus_rxmtyin4fs1  <= lbus_rxmtyin4;
            lbus_rxmtyin5fs1  <= lbus_rxmtyin5;
            lbus_rxmtyin6fs1  <= lbus_rxmtyin6;
            lbus_rxmtyin7fs1  <= lbus_rxmtyin7;
            -- Save the EOPs 
            lbus_rxeopin0fs1  <= lbus_rxeopin0;
            lbus_rxeopin1fs1  <= lbus_rxeopin1;
            lbus_rxeopin2fs1  <= lbus_rxeopin2;
            lbus_rxeopin3fs1  <= lbus_rxeopin3;
            lbus_rxeopin4fs1  <= lbus_rxeopin4;
            lbus_rxeopin5fs1  <= lbus_rxeopin5;
            lbus_rxeopin6fs1  <= lbus_rxeopin6;
            lbus_rxeopin7fs1  <= lbus_rxeopin7;
            -- Save the ENAs 
            lbus_rxenain0fs1  <= lbus_rxenain0;
            lbus_rxenain1fs1  <= lbus_rxenain1;
            lbus_rxenain2fs1  <= lbus_rxenain2;
            lbus_rxenain3fs1  <= lbus_rxenain3;
            lbus_rxenain4fs1  <= lbus_rxenain4;
            lbus_rxenain5fs1  <= lbus_rxenain5;
            lbus_rxenain6fs1  <= lbus_rxenain6;
            lbus_rxenain7fs1  <= lbus_rxenain7;

            lbus_rxvldinfs1 <= lbus_rxvldin0;

            -- Determine the alignment using a barrel shifter
            case (CurrentAlignment) is
                when b"000" =>
                    -- Data is properly aligned to 64 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain0fs1;
                    aligned_rxdatain1 <= lbus_rxdatain1fs1;
                    aligned_rxdatain2 <= lbus_rxdatain2fs1;
                    aligned_rxdatain3 <= lbus_rxdatain3fs1;
                    aligned_rxdatain4 <= lbus_rxdatain4fs1;
                    aligned_rxdatain5 <= lbus_rxdatain5fs1;
                    aligned_rxdatain6 <= lbus_rxdatain6fs1;
                    aligned_rxdatain7 <= lbus_rxdatain7fs1;
                    -- Mty is also aligned to 64 byte boundary				
                    aligned_rxmtyin0  <= lbus_rxmtyin0fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin1fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin2fs1;
                    aligned_rxmtyin3  <= lbus_rxmtyin3fs1;
                    aligned_rxmtyin4  <= lbus_rxmtyin4fs1;
                    aligned_rxmtyin5  <= lbus_rxmtyin5fs1;
                    aligned_rxmtyin6  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin7  <= lbus_rxmtyin7fs1;
                    -- EOP is also aligned to 64 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin0fs1;
                    aligned_rxeopin1  <= lbus_rxeopin1fs1;
                    aligned_rxeopin2  <= lbus_rxeopin2fs1;
                    aligned_rxeopin3  <= lbus_rxeopin3fs1;
                    aligned_rxeopin4  <= lbus_rxeopin4fs1;
                    aligned_rxeopin5  <= lbus_rxeopin5fs1;
                    aligned_rxeopin6  <= lbus_rxeopin6fs1;
                    aligned_rxeopin7  <= lbus_rxeopin7fs1;
                    -- ENA is also aligned to 64 byte boundary
                    aligned_rxenain0  <= lbus_rxenain0fs1;
                    aligned_rxenain1  <= lbus_rxenain1fs1;
                    aligned_rxenain2  <= lbus_rxenain2fs1;
                    aligned_rxenain3  <= lbus_rxenain3fs1;
                    aligned_rxenain4  <= lbus_rxenain4fs1;
                    aligned_rxenain5  <= lbus_rxenain5fs1;
                    aligned_rxenain6  <= lbus_rxenain6fs1;
                    aligned_rxenain7  <= lbus_rxenain7fs1;

                    aligned_rxvldin  <= lbus_rxvldinfs1;

                when b"001" =>
                    -- Data is aligned to 16 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain1fs1;
                    aligned_rxdatain1 <= lbus_rxdatain2fs1;
                    aligned_rxdatain2 <= lbus_rxdatain3fs1;
                    aligned_rxdatain3 <= lbus_rxdatain4fs1;
                    aligned_rxdatain4 <= lbus_rxdatain5fs1;
                    aligned_rxdatain5 <= lbus_rxdatain6fs1;
                    aligned_rxdatain6 <= lbus_rxdatain7fs1;
                    aligned_rxdatain7 <= lbus_rxdatain0fs0;
                    -- Mty is also aligned to 16 byte boundary				
                    aligned_rxmtyin0  <= lbus_rxmtyin1fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin2fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin3fs1;
                    aligned_rxmtyin3  <= lbus_rxmtyin4fs1;
                    aligned_rxmtyin4  <= lbus_rxmtyin5fs1;
                    aligned_rxmtyin5  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin6  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin7  <= lbus_rxmtyin0fs0;
                    -- EOP is also aligned to 16 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin1fs1;
                    aligned_rxeopin1  <= lbus_rxeopin2fs1;
                    aligned_rxeopin2  <= lbus_rxeopin3fs1;
                    aligned_rxeopin3  <= lbus_rxeopin4fs1;
                    aligned_rxeopin4  <= lbus_rxeopin5fs1;
                    aligned_rxeopin5  <= lbus_rxeopin6fs1;
                    aligned_rxeopin6  <= lbus_rxeopin7fs1;
                    aligned_rxeopin7  <= lbus_rxeopin0fs0;
                    -- ENA is also aligned to 16 byte boundary
                    aligned_rxenain0  <= lbus_rxenain1fs1;
                    aligned_rxenain1  <= lbus_rxenain2fs1;
                    aligned_rxenain2  <= lbus_rxenain3fs1;
                    aligned_rxenain3  <= lbus_rxenain4fs1;
                    aligned_rxenain4  <= lbus_rxenain5fs1;
                    aligned_rxenain5  <= lbus_rxenain6fs1;
                    aligned_rxenain6  <= lbus_rxenain7fs1;
                    aligned_rxenain7  <= lbus_rxenain0fs0;
                when b"010" =>
                    -- Data is aligned to 32 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain2fs1;
                    aligned_rxdatain1 <= lbus_rxdatain3fs1;
                    aligned_rxdatain2 <= lbus_rxdatain4fs1;
                    aligned_rxdatain3 <= lbus_rxdatain5fs1;
                    aligned_rxdatain4 <= lbus_rxdatain6fs1;
                    aligned_rxdatain5 <= lbus_rxdatain7fs1;
                    aligned_rxdatain6 <= lbus_rxdatain0fs0;
                    aligned_rxdatain7 <= lbus_rxdatain1fs0;
                    -- Mty is also aligned to 32 byte boundary				
                    aligned_rxmtyin0  <= lbus_rxmtyin2fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin3fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin4fs1;
                    aligned_rxmtyin3  <= lbus_rxmtyin5fs1;
                    aligned_rxmtyin4  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin5  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin6  <= lbus_rxmtyin0fs0;
                    aligned_rxmtyin7  <= lbus_rxmtyin1fs0;
                    -- EOP is also aligned to 32 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin2fs1;
                    aligned_rxeopin1  <= lbus_rxeopin3fs1;
                    aligned_rxeopin2  <= lbus_rxeopin4fs1;
                    aligned_rxeopin3  <= lbus_rxeopin5fs1;
                    aligned_rxeopin4  <= lbus_rxeopin6fs1;
                    aligned_rxeopin5  <= lbus_rxeopin7fs1;
                    aligned_rxeopin6  <= lbus_rxeopin0fs0;
                    aligned_rxeopin7  <= lbus_rxeopin1fs0;
                    -- ENA is also aligned to 32 byte boundary
                    aligned_rxenain0  <= lbus_rxenain2fs1;
                    aligned_rxenain1  <= lbus_rxenain3fs1;
                    aligned_rxenain2  <= lbus_rxenain4fs1;
                    aligned_rxenain3  <= lbus_rxenain5fs1;
                    aligned_rxenain4  <= lbus_rxenain6fs1;
                    aligned_rxenain5  <= lbus_rxenain7fs1;
                    aligned_rxenain6  <= lbus_rxenain0fs0;
                    aligned_rxenain7  <= lbus_rxenain1fs0;
                when b"011" =>
                    -- Data is aligned to 48 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain3fs1;
                    aligned_rxdatain1 <= lbus_rxdatain4fs1;
                    aligned_rxdatain2 <= lbus_rxdatain5fs1;
                    aligned_rxdatain3 <= lbus_rxdatain6fs1;
                    aligned_rxdatain4 <= lbus_rxdatain7fs1;
                    aligned_rxdatain5 <= lbus_rxdatain0fs0;
                    aligned_rxdatain6 <= lbus_rxdatain1fs0;
                    aligned_rxdatain7 <= lbus_rxdatain2fs0;
                    -- Mty is also aligned to 48 byte boundary				
                    aligned_rxmtyin0  <= lbus_rxmtyin3fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin4fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin5fs1;
                    aligned_rxmtyin3  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin4  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin5  <= lbus_rxmtyin0fs0;
                    aligned_rxmtyin6  <= lbus_rxmtyin1fs0;
                    aligned_rxmtyin7  <= lbus_rxmtyin2fs0;
                    -- EOP is also aligned to 48 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin3fs1;
                    aligned_rxeopin1  <= lbus_rxeopin4fs1;
                    aligned_rxeopin2  <= lbus_rxeopin5fs1;
                    aligned_rxeopin3  <= lbus_rxeopin6fs1;
                    aligned_rxeopin4  <= lbus_rxeopin7fs1;
                    aligned_rxeopin5  <= lbus_rxeopin0fs0;
                    aligned_rxeopin6  <= lbus_rxeopin1fs0;
                    aligned_rxeopin7  <= lbus_rxeopin2fs0;
                    -- ENA is also aligned to 48 byte boundary
                    aligned_rxenain0  <= lbus_rxenain3fs1;
                    aligned_rxenain1  <= lbus_rxenain4fs1;
                    aligned_rxenain2  <= lbus_rxenain5fs1;
                    aligned_rxenain3  <= lbus_rxenain6fs1;
                    aligned_rxenain4  <= lbus_rxenain7fs1;
                    aligned_rxenain5  <= lbus_rxenain0fs0;
                    aligned_rxenain6  <= lbus_rxenain1fs0;
                    aligned_rxenain7  <= lbus_rxenain2fs0;

                    aligned_rxvldin  <= lbus_rxvldinfs1 or lbus_rxvldinfs0; 

                when b"100" =>
                    -- Data is aligned to 64 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain4fs1;
                    aligned_rxdatain1 <= lbus_rxdatain5fs1;
                    aligned_rxdatain2 <= lbus_rxdatain6fs1;
                    aligned_rxdatain3 <= lbus_rxdatain7fs1;
                    aligned_rxdatain4 <= lbus_rxdatain0fs0;
                    aligned_rxdatain5 <= lbus_rxdatain1fs0;
                    aligned_rxdatain6 <= lbus_rxdatain2fs0;
                    aligned_rxdatain7 <= lbus_rxdatain3fs0;
                    -- Mty is also aligned to 64 byte boundary
                    aligned_rxmtyin0  <= lbus_rxmtyin4fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin5fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin3  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin4  <= lbus_rxmtyin0fs0;
                    aligned_rxmtyin5  <= lbus_rxmtyin1fs0;
                    aligned_rxmtyin6  <= lbus_rxmtyin2fs0;
                    aligned_rxmtyin7  <= lbus_rxmtyin3fs0;
                    -- EOP is also aligned to 64 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin4fs1;
                    aligned_rxeopin1  <= lbus_rxeopin5fs1;
                    aligned_rxeopin2  <= lbus_rxeopin6fs1;
                    aligned_rxeopin3  <= lbus_rxeopin7fs1;
                    aligned_rxeopin4  <= lbus_rxeopin0fs0;
                    aligned_rxeopin5  <= lbus_rxeopin1fs0;
                    aligned_rxeopin6  <= lbus_rxeopin2fs0;
                    aligned_rxeopin7  <= lbus_rxeopin3fs0;
                    -- ENA is also aligned to 64 byte boundary
                    aligned_rxenain0  <= lbus_rxenain4fs1;
                    aligned_rxenain1  <= lbus_rxenain5fs1;
                    aligned_rxenain2  <= lbus_rxenain6fs1;
                    aligned_rxenain3  <= lbus_rxenain7fs1;
                    aligned_rxenain4  <= lbus_rxenain0fs0;
                    aligned_rxenain5  <= lbus_rxenain1fs0;
                    aligned_rxenain6  <= lbus_rxenain2fs0;
                    aligned_rxenain7  <= lbus_rxenain3fs0;

                    aligned_rxvldin  <= lbus_rxvldinfs1 or lbus_rxvldinfs0;

                when b"101" =>
                    -- Data is aligned to 80 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain5fs1;
                    aligned_rxdatain1 <= lbus_rxdatain6fs1;
                    aligned_rxdatain2 <= lbus_rxdatain7fs1;
                    aligned_rxdatain3 <= lbus_rxdatain0fs0;
                    aligned_rxdatain4 <= lbus_rxdatain1fs0;
                    aligned_rxdatain5 <= lbus_rxdatain2fs0;
                    aligned_rxdatain6 <= lbus_rxdatain3fs0;
                    aligned_rxdatain7 <= lbus_rxdatain4fs0;
                    -- Mty is also aligned to 80 byte boundary
                    aligned_rxmtyin0  <= lbus_rxmtyin5fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin3  <= lbus_rxmtyin0fs0;
                    aligned_rxmtyin4  <= lbus_rxmtyin1fs0;
                    aligned_rxmtyin5  <= lbus_rxmtyin2fs0;
                    aligned_rxmtyin6  <= lbus_rxmtyin3fs0;
                    aligned_rxmtyin7  <= lbus_rxmtyin4fs0;
                    -- EOP is also aligned to 80 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin5fs1;
                    aligned_rxeopin1  <= lbus_rxeopin6fs1;
                    aligned_rxeopin2  <= lbus_rxeopin7fs1;
                    aligned_rxeopin3  <= lbus_rxeopin0fs0;
                    aligned_rxeopin4  <= lbus_rxeopin1fs0;
                    aligned_rxeopin5  <= lbus_rxeopin2fs0;
                    aligned_rxeopin6  <= lbus_rxeopin3fs0;
                    aligned_rxeopin7  <= lbus_rxeopin4fs0;
                    -- ENA is also aligned to 80 byte boundary
                    aligned_rxenain0  <= lbus_rxenain5fs1;
                    aligned_rxenain1  <= lbus_rxenain6fs1;
                    aligned_rxenain2  <= lbus_rxenain7fs1;
                    aligned_rxenain3  <= lbus_rxenain0fs0;
                    aligned_rxenain4  <= lbus_rxenain1fs0;
                    aligned_rxenain5  <= lbus_rxenain2fs0;
                    aligned_rxenain6  <= lbus_rxenain3fs0;
                    aligned_rxenain7  <= lbus_rxenain4fs0;

                    aligned_rxvldin  <= lbus_rxvldinfs1 or lbus_rxvldinfs0;

                when b"110" =>
                    -- Data is aligned to 96 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain6fs1;
                    aligned_rxdatain1 <= lbus_rxdatain7fs1;
                    aligned_rxdatain2 <= lbus_rxdatain0fs0;
                    aligned_rxdatain3 <= lbus_rxdatain1fs0;
                    aligned_rxdatain4 <= lbus_rxdatain2fs0;
                    aligned_rxdatain5 <= lbus_rxdatain3fs0;
                    aligned_rxdatain6 <= lbus_rxdatain4fs0;
                    aligned_rxdatain7 <= lbus_rxdatain5fs0;
                    -- Mty is also aligned to 96 byte boundary
                    aligned_rxmtyin0  <= lbus_rxmtyin6fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin2  <= lbus_rxmtyin0fs0;
                    aligned_rxmtyin3  <= lbus_rxmtyin1fs0;
                    aligned_rxmtyin4  <= lbus_rxmtyin2fs0;
                    aligned_rxmtyin5  <= lbus_rxmtyin3fs0;
                    aligned_rxmtyin6  <= lbus_rxmtyin4fs0;
                    aligned_rxmtyin7  <= lbus_rxmtyin5fs0;
                    -- EOP is also aligned to 96 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin6fs1;
                    aligned_rxeopin1  <= lbus_rxeopin7fs1;
                    aligned_rxeopin2  <= lbus_rxeopin0fs0;
                    aligned_rxeopin3  <= lbus_rxeopin1fs0;
                    aligned_rxeopin4  <= lbus_rxeopin2fs0;
                    aligned_rxeopin5  <= lbus_rxeopin3fs0;
                    aligned_rxeopin6  <= lbus_rxeopin4fs0;
                    aligned_rxeopin7  <= lbus_rxeopin5fs0;
                    -- ENA is also aligned to 96 byte boundary
                    aligned_rxenain0  <= lbus_rxenain6fs1;
                    aligned_rxenain1  <= lbus_rxenain7fs1;
                    aligned_rxenain2  <= lbus_rxenain0fs0;
                    aligned_rxenain3  <= lbus_rxenain1fs0;
                    aligned_rxenain4  <= lbus_rxenain2fs0;
                    aligned_rxenain5  <= lbus_rxenain3fs0;
                    aligned_rxenain6  <= lbus_rxenain4fs0;
                    aligned_rxenain7  <= lbus_rxenain5fs0;

                    aligned_rxvldin  <= lbus_rxvldinfs1 or lbus_rxvldinfs0;

                when b"111" =>
                    -- Data is aligned to 112 byte boundary
                    aligned_rxdatain0 <= lbus_rxdatain7fs1;
                    aligned_rxdatain1 <= lbus_rxdatain0fs0;
                    aligned_rxdatain2 <= lbus_rxdatain1fs0;
                    aligned_rxdatain3 <= lbus_rxdatain2fs0;
                    aligned_rxdatain4 <= lbus_rxdatain3fs0;
                    aligned_rxdatain5 <= lbus_rxdatain4fs0;
                    aligned_rxdatain6 <= lbus_rxdatain5fs0;
                    aligned_rxdatain7 <= lbus_rxdatain6fs0;
                    -- Mty is also aligned to 112 byte boundary
                    aligned_rxmtyin0  <= lbus_rxmtyin7fs1;
                    aligned_rxmtyin1  <= lbus_rxmtyin0fs0;
                    aligned_rxmtyin2  <= lbus_rxmtyin1fs0;
                    aligned_rxmtyin3  <= lbus_rxmtyin2fs0;
                    aligned_rxmtyin4  <= lbus_rxmtyin3fs0;
                    aligned_rxmtyin5  <= lbus_rxmtyin4fs0;
                    aligned_rxmtyin6  <= lbus_rxmtyin5fs0;
                    aligned_rxmtyin7  <= lbus_rxmtyin6fs0;
                    -- EOP is also aligned to 112 byte boundary
                    aligned_rxeopin0  <= lbus_rxeopin7fs1;
                    aligned_rxeopin1  <= lbus_rxeopin0fs0;
                    aligned_rxeopin2  <= lbus_rxeopin1fs0;
                    aligned_rxeopin3  <= lbus_rxeopin2fs0;
                    aligned_rxeopin4  <= lbus_rxeopin3fs0;
                    aligned_rxeopin5  <= lbus_rxeopin4fs0;
                    aligned_rxeopin6  <= lbus_rxeopin5fs0;
                    aligned_rxeopin7  <= lbus_rxeopin6fs0;
                    -- ENA is also aligned to 112 byte boundary
                    aligned_rxenain0  <= lbus_rxenain7fs1;
                    aligned_rxenain1  <= lbus_rxenain0fs0;
                    aligned_rxenain2  <= lbus_rxenain1fs0;
                    aligned_rxenain3  <= lbus_rxenain2fs0;
                    aligned_rxenain4  <= lbus_rxenain3fs0;
                    aligned_rxenain5  <= lbus_rxenain4fs0;
                    aligned_rxenain6  <= lbus_rxenain5fs0;
                    aligned_rxenain7  <= lbus_rxenain6fs0;

                    aligned_rxvldin  <= lbus_rxvldinfs1 or lbus_rxvldinfs0;

                when others =>
                    null;
            end case;
        end if;
    end process AlignmentBarrelShifterProc;

    CurrentAlignmentProc : process(lbus_rxclk)
    begin
        if rising_edge(lbus_rxclk) then
            if (lbus_rxreset = '1') then
                CurrentAlignment <= (others => '0');
            else
                if (lbus_rxsopin0 = '1') then
                    -- The SOP is in segment 0
                    -- The alignment is 64 bytes
                    CurrentAlignment <= b"000";
                else
                    if (lbus_rxsopin1 = '1') then
                        -- The SOP is in segment 1
                        -- The alignment is 16 bytes
                        CurrentAlignment <= b"001";
                    else
                        if (lbus_rxsopin2 = '1') then
                            -- The SOP is in segment 2
                            -- The alignment is 32 bytes
                            CurrentAlignment <= b"010";
                        else
                            if (lbus_rxsopin3 = '1') then
                                -- The SOP is in segment 3
                                -- The alignment is 48 bytes
                                CurrentAlignment <= b"011";
                            else
                                if (lbus_rxsopin4 = '1') then
                                    -- The SOP is in segment 4
                                    -- The alignment is 64 bytes
                                    CurrentAlignment <= b"100";
                                else
                                    if (lbus_rxsopin5 = '1') then
                                        -- The SOP is in segment 5
                                        -- The alignment is 80 bytes
                                        CurrentAlignment <= b"101";
                                    else
                                        if (lbus_rxsopin6 = '1') then
                                            -- The SOP is in segment 6
                                            -- The alignment is 96 bytes
                                            CurrentAlignment <= b"110";
                                        else
                                            if (lbus_rxsopin7 = '1') then
                                                -- The SOP is in segment 7
                                                -- The alignment is 112 bytes
                                                CurrentAlignment <= b"111";
                                            else
                                                null;
                                            end if;
                                        end if;
                                    end if;
                                end if;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process CurrentAlignmentProc;

    Seg0DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain0,
            axis_dataout => axis_tx_tdata(127 downto 0)
        );

    Seg0MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain0,
            lbus_rxmty    => aligned_rxmtyin0,
            axis_tkeepout => axis_tx_tkeep(15 downto 0)
        );

    Seg1DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain1,
            axis_dataout => axis_tx_tdata(255 downto 128)
        );

    Seg1MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain1,
            lbus_rxmty    => aligned_rxmtyin1,
            axis_tkeepout => axis_tx_tkeep(31 downto 16)
        );

    Seg2DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain2,
            axis_dataout => axis_tx_tdata(383 downto 256)
        );

    Seg2MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain2,
            lbus_rxmty    => aligned_rxmtyin2,
            axis_tkeepout => axis_tx_tkeep(47 downto 32)
        );

    Seg3DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain3,
            axis_dataout => axis_tx_tdata(511 downto 384)
        );

    Seg3MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain3,
            lbus_rxmty    => aligned_rxmtyin3,
            axis_tkeepout => axis_tx_tkeep(63 downto 48)
        );

    Seg4DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain4,
            axis_dataout => axis_tx_tdata(639 downto 512)
        );

    Seg4MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain4,
            lbus_rxmty    => aligned_rxmtyin4,
            axis_tkeepout => axis_tx_tkeep(79 downto 64)
        );

    Seg5DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain5,
            axis_dataout => axis_tx_tdata(767 downto 640)
        );

    Seg5MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain5,
            lbus_rxmty    => aligned_rxmtyin5,
            axis_tkeepout => axis_tx_tkeep(95 downto 80)
        );

    Seg6DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain6,
            axis_dataout => axis_tx_tdata(895 downto 768)
        );

    Seg6MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain6,
            lbus_rxmty    => aligned_rxmtyin6,
            axis_tkeepout => axis_tx_tkeep(111 downto 96)
        );

    Seg7DataMapping_i : maplbusdatatoaxis400g
        port map(
            lbus_rxclk   => lbus_rxclk,
            lbus_data    => aligned_rxdatain7,
            axis_dataout => axis_tx_tdata(1023 downto 896)
        );

    Seg7MTYMapping_i : mapmtytotkeep
        port map(
            lbus_rxclk    => lbus_rxclk,
            lbus_rxen     => aligned_rxenain7,
            lbus_rxmty    => aligned_rxmtyin7,
            axis_tkeepout => axis_tx_tkeep(127 downto 112)
        );

end architecture rtl;
