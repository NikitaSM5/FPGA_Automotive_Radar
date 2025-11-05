-- =========================================================================
-- tb_adc_if_iq.vhd
-- Testbench for adc_if_iq:
--   * Drives Offset Binary 12-bit ramps on I and Q
--   * Issues chirp_start_p pulses
--   * Verifies: start latency, exact n_samp valid samples, tlast alignment,
--               no stray valid between chirps
-- Notes:
--   * Assumes work.radar_pkg provides ADC_W=12, IQ_W=16, CHIRP_TICKS, etc.
--   * Data pipeline latency RAW->OUT is 2 cycles; VALID is delayed accordingly.
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity tb_adc_if_iq is
end entity;

architecture sim of tb_adc_if_iq is
    -- Clock ~65 MHz
    constant CLK_PER : time := 15.384615 ns;

    -- Samples-per-chirp from package; expose as int and unsigned
    constant NS_I : integer := work.radar_pkg.CHIRP_TICKS;               -- for assertions
    constant NS_U : unsigned(15 downto 0) := to_unsigned(NS_I, 16);      -- for DUT port

    -- Expected pipeline latency from chirp_start_p to first valid output
    -- RAW -> OUT = 2 cycles; VALID is aligned to OUT
    constant PIPE_LAT : integer := 2;

    -- Chirp control
    constant NUM_CHIRPS : integer := 4;
    constant GAP_CYCLES : integer := 5;  -- idle cycles between chirps (no output expected)

    -- DUT I/O
    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    signal adc_a : std_logic_vector(ADC_W - 1 downto 0) := (others => '0');
    signal adc_b : std_logic_vector(ADC_W - 1 downto 0) := (others => '0');

    signal chirp_start_p : std_logic := '0';
    signal n_samp        : unsigned(15 downto 0);

    signal tvalid_in : std_logic := '1';

    signal i_out    : signed(IQ_W - 1 downto 0);
    signal q_out    : signed(IQ_W - 1 downto 0);
    signal tvalid   : std_logic;
    signal tlast_ch : std_logic;

    -- Local monitors
    signal cyc : integer := 0;

    -- Helper: convert signed [-2048..2047] to 12-bit Offset Binary
    function to_offbin12(x : integer) return std_logic_vector is
        variable y : integer := x + 2048;
    begin
        if y < 0 then
            y := 0;
        end if;
        if y > 4095 then
            y := 4095;
        end if;
        return std_logic_vector(to_unsigned(y, 12));
    end function;

    -- Wait N clock cycles (blocking)
    procedure wait_cycles(n : in integer) is
    begin
        for k in 1 to n loop
            wait for CLK_PER;
        end loop;
    end procedure;

