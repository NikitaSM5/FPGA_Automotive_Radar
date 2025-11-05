-- =========================================================================
-- adc_if_iq.vhd
-- AD9238 dual-channel (I/Q) front-end:
--   * Converts 12-bit ADC samples to signed Q15.0
--   * Starts output only after chirp_start_p and emits exactly n_samp samples
--   * tlast_ch is aligned to output data (accounts for pipeline latency)
--
-- SINGLE CLOCK DOMAIN (clk = ADC DCO)
-- Dependencies: work.radar_pkg (defines ADC_W, IQ_W, etc.)
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity adc_if_iq is
    generic (
        -- 0 = Offset Binary ADC input, nonzero = Two's Complement ADC input
        G_INPUT_FMT_TC : integer := 0;

        -- Fixed-point post-correction:
        --  y = arshift( (raw - DC), G_GAIN_SHIFT )
        G_DC_I       : signed(IQ_W - 1 downto 0) := (others => '0');
        G_DC_Q       : signed(IQ_W - 1 downto 0) := (others => '0');
        G_GAIN_SHIFT : natural := 0  -- arithmetic shift right after DC removal
    );
    port (
        clk   : in  std_logic;  -- ADC DCO
        rst_n : in  std_logic;  -- active-low synchronous reset

        -- Raw ADC inputs (12-bit per channel)
        adc_a : in  std_logic_vector(ADC_W - 1 downto 0); -- I
        adc_b : in  std_logic_vector(ADC_W - 1 downto 0); -- Q

        -- Chirp control
        chirp_start_p : in  std_logic;               -- 1-cycle pulse; starts a new chirp
        n_samp        : in  unsigned(15 downto 0);   -- samples per chirp (1..65535)

        -- Input sample valid (from ADC)
        tvalid_in : in  std_logic := '1';

        -- Stream output
        i_out    : out signed(IQ_W - 1 downto 0);
        q_out    : out signed(IQ_W - 1 downto 0);
        tvalid   : out std_logic;   -- valid aligned with i_out/q_out
        tlast_ch : out std_logic    -- asserted at the last sample of chirp (aligned)
    );
end entity;

