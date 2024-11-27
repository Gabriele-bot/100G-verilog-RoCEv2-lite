library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_handshake_monitor is
    generic(
        WINDOW_WIDTH : integer := 16
    );
    port(
        clk           : in  std_logic;
        rst           : in  std_logic;
        --------------------------------------------
        s_axis_tvalid : in  std_logic;
        m_axis_tready : in  std_logic;
        --------------------------------------------
        n_valid_up    : out std_logic_vector(WINDOW_WIDTH - 1 downto 0);
        n_ready_up    : out std_logic_vector(WINDOW_WIDTH - 1 downto 0);
        n_both_up     : out std_logic_vector(WINDOW_WIDTH - 1 downto 0)
    );
end entity axis_handshake_monitor;

architecture RTL of axis_handshake_monitor is

    signal valid_ctr : unsigned(WINDOW_WIDTH - 1 downto 0);
    signal ready_ctr : unsigned(WINDOW_WIDTH - 1 downto 0);
    signal both_ctr  : unsigned(WINDOW_WIDTH - 1 downto 0);
    signal clk_ctr   : unsigned(WINDOW_WIDTH - 1 downto 0);

    type srl_counter_t is array (7 downto 0) of unsigned(WINDOW_WIDTH - 1 downto 0);
    signal valid_ctr_srl : srl_counter_t;
    signal ready_ctr_srl : srl_counter_t;
    signal both_ctr_srl  : srl_counter_t;

begin

    process(clk) is
    begin
        if rising_edge(clk) then
            if rst then
                clk_ctr   <= (others => '0');
                valid_ctr <= (others => '0');
                ready_ctr <= (others => '0');
                both_ctr  <= (others => '0');
            else
                clk_ctr <= clk_ctr + 1;
                if clk_ctr = to_unsigned(0, WINDOW_WIDTH) then
                    valid_ctr <= (others => '0');
                    ready_ctr <= (others => '0');
                    both_ctr  <= (others => '0');
                else
                    if s_axis_tvalid then
                        valid_ctr <= valid_ctr + 1;
                    end if;
                    if m_axis_tready then
                        ready_ctr <= ready_ctr + 1;
                    end if;
                    if s_axis_tvalid and m_axis_tready then
                        both_ctr <= both_ctr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk) is
    begin
        if rising_edge(clk) then
            if clk_ctr = to_unsigned(0, WINDOW_WIDTH) then
                valid_ctr_srl(0)                           <= valid_ctr;
                ready_ctr_srl(0)                           <= ready_ctr;
                both_ctr_srl(0)                            <= both_ctr;
                valid_ctr_srl(valid_ctr_srl'high downto 1) <= valid_ctr_srl(valid_ctr_srl'high - 1 downto 0);
                ready_ctr_srl(ready_ctr_srl'high downto 1) <= ready_ctr_srl(ready_ctr_srl'high - 1 downto 0);
                both_ctr_srl(both_ctr_srl'high downto 1)   <= both_ctr_srl(both_ctr_srl'high - 1 downto 0);
            end if;
        end if;
    end process;

    avg_p : process(clk) is
        variable valid_ctr_avg_var : unsigned(WINDOW_WIDTH + 3 - 1 downto 0) := (others => '0');
        variable ready_ctr_avg_var : unsigned(WINDOW_WIDTH + 3 - 1 downto 0) := (others => '0');
        variable both_ctr_avg_var  : unsigned(WINDOW_WIDTH + 3 - 1 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            valid_ctr_avg_var := (others => '0');
            ready_ctr_avg_var := (others => '0');
            both_ctr_avg_var  := (others => '0');
            for i in 0 to valid_ctr_srl'high loop
                valid_ctr_avg_var := valid_ctr_avg_var + valid_ctr_srl(i);
            end loop;
            for i in 0 to ready_ctr_srl'high loop
                ready_ctr_avg_var := ready_ctr_avg_var + ready_ctr_srl(i);
            end loop;
            for i in 0 to both_ctr_srl'high loop
                both_ctr_avg_var := both_ctr_avg_var + both_ctr_srl(i);
            end loop;
            n_valid_up        <= std_logic_vector(valid_ctr_avg_var(valid_ctr_avg_var'high downto 3));
            n_ready_up        <= std_logic_vector(ready_ctr_avg_var(ready_ctr_avg_var'high downto 3));
            n_both_up         <= std_logic_vector(both_ctr_avg_var(both_ctr_avg_var'high downto 3));
        end if;
    end process;

end architecture RTL;
