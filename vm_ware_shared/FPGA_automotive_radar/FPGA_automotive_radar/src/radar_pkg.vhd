library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package radar_pkg is
  ----------------------------------------------------------------------------
  -- Clocking: single system clock derived from ADC
  ----------------------------------------------------------------------------
  constant F_CLK : natural := 65_000_000; -- Hz 65 MHz
  constant F_CLK_SYS : natural := F_CLK; -- system clock
  constant F_CLK_ADC : natural := F_CLK; -- AD9238 domain
  constant F_CLK_DAC : natural := F_CLK; -- AD974 marker output

  ----------------------------------------------------------------------------
  -- Chirp and frame parameters
  ----------------------------------------------------------------------------
  constant TCHIRP_US : natural := 33; -- chirp duration, microseconds
  constant TIDLE_US : natural := 0; -- idle between chirps
  constant CHIRP_TICKS : natural := 2145; -- ticks per chirp
  constant IDLE_TICKS : natural := (F_CLK * TIDLE_US) / 1_000_000;

  -- Number of ADC samples per chirp (assuming 1 sample per clk)
  constant N_SAMP : natural := CHIRP_TICKS; -- adjust to your effective Fs
  -- Range-FFT length (power-of-two >= N_SAMP)
  constant N_R : natural := 128;
  -- Number of chirps per frame (for Doppler processing)
  constant N_CHIRP : natural := 64;
  -- Doppler-FFT length
  constant N_D : natural := N_CHIRP;

  -- Range crop after range-FFT 
  constant RANGE_CROP_N : natural := 100;

  ----------------------------------------------------------------------------
  -- ADC / DAC interfaces
  ----------------------------------------------------------------------------
  constant ADC_W : natural := 12; -- AD9238, per channel
  constant IQ_W : natural := 16; -- sign-extended
  constant DAC_W : natural := 14; -- AD974

  ----------------------------------------------------------------------------
  -- Windows (Kaiser), coefficients stored in ROM as Q1.15
  ----------------------------------------------------------------------------
  constant KAISER_BETA_R : natural := 12; -- range window beta
  constant KAISER_BETA_D : natural := 5; -- doppler window beta

  constant RANGE_WIN_LEN : natural := N_R; -- samples per chirp actually used
  constant DOPPLER_WIN_LEN : natural := N_CHIRP; -- number of chirps per frame

  -- Q1.15 element and array types
  subtype q15u is unsigned(15 downto 0);
  type coef_arr_t is array (natural range <>) of q15u;

  constant RANGE_WIN_Q15 : coef_arr_t(0 to RANGE_WIN_LEN - 1) := (
    0 => to_unsigned(16#0002#, 16),
    1 => to_unsigned(16#0004#, 16),
    2 => to_unsigned(16#0008#, 16),
    3 => to_unsigned(16#000E#, 16),
    4 => to_unsigned(16#0017#, 16),
    5 => to_unsigned(16#0023#, 16),
    6 => to_unsigned(16#0033#, 16),
    7 => to_unsigned(16#0048#, 16),
    8 => to_unsigned(16#0064#, 16),
    9 => to_unsigned(16#0086#, 16),
    10 => to_unsigned(16#00B2#, 16),
    11 => to_unsigned(16#00E7#, 16),
    12 => to_unsigned(16#0129#, 16),
    13 => to_unsigned(16#0178#, 16),
    14 => to_unsigned(16#01D7#, 16),
    15 => to_unsigned(16#0247#, 16),
    16 => to_unsigned(16#02CB#, 16),
    17 => to_unsigned(16#0364#, 16),
    18 => to_unsigned(16#0416#, 16),
    19 => to_unsigned(16#04E2#, 16),
    20 => to_unsigned(16#05CB#, 16),
    21 => to_unsigned(16#06D3#, 16),
    22 => to_unsigned(16#07FC#, 16),
    23 => to_unsigned(16#0949#, 16),
    24 => to_unsigned(16#0ABC#, 16),
    25 => to_unsigned(16#0C56#, 16),
    26 => to_unsigned(16#0E19#, 16),
    27 => to_unsigned(16#1007#, 16),
    28 => to_unsigned(16#1222#, 16),
    29 => to_unsigned(16#1469#, 16),
    30 => to_unsigned(16#16DF#, 16),
    31 => to_unsigned(16#1982#, 16),
    32 => to_unsigned(16#1C54#, 16),
    33 => to_unsigned(16#1F53#, 16),
    34 => to_unsigned(16#227E#, 16),
    35 => to_unsigned(16#25D4#, 16),
    36 => to_unsigned(16#2954#, 16),
    37 => to_unsigned(16#2CF9#, 16),
    38 => to_unsigned(16#30C3#, 16),
    39 => to_unsigned(16#34AC#, 16),
    40 => to_unsigned(16#38B2#, 16),
    41 => to_unsigned(16#3CD0#, 16),
    42 => to_unsigned(16#4100#, 16),
    43 => to_unsigned(16#453E#, 16),
    44 => to_unsigned(16#4984#, 16),
    45 => to_unsigned(16#4DCD#, 16),
    46 => to_unsigned(16#5211#, 16),
    47 => to_unsigned(16#564A#, 16),
    48 => to_unsigned(16#5A72#, 16),
    49 => to_unsigned(16#5E81#, 16),
    50 => to_unsigned(16#6272#, 16),
    51 => to_unsigned(16#663D#, 16),
    52 => to_unsigned(16#69DC#, 16),
    53 => to_unsigned(16#6D47#, 16),
    54 => to_unsigned(16#707A#, 16),
    55 => to_unsigned(16#736D#, 16),
    56 => to_unsigned(16#761C#, 16),
    57 => to_unsigned(16#7880#, 16),
    58 => to_unsigned(16#7A97#, 16),
    59 => to_unsigned(16#7C5A#, 16),
    60 => to_unsigned(16#7DC8#, 16),
    61 => to_unsigned(16#7EDC#, 16),
    62 => to_unsigned(16#7F96#, 16),
    63 => to_unsigned(16#7FF3#, 16),
    64 => to_unsigned(16#7FF3#, 16),
    65 => to_unsigned(16#7F96#, 16),
    66 => to_unsigned(16#7EDC#, 16),
    67 => to_unsigned(16#7DC8#, 16),
    68 => to_unsigned(16#7C5A#, 16),
    69 => to_unsigned(16#7A97#, 16),
    70 => to_unsigned(16#7880#, 16),
    71 => to_unsigned(16#761C#, 16),
    72 => to_unsigned(16#736D#, 16),
    73 => to_unsigned(16#707A#, 16),
    74 => to_unsigned(16#6D47#, 16),
    75 => to_unsigned(16#69DC#, 16),
    76 => to_unsigned(16#663D#, 16),
    77 => to_unsigned(16#6272#, 16),
    78 => to_unsigned(16#5E81#, 16),
    79 => to_unsigned(16#5A72#, 16),
    80 => to_unsigned(16#564A#, 16),
    81 => to_unsigned(16#5211#, 16),
    82 => to_unsigned(16#4DCD#, 16),
    83 => to_unsigned(16#4984#, 16),
    84 => to_unsigned(16#453E#, 16),
    85 => to_unsigned(16#4100#, 16),
    86 => to_unsigned(16#3CD0#, 16),
    87 => to_unsigned(16#38B2#, 16),
    88 => to_unsigned(16#34AC#, 16),
    89 => to_unsigned(16#30C3#, 16),
    90 => to_unsigned(16#2CF9#, 16),
    91 => to_unsigned(16#2954#, 16),
    92 => to_unsigned(16#25D4#, 16),
    93 => to_unsigned(16#227E#, 16),
    94 => to_unsigned(16#1F53#, 16),
    95 => to_unsigned(16#1C54#, 16),
    96 => to_unsigned(16#1982#, 16),
    97 => to_unsigned(16#16DF#, 16),
    98 => to_unsigned(16#1469#, 16),
    99 => to_unsigned(16#1222#, 16),
    100 => to_unsigned(16#1007#, 16),
    101 => to_unsigned(16#0E19#, 16),
    102 => to_unsigned(16#0C56#, 16),
    103 => to_unsigned(16#0ABC#, 16),
    104 => to_unsigned(16#0949#, 16),
    105 => to_unsigned(16#07FC#, 16),
    106 => to_unsigned(16#06D3#, 16),
    107 => to_unsigned(16#05CB#, 16),
    108 => to_unsigned(16#04E2#, 16),
    109 => to_unsigned(16#0416#, 16),
    110 => to_unsigned(16#0364#, 16),
    111 => to_unsigned(16#02CB#, 16),
    112 => to_unsigned(16#0247#, 16),
    113 => to_unsigned(16#01D7#, 16),
    114 => to_unsigned(16#0178#, 16),
    115 => to_unsigned(16#0129#, 16),
    116 => to_unsigned(16#00E7#, 16),
    117 => to_unsigned(16#00B2#, 16),
    118 => to_unsigned(16#0086#, 16),
    119 => to_unsigned(16#0064#, 16),
    120 => to_unsigned(16#0048#, 16),
    121 => to_unsigned(16#0033#, 16),
    122 => to_unsigned(16#0023#, 16),
    123 => to_unsigned(16#0017#, 16),
    124 => to_unsigned(16#000E#, 16),
    125 => to_unsigned(16#0008#, 16),
    126 => to_unsigned(16#0004#, 16),
    127 => to_unsigned(16#0002#, 16)
  );

  constant DOPPLER_WIN_Q15 : coef_arr_t(0 to DOPPLER_WIN_LEN - 1) := (
    0 => to_unsigned(16#0002#, 16),
    1 => to_unsigned(16#0008#, 16),
    2 => to_unsigned(16#0017#, 16),
    3 => to_unsigned(16#0034#, 16),
    4 => to_unsigned(16#0066#, 16),
    5 => to_unsigned(16#00B6#, 16),
    6 => to_unsigned(16#0130#, 16),
    7 => to_unsigned(16#01E2#, 16),
    8 => to_unsigned(16#02DD#, 16),
    9 => to_unsigned(16#0432#, 16),
    10 => to_unsigned(16#05F3#, 16),
    11 => to_unsigned(16#0834#, 16),
    12 => to_unsigned(16#0B07#, 16),
    13 => to_unsigned(16#0E7B#, 16),
    14 => to_unsigned(16#129F#, 16),
    15 => to_unsigned(16#177B#, 16),
    16 => to_unsigned(16#1D12#, 16),
    17 => to_unsigned(16#2360#, 16),
    18 => to_unsigned(16#2A5B#, 16),
    19 => to_unsigned(16#31EE#, 16),
    20 => to_unsigned(16#39FE#, 16),
    21 => to_unsigned(16#4269#, 16),
    22 => to_unsigned(16#4B03#, 16),
    23 => to_unsigned(16#539D#, 16),
    24 => to_unsigned(16#5C01#, 16),
    25 => to_unsigned(16#63F8#, 16),
    26 => to_unsigned(16#6B4C#, 16),
    27 => to_unsigned(16#71C6#, 16),
    28 => to_unsigned(16#7735#, 16),
    29 => to_unsigned(16#7B71#, 16),
    30 => to_unsigned(16#7E57#, 16),
    31 => to_unsigned(16#7FD0#, 16),
    32 => to_unsigned(16#7FD0#, 16),
    33 => to_unsigned(16#7E57#, 16),
    34 => to_unsigned(16#7B71#, 16),
    35 => to_unsigned(16#7735#, 16),
    36 => to_unsigned(16#71C6#, 16),
    37 => to_unsigned(16#6B4C#, 16),
    38 => to_unsigned(16#63F8#, 16),
    39 => to_unsigned(16#5C01#, 16),
    40 => to_unsigned(16#539D#, 16),
    41 => to_unsigned(16#4B03#, 16),
    42 => to_unsigned(16#4269#, 16),
    43 => to_unsigned(16#39FE#, 16),
    44 => to_unsigned(16#31EE#, 16),
    45 => to_unsigned(16#2A5B#, 16),
    46 => to_unsigned(16#2360#, 16),
    47 => to_unsigned(16#1D12#, 16),
    48 => to_unsigned(16#177B#, 16),
    49 => to_unsigned(16#129F#, 16),
    50 => to_unsigned(16#0E7B#, 16),
    51 => to_unsigned(16#0B07#, 16),
    52 => to_unsigned(16#0834#, 16),
    53 => to_unsigned(16#05F3#, 16),
    54 => to_unsigned(16#0432#, 16),
    55 => to_unsigned(16#02DD#, 16),
    56 => to_unsigned(16#01E2#, 16),
    57 => to_unsigned(16#0130#, 16),
    58 => to_unsigned(16#00B6#, 16),
    59 => to_unsigned(16#0066#, 16),
    60 => to_unsigned(16#0034#, 16),
    61 => to_unsigned(16#0017#, 16),
    62 => to_unsigned(16#0008#, 16),
    63 => to_unsigned(16#0002#, 16)
  );

  ----------------------------------------------------------------------------
  -- FFT / Magnitude
  ----------------------------------------------------------------------------
  constant FFT_W : natural := 18; -- width of Re/Im after FFT (margin)
  constant POW_W : natural := 32; -- |S|^2 width

  ----------------------------------------------------------------------------
  -- CFAR (GOCA-CA) parameters
  ----------------------------------------------------------------------------
  constant CFAR_Tr : natural := 6; -- range training cells per side
  constant CFAR_Td : natural := 6; -- doppler training cells per side
  constant CFAR_Gr : natural := 20; -- range guard cells per side
  constant CFAR_Gd : natural := 20; -- doppler guard cells per side

  subtype q8_16 is unsigned(23 downto 0);
  constant CFAR_ALPHA_Q816 : q8_16 := to_unsigned(16#0100_000#, 24);

  ----------------------------------------------------------------------------
  -- UART (TX only; divider used to create baud enable)
  ----------------------------------------------------------------------------
  constant UART_BAUD : natural := 921_600;
  constant UART_DIVIDER : natural := (F_CLK + UART_BAUD/2) / UART_BAUD;

  ----------------------------------------------------------------------------
  -- Payload protocol (header + objects)
  ----------------------------------------------------------------------------
  subtype u8 is unsigned(7 downto 0);
  subtype s8 is signed(7 downto 0);
  subtype u16 is unsigned(15 downto 0);
  subtype s16 is signed(15 downto 0);
  subtype u24 is unsigned(23 downto 0);
  subtype u32 is unsigned(31 downto 0);
  subtype s32 is signed(31 downto 0);

  -- Header:
  -- t_us:u32, n:u8 (0..7), seq:u8, res:u16(0)
  type header_t is record
    t_us : u32;
    n : u8;
    seq : u8;
    res : u16;
  end record;

  -- Object: R_cm:u16, V_cms:s16, Peak:u16, BlobSize:u16
  type obj_t is record
    R_cm : u16;
    V_cms : s16;
    Peak_u16 : u16;
    BlobSize : u16;
  end record;

  constant OBJ_MAX : natural := 8;
  type obj_vec_t is array (natural range <>) of obj_t;

  ----------------------------------------------------------------------------
  -- Lightweight stream records
  ----------------------------------------------------------------------------
  type iq_t is record
    i : signed(IQ_W - 1 downto 0);
    q : signed(IQ_W - 1 downto 0);
    tvalid : std_logic;
    tlast : std_logic; -- end of chirp / line
  end record;

  type cplx_fft_t is record
    re : signed(FFT_W - 1 downto 0);
    im : signed(FFT_W - 1 downto 0);
    tvalid : std_logic;
    tlast : std_logic;
  end record;

  type pow_t is record
    pwr : unsigned(POW_W - 1 downto 0);
    tvalid : std_logic;
    tlast : std_logic;
  end record;

  ----------------------------------------------------------------------------
  -- DAC marker levels
  ----------------------------------------------------------------------------
  constant DAC_MARK_LOW : signed(DAC_W - 1 downto 0) := to_signed(0, DAC_W);
  constant DAC_MARK_HIGH : signed(DAC_W - 1 downto 0) := to_signed(2 ** (DAC_W) - 1, DAC_W);

  ----------------------------------------------------------------------------
  -- Utilities
  ----------------------------------------------------------------------------
  function clamp_u16(x : integer) return u16;
  function clamp_s16(x : integer) return s16;
  function to_u32(x : integer) return u32;
  function to_s32(x : integer) return s32;
  function baud_divider(f_clk : natural; baud : natural) return natural;
  function pack_u16(hi, lo : u8) return u16; -- pack two bytes into u16
  function pack_u32(b3, b2, b1, b0 : u8) return u32; -- pack four bytes into u32

end package;

package body radar_pkg is

  -- Clamp integer into 0..65535 and return as u16
  function clamp_u16(x : integer) return u16 is
    variable v : integer := x;
  begin
    if v < 0 then
      v := 0;
    elsif v > 65535 then
      v := 65535;
    end if;
    return to_unsigned(v, 16);
  end;

  -- Clamp integer into -32768..32767 and return as s16
  function clamp_s16(x : integer) return s16 is
    variable v : integer := x;
  begin
    if v <- 32768 then
      v := -32768;
    elsif v > 32767 then
      v := 32767;
    end if;
    return to_signed(v, 16);
  end;

  -- Convert non-negative integer to u32 (negative maps to 0)
  function to_u32(x : integer) return u32 is
  begin
    if x < 0 then
      return (others => '0');
    else
      return to_unsigned(x, 32);
    end if;
  end;

  -- Convert integer to s32
  function to_s32(x : integer) return s32 is
  begin
    return to_signed(x, 32);
  end;

  -- Integer divider for baud-rate enable generation
  function baud_divider(f_clk : natural; baud : natural) return natural is
  begin
    if baud = 0 then
      return 1;
    else
      return (f_clk + baud/2) / baud;
    end if;
  end;

  -- Pack two u8 into u16: {hi,lo}
  function pack_u16(hi, lo : u8) return u16 is
  begin
    return hi & lo; -- result is unsigned(15 downto 0)
  end;

  function pack_u32(b3, b2, b1, b0 : u8) return u32 is
  begin
    return b3 & b2 & b1 & b0;
  end;

end package body;