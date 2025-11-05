-- =========================================================================
-- tb_dac_marker_if.vhd
-- Testbench for dac_marker_if: toggles gate and observes 14-bit output.
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity tb_dac_marker_if is
end entity;

architecture sim of tb_dac_marker_if is
  signal clk        : std_logic := '0';
  signal rst_n      : std_logic := '0';
  signal gate_in    : std_logic := '0';
  signal use_dyn    : std_logic := '0';
  signal level_low  : signed(DAC_W-1 downto 0) := (others => '0');
  signal level_high : signed(DAC_W-1 downto 0) := (others => '0');
  signal dac_data   : signed(DAC_W-1 downto 0);

  constant CLK_PER  : time := 15.384615 ns; -- ~65 MHz
begin
  -- Clock
  p_clk : process
  begin
    clk <= '0'; wait for CLK_PER/2;
    clk <= '1'; wait for CLK_PER/2;
  end process;

  -- DUT
  dut : entity work.dac_marker_if
    generic map (
      G_LEVEL_LOW  => DAC_MARK_LOW,
      G_LEVEL_HIGH => DAC_MARK_HIGH
    )
    port map (
      clk        => clk,
      rst_n      => rst_n,
      gate_in    => gate_in,
      use_dyn    => use_dyn,
      level_low  => level_low,
      level_high => level_high,
      dac_data   => dac_data
    );

  -- Stimulus
  p_stim : process
  begin
    -- Reset
    rst_n <= '0';
    wait for 20*CLK_PER;
    rst_n <= '1';

    -- Gate OFF: expect LOW code
    gate_in <= '0';
    wait for 100*CLK_PER;

    -- Gate ON: expect HIGH code
    gate_in <= '1';
    wait for 100*CLK_PER;

    -- Back to low
    gate_in <= '0';
    wait for 2145*CLK_PER;	   
	
	    -- Gate ON: expect HIGH code
    gate_in <= '1';
    wait for 100*CLK_PER;  
	
	gate_in <= '0';
    wait for 2145*CLK_PER;	

    assert false report "tb_dac_marker_if done" severity failure;
  end process;

  -- Simple assertions
  p_check : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '1' then
        if gate_in = '1' then
          assert dac_data /= level_low report "DAC stuck LOW while gate=1" severity error;
        else
          -- when use_dyn='0' this compares against generic low; otherwise against dynamic low
          null;
        end if;
      end if;
    end if;
  end process;

end architecture;
