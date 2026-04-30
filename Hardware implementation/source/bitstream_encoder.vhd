library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity bitstream_encoder is
  Port (
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;
        data_in: in std_logic_vector(31 downto 0);
        data_in_valid: in std_logic;
        data_in_last: in std_logic;
        data_in_ready: out std_logic;
        data_out: out std_logic_vector(31 downto 0);
        data_out_valid: out std_logic;
        data_out_last: out std_logic;
        data_out_ready: in std_logic;
        done: out std_logic;
        table_id: in std_logic_vector(1 downto 0);
        huff_val: in std_logic_vector(7 downto 0);
        huff_len: in integer range 0 to 15;
        huff_code: in std_logic_vector(15 downto 0);
        huff_valid: in std_logic);
end bitstream_encoder;

architecture Behavioral of bitstream_encoder is

type state_type is (IDLE, LOAD_COEFS, ENCODE_COEFS, OUTPUT_STREAM);
signal state: state_type:= IDLE;

type code_array is array(0 to 255) of std_logic_vector(15 downto 0);
type len_array is array(0 to 255) of integer range 0 to 15;
type huff_table_type is record
        huffcode: code_array;
        hufflen: len_array;
    end record;
type huff_tables_type is array(0 to 3) of huff_table_type;
signal huff_tables: huff_tables_type:=(others =>(
huffcode => (others => (others => '0')),
hufflen => (others => 0)));

signal bitstream_buffer: std_logic_vector(0 to 63):=(others => '0');
signal bit_pos: integer range 0 to 63:=0;
signal last_coef: std_logic :='0';
signal coef_cnt: integer range 0 to 64:=0;
signal coef_idx: integer range 0 to 1:= 0;
signal coefs: std_logic_vector(31 downto 0);
signal curr_coef: std_logic_vector(15 downto 0);
signal block_id: integer range 0 to 2:=0;
signal prev_Y_dc: signed(15 downto 0):=(others=>'0');
signal prev_Cb_dc: signed(15 downto 0):=(others=>'0');
signal prev_Cr_dc: signed(15 downto 0):=(others=>'0');

begin
process(clk)
variable current_table_id: integer range 0 to 3:= 0;
begin
    if rising_edge(clk)then
        if rst = '1' then
            huff_tables <= (others =>(
                huffcode => (others => (others => '0')),
                hufflen => (others => 0)));
        else
            if huff_valid = '1' then
                current_table_id := to_integer(unsigned(table_id));
                huff_tables(current_table_id).huffcode(to_integer(unsigned(huff_val))) <= huff_code;
                huff_tables(current_table_id).hufflen(to_integer(unsigned(huff_val))) <= huff_len;
            end if;
        end if;
    end if;
end process;

process(clk)
begin
    if rising_edge(clk)then
        if rst = '1' then
            state <= IDLE;
        else
            case state is
            when IDLE =>
                if start = '1' then
                    state <= LOAD_COEFS;
                end if;
            when LOAD_COEFS =>
                if data_in_valid = '1' then
                    state <= ENCODE_COEFS;
                end if;
            when ENCODE_COEFS =>
                if bit_pos > 31 or last_coef = '1' then
                    state <= OUTPUT_STREAM;
                else
                    state <= LOAD_COEFS;
                end if;
            when OUTPUT_STREAM =>
                if data_out_ready = '1' then
                    if last_coef = '1' then
                        state <= IDLE;
                    else
                        state <= LOAD_COEFS;
                    end if;
                end if;
            end case;
        end if;
    end if;
end process;

process(clk)
variable h_table_id : integer range 0 to 3;
variable h_len: integer range 0 to 15;
variable h_value: integer range 0 to 255;
variable h_code: std_logic_vector(15 downto 0);

variable diff: signed(15 downto 0):=(others=>'0');
variable h_data: unsigned(15 downto 0):=(others=>'0');
variable run_length: integer range 0 to 16:=0;
variable category: integer range 0 to 16:=0;

variable v_bit_pos: integer range 0 to 63:=0;
variable v_bitstream_buffer: std_logic_vector(0 to 63):=(others => '0');
variable abs_val: unsigned(15 downto 0);

