
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity embedder is
  Port ( 
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;
        emb_bit: in std_logic;
        data_in: in std_logic_vector(31 downto 0);
        data_in_valid: in std_logic;
        data_in_last: in std_logic;
        data_in_ready: out std_logic;
        data_out: out std_logic_vector(31 downto 0);
        data_out_valid: out std_logic;
        data_out_last: out std_logic;
        data_out_ready: in std_logic;
        done: out std_logic
        );
end embedder;

architecture Behavioral of embedder is
type coeff_array is array(0 to 63) of signed(15 downto 0);
signal coeff_buffer: coeff_array;
signal wr_ptr: integer range 0 to 63:=0;
signal rd_ptr: integer range 0 to 63:=0;

type state_t is (IDLE, COLLECT, EMBED, OUTPUT);
signal state: state_t:= IDLE;

constant IDX1: integer:= 45;
constant IDX2: integer:= 46;

signal k1_in, k2_in: signed(15 downto 0);
signal k1_out, k2_out: signed(15 downto 0);
signal adj_valid_in, adj_valid_out: std_logic;

signal last_reg: std_logic:= '0';
 
begin
adj_inst: entity work.Adjust_coeffs_block
port map(
        clk => clk,
        rst => rst,
        k1_in => k1_in,
        k2_in => k2_in,
        input_valid => adj_valid_in,
        embed_bit => emb_bit,
        k1_out => k1_out,
        k2_out => k2_out,
        output_valid => adj_valid_out);
        
process(clk)
begin
    if rising_edge(clk)then
        if rst = '1' then
            state <= IDLE;
            wr_ptr <= 0;
            rd_ptr <= 0;
            data_out_valid <= '0';
            data_out_last <= '0';
            data_in_ready <= '0';
            done <= '0';
            adj_valid_in <= '0';
       else
            data_out_valid <= '0';
            data_out_last <= '0';
            done <= '0';
            adj_valid_in <= '0';
            case state is
            when IDLE =>
                wr_ptr <= 0;
                rd_ptr <= 0;
                data_in_ready <= '0';
                if start = '1' then
                    state <= COLLECT;
                    data_in_ready <= '1';
                end if;
            when COLLECT =>
                if data_in_valid = '1' then -- and data_in_ready = '1'
                    coeff_buffer(wr_ptr) <= signed(data_in(31 downto 16));
                    coeff_buffer(wr_ptr + 1) <= signed(data_in(15 downto 0));
                    wr_ptr <= wr_ptr + 2;
                    if data_in_last = '1' then
                        data_in_ready <= '0';
                        state <= EMBED;
                    end if;
                end if;
            when EMBED =>
                k1_in <= coeff_buffer(IDX1);
                k2_in <= coeff_buffer(IDX2);
                adj_valid_in <= '1';
                if adj_valid_out = '1' then
                    coeff_buffer(IDX1) <= k1_out;
                    coeff_buffer(IDX2) <= k2_out;
                    rd_ptr <= 0;
                    state <= OUTPUT;
                end if;
            when OUTPUT =>
                if data_out_ready = '1' then
                    data_out <= std_logic_vector(coeff_buffer(rd_ptr)) & std_logic_vector(coeff_buffer(rd_ptr + 1));
                    data_out_valid <= '1';
                    if rd_ptr >= 61 then
                        data_out_last <= '1';
                        done <= '1';
                        state <= IDLE;
                    else
                        rd_ptr <= rd_ptr + 2;
                    end if;
                end if;
            end case;
       end if;
    end if;
end process;

end Behavioral;
