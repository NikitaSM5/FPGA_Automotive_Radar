-- =========================================================================
-- dac_marker_if.vhd
-- Drives a 14-bit parallel DAC with a rectangular marker.
-- On gate_in='1' outputs HIGH level, otherwise LOW level. Levels are
-- configurable via generics and/or package constants.
--
-- Clocking: same single clock domain as the rest (ADC DCO).
-- Dependencies: use work.radar_pkg.all;
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity dac_marker_if is
  generic (
    -- Default output codes; can be overridden at instantiation.
    G_LEVEL_LOW  : signed(DAC_W-1 downto 0) := DAC_MARK_LOW;
    G_LEVEL_HIGH : signed(DAC_W-1 downto 0) := DAC_MARK_HIGH
  );
  port (
    clk       : in  std_logic;                         -- system clock
    rst_n     : in  std_logic;                         -- active-low sync reset
    gate_in   : in  std_logic;                         -- rectangular gate (from chirp_timing)
    -- Optional runtime override of levels
    use_dyn   : in  std_logic := '0';                
    level_low : in  signed(DAC_W-1 downto 0) := (others => '0');
    level_high: in  signed(DAC_W-1 downto 0) := (others => '0');
    -- DAC parallel data bus (connect directly to AD974 data pins)
    dac_data  : out signed(DAC_W-1 downto 0)
  );
end entity;

architecture rtl of dac_marker_if is
  signal r_data : signed(DAC_W-1 downto 0) := (others => '0');
  signal low_v  : signed(DAC_W-1 downto 0);
  signal high_v : signed(DAC_W-1 downto 0);
begin
  -- Select between generics and dynamic inputs
  low_v  <= level_low  when use_dyn = '1' else G_LEVEL_LOW;
  high_v <= level_high when use_dyn = '1' else G_LEVEL_HIGH;

  p_out : process(clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        r_data <= (others => '0');
      else
        if gate_in = '1' then
          r_data <= high_v;
        else
          r_data <= low_v;
        end if;
      end if;
    end if;
  end process;

  dac_data <= r_data;
end architecture;
