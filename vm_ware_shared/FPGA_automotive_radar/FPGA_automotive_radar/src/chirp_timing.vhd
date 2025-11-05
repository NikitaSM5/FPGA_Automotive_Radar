-- =========================================================================
-- chirp_timing.vhd
-- Generates a 1-cycle pulse at the start of each chirp and a rectangular
-- gate (for DAC marker) with programmable width. Also maintains a frame
-- sequence counter and a microsecond timestamp.
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity chirp_timing is
  port (
    clk            : in  std_logic;             -- system clock (ADC DCO)
    rst_n          : in  std_logic;             -- active-low synchronous reset

    -- Programmable timing
    chirp_ticks    : in  unsigned(31 downto 0); -- total chirp duration in clk ticks
    idle_ticks     : in  unsigned(31 downto 0); -- idle between chirps in clk ticks
    pulse_ticks    : in  unsigned(15 downto 0); -- DAC marker width in clk ticks

    -- Outputs
    chirp_start_p  : out std_logic;             -- 1-cycle pulse at chirp start
    chirp_gate     : out std_logic;             -- rectangular marker for DAC
    seq            : out unsigned(7 downto 0);  -- frame/chirp sequence counter
    t_us           : out unsigned(31 downto 0)  
  );
end entity;

architecture rtl of chirp_timing is

  -- Derived constant: number of clk ticks per microsecond
  constant TICKS_PER_US : natural := F_CLK / 1_000_000;

  -- Internal registers
  signal r_seq          : unsigned(7 downto 0)  := (others => '0');
  signal r_t_us         : unsigned(31 downto 0) := (others => '0');

  signal r_pulse_cnt    : unsigned(15 downto 0) := (others => '0');
  signal r_gate         : std_logic := '0';

  signal period_ticks   : unsigned(31 downto 0);  -- chirp + idle
  signal r_period_cnt   : unsigned(31 downto 0) := (others => '0');

  signal r_chirp_start  : std_logic := '0';

  -- Microsecond ticker
  signal r_us_div       : unsigned(15 downto 0) := (others => '0'); -- TICKS_PER_US <= 65535

begin

  -- Combine chirp and idle into a single period (all UNSIGNED)
  period_ticks <= chirp_ticks + idle_ticks;

  -- Main timing process
  p_timing : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        r_period_cnt  <= (others => '0');
        r_chirp_start <= '0';
        r_seq         <= (others => '0');
        r_pulse_cnt   <= (others => '0');
        r_gate        <= '0';
      else
        -- Default: deassert start pulse; assert only for 1 cycle when counter wraps
        r_chirp_start <= '0';

        -- Period counter: counts 0 .. period_ticks-1 (safe when period_ticks > 0)
        if r_period_cnt = (period_ticks - 1) then
          r_period_cnt  <= (others => '0');
          r_chirp_start <= '1';                 -- one-cycle pulse
          r_seq         <= r_seq + 1;           -- frame/chirp sequence increment

          -- Start (or restart) the DAC marker gate on chirp start
          if pulse_ticks = 0 then
            r_gate      <= '0';
            r_pulse_cnt <= (others => '0');
          else
            r_gate      <= '1';
            r_pulse_cnt <= (others => '0');
          end if;

        else
          r_period_cnt <= r_period_cnt + 1;

          -- Gate width handling
          if r_gate = '1' then
            if r_pulse_cnt = (pulse_ticks - 1) then
              r_gate      <= '0';
              r_pulse_cnt <= (others => '0');
            else
              r_pulse_cnt <= r_pulse_cnt + 1;
            end if;
          end if;

        end if;
      end if;
    end if;
  end process;

  -- Microsecond timestamp (free running)
  p_timestamp : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        r_us_div <= (others => '0');
        r_t_us   <= (others => '0');
      else
        if r_us_div = to_unsigned(TICKS_PER_US - 1, r_us_div'length) then
          r_us_div <= (others => '0');
          r_t_us   <= r_t_us + 1;
        else
          r_us_div <= r_us_div + 1;
        end if;
      end if;
    end if;
  end process;

  -- Output assignments
  chirp_start_p <= r_chirp_start;
  chirp_gate    <= r_gate;
  seq           <= r_seq;
  t_us          <= r_t_us;

end architecture;