begin
    if rising_edge(clk)then
        if rst = '1' then
            bitstream_buffer <= (others => '0');
            bit_pos <= 0;
            data_in_ready <= '0';
        else
            case state is
            when IDLE =>
                bitstream_buffer <= (others => '0');
                bit_pos <= 0;
                data_in_ready <= '1';
            when LOAD_COEFS =>
                if data_in_valid = '1' then
                    coefs <= data_in;
                    coef_cnt <= coef_cnt + 2;
                    data_in_ready <= '0';
                end if;
            when ENCODE_COEFS =>
                v_bitstream_buffer := bitstream_buffer;
                v_bit_pos := bit_pos;
                category:= 0;
    --            --написать для dc 
                if coef_cnt = 2 and coef_idx = 0 then
                    if block_id = 0 then
                        h_table_id := 0;
                        diff := signed(curr_coef) - prev_Y_dc;
                        prev_Y_dc <= signed(curr_coef);
                    else 
                        h_table_id := 2;
                        if block_id = 1 then
                            diff:= signed(curr_coef) - prev_Cb_dc;
                            prev_Cb_dc <= signed(curr_coef);
                        else
                            diff:= signed(curr_coef) - prev_Cr_dc;
                            prev_Cr_dc <= signed(curr_coef);
                        end if;
                    end if;
                    if signed(diff) < 0 then
                        abs_val := unsigned(-signed(diff));
                    else    
                        abs_val := unsigned(diff);
                    end if;
                    for i in 15 downto 0 loop
                        if abs_val(i) = '1' then
                            category:= i + 1;
                            exit;
                        end if;
                    end loop;
                    h_value:= category;
                    h_code := huff_tables(h_table_id).huffcode(h_value);
                    h_len := huff_tables(h_table_id).hufflen(h_value);
                
                    if signed(diff) < 0 then
                        h_data := unsigned(diff) + (2**category - 1);
                    else
                        h_data := unsigned(diff);
                    end if; 
                    for i in 0 to 15 loop
                        if i < h_len then
                            v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
                        end if;
                    end loop;
                    v_bit_pos := v_bit_pos + h_len;
                    
                    for i in 0 to 15 loop
                        if i < category then
                            v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
                        end if;
                    end loop;
                    v_bit_pos := v_bit_pos + category;
                    if h_table_id = 0 then
                        h_table_id:= 1;
                    else 
                        h_table_id:= 3;
                    end if;
                else
                    if signed(curr_coef) = 0 then
                        run_length:= run_length + 1;
                        if run_length = 16 then
                            h_value:= 240; --F0 --to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
                            h_code := huff_tables(h_table_id).huffcode(h_value);
                            h_len := huff_tables(h_table_id).hufflen(h_value);
    --                        v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len-1) := h_code(h_len-1 downto 0);
    --                        v_bit_pos := v_bit_pos + h_len;
                            for i in 0 to 15 loop
                                if i < h_len then
                                    v_bitstream_buffer(v_bit_pos+i) := h_code(h_len - 1 -i);
                                end if;
                            end loop;
                            v_bit_pos := v_bit_pos + h_len;
                            run_length:= 0;
                        end if;
                    else
                        if signed(curr_coef) < 0 then
                            abs_val := unsigned(-signed(curr_coef));
                        else
                            abs_val := unsigned(curr_coef);
                        end if;
                        for i in abs_val'range loop
                            if abs_val(i) = '1' then
                                category:= i + 1;
                                exit;
                            end if;
                        end loop;
                        h_value:= run_length*16 + category;--to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
                        h_code := huff_tables(h_table_id).huffcode(h_value);
                        h_len := huff_tables(h_table_id).hufflen(h_value);
                    
                        if signed(curr_coef) < 0 then
                            h_data := unsigned(curr_coef) + (2**category - 1);
                        else
                            h_data := unsigned(curr_coef);
                        end if;
    --                    v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len + category-1) := h_code(h_len-1 downto 0) & std_logic_vector(h_data(category-1 downto 0));
    --                    v_bit_pos := v_bit_pos + h_len + category;
                        for i in 0 to 15 loop
                            if i < h_len then
                                v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
                            end if;
                        end loop;
                        v_bit_pos := v_bit_pos + h_len;
                        
                        for i in 0 to 15 loop
                            if i < category then
                                v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
                            end if;
                        end loop;
                        v_bit_pos := v_bit_pos + category;
                        run_length := 0;                                        
                    end if;                            
                end if;
                bitstream_buffer <= v_bitstream_buffer;
                bit_pos <= v_bit_pos;  
            when OUTPUT_STREAM =>
                if data_out_ready = '1' then
                    data_out <= bitstream_buffer(0 to 31);
                    data_out_valid <= '1';
                    bitstream_buffer <= bitstream_buffer(32 to 63) & x"00000000";
                    bit_pos <= bit_pos - 32;
                end if;
            end case;
        end if;
    end if;
end process;

end Behavioral;