begin
    -- Clock generator
    p_clk : process
    begin
        clk <= '0';
        wait for CLK_PER/2;
        clk <= '1';
        wait for CLK_PER/2;
    end process;

    -- DUT: Offset Binary mode
    dut : entity work.adc_if_iq
        generic map(
            G_INPUT_FMT_TC => 0, -- 0 = Offset Binary
            G_DC_I => (others => '0'),
            G_DC_Q => (others => '0'),
            G_GAIN_SHIFT => 0
        )
        port map(
            clk => clk,
            rst_n => rst_n,
            adc_a => adc_a,
            adc_b => adc_b,
            chirp_start_p => chirp_start_p,
            n_samp => n_samp,
            tvalid_in => tvalid_in,
            i_out => i_out,
            q_out => q_out,
            tvalid => tvalid,
            tlast_ch => tlast_ch
        );

    -- Global cycle counter (for readable asserts)
    p_cyc : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                cyc <= 0;
            else
                cyc <= cyc + 1;
            end if;
        end if;
    end process;

    -- Stimulus / control
    p_stim : process
    begin
        n_samp <= NS_U;

        -- Reset
        rst_n <= '0';
        wait_cycles(20);
        rst_n <= '1';

        -- Generate several chirps, spaced by a small idle gap
        for c in 0 to NUM_CHIRPS-1 loop
            chirp_start_p <= '1';
            wait_cycles(1);
            chirp_start_p <= '0';

            -- Wait full chirp length + gap in clock cycles
            wait_cycles(NS_I + GAP_CYCLES);
        end loop;

        -- End of simulation
        assert false report "tb_adc_if_iq finished OK" severity failure;
    end process;

    -- Drive synthetic ADC samples (simple ramps)
    p_adc_drive : process (clk)
        variable i_val : integer := -2048;
        variable q_val : integer := 2047;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                i_val := -2048;
                q_val := 2047;
                adc_a <= (others => '0');
                adc_b <= (others => '0');
            else
                -- simple ramp patterns in Offset Binary domain
                adc_a <= to_offbin12(i_val);
                adc_b <= to_offbin12(q_val);

                i_val := i_val + 1;
                if i_val > 2047 then
                    i_val := -2048;
                end if;

                q_val := q_val - 1;
                if q_val < -2048 then
                    q_val := 2047;
                end if;
            end if;
        end if;
    end process;

    -- Checkers: start latency, exact length, tlast on the final valid, and quiet gaps
    p_checks : process (clk)
        -- FSM for monitoring a chirp on OUTPUT interface
        type state_t is (IDLE, WAIT_TVALID, IN_CHIRP);
        variable st : state_t := IDLE;

        variable exp_first_valid_cyc : integer := 0;
        variable valid_count         : integer := 0;
        variable gap_guard           : integer := 0; -- counts idle cycles between chirps
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                st := IDLE;
                exp_first_valid_cyc := 0;
                valid_count := 0;
                gap_guard := 0;
            else
                -- Observe chirp_start_p on TB side and arm the checker
                if chirp_start_p = '1' then
                    -- Expect first output-valid exactly PIPE_LAT cycles later
                    exp_first_valid_cyc := cyc + PIPE_LAT;
                    valid_count := 0;
                    st := WAIT_TVALID;
                    gap_guard := 0;
                end if;

                case st is
                    when IDLE =>
                        -- No output expected outside chirps:
                        if tvalid = '1' then
                            assert false report "Unexpected tvalid in IDLE state (between chirps)" severity error;
                        end if;

                    when WAIT_TVALID =>
                        -- Wait for the very first tvalid and check latency
                        if tvalid = '1' then
                            assert cyc = exp_first_valid_cyc
                                report "First tvalid latency mismatch: got " & integer'image(cyc - (exp_first_valid_cyc - PIPE_LAT)) &
                                       " cycles since chirp_start; expected " & integer'image(PIPE_LAT)
                                severity error;
                            valid_count := 1;
                            assert tlast_ch = '0'
                                report "tlast_ch asserted on first sample (should be 0)"
                                severity error;
                            st := IN_CHIRP;
                        else
                            -- Still waiting: make sure nothing toggles spuriously
                            null;
                        end if;

                    when IN_CHIRP =>
                        if tvalid = '1' then
                            if valid_count < NS_I then
                                -- For samples 1..(NS_I-1), tlast must be 0
                                assert tlast_ch = '0'
                                  report "tlast_ch asserted early at sample #" & integer'image(valid_count)
                                  severity error;
                                valid_count := valid_count + 1;
                            end if;

                            -- The last (NS_I-th) valid must have tlast=1
                            if valid_count = NS_I then
                                assert tlast_ch = '1'
                                  report "tlast_ch not asserted on the last sample of chirp"
                                  severity error;
                                -- Next state: expect silence until next chirp_start_p
                                st := IDLE;
                                gap_guard := 0;
                            end if;
                        else
                            -- Once IN_CHIRP, we expect continuous tvalid for NS_I samples
                            assert false
                              report "tvalid dropped inside chirp at sample #" & integer'image(valid_count)
                              severity error;
                        end if;
                end case;

                -- Optional: observe a small quiet gap between chirps (sanity)
                if st = IDLE then
                    if gap_guard < GAP_CYCLES then
                        if tvalid = '1' then
                            assert false report "tvalid seen during expected quiet gap" severity error;
                        end if;
                        gap_guard := gap_guard + 1;
                    end if;
                end if;

            end if;
        end if;
    end process;

end architecture;
