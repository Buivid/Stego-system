library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity extracter is
  generic (
        P : positive := 10);
  Port (
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;
        data_in: in std_logic_vector(31 downto 0);
        data_in_valid: in std_logic;
        data_in_last: in std_logic;
        data_in_ready: out std_logic;
        extr_bit: out std_logic;
        extr_bit_valid: out std_logic;
        done: out std_logic );
end extracter;

architecture Behavioral of extracter is
type coeff_array is array(0 to 63) of signed(15 downto 0);
signal coeff_buffer: coeff_array;
signal wr_ptr: integer range 0 to 63:=0;
type state_t is (IDLE, COLLECT, EXTRACT, OUTPUT);
signal state: state_t:= IDLE;

constant IDX1: integer := 45;
constant IDX2: integer := 46;

signal k1, k2: signed(15 downto 0);
signal extr_valid_in: std_logic := '0';
signal extr_valid_out: std_logic;

signal data_in_ready_reg: std_logic;
begin
--data_in_ready <= data_in_ready_reg;
process(clk)
variable abs_k1, abs_k2: unsigned(15 downto 0);
begin
    if rising_edge(clk)then
        if rst = '1' then
            state <= IDLE;
            wr_ptr <= 0;
            data_in_ready <= '0';
            extr_bit <= '0';
            extr_bit_valid <= '0';
            done <= '0';
        else
            case state is 
            when IDLE =>
                wr_ptr <= 0;
                data_in_ready <= '0';
                done <= '0';
                extr_bit_valid <= '0';
                if start = '1' then
                    state <= COLLECT;
                    data_in_ready <= '1';
                end if;
            when COLLECT =>
                if data_in_valid = '1' then --and data_in_ready_reg = '1' then
                    coeff_buffer(wr_ptr) <= signed(data_in(31 downto 16));
                    coeff_buffer(wr_ptr+1) <= signed(data_in(15 downto 0));
                    wr_ptr <= wr_ptr + 2; 
                    if data_in_last = '1' then
                        data_in_ready <= '0';
                        state <= EXTRACT;
                    end if;             
                end if;
            when EXTRACT =>
                abs_k1 := unsigned(abs(coeff_buffer(IDX1)));
                abs_k2 := unsigned(abs(coeff_buffer(IDX2)));
                if abs_k1 >= abs_k2 + P then
                    extr_bit <= '1';
                else
                    extr_bit <= '0';
                end if;
                extr_bit_valid <= '1';                   
                state <= OUTPUT;
            when OUTPUT =>
                done <= '1';   
                state <= IDLE;                 
            end case;
        end if;
    end if;
end process;

end Behavioral;
