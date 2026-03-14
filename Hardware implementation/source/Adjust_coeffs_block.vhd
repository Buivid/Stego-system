library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Adjust_coeffs_block is
  generic (
    P : positive := 10
  );
  port (
    clk: in  std_logic;
    rst: in  std_logic;
    k1_in: in  signed(15 downto 0);
    k2_in: in  signed(15 downto 0);
    input_valid: in  std_logic;
    embed_bit: in  std_logic;
    k1_out: out signed(15 downto 0);
    k2_out: out signed(15 downto 0);
    output_valid: out std_logic
  );
end entity Adjust_coeffs_block;


architecture behavior of Adjust_coeffs_block is
signal k1_reg: signed(15 downto 0);
signal k2_reg: signed(15 downto 0);
signal bit_reg: std_logic;
signal valid_reg: std_logic := '0';
signal abs_k1     : unsigned(15 downto 0);
signal abs_k2     : unsigned(15 downto 0);

begin
process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        k1_reg <= (others => '0');
        k2_reg <= (others => '0');
        bit_reg <= '0';
        valid_reg <= '0';
      else
        k1_reg <= k1_in;
        k2_reg <= k2_in;
        bit_reg <= embed_bit;
        valid_reg <= input_valid;
      end if;
    end if;
  end process;

  abs_k1 <= unsigned(abs(k1_reg));
  abs_k2 <= unsigned(abs(k2_reg));

  process(clk)
  variable new_big: signed(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        k1_out <= (others => '0');
        k2_out <= (others => '0');
        output_valid <= '0';
      elsif valid_reg = '1' then
        k1_out <= k1_reg;
        k2_out <= k2_reg;
        output_valid <= '1';
        if bit_reg = '1' then
          -- |k1| ? |k2| + P
          if abs_k1 >= abs_k2 + to_unsigned(P, 16) then
            null;
          else
            if k1_reg >= 0 then
              new_big := signed(abs_k2) + to_signed(P, 16);
            else
              new_big := - (signed(abs_k2) + to_signed(P, 16));
            end if;
            k1_out <= new_big;
          end if;
        else  -- bit = '0' -> |k2| ? |k1| + P
          if abs_k2 >= abs_k1 + to_unsigned(P, 16) then
            null;
          else
            if k2_reg >= 0 then
              new_big := signed(abs_k1) + to_signed(P, 16);
            else
              new_big := - (signed(abs_k1) + to_signed(P, 16));
            end if;
            k2_out <= new_big;
          end if;
        end if;
      else
        output_valid <= '0';
      end if;
    end if;
  end process;
end architecture behavior;