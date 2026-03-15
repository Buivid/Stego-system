----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 14.03.2026 14:35:08
-- Design Name: 
-- Module Name: Koch_Zhao_block - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Koch_Zhao_block is
  generic(
        DATA_WIDTH: integer:=16;
        P: integer:=10;
        addr_coef1: integer:=45;
        addr_coef2: integer:=46
        );
  Port ( 
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;
        coeff_in: in signed(DATA_WIDTH-1 downto 0);
        coeff_adr: in unsigned(5 downto 0);
--        block_num: in unsigned(9 downto 0);
        coeff_in_valid: in std_logic;
        bit_in: in std_logic;
        bit_valid: in std_logic;
        coeff_out: out signed(DATA_WIDTH-1 downto 0);
        out_adr: out unsigned(5 downto 0);
        out_valid: out std_logic;
        ready: out std_logic
        );
end Koch_Zhao_block;

architecture Behavioral of Koch_Zhao_block is
--constant ADDR1: unsigned(5 downto 0) := to_unsigned(addr_coef1, 6);
--constant ADDR2: unsigned(5 downto 0) := to_unsigned(addr_coef2, 6);
constant BLOCK_SIZE: integer:= 64;

type state_t is(
    IDLE,
    PASS_THROUGH,
    COLLECT,
    ADJUST,
    OUTPUT_BUFFER
);
signal state: state_t:= IDLE;
signal next_state: state_t;
type coeff_array_t is array (0 to (addr_coef2 - addr_coef1)) of signed(DATA_WIDTH-1 downto 0);
--type addr_array_t is array (0 to BLOCK_SIZE-1) of unsigned(5 downto 0);
signal buffer_coeff: coeff_array_t;
--signal buffer_addr: addr_array_t;

signal wr_ptr: integer range 0 to BLOCK_SIZE:=0;
signal rd_ptr: integer range 0 to BLOCK_SIZE:=0;
signal collecting: std_logic:= '0';
signal outputting: std_logic:= '0';

signal k1_in: signed(15 downto 0);
signal k2_in: signed(15 downto 0);
signal adjust_valid: std_logic:='0';
signal k1_out: signed(15 downto 0);
signal k2_out:signed(15 downto 0);
signal adjust_out_valid: std_logic;

signal coef1_found: std_logic:='0';
signal coef2_found: std_logic:='0';

--signal coeff_out_i: signed(DATA_WIDTH-1 downto 0);
--signal out_adr_i: unsigned(5 downto 0);
--signal out_valid_i: std_logic;
--signal ready_i: std_logic:='1';

begin
u_adjust: entity work.Adjust_coeffs_block
    generic map(
        P => P
        )
    port map(
        clk => clk,
        rst => rst,
        k1_in => k1_in,
        k2_in => k2_in,
        input_valid => adjust_valid,
        embed_bit => bit_in,
        k1_out => k1_out,
        k2_out => k2_out,
        output_valid => adjust_out_valid
    );
    
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            state <= IDLE;
            wr_ptr <= 0;
            rd_ptr <= 0;
            collecting <= '0';
            outputting <= '0';
            coef1_found <= '0';
            coef2_found <= '0';
            adjust_valid <= '0';
            ready <= '1';
            out_valid <='0';
        else
            adjust_valid <= '0';
            out_valid <= '0';
            case state is
            when IDLE =>
                if start = '1' then
                    state <= PASS_THROUGH;
                    ready <= '1';
                end if;
            when PASS_THROUGH =>
                if coeff_in_valid = '1' then
                    if to_integer(coeff_adr) = addr_coef1 then
                        state <= COLLECT;
                        collecting <= '1';
                        coef1_found <= '1';
                        coef2_found <= '0';
                        wr_ptr <= 1;
                        buffer_coeff(0) <= coeff_in;
--                        ready <= '0';
                    else
                        coeff_out <= coeff_in;
                        out_adr <= coeff_adr;
                        out_valid <= '1';
                    end if;
                end if;
            when COLLECT =>
                if coeff_in_valid = '1' then
                    buffer_coeff(wr_ptr) <= coeff_in;
                    if to_integer(coeff_adr) = addr_coef1 then
                        null;
                    elsif to_integer(coeff_adr) = addr_coef2 then
                        coef2_found <= '1';
                        k1_in <= buffer_coeff(0);
                        k2_in <= coeff_in;
                        adjust_valid <= '1';
                        state <= ADJUST;
                        ready <= '0';
                    else
                        if wr_ptr < BLOCK_SIZE-1 then
                            wr_ptr <= wr_ptr + 1;
                        end if;
                    end if;
                 end if;
             when ADJUST => 
                if adjust_out_valid = '1' then
                    buffer_coeff(0) <= k1_out;
                    buffer_coeff(wr_ptr) <= k2_out;
                    rd_ptr <= 0;
                    outputting <= '1';
                    state <= OUTPUT_BUFFER;
                end if;
            when OUTPUT_BUFFER =>
                if rd_ptr <= wr_ptr then
                    coeff_out <= buffer_coeff(rd_ptr);
                    out_adr <= to_unsigned(addr_coef1+rd_ptr, 6);
                    out_valid <= '1';
                    rd_ptr <= rd_ptr + 1;
                else
                    state <= PASS_THROUGH;
                    outputting <= '0';
                    collecting <= '0';
                    coef1_found <= '0';
                    coef2_found <= '0';
                    wr_ptr <= 0;
                    rd_ptr <= 0;
                    ready <= '1';
                end if;
            end case;
        end if;
    end if;
end process;
--ready <= '1' when state = IDLE or state=PASS_THROUGH else '0';

end Behavioral;
