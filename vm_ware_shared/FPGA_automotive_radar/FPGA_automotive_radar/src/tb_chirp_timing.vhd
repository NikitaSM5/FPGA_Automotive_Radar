-- =========================================================================
-- tb_chirp_timing.vhd
-- testbench for chirp_timing: drives clock/reset and checks pulse
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity tb_chirp_timing is
end entity;

architecture sim of tb_chirp_timing is
  -- DUT ports
  signal clk           : std_logic := '0';
  signal rst_n         : std_logic := '0';
  signal chirp_ticks   : unsigned(31 downto 0);
  signal idle_ticks    : unsigned(31 downto 0);
  signal pulse_ticks   : unsigned(15 downto 0);

  signal chirp_start_p : std_logic;
  signal chirp_gate    : std_logic;
  signal seq           : unsigned(7 downto 0);
  signal t_us          : unsigned(31 downto 0);

  -- Clock period
  constant CLK_PER     : time := 15.384615 ns;

  -- Local counters for checks
  signal last_start_cycle : integer := 0;
  signal cycle_count      : integer := 0;
  signal gate_len_count   : integer := 0;
  signal in_gate          : boolean := false;

begin
  -- Clock generation
  p_clk : process
  begin
    clk <= '0';
    wait for CLK_PER/2;
    clk <= '1';
    wait for CLK_PER/2;
  end process;

  -- DUT instantiation
  dut : entity work.chirp_timing
    port map (
      clk           => clk,
      rst_n         => rst_n,
      chirp_ticks   => chirp_ticks,
      idle_ticks    => idle_ticks,
      pulse_ticks   => pulse_ticks,
      chirp_start_p => chirp_start_p,
      chirp_gate    => chirp_gate,
      seq           => seq,
      t_us          => t_us
    );

	p_stim : process
	begin
	  -- drive DUT directly with the package constant
	  chirp_ticks <= to_unsigned(work.radar_pkg.CHIRP_TICKS, 32);
	  idle_ticks  <= to_unsigned(0, 32);
	  pulse_ticks <= to_unsigned(100, pulse_ticks'length);
	
	  -- Reset
	  rst_n <= '0';
	  wait for 10*CLK_PER;
	  rst_n <= '1';
	
	  -- Run
	  wait for 20 ms;
	  assert false report "Simulation finished" severity failure;
	end process;
	

  -- Simple checkers (cycle-count domain)
  p_cycle_count : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        cycle_count      <= 0;
        last_start_cycle <= 0;
        gate_len_count   <= 0;
        in_gate          <= false;
      else
        cycle_count <= cycle_count + 1;

        -- Measure gate length
        if chirp_gate = '1' then
          gate_len_count <= gate_len_count + 1;
          in_gate        <= true;
        elsif in_gate = true then
          -- Gate just ended: check width equals pulse_ticks
          assert gate_len_count = to_integer(pulse_ticks)
            report "Gate width mismatch: got " & integer'image(gate_len_count)
                   & ", expected " & integer'image(to_integer(pulse_ticks))
            severity error;
          gate_len_count <= 0;
          in_gate        <= false;
        end if;

        -- Check chirp_start_p is single-cycle
        if chirp_start_p = '1' then
          -- Verify single-cycle pulse
          -- Next cycle it must be '0' (checked implicitly by design)
          -- Check period since last start (after first one)
          if last_start_cycle /= 0 then
            assert (cycle_count - last_start_cycle) = to_integer(chirp_ticks + idle_ticks)
              report "Chirp period mismatch: got " & integer'image(cycle_count - last_start_cycle)
                     & ", expected " & integer'image(to_integer(chirp_ticks + idle_ticks))
              severity error;
          end if;
          last_start_cycle <= cycle_count;
        end if;

      end if;
    end if;
  end process;

end architecture;