architecture rtl of adc_if_iq is

    -- =======================
    -- Helpers / local signals
    -- =======================

    -- Convert 12-bit code to signed Q15.0
    --  Offset Binary: y = signed(unsigned(x)) - 2^(N-1)
    --  Two's Complement: sign-extend 12 -> 16
    function conv12_to_q15(
        x     : std_logic_vector(ADC_W - 1 downto 0);
        is_tc : boolean
    ) return signed is
        variable y16 : signed(IQ_W - 1 downto 0);
    begin
        if is_tc then
            -- two's complement input: sign-extend to IQ_W
            y16 := resize(signed(x), IQ_W);
        else
            -- offset-binary input: center around zero then sign-extend
            y16 := signed(resize(unsigned(x), IQ_W))
                 - to_signed(2 ** (ADC_W - 1), IQ_W);
        end if;
        return y16;
    end function;

    -- Arithmetic right shift for signed numbers
    function arshift(x : signed; sh : natural) return signed is
        variable r : signed(x'range) := x;
    begin
        if sh = 0 then
            return r;
        else
            return shift_right(r, sh); -- arithmetic for SIGNED per numeric_std
        end if;
    end function;

    -- Data path registers (3-stage: RAW -> CORR -> OUT)
    signal r_i_raw  : signed(IQ_W - 1 downto 0) := (others => '0');
    signal r_q_raw  : signed(IQ_W - 1 downto 0) := (others => '0');

    signal r_i_corr : signed(IQ_W - 1 downto 0) := (others => '0');
    signal r_q_corr : signed(IQ_W - 1 downto 0) := (others => '0');

    signal r_i_out  : signed(IQ_W - 1 downto 0) := (others => '0');
    signal r_q_out  : signed(IQ_W - 1 downto 0) := (others => '0');

    -- Chirp control (registered state)
    signal in_chirp : std_logic := '0';
    signal samp_cnt : unsigned(15 downto 0) := (others => '0');

    -- Valid / last pipelining to match data latency (2 cycles RAW->OUT)
    signal vld_d0, vld_d1, vld_d2 : std_logic := '0';
    signal tlast_d0, tlast_d1, tlast_d2 : std_logic := '0';

begin

    -- =======================
    -- Core synchronous logic
    -- =======================
    p_core : process (clk)
        variable is_tc_v      : boolean;
        variable in_chirp_v   : std_logic;  -- next-state for in_chirp (avoids losing the 1st sample)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                -- Data path
                r_i_raw  <= (others => '0');
                r_q_raw  <= (others => '0');
                r_i_corr <= (others => '0');
                r_q_corr <= (others => '0');
                r_i_out  <= (others => '0');
                r_q_out  <= (others => '0');

                -- Chirp control
                in_chirp <= '0';
                samp_cnt <= (others => '0');

                -- Valid/last pipelines
                vld_d0   <= '0';
                vld_d1   <= '0';
                vld_d2   <= '0';
                tlast_d0 <= '0';
                tlast_d1 <= '0';
                tlast_d2 <= '0';

            else
                -- Decode input format (static generic) once per cycle
                is_tc_v := (G_INPUT_FMT_TC /= 0);

                -- ======================
                -- 0) Chirp control (next-state)
                -- ======================
                in_chirp_v := in_chirp;  -- take current state

                -- External chirp_start_p immediately starts a chirp and resets the counter
                if chirp_start_p = '1' then
                    in_chirp_v := '1';
                    samp_cnt   <= (others => '0');
                end if;

                -- Count only when ADC data is present AND we are (next-state) inside chirp
                tlast_d0 <= '0';
                if (tvalid_in = '1') and (in_chirp_v = '1') then
                    if samp_cnt = (n_samp - 1) then
                        -- This input sample is the last one in the chirp
                        samp_cnt   <= (others => '0');
                        in_chirp_v := '0';
                        tlast_d0   <= '1';  -- raw "last" (to be pipelined)
                    else
                        samp_cnt <= samp_cnt + 1;
                    end if;
                end if;

                -- Commit next-state
                in_chirp <= in_chirp_v;

                -- ===================================
                -- 1) RAW: ADC code -> signed Q15.0
                -- ===================================
                r_i_raw <= conv12_to_q15(adc_a, is_tc_v);
                r_q_raw <= conv12_to_q15(adc_b, is_tc_v);

                -- ===================================
                -- 2) CORR: DC removal + gain (shift)
                -- ===================================
                r_i_corr <= arshift(r_i_raw - G_DC_I, G_GAIN_SHIFT);
                r_q_corr <= arshift(r_q_raw - G_DC_Q, G_GAIN_SHIFT);

                -- ===================================
                -- 3) OUT: register stage for output
                -- ===================================
                r_i_out <= r_i_corr;
                r_q_out <= r_q_corr;

                 -- ===================================
                -- 4) VALID/TLAST pipelining (2 cycles)
                --     Align control with data latency.
                -- ===================================
                -- vld_d0 is registered in the same clock; use sequential IF, not WHEN-ELSE
                if (tvalid_in = '1') and (in_chirp_v = '1') then
                    vld_d0 <= '1';
                else
                    vld_d0 <= '0';
                end if;

                vld_d1 <= vld_d0;
                vld_d2 <= vld_d1;

                tlast_d1 <= tlast_d0;
                tlast_d2 <= tlast_d1;

            end if;
        end if;
    end process;

    -- =======================
    -- Outputs
    -- =======================
    i_out    <= r_i_out;
    q_out    <= r_q_out;
    tvalid   <= vld_d2;
    tlast_ch <= tlast_d2 and vld_d2; -- tlast only when data is valid (aligned)

end architecture;
