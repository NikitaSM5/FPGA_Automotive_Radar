-- =========================================================================
-- tb_win_mul_q15_const.vhd
-- Minimal testbench for win_mul_q15:
-- * Drives constant max-value I/Q across two frames of RANGE_WIN_LEN.
-- * No text checks, no scoreboard — observe waveforms only.
-- * tvalid asserted during frames, tlast at last sample of each frame.
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;  -- expects IQ_W, RANGE_WIN_LEN, RANGE_WIN_Q15, etc.

entity tb_win_mul_q15 is
end entity;

architecture sim of tb_win_mul_q15 is
  -- Clock / reset
  constant CLK_PER : time := 15.384615 ns; -- ~65 MHz
  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';

  -- DUT I/F
  signal i_in       : signed(IQ_W-1 downto 0) := (others => '0');
  signal q_in       : signed(IQ_W-1 downto 0) := (others => '0');
  signal tvalid_in  : std_logic := '0';
  signal tlast_in   : std_logic := '0';

  signal i_out      : signed(IQ_W-1 downto 0);
  signal q_out      : signed(IQ_W-1 downto 0);
  signal tvalid_out : std_logic;
  signal tlast_out  : std_logic;

  -- Test parameters
  constant NFRAMES : integer := 2;
  constant L       : integer := RANGE_WIN_LEN;

  -- Constant input values (max positive Q15.0)
  constant I_MAX : signed(IQ_W-1 downto 0) := to_signed(2**(IQ_W-1) - 1, IQ_W);
  constant Q_MAX : signed(IQ_W-1 downto 0) := to_signed(2**(IQ_W-1) - 1, IQ_W);
begin
  -- Clock
  p_clk : process
  begin
    clk <= '0'; wait for CLK_PER/2;
    clk <= '1'; wait for CLK_PER/2;
  end process;

  -- DUT
  u_dut : entity work.win_mul_q15
    generic map (
      G_WIN_SEL => 1          
    )
    port map (
      clk        => clk,
      rst_n      => rst_n,
      i_in       => i_in,
      q_in       => q_in,
      tvalid_in  => tvalid_in,
      tlast_in   => tlast_in,
      i_out      => i_out,
      q_out      => q_out,
      tvalid_out => tvalid_out,
      tlast_out  => tlast_out
    );

  -- Reset
  p_reset : process
  begin
    rst_n <= '0';
    wait for 10*CLK_PER;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait;
  end process;

  -- Stimulus: two frames of constant data
  p_stim : process
    variable f, k : integer;
  begin
    -- Wait reset deasserted
    wait until rst_n = '1';
    wait until rising_edge(clk);

    tvalid_in <= '0';
    tlast_in  <= '0';
    i_in      <= (others => '0');
    q_in      <= (others => '0');

    for f in 0 to NFRAMES-1 loop
      for k in 0 to L-1 loop
        -- Drive constant inputs
        i_in <= I_MAX;
        q_in <= Q_MAX;

        tvalid_in <= '1';
        if (k = L-1) then
          tlast_in <= '1';
        else
          tlast_in <= '0';
        end if;

        wait until rising_edge(clk);
      end loop;

      -- Idle gap between frames
      tvalid_in <= '0';
      tlast_in  <= '0';
      i_in      <= (others => '0');
      q_in      <= (others => '0');
      wait for 5*CLK_PER;
    end loop;

    -- Stop
    tvalid_in <= '0';
    tlast_in  <= '0';
    i_in      <= (others => '0');
    q_in      <= (others => '0');

    wait for 100*CLK_PER;
    report "SIM DONE" severity note;
    wait;
  end process;

end architecture;
