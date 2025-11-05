-- =========================================================================
-- win_mul_q15.vhd
-- I/Q window multiplier using Q1.15 coefficients from work.radar_pkg.
-- * Multiplies incoming signed Q15.0 samples by Q1.15 window coefficients.
-- * Coeffs are read from RANGE_WIN_Q15 (default) or DOPPLER_WIN_Q15.
-- * 1-cycle latency;
-- =========================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.radar_pkg.all;

entity win_mul_q15 is
    generic (
        -- 0 = use RANGE_WIN_Q15 / RANGE_WIN_LEN
        -- 1 = use DOPPLER_WIN_Q15 / DOPPLER_WIN_LEN
        G_WIN_SEL : integer := 0
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;

        -- Input stream (I/Q signed Q15.0)
        i_in : in signed(IQ_W - 1 downto 0);
        q_in : in signed(IQ_W - 1 downto 0);
        tvalid_in : in std_logic;
        tlast_in : in std_logic;

        -- Output stream (windowed)
        i_out : out signed(IQ_W - 1 downto 0);
        q_out : out signed(IQ_W - 1 downto 0);
        tvalid_out : out std_logic;
        tlast_out : out std_logic
    );
end entity;

architecture rtl of win_mul_q15 is
    -- -----------------------------
    -- Local helpers
    -- -----------------------------
    -- Symmetric rounding before arithmetic right shift by 'fb' fractional bits.
    function round_shift_sym(x : signed; fb : natural) return signed is
        variable res : signed(x'range) := x;
        variable bias : signed(x'range);
    begin
        -- bias = +2^(fb-1) for x>=0;  -2^(fb-1) for x<0
        bias := (others => '0');
        bias(bias'low + fb - 1) := '1';
        if x(x'high) = '1' then
            res := x - bias;
        else
            res := x + bias;
        end if;
        return shift_right(res, integer(fb)); -- arithmetic for SIGNED
    end;

    -- Saturating resize to N bits (signed)
    -- Saturating resize to N bits (signed) Ч VHDL-93 friendly
    function sat_sresize(x : signed; N : natural) return signed is
        variable y : signed(x'range) := x;
        variable ys : signed(N - 1 downto 0);
        variable xmax : signed(N - 1 downto 0);
        variable xmin : signed(N - 1 downto 0);
    begin
        -- xmax = +2^(N-1)-1 = 0 & (N-1 ones)
        xmax := (others => '1');
        xmax(N - 1) := '0';

        -- xmin = -2^(N-1)   = 1 & (N-1 zeros)
        xmin := (others => '0');
        xmin(N - 1) := '1';

        if (y > resize(xmax, y'length)) then
            ys := xmax;
        elsif (y < resize(xmin, y'length)) then
            ys := xmin;
        else
            ys := resize(y, N);
        end if;
        return ys;
    end;

    -- Read window coefficient by index depending on selection
    function get_win_coef(sel : integer; idx : natural) return q15u is
    begin
        if sel = 0 then
            return RANGE_WIN_Q15(idx mod RANGE_WIN_LEN);
        else
            return DOPPLER_WIN_Q15(idx mod DOPPLER_WIN_LEN);
        end if;
    end;

    -- Window length for modulo increment
    function get_win_len(sel : integer) return natural is
    begin
        if sel = 0 then
            return RANGE_WIN_LEN;
        else
            return DOPPLER_WIN_LEN;
        end if;
    end;

    constant FBITS : natural := 15; -- Q1.15 fractional bits

    -- Address counter for coefficient ROM
    signal win_idx : natural range 0 to integer'high := 0;

    -- Pipeline regs
    signal vld_d0, vld_d1 : std_logic := '0';
    signal last_d0, last_d1 : std_logic := '0';

    -- Mult results (widened)
    constant PW : natural := IQ_W + 16; -- product width (signed * unsigned)
    signal mult_i : signed(PW - 1 downto 0);
    signal mult_q : signed(PW - 1 downto 0);

    -- Rounded/shifted
    signal rsh_i : signed(PW - 1 downto 0);
    signal rsh_q : signed(PW - 1 downto 0);

    -- Output regs
    signal i_o, q_o : signed(IQ_W - 1 downto 0) := (others => '0');
begin

    -- =====================================
    -- Coefficient address control
    -- =====================================
    p_addr : process (clk)
        variable L : natural;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                win_idx <= 0;
            else
                L := get_win_len(G_WIN_SEL);
                if tvalid_in = '1' then
                    -- Use current idx for this sample, then advance
                    if tlast_in = '1' then
                        -- Reset after the last valid sample of the block (chirp, line, etc.)
                        win_idx <= 0;
                    else
                        if win_idx + 1 >= L then
                            win_idx <= 0;
                        else
                            win_idx <= win_idx + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =====================================
    -- Datapath: multiply -> round/shift -> saturate
    -- 1) Multiply (signed Q15.0) * (unsigned Q1.15) => signed PW bits
    -- =====================================
	p_mul : process(clk)
	  constant C_W : natural := 16;  -- Q1.15 width
	  variable coef_u : q15u;                 -- <Ч тип из radar_pkg
	  variable coef_s : signed(C_W-1 downto 0);
	begin
	  if rising_edge(clk) then
	    if rst_n = '0' then
	      mult_i <= (others => '0');
	      mult_q <= (others => '0');
	      vld_d0 <= '0';
	      last_d0 <= '0';
	    else
	      coef_u := get_win_coef(G_WIN_SEL, win_idx);
	      coef_s := signed(resize(coef_u, C_W));  -- cast Q1.15 to signed(15 downto 0)
	
	      -- product width = IQ_W + C_W = PW
	      mult_i <= resize(i_in * coef_s, PW);
	      mult_q <= resize(q_in * coef_s, PW);
	
	      vld_d0  <= tvalid_in;
	      last_d0 <= tlast_in;
	    end if;
	  end if;
	end process;
	
    -- =====================================
    -- 2) Round (symmetric) + shift right by 15 frac bits
    -- =====================================
    p_rnd : process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                rsh_i <= (others => '0');
                rsh_q <= (others => '0');
                vld_d1 <= '0';
                last_d1 <= '0';
            else
                rsh_i <= round_shift_sym(mult_i, FBITS);
                rsh_q <= round_shift_sym(mult_q, FBITS);
                vld_d1 <= vld_d0;
                last_d1 <= last_d0;
            end if;
        end if;
    end process;

    -- =====================================
    -- 3) Saturate & register outputs
    -- =====================================
    p_out : process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                i_o <= (others => '0');
                q_o <= (others => '0');
            else
                i_o <= sat_sresize(rsh_i, IQ_W);
                q_o <= sat_sresize(rsh_q, IQ_W);
            end if;
        end if;
    end process;

    -- Drive outputs
    i_out <= i_o;
    q_out <= q_o;
    tvalid_out <= vld_d1;
    tlast_out <= last_d1;

end architecture;